import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/utils/connector_router.dart';
import 'package:varian/features/canvas/utils/snap_engine.dart';

void main() {
  group('Connector & Snapping Engine Tests', () {
    test('Anchor points calculated properly', () {
      final node = CanvasNode(
        id: 'test_node',
        type: NodeType.rectangle,
        x: 100,
        y: 100,
        width: 200,
        height: 100,
        payload: ShapePayload(),
      );

      expect(
        ConnectorRouter.getAnchorPoint(node, AnchorPosition.top),
        const Offset(200, 100),
      );
      expect(
        ConnectorRouter.getAnchorPoint(node, AnchorPosition.right),
        const Offset(300, 150),
      );
      expect(
        ConnectorRouter.getAnchorPoint(node, AnchorPosition.bottom),
        const Offset(200, 200),
      );
      expect(
        ConnectorRouter.getAnchorPoint(node, AnchorPosition.left),
        const Offset(100, 150),
      );
    });

    test('resolves free endpoints and manual waypoints into one route', () {
      final source = CanvasNode(
        id: 'source',
        type: NodeType.rectangle,
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );
      final edge = CanvasEdge(
        id: 'free-target',
        sourceNodeId: source.id,
        sourceAnchor: AnchorPosition.right,
        targetPoint: const Offset(500, 300),
        targetAnchor: AnchorPosition.left,
        waypoints: [const Offset(300, 150), const Offset(300, 300)],
      );

      expect(ConnectorRouter.routePointsForEdge(edge, {source.id: source}), [
        const Offset(200, 150),
        const Offset(300, 150),
        const Offset(300, 300),
        const Offset(500, 300),
      ]);
    });

    test('chooses the nearest shape anchor for endpoint snapping', () {
      final node = CanvasNode(
        id: 'snap-node',
        type: NodeType.rectangle,
        x: 100,
        y: 100,
        width: 200,
        height: 100,
        payload: ShapePayload(),
      );

      expect(
        ConnectorRouter.nearestAnchor(node, const Offset(305, 150)),
        AnchorPosition.right,
      );
      expect(
        ConnectorRouter.nearestAnchor(node, const Offset(200, 95)),
        AnchorPosition.top,
      );
    });

    test(
      'moves an elbow segment while keeping its connected corners aligned',
      () {
        const edge = CanvasEdge(
          id: 'elbow',
          sourcePoint: Offset(100, 100),
          targetPoint: Offset(400, 300),
          waypoints: [Offset(250, 100), Offset(250, 300)],
        );
        final moved = ConnectorRouter.moveSegment(
          edge,
          const {},
          segmentIndex: 1,
          delta: const Offset(40, 0),
        );

        expect(moved, [const Offset(290, 100), const Offset(290, 300)]);
      },
    );

    test('finds an anchor only inside the connector snap radius', () {
      final node = CanvasNode(
        id: 'snap-node',
        type: NodeType.rectangle,
        x: 100,
        y: 100,
        width: 200,
        height: 100,
        payload: ShapePayload(),
      );

      final snapped = ConnectorRouter.nearestAnchorWithin(
        node,
        const Offset(304, 150),
        radius: 8,
      );
      final missed = ConnectorRouter.nearestAnchorWithin(
        node,
        const Offset(320, 150),
        radius: 8,
      );

      expect(snapped?.$1, AnchorPosition.right);
      expect(snapped?.$2, const Offset(300, 150));
      expect(missed, isNull);
    });

    test('maps a normalized label position along a multi-segment route', () {
      const route = [
        Offset(80, 80),
        Offset(140, 80),
        Offset(140, 200),
        Offset(200, 200),
      ];

      expect(
        ConnectorRouter.pointAtRouteFraction(route, 0.25),
        const Offset(140, 80),
      );
      expect(
        ConnectorRouter.pointAtRouteFraction(route, 0.625),
        const Offset(140, 170),
      );
      expect(
        ConnectorRouter.routeFractionForPoint(route, const Offset(140, 170)),
        closeTo(0.625, 0.0001),
      );
    });

    test('clamps label position to the route endpoints', () {
      const route = [Offset(10, 10), Offset(110, 10)];

      expect(
        ConnectorRouter.pointAtRouteFraction(route, -1),
        const Offset(10, 10),
      );
      expect(
        ConnectorRouter.pointAtRouteFraction(route, 2),
        const Offset(110, 10),
      );
      expect(
        ConnectorRouter.routeFractionForPoint(route, const Offset(80, 40)),
        closeTo(0.7, 0.0001),
      );
    });

    test('skips zero-length segments when mapping label positions', () {
      const route = [Offset.zero, Offset.zero, Offset(100, 0), Offset(100, 0)];

      expect(
        ConnectorRouter.pointAtRouteFraction(route, 0.5),
        const Offset(50, 0),
      );
      expect(
        ConnectorRouter.routeFractionForPoint(route, const Offset(75, 20)),
        closeTo(0.75, 0.0001),
      );
    });

    test('creates two thin parallel guide lines around a connector bar', () {
      final guides = ConnectorRouter.segmentHandleGuides(
        const Offset(50, 100),
        const Offset(150, 100),
      );

      expect(guides, hasLength(2));
      expect(guides[0].$1, const Offset(90, 103));
      expect(guides[0].$2, const Offset(110, 103));
      expect(guides[1].$1, const Offset(90, 97));
      expect(guides[1].$2, const Offset(110, 97));
    });

    test('detects right-angle corners within a small tolerance', () {
      expect(
        ConnectorRouter.isRightAngle(
          const Offset(100, 100),
          const Offset(100, 200),
          const Offset(240, 200),
        ),
        isTrue,
      );
      expect(
        ConnectorRouter.isRightAngle(
          const Offset(100, 100),
          const Offset(170, 170),
          const Offset(240, 200),
        ),
        isFalse,
      );
      expect(
        ConnectorRouter.isRightAngle(
          const Offset(100, 100),
          const Offset(100, 100),
          const Offset(240, 200),
        ),
        isFalse,
      );
    });

    test('snaps a nearby waypoint to the closest square corner', () {
      expect(
        ConnectorRouter.snapCornerToRightAngle(
          const Offset(100, 100),
          const Offset(106, 194),
          const Offset(240, 200),
          tolerance: 10,
        ),
        const Offset(100, 200),
      );
      expect(
        ConnectorRouter.snapCornerToRightAngle(
          const Offset(100, 100),
          const Offset(150, 150),
          const Offset(240, 200),
          tolerance: 10,
        ),
        isNull,
      );
    });

    test('Magnetic snap detects aligned edges within threshold', () {
      final node1 = CanvasNode(
        id: 'node1',
        type: NodeType.rectangle,
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );

      final snapResult = SnapEngine.calculateSnap(
        targetRect: const Rect.fromLTWH(103, 250, 100, 100),
        otherNodes: [node1],
      );

      expect(snapResult.dx, -3.0);
      expect(snapResult.guides.length, 1);
      expect(snapResult.guides.first.isVertical, true);
    });
  });
}
