import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/document_package.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/features/ai/data/image_artifact_store.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/data/video_artifact_store.dart';
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'package:varian/features/assets/data/asset_library_repository.dart';
import 'package:varian/features/assets/data/asset_library_service.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/data/file_artifact_store.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/assets/domain/asset_library.dart';
import 'package:varian/features/assets/state/asset_library_provider.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/data/remote/supabase_sync_provider.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_panel_controller.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_surface.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/collaboration/state/collaboration_session_provider.dart';
import 'package:varian/features/capture/data/capture_asset_store.dart';
import 'package:varian/features/capture/data/capture_repository.dart';
import 'package:varian/features/capture/domain/capture_canvas_handoff.dart';
import 'package:varian/features/capture/domain/capture_item.dart';
import 'package:varian/features/capture/state/capture_provider.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store_types.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import '../../test_app.dart';

const _minimalPngBytes = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  4,
  0,
  0,
  0,
  181,
  28,
  12,
  2,
  0,
  0,
  0,
  11,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  100,
  248,
  15,
  0,
  1,
  5,
  1,
  1,
  39,
  24,
  227,
  102,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

class _MutableAccountSyncService extends SupabaseSyncService {
  _MutableAccountSyncService(this.accountId) : super(null);

  String? accountId;

  @override
  String? get currentUserId => accountId;
}

class _GatedCaptureRepository implements CaptureRepository {
  _GatedCaptureRepository(this.delegate);

  final CaptureRepository delegate;
  final Completer<void> readStarted = Completer<void>();
  final Completer<void> allowRead = Completer<void>();

  @override
  Future<CaptureItem> createCapture(CaptureInput input) =>
      delegate.createCapture(input);

  @override
  Future<List<CaptureItem>> listCaptures({
    CaptureQuery query = const CaptureQuery(),
  }) => delegate.listCaptures(query: query);

  @override
  Future<CaptureItem?> getCapture(String id) => delegate.getCapture(id);

  @override
  Future<Uint8List?> readCaptureAsset(String id) async {
    if (!readStarted.isCompleted) readStarted.complete();
    await allowRead.future;
    return delegate.readCaptureAsset(id);
  }

  @override
  Future<void> setRead(String id, bool value) => delegate.setRead(id, value);

  @override
  Future<void> setFavorite(String id, bool value) =>
      delegate.setFavorite(id, value);

  @override
  Future<void> deleteCapture(String id) => delegate.deleteCapture(id);

  @override
  Future<void> restoreCapture(String id) => delegate.restoreCapture(id);

  @override
  Future<void> purgeCapture(String id) => delegate.purgeCapture(id);
}

class _CatalogRepository implements AssetLibraryRepository {
  _CatalogRepository(this.item);

  final AssetLibraryItem item;
  final List<({String itemId, String? projectId, String? nodeId})> usage = [];

  @override
  Future<void> load() async {}

  @override
  Future<AssetLibraryPage> search(AssetLibraryQuery query) async =>
      AssetLibraryPage(
        items: query.scopeId == item.scopeId ? [item] : const [],
      );

  @override
  Future<List<AssetLibraryFolder>> loadFolders() async => const [];

  @override
  Future<AssetLibraryFolder> createFolder(String name, {String? parentId}) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteFolder(String folderId) async {}

  @override
  Future<AssetLibraryItem> save(AssetLibraryItem item) async => item;

  @override
  Future<AssetLibraryItem> saveProviderItem(AssetLibraryItem item) async =>
      item;

