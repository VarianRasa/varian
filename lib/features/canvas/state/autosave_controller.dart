import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/data/remote/supabase_sync_provider.dart';

export 'package:varian/data/remote/supabase_sync_provider.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/state/design_token_provider.dart';
import 'package:varian/features/canvas/state/viewport_provider.dart';
import 'package:varian/features/canvas/domain/canvas_navigation.dart';
import 'package:varian/features/collaboration/state/collaboration_session_provider.dart';
import 'package:varian/features/history/history_provider.dart';
import 'package:varian/features/history/snapshot_manager.dart';

enum SyncStatus {
  localOnly,
  localSaved,
  localDegraded,
  syncing,
  synced,
  cloudPending,
  error,
}

class SyncState {
  final SyncStatus status;
  final String? errorMessage;
  final DateTime lastSyncedAt;

  const SyncState({
    this.status = SyncStatus.localOnly,
    this.errorMessage,
    required this.lastSyncedAt,
  });

  SyncState copyWith({
    SyncStatus? status,
    String? errorMessage,
    DateTime? lastSyncedAt,
  }) {
    return SyncState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

final syncStatusProvider = StateProvider<SyncState>((ref) {
  return SyncState(status: SyncStatus.localOnly, lastSyncedAt: DateTime.now());
});

final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService(
    artifactStoreBundle: ref.watch(artifactStoreBundleProvider),
    durableProjectStore: ref.watch(durableProjectStoreProvider),
  );
});

// Persistence sessions are lightweight project-scoped handles over the
// app-owned durable store. Keep them alive for the container lifetime so an
// async final save cannot be invalidated merely because the autosave widget
// released its read-only provider access.
final projectPersistenceSessionProvider =
    Provider.family<ProjectSession, String>(
      (ref, projectId) => ref.watch(projectSessionProvider(projectId)),
    );

final autosaveControllerProvider = Provider.autoDispose<AutosaveController>((
  ref,
) {
  final keepAlive = ref.keepAlive();
  final controller = AutosaveController(ref);
  ref.onDispose(() {
    keepAlive.close();
    unawaited(controller.dispose());
  });
  return controller;
});

class AutosaveController {
  final Ref _ref;
  Timer? _debounceTimer;
  Timer? _cloudRetryTimer;
  String? _activeProjectId;
  CanvasDocument? _pendingCloudDocument;
  CanvasNavigationState? _navigationState;
  int _cloudRetryCount = 0;
  int _cloudRetryGeneration = 0;
  int _cloudOperationEpoch = 0;
  int _lifecycleGeneration = 0;
  bool _cloudRetryPaused = false;
  Future<void>? _saveInFlight;
  Future<void>? _cloudSyncInFlight;
  bool _listenersAttached = false;
  bool _syncCloudEnabled = true;
  int _changeRevision = 0;
  int _savedRevision = 0;
  bool _lastDurableSaveSucceeded = true;
  bool _disposeRequested = false;
  bool _transitionPaused = false;
  bool _disposed = false;

  AutosaveController(this._ref);

  bool get isInitialized => _activeProjectId != null;
  String? get activeProjectId => _activeProjectId;

  void updateNavigation(
    CanvasNavigationState navigation, {
    bool scheduleSave = true,
  }) {
    _navigationState = navigation;
    if (scheduleSave && isInitialized) _triggerDebouncedSave();
  }

