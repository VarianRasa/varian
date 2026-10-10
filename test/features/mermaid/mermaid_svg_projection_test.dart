import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/features/mermaid/domain/mermaid_svg_native_converter.dart';

final _source = CanvasNode(
  id: 's',
  type: NodeType.mermaid,
  x: 0,
  y: 0,
  width: 100,
  height: 100,
  payload: MermaidPayload(source: 'flowchart TD\nA-->B'),
);

void main() {
  test('expands local symbol instances at their own viewport and style', () {
    final result = MermaidSvgNativeConverter.convert(_source, '''
      <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
        <defs><symbol id="icon" viewBox="0 0 10 10"><path d="M0 0L10 0L10 10Z"/></symbol></defs>
        <use href="#icon" x="20" y="30" width="40" height="40" fill="#ff0000"/>
        <use href="#icon" x="70" y="10" width="10" height="10" fill="#0000ff"/>
      </svg>''');
    expect(result.isSuccess, isTrue, reason: result.diagnostic?.code);
    expect(result.nodes, hasLength(2));
    expect(result.nodes.first.bounds, const Rect.fromLTWH(20, 30, 40, 40));
    expect(
      (result.nodes.first.payload as VectorPathPayload).fill,
      const Color(0xFFFF0000),
    );
    expect(
      (result.nodes.last.payload as VectorPathPayload).fill,
      const Color(0xFF0000FF),
    );
  });

  test('rejects recursive local references atomically', () {
    final result = MermaidSvgNativeConverter.convert(
      _source,
      '''
      <svg viewBox="0 0 100 100"><rect width="10" height="10"/>
      <defs><g id="loop"><use href="#loop"/></g></defs><use href="#loop"/></svg>''',
    );
    expect(result.isSuccess, isFalse);
    expect(result.nodes, isEmpty);
    expect(result.edges, isEmpty);
  });

  test('preserves SVG default paint and applies ancestor opacity once', () {
    final result = MermaidSvgNativeConverter.convert(_source, '''
      <svg viewBox="0 0 100 100"><g opacity="0.5"><g>
      <path d="M10 10L30 10L20 30Z"/><rect x="40" y="10" width="20" height="20"/>
      </g></g></svg>''');
    expect(result.isSuccess, isTrue);
    for (final node in result.nodes) {
      expect(node.opacity, 0.5);
    }
    final path =
        result.nodes.singleWhere((n) => n.payload is VectorPathPayload).payload
            as VectorPathPayload;
    expect(path.fill, Colors.black);
    expect(path.stroke.a, 0);
    final box =
        result.nodes.singleWhere((n) => n.payload is ShapePayload).payload
            as ShapePayload;
    expect(box.fill, Colors.black);
  });

  test('preserves DOM paint order across native primitive types', () {
    final result = MermaidSvgNativeConverter.convert(
      _source,
      '''
      <svg viewBox="0 0 100 100"><path d="M0 0L50 0L50 50Z" fill="red"/>
      <text x="10" y="20">behind</text><rect width="60" height="60" fill="blue"/></svg>''',
    );
    expect(result.isSuccess, isTrue);
    final nodes = [...result.nodes]
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    expect(nodes.map((n) => n.type), [
      NodeType.vectorPath,
      NodeType.text,
      NodeType.rectangle,
    ]);
  });

  test('repeated actor aliases attach to the nearest matching instance', () {
    final result = MermaidSvgNativeConverter.convert(_source, '''
      <svg viewBox="0 0 100 100">
      <rect data-id="A" x="0" y="0" width="10" height="10"/>
      <rect data-id="B" x="90" y="0" width="10" height="10"/>
      <rect data-id="A" x="0" y="90" width="10" height="10"/>
      <rect data-id="B" x="90" y="90" width="10" height="10"/>
      <line x1="10" y1="95" x2="90" y2="95" data-source="A" data-target="B" stroke="black"/>
      </svg>''');
    expect(result.isSuccess, isTrue);
    final edge = result.edges.single;
    expect(result.nodes.singleWhere((n) => n.id == edge.sourceNodeId).y, 90);
    expect(result.nodes.singleWhere((n) => n.id == edge.targetNodeId).y, 90);
  });

  test('retains positioned tspan labels without duplicated parent text', () {
    final result = MermaidSvgNativeConverter.convert(_source, '''
      <svg viewBox="0 0 100 100"><text x="10" y="20" font-size="10">
      <tspan x="12" dy="2" fill="red">first</tspan><tspan x="30" dy="15" fill="blue">second</tspan>
      </text></svg>''');
    expect(result.isSuccess, isTrue);
    final texts = result.nodes.where((n) => n.type == NodeType.text).toList();
    expect(texts.map((n) => (n.payload as TextPayload).text), [
      'first',
      'second',
    ]);
    expect(texts.first.x, 12);
    expect(texts.last.x, 30);
    expect(texts.last.y - texts.first.y, closeTo(15, 0.01));
    expect((texts.first.payload as TextPayload).color, const Color(0xFFFF0000));
    expect((texts.last.payload as TextPayload).color, const Color(0xFF0000FF));
  });

  test('preserves custom marker geometry on a curved route', () {
    final result = MermaidSvgNativeConverter.convert(_source, '''
      <svg viewBox="0 0 100 100"><defs>
      <marker id="tip" markerUnits="userSpaceOnUse" markerWidth="10" markerHeight="10" refX="10" refY="5" orient="auto">
      <path d="M0 0L10 5L0 10Z" fill="red"/></marker></defs>
      <path d="M10 50C30 50 70 50 90 50" fill="none" stroke="black" marker-end="url(#tip)"/>
      </svg>''');
    expect(result.isSuccess, isTrue);
    expect(result.nodes, hasLength(2));
    final tip = result.nodes.last;
    expect(tip.bounds, const Rect.fromLTWH(80, 45, 10, 10));
    expect((tip.payload as VectorPathPayload).fill, const Color(0xFFFF0000));
  });
}
