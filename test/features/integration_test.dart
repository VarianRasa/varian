import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';
import 'package:varian/features/templates/data/diagram_templates.dart';

void main() {
  group('Full Stack Integration Tests', () {
    test('DiagramTemplates createFlowchart creates valid nodes and edges', () {
      final (nodes, edges) = DiagramTemplates.createFlowchart();
      expect(nodes.length, 4);
      expect(edges.length, 3);
      expect(nodes.any((n) => n.type == NodeType.diamond), isTrue);
      expect(nodes.any((n) => n.type == NodeType.ellipse), isTrue);
    });

    test(
      'ExportService exportNativeJson returns valid JSON string with indent',
      () {
        final node = CanvasNode(
          id: 'n1',
          type: NodeType.rectangle,
          x: 10,
          y: 20,
          width: 100,
          height: 80,
          payload: ShapePayload(fill: const Color(0xFF10B981)),
        );

        final doc = CanvasDocument(
          projectId: 'proj_test',
          nodes: [node],
          updatedAt: DateTime.now(),
        );

        final jsonOutput = ExportService.exportNativeJson(doc);
        expect(jsonOutput, contains('"projectId": "proj_test"'));
        expect(jsonOutput, contains('"type": "rectangle"'));
      },
    );
  });
}
