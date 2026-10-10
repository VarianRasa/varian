import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/utils/hit_tester.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  group('Smart Connector Edge Selection and Advanced Styling Tests', () {
    test('serializes strokeStyle, markers, isAnimated, and routing', () {
      const edge = CanvasEdge(
        id: 'edge-123',
        sourceNodeId: 'node-1',
        sourceAnchor: AnchorPosition.right,
        targetNodeId: 'node-2',
        targetAnchor: AnchorPosition.left,
        routing: ConnectorRouting.curved,
        strokeColor: Color(0xFF10B981),
        strokeWidth: 3.5,
        strokeStyle: StrokeStyle.dashed,
        startMarker: LineMarker.circle,
        endMarker: LineMarker.diamond,
        isAnimated: true,
        label: 'HTTP Payload',
        labelPosition: 0.25,
        waypoints: [Offset(260, 150), Offset(260, 260)],
      );

      final json = edge.toJson();
      final restored = CanvasEdge.fromJson(json);

      expect(restored.id, 'edge-123');
      expect(restored.sourceNodeId, 'node-1');
      expect(restored.targetNodeId, 'node-2');
      expect(restored.routing, ConnectorRouting.curved);
      expect(restored.strokeColor, const Color(0xFF10B981));
      expect(restored.strokeWidth, 3.5);
      expect(restored.strokeStyle, StrokeStyle.dashed);
      expect(restored.startMarker, LineMarker.circle);
      expect(restored.endMarker, LineMarker.diamond);
      expect(restored.isAnimated, isTrue);
      expect(restored.label, 'HTTP Payload');
      expect(restored.labelPosition, 0.25);
      expect(restored.waypoints, [
        const Offset(260, 150),
        const Offset(260, 260),
      ]);
    });

    test('defaults and clamps persisted label positions', () {
      final legacy = CanvasEdge.fromJson({'id': 'legacy-edge'});
      final restored = CanvasEdge.fromJson({
        'id': 'clamped-edge',
        'labelPosition': 2.0,
      });
      const direct = CanvasEdge(id: 'direct-edge', labelPosition: -1.0);

      expect(legacy.labelPosition, 0.5);
      expect(restored.labelPosition, 1.0);
      expect(direct.normalizedLabelPosition, 0.0);
      expect(direct.toJson()['labelPosition'], 0.0);
    });

    test('round-trips detached endpoints and manual waypoints', () {
      const edge = CanvasEdge(
        id: 'free-edge',
        sourcePoint: Offset(20, 30),
        targetNodeId: 'node-2',
        targetAnchor: AnchorPosition.left,
        waypoints: [Offset(120, 30), Offset(120, 90)],
      );

      final restored = CanvasEdge.fromJson(edge.toJson());

      expect(restored.sourceNodeId, isNull);
      expect(restored.sourcePoint, const Offset(20, 30));
      expect(restored.targetNodeId, 'node-2');
      expect(restored.targetPoint, isNull);
      expect(restored.waypoints, [
        const Offset(120, 30),
        const Offset(120, 90),
      ]);
    });

    test('hits test edge successfully when clicking on its routed path', () {
      final node1 = CanvasNode(
        id: 'n1',
        type: NodeType.rectangle,
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );
      final node2 = CanvasNode(
        id: 'n2',
        type: NodeType.rectangle,
        x: 400,
        y: 100,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );

      // Start is at right anchor (200, 150), End is at left anchor (400, 150)
      const edge = CanvasEdge(
        id: 'e1',
        sourceNodeId: 'n1',
        sourceAnchor: AnchorPosition.right,
        targetNodeId: 'n2',
        targetAnchor: AnchorPosition.left,
        routing: ConnectorRouting.straight,
      );

      final nodeMap = {'n1': node1, 'n2': node2};

      // Click exactly at the middle of the edge (300, 150)
      final hit = CanvasHitTester.hitTestEdge(
        [edge],
        nodeMap,
        const Offset(300, 150),
        tolerance: 8.0,
      );
      expect(hit, isNotNull);
      expect(hit!.id, 'e1');

      // Click far away
      final miss = CanvasHitTester.hitTestEdge(
        [edge],
        nodeMap,
        const Offset(300, 400),
        tolerance: 8.0,
      );
      expect(miss, isNull);
    });

    test('detects connector endpoints, waypoints, and elbow bars', () {
      final node1 = CanvasNode(
        id: 'n1',
        type: NodeType.rectangle,
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );
      final node2 = CanvasNode(
        id: 'n2',
        type: NodeType.rectangle,
        x: 400,
        y: 200,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );
      const edge = CanvasEdge(
        id: 'e1',
        sourceNodeId: 'n1',
        sourceAnchor: AnchorPosition.right,
        targetNodeId: 'n2',
        targetAnchor: AnchorPosition.left,
        waypoints: [Offset(300, 150), Offset(300, 250)],
      );
      final nodeMap = {'n1': node1, 'n2': node2};

      final endpoint = CanvasHitTester.hitTestConnectorControl(
        [edge],
        nodeMap,
        {'e1'},
        const Offset(200, 150),
        zoom: 1,
      );
      final waypoint = CanvasHitTester.hitTestConnectorControl(
        [edge],
        nodeMap,
        {'e1'},
        const Offset(300, 150),
        zoom: 1,
      );
      final bar = CanvasHitTester.hitTestConnectorControl(
        [edge],
        nodeMap,
        {'e1'},
        const Offset(250, 150),
        zoom: 1,
      );
      final label = CanvasHitTester.hitTestConnectorControl(
        [edge.copyWith(label: 'Yes')],
        nodeMap,
        {'e1'},
        const Offset(300, 200),
        zoom: 1,
      );

      expect(endpoint?.kind, ConnectorControlKind.sourceEndpoint);
      expect(waypoint?.kind, ConnectorControlKind.waypoint);
      expect(waypoint?.waypointIndex, 0);
      expect(bar?.kind, ConnectorControlKind.segment);
      expect(bar?.segmentIndex, 0);
      expect(label?.kind, ConnectorControlKind.label);
    });

    test('exports edge with accurate routing and dashed style in SVG', () {
      final node1 = CanvasNode(
        id: 'n1',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );
      final node2 = CanvasNode(
        id: 'n2',
        type: NodeType.rectangle,
        x: 300,
        y: 200,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );

      const edge = CanvasEdge(
        id: 'e1',
        sourceNodeId: 'n1',
        sourceAnchor: AnchorPosition.bottom, // (50, 100)
        targetNodeId: 'n2',
        targetAnchor: AnchorPosition.top, // (350, 200)
        routing: ConnectorRouting.orthogonal,
        strokeStyle: StrokeStyle.dashed,
        strokeWidth: 2.0,
        endMarker: LineMarker.arrow,
        label: 'Connects',
        labelPosition: 0.75,
      );

      final doc = CanvasDocument(
        projectId: 'edge-svg-test',
        updatedAt: DateTime(2026),
        nodes: [node1, node2],
        edges: [edge],
      );

      final svg = ExportService.exportVectorSvg(doc);

      expect(svg, contains('stroke-dasharray="6,4"'));
      expect(svg, contains('marker-end="url(#arrow)"'));
      expect(svg, contains('x="300.0" y="142.0"'));
      expect(svg, contains('Connects'));
    });

    test('exports detached endpoints and manual waypoints in SVG', () {
      final target = CanvasNode(
        id: 'target',
        type: NodeType.rectangle,
        x: 200,
        y: 80,
        width: 100,
        height: 80,
        payload: ShapePayload(),
      );
      final edge = CanvasEdge(
        id: 'free-edge',
        sourcePoint: const Offset(-40, 120),
        targetNodeId: target.id,
        targetAnchor: AnchorPosition.left,
        waypoints: const [Offset(80, 120), Offset(80, 180)],
      );
      final doc = CanvasDocument(
        projectId: 'free-edge-svg-test',
        updatedAt: DateTime(2026),
        nodes: [target],
        edges: [edge],
      );

      final svg = ExportService.exportVectorSvg(doc);

      expect(svg, contains('M -40.0 120.0 L 80.0 120.0 L 80.0 180.0'));
      expect(svg, contains('viewBox="-80.0 40.0'));
    });
  });
}