  void init(String projectId, {bool syncCloud = true}) {
    if (_activeProjectId == projectId && !_disposed) {
      _syncCloudEnabled = syncCloud;
      if (_cloudRetryPaused || _transitionPaused) {
        _transitionPaused = false;
        _cloudRetryCount = 0;
        if (_cloudRetryPaused) {
          _cancelCloudRetry(clearPending: true);
          _cloudRetryPaused = false;
        }
      }
      return;
    }
    _syncCloudEnabled = syncCloud;
    _cloudRetryPaused = false;
    _cancelCloudRetry(clearPending: true);
    _lifecycleGeneration++;
    _debounceTimer?.cancel();
    _disposeRequested = false;
    _transitionPaused = false;
    _disposed = false;
    _activeProjectId = projectId;
    _changeRevision = 0;
    _savedRevision = 0;
    _lastDurableSaveSucceeded = true;
    _ref.read(boardHistoryProvider.notifier).clear();
    if (!_listenersAttached) {
      _listenersAttached = true;
      _ref.listen(documentNodesProvider, (previous, next) {
        _markChanged();
      });
      _ref.listen(documentEdgesProvider, (previous, next) {
        _markChanged();
      });
      _ref.listen(viewportProvider, (previous, next) {
        _markChanged();
      });
      _ref.listen(designTokenSetProvider, (previous, next) {
        _markChanged();
      });
    }
    _setStatus(SyncStatus.localOnly);
  }

  void _markChanged() {
    _changeRevision++;
    _triggerDebouncedSave();
  }

