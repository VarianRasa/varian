import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:varian/domain/models/node_payload.dart';

class ChartCanvasCategoryHitTester {
  const ChartCanvasCategoryHitTester._();

  static String? categoryAt({
    required ChartPayload payload,
    required Size size,
    required Offset localPosition,
  }) {
    final count = payload.categories.length;
    if (count == 0 || size.width <= 0 || size.height <= 0) return null;

    final index = switch (payload.chartType) {
      ChartType.pie ||
      ChartType.doughnut ||
      ChartType.radar => _radialIndex(payload, size, localPosition, count),
      ChartType.line ||
      ChartType.bar ||
      ChartType.scatter => (localPosition.dx / size.width * count).floor(),
    };
    if (index == null || index < 0 || index >= count) return null;
    return payload.categories[index];
  }

  static int? _radialIndex(
    ChartPayload payload,
    Size size,
    Offset localPosition,
    int count,
  ) {
    final center = Offset(size.width / 2, size.height / 2);
    final vector = localPosition - center;
    if (payload.chartType == ChartType.doughnut &&
        vector.distance < math.min(size.width, size.height) * 0.14) {
      return null;
    }
    var angle = math.atan2(vector.dy, vector.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    return (angle / (math.pi * 2) * count).floor();
  }
}
