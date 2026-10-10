import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_panel_controller.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_surface.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import 'package:varian/features/canvas/state/viewport_provider.dart';
import 'package:varian/features/canvas/utils/hit_tester.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';
import '../../test_app.dart';

void main() {
  group('Interactive Resize Handles & Scaling Tests', () {
    test(
      'CanvasHitTester detects resize handles correctly on selected nodes',
      () {
        final node = CanvasNode(
          id: 'node_1',
          type: NodeType.rectangle,
          x: 100,
          y: 100,
          width: 200,
          height: 150,
          payload: ShapePayload(),
        );

        final nodes = [node];
        final selectedIds = {'node_1'};

        // Test topLeft handle at (100, 100)
        final hitTopLeft = CanvasHitTester.hitTestHandle(
          nodes,
          selectedIds,
          const Offset(102, 101),
          1.0,
        );
        expect(hitTopLeft, isNotNull);
        expect(hitTopLeft!.$1, 'node_1');
        expect(hitTopLeft.$2, ResizeHandle.topLeft);

        // Test bottomRight handle at (300, 250)
        final hitBottomRight = CanvasHitTester.hitTestHandle(
          nodes,
          selectedIds,
          const Offset(299, 249),
          1.0,
        );
        expect(hitBottomRight, isNotNull);
        expect(hitBottomRight!.$1, 'node_1');
        expect(hitBottomRight.$2, ResizeHandle.bottomRight);

        // Test middle of node (should not trigger handle)
        final hitCenter = CanvasHitTester.hitTestHandle(
          nodes,
          selectedIds,
          const Offset(200, 175),
          1.0,
        );
        expect(hitCenter, isNull);

        final rotationHandle = CanvasSelectionGeometry.rotationHandlePosition(
          node,
          zoom: 1.0,
        );
        final hitRotation = CanvasHitTester.hitTestHandle(
          nodes,
          selectedIds,
          rotationHandle,
          1.0,
        );
        expect(hitRotation, isNotNull);
        expect(hitRotation!.$1, 'node_1');
        expect(hitRotation.$2, ResizeHandle.rotation);
      },
    );

    testWidgets('Dragging the radius handle updates the diagram payload', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final panelController = CanvasEditorPanelController(
        initialShowLayers: false,
        initialShowInspector: false,
      );
      addTearDown(panelController.dispose);
      final node = CanvasNode(
        id: 'triangle-radius',
        type: NodeType.rectangle,
        x: 120,
        y: 100,
        width: 160,
        height: 100,
        zIndex: 1,
        payload: ShapePayload(diagramShapeId: 'triangle', cornerRadius: 0),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            CanvasEditorSurface(
              projectId: 'diagram-radius-drag-test',
              panelController: panelController,
              services: CanvasEditorServices.embedded,
            ),
          ),
        ),
      );
      await tester.pump();

      container.read(documentNodesProvider.notifier).addNode(node);
      container.read(selectionProvider.notifier).select(node.id);
      await tester.pump();

      final definition = DiagramShapeCatalog.resolve('triangle');
      final handle = definition.cornerRadiusHandlePosition(
        const Size(160, 100),
        0,
      )!;
      final surface = tester.getRect(
        find.byKey(const ValueKey('canvas-pointer-surface')),
      );
      final nodeLayer = tester.getRect(
        find.byKey(const ValueKey('canvas-node-layer-triangle-radius')),
      );
      final start =
          surface.topLeft + (nodeLayer.topLeft - surface.topLeft) + handle;
      final localStart = start - surface.topLeft;
      final worldStart = container
          .read(viewportProvider.notifier)
          .toWorld(localStart);
      final handleHit = CanvasHitTester.hitTestHandle(
        [node],
        {node.id},
        worldStart,
        container.read(viewportProvider).zoom,
      );
      expect(container.read(activeToolProvider), CanvasTool.select);
      expect(surface.contains(start), isTrue);
      expect(worldStart.dx, closeTo(node.x + handle.dx, 0.01));
      expect(worldStart.dy, closeTo(node.y + handle.dy, 0.01));
      expect(handleHit?.$2, ResizeHandle.cornerRadius);

      final gesture = await tester.startGesture(start);
      await tester.pump();
      // Cross Flutter's touch slop, then emit an update after pan starts.
      for (var index = 0; index < 5; index++) {
        await gesture.moveBy(const Offset(0, 5));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));

      final updated = container.read(documentNodesProvider).single;
      final payload = updated.payload as ShapePayload;
      expect(payload.cornerRadius, greaterThan(0));
      expect(payload.topLeftRadius, payload.cornerRadius);
      expect(payload.topRightRadius, payload.cornerRadius);
      expect(payload.bottomRightRadius, payload.cornerRadius);
      expect(payload.bottomLeftRadius, payload.cornerRadius);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dragging the rotation handle updates the node rotation', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final panelController = CanvasEditorPanelController(
        initialShowLayers: false,
        initialShowInspector: false,
      );
      addTearDown(panelController.dispose);
      final node = CanvasNode(
        id: 'rotation-drag',
        type: NodeType.rectangle,
        x: 120,
        y: 100,
        width: 160,
        height: 100,
        zIndex: 1,
        payload: ShapePayload(),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            CanvasEditorSurface(
              projectId: 'rotation-drag-test',
              panelController: panelController,
              services: CanvasEditorServices.embedded,
            ),
          ),
        ),
      );
      await tester.pump();

      container.read(documentNodesProvider.notifier).addNode(node);
      container.read(selectionProvider.notifier).select(node.id);
      await tester.pump();

      final surface = tester.getRect(
        find.byKey(const ValueKey('canvas-pointer-surface')),
      );
      final nodeLayer = tester.getRect(
        find.byKey(const ValueKey('canvas-node-layer-rotation-drag')),
      );
      final viewport = container.read(viewportProvider);
      final rotationHandle = CanvasSelectionGeometry.rotationHandlePosition(
        node,
        zoom: viewport.zoom,
      );
      final nodeOrigin = Offset(node.x, node.y);
      final start =
          nodeLayer.topLeft + (rotationHandle - nodeOrigin) * viewport.zoom;
      final center = Offset(node.x + node.width / 2, node.y + node.height / 2);
      final targetWorld = center + const Offset(60, 0);
      final target =
          nodeLayer.topLeft + (targetWorld - nodeOrigin) * viewport.zoom;
      final localStart = start - surface.topLeft;
      final worldStart = container
          .read(viewportProvider.notifier)
          .toWorld(localStart);

      expect(
        CanvasHitTester.hitTestHandle(
          [node],
          {node.id},
          worldStart,
          viewport.zoom,
        )?.$2,
        ResizeHandle.rotation,
      );

      final gesture = await tester.startGesture(start);
      await tester.pump();
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        container.read(documentNodesProvider).single.rotation,
        closeTo(math.pi / 2, 0.0001),
      );
      expect(tester.takeException(), isNull);
    });

    test('Resizing updates node dimensions and scales vector paths', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialVectorNode = CanvasNode(
        id: 'vec_1',
        type: NodeType.vectorPath,
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        payload: VectorPathPayload(
          points: const [
            BezierPoint(point: Offset(0, 0)),
            BezierPoint(point: Offset(100, 100)),
          ],
        ),
      );

      container.read(documentNodesProvider.notifier).addNode(initialVectorNode);

      const double scaleX = 2.0; // W = 200
      const double scaleY = 2.0; // H = 200

      final vp = initialVectorNode.payload as VectorPathPayload;
      final scaledPoints = vp.points
          .map(
            (bp) => BezierPoint(
              point: Offset(bp.point.dx * scaleX, bp.point.dy * scaleY),
            ),
          )
          .toList();

      final updated = initialVectorNode.copyWith(
        width: 200,
        height: 200,
        payload: vp.copyWith(points: scaledPoints),
      );

      container.read(documentNodesProvider.notifier).updateNode(updated);

      final nodes = container.read(documentNodesProvider);
      expect(nodes.first.width, 200.0);
      expect(nodes.first.height, 200.0);
      final updatedPayload = nodes.first.payload as VectorPathPayload;
      expect(updatedPayload.points.last.point.dx, 200.0);
      expect(updatedPayload.points.last.point.dy, 200.0);
    });
  });
}
