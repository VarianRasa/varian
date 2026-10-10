import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';
import 'package:varian/features/history/snapshot_manager.dart';
import 'package:varian/features/import/import_service.dart';

void main() {
  group(
    'Extended PRD Features: Drawio, PlantUML, MultiPage PDF & Snapshots',
    () {
      test(
        'ImportService parses Draw.io XML mxGraphModel with vertices and edges',
        () {
          const xml = '''<mxGraphModel>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <mxCell id="v1" value="Start Flow" style="ellipse;whiteSpace=wrap;" vertex="1" parent="1">
      <mxGeometry x="100" y="100" width="120" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="v2" value="Evaluate" style="rhombus;whiteSpace=wrap;" vertex="1" parent="1">
      <mxGeometry x="280" y="90" width="140" height="80" as="geometry"/>
    </mxCell>
    <mxCell id="e1" value="Next" edge="1" parent="1" source="v1" target="v2"/>
  </root>
</mxGraphModel>''';

          final res = ImportService.importFromDrawioXml(xml);
          expect(res.isSuccess, isTrue);
          expect(res.nodes.length, equals(2));
          expect(res.nodes[0].type, equals(NodeType.ellipse));
          expect(res.nodes[1].type, equals(NodeType.diamond));
          expect(res.edges.length, equals(1));
          expect(res.edges[0].sourceNodeId, equals('v1'));
          expect(res.edges[0].targetNodeId, equals('v2'));
        },
      );

      test('ImportService rejects Draw.io edges with dangling endpoints', () {
        const xml = '''<mxGraphModel>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <mxCell id="v1" value="Start" vertex="1" parent="1">
      <mxGeometry x="100" y="100" width="120" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="dangling" edge="1" parent="1" source="v1" target="missing"/>
  </root>
</mxGraphModel>''';

        final result = ImportService.importFromDrawioXml(xml);

        expect(result.isSuccess, isFalse);
        expect(result.nodes, isEmpty);
        expect(result.edges, isEmpty);
        expect(result.error, contains('unknown target node'));
      });

      test('ImportService parses PlantUML diagram syntax', () {
        const puml = '''@startuml
auth -> dashboard : Logged In
dashboard -> settings : Configure
@enduml''';

        final res = ImportService.importFromPlantUml(puml);
        expect(res.isSuccess, isTrue);
        expect(res.nodes.isNotEmpty, isTrue);
        expect(res.edges.length, equals(2));
      });

      test(
        'ExportService generates multi-page PDF bytes from CanvasDocument',
        () {
          final doc = CanvasDocument(
            projectId: 'proj_pdf',
            updatedAt: DateTime.now(),
            nodes: [
              CanvasNode(
                id: 'frame1',
                type: NodeType.frame,
                x: 50,
                y: 50,
                width: 400,
                height: 300,
                payload: FramePayload(name: 'Slide 1: Intro'),
              ),
              CanvasNode(
                id: 'frame2',
                type: NodeType.frame,
                x: 500,
                y: 50,
                width: 400,
                height: 300,
                payload: FramePayload(name: 'Slide 2: Architecture'),
              ),
              CanvasNode(
                id: 'text1',
                type: NodeType.text,
                x: 70,
                y: 90,
                width: 100,
                height: 30,
                payload: TextPayload(text: 'Welcome to Studio'),
              ),
            ],
            edges: [],
          );

          final pdfBytes = ExportService.exportMultiPagePdf(doc);
          expect(pdfBytes.isNotEmpty, isTrue);
          final pdfString = utf8.decode(pdfBytes, allowMalformed: true);
          expect(pdfString.startsWith('%PDF-1.4'), isTrue);
          expect(pdfString.contains('%%EOF'), isTrue);
          expect(pdfString.contains('/Count 2'), isTrue); // 2 frame pages
        },
      );

      test('VectorGeometryHelper & DocumentSnapshotRecord serialization', () {
        final doc = CanvasDocument(
          projectId: 'proj_snap',
          updatedAt: DateTime.now(),
          nodes: [
            CanvasNode(
              id: 'rect1',
              type: NodeType.rectangle,
              x: 10,
              y: 10,
              width: 100,
              height: 100,
              payload: ShapePayload(),
            ),
          ],
          edges: [],
        );

        final snapshot = DocumentSnapshotRecord(
          id: 'snap_1',
          description: 'Auto-saved before export',
          timestamp: DateTime.now(),
          document: doc,
        );

        final json = snapshot.toJson();
        final restored = DocumentSnapshotRecord.fromJson(json);
        expect(restored.id, equals('snap_1'));
        expect(restored.document.nodes.length, equals(1));
      });
    },
  );
}
