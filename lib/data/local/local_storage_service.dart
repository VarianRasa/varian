import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../artifacts/artifact_store_bundle.dart';
import '../artifacts/transient_artifact_hydrator.dart';
import 'durable/durable_project_store.dart';
import '../../domain/models/document.dart';
import '../../domain/models/ai_job.dart';
import '../../domain/models/node_payload.dart';
import '../../features/collaboration/domain/crdt_primitives.dart';
import '../../features/collaboration/domain/comment_notifications.dart';
import '../../features/drawing_paper/domain/services/drawing_paper_persistence.dart';
import '../../features/history/snapshot_manager.dart';
import '../../features/canvas/commands/command_replay.dart';
import '../../features/publishing/domain/published_snapshot.dart';
import '../../features/components/domain/component_library.dart';
import '../../features/canvas/domain/canvas_navigation.dart';
import '../../features/review/domain/review_workflow.dart';
import '../../features/ai/domain/semantic_index.dart';
import '../../features/ai/domain/ai_canvas_transaction.dart';
import '../../features/ai/domain/ai_governance.dart';
import '../../features/templates/domain/project_template.dart';
import '../../domain/models/workspace_governance.dart';
import '../../features/assets/domain/asset_library.dart';
import '../../features/governance/domain/plugin_registry.dart';

const _documentSizeLimit = 4 * 1024 * 1024;

bool _hasAssetLibraryControlCharacter(String value) =>
    value.codeUnits.any((code) => code < 0x20 || code == 0x7f);

int _utf8ByteLength(String value) => utf8.encode(value).length;

enum LocalSaveResult { full, degraded }

enum ProjectStatus { active, archived, trashed }

class LocalStorageException implements Exception {
  final String message;
  final Object cause;

  const LocalStorageException(this.message, this.cause);

  @override
  String toString() => message;
}

class LocalProjectMetadata {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? thumbnailPath;
  final bool isPinned;
  final ProjectStatus status;
  final DateTime? trashedAt;
  final String? collaborationRoomCode;
  final String? collaborationRole;
  final String? collaborationAccountId;
  final DateTime? collaborationRoomExpiresAt;
  final String? cloudOwnerId;
  final DateTime? cloudUpdatedAt;
  final int localMetadataRevision;
  final bool cloudMetadataSyncPending;
  final String? cloudAdoptionPendingAccountId;
  final bool cloudDeletionDetached;
  LocalProjectMetadata({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.thumbnailPath,
    this.isPinned = false,
    this.status = ProjectStatus.active,
    this.trashedAt,
    this.collaborationRoomCode,
    this.collaborationRole,
    this.collaborationAccountId,
    this.collaborationRoomExpiresAt,
    this.cloudOwnerId,
    this.cloudUpdatedAt,
    this.localMetadataRevision = 0,
    this.cloudMetadataSyncPending = false,
    this.cloudAdoptionPendingAccountId,
    this.cloudDeletionDetached = false,
  });

  bool get isCollaborationRoom =>
      collaborationRoomCode?.trim().isNotEmpty == true;

  LocalProjectMetadata copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? thumbnailPath,
    bool? isPinned,
    ProjectStatus? status,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    String? collaborationRoomCode,
    String? collaborationRole,
    String? collaborationAccountId,
    DateTime? collaborationRoomExpiresAt,
    bool clearCollaborationRoom = false,
    String? cloudOwnerId,
    bool clearCloudOwnerId = false,
    DateTime? cloudUpdatedAt,
    bool clearCloudUpdatedAt = false,
    int? localMetadataRevision,
    bool? cloudMetadataSyncPending,
    String? cloudAdoptionPendingAccountId,
    bool clearCloudAdoptionPendingAccountId = false,
    bool? cloudDeletionDetached,
  }) {
    return LocalProjectMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isPinned: isPinned ?? this.isPinned,
      status: status ?? this.status,
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      collaborationRoomCode: clearCollaborationRoom
          ? null
          : (collaborationRoomCode ?? this.collaborationRoomCode),
      collaborationRole: clearCollaborationRoom
          ? null
          : (collaborationRole ?? this.collaborationRole),
      collaborationAccountId: clearCollaborationRoom
          ? null
          : (collaborationAccountId ?? this.collaborationAccountId),
      collaborationRoomExpiresAt: clearCollaborationRoom
          ? null
          : (collaborationRoomExpiresAt ?? this.collaborationRoomExpiresAt),
      cloudOwnerId: clearCloudOwnerId
          ? null
          : (cloudOwnerId ?? this.cloudOwnerId),
      cloudUpdatedAt: clearCloudUpdatedAt
          ? null
          : (cloudUpdatedAt ?? this.cloudUpdatedAt),
      localMetadataRevision:
          localMetadataRevision ?? this.localMetadataRevision,
      cloudMetadataSyncPending:
          cloudMetadataSyncPending ?? this.cloudMetadataSyncPending,
      cloudAdoptionPendingAccountId: clearCloudAdoptionPendingAccountId
          ? null
          : (cloudAdoptionPendingAccountId ??
                this.cloudAdoptionPendingAccountId),
      cloudDeletionDetached:
          cloudDeletionDetached ?? this.cloudDeletionDetached,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'thumbnailPath': thumbnailPath,
    'isPinned': isPinned,
    'status': status.name,
    'trashedAt': trashedAt?.toIso8601String(),
    'collaborationRoomCode': collaborationRoomCode,
    'collaborationRole': collaborationRole,
    'collaborationAccountId': collaborationAccountId,
    'collaborationRoomExpiresAt': collaborationRoomExpiresAt?.toIso8601String(),
    'cloudOwnerId': cloudOwnerId,
    'cloudUpdatedAt': cloudUpdatedAt?.toIso8601String(),
    'localMetadataRevision': localMetadataRevision,
    'cloudMetadataSyncPending': cloudMetadataSyncPending,
    'cloudAdoptionPendingAccountId': cloudAdoptionPendingAccountId,
    'cloudDeletionDetached': cloudDeletionDetached,
  };

  factory LocalProjectMetadata.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String?;
    final status = ProjectStatus.values.firstWhere(
      (value) => value.name == rawStatus,
      orElse: () => ProjectStatus.active,
    );
    return LocalProjectMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      thumbnailPath: json['thumbnailPath'] as String?,
      isPinned: json['isPinned'] as bool? ?? false,
      status: status,
      trashedAt: json['trashedAt'] == null
          ? null
          : DateTime.tryParse(json['trashedAt'] as String),
      collaborationRoomCode: json['collaborationRoomCode'] as String?,
      collaborationRole: json['collaborationRole'] as String?,
      collaborationAccountId: json['collaborationAccountId'] as String?,
      collaborationRoomExpiresAt: json['collaborationRoomExpiresAt'] == null
          ? null
          : DateTime.tryParse(json['collaborationRoomExpiresAt'] as String),
      cloudOwnerId: json['cloudOwnerId'] as String?,
      cloudUpdatedAt: json['cloudUpdatedAt'] == null
          ? null
          : DateTime.tryParse(json['cloudUpdatedAt'] as String),
      localMetadataRevision:
          (json['localMetadataRevision'] as num?)?.toInt() ?? 0,
      cloudMetadataSyncPending:
          json['cloudMetadataSyncPending'] as bool? ?? false,
      cloudAdoptionPendingAccountId:
          json['cloudAdoptionPendingAccountId'] as String?,
      cloudDeletionDetached: json['cloudDeletionDetached'] as bool? ?? false,
    );
  }
}

