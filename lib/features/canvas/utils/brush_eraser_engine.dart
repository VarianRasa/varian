import 'dart:math' as math;
import 'dart:ui';
import '../../../domain/models/drawing_payload.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';

class BrushEraserEngine {
  /// Check if an eraser point with given radius intersects a drawing node's stroke.
  static bool intersectsDrawingNode(
    CanvasNode node,
    Offset eraserWorldPos,
    double eraserRadius,
  ) {
    if (node.type != NodeType.drawing || !node.visible || node.locked) {
      return false;
    }
    if (node.payload is! DrawingPayload) return false;
    final payload = node.payload as DrawingPayload;
    if (payload.points.isEmpty) return false;

    final effectiveRadius = eraserRadius + (payload.strokeWidth / 2.0);
    final expandedBounds = node.bounds.inflate(effectiveRadius);
    if (!expandedBounds.contains(eraserWorldPos)) {
      return false;
    }

    final localEraserPos = Offset(
      eraserWorldPos.dx - node.x,
      eraserWorldPos.dy - node.y,
    );

    // Check single point drawing
    if (payload.points.length == 1) {
      return (payload.points.first - localEraserPos).distance <=
          effectiveRadius;
    }

    // Check segment distances
    for (int i = 0; i < payload.points.length - 1; i++) {
      final p1 = payload.points[i];
      final p2 = payload.points[i + 1];
      final dist = _pointToSegmentDistance(localEraserPos, p1, p2);
      if (dist <= effectiveRadius) {
        return true;
      }
    }

    return false;
  }

  /// Calculates the shortest distance from point p to line segment v-w.
  static double _pointToSegmentDistance(Offset p, Offset v, Offset w) {
    final l2 = (v.dx - w.dx) * (v.dx - w.dx) + (v.dy - w.dy) * (v.dy - w.dy);
    if (l2 == 0.0) return (p - v).distance;
    final t = math.max(
      0.0,
      math.min(
        1.0,
        ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2,
      ),
    );
    final projection = Offset(
      v.dx + t * (w.dx - v.dx),
      v.dy + t * (w.dy - v.dy),
    );
    return (p - projection).distance;
  }

  /// Erase segments of a drawing node that fall within the eraser circle.
  /// Adds exact pixel cutouts so any brush size is carved with sub-pixel precision.
  static CanvasNode? applyCutout(
    CanvasNode node,
    Offset eraserWorldPos,
    double eraserRadius,
  ) {
    if (node.type != NodeType.drawing || node.payload is! DrawingPayload) {
      return node;
    }
    final payload = node.payload as DrawingPayload;
    if (payload.points.isEmpty) return node;

    final localEraserPos = Offset(
      eraserWorldPos.dx - node.x,
      eraserWorldPos.dy - node.y,
    );

    final newCutouts = List<EraserCutout>.from(payload.cutouts);
    final existsNearby = newCutouts.any(
      (c) =>
          (c.position - localEraserPos).distance <
              math.max(0.5, eraserRadius * 0.3) &&
          c.radius >= eraserRadius,
    );
    if (!existsNearby) {
      newCutouts.add(
        EraserCutout(position: localEraserPos, radius: eraserRadius),
      );
    }

    return node.copyWith(payload: payload.copyWith(cutouts: newCutouts));
  }
}
