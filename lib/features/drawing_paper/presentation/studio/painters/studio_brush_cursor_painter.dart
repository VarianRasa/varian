import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

enum StudioBrushCursorShape {
  gPen,
  maruPen,
  inkPen,
  fudeBrush,
  marker,
  airbrush,
  pencilRough,
  oilPastel,
  watercolor,
  screentone,
  specialPen,
  hardEraser,
  softEraser,
  vectorEraser,
  smudge,
  blur,
  bucketFill,
  lassoFill,
}

class StudioBrushCursorPainter extends CustomPainter {
  final Offset? position;
  final StudioBrushCategory brush;
  final StudioTool tool;
  final Color color;
  final double brushSize;
  final double zoom;

  const StudioBrushCursorPainter({
    this.position,
    this.brush = StudioBrushCategory.gPen,
    this.tool = StudioTool.brush,
    this.color = Colors.black,
    this.brushSize = 6.0,
    this.zoom = 1.0,
  });

  static StudioBrushCursorShape shapeFor(StudioBrushCategory brush) =>
      switch (brush) {
        StudioBrushCategory.gPen => StudioBrushCursorShape.gPen,
        StudioBrushCategory.maruPen => StudioBrushCursorShape.maruPen,
        StudioBrushCategory.inkPen => StudioBrushCursorShape.inkPen,
        StudioBrushCategory.fudeBrush => StudioBrushCursorShape.fudeBrush,
        StudioBrushCategory.marker => StudioBrushCursorShape.marker,
        StudioBrushCategory.airbrush => StudioBrushCursorShape.airbrush,
        StudioBrushCategory.pencilRough => StudioBrushCursorShape.pencilRough,
        StudioBrushCategory.oilPastel => StudioBrushCursorShape.oilPastel,
        StudioBrushCategory.watercolor => StudioBrushCursorShape.watercolor,
        StudioBrushCategory.screentoneBrush =>
          StudioBrushCursorShape.screentone,
        StudioBrushCategory.specialPen => StudioBrushCursorShape.specialPen,
        StudioBrushCategory.eraserHard => StudioBrushCursorShape.hardEraser,
        StudioBrushCategory.eraserSoft => StudioBrushCursorShape.softEraser,
        StudioBrushCategory.eraserVector => StudioBrushCursorShape.vectorEraser,
        StudioBrushCategory.smudge => StudioBrushCursorShape.smudge,
        StudioBrushCategory.blurTool => StudioBrushCursorShape.blur,
        StudioBrushCategory.bucketFill => StudioBrushCursorShape.bucketFill,
        StudioBrushCategory.lassoFill => StudioBrushCursorShape.lassoFill,
      };

  static StudioBrushCursorShape shapeForTool(
    StudioBrushCategory brush,
    StudioTool tool,
  ) => switch (tool) {
    StudioTool.eraser => switch (brush) {
      StudioBrushCategory.eraserSoft => StudioBrushCursorShape.softEraser,
      StudioBrushCategory.eraserVector => StudioBrushCursorShape.vectorEraser,
      _ => StudioBrushCursorShape.hardEraser,
    },
    StudioTool.smudge => StudioBrushCursorShape.smudge,
    StudioTool.blur => StudioBrushCursorShape.blur,
    StudioTool.bucketFill => StudioBrushCursorShape.bucketFill,
    StudioTool.lassoFill => StudioBrushCursorShape.lassoFill,
    _ => shapeFor(brush),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final cursorPosition = position;
    if (cursorPosition == null) return;
    paintCursor(
      canvas,
      position: cursorPosition,
      brush: brush,
      tool: tool,
      color: color,
      brushSize: brushSize,
      zoom: zoom,
    );
  }

