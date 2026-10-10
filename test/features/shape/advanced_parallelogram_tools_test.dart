import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  group('Advanced parallelogram (Data / IO) tools', () {
    test(
      'serializes skewRatio, ioType, subText, fillet, gradients, and label',
      () {
        final payload = ShapePayload(
          skewRatio: 0.35,
          ioType: 'input',
          subText: 'JSON_PAYLOAD',
          cornerRadius: 8.0,
          fillType: FillType.linearGradient,
          fillGradientEnd: const Color(0xFF10B981),
          fillOpacity: 0.85,
          strokeStyle: StrokeStyle.dashed,
          hasShadow: true,
          label: 'Receive Order',
        );

        final restored = ShapePayload.fromJson(payload.toJson());

        expect(restored.skewRatio, 0.35);
        expect(restored.ioType, 'input');
        expect(restored.subText, 'JSON_PAYLOAD');
        expect(restored.cornerRadius, 8.0);
        expect(restored.fillType, FillType.linearGradient);
        expect(restored.fillGradientEnd, const Color(0xFF10B981));
        expect(restored.fillOpacity, 0.85);
        expect(restored.strokeStyle, StrokeStyle.dashed);
        expect(restored.hasShadow, isTrue);
        expect(restored.label, 'Receive Order');
      },
    );

    test(
      'exports parallelogram as SVG polygon with skew, label, and dash attributes',
      () {
        final document = CanvasDocument(
          projectId: 'parallelogram-test',
          updatedAt: DateTime(2026),
          nodes: [
            CanvasNode(
              id: 'io-1',
              type: NodeType.parallelogram,
              x: 100,
              y: 50,
              width: 200,
              height: 100,
              payload: ShapePayload(
                skewRatio: 0.2, // skew = 40.0
                fillOpacity: 0.9,
                strokeStyle: StrokeStyle.dashed,
                label: 'Input Data',
              ),
            ),
          ],
        );

        final svg = ExportService.exportVectorSvg(document);

        // p1=(140,50), p2=(300,50), p3=(260,150), p4=(100,150)
        expect(
          svg,
          contains(
            '<polygon points="140.0,50.0 300.0,50.0 260.0,150.0 100.0,150.0"',
          ),
        );
        expect(svg, contains('stroke-dasharray="6,4"'));
        expect(svg, contains('fill-opacity="0.9"'));
        expect(svg, contains('Input Data'));
      },
    );
  });
}
