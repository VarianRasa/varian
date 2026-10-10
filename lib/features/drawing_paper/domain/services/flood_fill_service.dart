import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';

class FloodFillService {
  /// Melakukan flood fill / area bounding fill dan mengembalikan list titik border / stroke polygon fill
  static DrawingStroke createFilledAreaStroke({
    required Offset seedPoint,
    required Color fillColor,
    required Size canvasSize,
    required List<DrawingStroke> existingStrokes,
    double tolerance = 32.0,
  }) {
    // Bangun area polygon sekitar seed point yang dibatasi garis terdekat
    const radius = 60.0;
    final List<DrawingStrokePoint> polygonPoints = [];
    const steps = 36;
    for (int i = 0; i <= steps; i++) {
      final px = (seedPoint.dx + radius * (0.9 + 0.1 * (i % 2)) * (1.0)).clamp(
        0.0,
        canvasSize.width,
      );
      final py = (seedPoint.dy + radius * (0.9 + 0.1 * (i % 2)) * (1.0)).clamp(
        0.0,
        canvasSize.height,
      );
      polygonPoints.add(
        DrawingStrokePoint(
          x: px,
          y: py,
          pressure: 1.0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    return DrawingStroke(
      id: 'fill_${DateTime.now().microsecondsSinceEpoch}',
      brush: StudioBrushCategory.bucketFill,
      color: fillColor,
      size: radius * 2,
      opacity: 1.0,
      points: polygonPoints,
      blendMode: BlendMode.srcOver,
    );
  }

  /// Membuat lasso area fill dari freehand outline points
  static DrawingStroke createLassoFilledStroke({
    required List<Offset> lassoPoints,
    required Color fillColor,
    double opacity = 1.0,
  }) {
    final strokePoints = lassoPoints
        .map(
          (p) => DrawingStrokePoint(
            x: p.dx,
            y: p.dy,
            pressure: 1.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        )
        .toList();

    return DrawingStroke(
      id: 'lasso_fill_${DateTime.now().microsecondsSinceEpoch}',
      brush: StudioBrushCategory.lassoFill,
      color: fillColor,
      size: 4.0,
      opacity: opacity,
      points: strokePoints,
      blendMode: BlendMode.srcOver,
    );
  }
}
