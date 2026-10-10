import 'dart:math';
import 'package:varian/domain/models/drawing_paper_payload.dart';

class StrokeStabilizer {
  final List<DrawingStrokePoint> _rawQueue = [];
  final int maxQueueSize;
  final double strength; // 0.0 to 1.0

  StrokeStabilizer({this.strength = 0.5, this.maxQueueSize = 8});

  void reset() {
    _rawQueue.clear();
  }

  DrawingStrokePoint addPoint(DrawingStrokePoint point) {
    if (strength <= 0.01) {
      return point;
    }

    _rawQueue.add(point);
    final queueLimit = max(3, (strength * maxQueueSize).round());
    if (_rawQueue.length > queueLimit) {
      _rawQueue.removeAt(0);
    }

    double totalWeight = 0.0;
    double weightedX = 0.0;
    double weightedY = 0.0;
    double weightedP = 0.0;

    for (int i = 0; i < _rawQueue.length; i++) {
      final w = (i + 1).toDouble();
      totalWeight += w;
      weightedX += _rawQueue[i].x * w;
      weightedY += _rawQueue[i].y * w;
      weightedP += _rawQueue[i].pressure * w;
    }

    return DrawingStrokePoint(
      x: weightedX / totalWeight,
      y: weightedY / totalWeight,
      pressure: weightedP / totalWeight,
      tilt: point.tilt,
      timestamp: point.timestamp,
    );
  }

  static List<DrawingStrokePoint> applyTaper(
    List<DrawingStrokePoint> points, {
    double startTaperFraction = 0.15,
    double endTaperFraction = 0.2,
  }) {
    if (points.length < 4) return points;

    final count = points.length;
    final startIndex = (count * startTaperFraction)
        .clamp(1, count ~/ 2)
        .toInt();
    final endIndex = (count * (1 - endTaperFraction))
        .clamp(count ~/ 2, count - 1)
        .toInt();

    final result = <DrawingStrokePoint>[];
    for (int i = 0; i < count; i++) {
      final pt = points[i];
      double pFactor = 1.0;

      if (i < startIndex) {
        pFactor = (i + 1) / (startIndex + 1);
      } else if (i > endIndex) {
        pFactor = (count - i) / (count - endIndex);
      }

      result.add(
        DrawingStrokePoint(
          x: pt.x,
          y: pt.y,
          pressure: pt.pressure * pFactor.clamp(0.1, 1.0),
          tilt: pt.tilt,
          timestamp: pt.timestamp,
        ),
      );
    }

    return result;
  }
}
