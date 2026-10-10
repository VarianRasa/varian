import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  group('ShapePayload Advanced Rectangle Tools Tests', () {
    test(
      'Serializes and deserializes independent corners, strokeStyle, and shadow correctly',
      () {
        final payload = ShapePayload(
          fill: const Color(0xFF2563EB),
          stroke: const Color(0xFF60A5FA),
          strokeWidth: 3.5,
          cornerRadius: 8.0,
          independentCorners: true,
          topLeftRadius: 16.0,
          topRightRadius: 8.0,
          bottomRightRadius: 24.0,
          bottomLeftRadius: 4.0,
          strokeStyle: StrokeStyle.dashed,
          hasShadow: true,
          shadowColor: const Color(0x88000000),
          shadowBlur: 12.0,
          shadowOffsetX: 2.0,
          shadowOffsetY: 6.0,
        );

        final json = payload.toJson();
        final restored = ShapePayload.fromJson(json);

        expect(restored.fill, const Color(0xFF2563EB));
        expect(restored.stroke, const Color(0xFF60A5FA));
        expect(restored.strokeWidth, 3.5);
        expect(restored.cornerRadius, 8.0);
        expect(restored.independentCorners, true);
        expect(restored.topLeftRadius, 16.0);
        expect(restored.topRightRadius, 8.0);
        expect(restored.bottomRightRadius, 24.0);
        expect(restored.bottomLeftRadius, 4.0);
        expect(restored.strokeStyle, StrokeStyle.dashed);
        expect(restored.hasShadow, true);
        expect(restored.shadowColor, const Color(0x88000000));
        expect(restored.shadowBlur, 12.0);
        expect(restored.shadowOffsetX, 2.0);
        expect(restored.shadowOffsetY, 6.0);
      },
    );

    test('clone and copyWith maintain all corner and effect properties', () {
      final payload = ShapePayload(
        cornerRadius: 10.0,
        independentCorners: true,
        topLeftRadius: 12.0,
        topRightRadius: 14.0,
        bottomRightRadius: 16.0,
        bottomLeftRadius: 18.0,
        strokeStyle: StrokeStyle.dotted,
        hasShadow: true,
      );

      final cloned = payload.clone();
      expect(cloned.topLeftRadius, 12.0);
      expect(cloned.strokeStyle, StrokeStyle.dotted);
      expect(cloned.hasShadow, true);

      final updated = payload.copyWith(
        strokeStyle: StrokeStyle.solid,
        topLeftRadius: 20.0,
      );
      expect(updated.strokeStyle, StrokeStyle.solid);
      expect(updated.topLeftRadius, 20.0);
      expect(updated.topRightRadius, 14.0);
    });

    test(
      'Serializes and deserializes gradient fills, opacity, and embedded label correctly',
      () {
        final payload = ShapePayload(
          fill: const Color(0xFF2563EB),
          fillGradientEnd: const Color(0xFF9333EA),
          fillType: FillType.linearGradient,
          fillOpacity: 0.85,
          label: 'Process Step 1',
          labelColor: const Color(0xFFFFFFFF),
          labelFontSize: 16.0,
        );

        final json = payload.toJson();
        final restored = ShapePayload.fromJson(json);

        expect(restored.fillType, FillType.linearGradient);
        expect(restored.fillGradientEnd, const Color(0xFF9333EA));
        expect(restored.fillOpacity, 0.85);
        expect(restored.label, 'Process Step 1');
        expect(restored.labelColor, const Color(0xFFFFFFFF));
        expect(restored.labelFontSize, 16.0);
      },
    );
    test(
      'ExportService generates SVG with stroke-dasharray for dashed rectangle',
      () {
        final doc = CanvasDocument(
          projectId: 'test_doc',
          updatedAt: DateTime.now(),
          nodes: [
            CanvasNode(
              id: 'rect_1',
              type: NodeType.rectangle,
              x: 100,
              y: 150,
              width: 200,
              height: 100,
              payload: ShapePayload(
                fill: const Color(0xFF2563EB),
                stroke: const Color(0xFF60A5FA),
                strokeWidth: 2.0,
                cornerRadius: 12.0,
                strokeStyle: StrokeStyle.dashed,
              ),
            ),
          ],
        );

        final svg = ExportService.exportVectorSvg(doc);
        expect(svg.contains('stroke-dasharray="6 4"'), isTrue);
        expect(svg.contains('rx="12.0"'), isTrue);
      },
    );
  });
}