class LocalStorageService {
  static const String _projectsKey = 'ccs_local_projects_list';
  static const String _cloudProjectDeletionTombstonesPrefix =
      'ccs_cloud_project_deletions_';
  static const String _docPrefix = 'ccs_doc_';
  static const String _journalPrefix = 'ccs_journal_';
  static const String _collaborationQueuePrefix = 'ccs_collab_queue_';
  static const String _collaborationQueueGenerationSuffix = '_generation';
  static const String _versionsPrefix = 'ccs_versions_';
  static const String _autoCheckpointsPrefix = 'ccs_auto_checkpoints_';
  static const String _aiJobsPrefix = 'ccs_ai_jobs_';
  static const String _publishedSnapshotPrefix = 'ccs_published_snapshot_';
  static const String _componentLibraryPrefix = 'ccs_component_library_';
  static const String _projectTemplatesPrefix = 'ccs_project_templates_';
  static const String _assetLibraryPrefix = 'ccs_asset_library_';
  static const String _assetLibraryDeletionPrefix =
      'ccs_asset_library_deletions_';
  static const String _assetLibraryFolderDeletionPrefix =
      'ccs_asset_library_folder_deletions_';
  static const String _assetLibraryFolderUpsertPrefix =
      'ccs_asset_library_folder_upserts_';
  static const String _assetLibraryFoldersPrefix = 'ccs_asset_library_folders_';
  static const String _assetLibraryProviderCachePrefix =
      'ccs_asset_library_provider_cache_';
  static const int _assetLibraryCacheMaxBytes = 4 * 1024 * 1024;
  static const int _assetLibraryDeletionCacheMaxBytes = 256 * 1024;
  static const int _assetLibraryFolderCacheMaxBytes = 128 * 1024;
  static const String _canvasNavigationPrefix = 'ccs_canvas_navigation_';
  static const String _reviewWorkflowPrefix = 'ccs_review_workflow_';
  static const String _semanticIndexPrefix = 'ccs_semantic_index_';
  static const String _aiCanvasTransactionsPrefix =
      'ccs_ai_canvas_transactions_';
  static const String _commentNotificationsPrefix =
      'ccs_comment_notifications_';
  static const String _commentNotificationPreferencesPrefix =
      'ccs_comment_notification_preferences_';
  static const String _accessibilitySettingsKey = 'ccs_accessibility_settings';
  static const String _workspacePolicyKey = 'ccs_workspace_policy';
  static const String _pluginRegistryKey = 'ccs_plugin_registry';
  static const int maxVersions = 20;
  final DrawingPaperPersistence _drawingPaperPersistence;
  final TransientArtifactHydrator _artifactHydrator;
  final DurableProjectStore? _durableProjectStore;
  static Future<void>? _writeQueue;

  LocalStorageService({
    DrawingPaperPersistence? drawingPaperPersistence,
    TransientArtifactHydrator? artifactHydrator,
    ArtifactStoreBundle? artifactStoreBundle,
    this._durableProjectStore,
  }) : _drawingPaperPersistence =
           drawingPaperPersistence ?? DrawingPaperPersistence(),
       _artifactHydrator =
           artifactHydrator ??
           TransientArtifactHydrator(
             imageArtifactStore: artifactStoreBundle?.imageArtifactStore,
             fileArtifactStore: artifactStoreBundle?.fileArtifactStore,
             mediaArtifactStore: artifactStoreBundle?.mediaArtifactStore,
             videoArtifactStore: artifactStoreBundle?.videoArtifactStore,
             model3DArtifactStore: artifactStoreBundle?.model3DArtifactStore,
           );

  void setStorageByteReader(TransientStorageByteReader? reader) {
    _artifactHydrator.setStorageByteReader(reader);
  }

  Future<void> _enqueue(Future<void> Function() operation) async {
    final previous = _writeQueue ?? Future<void>.value();
    final next = previous.then((_) => operation());
    final queued = next.catchError((_) {});
    _writeQueue = queued;
    try {
      await next;
    } finally {
      if (identical(_writeQueue, queued)) {
        _writeQueue = null;
      }
    }
  }

  Future<void> _waitForWrites() async {
    final pending = _writeQueue;
    if (pending != null) await pending;
  }

  Future<void> _writeProjects(
    SharedPreferences prefs,
    List<LocalProjectMetadata> projects, {
    bool advanceLocalMetadataRevision = true,
  }) async {
    var projectsToWrite = projects;
    if (advanceLocalMetadataRevision) {
      final existingById = {
        for (final project in await _getProjectsUnlocked()) project.id: project,
      };
      projectsToWrite = projects
          .map((project) {
            final existing = existingById[project.id];
            if (existing == null) {
              return project.copyWith(
                localMetadataRevision: project.localMetadataRevision + 1,
              );
            }
            final existingContent = Map<String, dynamic>.from(existing.toJson())
              ..remove('localMetadataRevision');
            final nextContent = Map<String, dynamic>.from(project.toJson())
              ..remove('localMetadataRevision');
            final changed =
                jsonEncode(existingContent) != jsonEncode(nextContent);
            return project.copyWith(
              localMetadataRevision: changed
                  ? existing.localMetadataRevision + 1
                  : existing.localMetadataRevision,
            );
          })
          .toList(growable: false);
    }
    await _setString(
      prefs,
      _projectsKey,
      jsonEncode(projectsToWrite.map((project) => project.toJson()).toList()),
      message: 'Project metadata tidak dapat disimpan.',
    );
  }

  Future<void> _setString(
    SharedPreferences prefs,
    String key,
    String value, {
    required String message,
  }) async {
    try {
      final saved = await prefs.setString(key, value);
      if (!saved) {
        throw LocalStorageException(
          message,
          StateError('write returned false'),
        );
      }
    } catch (error) {
      if (error is LocalStorageException) rethrow;
      throw LocalStorageException(message, error);
    }
  }

  Future<void> _remove(SharedPreferences prefs, String key) async {
    try {
      final removed = await prefs.remove(key);
      if (!removed) {
        throw LocalStorageException(
          'Data lokal tidak dapat dihapus.',
          StateError('remove returned false'),
        );
      }
    } catch (error) {
      if (error is LocalStorageException) rethrow;
      throw LocalStorageException('Data lokal tidak dapat dihapus.', error);
    }
  }

  Future<List<LocalProjectMetadata>> getProjects() async {
    await _waitForWrites();
    return _getProjectsUnlocked();
  }

