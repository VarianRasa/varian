import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  group('Advanced cylinder tools', () {
    test(
      'serializes cylinder partitions, cap ratio, badge text, and gradient',
      () {
        final payload = ShapePayload(
          cylinderPartitions: 4,
          cylinderCapRatio: 0.3,
          badgeText: 'Primary',
          fillType: FillType.linearGradient,
          fillGradientEnd: const Color(0xFF1E3A8A),
          fillOpacity: 0.85,
          label: 'PostgreSQL DB',
        );

        final restored = ShapePayload.fromJson(payload.toJson());

        expect(restored.cylinderPartitions, 4);
        expect(restored.cylinderCapRatio, 0.3);
        expect(restored.badgeText, 'Primary');
        expect(restored.fillType, FillType.linearGradient);
        expect(restored.fillGradientEnd, const Color(0xFF1E3A8A));
        expect(restored.fillOpacity, 0.85);
        expect(restored.label, 'PostgreSQL DB');
      },
    );

    test('exports true cylinder shape and top cap in SVG', () {
      final document = CanvasDocument(
        projectId: 'cylinder-test',
        updatedAt: DateTime(2026),
        nodes: [
          CanvasNode(
            id: 'cylinder-1',
            type: NodeType.cylinder,
            x: 20,
            y: 40,
            width: 100,
            height: 140,
            payload: ShapePayload(
              cylinderCapRatio: 0.2,
              fillOpacity: 0.9,
              strokeStyle: StrokeStyle.dashed,
            ),
          ),
        ],
      );

      final svg = ExportService.exportVectorSvg(document);

      expect(svg, contains('<ellipse cx="70.0" cy="54.0" rx="50.0" ry="14.0"'));
      expect(svg, contains('stroke-dasharray="6 4"'));
      expect(svg, contains('fill-opacity="0.9"'));
    });
  });
}
