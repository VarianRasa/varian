import 'dart:ui';
import '../../../domain/models/node.dart';

class SnapResult {
  final double dx;
  final double dy;
  final List<SnapGuide> guides;

  const SnapResult({
    required this.dx,
    required this.dy,
    this.guides = const [],
  });
}

class SnapGuide {
  final bool isVertical;
  final double position;

  const SnapGuide({required this.isVertical, required this.position});
}

class SnapEngine {
  static const double snapThreshold = 5.0;

  static SnapResult calculateSnap({
    required Rect targetRect,
    required List<CanvasNode> otherNodes,
    double gridSpacing = 0.0,
  }) {
    double? bestDx;
    double bestDxAbs = snapThreshold;
    double? bestDy;
    double bestDyAbs = snapThreshold;
    final guides = <SnapGuide>[];

    final tEdges = [targetRect.left, targetRect.center.dx, targetRect.right];
    final tYEdges = [targetRect.top, targetRect.center.dy, targetRect.bottom];

    double? matchedOx;
    double? matchedOy;

    for (final node in otherNodes) {
      if (!node.visible) continue;
      final o = node.bounds;
      final oXEdges = [o.left, o.center.dx, o.right];
      final oYEdges = [o.top, o.center.dy, o.bottom];

      for (final tx in tEdges) {
        for (final ox in oXEdges) {
          final d = ox - tx;
          if (d.abs() < bestDxAbs) {
            bestDx = d;
            bestDxAbs = d.abs();
            matchedOx = ox;
          }
        }
      }

      for (final ty in tYEdges) {
        for (final oy in oYEdges) {
          final d = oy - ty;
          if (d.abs() < bestDyAbs) {
            bestDy = d;
            bestDyAbs = d.abs();
            matchedOy = oy;
          }
        }
      }
    }

    final sdx = bestDx ?? 0.0;
    final sdy = bestDy ?? 0.0;

    if (bestDx != null && matchedOx != null) {
      guides.add(SnapGuide(isVertical: true, position: matchedOx));
    }

    if (bestDy != null && matchedOy != null) {
      guides.add(SnapGuide(isVertical: false, position: matchedOy));
    }

    return SnapResult(dx: sdx, dy: sdy, guides: guides);
  }
}

class SpacingMeasurement {
  final bool isVertical;
  final Offset a;
  final Offset b;
  final double distance;

  const SpacingMeasurement({
    required this.isVertical,
    required this.a,
    required this.b,
    required this.distance,
  });
}

class SpacingEngine {
  static const double alignTolerance = 3.0;
  static const double gapTolerance = 1.0;
  static const double snapThreshold = 8.0;

  static List<SpacingMeasurement> calculateMeasurements({
    required Rect targetRect,
    required List<CanvasNode> otherNodes,
    bool altHeld = false,
  }) {
    if (!altHeld || otherNodes.isEmpty) return const [];
    final ms = <SpacingMeasurement>[];
    for (final n in otherNodes) {
      if (!n.visible) continue;
      final o = n.bounds;
      if ((o.center.dy - targetRect.center.dy).abs() < 100) {
        if (o.right < targetRect.left) {
          ms.add(
            SpacingMeasurement(
              isVertical: false,
              a: Offset(o.right, targetRect.center.dy),
              b: Offset(targetRect.left, targetRect.center.dy),
              distance: targetRect.left - o.right,
            ),
          );
        } else if (targetRect.right < o.left) {
          ms.add(
            SpacingMeasurement(
              isVertical: false,
              a: Offset(targetRect.right, targetRect.center.dy),
              b: Offset(o.left, targetRect.center.dy),
              distance: o.left - targetRect.right,
            ),
          );
        }
      }
    }
    return ms;
  }