  @override
  Future<AssetLibraryItem> saveUpload(
    AssetPickerResult result, {
    String? folderId,
    Iterable<String> tags = const [],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> setFavorite(String itemId, bool active) async {}

  @override
  Future<void> updateMetadata(
    String itemId, {
    String? name,
    String? folderId,
    Iterable<String>? tags,
  }) async {}

  @override
  Future<void> delete(String itemId) async {}

  @override
  Future<void> recordUsage(
    String itemId, {
    String? projectId,
    String? nodeId,
  }) async {
    usage.add((itemId: itemId, projectId: projectId, nodeId: nodeId));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  CanvasEditorServices toolbarServices({
    bool showProjectHeader = false,
    Future<AssetPickerResult?> Function({String? projectId})? pickImage,
    Future<AssetPickerResult?> Function({String? projectId})? pickAnyFile,
    ImageArtifactStore? imageArtifactStore,
    FileArtifactStore? fileArtifactStore,
  }) => CanvasEditorServices(
    showProjectHeader: showProjectHeader,
    showLayersByDefault: false,
    enableAutosave: false,
    enableCollaboration: false,
    enableAiStudio: false,
    trackVideoObjectUrls: false,
    stackPanelsOnCompact: false,
    pickImage: pickImage,
    pickAnyFile: pickAnyFile,
    imageArtifactStore: imageArtifactStore,
    fileArtifactStore: fileArtifactStore,
  );

  Future<void> pumpSurface(
    WidgetTester tester,
    ProviderContainer container, {
    required String projectId,
    required CanvasEditorServices services,
    CanvasEditorPanelController? panelController,
    CaptureCanvasHandoff? captureHandoff,
    bool captureTargetIsCollaborationRoom = false,
    CollaborationRole? collaborationRole,
    bool readOnly = false,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: projectId,
            services: services,
            panelController: panelController,
            captureHandoff: captureHandoff,
            captureTargetIsCollaborationRoom: captureTargetIsCollaborationRoom,
            collaborationRole: collaborationRole,
            readOnly: readOnly,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openImageTool(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Media & Cards tools'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Image Asset (I)'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('canvas-pointer-surface')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  testWidgets(
    'consumes a capture handoff once and adds an undoable text node',
    (tester) async {
      const projectId = 'capture-editor-text-project';
      final repository = LocalCaptureRepository(
        assetStore: MemoryCaptureAssetStore(),
      );
      final capture = await repository.createCapture(
        CaptureInput.text('Keep this capture', title: 'Inbox note'),
      );
      final handoff = CaptureCanvasHandoff(
        projectId: projectId,
        accountId: null,
        captureId: capture.id,
      );
      final container = ProviderContainer(
        overrides: [captureRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final existingNode = CanvasNode(
        id: 'preexisting-capture-editor-node',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 100,
        height: 80,
        payload: ShapePayload(),
      );
      container.read(documentNodesProvider.notifier).setNodes([existingNode]);

      await pumpSurface(
        tester,
        container,
        projectId: projectId,
        services: toolbarServices(),
        captureHandoff: handoff,
      );
      await tester.pump();

      final nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(2));
      final inserted = nodes.singleWhere((node) => node.id != existingNode.id);
      expect(inserted.type, NodeType.text);
      expect((inserted.payload as TextPayload).text, 'Keep this capture');
      expect(container.read(selectionProvider), {inserted.id});
      expect(container.read(documentAssetsProvider).entries, isEmpty);
      expect(handoff.isConsumed, isTrue);

      final unchanged = await repository.getCapture(capture.id);
      expect(unchanged?.status, capture.status);
      expect(unchanged?.isRead, capture.isRead);
      expect(unchanged?.isFavorite, capture.isFavorite);
      expect(unchanged?.text, capture.text);

      container.read(documentNodesProvider.notifier).undo();
      expect(container.read(documentNodesProvider), [existingNode]);
      expect(await repository.getCapture(capture.id), isNotNull);
    },
  );

  testWidgets(
    'copies capture image to its owned artifact and undo keeps the Inbox source',
    (tester) async {
      const projectId = 'capture-editor-image-project';
      final captureAssets = MemoryCaptureAssetStore();
      final repository = LocalCaptureRepository(assetStore: captureAssets);
      final capture = await repository.createCapture(
        CaptureInput.file(
          name: 'source.png',
          bytes: Uint8List.fromList(_minimalPngBytes),
          mimeType: 'image/png',
          title: 'Inbox image',
          origin: CaptureOrigin.share,
        ),
      );
      final imageStore = MemoryImageArtifactStore();
      final handoff = CaptureCanvasHandoff(
        projectId: projectId,
        accountId: null,
        captureId: capture.id,
      );
      final panelController = CanvasEditorPanelController(
        initialShowInspector: false,
      );
      addTearDown(panelController.dispose);
      final container = ProviderContainer(
        overrides: [captureRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await pumpSurface(
        tester,
        container,
        projectId: projectId,
        services: toolbarServices(imageArtifactStore: imageStore),
        panelController: panelController,
        captureHandoff: handoff,
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(1));
      final node = nodes.single;
      expect(node.type, NodeType.image);
      final payload = node.payload as ImagePayload;
      expect(payload.assetId, node.id);
      final asset = container.read(documentAssetsProvider)[node.id];
      expect(asset, isNotNull);
      expect(asset!.durableReference, startsWith('varian-image://'));
      final storedCaptureBytes = await repository.readCaptureAsset(capture.id);
      expect(storedCaptureBytes, Uint8List.fromList(_minimalPngBytes));
      final ownedArtifact = await imageStore.hydrate(
        asset.durableReference!,
        fileName: asset.name,
      );
      expect(ownedArtifact, isNotNull);
      expect(await imageStore.read(ownedArtifact!), storedCaptureBytes);

      await repository.deleteCapture(capture.id);
      await repository.purgeCapture(capture.id);
      expect(await repository.getCapture(capture.id), isNull);
      final canvasArtifact = await imageStore.hydrate(
        asset.durableReference!,
        fileName: asset.name,
      );
      expect(canvasArtifact, isNotNull);
      expect(await imageStore.read(canvasArtifact!), isNotNull);
      expect(container.read(documentNodesProvider), hasLength(1));
      container.read(documentNodesProvider.notifier).undo();
      expect(container.read(documentNodesProvider), isEmpty);
      expect(container.read(documentAssetsProvider)[node.id], isNotNull);
    },
  );

  testWidgets(
    'rejects capture insertion when an existing live session is read-only',
    (tester) async {
      const projectId = 'capture-editor-live-readonly-project';
      final repository = LocalCaptureRepository(
        assetStore: MemoryCaptureAssetStore(),
      );
      final capture = await repository.createCapture(
        CaptureInput.text('Do not add to a read-only canvas'),
      );
      final handoff = CaptureCanvasHandoff(
        projectId: projectId,
        accountId: null,
        captureId: capture.id,
      );
      final container = ProviderContainer(
        overrides: [captureRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final sessionSubscription = container.listen(
        collaborationSessionProvider(projectId),
        (_, _) {},
        fireImmediately: false,
      );
      addTearDown(sessionSubscription.close);
      final session = container.read(
        collaborationSessionProvider(projectId).notifier,
      );
      await session.start(
        initialDocument: CanvasDocument(
          projectId: projectId,
          updatedAt: DateTime.utc(2026, 9, 28),
        ),
        userId: 'read-only-capture-test-user',
        userName: 'Read only',
        userColor: Colors.blue,
        role: CollaborationRole.viewer,
      );
      expect(session.isStarted, isTrue);
      expect(session.canEditCanvas, isFalse);

      await pumpSurface(
        tester,
        container,
        projectId: projectId,
        services: const CanvasEditorServices(
          showProjectHeader: false,
          showLayersByDefault: false,
          enableAutosave: false,
          enableCollaboration: true,
          enableAiStudio: false,
          trackVideoObjectUrls: false,
          enableExport: false,
        ),
        captureHandoff: handoff,
      );
      await tester.pump();

      expect(handoff.isConsumed, isTrue);
      expect(container.read(documentNodesProvider), isEmpty);
      expect(container.read(documentAssetsProvider).entries, isEmpty);
      expect(await repository.getCapture(capture.id), isNotNull);
    },
  );

  testWidgets(
    'discards a capture handoff after the authenticated account changes',
    (tester) async {
      const projectId = 'capture-editor-account-change-project';
      final repository = LocalCaptureRepository(
        assetStore: MemoryCaptureAssetStore(),
      );
      final capture = await repository.createCapture(
        CaptureInput.file(
          name: 'source.png',
          bytes: Uint8List.fromList(_minimalPngBytes),
          mimeType: 'image/png',
        ),
      );
      final gatedRepository = _GatedCaptureRepository(repository);
      final sync = _MutableAccountSyncService('capture-account-before');
      final handoff = CaptureCanvasHandoff(
        projectId: projectId,
        accountId: 'capture-account-before',
        captureId: capture.id,
      );
      final container = ProviderContainer(
        overrides: [
          captureRepositoryProvider.overrideWithValue(gatedRepository),
          supabaseSyncServiceProvider.overrideWithValue(sync),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(sync.dispose);
      final imageStore = MemoryImageArtifactStore();

      await pumpSurface(
        tester,
        container,
        projectId: projectId,
        services: toolbarServices(imageArtifactStore: imageStore),
        captureHandoff: handoff,
      );
      await gatedRepository.readStarted.future;
      sync.accountId = 'capture-account-after';
      gatedRepository.allowRead.complete();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(container.read(documentNodesProvider), isEmpty);
      expect(container.read(documentAssetsProvider).entries, isEmpty);
      expect(await repository.getCapture(capture.id), isNotNull);
    },
  );

  testWidgets('discards a capture handoff after the editor project changes', (
    tester,
  ) async {
    const firstProjectId = 'capture-editor-old-project';
    const secondProjectId = 'capture-editor-new-project';
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final capture = await repository.createCapture(
      CaptureInput.file(
        name: 'source.png',
        bytes: Uint8List.fromList(_minimalPngBytes),
        mimeType: 'image/png',
      ),
    );
    final gatedRepository = _GatedCaptureRepository(repository);
    final handoff = CaptureCanvasHandoff(
      projectId: firstProjectId,
      accountId: null,
      captureId: capture.id,
    );
    final container = ProviderContainer(
      overrides: [captureRepositoryProvider.overrideWithValue(gatedRepository)],
    );
    addTearDown(container.dispose);
    final imageStore = MemoryImageArtifactStore();
    final panelController = CanvasEditorPanelController(
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);
    final services = toolbarServices(imageArtifactStore: imageStore);

    await pumpSurface(
      tester,
      container,
      projectId: firstProjectId,
      services: services,
      panelController: panelController,
      captureHandoff: handoff,
    );
    await gatedRepository.readStarted.future;
    await pumpSurface(
      tester,
      container,
      projectId: secondProjectId,
      services: services,
      panelController: panelController,
      captureHandoff: handoff,
    );
    gatedRepository.allowRead.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(container.read(documentNodesProvider), isEmpty);
    expect(container.read(documentAssetsProvider).entries, isEmpty);
    expect(await repository.getCapture(capture.id), isNotNull);
  });

  testWidgets('discards a capture handoff after a newer local edit starts', (
    tester,
  ) async {
    const projectId = 'capture-editor-newer-edit-project';
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final capture = await repository.createCapture(
      CaptureInput.file(
        name: 'source.png',
        bytes: Uint8List.fromList(_minimalPngBytes),
        mimeType: 'image/png',
      ),
    );
    final gatedRepository = _GatedCaptureRepository(repository);
    final handoff = CaptureCanvasHandoff(
      projectId: projectId,
      accountId: null,
      captureId: capture.id,
    );
    final container = ProviderContainer(
      overrides: [captureRepositoryProvider.overrideWithValue(gatedRepository)],
    );
    addTearDown(container.dispose);
    final existingNode = CanvasNode(
      id: 'newer-local-edit-node',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 100,
      height: 80,
      payload: ShapePayload(),
    );
    final imageStore = MemoryImageArtifactStore();
    final panelController = CanvasEditorPanelController(
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await pumpSurface(
      tester,
      container,
      projectId: projectId,
      services: toolbarServices(imageArtifactStore: imageStore),
      panelController: panelController,
      captureHandoff: handoff,
    );
    await gatedRepository.readStarted.future;

    container.read(documentNodesProvider.notifier).addNode(existingNode);
    gatedRepository.allowRead.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    expect(nodes.single.id, existingNode.id);
    expect(nodes.single.type, existingNode.type);
    expect(container.read(documentAssetsProvider).entries, isEmpty);
    expect(await repository.getCapture(capture.id), isNotNull);
    expect(
      await repository.readCaptureAsset(capture.id),
      Uint8List.fromList(_minimalPngBytes),
    );
  });

  testWidgets(
    'discards a toolbar image picker completion after the surface is disposed',
    (tester) async {
      final picker = Completer<AssetPickerResult?>();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final services = toolbarServices(
        pickImage: ({String? projectId}) => picker.future,
        imageArtifactStore: MemoryImageArtifactStore(),
      );

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-dispose-project',
        services: services,
      );
      await openImageTool(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      picker.complete(
        AssetPickerResult(
          name: 'late.png',
          bytes: Uint8List.fromList(_minimalPngBytes),
        ),
      );
      await tester.pump();

      expect(container.read(documentNodesProvider), isEmpty);
    },
  );

  testWidgets(
    'discards a toolbar image picker completion after the project changes',
    (tester) async {
      final picker = Completer<AssetPickerResult?>();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final services = toolbarServices(
        pickImage: ({String? projectId}) => picker.future,
        imageArtifactStore: MemoryImageArtifactStore(),
      );

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-old-project',
        services: services,
      );
      await openImageTool(tester);

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-new-project',
        services: services,
      );
      picker.complete(
        AssetPickerResult(
          name: 'late.png',
          bytes: Uint8List.fromList(_minimalPngBytes),
        ),
      );
      await tester.pump();

      expect(container.read(documentNodesProvider), isEmpty);
    },
  );

  testWidgets(
    'discards a toolbar image picker completion after the account changes',
    (tester) async {
      final picker = Completer<AssetPickerResult?>();
      final sync = _MutableAccountSyncService('toolbar-account-before');
      final container = ProviderContainer(
        overrides: [supabaseSyncServiceProvider.overrideWithValue(sync)],
      );
      addTearDown(container.dispose);
      addTearDown(sync.dispose);
      final services = toolbarServices(
        pickImage: ({String? projectId}) => picker.future,
        imageArtifactStore: MemoryImageArtifactStore(),
      );

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-account-project',
        services: services,
      );
      await openImageTool(tester);

      sync.accountId = 'toolbar-account-after';
      picker.complete(
        AssetPickerResult(
          name: 'late.png',
          bytes: Uint8List.fromList(_minimalPngBytes),
        ),
      );
      await tester.pump();

      expect(container.read(documentNodesProvider), isEmpty);
      expect(container.read(documentAssetsProvider).entries, isEmpty);
    },
  );

  testWidgets(
    'discards an older toolbar image operation after a newer operation starts',
    (tester) async {
      final firstPicker = Completer<AssetPickerResult?>();
      final secondPicker = Completer<AssetPickerResult?>();
      var pickerCalls = 0;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final services = toolbarServices(
        pickImage: ({String? projectId}) {
          pickerCalls++;
          return pickerCalls == 1 ? firstPicker.future : secondPicker.future;
        },
        imageArtifactStore: MemoryImageArtifactStore(),
      );

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-newer-image-project',
        services: services,
        panelController: CanvasEditorPanelController(
          initialShowInspector: false,
        ),
      );
      container.read(activeToolProvider.notifier).setTool(CanvasTool.image);
      await tester.pump();
      final canvas = tester.getRect(
        find.byKey(const ValueKey('canvas-pointer-surface')),
      );
      await tester.tapAt(canvas.center);
      await tester.pump(const Duration(milliseconds: 400));
      container.read(activeToolProvider.notifier).setTool(CanvasTool.image);
      await tester.pump();
      await tester.tapAt(canvas.center + const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 400));

      firstPicker.complete(
        AssetPickerResult(
          name: 'stale.png',
          bytes: Uint8List.fromList(_minimalPngBytes),
        ),
      );
      await tester.pump();
      expect(container.read(documentNodesProvider), isEmpty);

      secondPicker.complete(
        AssetPickerResult(
          name: 'current.png',
          bytes: Uint8List.fromList(_minimalPngBytes),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      final nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(1));
      expect((nodes.single.payload as dynamic).assetId, nodes.single.id);
      expect(
        container.read(documentAssetsProvider)[nodes.single.id],
        isNotNull,
      );
    },
  );

  testWidgets(
    'discards a toolbar file picker completion after the account changes',
    (tester) async {
      final picker = Completer<AssetPickerResult?>();
      final sync = _MutableAccountSyncService('toolbar-file-account-before');
      final container = ProviderContainer(
        overrides: [supabaseSyncServiceProvider.overrideWithValue(sync)],
      );
      addTearDown(container.dispose);
      addTearDown(sync.dispose);
      final panelController = CanvasEditorPanelController(
        initialShowInspector: false,
      );
      addTearDown(panelController.dispose);
      final services = toolbarServices(
        pickAnyFile: ({String? projectId}) => picker.future,
        fileArtifactStore: MemoryFileArtifactStore(),
      );

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-file-account-project',
        services: services,
        panelController: panelController,
      );
      container.read(activeToolProvider.notifier).setTool(CanvasTool.fileCard);
      await tester.pump();
      await tester.tapAt(
        tester
            .getRect(find.byKey(const ValueKey('canvas-pointer-surface')))
            .center,
      );
      await tester.pump(const Duration(milliseconds: 400));

      sync.accountId = 'toolbar-file-account-after';
      picker.complete(
        AssetPickerResult(
          name: 'late.txt',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      await tester.pump();

      expect(container.read(documentNodesProvider), isEmpty);
      expect(container.read(documentAssetsProvider).entries, isEmpty);
    },
  );

  testWidgets(
    'discards an older toolbar file operation after a newer operation starts',
    (tester) async {
      final firstPicker = Completer<AssetPickerResult?>();
      final secondPicker = Completer<AssetPickerResult?>();
      var pickerCalls = 0;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final panelController = CanvasEditorPanelController(
        initialShowInspector: false,
      );
      addTearDown(panelController.dispose);
      final services = toolbarServices(
        pickAnyFile: ({String? projectId}) {
          pickerCalls++;
          return pickerCalls == 1 ? firstPicker.future : secondPicker.future;
        },
        fileArtifactStore: MemoryFileArtifactStore(),
      );

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-newer-file-project',
        services: services,
        panelController: panelController,
      );
      container.read(activeToolProvider.notifier).setTool(CanvasTool.fileCard);
      await tester.pump();
      final canvas = tester.getRect(
        find.byKey(const ValueKey('canvas-pointer-surface')),
      );
      await tester.tapAt(canvas.center);
      await tester.pump(const Duration(milliseconds: 400));
      container.read(activeToolProvider.notifier).setTool(CanvasTool.fileCard);
      await tester.pump();
      await tester.tapAt(canvas.center + const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 400));

      firstPicker.complete(
        AssetPickerResult(
          name: 'stale.txt',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      await tester.pump();
      expect(container.read(documentNodesProvider), isEmpty);

      secondPicker.complete(
        AssetPickerResult(
          name: 'current.txt',
          bytes: Uint8List.fromList(<int>[4, 5, 6]),
        ),
      );
      await tester.pump();

      final nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(1));
      final node = nodes.single;
      expect(node.type, NodeType.fileCard);
      expect((node.payload as FilePayload).assetId, node.id);
      expect(container.read(documentAssetsProvider)[node.id], isNotNull);
    },
  );

  testWidgets(
    'discards a toolbar file picker completion after the surface is disposed',
    (tester) async {
      final picker = Completer<AssetPickerResult?>();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final panelController = CanvasEditorPanelController(
        initialShowInspector: false,
      );
      addTearDown(panelController.dispose);
      final services = toolbarServices(
        pickAnyFile: ({String? projectId}) => picker.future,
        fileArtifactStore: MemoryFileArtifactStore(),
      );

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-file-dispose-project',
        services: services,
        panelController: panelController,
      );
      container.read(activeToolProvider.notifier).setTool(CanvasTool.fileCard);
      await tester.pump();
      await tester.tapAt(
        tester
            .getRect(find.byKey(const ValueKey('canvas-pointer-surface')))
            .center,
      );
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pumpWidget(const SizedBox.shrink());
      picker.complete(
        AssetPickerResult(
          name: 'late.txt',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      await tester.pump();

      expect(container.read(documentNodesProvider), isEmpty);
    },
  );

  testWidgets(
    'discards a toolbar file picker completion after the project changes',
    (tester) async {
      final picker = Completer<AssetPickerResult?>();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final panelController = CanvasEditorPanelController(
        initialShowInspector: false,
      );
      addTearDown(panelController.dispose);
      final services = toolbarServices(
        pickAnyFile: ({String? projectId}) => picker.future,
        fileArtifactStore: MemoryFileArtifactStore(),
      );

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-file-old-project',
        services: services,
        panelController: panelController,
      );
      container.read(activeToolProvider.notifier).setTool(CanvasTool.fileCard);
      await tester.pump();
      await tester.tapAt(
        tester
            .getRect(find.byKey(const ValueKey('canvas-pointer-surface')))
            .center,
      );
      await tester.pump(const Duration(milliseconds: 400));

      await pumpSurface(
        tester,
        container,
        projectId: 'toolbar-file-new-project',
        services: services,
        panelController: panelController,
      );
      picker.complete(
        AssetPickerResult(
          name: 'late.txt',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      await tester.pump();

      expect(container.read(documentNodesProvider), isEmpty);
    },
  );

  testWidgets('publishes a toolbar image with one durable identity', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var pickerCalled = false;
    final services = toolbarServices(
      pickImage: ({String? projectId}) async {
        pickerCalled = true;
        return AssetPickerResult(
          name: 'image.png',
          bytes: Uint8List.fromList(_minimalPngBytes),
        );
      },
      imageArtifactStore: MemoryImageArtifactStore(),
    );

    await pumpSurface(
      tester,
      container,
      projectId: 'toolbar-success-project',
      services: services,
      panelController: CanvasEditorPanelController(initialShowInspector: false),
    );
    container.read(activeToolProvider.notifier).setTool(CanvasTool.image);
    await tester.pump();
    expect(container.read(activeToolProvider), CanvasTool.image);
    expect(pickerCalled, isFalse);
    final pointerSurface = find.byKey(const ValueKey('canvas-pointer-surface'));
    final pointerRect = tester.getRect(pointerSurface);
    await tester.tapAt(pointerRect.center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(pickerCalled, isTrue);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    final node = nodes.single;
    expect(node.type.name, 'image');
    final payload = node.payload as dynamic;
    expect(payload.assetId, node.id);
    expect(container.read(documentAssetsProvider)[node.id], isNotNull);
  });

  testWidgets(
    'inserts every bundled shape without materializing binary bytes',
    (tester) async {
      const projectId = 'bundled-shapes-project';
      final shapes = AssetLibraryService.builtInItems(projectId);
      final repository = _CatalogRepository(shapes.first);
      final container = ProviderContainer(
        overrides: [
          assetLibraryRepositoryProvider(
            projectId,
          ).overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final panelController = CanvasEditorPanelController(
        initialShowInspector: false,
      );
      addTearDown(panelController.dispose);
      await pumpSurface(
        tester,
        container,
        projectId: projectId,
        services: const CanvasEditorServices(
          showProjectHeader: false,
          showLayersByDefault: false,
          enableAutosave: false,
          enableCollaboration: false,
          enableAiStudio: false,
          trackVideoObjectUrls: false,
          enableExport: false,
        ),
        panelController: panelController,
      );

      final state = tester.state(find.byType(CanvasEditorSurface));
      for (final shape in shapes) {
        await (state as dynamic).insertAssetLibraryItem(shape);
      }
      await tester.pump();

      final nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(shapes.length));
      expect(
        nodes.map((node) => node.type),
        containsAll(<NodeType>[
          NodeType.rectangle,
          NodeType.ellipse,
          NodeType.diamond,
          NodeType.cylinder,
          NodeType.parallelogram,
          NodeType.arrow,
        ]),
      );
      expect(container.read(documentAssetsProvider).entries, isEmpty);
    },
  );

  testWidgets('inserts a catalog image with one durable identity and usage', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final imageStore = MemoryImageArtifactStore();
    final image = await imageStore.save(
      Uint8List.fromList(_minimalPngBytes),
      fileName: 'catalog.png',
    );
    final item = AssetLibraryItem(
      id: 'catalog-image',
      scopeId: 'catalog-image-project',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Catalog image',
      mimeType: 'image/png',
      sizeBytes: _minimalPngBytes.length,
      checksum: sha256.convert(_minimalPngBytes).toString(),
      metadata: {'imageArtifactReference': image.reference},
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );
    final repository = _CatalogRepository(item);
    final container = ProviderContainer(
      overrides: [
        assetLibraryRepositoryProvider(
          item.scopeId,
        ).overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final panelController = CanvasEditorPanelController(
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);
    final services = CanvasEditorServices(
      showProjectHeader: true,
      showLayersByDefault: false,
      enableAutosave: false,
      enableCollaboration: false,
      enableAiStudio: false,
      trackVideoObjectUrls: false,
      imageArtifactStore: imageStore,
    );

    await pumpSurface(
      tester,
      container,
      projectId: item.scopeId,
      services: services,
      panelController: panelController,
    );
    final state = tester.state(find.byType(CanvasEditorSurface));
    await (state as dynamic).insertAssetLibraryItem(item);
    await tester.pump();

    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    final node = nodes.single;
    final payload = node.payload as ImagePayload;
    expect(node.id, payload.assetId);
    expect(node.id, container.read(documentAssetsProvider).entries.keys.single);
    expect(payload.imageArtifactReference, image.reference);
    expect(
      container
          .read(documentAssetsProvider)[node.id]!
          .metadata['libraryItemId'],
      item.id,
    );
    expect(repository.usage, hasLength(1));
    expect(repository.usage.single.itemId, item.id);
    expect(repository.usage.single.projectId, item.scopeId);
    expect(repository.usage.single.nodeId, node.id);
  });

  testWidgets('does not record catalog usage when materialization fails', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final item = AssetLibraryItem(
      id: 'catalog-invalid',
      scopeId: 'catalog-invalid-project',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Broken image',
      mimeType: 'image/png',
      metadata: const {
        'imageArtifactReference': 'varian-image://missing-catalog-image',
      },
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );
    final repository = _CatalogRepository(item);
    final container = ProviderContainer(
      overrides: [
        assetLibraryRepositoryProvider(
          item.scopeId,
        ).overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final panelController = CanvasEditorPanelController(
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);
    await pumpSurface(
      tester,
      container,
      projectId: item.scopeId,
      services: CanvasEditorServices(
        showProjectHeader: true,
        showLayersByDefault: false,
        enableAutosave: false,
        enableCollaboration: false,
        enableAiStudio: false,
        trackVideoObjectUrls: false,
        imageArtifactStore: MemoryImageArtifactStore(),
      ),
      panelController: panelController,
    );
    final state = tester.state(find.byType(CanvasEditorSurface));
    await (state as dynamic).insertAssetLibraryItem(item);
    await tester.pump();

    expect(container.read(documentNodesProvider), isEmpty);
    expect(container.read(documentAssetsProvider).entries, isEmpty);
    expect(repository.usage, isEmpty);
  });

  testWidgets('inserts every catalog binary through its typed artifact store', (
    tester,
  ) async {
    final imageStore = MemoryImageArtifactStore();
    final fileStore = MemoryFileArtifactStore();
    final mediaStore = MemoryMediaArtifactStore();
    final videoStore = MemoryVideoArtifactStore();
    final modelStore = MemoryModel3DArtifactStore();
    final image = await imageStore.save(
      Uint8List.fromList(_minimalPngBytes),
      fileName: 'catalog.png',
    );
    final fileBytes = Uint8List.fromList('%PDF-1.7'.codeUnits);
    final file = await fileStore.save(fileBytes, fileName: 'brief.pdf');
    final audioBytes = Uint8List.fromList(<int>[73, 68, 51, 3, 0, 0]);
    final audio = await mediaStore.save(
      audioBytes,
      kind: MediaArtifactKind.original,
      mimeType: 'audio/mpeg',
      checksum: sha256.convert(audioBytes).toString(),
      fileName: 'voice.mp3',
      storagePolicy: MediaStoragePolicy.durable,
    );
    final videoBytes = Uint8List.fromList(<int>[
      0,
      0,
      0,
      16,
      102,
      116,
      121,
      112,
      105,
      115,
      111,
      109,
      0,
      0,
      0,
      0,
    ]);
    final video = await videoStore.save(videoBytes, fileName: 'demo.mp4');
    final modelBytes = Uint8List.fromList(<int>[
      0x67,
      0x6c,
      0x54,
      0x46,
      2,
      0,
      0,
      0,
      24,
      0,
      0,
      0,
      4,
      0,
      0,
      0,
      0x4a,
      0x53,
      0x4f,
      0x4e,
      32,
      32,
      32,
      32,
    ]);
    final model = await modelStore.save(modelBytes, fileName: 'chair.glb');
    final now = DateTime.utc(2026, 9, 25);
    AssetLibraryItem item(
      String id,
      AssetLibraryItemKind kind,
      String name,
      String mimeType,
      String reference,
      Uint8List bytes,
    ) => AssetLibraryItem(
      id: id,
      scopeId: 'catalog-all-kinds-project',
      kind: kind,
      source: AssetLibrarySource.upload,
      name: name,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      checksum: sha256.convert(bytes).toString(),
      metadata: {
        switch (kind) {
          AssetLibraryItemKind.image ||
          AssetLibraryItemKind.graphic ||
          AssetLibraryItemKind.icon ||
          AssetLibraryItemKind.illustration => 'imageArtifactReference',
          AssetLibraryItemKind.file => 'fileArtifactReference',
          AssetLibraryItemKind.audio => 'audioArtifactReference',
          AssetLibraryItemKind.video => 'videoArtifactReference',
          AssetLibraryItemKind.model3d => 'model3dArtifactReference',
        }: reference,
      },
      createdAt: now,
      updatedAt: now,
    );
    final items = [
      item(
        'catalog-image',
        AssetLibraryItemKind.image,
        'Catalog image',
        'image/png',
        image.reference!,
        Uint8List.fromList(_minimalPngBytes),
      ),
      item(
        'catalog-file',
        AssetLibraryItemKind.file,
        'Catalog file',
        'application/pdf',
        file.reference!,
        fileBytes,
      ),
      item(
        'catalog-audio',
        AssetLibraryItemKind.audio,
        'Catalog audio',
        'audio/mpeg',
        audio.reference!,
        audioBytes,
      ),
      item(
        'catalog-video',
        AssetLibraryItemKind.video,
        'Catalog video',
        'video/mp4',
        video.reference!,
        videoBytes,
      ),
      item(
        'catalog-model',
        AssetLibraryItemKind.model3d,
        'Catalog model',
        'model/gltf-binary',
        model.reference!,
        modelBytes,
      ),
    ];
    final repository = _CatalogRepository(items.first);
    final container = ProviderContainer(
      overrides: [
        assetLibraryRepositoryProvider(
          items.first.scopeId,
        ).overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final panelController = CanvasEditorPanelController(
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);
    await pumpSurface(
      tester,
      container,
      projectId: items.first.scopeId,
      services: CanvasEditorServices(
        showProjectHeader: false,
        showLayersByDefault: false,
        enableAutosave: false,
        enableCollaboration: false,
        enableAiStudio: false,
        trackVideoObjectUrls: false,
        imageArtifactStore: imageStore,
        fileArtifactStore: fileStore,
        mediaArtifactStore: mediaStore,
        videoArtifactStore: videoStore,
        model3DArtifactStore: modelStore,
        // Keep the integration assertion focused on state publication. The
        // native 3D viewer schedules renderer timers in widget tests.
        enableExport: false,
      ),
      panelController: panelController,
    );

    final state = tester.state(find.byType(CanvasEditorSurface));
    for (final catalogItem in items) {
      await (state as dynamic).insertAssetLibraryItem(catalogItem);
    }

    final nodes = container.read(documentNodesProvider);
    final manifest = container.read(documentAssetsProvider);
    expect(nodes, hasLength(items.length));
    expect(manifest.entries, hasLength(items.length));
    expect(repository.usage, hasLength(items.length));
    for (final node in nodes) {
      final payload = node.payload as dynamic;
      expect(payload.assetId, node.id);
      expect(manifest[node.id], isNotNull);
      expect(repository.usage.any((event) => event.nodeId == node.id), isTrue);
    }
    expect(
      nodes.map((node) => node.type),
      containsAll(<NodeType>[
        NodeType.image,
        NodeType.fileCard,
        NodeType.audioCard,
        NodeType.videoCard,
        NodeType.model3d,
      ]),
    );
  });

  testWidgets('rejects corrupt dropped audio before publication', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final panelController = CanvasEditorPanelController(
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);
    await pumpSurface(
      tester,
      container,
      projectId: 'dropped-audio-corrupt-project',
      services: CanvasEditorServices(
        showProjectHeader: false,
        showLayersByDefault: false,
        enableAutosave: false,
        enableCollaboration: false,
        enableAiStudio: false,
        trackVideoObjectUrls: false,
        mediaArtifactStore: MemoryMediaArtifactStore(),
      ),
      panelController: panelController,
    );

    final state = tester.state(find.byType(CanvasEditorSurface));
    await (state as dynamic).handleFileDrop(
      DropDoneDetails(
        files: [
          DropItemFile.fromData(
            Uint8List.fromList(<int>[1, 2, 3, 4]),
            path: 'broken.mp3',
          ),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );

    expect(container.read(documentNodesProvider), isEmpty);
    expect(container.read(documentAssetsProvider).entries, isEmpty);
  });

  testWidgets(
    'materializes dropped audio, video, and files before publication',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final panelController = CanvasEditorPanelController(
        initialShowInspector: false,
      );
      addTearDown(panelController.dispose);
      final mediaStore = MemoryMediaArtifactStore();
      final videoStore = MemoryVideoArtifactStore();
      final fileStore = MemoryFileArtifactStore();
      await pumpSurface(
        tester,
        container,
        projectId: 'dropped-media-project',
        services: CanvasEditorServices(
          showProjectHeader: false,
          showLayersByDefault: false,
          enableAutosave: false,
          enableCollaboration: false,
          enableAiStudio: false,
          trackVideoObjectUrls: false,
          mediaArtifactStore: mediaStore,
          videoArtifactStore: videoStore,
          fileArtifactStore: fileStore,
        ),
        panelController: panelController,
      );

      final state = tester.state(find.byType(CanvasEditorSurface));
      Future<void> drop(Uint8List bytes, String name) =>
          (state as dynamic).handleFileDrop(
            DropDoneDetails(
              files: [DropItemFile.fromData(bytes, path: name)],
              localPosition: Offset.zero,
              globalPosition: Offset.zero,
            ),
          );

      await drop(Uint8List.fromList(<int>[73, 68, 51, 3, 0, 0]), 'voice.mp3');
      await drop(
        Uint8List.fromList(<int>[
          0,
          0,
          0,
          16,
          102,
          116,
          121,
          112,
          105,
          115,
          111,
          109,
          0,
          0,
          0,
          0,
        ]),
        'demo.mp4',
      );
      await drop(Uint8List.fromList('%PDF-1.7'.codeUnits), 'brief.pdf');

      final nodes = container.read(documentNodesProvider);
      final manifest = container.read(documentAssetsProvider);
      expect(nodes, hasLength(3));
      expect(manifest.entries, hasLength(3));
      for (final node in nodes) {
        final payload = node.payload as dynamic;
        expect(payload.assetId, node.id);
        expect(manifest[node.id], isNotNull);
      }
      final audio = nodes.firstWhere((node) => node.type == NodeType.audioCard);
      final video = nodes.firstWhere((node) => node.type == NodeType.videoCard);
      final file = nodes.firstWhere((node) => node.type == NodeType.fileCard);
      expect(
        (audio.payload as AudioPayload).audioArtifactReference,
        startsWith('varian-media://'),
      );
      expect(
        (video.payload as VideoPayload).videoArtifactReference,
        startsWith('varian-video://'),
      );
      expect(
        (file.payload as FilePayload).artifactReference,
        startsWith('varian-file://'),
      );
    },
  );

  testWidgets('publishes a toolbar file card with one durable identity', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var pickerCalled = false;
    final services = toolbarServices(
      pickAnyFile: ({String? projectId}) async {
        pickerCalled = true;
        return AssetPickerResult(
          name: 'brief.txt',
          bytes: Uint8List.fromList(<int>[72, 101, 108, 108, 111]),
        );
      },
      fileArtifactStore: MemoryFileArtifactStore(),
    );

    await pumpSurface(
      tester,
      container,
      projectId: 'toolbar-file-success-project',
      services: services,
      panelController: CanvasEditorPanelController(initialShowInspector: false),
    );
    container.read(activeToolProvider.notifier).setTool(CanvasTool.fileCard);
    await tester.pump();
    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-pointer-surface')),
    );
    await tester.tapAt(canvas.center);
    await tester.pump(const Duration(milliseconds: 400));

    expect(pickerCalled, isTrue);
    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    final node = nodes.single;
    expect(node.type, NodeType.fileCard);
    final payload = node.payload as FilePayload;
    expect(payload.assetId, node.id);
    expect(payload.artifactReference, startsWith('varian-file://'));
    expect(container.read(documentAssetsProvider)[node.id], isNotNull);
  });

  testWidgets(
    'production import preserves existing assets and remaps imported collisions',
    (tester) async {
      final now = DateTime.utc(2026, 9, 26);
      final existingAsset = DocumentAsset(
        id: 'shared-import-asset',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'existing.png',
        mimeType: 'image/png',
        durableReference: 'varian-image://existing-import',
        createdAt: now,
        updatedAt: now,
      );
      final importedAsset = existingAsset.copyWith(
        name: 'imported.png',
        durableReference: 'varian-image://imported-import',
      );
      final importedManifest = DocumentAssetManifest(
        entries: {importedAsset.id: importedAsset},
      );
      final rawJson = CanvasDocumentPackage(
        document: CanvasDocument(
          projectId: 'production-import-project',
          nodes: [
            CanvasNode(
              id: 'imported-image-node',
              type: NodeType.image,
              x: 0,
              y: 0,
              width: 120,
              height: 80,
              payload: ImagePayload(assetId: importedAsset.id),
            ),
          ],
          assets: importedManifest,
          updatedAt: now,
        ),
        assets: importedManifest,
      ).encode();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentAssetsProvider.notifier)
          .setManifest(
            DocumentAssetManifest(entries: {existingAsset.id: existingAsset}),
          );

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSurface(
        tester,
        container,
        projectId: 'production-import-project',
        services: toolbarServices(showProjectHeader: true),
      );
      final settingsButton = find.byKey(const Key('canvas-settings-menu'));
      await tester.ensureVisible(settingsButton);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Diagram / JSON'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(TabBar).last, const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANVAS JSON'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, rawJson);
      await tester.tap(find.text('Preview Import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Nodes'));
      await tester.pumpAndSettle();

      final importedNode = container.read(documentNodesProvider).single;
      final remappedAssetId = (importedNode.payload as ImagePayload).assetId!;
      expect(remappedAssetId, isNot(existingAsset.id));
      expect(
        container.read(documentAssetsProvider)[existingAsset.id]!.name,
        existingAsset.name,
      );
      expect(
        container.read(documentAssetsProvider)[remappedAssetId]!.name,
        importedAsset.name,
      );
      expect(find.text('IMPORT DIAGRAM / DOCUMENT'), findsNothing);
    },
  );

  testWidgets(
    'opens cloud governance from the editor menu using only mocked reads',
    (tester) async {
      const projectId = 'governance-editor-project';
      const userId = 'governance-editor-owner';
      SharedPreferences.setMockInitialValues({});
      final requests = <String>[];
      final lifecycleRequests = <String>[];
      final client = SupabaseClient(
        'https://example.test',
        _governanceTestKey(),
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          switch (request.url.path) {
            case '/rest/v1/projects':
              return http.Response(
                jsonEncode({'id': projectId, 'owner_id': userId}),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            case '/rest/v1/rpc/get_workspace_governance':
              return http.Response(
                jsonEncode({
                  'projectId': projectId,
                  'policy': const {},
                  'usage': const {},
                  'deletionRequestedAt': null,
                  'archivedAt': null,
                }),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            case '/rest/v1/rpc/list_workspace_audit_events':
              return http.Response('[]', 200, request: request);
            case '/rest/v1/rpc/get_workspace_health':
              return http.Response(
                jsonEncode({
                  'status': 'healthy',
                  'version': 'test',
                  'timestamp': '2026-09-27T00:00:00Z',
                  'checks': const [],
                }),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            case '/rest/v1/rpc/get_workspace_entitlement':
              return http.Response(
                jsonEncode({
                  'planId': 'test',
                  'revision': 1,
                  'limits': const {},
                  'overagePolicy': 'block',
                  'fetchedAt': '2026-09-27T00:00:00Z',
                  'status': 'active',
                  'provider': 'test',
                }),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            case '/rest/v1/rpc/list_workspace_plugin_registrations':
              return http.Response('[]', 200, request: request);
            case '/rest/v1/rpc/request_project_deletion':
            case '/rest/v1/rpc/cancel_project_deletion':
            case '/rest/v1/rpc/purge_workspace_retention':
              lifecycleRequests.add(request.url.path);
              fail('Cloud lifecycle mutations must not run in this test.');
            default:
              fail('Unexpected mocked backend request: ${request.url}');
          }
        }),
      );
      client.auth.stopAutoRefresh();
      await _authenticateGovernanceTestClient(client, userId);
      final service = SupabaseSyncService(client);
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        service.dispose();
        client.dispose();
      });
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;

      await pumpSurface(
        tester,
        container,
        projectId: projectId,
        services: toolbarServices(showProjectHeader: true),
      );
      final settingsMenu = tester.widget<UiMenuButton<String>>(
        find.byKey(const Key('canvas-settings-menu')),
      );
      expect(
        settingsMenu.items.any(
          (item) =>
              item.value == 'governance' &&
              item.label == 'Workspace Governance',
        ),
        isTrue,
      );
      settingsMenu.onSelected('governance');
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.byKey(const ValueKey('workspace-governance-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('governance-cloud-deletion')),
        findsOneWidget,
      );
      expect(find.text('No active cloud deletion request.'), findsOneWidget);
      final requestButton = find.byKey(
        const ValueKey('governance-cloud-deletion-request'),
      );
      await tester.ensureVisible(requestButton);
      expect(requestButton, findsOneWidget);
      expect(
        find.byKey(const ValueKey('governance-cloud-deletion-cancel')),
        findsNothing,
      );
      expect(requests, contains('GET /rest/v1/projects'));
      expect(
        requests.where(
          (request) => request == 'POST /rest/v1/rpc/get_workspace_governance',
        ),
        hasLength(greaterThanOrEqualTo(2)),
      );
      expect(lifecycleRequests, isEmpty);
      expect(requests, isNotEmpty);
      expect(requests.every((request) => request.isNotEmpty), isTrue);
      final close = find.byTooltip('Close workspace governance');
      await tester.ensureVisible(close);
      await tester.tap(close);
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'production import rejects unresolved dependencies before mutation',
    (tester) async {
      final now = DateTime.utc(2026, 9, 26);
      final existingNode = CanvasNode(
        id: 'existing-import-node',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 120,
        height: 80,
        payload: ShapePayload(),
      );
      final rawJson = CanvasDocumentPackage(
        document: CanvasDocument(
          projectId: 'production-import-unresolved-project',
          nodes: [
            CanvasNode(
              id: 'unresolved-image-node',
              type: NodeType.image,
              x: 0,
              y: 0,
              width: 120,
              height: 80,
              payload: ImagePayload(assetId: 'missing-import-asset'),
            ),
          ],
          updatedAt: now,
        ),
      ).encode();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(documentNodesProvider.notifier).setNodes([existingNode]);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSurface(
        tester,
        container,
        projectId: 'production-import-unresolved-project',
        services: toolbarServices(showProjectHeader: true),
      );
      final settingsButton = find.byKey(const Key('canvas-settings-menu'));
      await tester.ensureVisible(settingsButton);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Diagram / JSON'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(TabBar).last, const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANVAS JSON'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, rawJson);
      await tester.tap(find.text('Preview Import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Nodes'));
      await tester.pumpAndSettle();

      expect(container.read(documentNodesProvider), [existingNode]);
      expect(container.read(documentEdgesProvider), isEmpty);
      expect(container.read(documentAssetsProvider).entries, isEmpty);
      expect(find.text('IMPORT DIAGRAM / DOCUMENT'), findsOneWidget);
    },
  );
}

String _governanceTestKey() => String.fromCharCodes(const [116, 101, 115, 116]);

Future<void> _authenticateGovernanceTestClient(
  SupabaseClient client,
  String userId,
) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  String encodePart(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encodePart({'alg': 'HS256'})}.${encodePart({'sub': userId, 'exp': expiration})}.test-signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'governance-test-refresh',
      'user': {
        'id': userId,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}
