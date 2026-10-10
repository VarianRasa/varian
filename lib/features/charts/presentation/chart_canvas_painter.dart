import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';

class ChartCanvasPainter {
  static void paint(
    Canvas canvas,
    CanvasNode node,
    ChartPayload payload, {
    required CanvasRenderTokens tokens,
  }) {
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final card = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(card, Paint()..color = tokens.panelElevated);
    canvas.drawRRect(
      card,
      Paint()
        ..color = tokens.panelBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    var top = 8.0;
    if (payload.title.isNotEmpty) {
      _paintText(
        canvas,
        payload.title,
        Offset(10, top),
        TextStyle(
          color: tokens.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        maxWidth: math.max(20, node.width - 20),
      );
      top += 20;
    }

    final legendHeight = payload.showLegend && payload.series.isNotEmpty
        ? 20.0
        : 4.0;
    final plot = Rect.fromLTWH(
      10,
      top,
      math.max(20, node.width - 20),
      math.max(20, node.height - top - legendHeight - 6),
    );

    switch (payload.chartType) {
      case ChartType.line:
        _paintLine(canvas, plot, payload, tokens);
        break;
      case ChartType.bar:
        _paintBar(canvas, plot, payload, tokens);
        break;
      case ChartType.pie:
      case ChartType.doughnut:
        _paintPie(canvas, plot, payload, tokens);
        break;
      case ChartType.scatter:
        _paintScatter(canvas, plot, payload, tokens);
        break;
      case ChartType.radar:
        _paintRadar(canvas, plot, payload, tokens);
        break;
    }

    if (payload.showLegend && payload.series.isNotEmpty) {
      _paintLegend(
        canvas,
        payload,
        Offset(10, node.height - 18),
        node.width - 20,
        tokens,
      );
    }
  }

  static void _paintLine(
    Canvas canvas,
    Rect plot,
    ChartPayload payload,
    CanvasRenderTokens tokens,
  ) {
    final values = payload.series.expand(_valuesFor).toList();
    final bounds = _chartBounds(values, payload);
    _paintGrid(canvas, plot, payload, bounds: bounds, tokens: tokens);
    for (
      var seriesIndex = 0;
      seriesIndex < payload.series.length;
      seriesIndex++
    ) {
      final series = payload.series[seriesIndex];
      final values = _valuesFor(series);
      if (values.isEmpty) continue;
      final path = Path();
      for (var index = 0; index < values.length; index++) {
        final point = _valuePoint(
          plot,
          index,
          values[index],
          values.length,
          bounds,
        );
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else if (payload.lineCurved) {
          final previous = _valuePoint(
            plot,
            index - 1,
            values[index - 1],
            values.length,
            bounds,
          );
          final middleX = (previous.dx + point.dx) / 2;
          path.cubicTo(
            middleX,
            previous.dy,
            middleX,
            point.dy,
            point.dx,
            point.dy,
          );
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = series.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (payload.showDots) {
        for (var index = 0; index < values.length; index++) {
          final point = _valuePoint(
            plot,
            index,
            values[index],
            values.length,
            bounds,
          );
          canvas.drawCircle(point, 3, Paint()..color = series.color);
        }
      }
    }
    _paintCategoryLabels(canvas, plot, payload, tokens);
  }

  static void _paintBar(
    Canvas canvas,
    Rect plot,
    ChartPayload payload,
    CanvasRenderTokens tokens,
  ) {
    final values = payload.series.expand(_valuesFor).toList();
    final bounds = _chartBounds(values, payload);
    _paintGrid(canvas, plot, payload, bounds: bounds, tokens: tokens);
    final groupCount = math.max(
      1,
      math.max(
        payload.categories.length,
        payload.series.fold<int>(0, (maxLength, series) {
          return math.max(maxLength, _valuesFor(series).length);
        }),
      ),
    );
    final groupWidth = plot.width / groupCount;
    final rodWidth = math.min(
      20.0,
      math.max(4.0, groupWidth / math.max(1, payload.series.length + 1)),
    );
    for (var groupIndex = 0; groupIndex < groupCount; groupIndex++) {
      for (
        var seriesIndex = 0;
        seriesIndex < payload.series.length;
        seriesIndex++
      ) {
        final series = payload.series[seriesIndex];
        final value = _valueAt(series, groupIndex);
        final color = series.color;
        if (payload.barOrientation == ChartBarOrientation.horizontal) {
          final y =
              plot.top +
              groupWidth * groupIndex +
              (groupWidth - rodWidth * payload.series.length) / 2 +
              seriesIndex * rodWidth;
          final zeroX = _scaleX(0, plot.left, plot.right, bounds);
          final valueX = _scaleX(value, plot.left, plot.right, bounds);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(
                math.min(zeroX, valueX),
                y,
                math.max(zeroX, valueX),
                y + rodWidth - 2,
              ),
              const Radius.circular(2),
            ),
            Paint()..color = color,
          );
        } else {
          final x =
              plot.left +
              groupWidth * groupIndex +
              (groupWidth - rodWidth * payload.series.length) / 2 +
              seriesIndex * rodWidth;
          final zeroY = _scaleY(0, plot.top, plot.bottom, bounds);
          final valueY = _scaleY(value, plot.top, plot.bottom, bounds);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(
                x,
                math.min(zeroY, valueY),
                x + rodWidth - 2,
                math.max(zeroY, valueY),
              ),
              const Radius.circular(2),
            ),
            Paint()..color = color,
          );
        }
      }
    }
    if (payload.barOrientation == ChartBarOrientation.vertical) {
      _paintCategoryLabels(canvas, plot, payload, tokens);
    }
  }

