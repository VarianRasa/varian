import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  group('Advanced diamond tools', () {
    test('serializes diamond label, branch labels, fillet, and gradients', () {
      final payload = ShapePayload(
        cornerRadius: 12,
        fillType: FillType.linearGradient,
        fillGradientEnd: const Color(0xFFEA580C),
        fillOpacity: 0.9,
        strokeStyle: StrokeStyle.dashed,
        hasShadow: true,
        label: 'Is Authenticated?',
        branchTop: 'Retry',
        branchRight: 'Yes',
        branchBottom: 'No',
        branchLeft: 'Fallback',
      );

      final restored = ShapePayload.fromJson(payload.toJson());

      expect(restored.cornerRadius, 12);
      expect(restored.fillType, FillType.linearGradient);
      expect(restored.fillGradientEnd, const Color(0xFFEA580C));
      expect(restored.fillOpacity, 0.9);
      expect(restored.strokeStyle, StrokeStyle.dashed);
      expect(restored.hasShadow, isTrue);
      expect(restored.label, 'Is Authenticated?');
      expect(restored.branchTop, 'Retry');
      expect(restored.branchRight, 'Yes');
      expect(restored.branchBottom, 'No');
      expect(restored.branchLeft, 'Fallback');
    });

    test('exports diamond with dash array and opacity in SVG', () {
      final document = CanvasDocument(
        projectId: 'diamond-test',
        updatedAt: DateTime(2026),
        nodes: [
          CanvasNode(
            id: 'diamond-1',
            type: NodeType.diamond,
            x: 50,
            y: 50,
            width: 120,
            height: 120,
            payload: ShapePayload(
              fillOpacity: 0.75,
              strokeStyle: StrokeStyle.dotted,
            ),
          ),
        ],
      );

      final svg = ExportService.exportVectorSvg(document);

      expect(
        svg,
        contains(
          '<polygon points="110.0,50.0 170.0,110.0 110.0,170.0 50.0,110.0"',
        ),
      );
      expect(svg, contains('stroke-dasharray="2 3"'));
      expect(svg, contains('fill-opacity="0.75"'));
    });
  });
}
