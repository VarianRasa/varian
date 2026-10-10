import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/utils/hit_tester.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';

void main() {
  group('CanvasHitTester Tests', () {
    final node1 = CanvasNode(
      id: '1',
      type: NodeType.rectangle,
      x: 100,
      y: 100,
      width: 100,
      height: 100,
      zIndex: 1,
      payload: ShapePayload(),
    );

    final node2 = CanvasNode(
      id: '2',
      type: NodeType.rectangle,
      x: 150,
      y: 150,
      width: 100,
      height: 100,
      zIndex: 2,
      payload: ShapePayload(),
    );

    test('Hit test single point returns topmost z-index node', () {
      final hit = CanvasHitTester.hitTest([
        node1,
        node2,
      ], const Offset(160, 160));
      expect(hit, isNotNull);
      expect(hit!.id, '2');
    });

    test('Hit test outside returns null', () {
      final hit = CanvasHitTester.hitTest([
        node1,
        node2,
      ], const Offset(500, 500));
      expect(hit, isNull);
    });

    test('Hit test marquee selects intersecting nodes', () {
      final hits = CanvasHitTester.hitTestMarquee([
        node1,
        node2,
      ], const Rect.fromLTWH(50, 50, 250, 250));
      expect(hits.length, 2);
    });

    test('Hit testing excludes locked and hidden nodes', () {
      final locked = node2.copyWith(locked: true);
      final hidden = node2.copyWith(id: 'hidden', visible: false);
      expect(CanvasHitTester.hitTest([locked], const Offset(160, 160)), isNull);
      expect(CanvasHitTester.hitTest([hidden], const Offset(160, 160)), isNull);
      expect(
        CanvasHitTester.hitTestMarquee([
          locked,
          hidden,
        ], const Rect.fromLTWH(100, 100, 200, 200)),
        isEmpty,
      );
    });

    test('Generic radius handle is available for polygonal diagram shapes', () {
      final definition = DiagramShapeCatalog.resolve('rhombus');
      final node = CanvasNode(
        id: 'rhombus-1',
        type: NodeType.diamond,
        x: 100,
        y: 100,
        width: 160,
        height: 100,
        zIndex: 1,
        payload: ShapePayload(diagramShapeId: 'rhombus', cornerRadius: 18),
      );
      final handle = definition.cornerRadiusHandlePosition(
        const Size(160, 100),
        18,
      )!;

      final hit = CanvasHitTester.hitTestHandle(
        [node],
        {'rhombus-1'},
        Offset(node.x + handle.dx, node.y + handle.dy),
        1.0,
      );

      expect(hit, ('rhombus-1', ResizeHandle.cornerRadius));
    });

    test('Intrinsic curves keep their specialized handles', () {
      for (final entry in [
        (id: 'ellipse', type: NodeType.ellipse),
        (id: 'circle', type: NodeType.ellipse),
        (id: 'cylinder', type: NodeType.cylinder),
        (id: 'cloud', type: NodeType.rectangle),
        (id: 'uml.actor', type: NodeType.rectangle),
      ]) {
        final node = CanvasNode(
          id: entry.id,
          type: entry.type,
          x: 100,
          y: 100,
          width: 160,
          height: 100,
          zIndex: 1,
          payload: ShapePayload(diagramShapeId: entry.id),
        );
        final hit = CanvasHitTester.hitTestHandle(
          [node],
          {entry.id},
          const Offset(114, 114),
          1.0,
        );
        expect(hit?.$2, isNot(ResizeHandle.cornerRadius), reason: entry.id);
      }
    });

    test('Radius drag math updates all corner values consistently', () {
      final definition = DiagramShapeCatalog.resolve('triangle');
      const size = Size(160, 100);
      final handle = definition.cornerRadiusHandlePosition(size, 18)!;
      final dragged = handle + const Offset(0, 10);
      final radius = definition.cornerRadiusFromHandle(size, dragged);
      final payload = ShapePayload(
        cornerRadius: 18,
      ).copyWith(cornerRadius: radius);

      expect(radius, closeTo(28, 0.01));
      expect(payload.topLeftRadius, closeTo(28, 0.01));
      expect(payload.topRightRadius, closeTo(28, 0.01));
      expect(payload.bottomRightRadius, closeTo(28, 0.01));
      expect(payload.bottomLeftRadius, closeTo(28, 0.01));
    });
  });
}
