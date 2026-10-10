import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  group('Advanced ellipse tools', () {
    test(
      'serializes arc, donut, gradient, stroke, shadow, and label properties',
      () {
        final payload = ShapePayload(
          startAngle: 45,
          sweepAngle: 270,
          innerRadiusRatio: 0.6,
          fillType: FillType.angularGradient,
          fillGradientEnd: const Color(0xFF9333EA),
          fillOpacity: 0.8,
          strokeStyle: StrokeStyle.dashed,
          hasShadow: true,
          label: '75%',
        );

        final restored = ShapePayload.fromJson(payload.toJson());

        expect(restored.startAngle, 45);
        expect(restored.sweepAngle, 270);
        expect(restored.innerRadiusRatio, 0.6);
        expect(restored.fillType, FillType.angularGradient);
        expect(restored.fillGradientEnd, const Color(0xFF9333EA));
        expect(restored.fillOpacity, 0.8);
        expect(restored.strokeStyle, StrokeStyle.dashed);
        expect(restored.hasShadow, isTrue);
        expect(restored.label, '75%');
      },
    );

    test('exports partial donut ellipse as an SVG path', () {
      final document = CanvasDocument(
        projectId: 'ellipse-test',
        updatedAt: DateTime(2026),
        nodes: [
          CanvasNode(
            id: 'ellipse-1',
            type: NodeType.ellipse,
            x: 10,
            y: 20,
            width: 200,
            height: 100,
            payload: ShapePayload(
              startAngle: 0,
              sweepAngle: 270,
              innerRadiusRatio: 0.5,
              strokeStyle: StrokeStyle.dotted,
            ),
          ),
        ],
      );

      final svg = ExportService.exportVectorSvg(document);

      expect(svg, contains('<path d='));
      expect(svg, contains('stroke-dasharray="2 3"'));
      expect(svg, contains('A 100.0 50.0'));
    });
  });
}
