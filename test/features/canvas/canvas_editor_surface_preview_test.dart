import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_viewport;
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_surface.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_panel_controller.dart';
import 'package:varian/features/collaboration/presentation/widgets/comment_ui.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/collaboration/state/collaboration_provider.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';
import 'package:varian/features/canvas/state/viewport_provider.dart';
import 'package:varian/features/model3d/presentation/model3d_node_widget.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_persistence.dart';
import '../../test_app.dart';

class _TestPathProvider extends PathProviderPlatform {
  final String supportPath;

  _TestPathProvider(this.supportPath);

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final originalPathProvider = PathProviderPlatform.instance;
    final supportDirectory = await Directory.systemTemp.createTemp(
      'varian-preview-test-',
    );
    PathProviderPlatform.instance = _TestPathProvider(supportDirectory.path);
    addTearDown(() async {
      PathProviderPlatform.instance = originalPathProvider;
      if (await supportDirectory.exists()) {
        await supportDirectory.delete(recursive: true);
      }
    });
    SharedPreferences.setMockInitialValues({});
    CanvasImageCache.instance.clear();
  });

  testWidgets('Canvas comment anchors provide a semantic 44 px target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const projectId = 'comment-anchor-local-fixture';
    final node = CanvasNode(
      id: 'comment-anchor-node',
      type: NodeType.rectangle,
      x: 0,
      y: 80,
      width: 100,
      height: 80,
      payload: ShapePayload(),
    );
    final comment = CanvasComment(
      id: 'comment-anchor-thread',
      nodeId: node.id,
      authorId: 'fixture-author',
      authorName: 'Fixture Author',
      text: 'Needs review',
      x: 0,
      y: 0,
      createdAt: DateTime.utc(2026, 10, 5),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: projectId,
            services: CanvasEditorServices.embedded,
            panelController: panelController,
            initialDocument: CanvasDocument(
              projectId: projectId,
              nodes: [node],
              updatedAt: DateTime.utc(2026, 10, 5),
            ),
            initialComments: [comment],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(
        collaborationCommentsProvider(
          const CollaborationProjectionScope(
            projectId: projectId,
            accountId: 'local-device',
          ),
        ),
      ),
      [comment],
    );
    final anchor = find.byKey(
      const ValueKey('canvas-comment-anchor-comment-anchor-thread'),
    );
    expect(anchor, findsOneWidget);
    final anchorRect = tester.getRect(anchor);
    final pinVisual = find.byKey(
      const ValueKey('canvas-comment-pin-visual-comment-anchor-thread'),
    );
    expect(tester.getSize(pinVisual), const Size(24, 24));
    expect(
      anchorRect.width,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(
      anchorRect.height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(tester.getSemantics(anchor).label, 'Comment by Fixture Author');
    expect(find.byType(CanvasCommentThreadCard), findsNothing);

    await tester.tapAt(Offset(anchorRect.right - 1, anchorRect.bottom - 1));
    await tester.pumpAndSettle();

    expect(find.byType(CanvasCommentThreadCard), findsOneWidget);
    final exception = tester.takeException();
    if (exception is FlutterError) debugPrint(exception.toString());
    expect(exception, isNull);
    semantics.dispose();
  });

  testWidgets(
    'Canvas prepares a missing Drawing Paper preview from raster edits',
    (tester) async {
      final payload = DrawingPaperPayload(
        pixelWidth: 10,
        pixelHeight: 10,
        paperColor: Colors.white,
        layers: const [DrawingLayer(id: 'root', name: 'Root')],
        rasterOperations: const [
          RasterEditOperation(
            id: 'fill',
            kind: RasterEditKind.bucketFill,
            seedPoint: Offset(2, 2),
            color: Colors.blue,
          ),
        ],
      );
      final node = CanvasNode(
        id: 'paper',
        type: NodeType.drawingPaper,
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        payload: payload,
      );
      final expectedReference =
          DrawingPaperPersistence.previewReferenceForPayload(
            payload,
            nodeId: node.id,
          );
      addTearDown(CanvasImageCache.instance.clear);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              documentNodesProvider.overrideWith(
                (ref) => DocumentNodesNotifier(ref, initialNodes: [node]),
              ),
            ],
            child: testApp(
              const CanvasEditorSurface(
                projectId: 'preview-test',
                services: CanvasEditorServices.embedded,
              ),
            ),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump();

      expect(
        find.byKey(const ValueKey('canvas-node-layer-paper')),
        findsOneWidget,
      );
      final editorState = tester.state<State>(find.byType(CanvasEditorSurface));
      final preview =
          (editorState as dynamic).debugImageCache.getImage(expectedReference)
              as ui.Image?;
      expect(preview, isNotNull);
      final previewColor = await tester.runAsync(() async {
        final raw = await preview!.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return _pixel(raw!, preview.width, 2, 2);
      });
      expect(previewColor?.toARGB32(), Colors.blue.toARGB32());
    },
  );

  testWidgets('Canvas creates a real preview widget for every visible GLB', (
    tester,
  ) async {
    final nodes = [
      CanvasNode(
        id: 'model-a',
        type: NodeType.model3d,
        x: 80,
        y: 80,
        width: 240,
        height: 180,
        payload: Model3DPayload(fileName: 'model-a.glb'),
      ),
      CanvasNode(
        id: 'model-b',
        type: NodeType.model3d,
        x: 360,
        y: 80,
        width: 240,
        height: 180,
        payload: Model3DPayload(fileName: 'model-b.glb'),
      ),
    ];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes(nodes);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const CanvasEditorSurface(
            projectId: 'model-preview-test',
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(Model3DNodeWidget), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('canvas-node-layer-model-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('canvas-node-layer-model-b')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final firstLayer = find.byKey(const ValueKey('canvas-node-layer-model-a'));
    final initialPosition = container.read(documentNodesProvider).first;
    final gesture = await tester.startGesture(
      tester.getRect(firstLayer).center,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(80, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(documentNodesProvider).first.x, initialPosition.x);
    expect(container.read(documentNodesProvider).first.y, initialPosition.y);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected GLB top-center handle resizes instead of moving', (
    tester,
  ) async {
    final node = CanvasNode(
      id: 'selected-model-resize',
      type: NodeType.model3d,
      x: 80,
      y: 80,
      width: 240,
      height: 180,
      payload: Model3DPayload(fileName: 'selected-model.glb'),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'selected-model-resize-test',
            services: CanvasEditorServices.embedded,
            panelController: panelController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final layer = find.byKey(
      const ValueKey('canvas-node-layer-selected-model-resize'),
    );
    final topCenter = tester.getRect(layer).topCenter;
    final gesture = await tester.startGesture(topCenter);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    final resized = container.read(documentNodesProvider).single;
    expect(resized.y, 100);
    expect(resized.height, 160);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the selected GLB header moves it once', (tester) async {
    final node = CanvasNode(
      id: 'selected-model-header-drag',
      type: NodeType.model3d,
      x: 80,
      y: 80,
      width: 240,
      height: 180,
      payload: Model3DPayload(fileName: 'selected-model.glb'),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'selected-model-header-drag-test',
            services: CanvasEditorServices.embedded,
            panelController: panelController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('model3d-drag-header-target'));
    final gesture = await tester.startGesture(tester.getRect(header).center);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    final moved = container.read(documentNodesProvider).single;
    expect(moved.x, node.x);
    expect(moved.y, node.y + 60);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected GLB wheel does not zoom the canvas viewport', (
    tester,
  ) async {
    final node = CanvasNode(
      id: 'selected-model',
      type: NodeType.model3d,
      x: 80,
      y: 80,
      width: 240,
      height: 180,
      payload: Model3DPayload(fileName: 'selected-model.glb'),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const CanvasEditorSurface(
            projectId: 'selected-model-wheel-test',
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final layer = find.byKey(
      const ValueKey('canvas-node-layer-selected-model'),
    );
    final initialZoom = container.read(viewportProvider).zoom;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getRect(layer).center,
        scrollDelta: const Offset(0, -100),
      ),
    );
    await tester.pump();

    expect(container.read(viewportProvider).zoom, initialZoom);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scales the GLB layer once with the canvas viewport', (
    tester,
  ) async {
    final node = CanvasNode(
      id: 'scaled-model',
      type: NodeType.model3d,
      x: 80,
      y: 80,
      width: 240,
      height: 180,
      payload: Model3DPayload(fileName: 'scaled-model.glb'),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(viewportProvider.notifier).setZoom(1.5);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const CanvasEditorSurface(
            projectId: 'scaled-model-test',
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final layer = find.byKey(const ValueKey('canvas-node-layer-scaled-model'));
    final modelWidget = find.byType(Model3DNodeWidget);
    expect(tester.getSize(layer), const Size(360, 270));
    expect(tester.getSize(modelWidget), const Size(240, 180));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a selected connector endpoint detaches it once', (
    tester,
  ) async {
    final source = CanvasNode(
      id: 'connector-source',
      type: NodeType.rectangle,
      x: 80,
      y: 100,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final target = CanvasNode(
      id: 'connector-target',
      type: NodeType.rectangle,
      x: 400,
      y: 220,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final edge = CanvasEdge(
      id: 'connector-edge',
      sourceNodeId: source.id,
      sourceAnchor: AnchorPosition.right,
      targetNodeId: target.id,
      targetAnchor: AnchorPosition.left,
      waypoints: const [Offset(300, 140), Offset(300, 260)],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([source, target]);
    container.read(documentEdgesProvider.notifier).setEdges([edge]);
    container.read(selectionProvider.notifier).select(edge.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'connector-gesture-test',
            panelController: panelController,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    await tester.dragFrom(
      canvas.topLeft + const Offset(200, 140),
      const Offset(-40, 30),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final edited = container.read(documentEdgesProvider).single;
    expect(edited.sourceNodeId, isNull);
    expect(edited.sourcePoint, const Offset(160, 170));
    expect(container.read(historyProvider).undoStack, hasLength(1));

    container.read(documentNodesProvider.notifier).undo();
    final undone = container.read(documentEdgesProvider).single;
    expect(undone.sourceNodeId, source.id);
    expect(undone.sourcePoint, isNull);
    expect(container.read(historyProvider).undoStack, isEmpty);

    container.read(documentNodesProvider.notifier).redo();
    final redone = container.read(documentEdgesProvider).single;
    expect(redone.sourceNodeId, isNull);
    expect(redone.sourcePoint, const Offset(160, 170));
    expect(container.read(historyProvider).undoStack, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('snaps a free connector endpoint to the nearest shape anchor', (
    tester,
  ) async {
    final source = CanvasNode(
      id: 'free-source',
      type: NodeType.rectangle,
      x: 80,
      y: 100,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final snapNode = CanvasNode(
      id: 'snap-target',
      type: NodeType.rectangle,
      x: 240,
      y: 100,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final target = CanvasNode(
      id: 'free-target',
      type: NodeType.rectangle,
      x: 500,
      y: 220,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final edge = CanvasEdge(
      id: 'snap-edge',
      sourcePoint: const Offset(180, 140),
      targetNodeId: target.id,
      targetAnchor: AnchorPosition.left,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([
      source,
      snapNode,
      target,
    ]);
    container.read(documentEdgesProvider.notifier).setEdges([edge]);
    container.read(selectionProvider.notifier).select(edge.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'connector-snap-test',
            panelController: panelController,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    await tester.dragFrom(
      canvas.topLeft + const Offset(180, 140),
      const Offset(60, 0),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final snapped = container.read(documentEdgesProvider).single;
    expect(snapped.sourceNodeId, snapNode.id);
    expect(snapped.sourceAnchor, AnchorPosition.left);
    expect(snapped.sourcePoint, isNull);
    expect(container.read(historyProvider).undoStack, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('moves a connector waypoint as one history edit', (tester) async {
    final source = CanvasNode(
      id: 'waypoint-source',
      type: NodeType.rectangle,
      x: 20,
      y: 60,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final target = CanvasNode(
      id: 'waypoint-target',
      type: NodeType.rectangle,
      x: 200,
      y: 180,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final edge = CanvasEdge(
      id: 'waypoint-edge',
      sourceNodeId: source.id,
      targetNodeId: target.id,
      waypoints: const [Offset(140, 80), Offset(140, 200)],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([source, target]);
    container.read(documentEdgesProvider.notifier).setEdges([edge]);
    container.read(selectionProvider.notifier).select(edge.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'connector-waypoint-test',
            panelController: panelController,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    final globalStart = canvas.topLeft + const Offset(140, 80);
    final drag = await tester.startGesture(globalStart);
    await tester.pump();
    for (var index = 0; index < 5; index++) {
      await drag.moveBy(const Offset(0, 6));
      await tester.pump();
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 50));

    final moved = container.read(documentEdgesProvider).single;
    expect(moved.waypoints, [const Offset(140, 110), const Offset(140, 200)]);
    expect(container.read(historyProvider).undoStack, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('snaps a nearby waypoint to a clean right angle', (tester) async {
    final source = CanvasNode(
      id: 'right-angle-source',
      type: NodeType.rectangle,
      x: 20,
      y: 60,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final target = CanvasNode(
      id: 'right-angle-target',
      type: NodeType.rectangle,
      x: 200,
      y: 180,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final edge = CanvasEdge(
      id: 'right-angle-edge',
      sourceNodeId: source.id,
      targetNodeId: target.id,
      waypoints: const [Offset(140, 110), Offset(140, 200)],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([source, target]);
    container.read(documentEdgesProvider.notifier).setEdges([edge]);
    container.read(selectionProvider.notifier).select(edge.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'connector-right-angle-test',
            panelController: panelController,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    await tester.dragFrom(
      canvas.topLeft + const Offset(140, 110),
      const Offset(0, -24),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final snapped = container.read(documentEdgesProvider).single;
    expect(snapped.waypoints, [const Offset(140, 80), const Offset(140, 200)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moves an orthogonal elbow bar without breaking its corners', (
    tester,
  ) async {
    final source = CanvasNode(
      id: 'elbow-source',
      type: NodeType.rectangle,
      x: 20,
      y: 60,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final target = CanvasNode(
      id: 'elbow-target',
      type: NodeType.rectangle,
      x: 200,
      y: 180,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final edge = CanvasEdge(
      id: 'elbow-edge',
      sourceNodeId: source.id,
      targetNodeId: target.id,
      waypoints: const [Offset(140, 80), Offset(140, 200)],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([source, target]);
    container.read(documentEdgesProvider.notifier).setEdges([edge]);
    container.read(selectionProvider.notifier).select(edge.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'connector-elbow-test',
            panelController: panelController,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    await tester.dragFrom(
      canvas.topLeft + const Offset(140, 140),
      const Offset(40, 0),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final moved = container.read(documentEdgesProvider).single;
    expect(moved.waypoints, [const Offset(180, 80), const Offset(180, 200)]);
    expect(container.read(historyProvider).undoStack, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inserts and removes a waypoint with a segment double tap', (
    tester,
  ) async {
    final source = CanvasNode(
      id: 'double-source',
      type: NodeType.rectangle,
      x: 80,
      y: 100,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final target = CanvasNode(
      id: 'double-target',
      type: NodeType.rectangle,
      x: 400,
      y: 220,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final edge = CanvasEdge(
      id: 'double-edge',
      sourceNodeId: source.id,
      targetNodeId: target.id,
      waypoints: const [Offset(300, 140), Offset(300, 260)],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([source, target]);
    container.read(documentEdgesProvider.notifier).setEdges([edge]);
    container.read(selectionProvider.notifier).select(edge.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'connector-double-tap-test',
            panelController: panelController,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    final segment = canvas.topLeft + const Offset(250, 140);
    await tester.tapAt(segment);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(segment);
    await tester.pump(const Duration(milliseconds: 100));

    final inserted = container.read(documentEdgesProvider).single;
    expect(inserted.waypoints, [
      const Offset(250, 140),
      const Offset(300, 140),
      const Offset(300, 260),
    ]);
    expect(container.read(historyProvider).undoStack, hasLength(1));

    await tester.tapAt(segment);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(segment);
    await tester.pump(const Duration(milliseconds: 100));

    final removed = container.read(documentEdgesProvider).single;
    expect(removed.waypoints, [const Offset(300, 140), const Offset(300, 260)]);
    expect(container.read(historyProvider).undoStack, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape cancels a connector preview without history', (
    tester,
  ) async {
    final source = CanvasNode(
      id: 'cancel-source',
      type: NodeType.rectangle,
      x: 20,
      y: 60,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final target = CanvasNode(
      id: 'cancel-target',
      type: NodeType.rectangle,
      x: 200,
      y: 180,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final edge = CanvasEdge(
      id: 'cancel-edge',
      sourceNodeId: source.id,
      targetNodeId: target.id,
      waypoints: const [Offset(140, 80), Offset(140, 200)],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([source, target]);
    container.read(documentEdgesProvider.notifier).setEdges([edge]);
    container.read(selectionProvider.notifier).select(edge.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'connector-cancel-test',
            panelController: panelController,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    final gesture = await tester.startGesture(
      canvas.topLeft + const Offset(140, 80),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));

    final cancelled = container.read(documentEdgesProvider).single;
    expect(cancelled, edge);
    expect(container.read(historyProvider).undoStack, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drags a connector label along its route with undo and redo', (
    tester,
  ) async {
    final source = CanvasNode(
      id: 'label-source',
      type: NodeType.rectangle,
      x: 20,
      y: 60,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final target = CanvasNode(
      id: 'label-target',
      type: NodeType.rectangle,
      x: 200,
      y: 60,
      width: 60,
      height: 40,
      payload: ShapePayload(),
    );
    final edge = CanvasEdge(
      id: 'label-edge',
      sourceNodeId: source.id,
      targetNodeId: target.id,
      sourceAnchor: AnchorPosition.right,
      targetAnchor: AnchorPosition.left,
      routing: ConnectorRouting.straight,
      label: 'Move me',
      labelPosition: 0.5,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([source, target]);
    container.read(documentEdgesProvider.notifier).setEdges([edge]);
    container.read(selectionProvider.notifier).select(edge.id);
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
    );
    addTearDown(panelController.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'connector-label-test',
            panelController: panelController,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    await tester.dragFrom(
      canvas.topLeft + const Offset(140, 80),
      const Offset(40, 0),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final moved = container.read(documentEdgesProvider).single;
    expect(moved.labelPosition, closeTo(5 / 6, 0.001));
    expect(container.read(historyProvider).undoStack, hasLength(1));

    container.read(documentNodesProvider.notifier).undo();
    expect(container.read(documentEdgesProvider).single.labelPosition, 0.5);
    expect(container.read(historyProvider).undoStack, isEmpty);

    container.read(documentNodesProvider.notifier).redo();
    expect(
      container.read(documentEdgesProvider).single.labelPosition,
      closeTo(5 / 6, 0.001),
    );
    expect(container.read(historyProvider).undoStack, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'double-clicking a shape edits its embedded label without creating text',
    (tester) async {
      final shape = CanvasNode(
        id: 'embedded-label-shape',
        type: NodeType.rectangle,
        x: 100,
        y: 100,
        width: 200,
        height: 100,
        payload: ShapePayload(),
      );
      final document = CanvasDocument(
        projectId: 'embedded-label-test',
        nodes: [shape],
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            CanvasEditorSurface(
              projectId: 'embedded-label-test',
              initialDocument: document,
              services: CanvasEditorServices.embedded,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final canvas = tester.getRect(
        find.byKey(const ValueKey('canvas-render-stack')),
      );
      final shapeLayer = find.byKey(
        const ValueKey('canvas-node-layer-embedded-label-shape'),
      );
      final shapeCenter = tester.getRect(shapeLayer).center;
      await _tapThenDoubleTapAt(tester, shapeCenter);
      final inlineField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.controller?.text == '' &&
            widget.focusNode?.hasFocus == true,
      );
      expect(inlineField, findsOneWidget);

      await tester.enterText(inlineField, 'Process complete');
      await tester.tapAt(canvas.bottomRight - const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 350));

      final edited = container.read(documentNodesProvider).single;
      expect(edited.id, shape.id);
      expect((edited.payload as ShapePayload).label, 'Process complete');
      expect(
        container
            .read(documentNodesProvider)
            .where((node) => node.type == NodeType.text),
        isEmpty,
      );
      expect(container.read(historyProvider).undoStack, hasLength(1));

      container.read(documentNodesProvider.notifier).undo();
      expect(
        (container.read(documentNodesProvider).single.payload as ShapePayload)
            .label,
        '',
      );
      container.read(documentNodesProvider.notifier).redo();
      expect(
        (container.read(documentNodesProvider).single.payload as ShapePayload)
            .label,
        'Process complete',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clearing a shape label keeps the shape in place', (
    tester,
  ) async {
    final shape = CanvasNode(
      id: 'clear-embedded-label-shape',
      type: NodeType.rectangle,
      x: 100,
      y: 100,
      width: 200,
      height: 100,
      payload: ShapePayload(label: 'Existing label'),
    );
    final document = CanvasDocument(
      projectId: 'clear-embedded-label-test',
      nodes: [shape],
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'clear-embedded-label-test',
            initialDocument: document,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shapeLayer = find.byKey(
      const ValueKey('canvas-node-layer-clear-embedded-label-shape'),
    );
    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    final shapeCenter = tester.getRect(shapeLayer).center;
    await _tapThenDoubleTapAt(tester, shapeCenter);

    final inlineField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.controller?.text == 'Existing label' &&
          widget.focusNode?.hasFocus == true,
    );
    expect(inlineField, findsOneWidget);

    await tester.enterText(inlineField, '');
    await tester.tapAt(canvas.bottomRight - const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 350));

    final cleared = container.read(documentNodesProvider);
    expect(cleared, hasLength(1));
    expect(cleared.single.id, shape.id);
    expect((cleared.single.payload as ShapePayload).label, isEmpty);
    expect(cleared.where((node) => node.type == NodeType.text), isEmpty);
    expect(container.read(historyProvider).undoStack, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline text formatting chrome has a one-pixel border', (
    tester,
  ) async {
    final textNode = CanvasNode(
      id: 'inline-text-border-node',
      type: NodeType.text,
      x: 320,
      y: 220,
      width: 160,
      height: 40,
      payload: TextPayload(fontFamily: 'system', spellCheckEnabled: false),
    );
    final document = CanvasDocument(
      projectId: 'inline-text-border-test',
      nodes: [textNode],
      viewport: const canvas_viewport.Viewport(),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'inline-text-border-test',
            initialDocument: document,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textNodeLayer = find.byKey(
      const ValueKey('canvas-node-layer-inline-text-border-node'),
    );
    final textCenter = tester.getRect(textNodeLayer).center;
    await _tapThenDoubleTapAt(tester, textCenter);

    expect(container.read(documentNodesProvider), hasLength(1));
    expect(
      find.byKey(const ValueKey('inline-text-formatting-quick-bar')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, 'Payload text');
    await tester.pumpAndSettle();
    expect(
      (container.read(documentNodesProvider).single.payload as TextPayload)
          .text,
      'Payload text',
    );

    final quickBar = tester.widget<Container>(
      find.byKey(const ValueKey('inline-text-formatting-quick-bar')),
    );
    final border = (quickBar.decoration! as BoxDecoration).border! as Border;
    expect(border.left.width, AppBorder.thin);
    expect(border.top.width, AppBorder.thin);
    expect(border.right.width, AppBorder.thin);
    expect(border.bottom.width, AppBorder.thin);
    final separatorFinder = find.descendant(
      of: find.byKey(const ValueKey('inline-text-formatting-quick-bar')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints ==
                const BoxConstraints.tightFor(
                  width: AppBorder.thin,
                  height: 16,
                ),
      ),
    );
    expect(separatorFinder, findsNWidgets(2));
    for (final separator in tester.widgetList<Container>(separatorFinder)) {
      expect(separator.constraints!.minWidth, AppBorder.thin);
      expect(separator.constraints!.maxWidth, AppBorder.thin);
      expect(
        separator.margin,
        const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      );
      expect(
        tester.getSize(find.byWidget(separator)),
        const Size(AppBorder.thin + AppSpacing.xs * 2, 16),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('shape label editor has no field chrome', (tester) async {
    final shape = CanvasNode(
      id: 'transparent-embedded-label-shape',
      type: NodeType.rectangle,
      x: 100,
      y: 100,
      width: 200,
      height: 100,
      payload: ShapePayload(label: 'Existing label'),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final document = CanvasDocument(
      projectId: 'transparent-embedded-label-test',
      nodes: [shape],
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: 'transparent-embedded-label-test',
            initialDocument: document,
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shapeLayer = find.byKey(
      const ValueKey('canvas-node-layer-transparent-embedded-label-shape'),
    );
    final shapeCenter = tester.getRect(shapeLayer).center;
    await _tapThenDoubleTapAt(tester, shapeCenter);

    final editorFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.controller?.text == 'Existing label' &&
          widget.focusNode?.hasFocus == true,
    );
    expect(editorFinder, findsOneWidget);
    final shapeRect = tester.getRect(
      find.byKey(
        const ValueKey('canvas-node-layer-transparent-embedded-label-shape'),
      ),
    );
    final editorRect = tester.getRect(editorFinder);
    expect(editorRect.center.dx, closeTo(shapeRect.center.dx, 0.1));
    expect(editorRect.width, closeTo(shapeRect.width - 16.0, 0.1));
    expect(editorRect.height, closeTo(shapeRect.height, 0.1));
    final editor = tester.widget<TextField>(editorFinder);
    expect(editor.controller?.selection.baseOffset, 0);
    expect(editor.controller?.selection.extentOffset, 'Existing label'.length);
    expect(editor.decoration?.border, InputBorder.none);
    expect(editor.decoration?.enabledBorder, InputBorder.none);
    expect(editor.decoration?.focusedBorder, InputBorder.none);
    expect(editor.decoration?.filled, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Color _pixel(ByteData data, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

Future<void> _tapThenDoubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(position);
  await tester.pumpAndSettle();
}
