import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/canvas/utils/minimap_geometry.dart';

void main() {
  group('MinimapTransform', () {
    test('preserves negative coordinates and round trips points', () {
      final transform = MinimapTransform.fromWorldBounds(
        const Rect.fromLTRB(-300, -100, 700, 500),
        const Size(220, 140),
      );
      const point = Offset(125, 220);

      final mapped = transform.worldToMinimap(point);
      final restored = transform.minimapToWorld(mapped);

      expect(restored.dx, closeTo(point.dx, 0.0001));
      expect(restored.dy, closeTo(point.dy, 0.0001));
      expect(transform.mapRect, const Rect.fromLTWH(0, 0, 220, 140));
    });

    test('expands empty and degenerate bounds to a stable finite domain', () {
      final empty = MinimapTransform.worldBoundsFor(nodeBounds: const []);
      final point = MinimapTransform.worldBoundsFor(
        nodeBounds: [const Rect.fromLTWH(40, 70, 0, 0)],
      );

      expect(empty.width, greaterThanOrEqualTo(200));
      expect(empty.height, greaterThanOrEqualTo(200));
      expect(point.width, greaterThanOrEqualTo(200));
      expect(point.height, greaterThanOrEqualTo(200));
      expect(empty.left.isFinite, isTrue);
      expect(point.top.isFinite, isTrue);
    });

    test('skips non-finite bounds and includes viewport fallback', () {
      final result = MinimapTransform.worldBoundsFor(
        nodeBounds: [
          const Rect.fromLTRB(double.nan, 0, 20, 20),
          const Rect.fromLTRB(-10, -20, 30, 40),
        ],
        viewportBounds: const Rect.fromLTWH(500, 600, 10, 10),
      );

      expect(result.left, lessThanOrEqualTo(-10));
      expect(result.top, lessThanOrEqualTo(-20));
      expect(result.right, greaterThanOrEqualTo(510));
      expect(result.bottom, greaterThanOrEqualTo(610));
    });

    test('normalizes reversed rectangles', () {
      final result = MinimapTransform.worldBoundsFor(
        nodeBounds: [const Rect.fromLTRB(20, 30, -20, -10)],
      );

      expect(result.left, lessThanOrEqualTo(-20));
      expect(result.top, lessThanOrEqualTo(-10));
      expect(result.right, greaterThanOrEqualTo(20));
      expect(result.bottom, greaterThanOrEqualTo(30));
    });
  });
}
