import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/collaboration/domain/crdt_engine.dart';
import 'package:varian/features/collaboration/domain/sync_models.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';
import 'package:varian/features/collaboration/state/collaboration_provider.dart';
import 'package:varian/features/collaboration/state/collaboration_session_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<({ProviderContainer container, DurableProjectStore store})>
  createContainer({
    bool allowInvalidAssetManifest = false,
    CollaborationRole? verifiedRole = CollaborationRole.owner,
  }) async {
    final store = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(null),
        durableProjectStoreProvider.overrideWithValue(store),
        if (verifiedRole != null)
          collaborationVerifiedRoleForTestingProvider.overrideWithValue(
            verifiedRole,
          ),
        if (allowInvalidAssetManifest)
          documentAssetsProvider.overrideWith(
            (ref) => _UnvalidatedDocumentAssetsNotifier(),
          ),
      ],
    );
    return (container: container, store: store);
  }

  Future<void> disposeContainer(
    ({ProviderContainer container, DurableProjectStore store}) owned,
  ) async {
    owned.container.dispose();
    await owned.store.close();
  }

  test(
    'rejects malformed initial assets without starting the session',
    () async {
      final asset = DocumentAsset(
        id: 'asset-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.remote,
        name: 'Image',
        mimeType: 'image/png',
        createdAt: DateTime.utc(2026, 9, 27),
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final invalidDocument = CanvasDocument(
        projectId: 'invalid-initial-assets-project',
        assets: DocumentAssetManifest(entries: {'wrong-key': asset}),
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final controller = owned.container.read(
        collaborationSessionProvider(invalidDocument.projectId).notifier,
      );

      await expectLater(
        controller.start(
          initialDocument: invalidDocument,
          userId: 'actor-a',
          userName: 'A',
          userColor: Colors.blue,
        ),
        throwsFormatException,
      );

      expect(controller.isStarted, isFalse);
    },
  );

  test(
    'rejects malformed asset manifest transitions before queuing CRDT ops',
    () async {
      final asset = DocumentAsset(
        id: 'asset-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.remote,
        name: 'Image',
        mimeType: 'image/png',
        createdAt: DateTime.utc(2026, 9, 27),
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final manifest = DocumentAssetManifest(entries: {'asset-1': asset});
      final document = CanvasDocument(
        projectId: 'asset-transition-project',
        assets: manifest,
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final owned = await createContainer(allowInvalidAssetManifest: true);
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;
      final assets = container.read(documentAssetsProvider.notifier);
      assets.setManifest(manifest);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      assets.setManifest(
        DocumentAssetManifest(
          entries: {'wrong-key': asset.copyWith(id: 'asset-2')},
        ),
      );

      expect(controller.pendingOperationDetails, isEmpty);
      expect(controller.syncStatus, CollaborationSyncStatus.failed);
      expect(controller.lastErrorMessage, contains('does not match asset ID'));
    },
  );

  test(
    'rejects prepared documents with invalid asset identities before merge',
    () async {
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;
      final controller = container.read(
        collaborationSessionProvider(
          'prepared-invalid-assets-project',
        ).notifier,
      );
      await controller.start(
        initialDocument: CanvasDocument(
          projectId: 'prepared-invalid-assets-project',
          updatedAt: DateTime.utc(2026, 9, 27),
        ),
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );
      final asset = DocumentAsset(
        id: 'asset-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.remote,
        name: 'Image',
        mimeType: 'image/png',
        createdAt: DateTime.utc(2026, 9, 27),
        updatedAt: DateTime.utc(2026, 9, 27),
      );

      expect(
        controller.applyPreparedDocumentForTesting(
          CanvasDocument(
            projectId: 'prepared-invalid-assets-project',
            assets: DocumentAssetManifest(entries: {'wrong-key': asset}),
            updatedAt: DateTime.utc(2026, 9, 27),
          ),
        ),
        isFalse,
      );
      expect(controller.pendingOperationDetails, isEmpty);
      expect(controller.lastErrorMessage, contains('does not match asset ID'));
    },
  );

  test(
    'rejects malformed previous asset manifests before queuing CRDT ops',
    () async {
      final asset = DocumentAsset(
        id: 'asset-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.remote,
        name: 'Image',
        mimeType: 'image/png',
        createdAt: DateTime.utc(2026, 9, 27),
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final validManifest = DocumentAssetManifest(entries: {'asset-1': asset});
      final document = CanvasDocument(
        projectId: 'invalid-previous-asset-transition-project',
        assets: validManifest,
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final owned = await createContainer(allowInvalidAssetManifest: true);
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;
      final assets = container.read(documentAssetsProvider.notifier);
      assets.setManifest(validManifest);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      assets.setManifest(DocumentAssetManifest(entries: {'wrong-key': asset}));
      assets.setManifest(validManifest);

      expect(controller.pendingOperationDetails, isEmpty);
      expect(controller.syncStatus, CollaborationSyncStatus.failed);
      expect(controller.lastErrorMessage, contains('does not match asset ID'));
    },
  );

  test(
    'coalesces rapid movement updates into one pending node operation',
    () async {
      final document = _drawingDocument();
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;

      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      var current = document.nodes.single;
      for (var index = 1; index <= 159; index++) {
        current = current.copyWith(x: index.toDouble());
        container
            .read(documentNodesProvider.notifier)
            .updateTransientNode(current);
      }

      expect(controller.state.pendingOperations, equals(1));
    },
  );

  test(
    'keeps the generated local display name in the active session',
    () async {
      final document = _drawingDocument();
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;

      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'Amber Fox 42',
        userColor: Colors.blue,
      );

      expect(controller.localUserName, 'Amber Fox 42');
    },
  );

  test('does not queue canvas edits without verified membership', () async {
    final document = _drawingDocument();
    final owned = await createContainer(verifiedRole: null);
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    container
        .read(documentNodesProvider.notifier)
        .updateTransientNode(document.nodes.single.copyWith(x: 42));

    expect(controller.hasVerifiedMembership, isFalse);
    expect(controller.canEditCanvas, isFalse);
    expect(controller.pendingOperationDetails, isEmpty);
  });

  test('does not queue canvas edits for a verified viewer', () async {
    final document = _drawingDocument();
    final owned = await createContainer(verifiedRole: CollaborationRole.viewer);
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    container
        .read(documentNodesProvider.notifier)
        .updateTransientNode(document.nodes.single.copyWith(x: 42));

    expect(controller.hasVerifiedMembership, isTrue);
    expect(controller.canEditCanvas, isFalse);
    expect(controller.pendingOperationDetails, isEmpty);
  });

  test(
    'queues a stroke operation for a local Drawing Paper stroke edit',
    () async {
      final document = _drawingDocument();
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;

      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      final paper = document.nodes.single;
      final payload = paper.payload as DrawingPaperPayload;
      const stroke = DrawingStroke(
        id: 'stroke-a',
        brush: StudioBrushCategory.gPen,
        color: Colors.black,
        size: 4,
        opacity: 1,
        points: [
          DrawingStrokePoint(x: 10, y: 10),
          DrawingStrokePoint(x: 30, y: 20),
        ],
      );
      final updatedPayload = payload.copyWith(
        layers: [
          payload.layers.single.copyWith(strokes: [stroke]),
        ],
        rasterRevision: payload.rasterRevision + 1,
      );

      container
          .read(documentNodesProvider.notifier)
          .updateTransientNode(paper.copyWith(payload: updatedPayload));

      expect(controller.state.pendingOperations, equals(1));
    },
  );

  test('queues a raster operation for a local Drawing Paper edit', () async {
    final document = _drawingDocument();
    final owned = await createContainer();
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    final paper = document.nodes.single;
    final payload = paper.payload as DrawingPaperPayload;
    const raster = RasterEditOperation(
      id: 'raster-fill-1',
      kind: RasterEditKind.bucketFill,
      seedPoint: Offset(12, 18),
      color: Color(0xFF00FF00),
    );
    final updatedPayload = payload.copyWith(
      rasterRevision: payload.rasterRevision + 1,
      rasterOperations: [raster],
    );

    container
        .read(documentNodesProvider.notifier)
        .updateTransientNode(paper.copyWith(payload: updatedPayload));

    expect(controller.pendingOperationDetails, hasLength(1));
    expect(
      controller.pendingOperationDetails.single.kind,
      CrdtOperationKind.rasterOperation,
    );
    expect(
      controller.pendingOperationDetails.single.value['pageId'],
      'root-page',
    );
    expect(
      controller.pendingOperationDetails.single.value['operation']['id'],
      raster.id,
    );
  });

  test('queues a raster reset when a Drawing Paper page is cleared', () async {
    const raster = RasterEditOperation(
      id: 'raster-clear-me',
      kind: RasterEditKind.bucketFill,
      seedPoint: Offset(12, 18),
      color: Color(0xFF00FF00),
    );
    final base = _drawingDocument();
    final initialPayload = base.nodes.single.payload as DrawingPaperPayload;
    final document = base.copyWith(
      nodes: [
        base.nodes.single.copyWith(
          payload: initialPayload.copyWith(rasterOperations: [raster]),
        ),
      ],
    );
    final owned = await createContainer();
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    final paper = document.nodes.single;
    final payload = paper.payload as DrawingPaperPayload;
    final updatedPayload = payload.copyWith(
      rasterRevision: payload.rasterRevision + 1,
      rasterOperations: const [],
    );
    container
        .read(documentNodesProvider.notifier)
        .updateTransientNode(paper.copyWith(payload: updatedPayload));

    expect(controller.pendingOperationDetails, hasLength(1));
    expect(
      controller.pendingOperationDetails.single.kind,
      CrdtOperationKind.rasterReset,
    );
    expect(
      controller.pendingOperationDetails.single.value['pageId'],
      'root-page',
    );
  });

  test(
    'queues a raster reset before re-adding survivors after partial removal',
    () async {
      const firstRaster = RasterEditOperation(
        id: 'raster-remove-me',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(4, 4),
        color: Color(0xFF00FF00),
      );
      const survivor = RasterEditOperation(
        id: 'raster-survivor',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(8, 8),
        color: Color(0xFFFF0000),
      );
      final base = _drawingDocument();
      final initialPayload = base.nodes.single.payload as DrawingPaperPayload;
      final document = base.copyWith(
        nodes: [
          base.nodes.single.copyWith(
            payload: initialPayload.copyWith(
              rasterOperations: [firstRaster, survivor],
            ),
          ),
        ],
      );
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;

      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      final paper = document.nodes.single;
      final payload = paper.payload as DrawingPaperPayload;
      final updatedPayload = payload.copyWith(
        rasterRevision: payload.rasterRevision + 1,
        rasterOperations: [survivor],
      );
      container
          .read(documentNodesProvider.notifier)
          .updateTransientNode(paper.copyWith(payload: updatedPayload));

      expect(controller.pendingOperationDetails, hasLength(2));
      expect(
        controller.pendingOperationDetails.map((operation) => operation.kind),
        [CrdtOperationKind.rasterReset, CrdtOperationKind.rasterOperation],
      );
      expect(
        controller.pendingOperationDetails.last.value['operation']['id'],
        survivor.id,
      );
    },
  );

  test('queues a stroke replacement as a stroke upsert', () async {
    final base = _drawingDocument();
    final original = _nestedStroke('replace-stroke', 10);
    final initialPayload = base.nodes.single.payload as DrawingPaperPayload;
    final document = base.copyWith(
      nodes: [
        base.nodes.single.copyWith(
          payload: initialPayload.copyWith(
            layers: [
              initialPayload.layers.single.copyWith(strokes: [original]),
            ],
          ),
        ),
      ],
    );
    final owned = await createContainer();
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    final paper = document.nodes.single;
    final payload = paper.payload as DrawingPaperPayload;
    final replacement = original.copyWith(
      points: const [
        DrawingStrokePoint(x: 110, y: 10),
        DrawingStrokePoint(x: 140, y: 30),
      ],
    );
    final updatedPayload = payload.copyWith(
      rasterRevision: payload.rasterRevision + 1,
      layers: [
        payload.layers.single.copyWith(strokes: [replacement]),
      ],
    );

    container
        .read(documentNodesProvider.notifier)
        .updateTransientNode(paper.copyWith(payload: updatedPayload));

    expect(controller.pendingOperationDetails, hasLength(1));
    final operation = controller.pendingOperationDetails.single;
    expect(operation.kind, CrdtOperationKind.strokeUpsert);
    expect(operation.value['pageId'], 'root-page');
    expect(operation.value['layerId'], 'layer-1');
    expect(operation.value['strokeId'], replacement.id);
    expect(operation.value['stroke'], replacement.toJson());
  });

  test('queues a stroke deletion as a stroke tombstone', () async {
    final base = _drawingDocument();
    final original = _nestedStroke('delete-stroke', 10);
    final initialPayload = base.nodes.single.payload as DrawingPaperPayload;
    final document = base.copyWith(
      nodes: [
        base.nodes.single.copyWith(
          payload: initialPayload.copyWith(
            layers: [
              initialPayload.layers.single.copyWith(strokes: [original]),
            ],
          ),
        ),
      ],
    );
    final owned = await createContainer();
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    final paper = document.nodes.single;
    final payload = paper.payload as DrawingPaperPayload;
    final updatedPayload = payload.copyWith(
      rasterRevision: payload.rasterRevision + 1,
      layers: [payload.layers.single.copyWith(strokes: const [])],
    );

    container
        .read(documentNodesProvider.notifier)
        .updateTransientNode(paper.copyWith(payload: updatedPayload));

    expect(controller.pendingOperationDetails, hasLength(1));
    final operation = controller.pendingOperationDetails.single;
    expect(operation.kind, CrdtOperationKind.strokeDelete);
    expect(operation.value, {
      'pageId': 'root-page',
      'layerId': 'layer-1',
      'strokeId': original.id,
    });
  });

  test(
    'falls back to a node upsert when a Drawing Paper layer changes',
    () async {
      final document = _drawingDocument();
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;

      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      final paper = document.nodes.single;
      final payload = paper.payload as DrawingPaperPayload;
      final updatedPayload = payload.copyWith(
        layers: [payload.layers.single.copyWith(id: 'layer-replaced')],
      );

      container
          .read(documentNodesProvider.notifier)
          .updateTransientNode(paper.copyWith(payload: updatedPayload));

      expect(controller.pendingOperationDetails, hasLength(1));
      expect(
        controller.pendingOperationDetails.single.kind,
        CrdtOperationKind.nodeUpsert,
      );
    },
  );

  test(
    'preserves stroke deletes and raster resets when a page moves',
    () async {
      const stroke = DrawingStroke(
        id: 'mixed-transition-stroke',
        brush: StudioBrushCategory.gPen,
        color: Colors.black,
        size: 4,
        opacity: 1,
        points: [
          DrawingStrokePoint(x: 1, y: 2),
          DrawingStrokePoint(x: 3, y: 4),
        ],
      );
      const raster = RasterEditOperation(
        id: 'mixed-transition-raster',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(12, 18),
        color: Color(0xFF00FF00),
      );
      final base = _drawingDocument();
      final initialPayload = base.nodes.single.payload as DrawingPaperPayload;
      final pagePayload = DrawingPaperPayload(
        layers: [
          const DrawingLayer(id: 'page-layer', name: 'Ink', strokes: [stroke]),
        ],
        rasterOperations: [raster],
      );
      final document = base.copyWith(
        nodes: [
          base.nodes.single.copyWith(
            payload: initialPayload.copyWith(
              studioPages: [
                DrawingPaperPage(
                  id: 'page-a',
                  position: Offset.zero,
                  payload: pagePayload,
                ),
              ],
            ),
          ),
        ],
      );
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;
      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      final paper = document.nodes.single;
      final payload = paper.payload as DrawingPaperPayload;
      final page = payload.studioPages.single;
      final updatedPagePayload = page.payload.copyWith(
        rasterRevision: page.payload.rasterRevision + 1,
        layers: [page.payload.layers.single.copyWith(strokes: const [])],
        rasterOperations: const [],
      );
      final updated = paper.copyWith(
        payload: payload.copyWith(
          studioPages: [
            page.copyWith(
              position: const Offset(24, 36),
              payload: updatedPagePayload,
            ),
          ],
        ),
      );

      container
          .read(documentNodesProvider.notifier)
          .updateTransientNode(updated);

      expect(
        controller.pendingOperationDetails.map((operation) => operation.kind),
        containsAllInOrder([
          CrdtOperationKind.nodeUpsert,
          CrdtOperationKind.strokeDelete,
          CrdtOperationKind.rasterReset,
        ]),
      );
      final remote = CrdtDocumentSession.fromDocument(
        document,
        actorId: 'actor-b',
      );
      for (final operation in controller.pendingOperationDetails) {
        remote.applyRemote(operation);
      }
      final remotePage =
          (remote.document.nodes.single.payload as DrawingPaperPayload)
              .studioPages
              .single
              .payload;
      expect(remotePage.layers.single.strokes, isEmpty);
      expect(remotePage.rasterOperations, isEmpty);
      expect(remote.hasCausalBuffer, isFalse);
    },
  );

  test('falls back to a node upsert when a Drawing Paper page moves', () async {
    final document = _deeplyNestedDrawingDocument();
    final owned = await createContainer();
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    final paper = document.nodes.single;
    final payload = paper.payload as DrawingPaperPayload;
    final updatedPayload = payload.copyWith(
      studioPages: [
        payload.studioPages.single.copyWith(position: const Offset(24, 36)),
      ],
    );

    container
        .read(documentNodesProvider.notifier)
        .updateTransientNode(paper.copyWith(payload: updatedPayload));

    expect(controller.pendingOperationDetails, hasLength(1));
    expect(
      controller.pendingOperationDetails.single.kind,
      CrdtOperationKind.nodeUpsert,
    );
  });

  test(
    'marks sync failed instead of throwing when a stroke exceeds the CRDT limit',
    () async {
      final document = _drawingDocument();
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;

      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      final oversized = DrawingStroke(
        id: 'oversized-stroke',
        brush: StudioBrushCategory.gPen,
        color: Colors.black,
        size: 4,
        opacity: 1,
        points: List.generate(
          6000,
          (index) => DrawingStrokePoint(
            x: index.toDouble(),
            y: (index % 97).toDouble(),
            timestamp: index,
          ),
        ),
      );
      final paper = document.nodes.single;
      final payload = paper.payload as DrawingPaperPayload;
      final updatedPayload = payload.copyWith(
        rasterRevision: payload.rasterRevision + 1,
        layers: [
          payload.layers.single.copyWith(strokes: [oversized]),
        ],
      );

      expect(
        () => container
            .read(documentNodesProvider.notifier)
            .updateTransientNode(paper.copyWith(payload: updatedPayload)),
        returnsNormally,
      );
      expect(controller.pendingOperationDetails, isEmpty);
      expect(controller.syncStatus, CollaborationSyncStatus.failed);
      expect(
        controller.lastErrorMessage,
        contains('Asset is too large to sync.'),
      );
    },
  );

  test('exposes pending operations and exports recovery JSON', () async {
    final document = _drawingDocument();
    final owned = await createContainer();
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    final updated = document.nodes.single.copyWith(x: 42);
    container.read(documentNodesProvider.notifier).updateTransientNode(updated);

    expect(controller.pendingOperationDetails, hasLength(1));
    final bundle =
        jsonDecode(controller.exportRecoveryBundle()) as Map<String, dynamic>;
    expect(bundle['schemaVersion'], equals(1));
    expect(bundle['projectId'], equals(document.projectId));
    expect(bundle['pendingOperations'], hasLength(1));
    expect(
      (bundle['pendingOperations'] as List).single['opId'],
      equals(controller.pendingOperationDetails.single.opId),
    );
  });

  test('clears the persisted queue when leaving a session', () async {
    final document = _drawingDocument();
    final owned = await createContainer();
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );
    container
        .read(documentNodesProvider.notifier)
        .updateTransientNode(document.nodes.single.copyWith(x: 42));
    expect(controller.pendingOperationDetails, isNotEmpty);

    await controller.leave(updateState: false);
    final reloaded = await LocalStorageService().loadCollaborationQueue(
      document.projectId,
    );
    expect(reloaded, isEmpty);
  });

  test(
    'retains pending operations when leaving while collaboration is offline',
    () async {
      final document = _drawingDocument();
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;

      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );
      container
          .read(documentNodesProvider.notifier)
          .updateTransientNode(document.nodes.single.copyWith(x: 42));
      final pending = controller.pendingOperationDetails.single;

      await controller.leave(updateState: false);

      final raw = await owned.store.readCollaborationQueue(
        document.projectId,
        accountId: null,
        generation: 0,
      );
      expect(raw, isNotNull);
      expect(raw, contains(pending.opId));
    },
  );

  test('leaving during widget disposal suppresses notifier updates', () async {
    final document = _drawingDocument();
    final owned = await createContainer();
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    var notifications = 0;
    final subscription = container.listen<CollaborationSessionState>(
      collaborationSessionProvider(document.projectId),
      (_, _) => notifications++,
      fireImmediately: false,
    );
    addTearDown(subscription.close);

    await controller.leave(updateState: false);

    expect(notifications, equals(0));
  });

  test(
    'queues a stroke operation for a deeply nested Drawing Paper page edit',
    () async {
      final document = _deeplyNestedDrawingDocument();
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;

      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      final paper = document.nodes.single;
      final payload = paper.payload as DrawingPaperPayload;
      final outerPage = payload.studioPages.single;
      final outerPayload = outerPage.payload;
      final innerPage = outerPayload.studioPages.single;
      final innerPayload = innerPage.payload;
      final updatedPayload = payload.copyWith(
        studioPages: [
          outerPage.copyWith(
            payload: outerPayload.copyWith(
              studioPages: [
                innerPage.copyWith(
                  payload: innerPayload.copyWith(
                    layers: [
                      innerPayload.layers.single.copyWith(
                        strokes: [_nestedStroke('deep-stroke', 24)],
                      ),
                    ],
                    rasterRevision: innerPayload.rasterRevision + 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

      container
          .read(documentNodesProvider.notifier)
          .updateTransientNode(paper.copyWith(payload: updatedPayload));

      expect(controller.pendingOperationDetails, hasLength(1));
      expect(
        controller.pendingOperationDetails.single.kind,
        CrdtOperationKind.strokeUpsert,
      );
      expect(
        controller.pendingOperationDetails.single.value['pageId'],
        'inner-page',
      );
    },
  );

  test('removes a comment after a remote delete is materialized', () async {
    final document = _drawingDocument();
    final owned = await createContainer();
    addTearDown(() => disposeContainer(owned));
    final container = owned.container;

    container.read(documentNodesProvider.notifier).setNodes(document.nodes);
    final controller = container.read(
      collaborationSessionProvider(document.projectId).notifier,
    );
    await controller.start(
      initialDocument: document,
      userId: 'actor-a',
      userName: 'A',
      userColor: Colors.blue,
    );

    final comment = CanvasComment(
      id: 'comment-remote-delete',
      authorId: 'actor-a',
      authorName: 'A',
      text: 'Remove me remotely',
      x: 10,
      y: 10,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    controller.upsertComment(comment);

    final remote = CrdtDocumentSession.fromDocument(
      document,
      actorId: 'actor-b',
    )..seedComments([comment]);
    final delete = remote.deleteComment(comment.id);

    controller.applyRemoteOperation(delete);

    expect(container.read(commentsProvider), isEmpty);
  });

  test(
    'materializes comment replies, reactions, and resolution locally',
    () async {
      final document = _drawingDocument();
      final owned = await createContainer();
      addTearDown(() => disposeContainer(owned));
      final container = owned.container;

      container.read(documentNodesProvider.notifier).setNodes(document.nodes);
      final controller = container.read(
        collaborationSessionProvider(document.projectId).notifier,
      );
      await controller.start(
        initialDocument: document,
        userId: 'actor-a',
        userName: 'A',
        userColor: Colors.blue,
      );

      final comment = CanvasComment(
        id: 'comment-1',
        authorId: 'actor-a',
        authorName: 'A',
        text: 'Need a pass here',
        x: 10,
        y: 10,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      controller.upsertComment(comment);
      controller.insertCommentReply(
        commentId: comment.id,
        reply: CommentReply(
          id: 'reply-1',
          authorId: 'actor-a',
          authorName: 'A',
          text: 'On it',
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      );
      controller.setCommentReaction(
        commentId: comment.id,
        userId: 'actor-a',
        emoji: '👍',
        active: true,
      );
      expect(
        controller.isCommentReactionActive(
          commentId: comment.id,
          userId: 'actor-a',
          emoji: '👍',
        ),
        isTrue,
      );
      controller.setCommentResolved(commentId: comment.id, resolved: true);

      final materialized = container.read(commentsProvider).single;
      expect(materialized.replies.single.text, equals('On it'));
      expect(materialized.reactions, equals({'👍': 1}));
      expect(materialized.resolved, isTrue);
      expect(controller.state.pendingOperations, equals(4));
    },
  );
}

class _UnvalidatedDocumentAssetsNotifier extends DocumentAssetsNotifier {
  @override
  void setManifest(DocumentAssetManifest manifest) {
    state = manifest;
  }
}

CanvasDocument _deeplyNestedDrawingDocument() => CanvasDocument(
  projectId: 'project-1',
  updatedAt: DateTime.utc(2026, 1, 1),
  nodes: [
    CanvasNode(
      id: 'paper-node',
      type: NodeType.drawingPaper,
      x: 0,
      y: 0,
      width: 400,
      height: 400,
      payload: DrawingPaperPayload(
        layers: [const DrawingLayer(id: 'layer-1', name: 'Ink')],
        studioPages: [
          DrawingPaperPage(
            id: 'outer-page',
            position: Offset.zero,
            payload: DrawingPaperPayload(
              layers: [const DrawingLayer(id: 'outer-layer', name: 'Ink')],
              studioPages: [
                DrawingPaperPage(
                  id: 'inner-page',
                  position: Offset.zero,
                  payload: DrawingPaperPayload(
                    layers: [
                      const DrawingLayer(id: 'inner-layer', name: 'Ink'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ],
);

DrawingStroke _nestedStroke(String id, double x) => DrawingStroke(
  id: id,
  brush: StudioBrushCategory.gPen,
  color: Colors.black,
  size: 4,
  opacity: 1,
  points: [
    DrawingStrokePoint(x: x, y: 10),
    DrawingStrokePoint(x: x + 20, y: 20),
  ],
);

CanvasDocument _drawingDocument() => CanvasDocument(
  projectId: 'project-1',
  updatedAt: DateTime.utc(2026, 1, 1),
  nodes: [
    CanvasNode(
      id: 'paper-node',
      type: NodeType.drawingPaper,
      x: 0,
      y: 0,
      width: 400,
      height: 400,
      payload: DrawingPaperPayload(
        layers: [const DrawingLayer(id: 'layer-1', name: 'Ink')],
      ),
    ),
  ],
);
