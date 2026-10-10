import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/features/export/export_presets.dart';
import 'package:varian/features/export/export_service.dart';
import 'package:varian/features/import/import_service.dart';

void main() {
  group('Format Importer & SVG Exporter Tests', () {
    test(
      'ImportService preserves Mermaid source as one editable canvas node',
      () {
        const sampleMermaid = '''
graph TD
A[Start Login] --> B{Is Authenticated}
B -->|Yes| C(Enter Dashboard)
B -->|No| D[Show Error]
''';

        final result = ImportService.importFromMermaid(sampleMermaid);
        expect(result.isSuccess, isTrue);
        expect(result.nodes.length, 1);
        expect(result.edges, isEmpty);
        expect(result.nodes.single.type, NodeType.mermaid);
        expect(
          (result.nodes.single.payload as MermaidPayload).source,
          sampleMermaid.trim(),
        );
      },
    );

    test('ExportService exports canonical Mermaid sources only', () {
      const firstSource = 'flowchart TD\n  A[Start] --> B[End]';
      const secondSource = 'graph LR\n  C[Left] --> D[Right]';
      final first = CanvasNode(
        id: 'mermaid_1',
        type: NodeType.mermaid,
        x: 0,
        y: 0,
        width: 240,
        height: 160,
        zIndex: 1,
        payload: MermaidPayload(source: firstSource),
      );
      final second = CanvasNode(
        id: 'mermaid_2',
        type: NodeType.mermaid,
        x: 0,
        y: 200,
        width: 240,
        height: 160,
        zIndex: 2,
        visible: false,
        payload: MermaidPayload(
          source: secondSource,
          renderMode: MermaidRenderMode.native,
          conversionStatus: MermaidConversionStatus.converted,
          nativeNodeIds: const ['native_1'],
        ),
      );
      final generated = CanvasNode(
        id: 'native_1',
        type: NodeType.rectangle,
        x: 0,
        y: 200,
        width: 120,
        height: 60,
        payload: ShapePayload(fill: const Color(0xFF2563EB)),
      );

      final exported = ExportService.exportMermaid(
        CanvasDocument(
          projectId: 'test_p',
          nodes: [generated, second, first],
          updatedAt: DateTime.now(),
        ),
      );

      expect(exported, startsWith('%% Canvas Mermaid source bundle'));
      expect(exported, contains(firstSource));
      expect(exported, contains(secondSource));
      expect(
        exported.indexOf(firstSource),
        lessThan(exported.indexOf(secondSource)),
      );
      expect(exported, isNot(contains('native_1')));
    });

    test('Mermaid export preset returns UTF-8 source data', () async {
      const source = 'flowchart LR\n  A[One] --> B[Two]';
      final document = CanvasDocument(
        projectId: 'test_p',
        nodes: [
          CanvasNode(
            id: 'mermaid_1',
            type: NodeType.mermaid,
            x: 0,
            y: 0,
            width: 240,
            height: 160,
            payload: MermaidPayload(source: source),
          ),
        ],
        updatedAt: DateTime.now(),
      );

      final result = await ExportPresetRegistry.mermaid.export(document);

      expect(result, isNotNull);
      expect(result!.text, contains(source));
      expect(result.data, utf8.encode(result.text!));
      expect(
        ExportPresetRegistry.lookup('MERMAID'),
        same(ExportPresetRegistry.mermaid),
      );
    });

    test('native JSON export omits transient file delivery sources', () {
      final document = CanvasDocument(
        projectId: 'runtime-file-export',
        nodes: [
          CanvasNode(
            id: 'brief-file',
            type: NodeType.fileCard,
            x: 0,
            y: 0,
            width: 240,
            height: 160,
            payload: FilePayload(
              fileName: 'brief.pdf',
              fileExtension: 'PDF',
              localPath: r'C:\\runtime\\brief.pdf',
              base64Data: 'c2Vuc2l0aXZl',
              remoteUrl: 'https://cdn.example/brief.pdf',
            ),
          ),
        ],
        updatedAt: DateTime.utc(2026, 9, 26),
      );

      final exported =
          jsonDecode(ExportService.exportNativeJson(document))
              as Map<String, dynamic>;
      final payload =
          ((exported['nodes'] as List).single
                  as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;

      expect(payload['fileName'], 'brief.pdf');
      expect(payload.containsKey('localPath'), isFalse);
      expect(payload.containsKey('base64Data'), isFalse);
      expect(payload.containsKey('remoteUrl'), isFalse);
    });

    test('Draw.io export preset returns native XML', () async {
      final document = CanvasDocument(
        projectId: 'drawio-export-test',
        nodes: [
          CanvasNode(
            id: 'hexagon',
            type: NodeType.rectangle,
            x: 10,
            y: 20,
            width: 120,
            height: 80,
            payload: ShapePayload(diagramShapeId: 'hexagon', label: 'Service'),
          ),
        ],
        updatedAt: DateTime.now(),
      );

      final result = await ExportPresetRegistry.drawio.export(document);

      expect(result, isNotNull);
      expect(result!.text, contains('<mxGraphModel'));
      expect(result.text, contains('shape=hexagon'));
      expect(result.data, utf8.encode(result.text!));
      expect(
        ExportPresetRegistry.lookup('DRAWIO'),
        same(ExportPresetRegistry.drawio),
      );
    });

    test(
      'ExportService exportVectorSvg generates well-formed SVG XML string',
      () {
        final rect = CanvasNode(
          id: 'rect_1',
          type: NodeType.rectangle,
          x: 10,
          y: 20,
          width: 120,
          height: 80,
          payload: ShapePayload(fill: const Color(0xFF2563EB)),
        );

        final vectorPath = CanvasNode(
          id: 'vec_1',
          type: NodeType.vectorPath,
          x: 200,
          y: 100,
          width: 100,
          height: 100,
          payload: VectorPathPayload(
            points: const [
              BezierPoint(point: Offset(0, 0)),
              BezierPoint(point: Offset(50, 50)),
              BezierPoint(point: Offset(100, 0)),
            ],
            isClosed: true,
          ),
        );

        final model = CanvasNode(
          id: 'model_1',
          type: NodeType.model3d,
          x: 350,
          y: 240,
          width: 120,
          height: 80,
          payload: Model3DPayload(fileName: 'chair.glb', fileSizeText: '4 KB'),
        );

        const edge = CanvasEdge(
          id: 'e1',
          sourceNodeId: 'rect_1',
          targetNodeId: 'vec_1',
          label: 'Flow Link',
        );

        final doc = CanvasDocument(
          projectId: 'test_p',
          nodes: [rect, vectorPath, model],
          edges: [edge],
          updatedAt: DateTime.now(),
        );

        final svgXml = ExportService.exportVectorSvg(doc);
        expect(svgXml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
        expect(svgXml, contains('<svg xmlns="http://www.w3.org/2000/svg"'));
        expect(svgXml, contains('<rect x="10.0" y="20.0"'));
        expect(svgXml, contains('<path d="M 200.0 100.0'));
        expect(
          svgXml,
          contains(
            '<path d="M 410.0 268.0 l 28 16 v 32 l -28 16 l -28 -16 v -32 z"',
          ),
        );
        expect(svgXml, contains('Flow Link'));
        expect(svgXml, contains('</svg>'));
      },
    );
  });
}
