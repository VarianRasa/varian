import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/mermaid/domain/mermaid_renderer.dart';
import 'package:varian/features/mermaid/domain/mermaid_svg_native_converter.dart';

CanvasNode _sourceNode(String source) => CanvasNode(
  id: 'mermaid-source',
  type: NodeType.mermaid,
  x: 0,
  y: 0,
  width: 480,
  height: 395.1,
  payload: MermaidPayload(source: source),
);

class _CachedSvgRenderer implements MermaidRenderer {
  @override
  String get rendererVersion => 'parity-test-renderer';

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async => MermaidValidationResult.valid(
    diagramType: detectMermaidDiagramType(source),
  );

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async => const MermaidRenderResult.failure(
    MermaidDiagnostic(
      code: 'UNEXPECTED_RENDER',
      message: 'This test must use the supplied cached SVG.',
    ),
  );
}

String _fixture(String name) =>
    File('test/features/mermaid/fixtures/$name').readAsStringSync();

List<String> _visibleText(CanvasNode node) => [
  for (final item
      in node.payload is TextPayload
          ? [(node.payload as TextPayload).text]
          : <String>[])
    item,
  if (node.payload is ShapePayload &&
      (node.payload as ShapePayload).label.trim().isNotEmpty)
    (node.payload as ShapePayload).label,
];

void main() {
  test('flowchart conversion projects cached rendered geometry', () async {
    final result = await MermaidNativeConverter(renderer: _CachedSvgRenderer())
        .convert(
          _sourceNode('flowchart TD\n  A[Start] --> B[End]'),
          cachedSvg: _fixture('probe_flowchart.svg'),
        );

    expect(result.isSuccess, isTrue);
    expect(result.renderedSvg, isNotNull);

    final rectangles = result.nodes
        .where((node) => node.type == NodeType.rectangle)
        .toList();
    expect(rectangles, hasLength(2));
    expect(rectangles.first.width, closeTo(215.7, 0.2));
    expect(
      (rectangles.first.payload as ShapePayload).fill,
      const Color(0xFFECECFF),
    );

    final labels = result.nodes.expand(_visibleText).toList();
    expect(labels.where((label) => label == 'Start'), hasLength(1));
    expect(labels.where((label) => label == 'End'), hasLength(1));
  });

  test('sequence conversion preserves actor text color and SVG endpoints', () {
    final source = _sourceNode('sequenceDiagram\n  Alice->>Bob: Hello');
    final result = MermaidSvgNativeConverter.convert(
      source,
      _fixture('probe_sequence.svg'),
    );

    expect(result.isSuccess, isTrue);

    final aliceLabels = result.nodes.where((node) {
      return node.type == NodeType.text &&
          (node.payload as TextPayload).text == 'Alice';
    });
    final bobLabels = result.nodes.where((node) {
      return node.type == NodeType.text &&
          (node.payload as TextPayload).text == 'Bob';
    });
    expect(aliceLabels, hasLength(2));
    expect(bobLabels, hasLength(2));
    expect(
      [
        ...aliceLabels,
        ...bobLabels,
      ].map((node) => (node.payload as TextPayload).color),
      everyElement(Colors.black),
    );

    final helloLabels = result.nodes.where((node) {
      return node.type == NodeType.text &&
          (node.payload as TextPayload).text == 'Hello';
    });
    expect(helloLabels, hasLength(1));

    expect(result.edges, hasLength(1));
    expect(result.edges.single.sourcePoint, isNotNull);
    expect(result.edges.single.targetPoint, isNotNull);
    expect(result.edges.single.sourcePoint!.dx, closeTo(134.4, 0.1));
    expect(result.edges.single.targetPoint!.dx, closeTo(342.4, 0.1));
  });
}