  void _triggerDebouncedSave() {
    if (_transitionPaused) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      saveImmediately(syncCloud: _syncCloudEnabled);
    });
  }

  CanvasDocument currentDocument() {
    final projectId = _activeProjectId;
    if (projectId == null) {
      throw StateError('Autosave controller is not initialized.');
    }
    return CanvasDocument(
      projectId: projectId,
      nodes: _ref.read(documentNodesProvider),
      edges: _ref.read(documentEdgesProvider),
      viewport: _ref.read(viewportProvider),
      navigation: _navigationState?.toJson() ?? const {},
      assets: _ref.read(documentAssetsProvider),
      tokens: _ref.read(designTokenSetProvider),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> restoreDocument(CanvasDocument document) async {
    if (_disposed || _activeProjectId != document.projectId) return;
    _ref.read(documentNodesProvider.notifier).setNodes(document.nodes);
    _ref.read(documentEdgesProvider.notifier).setEdges(document.edges);
    _ref.read(documentAssetsProvider.notifier).setManifest(document.assets);
    _ref.read(designTokenSetProvider.notifier).setSet(document.tokens);
    _ref
        .read(viewportProvider.notifier)
        .setPosition(document.viewport.x, document.viewport.y);
    _ref.read(viewportProvider.notifier).setZoom(document.viewport.zoom);
    _ref.read(historyProvider.notifier).clear();
    _ref.read(nodeHistoryProvider.notifier).clear();
    await saveImmediately(syncCloud: _syncCloudEnabled);
  }

  Future<void> saveImmediately({bool syncCloud = true}) {
    _debounceTimer?.cancel();
    final current = _saveInFlight;
    if (current != null) {
      return current.then((_) => saveImmediately(syncCloud: syncCloud));
    }
    final operation = _saveImmediatelyOnce(syncCloud: syncCloud);
    _saveInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_saveInFlight, operation)) _saveInFlight = null;
    });
  }

  /// Completes the current project's durable save before a route or tab
  /// transition. Widget disposal is synchronous, so callers that own the
  /// transition must await this boundary while the controller is still live.
  Future<void> flush() => _flush(syncCloud: _syncCloudEnabled);

  /// Flushes the outgoing project and detaches its autosave lifecycle before
  /// route loading can replace the shared canvas providers with another project.
  Future<void> flushAndDeactivateProject(String projectId) async {
    if (_disposed || _activeProjectId != projectId) return;
    _transitionPaused = true;
    _cloudOperationEpoch++;
    try {
      await _flush(syncCloud: _syncCloudEnabled);
      if (_disposed || _activeProjectId != projectId) return;
      _debounceTimer?.cancel();
      _cancelCloudRetry(clearPending: true);
      _lifecycleGeneration++;
      _activeProjectId = null;
      _changeRevision = 0;
      _savedRevision = 0;
      _lastDurableSaveSucceeded = true;
    } catch (_) {
      if (!_disposed && _activeProjectId == projectId) {
        _transitionPaused = false;
      }
      rethrow;
    }
  }

  /// Completes only the local durable save. Account transitions use this
  /// boundary because the auth stream may already expose the replacement
  /// account; publishing the outgoing document to that account is unsafe.
  Future<void> flushDurable({bool deactivateAfterFlush = false}) async {
    _transitionPaused = true;
    _cloudRetryPaused = true;
    _cloudOperationEpoch++;
    _cancelCloudRetry(clearPending: true);
    var flushed = false;
    try {
      await _flush(syncCloud: false);
      flushed = true;
      if (deactivateAfterFlush && !_disposed) {
        _debounceTimer?.cancel();
        _cancelCloudRetry(clearPending: true);
        _lifecycleGeneration++;
        _activeProjectId = null;
        _changeRevision = 0;
        _savedRevision = 0;
        _lastDurableSaveSucceeded = true;
      }
    } finally {
      // On a failed account-transition flush, leave writes paused. The caller
      // must retain the in-memory revision and never let a later account's
      // edits or autosave lifecycle take ownership of it.
      if (!_disposed && (!deactivateAfterFlush || flushed)) {
        _transitionPaused = false;
      }
      if (flushed && !deactivateAfterFlush) {
        _cloudRetryPaused = false;
        _cancelCloudRetry(clearPending: true);
      }
    }
  }

  Future<void> _flush({required bool syncCloud}) async {
    _debounceTimer?.cancel();
    if (_disposed || _activeProjectId == null) return;
    while (!_disposed && _activeProjectId != null) {
      final targetRevision = _changeRevision;
      await saveImmediately(syncCloud: syncCloud);
      if (!_lastDurableSaveSucceeded) {
        throw StateError('Durable project save failed; navigation is unsafe.');
      }
      if (_changeRevision == targetRevision &&
          _savedRevision >= targetRevision) {
        return;
      }
      _debounceTimer?.cancel();
    }
  }

  Future<void> _saveImmediatelyOnce({required bool syncCloud}) async {
    final generation = _lifecycleGeneration;
    final saveRevision = _changeRevision;
    final accountId = _currentAccountId();
    if (!_isCurrent(generation) || _activeProjectId == null) return;

    var doc = currentDocument();

    final localStorage = _ref.read(localStorageServiceProvider);
    final durableSession = _ref.read(
      projectPersistenceSessionProvider(doc.projectId),
    );
    try {
      doc = await localStorage.prepareDocument(doc);
    } catch (_) {
      // Local JSON and replayable edits remain the fallback when preview
      // generation is unavailable on the current platform.
    }
    if (!_isCurrent(generation)) return;
    LocalSaveResult? localResult;
    var durableSaved = false;
    try {
      await durableSession.saveDocument(doc, navigation: _navigationState);
      durableSaved = true;
    } catch (error) {
      _lastDurableSaveSucceeded = false;
      if (!_isCurrent(generation)) return;
      debugPrint('[AutosaveController] Durable persistence failed: $error');
      // SharedPreferences remains a compatibility fallback, but it must not
      // become the authoritative write when the durable project store works.
    }
    if (durableSaved) _lastDurableSaveSucceeded = true;
    if (!_isCurrent(generation)) return;

    try {
      localResult = await localStorage.saveDocument(
        doc,
        shouldWriteMetadata: () =>
            _isCurrent(generation) && _accountIsCurrent(accountId),
      );
    } on LocalStorageException catch (error) {
      if (!_isCurrent(generation)) return;
      if (!durableSaved) {
        _setStatus(SyncStatus.error, errorMessage: error.message);
        return;
      }
      _setStatus(
        SyncStatus.localDegraded,
        errorMessage: 'Data durable tersimpan; fallback legacy gagal.',
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      if (!durableSaved) {
        _setStatus(
          SyncStatus.error,
          errorMessage: 'Penyimpanan lokal gagal. Periksa ruang browser.',
        );
        return;
      }
      _setStatus(
        SyncStatus.localDegraded,
        errorMessage: 'Data durable tersimpan; fallback legacy gagal.',
      );
    }

    if (!_isCurrent(generation)) return;
    _ref.read(boardHistoryProvider.notifier).addSnapshot(doc);
    try {
      final commandReplay = _ref
          .read(historyProvider.notifier)
          .exportReplay(doc.projectId);
      await _ref
          .read(persistedAutoCheckpointsProvider(doc.projectId).notifier)
          .save(doc, commandReplay: commandReplay);
      final checkpoints = await durableSession.store.loadAutoCheckpoints(
        doc.projectId,
      );
      final latest = checkpoints.isEmpty ? null : checkpoints.last;
      final record =
          latest?.document.toPersistenceJson().toString() ==
              doc.toPersistenceJson().toString()
          ? latest
          : DocumentSnapshotRecord(
              id: 'auto_${DateTime.now().microsecondsSinceEpoch}',
              description: 'Autosave checkpoint',
              timestamp: DateTime.now(),
              document: doc,
              commandReplay: commandReplay,
            );
      if (record != null && (latest == null || !identical(record, latest))) {
        final bounded = [...checkpoints, record];
        await durableSession.store.saveAutoCheckpoints(
          doc.projectId,
          bounded.length > LocalStorageService.maxVersions
              ? bounded.sublist(
                  bounded.length - LocalStorageService.maxVersions,
                )
              : bounded,
        );
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      debugPrint(
        '[AutosaveController] Auto checkpoint persistence failed: $error',
      );
    }
    if (!_isCurrent(generation)) return;
    _pendingCloudDocument = doc;
    _cloudRetryCount = 0;
    _setStatus(
      !durableSaved ||
              localResult == null ||
              localResult == LocalSaveResult.degraded
          ? SyncStatus.localDegraded
          : SyncStatus.localSaved,
      errorMessage: !durableSaved
          ? 'Penyimpanan durable gagal. Data legacy tersimpan.'
          : localResult == LocalSaveResult.degraded
          ? 'Data gambar besar dilewati pada penyimpanan browser.'
          : null,
    );

    if (saveRevision > _savedRevision) _savedRevision = saveRevision;
    if (!syncCloud) return;
    final cloudSync = _syncCloud(
      doc,
      generation: generation,
      accountId: accountId,
    );
    _cloudSyncInFlight = cloudSync;
    unawaited(
      cloudSync.whenComplete(() {
        if (identical(_cloudSyncInFlight, cloudSync)) {
          _cloudSyncInFlight = null;
        }
      }),
    );
  }

  String? _currentAccountId() {
    final client = _ref.read(supabaseClientProvider);
    return client?.auth.currentUser?.id ?? client?.auth.currentSession?.user.id;
  }

  bool _accountIsCurrent(String? accountId) => _currentAccountId() == accountId;

  bool _isCurrent(int generation) =>
      !_disposeRequested && !_disposed && generation == _lifecycleGeneration;

  bool _isCloudOperationCurrent(int epoch) =>
      !_cloudRetryPaused && epoch == _cloudOperationEpoch;

  Future<CanvasDocument> _prepareCloudDocument(
    CanvasDocument document,
    SupabaseSyncService sync, {
    required int generation,
    required String? accountId,
    required int cloudOperationEpoch,
  }) async {
    if (accountId == null) return document;
    final nodes = List.of(document.nodes);
    for (var index = 0; index < nodes.length; index++) {
      if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
          !_isCurrent(generation) ||
          !_accountIsCurrent(accountId)) {
        return document;
      }
      final node = nodes[index];
      final payload = node.payload;
      if (payload is! DrawingPaperPayload) continue;
      Uint8List? bytes;
      try {
        bytes = await DrawingPaperRenderer.renderPng(payload);
      } catch (_) {
        bytes = null;
      }
      if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
          !_isCurrent(generation) ||
          !_accountIsCurrent(accountId)) {
        return document;
      }
      if (bytes == null) {
        nodes[index] = node.copyWith(
          payload: payload.copyWith(compositePreviewRef: null),
        );
        continue;
      }
      final documentId = payload.rasterDocumentId.isEmpty
          ? node.id
          : payload.rasterDocumentId;
      final fingerprint = sha256.convert(bytes).toString().substring(0, 16);
      final path =
          'drawing-paper/${document.projectId}/$documentId/${payload.rasterRevision}-$fingerprint.png';
      if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
          !_isCurrent(generation) ||
          !_accountIsCurrent(accountId)) {
        return document;
      }
      final storagePath = await sync.uploadAssetForProjectEditor(
        bucket: 'assets',
        path: path,
        bytes: bytes,
        contentType: 'image/png',
        expectedUserId: accountId,
        isOperationCurrent: () =>
            _isCloudOperationCurrent(cloudOperationEpoch) &&
            _isCurrent(generation) &&
            _accountIsCurrent(accountId),
      );
      if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
          !_isCurrent(generation) ||
          !_accountIsCurrent(accountId)) {
        return document;
      }
      nodes[index] = node.copyWith(
        payload: payload.copyWith(compositePreviewRef: storagePath),
      );
    }
    return document.copyWith(nodes: nodes);
  }

  Future<void> _syncCloud(
    CanvasDocument doc, {
    required int generation,
    required String? accountId,
  }) async {
    final cloudOperationEpoch = _cloudOperationEpoch;
    if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
        !_isCurrent(generation) ||
        !_accountIsCurrent(accountId)) {
      return;
    }
    final supabaseSync = _ref.read(supabaseSyncServiceProvider);
    if (!supabaseSync.isConfigured) {
      if (_isCurrent(generation)) _setStatus(SyncStatus.localSaved);
      return;
    }
    if (!supabaseSync.isAuthenticated) {
      if (_isCurrent(generation)) _setStatus(SyncStatus.localSaved);
      return;
    }

    try {
      final collaboration = _ref.read(
        collaborationSessionProvider(doc.projectId).notifier,
      );
      if (collaboration.isStarted) {
        if (!collaboration.hasVerifiedMembership ||
            collaboration.localAccountId != accountId) {
          _pendingCloudDocument = null;
          _setStatus(SyncStatus.localSaved);
          return;
        }
        _setStatus(SyncStatus.syncing);
        if (!collaboration.canEditCanvas) {
          if (!_isCurrent(generation)) return;
          _pendingCloudDocument = null;
          _setStatus(SyncStatus.localSaved);
          return;
        }
        // Keep binary preview preparation on the existing asset path, but make
        // the CRDT snapshot the only document write for collaborative rooms.
        final cloudDocument = await _prepareCloudDocument(
          doc,
          supabaseSync,
          generation: generation,
          accountId: accountId,
          cloudOperationEpoch: cloudOperationEpoch,
        );
        if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
            !_isCurrent(generation) ||
            !_accountIsCurrent(accountId)) {
          return;
        }
        final persisted = await collaboration.persistSnapshot(
          preparedDocument: cloudDocument,
        );
        if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
            !_isCurrent(generation) ||
            !_accountIsCurrent(accountId)) {
          return;
        }
        if (!persisted) {
          throw SyncException(
            'Collaboration room is offline; pending operations are queued.',
            collaboration.lastErrorMessage,
          );
        }
      } else {
        if (accountId == null) {
          _setStatus(SyncStatus.localSaved);
          return;
        }
        final metadata =
            (await _ref.read(localStorageServiceProvider).getProjects())
                .where((project) => project.id == doc.projectId)
                .firstOrNull;
        if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
            !_isCurrent(generation) ||
            !_accountIsCurrent(accountId)) {
          return;
        }
        if (metadata?.cloudOwnerId != accountId ||
            metadata?.isCollaborationRoom == true ||
            metadata?.status == ProjectStatus.trashed) {
          _setStatus(SyncStatus.localSaved);
          return;
        }
        await supabaseSync.verifyProjectOwnership(
          doc.projectId,
          expectedUserId: accountId,
        );
        if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
            !_isCurrent(generation) ||
            !_accountIsCurrent(accountId)) {
          return;
        }
        _setStatus(SyncStatus.syncing);
        final cloudDocument = await _prepareCloudDocument(
          doc,
          supabaseSync,
          generation: generation,
          accountId: accountId,
          cloudOperationEpoch: cloudOperationEpoch,
        );
        if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
            !_isCurrent(generation) ||
            !_accountIsCurrent(accountId)) {
          return;
        }
        await supabaseSync.syncDocumentSnapshot(
          cloudDocument,
          expectedUserId: accountId,
          isOperationCurrent: () =>
              _isCloudOperationCurrent(cloudOperationEpoch) &&
              _isCurrent(generation) &&
              _accountIsCurrent(accountId),
        );
        if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
            !_isCurrent(generation) ||
            !_accountIsCurrent(accountId)) {
          return;
        }
      }
      if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
          !_isCurrent(generation) ||
          !_accountIsCurrent(accountId)) {
        return;
      }
      _pendingCloudDocument = null;
      _cloudRetryTimer?.cancel();
      _cloudRetryCount = 0;
      _setStatus(SyncStatus.synced);
    } catch (error) {
      if (!_isCloudOperationCurrent(cloudOperationEpoch) ||
          !_isCurrent(generation) ||
          !_accountIsCurrent(accountId)) {
        return;
      }
      debugPrint('[AutosaveController] Remote sync failed: $error');
      _setStatus(
        SyncStatus.cloudPending,
        errorMessage: 'Cloud sync tertunda. Data lokal sudah tersimpan.',
      );
      if (_isRetryableCloudError(error)) {
        _scheduleCloudRetry(generation, accountId);
      }
    }
  }

  bool _isRetryableCloudError(Object error) {
    final cause = error is SyncException ? error.cause : error;
    final text = cause?.toString().toLowerCase() ?? '';
    return cause is TimeoutException ||
        cause is http.ClientException ||
        text.contains('network') ||
        text.contains('timeout') ||
        text.contains('failed to fetch');
  }

  void _cancelCloudRetry({bool clearPending = false}) {
    _cloudRetryGeneration++;
    _cloudRetryTimer?.cancel();
    _cloudRetryTimer = null;
    if (clearPending) _pendingCloudDocument = null;
  }

  void _scheduleCloudRetry(int generation, String? accountId) {
    if (_cloudRetryPaused ||
        _transitionPaused ||
        !_isCurrent(generation) ||
        !_accountIsCurrent(accountId) ||
        _cloudRetryCount >= 3 ||
        _pendingCloudDocument == null) {
      return;
    }
    _cloudRetryTimer?.cancel();
    final retryGeneration = ++_cloudRetryGeneration;
    const delays = [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ];
    final delay = delays[_cloudRetryCount++];
    _cloudRetryTimer = Timer(delay, () {
      if (retryGeneration != _cloudRetryGeneration ||
          !_isCurrent(generation) ||
          !_accountIsCurrent(accountId)) {
        return;
      }
      _cloudRetryTimer = null;
      if (_cloudRetryPaused || _transitionPaused) return;
      final pending = _pendingCloudDocument;
      if (pending != null) {
        _syncCloud(pending, generation: generation, accountId: accountId);
      }
    });
  }

  void _setStatus(SyncStatus status, {String? errorMessage}) {
    if (_disposeRequested || _disposed) return;
    _ref.read(syncStatusProvider.notifier).state = SyncState(
      status: status,
      errorMessage: errorMessage,
      lastSyncedAt: DateTime.now(),
    );
  }

  Future<void> dispose() async {
    if (_disposeRequested) {
      await _saveInFlight;
      return;
    }
    _disposeRequested = true;
    _debounceTimer?.cancel();
    _cloudRetryTimer?.cancel();
    _pendingCloudDocument = null;
    final inFlight = _saveInFlight;
    if (inFlight != null) await inFlight;
    final cloudInFlight = _cloudSyncInFlight;
    if (cloudInFlight != null) await cloudInFlight;
    _lifecycleGeneration++;
    _disposed = true;
  }
}