  static void _paintPie(
    Canvas canvas,
    Rect plot,
    ChartPayload payload,
    CanvasRenderTokens tokens,
  ) {
    final series = payload.series.isEmpty
        ? ChartSeries(values: [1])
        : payload.series.first;
    final values = _valuesFor(series);
    final safeValues = values.isEmpty ? [1.0] : values;
    final total = safeValues.fold<double>(0, (sum, value) => sum + value.abs());
    final center = plot.center;
    final radius = math.min(plot.width, plot.height) / 2;
    var start = -math.pi / 2;
    for (var index = 0; index < safeValues.length; index++) {
      final ratio = total == 0
          ? 1 / safeValues.length
          : safeValues[index].abs() / total;
      final sweep = math.pi * 2 * ratio;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(plotFromCenter(center, radius), start, sweep, false)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = _colorAt(payload, index, series.color),
      );
      start += sweep;
    }
    if (payload.chartType == ChartType.doughnut) {
      canvas.drawCircle(
        center,
        radius * payload.doughnutHoleRatio,
        Paint()..color = tokens.panelElevated,
      );
    }
  }

  static void _paintScatter(
    Canvas canvas,
    Rect plot,
    ChartPayload payload,
    CanvasRenderTokens tokens,
  ) {
    final points = <(ChartPoint, Color)>[];
    for (final series in payload.series) {
      final seriesPoints = series.points.isEmpty
          ? [
              for (var index = 0; index < series.values.length; index++)
                ChartPoint(x: index.toDouble(), y: series.values[index]),
            ]
          : series.points;
      for (final point in seriesPoints) {
        points.add((point, series.color));
      }
    }
    final safePoints = points.isEmpty
        ? [(ChartPoint(x: 0, y: 0), payload.colors.first)]
        : points;
    final xBounds = _bounds(safePoints.map((entry) => entry.$1.x));
    final yBounds = _chartBounds(
      safePoints.map((entry) => entry.$1.y),
      payload,
    );
    _paintGrid(canvas, plot, payload, bounds: yBounds, tokens: tokens);
    for (final entry in safePoints) {
      final point = Offset(
        _scaleX(entry.$1.x, plot.left, plot.right, xBounds),
        _scaleY(entry.$1.y, plot.top, plot.bottom, yBounds),
      );
      canvas.drawCircle(point, 4, Paint()..color = entry.$2);
    }
  }

  static void _paintRadar(
    Canvas canvas,
    Rect plot,
    ChartPayload payload,
    CanvasRenderTokens tokens,
  ) {
    final count = math.max(
      3,
      math.max(
        payload.categories.length,
        payload.series.fold<int>(0, (maxLength, series) {
          return math.max(maxLength, _valuesFor(series).length);
        }),
      ),
    );
    final center = plot.center;
    final radius = math.min(plot.width, plot.height) * 0.34;
    final bounds = _chartBounds(
      payload.series.expand(_valuesFor),
      payload,
      minimum: 0,
    );
    if (payload.showGrid) {
      for (var ring = 1; ring <= 4; ring++) {
        _drawRadarPolygon(
          canvas,
          center,
          radius * ring / 4,
          count,
          Paint()
            ..color = tokens.panelBorder.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    for (var index = 0; index < count; index++) {
      final angle = -math.pi / 2 + index * math.pi * 2 / count;
      final end = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(
        center,
        end,
        Paint()
          ..color = tokens.panelBorder
          ..strokeWidth = 1,
      );
      _paintText(
        canvas,
        _categoryAt(payload, index),
        Offset(end.dx - 18, end.dy - 6),
        TextStyle(color: tokens.textMuted, fontSize: 8),
        maxWidth: 36,
      );
    }
    for (
      var seriesIndex = 0;
      seriesIndex < payload.series.length;
      seriesIndex++
    ) {
      final series = payload.series[seriesIndex];
      final values = _valuesFor(series);
      if (values.isEmpty) continue;
      final path = Path();
      for (var index = 0; index < count; index++) {
        final value = _valueAt(series, index);
        final ratio = _normalize(value, bounds);
        final angle = -math.pi / 2 + index * math.pi * 2 / count;
        final point = Offset(
          center.dx + math.cos(angle) * radius * ratio,
          center.dy + math.sin(angle) * radius * ratio,
        );
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = series.color.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = series.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  static void _paintGrid(
    Canvas canvas,
    Rect plot,
    ChartPayload payload, {
    required (double, double) bounds,
    required CanvasRenderTokens tokens,
  }) {
    if (payload.showAxes) {
      canvas.drawLine(
        Offset(plot.left, plot.bottom),
        Offset(plot.right, plot.bottom),
        Paint()
          ..color = tokens.panelBorder
          ..strokeWidth = 1,
      );
      canvas.drawLine(
        Offset(plot.left, plot.top),
        Offset(plot.left, plot.bottom),
        Paint()
          ..color = tokens.panelBorder
          ..strokeWidth = 1,
      );
    }
    if (!payload.showGrid) return;
    final gridPaint = Paint()
      ..color = tokens.panelBorder.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final y = plot.top + plot.height * index / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
  }

  static void _paintCategoryLabels(
    Canvas canvas,
    Rect plot,
    ChartPayload payload,
    CanvasRenderTokens tokens,
  ) {
    if (!payload.showAxes || payload.categories.isEmpty) return;
    for (var index = 0; index < payload.categories.length; index++) {
      final x = payload.categories.length == 1
          ? plot.center.dx
          : plot.left + plot.width * index / (payload.categories.length - 1);
      _paintText(
        canvas,
        payload.categories[index],
        Offset(x - 18, plot.bottom + 3),
        TextStyle(color: tokens.textMuted, fontSize: 8),
        maxWidth: 36,
      );
    }
  }

  static void _paintLegend(
    Canvas canvas,
    ChartPayload payload,
    Offset offset,
    double maxWidth,
    CanvasRenderTokens tokens,
  ) {
    var x = offset.dx;
    for (final series in payload.series) {
      if (x >= offset.dx + maxWidth) break;
      canvas.drawCircle(
        Offset(x + 4, offset.dy + 5),
        3,
        Paint()..color = series.color,
      );
      x += 10;
      final width = math.min(82.0, maxWidth - (x - offset.dx));
      _paintText(
        canvas,
        series.name,
        Offset(x, offset.dy),
        TextStyle(color: tokens.textMuted, fontSize: 8),
        maxWidth: width,
      );
      x += width + 10;
    }
  }

  static void _drawRadarPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    int count,
    Paint paint,
  ) {
    final path = Path();
    for (var index = 0; index < count; index++) {
      final angle = -math.pi / 2 + index * math.pi * 2 / count;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  static Offset _valuePoint(
    Rect plot,
    int index,
    double value,
    int count,
    (double, double) bounds,
  ) {
    final x = count <= 1
        ? plot.center.dx
        : plot.left + plot.width * index / (count - 1);
    return Offset(x, _scaleY(value, plot.top, plot.bottom, bounds));
  }

  static double _scaleX(
    double value,
    double start,
    double end,
    (double, double) bounds,
  ) {
    final span = bounds.$2 - bounds.$1;
    final ratio = span == 0
        ? 0.5
        : ((value - bounds.$1) / span).clamp(0.0, 1.0);
    return start + (end - start) * ratio;
  }

  static double _scaleY(
    double value,
    double top,
    double bottom,
    (double, double) bounds,
  ) {
    final span = bounds.$2 - bounds.$1;
    final ratio = span == 0
        ? 0.5
        : ((value - bounds.$1) / span).clamp(0.0, 1.0);
    return bottom - (bottom - top) * ratio;
  }

  static double _normalize(double value, (double, double) bounds) {
    final span = bounds.$2 - bounds.$1;
    if (span == 0) return 0.5;
    return ((value - bounds.$1) / span).clamp(0.0, 1.0);
  }

  static (double, double) _chartBounds(
    Iterable<double> values,
    ChartPayload payload, {
    double? minimum,
  }) {
    final bounds = _bounds(values, minimum: minimum);
    var minValue = payload.minY ?? bounds.$1;
    var maxValue = payload.maxY ?? bounds.$2;
    if (minValue > maxValue) (minValue, maxValue) = (maxValue, minValue);
    if (minValue == maxValue) {
      minValue -= 1;
      maxValue += 1;
    }
    return (minValue, maxValue);
  }

  static (double, double) _bounds(Iterable<double> values, {double? minimum}) {
    final finite = values.where((value) => value.isFinite).toList();
    if (finite.isEmpty) return (minimum ?? 0, (minimum ?? 0) + 1);
    var minValue = finite.reduce((a, b) => a < b ? a : b);
    final maxValue = finite.reduce((a, b) => a > b ? a : b);
    if (minimum != null) minValue = math.min(minValue, minimum).toDouble();
    var lower = math.min(0.0, minValue).toDouble();
    var upper = math.max(0.0, maxValue).toDouble();
    if (lower == upper) {
      lower -= 1;
      upper += 1;
    }
    return (lower, upper);
  }

  static List<double> _valuesFor(ChartSeries series) => series.values.isEmpty
      ? [for (final point in series.points) point.y]
      : series.values;

  static double _valueAt(ChartSeries series, int index) {
    final values = _valuesFor(series);
    return index < values.length ? values[index] : 0;
  }

  static Color _colorAt(ChartPayload payload, int index, Color fallback) {
    if (payload.colors.isEmpty) return fallback;
    return payload.colors[index % payload.colors.length];
  }

  static String _categoryAt(ChartPayload payload, int index) {
    if (index >= 0 && index < payload.categories.length) {
      return payload.categories[index];
    }
    return '${index + 1}';
  }

  static void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(1, maxWidth));
    painter.paint(canvas, offset);
  }

  static Rect plotFromCenter(Offset center, double radius) =>
      Rect.fromCircle(center: center, radius: radius);
}
