import 'dart:ui';

class BrushPathSmoother {
  /// Builds a smooth Path from points using quadratic Bézier curves with midpoint interpolation.
  static Path buildSmoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    if (points.length == 1) {
      path.moveTo(points.first.dx, points.first.dy);
      path.lineTo(points.first.dx + 0.1, points.first.dy + 0.1);
      return path;
    }

    if (points.length == 2) {
      path.moveTo(points[0].dx, points[0].dy);
      path.lineTo(points[1].dx, points[1].dy);
      return path;
    }

    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 1; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final midX = (p0.dx + p1.dx) / 2.0;
      final midY = (p0.dy + p1.dy) / 2.0;
      path.quadraticBezierTo(p0.dx, p0.dy, midX, midY);
    }

    // Connect to final point
    final last = points.last;
    path.lineTo(last.dx, last.dy);

    return path;
  }

  /// Builds standard linear polyline path (without curve interpolation).
  static Path buildLinearPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    return path;
  }
}
