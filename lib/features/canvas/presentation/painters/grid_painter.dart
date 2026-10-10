import 'dart:math';
import 'package:flutter/material.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_model;
import 'package:varian/features/canvas/domain/canvas_precision.dart';

@immutable
class CanvasRenderTokens {
  final Color canvas;
  final Color canvasGrid;
  final Color panelElevated;
  final Color panelBorder;
  final Color selection;
  final Color handle;
  final Color accent;
  final Color success;
  final Color warning;
  final Color info;
  final Color danger;
  final Color text;
  final Color textMuted;

  const CanvasRenderTokens({
    required this.canvas,
    required this.canvasGrid,
    required this.panelElevated,
    required this.panelBorder,
    required this.selection,
    required this.handle,
    required this.accent,
    required this.success,
    required this.warning,
    required this.info,
    required this.danger,
    required this.text,
    required this.textMuted,
  });

  static const light = CanvasRenderTokens(
    canvas: Color(0xFFF5F5F5),
    canvasGrid: Color(0xFFD4D4D4),
    panelElevated: Color(0xFFFFFFFF),
    panelBorder: Color(0xFFE5E5E5),
    selection: Color(0xFF525252),
    handle: Color(0xFFFFFFFF),
    accent: Color(0xFF171717),
    success: Color(0xFF404040),
    warning: Color(0xFF737373),
    info: Color(0xFF525252),
    danger: Color(0xFF262626),
    text: Color(0xFF171717),
    textMuted: Color(0xFF737373),
  );

  static const dark = CanvasRenderTokens(
    canvas: Color(0xFF0A0A0A),
    canvasGrid: Color(0xFF333333),
    panelElevated: Color(0xFF262626),
    panelBorder: Color(0xFF404040),
    selection: Color(0xFFE5E5E5),
    handle: Color(0xFFFAFAFA),
    accent: Color(0xFFE5E5E5),
    success: Color(0xFFD4D4D4),
    warning: Color(0xFFA1A1A1),
    info: Color(0xFFBDBDBD),
    danger: Color(0xFFF5F5F5),
    text: Color(0xFFFAFAFA),
    textMuted: Color(0xFFA1A1A1),
  );

  @override
  bool operator ==(Object other) =>
      other is CanvasRenderTokens &&
      other.canvas == canvas &&
      other.canvasGrid == canvasGrid &&
      other.panelElevated == panelElevated &&
      other.panelBorder == panelBorder &&
      other.selection == selection &&
      other.handle == handle &&
      other.accent == accent &&
      other.success == success &&
      other.warning == warning &&
      other.info == info &&
      other.danger == danger &&
      other.text == text &&
      other.textMuted == textMuted;

  @override
  int get hashCode => Object.hash(
    canvas,
    canvasGrid,
    panelElevated,
    panelBorder,
    selection,
    handle,
    accent,
    success,
    warning,
    info,
    danger,
    text,
    textMuted,
  );

  static CanvasRenderTokens fromAppTokens(AppTokens tokens) =>
      CanvasRenderTokens(
        canvas: tokens.canvas,
        panelElevated: tokens.panelElevated,
        panelBorder: tokens.panelBorder,
        canvasGrid: tokens.canvasGrid,
        selection: tokens.selection,
        handle: tokens.handle,
        accent: tokens.accent,
        success: tokens.success,
        warning: tokens.warning,
        info: tokens.info,
        danger: tokens.danger,
        text: tokens.text,
        textMuted: tokens.textMuted,
      );

  // AppTheme remains the compatibility source for legacy painter callers.
}

class GridPainter extends CustomPainter {
  final double panX;
  final double panY;
  final double zoom;
  final bool isDark;
  final CanvasRenderTokens? tokens;
  final bool gridVisible;
  final CanvasGridPreset gridPreset;
  final double gridSpacing;
  final int gridSubdivisions;

