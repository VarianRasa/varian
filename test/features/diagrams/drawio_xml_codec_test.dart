import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/diagrams/data/drawio_xml_codec.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';

void main() {
  const source = '''<mxGraphModel dx="1200" dy="800" grid="1">
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <mxCell id="lane" value="Main" style="swimlane;horizontal=0;" vertex="1" parent="1">
      <mxGeometry x="40" y="40" width="700" height="420" as="geometry"/>
    </mxCell>
    <mxCell id="start" value="Start &amp; Go" style="shape=ellipse;fillColor=#10B981;strokeColor=#047857;fontColor=#FFFFFF;fontSize=18;rounded=1;shadow=1;rotation=15;" vertex="1" parent="lane" data-custom="retain">
      <mxGeometry x="40" y="60" width="140" height="70" as="geometry"/>
    </mxCell>
    <mxCell id="decision" value="Ready?" style="shape=rhombus;dashed=1;strokeWidth=3;" vertex="1" parent="lane">
      <mxGeometry x="300" y="60" width="160" height="90" as="geometry"/>
    </mxCell>
    <mxCell id="edge" value="Yes" style="edgeStyle=orthogonalEdgeStyle;rounded=0;dashed=1;startArrow=oval;endArrow=classic;strokeColor=#F97316;" edge="1" source="start" target="decision" parent="lane">
      <mxGeometry relative="1" as="geometry">
        <Array as="points"><mxPoint x="220" y="95"/><mxPoint x="260" y="95"/></Array>
      </mxGeometry>
    </mxCell>
  </root>
</mxGraphModel>''';

  test(
    'imports geometry, hierarchy, style, labels, markers, and waypoints',
    () {
      final result = DrawioXmlCodec.importDocument(source);

      expect(result.isSuccess, isTrue);
      expect(result.nodes, hasLength(3));
      expect(result.edges, hasLength(1));

      final lane = result.nodes.firstWhere((node) => node.id == 'lane');
      final lanePayload = lane.payload as FramePayload;
      expect(lanePayload.rawDrawioStyle, contains('horizontal=0'));
      expect(lanePayload.rawDrawioCellXml, contains('id="lane"'));

      final start = result.nodes.firstWhere((node) => node.id == 'start');
      final startPayload = start.payload as ShapePayload;
      expect(start.parentId, 'lane');
      expect(startPayload.diagramShapeId, 'ellipse');
      expect(startPayload.rawDrawioStyle, contains('fillColor=#10B981'));
      expect(startPayload.label, 'Start & Go');
      expect(startPayload.fill, const Color(0xFF10B981));
      expect(startPayload.labelFontSize, 18);
      expect(startPayload.hasShadow, isTrue);
      expect(start.rotation, closeTo(15 * 3.141592653589793 / 180, 0.0001));

      final edge = result.edges.single;
      expect(edge.sourceNodeId, 'start');
      expect(edge.targetNodeId, 'decision');
      expect(edge.routing, ConnectorRouting.orthogonal);
      expect(edge.waypoints, hasLength(2));
      expect(edge.startMarker, LineMarker.circle);
      expect(edge.endMarker, LineMarker.arrow);
      expect(edge.strokeStyle, StrokeStyle.dashed);
      expect(edge.label, 'Yes');
      expect(edge.parentId, 'lane');
      expect(edge.rawDrawioCellXml, contains('id="edge"'));

      final restoredEdge = CanvasEdge.fromJson(edge.toJson());
      expect(restoredEdge.parentId, 'lane');
      expect(restoredEdge.rawDrawioStyle, edge.rawDrawioStyle);
    },
  );

  test('exports a valid mxGraphModel and preserves imported raw styles', () {
    final result = DrawioXmlCodec.importDocument(source);
    final xml = DrawioXmlCodec.exportDocument(
      nodes: result.nodes,
      edges: result.edges,
    );

    expect(xml, contains('<mxGraphModel'));
    expect(xml, contains('id="start"'));
    expect(xml, contains('shape=ellipse'));
    expect(xml, contains('fillColor=#10B981'));
    expect(xml, contains('data-custom="retain"'));
    expect(xml, contains('source="start"'));
    expect(xml, contains('target="decision"'));
    expect(xml, contains('<mxPoint x="220.0" y="95.0"'));

    final restored = DrawioXmlCodec.importDocument(xml);
    final restoredStart = restored.nodes.firstWhere(
      (node) => node.id == 'start',
    );
    expect(restoredStart.x, 80);
    expect(restoredStart.y, 100);
    expect(restoredStart.parentId, 'lane');

    final editedEdge = result.edges.single.copyWith(
      strokeColor: const Color(0xFF7C3AED),
      endMarker: LineMarker.circle,
    );
    final editedXml = DrawioXmlCodec.exportDocument(
      nodes: result.nodes,
      edges: [editedEdge],
    );
    expect(editedXml, contains('strokeColor=#7C3AED'));
    expect(editedXml, contains('endArrow=oval'));
    expect(editedXml, isNot(contains('strokeColor=#F97316')));
  });

  test('exports edited style values instead of stale raw style fields', () {
    final imported = DrawioXmlCodec.importDocument(source);
    final start = imported.nodes.firstWhere((node) => node.id == 'start');
    final payload = start.payload as ShapePayload;
    final edited = start.copyWith(
      payload: payload.copyWith(fill: const Color(0xFF7C3AED)),
    );

    final xml = DrawioXmlCodec.exportDocument(
      nodes: [edited, ...imported.nodes.where((node) => node.id != start.id)],
      edges: imported.edges,
    );

    expect(xml, contains('fillColor=#7C3AED'));
    expect(xml, isNot(contains('fillColor=#10B981')));
  });

  test('round trips native groups and relative child geometry', () {
    final group = CanvasNode(
      id: 'group',
      type: NodeType.group,
      x: 100,
      y: 120,
      width: 320,
      height: 220,
      payload: GroupPayload(name: 'Checkout flow'),
    );
    final child = CanvasNode(
      id: 'group-child',
      type: NodeType.rectangle,
      x: 140,
      y: 170,
      width: 120,
      height: 60,
      parentId: group.id,
      payload: ShapePayload(label: 'Pay'),
    );

    final xml = DrawioXmlCodec.exportDocument(nodes: [group, child]);
    expect(xml, contains('id="group-child"'));
    expect(xml, contains('parent="group"'));

    final restored = DrawioXmlCodec.importDocument(xml);
    final restoredGroup = restored.nodes.firstWhere(
      (node) => node.id == 'group',
    );
    final restoredChild = restored.nodes.firstWhere(
      (node) => node.id == 'group-child',
    );
    expect(restoredGroup.type, NodeType.group);
    expect((restoredGroup.payload as GroupPayload).childNodeIds, [
      'group-child',
    ]);
    expect(restoredChild.parentId, 'group');
    expect(restoredChild.x, 140);
    expect(restoredChild.y, 170);
  });

  test('keeps unknown shapes editable and exportable with raw metadata', () {
    const customXml = '''<mxGraphModel><root>
      <mxCell id="0"/><mxCell id="1" parent="0"/>
      <mxCell id="custom" value="Custom" style="shape=mxgraph.custom.foo;foo=bar;" vertex="1" parent="1" data-source="custom">
        <mxGeometry x="10" y="20" width="80" height="40" as="geometry"/>
      </mxCell>
    </root></mxGraphModel>''';

    final imported = DrawioXmlCodec.importDocument(customXml);
    final node = imported.nodes.single;
    final payload = node.payload as ShapePayload;
    expect(node.type, NodeType.rectangle);
    expect(payload.diagramShapeId, 'mxgraph.custom.foo');
    expect(
      DiagramShapeCatalog.resolve(payload.diagramShapeId!).isFallback,
      isTrue,
    );

    final exported = DrawioXmlCodec.exportDocument(nodes: imported.nodes);
    expect(exported, contains('shape=mxgraph.custom.foo'));
    expect(exported, contains('data-source="custom"'));
  });

  test('round trips chart metadata without flattening the chart model', () {
    final chart = CanvasNode(
      id: 'chart-1',
      type: NodeType.chart,
      x: 40,
      y: 60,
      width: 360,
      height: 240,
      payload: ChartPayload(
        title: 'Revenue & margin',
        chartType: ChartType.radar,
        categories: const ['Q1', 'Q2', 'Q3'],
        series: [
          ChartSeries(
            name: 'Gross margin',
            values: const [0.31, 0.38, 0.42],
            color: const Color(0xFF38BDF8),
          ),
        ],
        showValues: true,
        doughnutHoleRatio: 0.72,
      ),
    );

    final xml = DrawioXmlCodec.exportDocument(nodes: [chart]);
    expect(xml, contains('data-varian-chart='));
    expect(xml, contains('shape=rectangle'));

    final restored = DrawioXmlCodec.importDocument(xml).nodes.single;
    expect(restored.type, NodeType.chart);
    final payload = restored.payload as ChartPayload;
    expect(payload.title, 'Revenue & margin');
    expect(payload.chartType, ChartType.radar);
    expect(payload.categories, ['Q1', 'Q2', 'Q3']);
    expect(payload.series.single.name, 'Gross margin');
    expect(payload.series.single.values, [0.31, 0.38, 0.42]);
    expect(payload.showValues, isTrue);
    expect(payload.doughnutHoleRatio, closeTo(0.72, 0.0001));
  });

  test('ignores oversized or malformed chart metadata safely', () {
    const malformed = '''<mxGraphModel><root>
      <mxCell id="0"/><mxCell id="1" parent="0"/>
      <mxCell id="chart" value="Fallback" style="shape=rectangle;" vertex="1" parent="1" data-varian-chart="not-base64">
        <mxGeometry x="10" y="20" width="80" height="40" as="geometry"/>
      </mxCell>
    </root></mxGraphModel>''';

    final restored = DrawioXmlCodec.importDocument(malformed).nodes.single;
    expect(restored.type, NodeType.rectangle);
    expect(restored.payload, isA<ShapePayload>());
  });

  test('materializes referenced Draw.io layers as editable groups', () {
    const layerXml = '''<mxGraphModel><root>
      <mxCell id="0"/>
      <mxCell id="1" parent="0"/>
      <mxCell id="layer-a" value="Layer A" parent="0"/>
      <mxCell id="layer-child" value="Child" style="shape=rectangle;" vertex="1" parent="layer-a">
        <mxGeometry x="24" y="30" width="100" height="50" as="geometry"/>
      </mxCell>
    </root></mxGraphModel>''';

    final result = DrawioXmlCodec.importDocument(layerXml);
    final layer = result.nodes.firstWhere((node) => node.id == 'layer-a');
    final child = result.nodes.firstWhere((node) => node.id == 'layer-child');

    expect(layer.type, NodeType.group);
    expect((layer.payload as GroupPayload).name, 'Layer A');
    expect((layer.payload as GroupPayload).childNodeIds, ['layer-child']);
    expect(child.parentId, 'layer-a');
  });

  test('rejects malformed or oversized input atomically', () {
    expect(
      () => DrawioXmlCodec.importDocument('<mxGraphModel><root>'),
      throwsA(isA<DrawioXmlException>()),
    );
    expect(
      () =>
          DrawioXmlCodec.importDocument('x' * (DrawioXmlCodec.maxXmlBytes + 1)),
      throwsA(isA<DrawioXmlException>()),
    );
  });
}
