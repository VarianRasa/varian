import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/inspect/domain/inspect_handoff.dart';

void main() {
  final document = CanvasDocument(
    projectId: 'project-a',
    canvasId: 'canvas-a',
    schemaVersion: 7,
    updatedAt: DateTime.utc(2026, 9, 13),
    nodes: [
      CanvasNode(
        id: 'frame',
        type: NodeType.frame,
        x: 10,
        y: 20,
        width: 400,
        height: 300,
        payload: FramePayload(
          name: 'Hero',
          paddingLeft: 24,
          paddingTop: 16,
          paddingRight: 24,
          paddingBottom: 16,
          itemSpacing: 12,
        ),
      ),
      CanvasNode(
        id: 'title',
        type: NodeType.text,
        x: 34,
        y: 36,
        width: 220,
        height: 48,
        parentId: 'frame',
        payload: TextPayload(
          text: 'Build faster',
          fontFamily: 'Inter',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFF8FAFC),
        ),
      ),
      CanvasNode(
        id: 'badge',
        type: NodeType.rectangle,
        x: 34,
        y: 96,
        width: 100,
        height: 32,
        parentId: 'frame',
        payload: ShapePayload(
          fill: const Color(0xFF2563EB),
          stroke: const Color(0xFF60A5FA),
          cornerRadius: 8,
        ),
      ),
    ],
  );

  test('collects geometry, spacing, typography, and provenance', () {
    final bundle = InspectHandoffService.inspect(
      document,
      nodeIds: const ['title'],
    );

    expect(bundle.documentSchemaVersion, 7);
    expect(bundle.sourceNodeIds, ['title']);
    expect(bundle.nodes.single.bounds, const Rect.fromLTWH(34, 36, 220, 48));
    expect(bundle.nodes.single.spacing['parent'], {
      'bottom': 236.0,
      'id': 'frame',
      'left': 24.0,
      'right': 156.0,
      'top': 16.0,
    });
    expect(bundle.nodes.single.typography['fontFamily'], 'Inter');
    expect(bundle.nodes.single.typography['fontSize'], 32.0);
    expect(bundle.nodes.single.styles['color'], '#F8FAFC');
  });

  test('exports deterministic CSS and Flutter handoff', () {
    final css = InspectHandoffService.export(
      document,
      nodeIds: const ['title'],
      format: InspectHandoffFormat.css,
    );
    final flutter = InspectHandoffService.export(
      document,
      nodeIds: const ['title'],
      format: InspectHandoffFormat.flutter,
    );

    expect(css, contains('documentSchemaVersion: 7'));
    expect(css, contains('left: 0px'));
    expect(css, contains('font-family: Inter'));
    expect(css, contains('color: #F8FAFC'));
    expect(flutter, contains('Stack('));
    expect(flutter, contains('Text("Build faster"'));
    expect(flutter, contains('fontSize: 32'));
  });

  test('JSON handoff preserves schema and raw node data', () {
    final jsonText = InspectHandoffService.export(
      document,
      nodeIds: const ['title'],
      format: InspectHandoffFormat.json,
    );
    final json = jsonDecode(jsonText) as Map<String, dynamic>;

    expect(json['schemaVersion'], 1);
    expect(json['documentSchemaVersion'], 7);
    expect(json['sourceNodeIds'], ['title']);
    expect((json['nodes'] as List).single['node']['id'], 'title');
  });

  test('SVG handoff excludes unrelated nodes and edges', () {
    final svg = InspectHandoffService.export(
      document,
      nodeIds: const ['title'],
      format: InspectHandoffFormat.svg,
    );

    expect(svg, contains('<svg'));
    expect(svg, contains('Build faster'));
    expect(svg, isNot(contains('#2563EB')));
  });
}