  static void paintCursor(
    Canvas canvas, {
    required Offset position,
    required StudioBrushCategory brush,
    StudioTool tool = StudioTool.brush,
    required Color color,
    required double brushSize,
    double zoom = 1.0,
  }) {
    final shape = shapeForTool(brush, tool);
    final safeZoom = math.max(0.01, zoom);
    final radius = math.max(5.0, brushSize * safeZoom / 2);
    final cursorColor = switch (shape) {
      StudioBrushCursorShape.hardEraser ||
      StudioBrushCursorShape.softEraser ||
      StudioBrushCursorShape.vectorEraser => const Color(0xFFEF4444),
      _ => color,
    };
    final stroke = Paint()
      ..color = cursorColor.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, 1.5 / safeZoom)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = cursorColor.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    switch (shape) {
      case StudioBrushCursorShape.gPen:
        _polygon(
          canvas,
          position,
          radius,
          const [Offset(0, -1), Offset(-0.62, 0.62), Offset(0.62, 0.62)],
          stroke,
          fill,
        );
        canvas.drawLine(
          position.translate(0, -radius * 0.1),
          position.translate(0, radius * 0.62),
          stroke,
        );
      case StudioBrushCursorShape.maruPen:
        canvas.drawCircle(position, radius, fill);
        canvas.drawCircle(position, radius, stroke);
        canvas.drawCircle(position, math.max(1.5, radius * 0.18), stroke);
      case StudioBrushCursorShape.inkPen:
        _polygon(canvas, position, radius, const [
          Offset(0, -1),
          Offset(0.62, 0),
          Offset(0, 1),
          Offset(-0.62, 0),
        ], stroke);
        canvas.drawLine(
          position.translate(-radius * 0.42, radius * 0.42),
          position.translate(radius * 0.42, -radius * 0.42),
          stroke,
        );
      case StudioBrushCursorShape.fudeBrush:
        _polygon(
          canvas,
          position,
          radius,
          const [
            Offset(0, -1),
            Offset(0.75, -0.35),
            Offset(0.55, 0.72),
            Offset(0, 1),
            Offset(-0.55, 0.72),
            Offset(-0.75, -0.35),
          ],
          stroke,
          fill,
        );
      case StudioBrushCursorShape.marker:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: position,
              width: radius * 2,
              height: radius * 1.35,
            ),
            Radius.circular(radius * 0.18),
          ),
          stroke,
        );
      case StudioBrushCursorShape.airbrush:
        canvas.drawCircle(position, radius, fill);
        canvas.drawCircle(position, radius, stroke);
        for (final offset in const [
          Offset(-0.35, -0.25),
          Offset(0.30, -0.18),
          Offset(0.12, 0.32),
        ]) {
          canvas.drawCircle(
            position + Offset(offset.dx * radius, offset.dy * radius),
            math.max(1.0, radius * 0.10),
            stroke,
          );
        }
      case StudioBrushCursorShape.pencilRough:
        _polygon(
          canvas,
          position,
          radius,
          const [
            Offset(0, -1),
            Offset(0.72, 0.45),
            Offset(0, 1),
            Offset(-0.72, 0.45),
          ],
          stroke,
          fill,
        );
        canvas.drawLine(
          position.translate(-radius * 0.42, radius * 0.45),
          position.translate(radius * 0.42, radius * 0.45),
          stroke,
        );
      case StudioBrushCursorShape.oilPastel:
        canvas.drawOval(
          Rect.fromCenter(
            center: position,
            width: radius * 2,
            height: radius * 1.45,
          ),
          fill,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: position,
            width: radius * 2,
            height: radius * 1.45,
          ),
          stroke,
        );
        canvas.drawLine(
          position.translate(-radius * 0.35, radius * 0.25),
          position.translate(radius * 0.35, -radius * 0.25),
          stroke,
        );
      case StudioBrushCursorShape.watercolor:
        canvas.drawCircle(position, radius, fill);
        canvas.drawCircle(position, radius, stroke);
        canvas.drawCircle(
          position,
          radius * 0.62,
          Paint()
            ..color = cursorColor.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.strokeWidth,
        );
      case StudioBrushCursorShape.screentone:
        canvas.drawRect(
          Rect.fromCenter(
            center: position,
            width: radius * 2,
            height: radius * 2,
          ),
          stroke,
        );
        for (int x = -1; x <= 1; x++) {
          for (int y = -1; y <= 1; y++) {
            canvas.drawCircle(
              position + Offset(x * radius * 0.45, y * radius * 0.45),
              math.max(0.8, radius * 0.08),
              stroke,
            );
          }
        }
      case StudioBrushCursorShape.specialPen:
        _star(canvas, position, radius, stroke);
      case StudioBrushCursorShape.hardEraser:
        canvas.drawRect(
          Rect.fromCenter(
            center: position,
            width: radius * 2,
            height: radius * 1.6,
          ),
          fill,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: position,
            width: radius * 2,
            height: radius * 1.6,
          ),
          stroke,
        );
        canvas.drawLine(
          position.translate(-radius * 0.65, radius * 0.55),
          position.translate(radius * 0.65, -radius * 0.55),
          stroke,
        );
      case StudioBrushCursorShape.softEraser:
        canvas.drawCircle(position, radius, fill);
        canvas.drawCircle(position, radius, stroke);
        canvas.drawCircle(position, radius * 0.55, stroke);
      case StudioBrushCursorShape.vectorEraser:
        _cross(canvas, position, radius, stroke);
      case StudioBrushCursorShape.smudge:
        final path = Path()
          ..moveTo(position.dx - radius, position.dy)
          ..cubicTo(
            position.dx - radius * 0.35,
            position.dy - radius,
            position.dx + radius * 0.35,
            position.dy + radius,
            position.dx + radius,
            position.dy,
          );
        canvas.drawPath(path, stroke);
        canvas.drawCircle(position, radius * 0.16, fill);
      case StudioBrushCursorShape.blur:
        canvas.drawCircle(position, radius, stroke);
        canvas.drawCircle(position, radius * 0.62, stroke);
        canvas.drawCircle(position, radius * 0.25, fill);
      case StudioBrushCursorShape.bucketFill:
        _bucket(canvas, position, radius, stroke, fill);
      case StudioBrushCursorShape.lassoFill:
        final path = Path()
          ..addOval(
            Rect.fromCenter(
              center: position,
              width: radius * 2,
              height: radius * 1.45,
            ),
          )
          ..moveTo(position.dx + radius * 0.65, position.dy + radius * 0.45)
          ..lineTo(position.dx + radius * 1.15, position.dy + radius * 0.90);
        canvas.drawPath(path, stroke);
    }
  }

  static void _polygon(
    Canvas canvas,
    Offset center,
    double radius,
    List<Offset> points,
    Paint stroke, [
    Paint? fill,
  ]) {
    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final point =
          center + Offset(points[i].dx * radius, points[i].dy * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    if (fill != null) canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  static void _cross(
    Canvas canvas,
    Offset center,
    double radius,
    Paint stroke,
  ) {
    canvas.drawLine(
      center.translate(-radius, -radius),
      center.translate(radius, radius),
      stroke,
    );
    canvas.drawLine(
      center.translate(-radius, radius),
      center.translate(radius, -radius),
      stroke,
    );
  }

  static void _star(Canvas canvas, Offset center, double radius, Paint stroke) {
    final points = <Offset>[];
    for (int i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? radius : radius * 0.42;
      points.add(Offset(math.cos(angle) * r, math.sin(angle) * r));
    }
    _polygon(canvas, center, 1, points, stroke);
  }

  static void _bucket(
    Canvas canvas,
    Offset center,
    double radius,
    Paint stroke,
    Paint fill,
  ) {
    _polygon(
      canvas,
      center,
      radius,
      const [
        Offset(-0.72, -0.25),
        Offset(0.72, -0.25),
        Offset(0.50, 0.72),
        Offset(-0.50, 0.72),
      ],
      stroke,
      fill,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: center.translate(0, -radius * 0.18),
        radius: radius * 0.68,
      ),
      math.pi,
      math.pi,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant StudioBrushCursorPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.brush != brush ||
      oldDelegate.tool != tool ||
      oldDelegate.color != color ||
      oldDelegate.brushSize != brushSize ||
      oldDelegate.zoom != zoom;
}
