import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_surface.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';
import '../../test_app.dart';

void main() {
  testWidgets('creates a selected native diagram shape by dragging', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeDiagramShapeProvider.notifier).state =
        DiagramShapeCatalog.resolve('hexagon');
    container
        .read(activeToolProvider.notifier)
        .setTool(CanvasTool.diagramShape);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const CanvasEditorSurface(
            projectId: 'native-diagram-create-test',
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(container.read(activeToolProvider), CanvasTool.diagramShape);
    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    final gesture = await tester.startGesture(
      canvas.topLeft + const Offset(80, 80),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(80, 60));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pump();

    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    expect(nodes.single.type.name, 'rectangle');
    final payload = nodes.single.payload as ShapePayload;
    expect(payload.diagramShapeId, 'hexagon');
    expect(
      find.byWidgetPredicate((widget) => widget is TextField && widget.expands),
      findsOneWidget,
    );
    expect(container.read(activeToolProvider), CanvasTool.select);
    expect(
      find.byKey(ValueKey('canvas-node-layer-${nodes.single.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates a native diagram shape by clicking the canvas', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeDiagramShapeProvider.notifier).state =
        DiagramShapeCatalog.resolve('hexagon');
    container
        .read(activeToolProvider.notifier)
        .setTool(CanvasTool.diagramShape);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const CanvasEditorSurface(
            projectId: 'native-diagram-click-test',
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvasFinder = find.byKey(const ValueKey('canvas-render-stack'));
    expect(canvasFinder, findsOneWidget);
    expect(container.read(activeToolProvider), CanvasTool.diagramShape);
    await tester.tap(canvasFinder);
    await tester.pump(const Duration(milliseconds: 400));

    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    expect((nodes.single.payload as ShapePayload).diagramShapeId, 'hexagon');
    expect(container.read(activeToolProvider), CanvasTool.select);
    expect(
      find.byWidgetPredicate((widget) => widget is TextField && widget.expands),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'creates a native diagram shape when dragged from a palette item',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            Stack(
              children: [
                const CanvasEditorSurface(
                  projectId: 'native-diagram-drop-test',
                  services: CanvasEditorServices.embedded,
                ),
                Positioned(
                  left: 20,
                  top: 20,
                  child: Draggable<DiagramShapeDefinition>(
                    data: DiagramShapeCatalog.resolve('circle'),
                    feedback: const SizedBox(width: 40, height: 40),
                    child: Container(
                      key: const ValueKey('diagram-shape-drag-source'),
                      width: 60,
                      height: 60,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final source = tester.getRect(
        find.byKey(const ValueKey('diagram-shape-drag-source')),
      );
      final target = tester.getRect(
        find.byKey(const ValueKey('diagram-shape-drop-target')),
      );
      await tester.dragFrom(source.center, target.center - source.center);
      await tester.pump(const Duration(milliseconds: 400));

      final nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(1));
      expect((nodes.single.payload as ShapePayload).diagramShapeId, 'circle');
      expect(nodes.single.type, NodeType.ellipse);
      expect(nodes.single.width, 100);
      expect(nodes.single.height, 100);
      expect(container.read(activeToolProvider), CanvasTool.select);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('creates primitive shapes with their native geometry', (
    tester,
  ) async {
    final created = <CanvasNode>[];
    final containers = <ProviderContainer>[];
    addTearDown(() {
      for (final container in containers) {
        container.dispose();
      }
    });

    for (final shapeId in [
      'rectangle',
      'roundedRectangle',
      'ellipse',
      'circle',
    ]) {
      final container = ProviderContainer();
      containers.add(container);
      container.read(activeDiagramShapeProvider.notifier).state =
          DiagramShapeCatalog.resolve(shapeId);
      container
          .read(activeToolProvider.notifier)
          .setTool(CanvasTool.diagramShape);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            CanvasEditorSurface(
              projectId: 'native-diagram-primitive-$shapeId',
              services: CanvasEditorServices.embedded,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('canvas-render-stack')));
      await tester.pump(const Duration(milliseconds: 400));

      final nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(1));
      expect(container.read(activeToolProvider), CanvasTool.select);
      created.add(nodes.single);
      container.dispose();
    }

    final byShapeId = {
      for (final node in created)
        (node.payload as ShapePayload).diagramShapeId!: node,
    };
    expect(byShapeId['rectangle']!.type, NodeType.rectangle);
    expect((byShapeId['rectangle']!.payload as ShapePayload).cornerRadius, 0);
    expect(byShapeId['roundedRectangle']!.type, NodeType.rectangle);
    expect(
      (byShapeId['roundedRectangle']!.payload as ShapePayload).cornerRadius,
      greaterThan(0),
    );
    expect(byShapeId['ellipse']!.type, NodeType.ellipse);
    expect(byShapeId['circle']!.type, NodeType.ellipse);
    expect(byShapeId['ellipse']!.width, 160);
    expect(byShapeId['ellipse']!.height, 100);
    expect(byShapeId['circle']!.width, 100);
    expect(byShapeId['circle']!.height, 100);
    expect(tester.takeException(), isNull);
  });
}
