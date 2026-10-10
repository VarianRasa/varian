import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  group('Advanced Line & Arrow tools', () {
    test('serializes directional ratios, markers, routing, and label', () {
      final payload = ShapePayload(
        startXRatio: 0.0,
        startYRatio: 1.0,
        endXRatio: 1.0,
        endYRatio: 0.0,
        startMarker: LineMarker.circle,
        endMarker: LineMarker.arrow,
        lineRouting: LineRouting.orthogonal,
        strokeStyle: StrokeStyle.dashed,
        label: 'Trigger Event',
        stroke: const Color(0xFFF97316),
        strokeWidth: 3.0,
      );

      final restored = ShapePayload.fromJson(payload.toJson());

      expect(restored.startXRatio, 0.0);
      expect(restored.startYRatio, 1.0);
      expect(restored.endXRatio, 1.0);
      expect(restored.endYRatio, 0.0);
      expect(restored.startMarker, LineMarker.circle);
      expect(restored.endMarker, LineMarker.arrow);
      expect(restored.lineRouting, LineRouting.orthogonal);
      expect(restored.strokeStyle, StrokeStyle.dashed);
      expect(restored.label, 'Trigger Event');
      expect(restored.strokeWidth, 3.0);
    });

    test('exports directional straight line accurately to SVG', () {
      final document = CanvasDocument(
        projectId: 'line-test',
        updatedAt: DateTime(2026),
        nodes: [
          CanvasNode(
            id: 'line-1',
            type: NodeType.line,
            x: 100,
            y: 100,
            width: 200,
            height: 100,
            payload: ShapePayload(
              startXRatio: 0.0,
              startYRatio: 1.0, // (100, 200)
              endXRatio: 1.0,
              endYRatio: 0.0, // (300, 100)
              strokeStyle: StrokeStyle.dotted,
              label: 'Upward Link',
            ),
          ),
        ],
      );

      final svg = ExportService.exportVectorSvg(document);

      expect(
        svg,
        contains('<line x1="100.0" y1="200.0" x2="300.0" y2="100.0"'),
      );
      expect(svg, contains('stroke-dasharray="2,3"'));
      expect(svg, contains('Upward Link'));
    });

    test('exports orthogonal routed arrow to SVG with path and markers', () {
      final document = CanvasDocument(
        projectId: 'arrow-ortho-test',
        updatedAt: DateTime(2026),
        nodes: [
          CanvasNode(
            id: 'arrow-1',
            type: NodeType.arrow,
            x: 50,
            y: 50,
            width: 100,
            height: 60,
            payload: ShapePayload(
              startXRatio: 0.0,
              startYRatio: 0.0,
              endXRatio: 1.0,
              endYRatio: 1.0,
              lineRouting: LineRouting.orthogonal,
              endMarker: LineMarker.arrow,
            ),
          ),
        ],
      );

      final svg = ExportService.exportVectorSvg(document);

      expect(
        svg,
        contains(
          '<path d="M 50.0 50.0 L 100.0 50.0 L 100.0 110.0 L 150.0 110.0"',
        ),
      );
      expect(svg, contains('marker-end="url(#arrow)"'));
    });

    test('exports curved line with custom curveDepth to SVG path', () {
      final document = CanvasDocument(
        projectId: 'curved-line-test',
        updatedAt: DateTime(2026),
        nodes: [
          CanvasNode(
            id: 'line-curved-1',
            type: NodeType.line,
            x: 0,
            y: 0,
            width: 100,
            height: 0,
            payload: ShapePayload(
              startXRatio: 0.0,
              startYRatio: 0.0,
              endXRatio: 1.0,
              endYRatio: 0.0,
              lineRouting: LineRouting.curved,
              curveDepth: 0.5,
            ),
          ),
        ],
      );

      final svg = ExportService.exportVectorSvg(document);

      // midX = 50, midY = 0, dx = 100, dy = 0, depth = 0.5 -> cx = 50 - 0 = 50, cy = 0 + 100 * 0.5 = 50
      expect(svg, contains('<path d="M 0.0 0.0 Q 50.0 50.0 100.0 0.0"'));
    });
  });
}
