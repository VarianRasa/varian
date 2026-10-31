import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_surface.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
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
      final surfaceState = tester.state(find.byType(CanvasEditorSurface));
      final preview =
          (surfaceState as dynamic).debugImageCache.getImage(expectedReference)
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