  Future<List<LocalProjectMetadata>> _getProjectsUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_projectsKey);
    if (jsonStr == null) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final projects = <LocalProjectMetadata>[];
      for (final item in list) {
        try {
          projects.add(
            LocalProjectMetadata.fromJson(item as Map<String, dynamic>),
          );
        } catch (_) {
          // Keep recoverable project records when one legacy record is corrupt.
        }
      }
      return projects;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProjectMetadata(
    LocalProjectMetadata meta, {
    bool Function()? shouldWrite,
  }) async {
    await _enqueue(() async {
      if (shouldWrite != null && !shouldWrite()) return;
      final prefs = await SharedPreferences.getInstance();
      if (shouldWrite != null && !shouldWrite()) return;
      final projects = await _getProjectsUnlocked();
      final index = projects.indexWhere((project) => project.id == meta.id);
      if (index >= 0) {
        projects[index] = meta;
      } else {
        projects.insert(0, meta);
      }
      if (shouldWrite != null && !shouldWrite()) return;
      await _writeProjects(prefs, projects);
    });
  }

  Future<bool> saveProjectMetadataIfRevisionUnchanged(
    LocalProjectMetadata meta, {
    required int expectedRevision,
    bool Function()? shouldWrite,
  }) async {
    var saved = false;
    await _enqueue(() async {
      if (shouldWrite != null && !shouldWrite()) return;
      final prefs = await SharedPreferences.getInstance();
      if (shouldWrite != null && !shouldWrite()) return;
      final projects = await _getProjectsUnlocked();
      final index = projects.indexWhere((project) => project.id == meta.id);
      if (index < 0 ||
          projects[index].localMetadataRevision != expectedRevision ||
          (shouldWrite != null && !shouldWrite())) {
        return;
      }
      projects[index] = meta;
      await _writeProjects(prefs, projects);
      saved = true;
    });
    return saved;
  }

  Future<bool> saveProjectMetadataIfAbsent(
    LocalProjectMetadata meta, {
    bool Function()? shouldWrite,
  }) async {
    var saved = false;
    await _enqueue(() async {
      if (shouldWrite != null && !shouldWrite()) return;
      final prefs = await SharedPreferences.getInstance();
      if (shouldWrite != null && !shouldWrite()) return;
      final projects = await _getProjectsUnlocked();
      if (projects.any((project) => project.id == meta.id) ||
          (shouldWrite != null && !shouldWrite())) {
        return;
      }
      projects.insert(0, meta);
      await _writeProjects(prefs, projects);
      saved = true;
    });
    return saved;
  }

  Future<void> _touchProjectMetadata(
    SharedPreferences prefs,
    CanvasDocument doc,
    bool Function()? shouldWrite,
  ) async {
    if (shouldWrite != null && !shouldWrite()) return;
    final jsonStr = prefs.getString(_projectsKey);
    if (jsonStr == null) return;
    final projects = <LocalProjectMetadata>[];
    try {
      for (final item in jsonDecode(jsonStr) as List<dynamic>) {
        try {
          projects.add(
            LocalProjectMetadata.fromJson(item as Map<String, dynamic>),
          );
        } catch (_) {
          // Keep recoverable project records when one legacy record is corrupt.
        }
      }
    } catch (_) {
      return;
    }
    final index = projects.indexWhere((project) => project.id == doc.projectId);
    if (index < 0) return;
    projects[index] = projects[index].copyWith(updatedAt: doc.updatedAt);
    if (shouldWrite != null && !shouldWrite()) return;
    await _writeProjects(prefs, projects);
  }

  Future<LocalSaveResult> saveDocument(
    CanvasDocument doc, {
    bool Function()? shouldWriteMetadata,
  }) async {
    LocalSaveResult? result;
    Object? failure;
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      CanvasDocument prepared = doc;
      try {
        prepared = await _drawingPaperPersistence.prepareDocument(doc);
      } catch (_) {
        // The editable document remains usable when a derived preview cannot
        // be written. It will be retried by the next save.
      }
      final encoded = jsonEncode(prepared.toPersistenceJson());
      try {
        await _setString(
          prefs,
          '$_journalPrefix${doc.projectId}',
          jsonEncode({
            'version': 1,
            'writtenAt': DateTime.now().toUtc().toIso8601String(),
            'document': prepared.toPersistenceJson(),
          }),
          message: 'Dokumen recovery tidak dapat disiapkan.',
        );
      } catch (_) {
        // The primary save still has a chance to succeed when the storage
        // budget cannot accommodate a second copy of the document.
      }
      try {
        await _setString(
          prefs,
          '$_docPrefix${doc.projectId}',
          encoded,
          message: encoded.length > _documentSizeLimit
              ? 'Dokumen terlalu besar untuk penyimpanan browser.'
              : 'Dokumen lokal tidak dapat disimpan.',
        );
        await prefs.remove('$_journalPrefix${doc.projectId}');
        result = LocalSaveResult.full;
      } catch (error) {
        failure = error;
        if (!kIsWeb) rethrow;
        final degraded = _degradedDocument(prepared);
        try {
          await _setString(
            prefs,
            '$_docPrefix${doc.projectId}',
            jsonEncode(degraded.toPersistenceJson()),
            message: 'Penyimpanan lokal browser tidak tersedia.',
          );
          result = LocalSaveResult.degraded;
        } catch (_) {
          rethrow;
        }
      }
      await _touchProjectMetadata(prefs, prepared, shouldWriteMetadata);
    });
    if (result != null) return result!;
    throw LocalStorageException(
      'Dokumen lokal tidak dapat disimpan.',
      failure ?? StateError('unknown local save failure'),
    );
  }

  Future<void> clearAccountScopedCollaborationMetadataAtomically({
    String? expectedAccountId,
    bool Function()? shouldClear,
  }) async {
    await _enqueue(() async {
      if (shouldClear != null && !shouldClear()) return;
      final prefs = await SharedPreferences.getInstance();
      if (shouldClear != null && !shouldClear()) return;
      final projects = await _getProjectsUnlocked();
      if (shouldClear != null && !shouldClear()) return;
      final collaborationProjectIds = projects
          .where(
            (project) =>
                project.isCollaborationRoom &&
                (expectedAccountId == null ||
                    project.collaborationAccountId == expectedAccountId ||
                    // Legacy room metadata has no owner. Clear it during an
                    // account transition rather than risk exposing it.
                    project.collaborationAccountId == null),
          )
          .map((project) => project.id)
          .toSet();
      if (collaborationProjectIds.isEmpty) return;

      const rejoinKey = 'ccs_account_scoped_rejoin_projects';
      final existing = prefs.getStringList(rejoinKey) ?? const <String>[];
      await prefs.setStringList(
        rejoinKey,
        {...existing, ...collaborationProjectIds}.toList(growable: false),
      );
      if (shouldClear != null && !shouldClear()) return;
      final clearedProjects = projects
          .map(
            (project) => collaborationProjectIds.contains(project.id)
                ? project.copyWith(clearCollaborationRoom: true)
                : project,
          )
          .toList(growable: false);
      await _writeProjects(prefs, clearedProjects);
    });
  }

  CanvasDocument _degradedDocument(CanvasDocument doc) {
    return doc.copyWith(
      nodes: doc.nodes.map((node) {
        final payload = node.payload;
        if (payload is ImagePayload) {
          return node.copyWith(
            payload: payload.copyWith(
              url: payload.url?.startsWith('data:') == true
                  ? null
                  : payload.url,
            ),
          );
        }
        if (payload is FilePayload && payload.base64Data != null) {
          return node.copyWith(
            payload: payload.copyWith(clearBase64Data: true),
          );
        }
        if (payload is MermaidPayload && payload.cachedSvg != null) {
          return node.copyWith(
            payload: payload.copyWith(
              cachedSvg: null,
              cachedSvgRevision: null,
              cachedSvgConfigKey: null,
            ),
          );
        }
        return node;
      }).toList(),
    );
  }

  static int get documentSizeLimit => _documentSizeLimit;

  Future<CanvasDocument> prepareDocument(CanvasDocument document) =>
      _drawingPaperPersistence.prepareDocument(document);

  Future<CanvasDocument?> loadDocument(String projectId) async {
    await _waitForWrites();
    return _loadDocumentUnlocked(projectId);
  }

  Future<CanvasDocument?> _loadDocumentUnlocked(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_docPrefix$projectId');
    final journalDocument = _readJournalDocument(
      prefs.getString('$_journalPrefix$projectId'),
    );
    CanvasDocument? primaryDocument;
    Object? primaryError;
    if (jsonStr != null) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Canvas document must be a JSON object.');
        }
        primaryDocument = CanvasDocument.fromJson(decoded);
      } catch (error) {
        primaryError = error;
      }
    }
    if (journalDocument != null) {
      return _artifactHydrator.hydrate(journalDocument, projectId: projectId);
    }
    if (primaryDocument != null) {
      return _artifactHydrator.hydrate(primaryDocument, projectId: projectId);
    }
    if (jsonStr == null) return null;
    if (primaryError != null) {
      throw LocalStorageException(
        'Dokumen lokal rusak dan tidak dapat dipulihkan otomatis.',
        primaryError,
      );
    }
    throw LocalStorageException(
      'Dokumen lokal rusak dan tidak dapat dipulihkan otomatis.',
      StateError('document decode returned null'),
    );
  }

  CanvasDocument? _readJournalDocument(String? journalJson) {
    if (journalJson == null) return null;
    try {
      final decoded = jsonDecode(journalJson);
      if (decoded is! Map || decoded['document'] is! Map) return null;
      return CanvasDocument.fromJson(
        Map<String, dynamic>.from(decoded['document'] as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<CanvasDocument?> loadRecoveryDocument(String projectId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    return _readJournalDocument(prefs.getString('$_journalPrefix$projectId'));
  }

  Future<void> saveCollaborationQueue(
    String projectId,
    Iterable<CrdtOperation> operations,
  ) async {
    final queued = List<CrdtOperation>.from(operations);
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_collaborationQueuePrefix$projectId';
      if (queued.isEmpty) {
        if (prefs.containsKey(key)) await _remove(prefs, key);
        return;
      }
      await _setString(
        prefs,
        key,
        jsonEncode(
          queued.map((operation) => operation.toPersistenceJson()).toList(),
        ),
        message: 'Antrian sinkronisasi lokal tidak dapat disimpan.',
      );
    });
  }

  Future<List<CrdtOperation>> loadCollaborationQueue(String projectId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_collaborationQueuePrefix$projectId');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final operations = <CrdtOperation>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          operations.add(
            CrdtOperation.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {
          // Ignore one corrupt queue item and preserve the rest.
        }
      }
      return operations;
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearCollaborationQueue(String projectId) async {
    await saveCollaborationQueue(projectId, const []);
  }

  Future<CanvasDocument> hydrateDocument(CanvasDocument document) {
    return _artifactHydrator.hydrate(document, projectId: document.projectId);
  }

  Future<void> _saveProjectMetadataUnlocked(
    SharedPreferences prefs,
    LocalProjectMetadata meta,
  ) async {
    final projects = await _getProjectsUnlocked();
    final index = projects.indexWhere((project) => project.id == meta.id);
    if (index >= 0) {
      projects[index] = meta;
    } else {
      projects.insert(0, meta);
    }
    await _writeProjects(prefs, projects);
  }

  Future<LocalProjectMetadata> _requireProject(String projectId) async {
    final projects = await _getProjectsUnlocked();
    return projects.firstWhere(
      (project) => project.id == projectId,
      orElse: () => throw StateError('Project not found: $projectId'),
    );
  }

  Future<bool> markCloudAdoptionPending({
    required String projectId,
    required String expectedAccountId,
    required bool Function() shouldWrite,
  }) async {
    var marked = false;
    await _enqueue(() async {
      if (!shouldWrite()) return;
      final prefs = await SharedPreferences.getInstance();
      if (!shouldWrite()) return;
      final projects = await _getProjectsUnlocked();
      final index = projects.indexWhere((project) => project.id == projectId);
      if (index < 0) return;
      final current = projects[index];
      if (current.cloudDeletionDetached ||
          (current.cloudOwnerId != null &&
              current.cloudOwnerId != expectedAccountId) ||
          current.isCollaborationRoom ||
          current.status == ProjectStatus.trashed ||
          (current.cloudAdoptionPendingAccountId != null &&
              current.cloudAdoptionPendingAccountId != expectedAccountId)) {
        return;
      }
      projects[index] = current.copyWith(
        cloudAdoptionPendingAccountId: expectedAccountId,
      );
      if (!shouldWrite()) return;
      await _writeProjects(prefs, projects);
      marked = true;
    });
    return marked;
  }

  Future<void> clearCloudMetadataSyncPendingIfUnchanged(
    LocalProjectMetadata expected, {
    required String expectedOwnerId,
    String? expectedAdoptionPendingAccountId,
    bool Function()? shouldWrite,
  }) async {
    await _enqueue(() async {
      if (shouldWrite != null && !shouldWrite()) return;
      final prefs = await SharedPreferences.getInstance();
      if (shouldWrite != null && !shouldWrite()) return;
      final projects = await _getProjectsUnlocked();
      final index = projects.indexWhere((project) => project.id == expected.id);
      if (index < 0 || (shouldWrite != null && !shouldWrite())) return;
      final current = projects[index];
      if (current.cloudOwnerId != expectedOwnerId ||
          !current.cloudMetadataSyncPending ||
          current.cloudAdoptionPendingAccountId !=
              expectedAdoptionPendingAccountId ||
          current.name != expected.name ||
          current.isPinned != expected.isPinned ||
          current.status != expected.status ||
          current.trashedAt != expected.trashedAt ||
          current.updatedAt != expected.updatedAt) {
        return;
      }
      projects[index] = current.copyWith(
        cloudMetadataSyncPending: false,
        clearCloudAdoptionPendingAccountId:
            current.cloudAdoptionPendingAccountId ==
            expectedAdoptionPendingAccountId,
      );
      if (shouldWrite != null && !shouldWrite()) return;
      await _writeProjects(prefs, projects);
    });
  }

  Future<void> setProjectPinned(String projectId, bool pinned) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final project = await _requireProject(projectId);
      await _saveProjectMetadataUnlocked(
        prefs,
        project.copyWith(
          isPinned: pinned,
          updatedAt: DateTime.now(),
          cloudMetadataSyncPending: project.cloudOwnerId != null
              ? true
              : project.cloudMetadataSyncPending,
        ),
      );
    });
  }

  Future<void> archiveProject(String projectId) async {
    await _setProjectStatus(projectId, ProjectStatus.archived);
  }

  Future<void> moveProjectToTrash(String projectId) async {
    await moveProjectsToTrash([projectId]);
  }

  Future<void> moveProjectsToTrash(Iterable<String> projectIds) async {
    final ids = projectIds.toSet();
    if (ids.isEmpty) return;

    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final projects = await _getProjectsUnlocked();
      final missingIds = ids.difference(
        projects.map((project) => project.id).toSet(),
      );
      if (missingIds.isNotEmpty) {
        throw StateError('Project not found: ${missingIds.first}');
      }
      final now = DateTime.now();
      var changed = false;
      final updatedProjects = projects.map((project) {
        if (!ids.contains(project.id) ||
            project.status == ProjectStatus.trashed) {
          return project;
        }
        changed = true;
        return project.copyWith(
          status: ProjectStatus.trashed,
          isPinned: false,
          trashedAt: now,
          updatedAt: now,
          cloudMetadataSyncPending: project.cloudOwnerId != null
              ? true
              : project.cloudMetadataSyncPending,
        );
      }).toList();

      if (changed) await _writeProjects(prefs, updatedProjects);
    });
  }

  Future<void> restoreProject(String projectId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final project = await _requireProject(projectId);
      await _saveProjectMetadataUnlocked(
        prefs,
        project.copyWith(
          status: ProjectStatus.active,
          updatedAt: DateTime.now(),
          clearTrashedAt: true,
          cloudMetadataSyncPending: project.cloudOwnerId != null
              ? true
              : project.cloudMetadataSyncPending,
        ),
      );
    });
  }

  Future<void> _setProjectStatus(String projectId, ProjectStatus status) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final project = await _requireProject(projectId);
      await _saveProjectMetadataUnlocked(
        prefs,
        project.copyWith(
          status: status,
          updatedAt: DateTime.now(),
          cloudMetadataSyncPending: project.cloudOwnerId != null
              ? true
              : project.cloudMetadataSyncPending,
        ),
      );
    });
  }

  Future<void> deleteProject(String projectId) => moveProjectToTrash(projectId);

  String _cloudProjectDeletionTombstonesKey(String accountId) =>
      '$_cloudProjectDeletionTombstonesPrefix${Uri.encodeComponent(accountId)}';

  Future<Set<String>> pendingCloudProjectDeletionIds(String accountId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(
              _cloudProjectDeletionTombstonesKey(accountId),
            ) ??
            const <String>[])
        .toSet();
  }

  Future<void> queueCloudProjectDeletions(
    String accountId,
    Iterable<String> projectIds,
  ) async {
    final ids = projectIds.where((id) => id.isNotEmpty).toSet();
    if (accountId.isEmpty || ids.isEmpty) return;

    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = _cloudProjectDeletionTombstonesKey(accountId);
      final pending = prefs.getStringList(key) ?? const <String>[];
      await prefs.setStringList(key, {...pending, ...ids}.toList()..sort());
    });
  }

  Future<void> clearCloudProjectDeletions(
    String accountId,
    Iterable<String> projectIds,
  ) async {
    final ids = projectIds.toSet();
    if (accountId.isEmpty || ids.isEmpty) return;

    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = _cloudProjectDeletionTombstonesKey(accountId);
      final pending = prefs.getStringList(key) ?? const <String>[];
      final remaining = pending.where((id) => !ids.contains(id)).toList();
      if (remaining.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setStringList(key, remaining);
      }
    });
  }

  Future<void> purgeProject(String projectId) async {
    await purgeProjects([projectId]);
  }

  Future<void> purgeProjects(Iterable<String> projectIds) async {
    final ids = projectIds.toSet();
    if (ids.isEmpty) return;

    await _enqueue(() async {
      // Complete the authoritative durable purge before changing the legacy
      // project index. If SQLite is unavailable, callers retain the project
      // metadata and can retry without reporting a partial purge as complete.
      final durableStore = _durableProjectStore;
      if (durableStore != null) {
        await durableStore.purgeProjects(ids);
      }

      final prefs = await SharedPreferences.getInstance();
      final projects = await _getProjectsUnlocked();
      await _writeProjects(
        prefs,
        projects.where((project) => !ids.contains(project.id)).toList(),
      );

      for (final projectId in ids) {
        final providerCachePrefix =
            '$_assetLibraryProviderCachePrefix${Uri.encodeComponent(projectId)}_';
        final projectKeyPrefix = '$_collaborationQueuePrefix$projectId';
        final providerCacheKeys = prefs.getKeys().where(
          (key) => key.startsWith(providerCachePrefix),
        );
        final commentNotificationPrefix =
            '$_commentNotificationsPrefix$projectId-';
        final commentNotificationKeys = prefs.getKeys().where(
          (key) => key.startsWith(commentNotificationPrefix),
        );
        final keys = <String>{
          '$_docPrefix$projectId',
          '$_journalPrefix$projectId',
          '$_versionsPrefix$projectId',
          '$_autoCheckpointsPrefix$projectId',
          '$_collaborationQueuePrefix$projectId',
          '$_collaborationQueuePrefix$projectId$_collaborationQueueGenerationSuffix',
          '$_aiJobsPrefix$projectId',
          '$_publishedSnapshotPrefix$projectId',
          '$_componentLibraryPrefix$projectId',
          '$_assetLibraryPrefix$projectId',
          '$_assetLibraryDeletionPrefix$projectId',
          '$_assetLibraryFolderDeletionPrefix$projectId',
          '$_assetLibraryFolderUpsertPrefix$projectId',
          '$_assetLibraryFoldersPrefix$projectId',
          '$_canvasNavigationPrefix$projectId',
          '$_reviewWorkflowPrefix$projectId',
          '$_semanticIndexPrefix$projectId',
          '$_aiCanvasTransactionsPrefix$projectId',
          ...commentNotificationKeys,
          ...providerCacheKeys,
        };
        // Account-scoped collaboration queues use the same project key plus a
        // generation suffix. Match only this project's exact queue prefix so
        // purging `project-a` cannot remove `project-ab`.
        keys.addAll(
          prefs.getKeys().where(
            (key) =>
                key.startsWith(projectKeyPrefix) &&
                (key == projectKeyPrefix ||
                    key ==
                        '$projectKeyPrefix$_collaborationQueueGenerationSuffix'),
          ),
        );
        for (final key in keys) {
          if (prefs.containsKey(key)) await _remove(prefs, key);
        }
      }
    });
  }

  Future<LocalProjectMetadata> duplicateProject(
    String projectId, {
    String? name,
  }) async {
    late LocalProjectMetadata duplicate;
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final source = await _requireProject(projectId);
      final document = await _loadDocumentUnlocked(projectId);
      final duplicateId = const Uuid().v4();
      final now = DateTime.now();
      duplicate = LocalProjectMetadata(
        id: duplicateId,
        name: name?.trim().isNotEmpty == true
            ? name!.trim()
            : '${source.name} Copy',
        createdAt: now,
        updatedAt: now,
        thumbnailPath: source.thumbnailPath,
      );
      if (document != null) {
        await _setString(
          prefs,
          '$_docPrefix$duplicateId',
          jsonEncode(
            document.copyWith(projectId: duplicateId).toPersistenceJson(),
          ),
          message: 'Salinan dokumen tidak dapat disimpan.',
        );
      }
      await _saveProjectMetadataUnlocked(prefs, duplicate);
    });
    return duplicate;
  }

  Future<LocalProjectMetadata> duplicateProjectFromDocument(
    String sourceProjectId,
    CanvasDocument document, {
    String? name,
  }) async {
    late LocalProjectMetadata duplicate;
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final source = await _requireProject(sourceProjectId);
      final duplicateId = const Uuid().v4();
      final now = DateTime.now();
      duplicate = LocalProjectMetadata(
        id: duplicateId,
        name: name?.trim().isNotEmpty == true
            ? name!.trim()
            : '${source.name} Branch',
        createdAt: now,
        updatedAt: now,
        thumbnailPath: source.thumbnailPath,
      );
      await _setString(
        prefs,
        '$_docPrefix$duplicateId',
        jsonEncode(
          document
              .copyWith(projectId: duplicateId, updatedAt: now)
              .toPersistenceJson(),
        ),
        message: 'Branch dokumen tidak dapat disimpan.',
      );
      await _saveProjectMetadataUnlocked(prefs, duplicate);
    });
    return duplicate;
  }

  Future<List<DocumentSnapshotRecord>> loadVersions(String projectId) async {
    await _waitForWrites();
    return _loadVersionsUnlocked(projectId);
  }

  Future<List<DocumentSnapshotRecord>> loadAutoCheckpoints(
    String projectId,
  ) async {
    await _waitForWrites();
    return _loadAutoCheckpointsUnlocked(projectId);
  }

  Future<List<DocumentSnapshotRecord>> _loadAutoCheckpointsUnlocked(
    String projectId, {
    bool hydrate = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_autoCheckpointsPrefix$projectId');
    if (jsonStr == null) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final checkpoints = <DocumentSnapshotRecord>[];
      for (final item in list) {
        final record = DocumentSnapshotRecord.fromJson(
          item as Map<String, dynamic>,
        );
        checkpoints.add(
          DocumentSnapshotRecord(
            id: record.id,
            description: record.description,
            timestamp: record.timestamp,
            document: hydrate
                ? await _artifactHydrator.hydrate(
                    record.document,
                    projectId: projectId,
                  )
                : record.document,
            commandReplay: record.commandReplay,
          ),
        );
      }
      return checkpoints;
    } catch (error) {
      throw LocalStorageException(
        'Autosave checkpoint rusak dan tidak dapat dipulihkan otomatis.',
        error,
      );
    }
  }

  Future<DocumentSnapshotRecord?> saveAutoCheckpoint(
    String projectId,
    CanvasDocument document, {
    String description = 'Autosave checkpoint',
    CommandReplayLog? commandReplay,
  }) async {
    final normalizedDescription = description.trim().isEmpty
        ? 'Autosave checkpoint'
        : description.trim();
    DocumentSnapshotRecord? saved;
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final checkpoints = await _loadAutoCheckpointsUnlocked(
        projectId,
        hydrate: false,
      );
      final candidateDocument = document.copyWith(projectId: projectId);
      final candidateJson = jsonEncode(candidateDocument.toPersistenceJson());
      if (checkpoints.isNotEmpty &&
          jsonEncode(checkpoints.last.document.toPersistenceJson()) ==
              candidateJson) {
        return;
      }

      var record = DocumentSnapshotRecord(
        id: 'auto_${DateTime.now().microsecondsSinceEpoch}',
        description: normalizedDescription,
        timestamp: DateTime.now(),
        document: candidateDocument,
        commandReplay: commandReplay,
      );
      var bounded = [...checkpoints, record];
      if (bounded.length > maxVersions) {
        bounded = bounded.sublist(bounded.length - maxVersions);
      }
      var encoded = jsonEncode(
        bounded.map((checkpoint) => checkpoint.toPersistenceJson()).toList(),
      );
      if (encoded.length > _documentSizeLimit) {
        record = DocumentSnapshotRecord(
          id: record.id,
          description: record.description,
          timestamp: record.timestamp,
          document: _degradedDocument(record.document),
          commandReplay: record.commandReplay,
        );
        bounded = [...checkpoints, record];
        if (bounded.length > maxVersions) {
          bounded = bounded.sublist(bounded.length - maxVersions);
        }
        encoded = jsonEncode(
          bounded.map((checkpoint) => checkpoint.toPersistenceJson()).toList(),
        );
      }
      while (bounded.length > 1 && encoded.length > _documentSizeLimit) {
        bounded = bounded.sublist(1);
        encoded = jsonEncode(
          bounded.map((checkpoint) => checkpoint.toPersistenceJson()).toList(),
        );
      }
      if (encoded.length > _documentSizeLimit) {
        throw LocalStorageException(
          'Autosave checkpoint terlalu besar untuk penyimpanan lokal.',
          StateError('auto checkpoint size limit exceeded'),
        );
      }
      await _setString(
        prefs,
        '$_autoCheckpointsPrefix$projectId',
        encoded,
        message: 'Autosave checkpoint tidak dapat disimpan.',
      );
      saved = record;
    });
    return saved;
  }

  Future<void> clearAutoCheckpoints(String projectId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_autoCheckpointsPrefix$projectId';
      if (prefs.containsKey(key)) await _remove(prefs, key);
    });
  }

  Future<List<DocumentSnapshotRecord>> _loadVersionsUnlocked(
    String projectId, {
    bool hydrate = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_versionsPrefix$projectId');
    if (jsonStr == null) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final versions = <DocumentSnapshotRecord>[];
      for (final item in list) {
        final record = DocumentSnapshotRecord.fromJson(
          item as Map<String, dynamic>,
        );
        versions.add(
          DocumentSnapshotRecord(
            id: record.id,
            description: record.description,
            timestamp: record.timestamp,
            document: hydrate
                ? await _artifactHydrator.hydrate(
                    record.document,
                    projectId: projectId,
                  )
                : record.document,
            commandReplay: record.commandReplay,
          ),
        );
      }
      return versions;
    } catch (error) {
      throw LocalStorageException(
        'Version history rusak dan tidak dapat dipulihkan otomatis.',
        error,
      );
    }
  }

  Future<DocumentSnapshotRecord> saveVersion(
    String projectId,
    CanvasDocument document, {
    required String description,
    CommandReplayLog? commandReplay,
  }) async {
    final normalizedDescription = description.trim();
    if (normalizedDescription.isEmpty) {
      throw ArgumentError.value(
        description,
        'description',
        'Version name cannot be empty.',
      );
    }
    late DocumentSnapshotRecord record;
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final versions = await _loadVersionsUnlocked(projectId, hydrate: false);
      record = DocumentSnapshotRecord(
        id: 'version_${DateTime.now().microsecondsSinceEpoch}',
        description: normalizedDescription,
        timestamp: DateTime.now(),
        document: document.copyWith(projectId: projectId),
        commandReplay: commandReplay,
      );
      var bounded = [...versions, record];
      if (bounded.length > maxVersions) {
        bounded = bounded.sublist(bounded.length - maxVersions);
      }
      var encoded = jsonEncode(
        bounded.map((version) => version.toPersistenceJson()).toList(),
      );
      if (encoded.length > _documentSizeLimit) {
        record = DocumentSnapshotRecord(
          id: record.id,
          description: record.description,
          timestamp: record.timestamp,
          document: _degradedDocument(record.document),
          commandReplay: record.commandReplay,
        );
        bounded = [...versions, record];
        if (bounded.length > maxVersions) {
          bounded = bounded.sublist(bounded.length - maxVersions);
        }
        encoded = jsonEncode(
          bounded.map((version) => version.toPersistenceJson()).toList(),
        );
      }
      while (bounded.length > 1 && encoded.length > _documentSizeLimit) {
        bounded = bounded.sublist(1);
        encoded = jsonEncode(
          bounded.map((version) => version.toPersistenceJson()).toList(),
        );
      }
      if (encoded.length > _documentSizeLimit) {
        throw LocalStorageException(
          'Version history terlalu besar untuk penyimpanan lokal.',
          StateError('version history size limit exceeded'),
        );
      }
      await _setString(
        prefs,
        '$_versionsPrefix$projectId',
        encoded,
        message: 'Version dokumen tidak dapat disimpan.',
      );
    });
    return record;
  }

  Future<void> deleteVersion(String projectId, String versionId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final versions = await _loadVersionsUnlocked(projectId, hydrate: false)
        ..removeWhere((version) => version.id == versionId);
      if (versions.isEmpty) {
        if (prefs.containsKey('$_versionsPrefix$projectId')) {
          await _remove(prefs, '$_versionsPrefix$projectId');
        }
      } else {
        await _setString(
          prefs,
          '$_versionsPrefix$projectId',
          jsonEncode(
            versions.map((version) => version.toPersistenceJson()).toList(),
          ),
          message: 'Version dokumen tidak dapat diperbarui.',
        );
      }
    });
  }

  Future<List<AIJob>> loadAIJobHistory(String projectId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_aiJobsPrefix$projectId');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map) AIJob.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (error) {
      throw LocalStorageException(
        'AI job history is corrupt and could not be recovered automatically.',
        error,
      );
    }
  }

  Future<void> saveAIJobHistory(String projectId, Iterable<AIJob> jobs) async {
    final bounded = jobs.toList(growable: false).take(100).toList();
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        bounded
            .map((job) => redactAIJobJson(job, retainInputArtifacts: true))
            .toList(growable: false),
      );
      if (encoded.length > _documentSizeLimit) {
        throw LocalStorageException(
          'AI job history is too large for local storage.',
          StateError('ai job history size limit exceeded'),
        );
      }
      await _setString(
        prefs,
        '$_aiJobsPrefix$projectId',
        encoded,
        message: 'AI job history could not be saved.',
      );
    });
  }

  Future<void> clearAIJobHistory(String projectId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _remove(prefs, '$_aiJobsPrefix$projectId');
    });
  }

  Future<PublishedSnapshot?> loadPublishedSnapshot(String projectId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_publishedSnapshotPrefix$projectId');
    if (raw == null) return null;
    try {
      return PublishedSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (error) {
      throw LocalStorageException(
        'Published snapshot is corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> savePublishedSnapshot(PublishedSnapshot snapshot) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_publishedSnapshotPrefix${snapshot.projectId}',
        jsonEncode(snapshot.toJson()),
        message: 'Published snapshot could not be saved.',
      );
    });
  }

  Future<void> clearPublishedSnapshot(String projectId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _remove(prefs, '$_publishedSnapshotPrefix$projectId');
    });
  }

  Future<ReviewWorkflow> loadReviewWorkflow(String projectId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_reviewWorkflowPrefix$projectId');
    if (raw == null) return ReviewWorkflow.empty(projectId);
    try {
      return ReviewWorkflow.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (error) {
      throw LocalStorageException(
        'Review workflow is corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveReviewWorkflow(ReviewWorkflow workflow) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_reviewWorkflowPrefix${workflow.projectId}',
        jsonEncode(workflow.toJson()),
        message: 'Review workflow could not be saved.',
      );
    });
  }

  Future<void> clearReviewWorkflow(String projectId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_reviewWorkflowPrefix$projectId';
      if (prefs.containsKey(key)) await _remove(prefs, key);
    });
  }

  Future<SemanticIndex> loadSemanticIndex(String projectId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_semanticIndexPrefix$projectId');
    if (raw == null || raw.isEmpty) return SemanticIndex.empty(projectId);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return SemanticIndex.empty(projectId);
      final index = SemanticIndex.fromJson(Map<String, dynamic>.from(decoded));
      return index.projectId == projectId
          ? index
          : SemanticIndex.empty(projectId);
    } catch (error) {
      throw LocalStorageException(
        'Semantic index is corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveSemanticIndex(SemanticIndex index) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_semanticIndexPrefix${index.projectId}',
        jsonEncode(index.toJson()),
        message: 'Semantic index could not be saved.',
      );
    });
  }

  Future<void> clearSemanticIndex(String projectId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_semanticIndexPrefix$projectId';
      if (prefs.containsKey(key)) await _remove(prefs, key);
    });
  }

  Future<List<AICanvasTransactionEntry>> loadAICanvasTransactions(
    String projectId,
  ) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_aiCanvasTransactionsPrefix$projectId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map)
            AICanvasTransactionEntry.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (error) {
      throw LocalStorageException(
        'AI canvas transactions are corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveAICanvasTransactions(
    String projectId,
    Iterable<AICanvasTransactionEntry> entries,
  ) async {
    final bounded = entries.take(50).toList(growable: false);
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        bounded
            .map((entry) => entry.toPersistenceJson())
            .toList(growable: false),
      );
      if (encoded.length > _documentSizeLimit) {
        throw LocalStorageException(
          'AI canvas transaction history is too large for local storage.',
          StateError('ai canvas transaction history size limit exceeded'),
        );
      }
      await _setString(
        prefs,
        '$_aiCanvasTransactionsPrefix$projectId',
        encoded,
        message: 'AI canvas transaction history could not be saved.',
      );
    });
  }

  Future<void> clearAICanvasTransactions(String projectId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_aiCanvasTransactionsPrefix$projectId';
      if (prefs.containsKey(key)) await _remove(prefs, key);
    });
  }

  Future<ComponentLibrary> loadComponentLibrary(String projectId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_componentLibraryPrefix$projectId');
    if (raw == null) return const ComponentLibrary();
    try {
      return ComponentLibrary.fromJson(jsonDecode(raw));
    } catch (error) {
      throw LocalStorageException(
        'Component library is corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveComponentLibrary(
    String projectId,
    ComponentLibrary library,
  ) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_componentLibraryPrefix$projectId',
        jsonEncode(library.toJson()),
        message: 'Component library could not be saved.',
      );
    });
  }

  Future<void> clearComponentLibrary(String projectId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _remove(prefs, '$_componentLibraryPrefix$projectId');
    });
  }

  Future<ProjectTemplateCatalog> loadProjectTemplates(
    String workspaceId,
  ) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_projectTemplatesPrefix$workspaceId');
    if (raw == null) return ProjectTemplateCatalog.withBuiltIns();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return ProjectTemplateCatalog.withBuiltIns();
      final custom = [
        for (final item in decoded)
          if (item is Map)
            ProjectTemplate.fromJson(Map<String, dynamic>.from(item)),
      ];
      return ProjectTemplateCatalog.withBuiltIns(custom: custom);
    } catch (error) {
      throw LocalStorageException(
        'Project templates are corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveProjectTemplates(
    String workspaceId,
    ProjectTemplateCatalog catalog,
  ) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final custom = catalog.templates
          .where((template) => !template.isBuiltIn)
          .map((template) => template.toJson())
          .toList(growable: false);
      await _setString(
        prefs,
        '$_projectTemplatesPrefix$workspaceId',
        jsonEncode(custom),
        message: 'Project templates could not be saved.',
      );
    });
  }

  Future<void> clearProjectTemplates(String workspaceId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _remove(prefs, '$_projectTemplatesPrefix$workspaceId');
    });
  }

  Future<List<AssetLibraryItem>> loadAssetLibrary(String scopeId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_assetLibraryPrefix$scopeId');
    if (raw == null ||
        raw.isEmpty ||
        _utf8ByteLength(raw) > _assetLibraryCacheMaxBytes) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = <AssetLibraryItem>[];
      for (final value in decoded.take(500)) {
        if (value is! Map) continue;
        try {
          final item = AssetLibraryItem.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (item.scopeId == scopeId) items.add(item);
        } catch (_) {
          // One corrupt catalog item must not hide the remaining library.
        }
      }
      return items;
    } catch (error) {
      debugPrint('[LocalStorage] Ignoring corrupt asset library cache: $error');
      return const [];
    }
  }

  Future<void> saveAssetLibrary(
    String scopeId,
    Iterable<AssetLibraryItem> items,
  ) async {
    final scopedItems = items.where((item) => item.scopeId == scopeId).toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final candidates = scopedItems.length <= 500
        ? scopedItems
        : scopedItems.sublist(0, 500);
    final bounded = <AssetLibraryItem>[];
    var encodedLength = 2; // JSON array brackets.
    for (final item in candidates) {
      final itemLength = _utf8ByteLength(jsonEncode(item.toJson()));
      final separatorLength = bounded.isEmpty ? 0 : 1;
      if (encodedLength + separatorLength + itemLength >
          _assetLibraryCacheMaxBytes) {
        break;
      }
      bounded.add(item);
      encodedLength += separatorLength + itemLength;
    }
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_assetLibraryPrefix$scopeId',
        jsonEncode(bounded.map((item) => item.toJson()).toList()),
        message: 'Asset library could not be saved locally.',
      );
    });
  }

  Future<void> clearAssetLibrary(String scopeId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        '$_assetLibraryPrefix$scopeId',
        '$_assetLibraryDeletionPrefix$scopeId',
        '$_assetLibraryFolderDeletionPrefix$scopeId',
        '$_assetLibraryFolderUpsertPrefix$scopeId',
        '$_assetLibraryFoldersPrefix$scopeId',
      ]) {
        if (prefs.containsKey(key)) await _remove(prefs, key);
      }
      final providerCachePrefix =
          '$_assetLibraryProviderCachePrefix${Uri.encodeComponent(scopeId)}_';
      final providerCacheKeys = prefs
          .getKeys()
          .where((key) => key.startsWith(providerCachePrefix))
          .toList(growable: false);
      for (final key in providerCacheKeys) {
        if (prefs.containsKey(key)) await _remove(prefs, key);
      }
    });
  }

  Future<Map<String, String?>> loadAssetLibraryDeletionTombstones(
    String scopeId,
  ) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_assetLibraryDeletionPrefix$scopeId');
    if (raw == null ||
        raw.isEmpty ||
        _utf8ByteLength(raw) > _assetLibraryDeletionCacheMaxBytes) {
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final tombstones = <String, String?>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) continue;
        final rawId = entry.key as String;
        final id = rawId.trim();
        if (id.isEmpty ||
            id.length > 256 ||
            rawId != id ||
            _hasAssetLibraryControlCharacter(rawId)) {
          continue;
        }
        if (entry.value != null && entry.value is! String) continue;
        final rawPath = entry.value as String?;
        final path = rawPath?.trim();
        if (rawPath != null &&
            (path == null ||
                path.isEmpty ||
                path.length > 512 ||
                rawPath != path ||
                _hasAssetLibraryControlCharacter(rawPath))) {
          continue;
        }
        tombstones[id] = path;
        if (tombstones.length == 500) break;
      }
      return tombstones;
    } catch (_) {
      // A corrupt deletion queue is disposable; it must not hide the catalog.
      return const {};
    }
  }

  Future<void> saveAssetLibraryDeletionTombstones(
    String scopeId,
    Map<String, String?> tombstones,
  ) async {
    final entries = tombstones.entries.toList(growable: false);
    final candidates = entries.length <= 500
        ? entries
        : entries.sublist(entries.length - 500);
    final bounded = <String, String?>{};
    for (final entry in candidates) {
      final id = entry.key.trim();
      final path = entry.value?.trim();
      if (id.isEmpty ||
          id.length > 256 ||
          entry.key != id ||
          _hasAssetLibraryControlCharacter(entry.key)) {
        continue;
      }
      if (path != null &&
          (path.isEmpty ||
              path.length > 512 ||
              entry.value != path ||
              _hasAssetLibraryControlCharacter(entry.value!))) {
        continue;
      }
      bounded[id] = path;
      if (_utf8ByteLength(jsonEncode(bounded)) >
          _assetLibraryDeletionCacheMaxBytes) {
        bounded.remove(id);
        break;
      }
      if (bounded.length == 500) break;
    }
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_assetLibraryDeletionPrefix$scopeId',
        jsonEncode(bounded),
        message: 'Asset library deletion queue could not be saved locally.',
      );
    });
  }

  Future<Set<String>> loadAssetLibraryFolderDeletionTombstones(
    String scopeId,
  ) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_assetLibraryFolderDeletionPrefix$scopeId');
    if (raw == null ||
        raw.isEmpty ||
        _utf8ByteLength(raw) > _assetLibraryFolderCacheMaxBytes) {
      return const <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>{};
      final tombstones = <String>{};
      for (final value in decoded) {
        if (value is! String ||
            value.trim().isEmpty ||
            value.length > 256 ||
            value != value.trim() ||
            _hasAssetLibraryControlCharacter(value)) {
          continue;
        }
        tombstones.add(value.trim());
        if (tombstones.length == 500) break;
      }
      return tombstones;
    } catch (_) {
      return const <String>{};
    }
  }

  Future<void> saveAssetLibraryFolderDeletionTombstones(
    String scopeId,
    Iterable<String> folderIds,
  ) async {
    final values = folderIds.toList(growable: false);
    final candidates = values.length <= 500
        ? values
        : values.sublist(values.length - 500);
    final bounded = <String>{};
    for (final value in candidates) {
      final id = value.trim();
      if (id.isEmpty ||
          id.length > 256 ||
          value != id ||
          _hasAssetLibraryControlCharacter(value)) {
        continue;
      }
      bounded.add(id);
      if (_utf8ByteLength(jsonEncode(bounded.toList(growable: false))) >
          _assetLibraryFolderCacheMaxBytes) {
        bounded.remove(id);
        break;
      }
      if (bounded.length == 500) break;
    }
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_assetLibraryFolderDeletionPrefix$scopeId',
        jsonEncode(bounded.toList(growable: false)),
        message: 'Asset library folder deletion queue could not be saved.',
      );
    });
  }

  Future<Set<String>> loadAssetLibraryFolderUpsertQueue(String scopeId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_assetLibraryFolderUpsertPrefix$scopeId');
    if (raw == null ||
        raw.isEmpty ||
        _utf8ByteLength(raw) > _assetLibraryFolderCacheMaxBytes) {
      return const <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>{};
      final pending = <String>{};
      for (final value in decoded) {
        if (value is! String ||
            value.trim().isEmpty ||
            value.length > 256 ||
            value != value.trim() ||
            _hasAssetLibraryControlCharacter(value)) {
          continue;
        }
        pending.add(value.trim());
        if (pending.length == 500) break;
      }
      return pending;
    } catch (_) {
      return const <String>{};
    }
  }

  Future<void> saveAssetLibraryFolderUpsertQueue(
    String scopeId,
    Iterable<String> folderIds,
  ) async {
    final values = folderIds.toList(growable: false);
    final candidates = values.length <= 500
        ? values
        : values.sublist(values.length - 500);
    final bounded = <String>{};
    for (final value in candidates) {
      final id = value.trim();
      if (id.isEmpty ||
          id.length > 256 ||
          value != id ||
          _hasAssetLibraryControlCharacter(value)) {
        continue;
      }
      bounded.add(id);
      if (_utf8ByteLength(jsonEncode(bounded.toList(growable: false))) >
          _assetLibraryFolderCacheMaxBytes) {
        bounded.remove(id);
        break;
      }
      if (bounded.length == 500) break;
    }
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_assetLibraryFolderUpsertPrefix$scopeId',
        jsonEncode(bounded.toList(growable: false)),
        message: 'Asset library folder sync queue could not be saved.',
      );
    });
  }

  String _assetProviderCacheKey(
    String scopeId,
    String providerId,
    String queryKey,
  ) =>
      '$_assetLibraryProviderCachePrefix${Uri.encodeComponent(scopeId)}_${Uri.encodeComponent(providerId)}_${Uri.encodeComponent(queryKey)}';

  Future<AssetLibraryProviderCache?> loadAssetLibraryProviderCache(
    String scopeId,
    String providerId,
    String queryKey,
  ) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      _assetProviderCacheKey(scopeId, providerId, queryKey),
    );
    if (raw == null || raw.isEmpty || _utf8ByteLength(raw) > 2 * 1024 * 1024) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? AssetLibraryProviderCache.fromJson(
              Map<String, dynamic>.from(decoded),
            )
          : null;
    } catch (_) {
      // A corrupt provider cache is disposable; saved catalog items remain.
      return null;
    }
  }

  Future<void> saveAssetLibraryProviderCache(
    String scopeId,
    String providerId,
    String queryKey,
    AssetLibraryProviderCache cache,
  ) async {
    final encoded = jsonEncode(cache.toJson());
    if (_utf8ByteLength(encoded) > 2 * 1024 * 1024) return;
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = _assetProviderCacheKey(scopeId, providerId, queryKey);
      final prefix =
          '$_assetLibraryProviderCachePrefix${Uri.encodeComponent(scopeId)}_';
      final existingKeys = prefs.getKeys().where(
        (candidate) => candidate.startsWith(prefix) && candidate != key,
      );
      final cacheRecords = <({String key, DateTime fetchedAt})>[];
      for (final candidate in existingKeys) {
        final raw = prefs.getString(candidate);
        if (raw == null) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final fetchedAt = DateTime.tryParse(
              decoded['fetchedAt']?.toString() ?? '',
            );
            if (fetchedAt != null) {
              cacheRecords.add((key: candidate, fetchedAt: fetchedAt));
            }
          }
        } catch (_) {
          cacheRecords.add((
            key: candidate,
            fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ));
        }
      }
      cacheRecords.sort(
        (left, right) => left.fetchedAt.compareTo(right.fetchedAt),
      );
      while (cacheRecords.length >= 32) {
        final oldest = cacheRecords.removeAt(0);
        if (prefs.containsKey(oldest.key)) await _remove(prefs, oldest.key);
      }
      await _setString(
        prefs,
        key,
        encoded,
        message: 'Asset provider cache could not be saved locally.',
      );
    });
  }

  Future<List<AssetLibraryFolder>> loadAssetLibraryFolders(
    String scopeId,
  ) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_assetLibraryFoldersPrefix$scopeId');
    if (raw == null ||
        raw.isEmpty ||
        _utf8ByteLength(raw) > _assetLibraryFolderCacheMaxBytes) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final folders = <AssetLibraryFolder>[];
      for (final value in decoded.take(100)) {
        if (value is! Map) continue;
        try {
          final folder = AssetLibraryFolder.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (folder.scopeId == scopeId) folders.add(folder);
        } catch (_) {
          // Ignore only the malformed folder; keep the rest of the catalog.
        }
      }
      return folders;
    } catch (error) {
      debugPrint(
        '[LocalStorage] Ignoring corrupt asset library folders: $error',
      );
      return const [];
    }
  }

  Future<void> saveAssetLibraryFolders(
    String scopeId,
    Iterable<AssetLibraryFolder> folders,
  ) async {
    final scopedFolders =
        folders.where((folder) => folder.scopeId == scopeId).toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final candidates = scopedFolders.length <= 100
        ? scopedFolders
        : scopedFolders.sublist(0, 100);
    final bounded = <AssetLibraryFolder>[];
    for (final folder in candidates) {
      bounded.add(folder);
      if (_utf8ByteLength(
            jsonEncode(bounded.map((item) => item.toJson()).toList()),
          ) >
          _assetLibraryFolderCacheMaxBytes) {
        bounded.removeLast();
        break;
      }
    }
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_assetLibraryFoldersPrefix$scopeId',
        jsonEncode(bounded.map((folder) => folder.toJson()).toList()),
        message: 'Asset library folders could not be saved locally.',
      );
    });
  }

  Future<void> clearAssetLibraryFolders(String scopeId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        '$_assetLibraryFoldersPrefix$scopeId',
        '$_assetLibraryFolderDeletionPrefix$scopeId',
        '$_assetLibraryFolderUpsertPrefix$scopeId',
      ]) {
        if (prefs.containsKey(key)) await _remove(prefs, key);
      }
    });
  }

  Future<CanvasNavigationState> loadCanvasNavigation(String projectId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_canvasNavigationPrefix$projectId');
    if (raw == null) return const CanvasNavigationState();
    try {
      return CanvasNavigationState.fromJson(jsonDecode(raw));
    } catch (error) {
      throw LocalStorageException(
        'Canvas navigation data is corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveCanvasNavigation(
    String projectId,
    CanvasNavigationState navigation,
  ) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_canvasNavigationPrefix$projectId',
        jsonEncode(navigation.toJson()),
        message: 'Canvas navigation data could not be saved.',
      );
    });
  }

  Future<void> clearCanvasNavigation(String projectId) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _remove(prefs, '$_canvasNavigationPrefix$projectId');
    });
  }

  Future<List<CommentNotification>> loadCommentNotifications(
    String projectId,
    String userId,
  ) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      '$_commentNotificationsPrefix$projectId-$userId',
    );
    if (raw == null) return const [];
    try {
      return CommentNotificationCenter.fromJson(jsonDecode(raw)).notifications;
    } catch (error) {
      throw LocalStorageException(
        'Comment notifications are corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveCommentNotifications(
    String projectId,
    String userId,
    Iterable<CommentNotification> notifications,
  ) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_commentNotificationsPrefix$projectId-$userId',
        jsonEncode(CommentNotificationCenter(notifications).toJson()),
        message: 'Comment notifications could not be saved.',
      );
    });
  }

  Future<void> clearCommentNotifications(
    String projectId,
    String userId,
  ) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _remove(prefs, '$_commentNotificationsPrefix$projectId-$userId');
    });
  }

  Future<CommentNotificationPreferences> loadCommentNotificationPreferences(
    String userId,
  ) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      '$_commentNotificationPreferencesPrefix$userId',
    );
    if (raw == null) return const CommentNotificationPreferences();
    try {
      return CommentNotificationPreferences.fromJson(jsonDecode(raw));
    } catch (error) {
      throw LocalStorageException(
        'Comment notification preferences are corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveCommentNotificationPreferences(
    String userId,
    CommentNotificationPreferences preferences,
  ) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        '$_commentNotificationPreferencesPrefix$userId',
        jsonEncode(preferences.toJson()),
        message: 'Comment notification preferences could not be saved.',
      );
    });
  }

  Future<AccessibilitySettings> loadAccessibilitySettings() async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accessibilitySettingsKey);
    if (raw == null) return const AccessibilitySettings();
    try {
      return AccessibilitySettings.fromJson(jsonDecode(raw));
    } catch (error) {
      throw LocalStorageException(
        'Accessibility settings are corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveAccessibilitySettings(AccessibilitySettings settings) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        _accessibilitySettingsKey,
        jsonEncode(settings.toJson()),
        message: 'Accessibility settings could not be saved.',
      );
    });
  }

  Future<WorkspacePolicy> loadWorkspacePolicy() async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_workspacePolicyKey);
    if (raw == null) return const WorkspacePolicy();
    try {
      return WorkspacePolicy.fromJson(jsonDecode(raw));
    } catch (error) {
      throw LocalStorageException(
        'Workspace policy is corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> saveWorkspacePolicy(WorkspacePolicy policy) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        _workspacePolicyKey,
        jsonEncode(policy.toJson()),
        message: 'Workspace policy could not be saved.',
      );
    });
  }

  Future<PluginRegistry> loadPluginRegistry({
    DateTime Function()? clock,
  }) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pluginRegistryKey);
    if (raw == null) return PluginRegistry(clock: clock);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Plugin registry must be a list.');
      }
      return PluginRegistry.fromJson(decoded, clock: clock);
    } catch (error) {
      throw LocalStorageException(
        'Plugin registry is corrupt and could not be recovered.',
        error,
      );
    }
  }

  Future<void> savePluginRegistry(PluginRegistry registry) async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await _setString(
        prefs,
        _pluginRegistryKey,
        jsonEncode(registry.toJson()),
        message: 'Plugin registry could not be saved.',
      );
    });
  }

  Future<void> clearPluginRegistry() async {
    await _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_pluginRegistryKey)) {
        await _remove(prefs, _pluginRegistryKey);
      }
    });
  }
}