  const GridPainter({
    required this.panX,
    required this.panY,
    required this.zoom,
    this.isDark = true,
    this.tokens,
    this.gridVisible = true,
    this.gridPreset = CanvasGridPreset.dots,
    this.gridSpacing = 28,
    this.gridSubdivisions = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final palette =
        tokens ?? (isDark ? CanvasRenderTokens.dark : CanvasRenderTokens.light);
    final bgPaint = Paint()..color = palette.canvas;
    canvas.drawRect(Offset.zero & size, bgPaint);

    if (!gridVisible || gridPreset == CanvasGridPreset.none) return;

    final dotPaint = Paint()
      ..color = palette.canvasGrid.withValues(alpha: isDark ? 0.75 : 0.85)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(1.0, 1.4 * zoom);

    final double baseSpacing =
        CanvasPrecisionMath.effectiveGridSpacing(gridPreset, gridSpacing) *
        zoom;
    if (baseSpacing < 7) return;

    final double startX = panX % baseSpacing;
    final double startY = panY % baseSpacing;

    if (gridPreset == CanvasGridPreset.dots) {
      for (double x = startX; x < size.width; x += baseSpacing) {
        for (double y = startY; y < size.height; y += baseSpacing) {
          canvas.drawCircle(
            Offset(x, y),
            max(0.75, 1.1 * min(zoom, 1.4)),
            dotPaint,
          );
        }
      }
    } else if (gridPreset == CanvasGridPreset.isometric) {
      final diagonalPaint = Paint()
        ..color = dotPaint.color.withValues(alpha: dotPaint.color.a * 0.65)
        ..strokeWidth = max(0.5, zoom);
      for (
        double x = -size.height;
        x < size.width + size.height;
        x += baseSpacing
      ) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x + size.height, size.height),
          diagonalPaint,
        );
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x + size.height, 0),
          diagonalPaint,
        );
      }
    } else {
      final subdivisions = gridPreset == CanvasGridPreset.majorMinor
          ? gridSubdivisions.clamp(1, 16)
          : 1;
      final minorPaint = Paint()
        ..color = dotPaint.color.withValues(alpha: dotPaint.color.a * 0.45)
        ..strokeWidth = max(0.5, zoom * 0.7);
      for (var lineIndex = 0; ; lineIndex++) {
        final x = startX + lineIndex * baseSpacing;
        if (x >= size.width) break;
        final paint = lineIndex % subdivisions == 0 ? dotPaint : minorPaint;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (var lineIndex = 0; ; lineIndex++) {
        final y = startY + lineIndex * baseSpacing;
        if (y >= size.height) break;
        final paint = lineIndex % subdivisions == 0 ? dotPaint : minorPaint;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.panX != panX ||
        oldDelegate.panY != panY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.isDark != isDark ||
        oldDelegate.tokens != tokens ||
        oldDelegate.gridVisible != gridVisible ||
        oldDelegate.gridPreset != gridPreset ||
        oldDelegate.gridSpacing != gridSpacing ||
        oldDelegate.gridSubdivisions != gridSubdivisions;
  }
}

class CanvasGuidesPainter extends CustomPainter {
  final List<CanvasGuide> guides;
  final canvas_model.Viewport viewport;
  final bool visible;
  final Color color;

  const CanvasGuidesPainter({
    required this.guides,
    required this.viewport,
    this.visible = true,
    this.color = const Color(0xFFEF4444),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final guidePaint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
      color: color,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    for (final guide in guides) {
      final screenPosition =
          guide.position * viewport.zoom +
          (guide.axis == CanvasGuideAxis.vertical ? viewport.x : viewport.y);
      if (guide.axis == CanvasGuideAxis.vertical) {
        if (screenPosition < 0 || screenPosition > size.width) continue;
        canvas.drawLine(
          Offset(screenPosition, 0),
          Offset(screenPosition, size.height),
          guidePaint,
        );
        _paintLabel(canvas, guide, Offset(screenPosition + 4, 28), labelStyle);
      } else {
        if (screenPosition < 0 || screenPosition > size.height) continue;
        canvas.drawLine(
          Offset(0, screenPosition),
          Offset(size.width, screenPosition),
          guidePaint,
        );
        _paintLabel(canvas, guide, Offset(28, screenPosition + 4), labelStyle);
      }
    }
  }

  void _paintLabel(
    Canvas canvas,
    CanvasGuide guide,
    Offset offset,
    TextStyle style,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: guide.label ?? guide.position.toStringAsFixed(0),
        style: style,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CanvasGuidesPainter oldDelegate) {
    return oldDelegate.guides != guides ||
        oldDelegate.viewport != viewport ||
        oldDelegate.visible != visible ||
        oldDelegate.color != color;
  }
}

class CanvasRulersPainter extends CustomPainter {
  final canvas_model.Viewport viewport;
  final bool visible;
  final Color backgroundColor;
  final Color foregroundColor;
  final double rulerSize;

  const CanvasRulersPainter({
    required this.viewport,
    this.visible = false,
    this.backgroundColor = const Color(0xCC171717),
    this.foregroundColor = const Color(0xFFBDBDBD),
    this.rulerSize = 24,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final backgroundPaint = Paint()..color = backgroundColor;
    final tickPaint = Paint()
      ..color = foregroundColor.withValues(alpha: 0.72)
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, rulerSize),
      backgroundPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, rulerSize, size.height),
      backgroundPaint,
    );

    final horizontalStart = -viewport.x / viewport.zoom;
    final horizontalEnd = (size.width - viewport.x) / viewport.zoom;
    final verticalStart = -viewport.y / viewport.zoom;
    final verticalEnd = (size.height - viewport.y) / viewport.zoom;
    final horizontalTicks = CanvasPrecisionMath.rulerTicks(
      start: horizontalStart,
      end: horizontalEnd,
      zoom: viewport.zoom,
    );
    final verticalTicks = CanvasPrecisionMath.rulerTicks(
      start: verticalStart,
      end: verticalEnd,
      zoom: viewport.zoom,
    );
    final labelStyle = TextStyle(color: foregroundColor, fontSize: 9);
    for (final tick in horizontalTicks) {
      final x = tick.worldPosition * viewport.zoom + viewport.x;
      if (x < rulerSize || x > size.width) continue;
      final tickHeight = tick.major ? 11 : 6;
      canvas.drawLine(
        Offset(x, rulerSize),
        Offset(x, rulerSize - tickHeight),
        tickPaint,
      );
      if (tick.major) {
        _paintLabel(canvas, tick.label, Offset(x + 2, 2), labelStyle);
      }
    }
    for (final tick in verticalTicks) {
      final y = tick.worldPosition * viewport.zoom + viewport.y;
      if (y < rulerSize || y > size.height) continue;
      final tickWidth = tick.major ? 11 : 6;
      canvas.drawLine(
        Offset(rulerSize, y),
        Offset(rulerSize - tickWidth, y),
        tickPaint,
      );
      if (tick.major) {
        _paintLabel(canvas, tick.label, Offset(2, y + 2), labelStyle);
      }
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, rulerSize, rulerSize), backgroundPaint);
  }

  void _paintLabel(Canvas canvas, String text, Offset offset, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CanvasRulersPainter oldDelegate) {
    return oldDelegate.viewport != viewport ||
        oldDelegate.visible != visible ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.foregroundColor != foregroundColor ||
        oldDelegate.rulerSize != rulerSize;
  }
}