  static ({
    double dx,
    double dy,
    bool snappedX,
    bool snappedY,
    List<SpacingMeasurement> measurements,
  })
  calculateSpacingSnap({
    required Rect targetRect,
    required List<CanvasNode> otherNodes,
  }) {
    double dx = 0.0;
    double dy = 0.0;
    bool snappedX = false;
    bool snappedY = false;
    final ms = <SpacingMeasurement>[];

    final row = <Rect>[];
    for (final n in otherNodes) {
      if (n.visible &&
          (n.bounds.center.dy - targetRect.center.dy).abs() < alignTolerance) {
        row.add(n.bounds);
      }
    }
    if (row.length >= 2) {
      final (corr, l, r, gap) = _facingGapCorrection(
        row,
        targetRect,
        horizontal: true,
      );
      if (corr.abs() >= 0.001) {
        snappedX = true;
        dx = corr;
        final y = targetRect.center.dy;
        final left = targetRect.left + corr;
        final right = targetRect.right + corr;
        if (l != null && l < left) {
          ms.add(
            SpacingMeasurement(
              isVertical: false,
              a: Offset(l, y),
              b: Offset(left, y),
              distance: (left - l).abs(),
            ),
          );
        }
        if (r != null && right < r) {
          ms.add(
            SpacingMeasurement(
              isVertical: false,
              a: Offset(right, y),
              b: Offset(r, y),
              distance: (r - right).abs(),
            ),
          );
        }
      }
    }

    final column = <Rect>[];
    for (final n in otherNodes) {
      if (n.visible &&
          (n.bounds.center.dx - targetRect.center.dx).abs() < alignTolerance) {
        column.add(n.bounds);
      }
    }
    if (column.length >= 2) {
      final (corr, t, b, gap) = _facingGapCorrection(
        column,
        targetRect,
        horizontal: false,
      );
      if (corr.abs() >= 0.001) {
        snappedY = true;
        dy = corr;
        final x = targetRect.center.dx;
        final top = targetRect.top + corr;
        final bottom = targetRect.bottom + corr;
        if (t != null && t < top) {
          ms.add(
            SpacingMeasurement(
              isVertical: true,
              a: Offset(x, t),
              b: Offset(x, top),
              distance: (top - t).abs(),
            ),
          );
        }
        if (b != null && bottom < b) {
          ms.add(
            SpacingMeasurement(
              isVertical: true,
              a: Offset(x, bottom),
              b: Offset(x, b),
              distance: (b - bottom).abs(),
            ),
          );
        }
      }
    }

    return (
      dx: dx,
      dy: dy,
      snappedX: snappedX,
      snappedY: snappedY,
      measurements: ms,
    );
  }

  static (double corr, double? prevEdge, double? nextEdge, double gap)
  _facingGapCorrection(
    List<Rect> neighbors,
    Rect target, {
    required bool horizontal,
  }) {
    if (horizontal) {
      neighbors.sort((a, b) => a.left.compareTo(b.left));
      final gaps = <double>[];
      for (var i = 0; i < neighbors.length - 1; i++) {
        final g = neighbors[i + 1].left - neighbors[i].right;
        if (g > 0) gaps.add(g);
      }
      if (gaps.isEmpty) return (0.0, null, null, 0.0);
      final refGap = gaps.first;

      Rect? leftNeighbor;
      Rect? rightNeighbor;
      for (final n in neighbors) {
        if (n.right <= target.left + snapThreshold) leftNeighbor = n;
        if (n.left >= target.right - snapThreshold && rightNeighbor == null) {
          rightNeighbor = n;
        }
      }

      if (leftNeighbor != null) {
        final expectedLeft = leftNeighbor.right + refGap;
        final d = expectedLeft - target.left;
        if (d.abs() <= snapThreshold) {
          return (d, leftNeighbor.right, rightNeighbor?.left, refGap);
        }
      }
      if (rightNeighbor != null) {
        final expectedRight = rightNeighbor.left - refGap;
        final d = expectedRight - target.right;
        if (d.abs() <= snapThreshold) {
          return (d, leftNeighbor?.right, rightNeighbor.left, refGap);
        }
      }
    } else {
      neighbors.sort((a, b) => a.top.compareTo(b.top));
      final gaps = <double>[];
      for (var i = 0; i < neighbors.length - 1; i++) {
        final g = neighbors[i + 1].top - neighbors[i].bottom;
        if (g > 0) gaps.add(g);
      }
      if (gaps.isEmpty) return (0.0, null, null, 0.0);
      final refGap = gaps.first;

      Rect? topNeighbor;
      Rect? bottomNeighbor;
      for (final n in neighbors) {
        if (n.bottom <= target.top + snapThreshold) topNeighbor = n;
        if (n.top >= target.bottom - snapThreshold && bottomNeighbor == null) {
          bottomNeighbor = n;
        }
      }

      if (topNeighbor != null) {
        final expectedTop = topNeighbor.bottom + refGap;
        final d = expectedTop - target.top;
        if (d.abs() <= snapThreshold) {
          return (d, topNeighbor.bottom, bottomNeighbor?.top, refGap);
        }
      }
      if (bottomNeighbor != null) {
        final expectedBottom = bottomNeighbor.top - refGap;
        final d = expectedBottom - target.bottom;
        if (d.abs() <= snapThreshold) {
          return (d, topNeighbor?.bottom, bottomNeighbor.top, refGap);
        }
      }
    }

    return (0.0, null, null, 0.0);
  }
}
