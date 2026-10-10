import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';

import '../models/selection_mask.dart';

class RasterSurface {
  final int width;
  final int height;
  final Uint8List pixels;

  RasterSurface({required this.width, required this.height, Uint8List? pixels})
    : pixels = pixels ?? Uint8List(width * height * 4) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Raster surface dimensions must be positive.');
    }
    if (this.pixels.length != width * height * 4) {
      throw ArgumentError('Raster pixel buffer has an invalid size.');
    }
  }

  factory RasterSurface.solid(int width, int height, Color color) {
    final surface = RasterSurface(width: width, height: height);
    surface.fill(color);
    return surface;
  }

  RasterSurface clone() => RasterSurface(
    width: width,
    height: height,
    pixels: Uint8List.fromList(pixels),
  );

  bool contains(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  Color colorAt(int x, int y) {
    if (!contains(x, y)) return Colors.transparent;
    final index = _index(x, y);
    return Color.fromARGB(
      pixels[index + 3],
      pixels[index],
      pixels[index + 1],
      pixels[index + 2],
    );
  }

  Color sample(Offset point) => colorAt(
    point.dx.round().clamp(0, width - 1),
    point.dy.round().clamp(0, height - 1),
  );

  void setColor(int x, int y, Color color) {
    if (!contains(x, y)) return;
    final index = _index(x, y);
    final argb = color.toARGB32();
    pixels[index] = (argb >> 16) & 0xff;
    pixels[index + 1] = (argb >> 8) & 0xff;
    pixels[index + 2] = argb & 0xff;
    pixels[index + 3] = (argb >> 24) & 0xff;
  }

  void blendColor(int x, int y, Color color, {double opacity = 1.0}) {
    if (!contains(x, y) || opacity <= 0) return;
    final index = _index(x, y);
    final sourceAlpha = _alpha(color) * opacity.clamp(0.0, 1.0);
    final destinationAlpha = pixels[index + 3] / 255.0;
    final outputAlpha = sourceAlpha + destinationAlpha * (1 - sourceAlpha);
    if (outputAlpha <= 0) {
      pixels[index] = 0;
      pixels[index + 1] = 0;
      pixels[index + 2] = 0;
      pixels[index + 3] = 0;
      return;
    }

    pixels[index] = _compositeChannel(
      _red(color),
      pixels[index],
      sourceAlpha,
      destinationAlpha,
      outputAlpha,
    );
    pixels[index + 1] = _compositeChannel(
      _green(color),
      pixels[index + 1],
      sourceAlpha,
      destinationAlpha,
      outputAlpha,
    );
    pixels[index + 2] = _compositeChannel(
      _blue(color),
      pixels[index + 2],
      sourceAlpha,
      destinationAlpha,
      outputAlpha,
    );
    pixels[index + 3] = (outputAlpha * 255).round().clamp(0, 255);
  }

  void clearCircle(Offset center, double radius, {SelectionMask? selection}) {
    final bounds = _circleBounds(center, radius);
    for (int y = bounds.top.floor(); y <= bounds.bottom.ceil(); y++) {
      for (int x = bounds.left.floor(); x <= bounds.right.ceil(); x++) {
        final point = Offset(x + 0.5, y + 0.5);
        if ((point - center).distance <= radius && _allows(point, selection)) {
          setColor(x, y, Colors.transparent);
        }
      }
    }
  }

  void fill(Color color) {
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        setColor(x, y, color);
      }
    }
  }

  int _index(int x, int y) => (y * width + x) * 4;

  Rect _circleBounds(Offset center, double radius) => Rect.fromLTRB(
    math.max(0.0, (center.dx - radius).floor().toDouble()),
    math.max(0.0, (center.dy - radius).floor().toDouble()),
    math.min((width - 1).toDouble(), (center.dx + radius).ceil().toDouble()),
    math.min((height - 1).toDouble(), (center.dy + radius).ceil().toDouble()),
  );

  bool _allows(Offset point, SelectionMask? selection) {
    if (selection == null || selection.isEmpty) return true;
    final box = selection.boundingBox;
    if (box != null && !box.contains(point)) return selection.inverted;

    bool inside;
    if (selection.toolType == SelectionToolType.ellipse && box != null) {
      final normalizedX = (point.dx - box.center.dx) / (box.width / 2);
      final normalizedY = (point.dy - box.center.dy) / (box.height / 2);
      inside = normalizedX * normalizedX + normalizedY * normalizedY <= 1;
    } else if (selection.outlinePoints.length >= 3) {
      inside = _pointInPolygon(point, selection.outlinePoints);
    } else {
      inside = box?.contains(point) ?? false;
    }
    return selection.inverted ? !inside : inside;
  }

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects =
          ((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  static int _red(Color color) => (color.toARGB32() >> 16) & 0xff;
  static int _green(Color color) => (color.toARGB32() >> 8) & 0xff;
  static int _blue(Color color) => color.toARGB32() & 0xff;
  static double _alpha(Color color) =>
      ((color.toARGB32() >> 24) & 0xff) / 255.0;

  static int _compositeChannel(
    int source,
    int destination,
    double sourceAlpha,
    double destinationAlpha,
    double outputAlpha,
  ) {
    return ((source * sourceAlpha +
                destination * destinationAlpha * (1 - sourceAlpha)) /
            outputAlpha)
        .round()
        .clamp(0, 255);
  }
}

class RasterCanvasEngine {
  final RasterSurface surface;

  RasterCanvasEngine(this.surface);

  Color sampleColor(Offset point) => surface.sample(point);

  int drawStroke({
    required List<Offset> points,
    required Color color,
    required double size,
    double opacity = 1.0,
    bool eraser = false,
    bool soft = false,
    StudioBrushCategory? brush,
    List<double>? pressures,
    SelectionMask? selection,
  }) {
    if (points.isEmpty || size <= 0) return 0;
    final selectedBrush = brush ?? StudioBrushCategory.gPen;
    final radiusScale = switch (selectedBrush) {
      StudioBrushCategory.maruPen => 0.65,
      StudioBrushCategory.fudeBrush => 1.45,
      StudioBrushCategory.marker => 1.2,
      StudioBrushCategory.airbrush => 1.9,
      StudioBrushCategory.pencilRough => 0.82,
      StudioBrushCategory.oilPastel => 1.25,
      StudioBrushCategory.watercolor => 1.8,
      StudioBrushCategory.eraserSoft => 1.35,
      _ => 1.0,
    };
    final opacityScale = switch (selectedBrush) {
      StudioBrushCategory.marker => 0.82,
      StudioBrushCategory.oilPastel => 0.72,
      StudioBrushCategory.watercolor => 0.28,
      StudioBrushCategory.pencilRough => 0.78,
      StudioBrushCategory.screentoneBrush => 0.85,
      _ => 1.0,
    };
    final baseRadius = size * radiusScale / 2;
    final useSoftFalloff =
        soft ||
        selectedBrush == StudioBrushCategory.airbrush ||
        selectedBrush == StudioBrushCategory.watercolor ||
        selectedBrush == StudioBrushCategory.eraserSoft;
    var changed = 0;
    for (int i = 0; i < points.length; i++) {
      final start = i == 0 ? points[i] : points[i - 1];
      final end = points[i];
      final distance = (end - start).distance;
      final steps = math.max(
        1,
        (distance / math.max(1.0, baseRadius * 0.5)).ceil(),
      );
      final pressure = pressures != null && i < pressures.length
          ? pressures[i].clamp(0.0, 1.0).toDouble()
          : 1.0;
      final pressureScale = 0.45 + pressure * 0.55;
      final radius = baseRadius * pressureScale;
      for (int step = 0; step <= steps; step++) {
        final t = step / steps;
        final center = Offset(
          start.dx + (end.dx - start.dx) * t,
          start.dy + (end.dy - start.dy) * t,
        );
        final bounds = _circleBounds(center, radius);
        for (int y = bounds.top.floor(); y <= bounds.bottom.ceil(); y++) {
          for (int x = bounds.left.floor(); x <= bounds.right.ceil(); x++) {
            if (!_allows(x, y, selection)) continue;
            if (selectedBrush == StudioBrushCategory.screentoneBrush &&
                (x + y + step) % 4 != 0) {
              continue;
            }
            if (selectedBrush == StudioBrushCategory.pencilRough &&
                (x * 31 + y * 17 + step * 13) % 11 < 2) {
              continue;
            }
            final point = Offset(x + 0.5, y + 0.5);
            final distanceFromCenter = (point - center).distance;
            if (distanceFromCenter > radius) continue;
            if (eraser) {
              surface.setColor(x, y, Colors.transparent);
            } else {
              final falloff = useSoftFalloff
                  ? (1 - distanceFromCenter / math.max(1.0, radius))
                  : 1.0;
              surface.blendColor(
                x,
                y,
                color,
                opacity: opacity.clamp(0.0, 1.0) * opacityScale * falloff,
              );
            }
            changed++;
          }
        }
      }
    }
    return changed;
  }

  int bucketFill({
    required Offset seedPoint,
    required Color color,
    double tolerance = 24.0,
    SelectionMask? selection,
  }) {
    final seedX = seedPoint.dx.round();
    final seedY = seedPoint.dy.round();
    if (!surface.contains(seedX, seedY)) return 0;
    if (!_allows(seedX, seedY, selection)) return 0;

    final target = surface.colorAt(seedX, seedY);
    if (_matches(target, color, tolerance)) return 0;

    final visited = Uint8List(surface.width * surface.height);
    final queue = <int>[seedY * surface.width + seedX];
    visited[seedY * surface.width + seedX] = 1;
    var head = 0;
    var changed = 0;

    while (head < queue.length) {
      final packed = queue[head++];
      final x = packed % surface.width;
      final y = packed ~/ surface.width;
      if (!_allows(x, y, selection)) continue;
      if (!_matches(surface.colorAt(x, y), target, tolerance)) continue;

      surface.setColor(x, y, color);
      changed++;
      _enqueue(queue, visited, x - 1, y);
      _enqueue(queue, visited, x + 1, y);
      _enqueue(queue, visited, x, y - 1);
      _enqueue(queue, visited, x, y + 1);
    }
    return changed;
  }

  int smudge({
    required List<Offset> points,
    required double radius,
    double strength = 0.65,
    SelectionMask? selection,
  }) {
    if (points.isEmpty || radius <= 0) return 0;
    final source = surface.clone();
    var changed = 0;
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final previous = i == 0 ? point : points[i - 1];
      final drag = point - previous;
      final samplePoint = point - drag * 1.5;
      changed += _dabFromSource(
        source,
        samplePoint,
        point,
        radius,
        strength,
        selection,
      );
    }
    return changed;
  }

  int blur({
    required List<Offset> points,
    required double radius,
    double strength = 0.65,
    SelectionMask? selection,
  }) {
    if (points.isEmpty || radius <= 0) return 0;
    final source = surface.clone();
    var changed = 0;
    final seen = <int>{};
    for (final point in points) {
      final bounds = _circleBounds(point, radius);
      for (int y = bounds.top.floor(); y <= bounds.bottom.ceil(); y++) {
        for (int x = bounds.left.floor(); x <= bounds.right.ceil(); x++) {
          final index = y * surface.width + x;
          if (seen.contains(index) || !_allows(x, y, selection)) continue;
          final pixelCenter = Offset(x + 0.5, y + 0.5);
          if ((pixelCenter - point).distance > radius) continue;
          seen.add(index);
          final average = _average(source, x, y, radius.ceil());
          surface.setColor(
            x,
            y,
            _mix(source.colorAt(x, y), average, strength.clamp(0.0, 1.0)),
          );
          changed++;
        }
      }
    }
    return changed;
  }

  int transform({
    required Rect bounds,
    Offset translation = Offset.zero,
    double scale = 1.0,
    double rotation = 0.0,
    bool flipH = false,
    bool flipV = false,
    SelectionMask? selection,
  }) {
    if (bounds.isEmpty || scale == 0) return 0;
    final source = surface.clone();
    final center = bounds.center;
    final cosA = math.cos(-rotation);
    final sinA = math.sin(-rotation);
    var changed = 0;
    final targetRect = bounds.shift(translation);
    final sourceLeft = bounds.left.floor().clamp(0, surface.width - 1);
    final sourceTop = bounds.top.floor().clamp(0, surface.height - 1);
    final sourceRight = bounds.right.ceil().clamp(0, surface.width - 1);
    final sourceBottom = bounds.bottom.ceil().clamp(0, surface.height - 1);

    // Clear the selected source before writing the translated copy. The
    // painter's paper background remains visible through transparent pixels.
    for (int y = sourceTop; y <= sourceBottom; y++) {
      for (int x = sourceLeft; x <= sourceRight; x++) {
        if (_allows(x, y, selection)) {
          surface.setColor(x, y, Colors.transparent);
        }
      }
    }

    final left = targetRect.left.floor().clamp(0, surface.width - 1);
    final top = targetRect.top.floor().clamp(0, surface.height - 1);
    final right = targetRect.right.ceil().clamp(0, surface.width - 1);
    final bottom = targetRect.bottom.ceil().clamp(0, surface.height - 1);

    for (int y = top; y <= bottom; y++) {
      for (int x = left; x <= right; x++) {
        final targetPoint = Offset(x + 0.5, y + 0.5);
        var local = targetPoint - center - translation;
        local = Offset(
          local.dx * cosA - local.dy * sinA,
          local.dx * sinA + local.dy * cosA,
        );
        local = local / scale + center;
        if (flipH) local = Offset(2 * center.dx - local.dx, local.dy);
        if (flipV) local = Offset(local.dx, 2 * center.dy - local.dy);
        if (!bounds.contains(local)) continue;
        if (!_allows(local.dx.floor(), local.dy.floor(), selection)) {
          continue;
        }
        surface.setColor(
          x,
          y,
          source.colorAt(local.dx.floor(), local.dy.floor()),
        );
        changed++;
      }
    }
    return changed;
  }

  int _dabFromSource(
    RasterSurface source,
    Offset sourceCenter,
    Offset targetCenter,
    double radius,
    double strength,
    SelectionMask? selection,
  ) {
    final bounds = _circleBounds(targetCenter, radius);
    final maxDistance = math.max(1.0, radius);
    var changed = 0;
    for (int y = bounds.top.floor(); y <= bounds.bottom.ceil(); y++) {
      for (int x = bounds.left.floor(); x <= bounds.right.ceil(); x++) {
        if (!_allows(x, y, selection)) continue;
        final point = Offset(x + 0.5, y + 0.5);
        final distance = (point - targetCenter).distance;
        if (distance > radius) continue;
        final falloff = 1 - distance / maxDistance;
        final sourceOffset = point - targetCenter;
        final sampled = source.sample(sourceCenter + sourceOffset);
        surface.blendColor(
          x,
          y,
          sampled,
          opacity: strength.clamp(0.0, 1.0) * falloff,
        );
        changed++;
      }
    }
    return changed;
  }

  Color _average(RasterSurface source, int x, int y, int radius) {
    var red = 0;
    var green = 0;
    var blue = 0;
    var alpha = 0.0;
    var count = 0;
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final sample = source.colorAt(x + dx, y + dy);
        red += _red(sample);
        green += _green(sample);
        blue += _blue(sample);
        alpha += _alpha(sample);
        count++;
      }
    }
    return Color.fromARGB(
      (alpha / count).round(),
      (red / count).round(),
      (green / count).round(),
      (blue / count).round(),
    );
  }

  bool _allows(int x, int y, SelectionMask? selection) {
    if (selection == null || selection.isEmpty) return true;
    final point = Offset(x + 0.5, y + 0.5);
    final box = selection.boundingBox;
    if (box != null && !box.contains(point)) return selection.inverted;
    if (selection.toolType == SelectionToolType.ellipse && box != null) {
      final nx = (point.dx - box.center.dx) / (box.width / 2);
      final ny = (point.dy - box.center.dy) / (box.height / 2);
      final inside = nx * nx + ny * ny <= 1;
      return selection.inverted ? !inside : inside;
    }
    if (selection.outlinePoints.length < 3) {
      final inside = box?.contains(point) ?? false;
      return selection.inverted ? !inside : inside;
    }
    final inside = _pointInPolygon(point, selection.outlinePoints);
    return selection.inverted ? !inside : inside;
  }

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects =
          ((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  Rect _circleBounds(Offset center, double radius) => Rect.fromLTRB(
    math.max(0.0, (center.dx - radius).floor().toDouble()),
    math.max(0.0, (center.dy - radius).floor().toDouble()),
    math.min(
      (surface.width - 1).toDouble(),
      (center.dx + radius).ceil().toDouble(),
    ),
    math.min(
      (surface.height - 1).toDouble(),
      (center.dy + radius).ceil().toDouble(),
    ),
  );

  void _enqueue(List<int> queue, Uint8List visited, int x, int y) {
    if (!surface.contains(x, y)) return;
    final packed = y * surface.width + x;
    if (visited[packed] == 1) return;
    visited[packed] = 1;
    queue.add(packed);
  }

  bool _matches(Color a, Color b, double tolerance) {
    final delta =
        (_red(a) - _red(b)).abs() +
        (_green(a) - _green(b)).abs() +
        (_blue(a) - _blue(b)).abs() +
        (_alpha(a) - _alpha(b)).abs();
    return delta <= tolerance.clamp(0.0, 1020.0);
  }

  Color _mix(Color a, Color b, double amount) => Color.fromARGB(
    (_alpha(a) * 255 + (_alpha(b) - _alpha(a)) * amount).round().clamp(0, 255),
    (_red(a) + (_red(b) - _red(a)) * amount).round().clamp(0, 255),
    (_green(a) + (_green(b) - _green(a)) * amount).round().clamp(0, 255),
    (_blue(a) + (_blue(b) - _blue(a)) * amount).round().clamp(0, 255),
  );

  static int _red(Color color) => (color.toARGB32() >> 16) & 0xff;
  static int _green(Color color) => (color.toARGB32() >> 8) & 0xff;
  static int _blue(Color color) => color.toARGB32() & 0xff;
  static double _alpha(Color color) =>
      ((color.toARGB32() >> 24) & 0xff) / 255.0;
}
