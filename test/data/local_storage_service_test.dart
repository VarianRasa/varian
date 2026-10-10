import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/collaboration/domain/comment_notifications.dart';
import 'package:varian/features/canvas/commands/command_replay.dart';
import 'package:varian/features/canvas/domain/canvas_navigation.dart';
import 'package:varian/features/ai/domain/semantic_index.dart';
import 'package:varian/features/components/domain/component_library.dart';
import 'package:varian/features/publishing/domain/published_snapshot.dart';
import 'package:varian/features/review/domain/review_workflow.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/governance/domain/plugin_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips collaboration room metadata with a project', () {
    final metadata = LocalProjectMetadata(
      id: 'room-project',
      name: 'Shared board',
      createdAt: DateTime.utc(2026, 9, 9, 10),
      updatedAt: DateTime.utc(2026, 9, 9, 11),
      collaborationRoomCode: '482917',
      collaborationRole: 'editor',
      collaborationRoomExpiresAt: DateTime.utc(2026, 9, 10),
    );

    final restored = LocalProjectMetadata.fromJson(metadata.toJson());

    expect(restored.isCollaborationRoom, isTrue);
    expect(restored.collaborationRoomCode, '482917');
    expect(restored.collaborationRole, 'editor');
    expect(restored.collaborationRoomExpiresAt, DateTime.utc(2026, 9, 10));
  });

  test('round-trips a pending cloud metadata intent', () {
    final metadata = LocalProjectMetadata(
      id: 'cloud-project',
      name: 'Renamed locally',
      createdAt: DateTime.utc(2026, 9, 9),
      updatedAt: DateTime.utc(2026, 9, 10),
      isPinned: true,
      status: ProjectStatus.archived,
      cloudOwnerId: 'account-1',
      cloudMetadataSyncPending: true,
    );

    final restored = LocalProjectMetadata.fromJson(metadata.toJson());

    expect(restored.cloudMetadataSyncPending, isTrue);
    expect(restored.name, 'Renamed locally');
    expect(restored.isPinned, isTrue);
    expect(restored.status, ProjectStatus.archived);
  });

  test(
    'clears a cloud metadata intent only while its value is unchanged',
    () async {
      final storage = LocalStorageService();
      final intent = LocalProjectMetadata(
        id: 'cloud-project',
        name: 'Renamed locally',
        createdAt: DateTime.utc(2026, 9, 9),
        updatedAt: DateTime.utc(2026, 9, 10),
        cloudOwnerId: 'account-1',
        cloudMetadataSyncPending: true,
      );
      await storage.saveProjectMetadata(intent);

      await storage.clearCloudMetadataSyncPendingIfUnchanged(
        intent,
        expectedOwnerId: 'account-1',
      );
      final cleared = (await storage.getProjects()).single;

      expect(cleared.cloudMetadataSyncPending, isFalse);

      final newerIntent = cleared.copyWith(
        name: 'A newer local name',
        cloudMetadataSyncPending: true,
      );
      await storage.saveProjectMetadata(newerIntent);
      await storage.clearCloudMetadataSyncPendingIfUnchanged(
        cleared,
        expectedOwnerId: 'account-1',
      );

      final preserved = (await storage.getProjects()).single;
      expect(preserved.name, 'A newer local name');
      expect(preserved.cloudMetadataSyncPending, isTrue);
    },
  );

  test(
    'persists plugin registrations across storage service recreation',
    () async {
      final registry = PluginRegistry(clock: () => DateTime.utc(2026, 9, 14));
      registry.register(
        const PluginManifest(
          id: 'sample.plugin',
          name: 'Sample plugin',
          version: '1.0.0',
          permissions: [PluginPermission.readSelection],
        ),
      );
      registry.approve(
        'sample.plugin',
        permissions: {PluginPermission.readSelection},
      );

      final storage = LocalStorageService();
      await storage.savePluginRegistry(registry);

      final restored = await LocalStorageService().loadPluginRegistry(
        clock: () => DateTime.utc(2026, 9, 15),
      );
      final registration = restored.find('sample.plugin');

      expect(registration, isNotNull);
      expect(registration!.state, PluginRegistrationState.enabled);
      expect(registration.approvedPermissions, {
        PluginPermission.readSelection,
      });
      expect(registration.manifest.name, 'Sample plugin');

      await storage.clearPluginRegistry();
      expect((await storage.loadPluginRegistry()).registrations, isEmpty);
    },
  );

  test(
    'recovers asset library and folder caches from malformed JSON',
    () async {
      SharedPreferences.setMockInitialValues({
        'ccs_asset_library_project-1': '{not-json',
        'ccs_asset_library_folders_project-1': '[not-json',
      });
      final storage = LocalStorageService();

      expect(await storage.loadAssetLibrary('project-1'), isEmpty);
      expect(await storage.loadAssetLibraryFolders('project-1'), isEmpty);
    },
  );

  test(
    'drops asset library queue entries with raw surrounding whitespace',
    () async {
      SharedPreferences.setMockInitialValues({
        'ccs_asset_library_deletion_project-1':
            '{" asset-1 ":" project-1/library/asset.png "}',
        'ccs_asset_library_folder_deletion_project-1': '[" folder-1 "]',
        'ccs_asset_library_folder_upsert_project-1': '[" folder-1 "]',
      });
      final storage = LocalStorageService();

      expect(
        await storage.loadAssetLibraryDeletionTombstones('project-1'),
        isEmpty,
      );
      expect(
        await storage.loadAssetLibraryFolderDeletionTombstones('project-1'),
        isEmpty,
      );
      expect(
        await storage.loadAssetLibraryFolderUpsertQueue('project-1'),
        isEmpty,
      );
    },
  );

  test(
    'clearing an asset library also removes provider cache entries',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ccs_asset_library_provider_cache_project-1_fake_query',
        '{}',
      );

      await LocalStorageService().clearAssetLibrary('project-1');

      expect(
        prefs.containsKey(
          'ccs_asset_library_provider_cache_project-1_fake_query',
        ),
        isFalse,
      );
    },
  );

  test('saves a full document when browser payload fits', () async {
    final result = await LocalStorageService().saveDocument(
      CanvasDocument(
        projectId: 'p1',
        nodes: [
          CanvasNode(
            id: 'image',
            type: NodeType.image,
            x: 0,
            y: 0,
            width: 100,
            height: 100,
            payload: ImagePayload(url: 'https://cdn.example/image.png'),
          ),
        ],
        updatedAt: DateTime.now(),
      ),
    );

    expect(result, LocalSaveResult.full);
    expect(
      (await LocalStorageService().loadDocument('p1'))?.nodes,
      hasLength(1),
    );
  });

  test(
    'local document reload drops runtime media sources but keeps identities',
    () async {
      final audioReference = 'varian-media://durable/${'a' * 64}/original';
      final document = CanvasDocument(
        projectId: 'runtime-media-persistence',
        nodes: [
          CanvasNode(
            id: 'image',
            type: NodeType.image,
            x: 0,
            y: 0,
            width: 100,
            height: 100,
            payload: ImagePayload(
              assetId: 'image-asset',
              imageArtifactReference: 'varian-image://imageasset',
              localPath: r'C:\\runtime\\image.png',
              url: 'https://cdn.example/image.png',
            ),
          ),
          CanvasNode(
            id: 'file',
            type: NodeType.fileCard,
            x: 120,
            y: 0,
            width: 100,
            height: 100,
            payload: FilePayload(
              assetId: 'file-asset',
              artifactReference: 'varian-file://fileasset',
              localPath: r'C:\\runtime\\brief.txt',
              base64Data: 'c2hvdWxkLW5vdC1wZXJzaXN0',
              remoteUrl: 'https://cdn.example/brief.txt',
            ),
          ),
          CanvasNode(
            id: 'audio',
            type: NodeType.audioCard,
            x: 240,
            y: 0,
            width: 100,
            height: 100,
            payload: AudioPayload(
              assetId: 'audio-asset',
              storagePath: 'runtime-media-persistence/audio/track.mp3',
              audioArtifactReference: audioReference,
              audioPath: r'C:\\runtime\\track.mp3',
              audioUrl: 'https://cdn.example/track.mp3',
            ),
          ),
          CanvasNode(
            id: 'video',
            type: NodeType.videoCard,
            x: 360,
            y: 0,
            width: 100,
            height: 100,
            payload: VideoPayload(
              assetId: 'video-asset',
              storagePath: 'runtime-media-persistence/video/demo.mp4',
              videoArtifactReference: 'varian-video://videoasset',
              videoPath: 'memory://transient-video',
              videoUrl: 'blob:https://example.test/transient-video',
            ),
          ),
        ],
        updatedAt: DateTime.utc(2026, 9, 25),
      );

      final result = await LocalStorageService().saveDocument(document);
      final restored = await LocalStorageService().loadDocument(
        document.projectId,
      );

      expect(result, LocalSaveResult.full);
      expect(restored, isNotNull);

      final image = restored!.nodes[0].payload as ImagePayload;
      expect(image.assetId, 'image-asset');
      expect(image.imageArtifactReference, 'varian-image://imageasset');
      expect(image.localPath, isNull);
      expect(image.url, isNull);

      final file = restored.nodes[1].payload as FilePayload;
      expect(file.assetId, 'file-asset');
      expect(file.artifactReference, 'varian-file://fileasset');
      expect(file.localPath, isNull);
      expect(file.base64Data, isNull);
      expect(file.remoteUrl, isNull);

      final audio = restored.nodes[2].payload as AudioPayload;
      expect(audio.assetId, 'audio-asset');
      expect(audio.storagePath, 'runtime-media-persistence/audio/track.mp3');
      expect(audio.audioArtifactReference, audioReference);
      expect(audio.audioPath, isNull);
      expect(audio.audioUrl, isNull);

      final video = restored.nodes[3].payload as VideoPayload;
      expect(video.assetId, 'video-asset');
      expect(video.storagePath, 'runtime-media-persistence/video/demo.mp4');
      expect(video.videoArtifactReference, 'varian-video://videoasset');
      expect(video.videoPath, isNull);
      expect(video.videoUrl, isNull);
    },
  );

  test('purges durable records through the local storage lifecycle', () async {
    final directory = await Directory.systemTemp.createTemp(
      'varian-local-purge-',
    );
    final path = '${directory.path}${Platform.pathSeparator}runtime.sqlite';
    final database = ProjectDurableDatabase(NativeDatabase(File(path)));
    final durableStore = DurableProjectStore(database: database);
    await durableStore.ready;
    addTearDown(() async {
      await durableStore.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final storage = LocalStorageService(durableProjectStore: durableStore);
    await storage.saveProjectMetadata(
      LocalProjectMetadata(
        id: 'durable-purge',
        name: 'Durable purge',
        createdAt: DateTime.utc(2026, 9, 14),
        updatedAt: DateTime.utc(2026, 9, 14),
      ),
    );
    await durableStore.writeDocument(
      projectId: 'durable-purge',
      documentJson: jsonEncode({'projectId': 'durable-purge'}),
    );

    await storage.purgeProject('durable-purge');

    expect(await durableStore.readDocument('durable-purge'), isNull);
  });

  test('purges every project-scoped legacy cache', () async {
    final storage = LocalStorageService();
    const projectId = 'legacy-purge-all';
    final metadata = LocalProjectMetadata(
      id: projectId,
      name: 'Legacy purge all',
      createdAt: DateTime.utc(2026, 9, 14),
      updatedAt: DateTime.utc(2026, 9, 14),
    );
    await storage.saveProjectMetadata(metadata);
    final document = CanvasDocument(
      projectId: projectId,
      updatedAt: metadata.updatedAt,
    );
    await storage.saveDocument(document);
    await storage.saveVersion(projectId, document, description: 'Version');
    await storage.saveAutoCheckpoint(projectId, document);
    await storage.saveAIJobHistory(projectId, const []);
    await storage.savePublishedSnapshot(
      PublishedSnapshot.publish(
        document,
        publishedBy: 'test-user',
        id: 'published-$projectId',
        publishedAt: metadata.updatedAt,
      ),
    );
    await storage.saveReviewWorkflow(ReviewWorkflow.empty(projectId));
    await storage.saveSemanticIndex(SemanticIndex.empty(projectId));
    await storage.saveAICanvasTransactions(projectId, const []);
    await storage.saveComponentLibrary(projectId, const ComponentLibrary());
    await storage.saveCanvasNavigation(
      projectId,
      const CanvasNavigationState(),
    );
    await storage.saveCommentNotifications(projectId, 'user-1', const []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'ccs_asset_library_provider_cache_${Uri.encodeComponent(projectId)}_cache',
      '{}',
    );

    await storage.purgeProject(projectId);

    for (final key in [
      'ccs_doc_$projectId',
      'ccs_journal_$projectId',
      'ccs_versions_$projectId',
      'ccs_auto_checkpoints_$projectId',
      'ccs_ai_jobs_$projectId',
      'ccs_published_snapshot_$projectId',
      'ccs_review_workflow_$projectId',
      'ccs_semantic_index_$projectId',
      'ccs_ai_canvas_transactions_$projectId',
      'ccs_component_library_$projectId',
      'ccs_canvas_navigation_$projectId',
      'ccs_comment_notifications_$projectId-user-1',
    ]) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
    expect(
      prefs.getKeys().where(
        (key) => key.startsWith(
          'ccs_asset_library_provider_cache_${Uri.encodeComponent(projectId)}_',
        ),
      ),
      isEmpty,
    );
    expect(await storage.getProjects(), isEmpty);
  });

  test('does not remove metadata when durable project purge fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'varian-local-purge-failure-',
    );
    final path = '${directory.path}${Platform.pathSeparator}runtime.sqlite';
    final database = ProjectDurableDatabase(NativeDatabase(File(path)));
    final durableStore = DurableProjectStore(database: database);
    await durableStore.ready;
    await durableStore.close();
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final storage = LocalStorageService(durableProjectStore: durableStore);
    await storage.saveProjectMetadata(
      LocalProjectMetadata(
        id: 'durable-purge-failure',
        name: 'Durable purge failure',
        createdAt: DateTime.utc(2026, 9, 14),
        updatedAt: DateTime.utc(2026, 9, 14),
      ),
    );

    await expectLater(
      storage.purgeProject('durable-purge-failure'),
      throwsA(isA<StateError>()),
    );

    expect(
      (await storage.getProjects()).map((project) => project.id),
      contains('durable-purge-failure'),
    );
  });

  test('moves and purges multiple projects in one storage operation', () async {
    final storage = LocalStorageService();
    final createdAt = DateTime.utc(2026, 9, 14, 10);
    for (final id in ['first', 'second', 'keep']) {
      await storage.saveProjectMetadata(
        LocalProjectMetadata(
          id: id,
          name: id,
          createdAt: createdAt,
          updatedAt: createdAt,
          isPinned: id != 'keep',
        ),
      );
      await storage.saveDocument(
        CanvasDocument(projectId: id, updatedAt: createdAt),
      );
    }

    await storage.moveProjectsToTrash(['first', 'second']);

    final moved = await storage.getProjects();
    expect(
      moved.where((project) => project.status == ProjectStatus.trashed),
      hasLength(2),
    );
    expect(
      moved.firstWhere((project) => project.id == 'keep').status,
      ProjectStatus.active,
    );
    expect(
      moved
          .where((project) => project.status == ProjectStatus.trashed)
          .every((project) => !project.isPinned),
      isTrue,
    );

    await storage.purgeProjects(['first', 'second']);

    expect((await storage.getProjects()).map((project) => project.id), [
      'keep',
    ]);
    expect(await storage.loadDocument('first'), isNull);
    expect(await storage.loadDocument('second'), isNull);
    expect(await storage.loadDocument('keep'), isNotNull);
  });

  test(
    'keeps single-project trash operations strict for missing IDs',
    () async {
      expect(
        LocalStorageService().moveProjectToTrash('missing'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('persists and clears the collaboration operation queue', () async {
    final operation = CrdtOperation.create(
      projectId: 'queued-project',
      dot: const CrdtDot(actorId: 'actor', counter: 1),
      dependencies: CrdtVersionVector(),
      kind: CrdtOperationKind.nodeDelete,
      targetId: 'node-1',
    );
    final storage = LocalStorageService();

    await storage.saveCollaborationQueue('queued-project', [operation]);

    final restored = await storage.loadCollaborationQueue('queued-project');
    expect(restored, hasLength(1));
    expect(restored.single.opId, operation.opId);
    expect(restored.single.kind, CrdtOperationKind.nodeDelete);

    await storage.clearCollaborationQueue('queued-project');
    expect(await storage.loadCollaborationQueue('queued-project'), isEmpty);
  });

  test('persists comment notification preferences and inbox', () async {
    final storage = LocalStorageService();
    const preferences = CommentNotificationPreferences(
      mentions: true,
      replies: false,
      unresolvedOnly: true,
    );
    final notification = CommentNotification(
      id: 'notification-1',
      projectId: 'project-1',
      commentId: 'comment-1',
      type: CommentNotificationType.mention,
      actorId: 'author-2',
      actorName: 'Calm Panda 02',
      message: 'You were mentioned',
      createdAt: DateTime.utc(2026, 9, 13, 8),
    );

    await storage.saveCommentNotificationPreferences('author-1', preferences);
    await storage.saveCommentNotifications('project-1', 'author-1', [
      notification,
    ]);

    final restoredPreferences = await storage
        .loadCommentNotificationPreferences('author-1');
    final restoredNotifications = await storage.loadCommentNotifications(
      'project-1',
      'author-1',
    );

    expect(restoredPreferences.unresolvedOnly, isTrue);
    expect(restoredPreferences.replies, isFalse);
    expect(restoredNotifications.single.id, 'notification-1');
    expect(restoredNotifications.single.type, CommentNotificationType.mention);
  });

  test('persists Mermaid source and native lifecycle metadata', () async {
    const renderConfig = MermaidRenderConfig();
    final document = CanvasDocument(
      projectId: 'mermaid-persistence',
      nodes: [
        CanvasNode(
          id: 'mermaid-source',
          type: NodeType.mermaid,
          x: 40,
          y: 60,
          width: 320,
          height: 220,
          visible: false,
          payload: MermaidPayload(
            source: 'flowchart LR\n  A[One] --> B[Two]',
            diagramType: 'flowchart',
            renderMode: MermaidRenderMode.native,
            sourceRevision: 2,
            conversionStatus: MermaidConversionStatus.nativeEdited,
            nativeNodeIds: const ['native-a', 'native-b'],
            nativeEdgeIds: const ['native-edge'],
            cachedSvg: '<svg xmlns="http://www.w3.org/2000/svg"/>',
            cachedSvgRevision: 2,
            cachedSvgConfigKey: renderConfig.cacheKey,
          ),
        ),
      ],
      updatedAt: DateTime(2026, 9, 4),
    );

    await LocalStorageService().saveDocument(document);
    final restored = await LocalStorageService().loadDocument(
      document.projectId,
    );
    final restoredNode = restored!.nodes.single;
    final payload = restoredNode.payload as MermaidPayload;

    expect(restoredNode.visible, isFalse);
    expect(payload.source, 'flowchart LR\n  A[One] --> B[Two]');
    expect(payload.renderMode, MermaidRenderMode.native);
    expect(payload.conversionStatus, MermaidConversionStatus.nativeEdited);
    expect(payload.nativeNodeIds, ['native-a', 'native-b']);
    expect(payload.nativeEdgeIds, ['native-edge']);
    expect(payload.cachedSvgRevision, 2);
    expect(payload.cachedSvgConfigKey, renderConfig.cacheKey);
  });

  test('persists the complete Mermaid native graph atomically', () async {
    final source = CanvasNode(
      id: 'mermaid-source',
      type: NodeType.mermaid,
      x: 40,
      y: 60,
      width: 320,
      height: 220,
      visible: false,
      payload: MermaidPayload(
        source: 'sequenceDiagram\n  Alice->>Bob: Hello',
        diagramType: 'sequencediagram',
        renderMode: MermaidRenderMode.native,
        conversionStatus: MermaidConversionStatus.converted,
        nativeNodeIds: const [
          'mermaid-source__mermaid_node_0',
          'mermaid-source__mermaid_node_1',
        ],
        nativeEdgeIds: const ['mermaid-source__mermaid_edge_0'],
        cachedSvg: '<svg xmlns="http://www.w3.org/2000/svg"/>',
        cachedSvgRevision: 0,
        cachedSvgConfigKey: const MermaidRenderConfig().cacheKey,
        rendererVersion: 'merman-0.7.0',
      ),
    );
    final first = CanvasNode(
      id: 'mermaid-source__mermaid_node_0',
      type: NodeType.rectangle,
      x: 100,
      y: 120,
      width: 120,
      height: 60,
      mermaidSourceId: source.id,
      payload: ShapePayload(),
    );
    final second = CanvasNode(
      id: 'mermaid-source__mermaid_node_1',
      type: NodeType.ellipse,
      x: 300,
      y: 240,
      width: 120,
      height: 60,
      mermaidSourceId: source.id,
      payload: ShapePayload(),
    );
    const edge = CanvasEdge(
      id: 'mermaid-source__mermaid_edge_0',
      sourceNodeId: 'mermaid-source__mermaid_node_0',
      targetNodeId: 'mermaid-source__mermaid_node_1',
      mermaidSourceId: 'mermaid-source',
    );
    final document = CanvasDocument(
      projectId: 'mermaid-native-persistence',
      nodes: [source, first, second],
      edges: [edge],
      updatedAt: DateTime(2026, 9, 5),
    );

    await LocalStorageService().saveDocument(document);
    final restored = await LocalStorageService().loadDocument(
      document.projectId,
    );

    expect(restored, isNotNull);
    expect(restored!.nodes, hasLength(3));
    expect(restored.edges, hasLength(1));
    final restoredPayload = restored.nodes.first.payload as MermaidPayload;
    expect(restored.nodes.first.visible, isFalse);
    expect(restoredPayload.source, (source.payload as MermaidPayload).source);
    expect(restoredPayload.renderMode, MermaidRenderMode.native);
    final sourcePayload = source.payload as MermaidPayload;
    expect(restoredPayload.nativeNodeIds, sourcePayload.nativeNodeIds);
    expect(restoredPayload.nativeEdgeIds, sourcePayload.nativeEdgeIds);
    expect(restored.nodes[1].mermaidSourceId, source.id);
    expect(restored.edges.single.mermaidSourceId, source.id);
  });

  test(
    'project lifecycle and named versions survive a fresh storage service',
    () async {
      final storage = LocalStorageService();
      final document = CanvasDocument(
        projectId: 'lifecycle-project',
        nodes: [
          CanvasNode(
            id: 'shape',
            type: NodeType.rectangle,
            x: 10,
            y: 20,
            width: 100,
            height: 80,
            payload: ShapePayload(),
          ),
        ],
        updatedAt: DateTime(2026, 8, 26, 10),
      );
      await storage.saveProjectMetadata(
        LocalProjectMetadata(
          id: document.projectId,
          name: 'Lifecycle project',
          createdAt: DateTime(2026, 8, 26),
          updatedAt: document.updatedAt,
        ),
      );
      await storage.saveDocument(document);
      await storage.setProjectPinned(document.projectId, true);
      await storage.archiveProject(document.projectId);

      final archived = (await LocalStorageService().getProjects()).single;
      expect(archived.isPinned, isTrue);
      expect(archived.status, ProjectStatus.archived);

      final version = await storage.saveVersion(
        document.projectId,
        document,
        description: 'Client review ready',
      );
      final reloaded = LocalStorageService();
      expect(
        (await reloaded.loadVersions(document.projectId)).single.id,
        version.id,
      );
      expect(
        (await reloaded.loadVersions(document.projectId)).single.description,
        'Client review ready',
      );

      final duplicate = await storage.duplicateProject(document.projectId);
      expect(duplicate.id, isNot(document.projectId));
      expect(
        (await reloaded.loadDocument(duplicate.id))?.projectId,
        duplicate.id,
      );
      expect(await reloaded.loadVersions(duplicate.id), isEmpty);

      await storage.deleteProject(document.projectId);
      expect(
        (await reloaded.getProjects())
            .singleWhere((p) => p.id == document.projectId)
            .status,
        ProjectStatus.trashed,
      );
      expect(await reloaded.loadDocument(document.projectId), isNotNull);

      await storage.restoreProject(document.projectId);
      expect(
        (await reloaded.getProjects())
            .singleWhere((p) => p.id == document.projectId)
            .status,
        ProjectStatus.active,
      );

      await storage.purgeProject(document.projectId);
      expect(
        (await reloaded.getProjects()).any((p) => p.id == document.projectId),
        isFalse,
      );
      expect(await reloaded.loadDocument(document.projectId), isNull);
      expect(await reloaded.loadVersions(document.projectId), isEmpty);
    },
  );

  test(
    'auto checkpoints survive restart, deduplicate, and stay out of branches',
    () async {
      final storage = LocalStorageService();
      const projectId = 'auto-checkpoint-project';
      final document = CanvasDocument(
        projectId: projectId,
        nodes: [
          CanvasNode(
            id: 'shape',
            type: NodeType.rectangle,
            x: 10,
            y: 20,
            width: 100,
            height: 80,
            payload: ShapePayload(),
          ),
        ],
        updatedAt: DateTime.utc(2026, 9, 13, 10),
      );
      await storage.saveProjectMetadata(
        LocalProjectMetadata(
          id: projectId,
          name: 'Auto checkpoint project',
          createdAt: document.updatedAt,
          updatedAt: document.updatedAt,
        ),
      );

      final replay = CommandReplayLog(
        projectId: projectId,
        createdAt: DateTime.utc(2026, 9, 13, 10),
      );
      final first = await storage.saveAutoCheckpoint(
        projectId,
        document,
        commandReplay: replay,
      );
      expect(first, isNotNull);
      expect(
        await storage.saveAutoCheckpoint(
          projectId,
          document,
          commandReplay: replay,
        ),
        isNull,
      );

      final changed = document.copyWith(
        nodes: [document.nodes.single.copyWith(x: 42)],
        updatedAt: DateTime.utc(2026, 9, 13, 10, 1),
      );
      final second = await storage.saveAutoCheckpoint(
        projectId,
        changed,
        commandReplay: replay,
      );
      expect(second, isNotNull);

      final reloaded = LocalStorageService();
      final checkpoints = await reloaded.loadAutoCheckpoints(projectId);
      expect(checkpoints, hasLength(2));
      expect(checkpoints.last.document.nodes.single.x, 42);
      expect(checkpoints.last.commandReplay?.projectId, projectId);

      final branch = await reloaded.duplicateProjectFromDocument(
        projectId,
        checkpoints.last.document,
        name: 'Auto checkpoint branch',
      );
      expect((await reloaded.loadDocument(branch.id))?.projectId, branch.id);
      expect(await reloaded.loadAutoCheckpoints(branch.id), isEmpty);

      await storage.purgeProject(projectId);
      expect(await reloaded.loadAutoCheckpoints(projectId), isEmpty);
    },
  );
}
