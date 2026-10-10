import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/ruler_guide.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';
import 'package:varian/features/drawing_paper/domain/services/studio_item_selection_service.dart';
import 'package:varian/features/drawing_paper/domain/models/selection_mask.dart';

import 'studio_item_selection_painter.dart';

class StudioCanvasPainter extends CustomPainter {
  final DrawingPaperPayload payload;
  final ui.Image? rasterImage;
  final double rasterImageScale;
  final List<DrawingStrokePoint> activePoints;
  final StudioBrushCategory activeBrush;
  final Color activeColor;
  final double activeSize;
  final double activeOpacity;
  final bool isEraser;
  final SelectionMask? selection;
  final List<FocusStudioItemEntry> selectedItems;
  final Rect? itemMarquee;
  final List<RulerGuide> rulers;
  final MangaStructure? mangaStructure;
  final double zoom;
  final double rotation;
  final Offset pan;
  final Size canvasPixelSize;
  final int activeLayerIndex;
  final bool applyTransform;
  final bool paintPaperChrome;

  const StudioCanvasPainter({
    required this.payload,
    this.rasterImage,
    this.rasterImageScale = 1.0,
    this.activePoints = const [],
    this.activeBrush = StudioBrushCategory.gPen,
    this.activeColor = Colors.black,
    this.activeSize = 6.0,
    this.activeOpacity = 1.0,
    this.isEraser = false,
    this.selection,
    this.selectedItems = const [],
    this.itemMarquee,
    this.rulers = const [],
    this.mangaStructure,
    this.zoom = 1.0,
    this.rotation = 0.0,
    this.pan = Offset.zero,
    required this.canvasPixelSize,
    this.activeLayerIndex = 0,
    this.applyTransform = true,
    this.paintPaperChrome = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Center transform
    canvas.save();
    if (applyTransform) {
      canvas.translate(size.width / 2 + pan.dx, size.height / 2 + pan.dy);
      if (rotation != 0) canvas.rotate(rotation);
      canvas.scale(zoom, zoom);
      canvas.translate(-canvasPixelSize.width / 2, -canvasPixelSize.height / 2);
    }

    final paperRect = Rect.fromLTWH(
      0,
      0,
      canvasPixelSize.width,
      canvasPixelSize.height,
    );

    // 2. Paper background. Workspace mode draws one shared chrome around all
    // tiles, while each tile still paints its own background color.
    if (paintPaperChrome) {
      final shadowPath = Path()..addRect(paperRect);
      canvas.drawShadow(shadowPath, Colors.black, 16.0, true);
    }
    canvas.drawRect(paperRect, Paint()..color = payload.paperColor);

    // 3. Paper Texture Simulation
    _paintPaperTexture(canvas, paperRect);

    // 4. Manga Bleed Guides
    if (payload.showMangaBleed ||
        payload.presetName.toLowerCase().contains('manga')) {
      _paintMangaBleedGuidelines(canvas, paperRect);
    }

    // 5. Render Layers
    canvas.save();
    canvas.clipRect(paperRect);

    final canRenderStrokesAsVector = payload.rasterOperations.isEmpty;
    if (rasterImage != null && !canRenderStrokesAsVector) {
      final sourceRect = Rect.fromLTWH(
        0,
        0,
        canvasPixelSize.width * rasterImageScale,
        canvasPixelSize.height * rasterImageScale,
      );
      canvas.drawImageRect(
        rasterImage!,
        sourceRect,
        paperRect,
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    if (canRenderStrokesAsVector || rasterImage == null) {
      // Regular strokes stay as paths so thin pen lines are not limited by a
      // downsampled bitmap. Raster operations still use the decoded surface,
      // with this path as a temporary fallback while it is being decoded.
      for (int i = payload.layers.length - 1; i >= 0; i--) {
        final layer = payload.layers[i];
        if (!FocusStudioItemCatalog.isLayerVisible(payload, layer) ||
            layer.type == LayerType.folder) {
          continue;
        }
        _paintLegacyStrokes(canvas, layer);
      }
    }
    DrawingPaperRenderer.paintOverlays(canvas, payload);

    final activeLayer = payload.layers.isEmpty
        ? null
        : payload.layers[activeLayerIndex.clamp(0, payload.layers.length - 1)];
    if (activeLayer != null &&
        activeLayer.visible &&
        activePoints.length >= 2) {
      final liveStroke = DrawingStroke(
        id: 'live_stroke',
        brush: activeBrush,
        color: activeColor,
        size: activeSize,
        opacity: activeOpacity,
        points: activePoints,
        isEraser: isEraser,
      );
      _paintStroke(canvas, liveStroke, activeLayer.opacity);
    }

    // 6. Grid & Pixel Grid Overlays
    if (payload.showGrid) {
      _paintGridOverlay(canvas, paperRect);
    }

    if (payload.showPixelGrid || zoom >= 6.0) {
      _paintPixelGridOverlay(canvas, paperRect);
    }

    // Manga structures are rendered by DrawingPaperRenderer above. Keep the
    // legacy fallback for callers that provide a structure outside payload.
    if (mangaStructure != null && payload.mangaStructure == null) {
      _paintMangaPanelsAndBalloons(canvas, mangaStructure!);
    }

    canvas.restore(); // end clip

    // 7. Rulers Overlay
    _paintRulers(canvas, paperRect);

    // 8. Selection Mask / Marching Ants
    if (selection != null && selection!.isNotEmpty) {
      _paintSelectionOverlay(canvas, selection!, paperRect);
    }
    StudioItemSelectionPainter.paint(canvas, items: selectedItems, zoom: zoom);
    if (itemMarquee != null) {
      StudioItemSelectionPainter.paintMarquee(canvas, itemMarquee!, zoom);
    }

    // 9. Paper Outer Border
    if (paintPaperChrome) {
      canvas.drawRect(
        paperRect,
        Paint()
          ..color = const Color(0xFF64748B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / zoom,
      );
    }

    canvas.restore();
  }

  void _paintLegacyStrokes(Canvas canvas, DrawingLayer layer) {
    for (final stroke in layer.strokes) {
      _paintStroke(canvas, stroke, layer.opacity.clamp(0.0, 1.0).toDouble());
    }
  }

  void _paintStroke(Canvas canvas, DrawingStroke stroke, double layerOpacity) {
    if (stroke.points.length < 2) return;

    final effectiveColor = stroke.isEraser
        ? payload.paperColor
        : stroke.color.withValues(alpha: stroke.opacity * layerOpacity);

    if (stroke.brush == StudioBrushCategory.bucketFill ||
        stroke.brush == StudioBrushCategory.lassoFill) {
      final fillPath = Path();
      fillPath.moveTo(stroke.points.first.x, stroke.points.first.y);
      for (int i = 1; i < stroke.points.length; i++) {
        fillPath.lineTo(stroke.points[i].x, stroke.points[i].y);
      }
      fillPath.close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..color = effectiveColor
          ..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path();
    path.moveTo(stroke.points.first.x, stroke.points.first.y);

    for (int i = 0; i < stroke.points.length - 1; i++) {
      final p0 = stroke.points[i];
      final p1 = stroke.points[i + 1];
      final midX = (p0.x + p1.x) / 2;
      final midY = (p0.y + p1.y) / 2;
      path.quadraticBezierTo(p0.x, p0.y, midX, midY);
    }
    path.lineTo(stroke.points.last.x, stroke.points.last.y);

    final widthScale = switch (stroke.brush) {
      StudioBrushCategory.maruPen => 0.65,
      StudioBrushCategory.fudeBrush => 1.35,
      StudioBrushCategory.marker => 1.2,
      StudioBrushCategory.pencilRough => 0.85,
      StudioBrushCategory.oilPastel => 1.25,
      StudioBrushCategory.watercolor => 1.6,
      _ => 1.0,
    };
    final opacityScale = switch (stroke.brush) {
      StudioBrushCategory.marker => 0.82,
      StudioBrushCategory.pencilRough => 0.78,
      StudioBrushCategory.oilPastel => 0.72,
      StudioBrushCategory.watercolor => 0.28,
      _ => 1.0,
    };
    final brushColor = effectiveColor.withValues(
      alpha: effectiveColor.a * opacityScale,
    );
    final paint = Paint()
      ..color = brushColor
      ..strokeWidth = max(1.0, stroke.size * widthScale)
      ..strokeCap = stroke.brush == StudioBrushCategory.marker
          ? StrokeCap.square
          : StrokeCap.round
      ..strokeJoin = stroke.brush == StudioBrushCategory.marker
          ? StrokeJoin.bevel
          : StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.blendMode;

    if (stroke.brush == StudioBrushCategory.airbrush ||
        stroke.brush == StudioBrushCategory.watercolor ||
        stroke.brush == StudioBrushCategory.blurTool) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, stroke.size * 0.4);
    } else if (stroke.brush == StudioBrushCategory.smudge ||
        stroke.brush == StudioBrushCategory.oilPastel) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.solid, stroke.size * 0.2);
    }

    final toneType =
        stroke.toneType == ScreenToneType.none &&
            stroke.brush == StudioBrushCategory.screentoneBrush
        ? ScreenToneType.dot
        : stroke.toneType;
    if (toneType != ScreenToneType.none) {
      _paintScreenToneArea(
        canvas,
        path,
        toneType,
        stroke.toneFrequency,
        stroke.toneAngle,
        brushColor,
      );
    } else {
      canvas.drawPath(path, paint);
    }
  }

  void _paintScreenToneArea(
    Canvas canvas,
    Path path,
    ScreenToneType toneType,
    double freq,
    double angle,
    Color toneColor,
  ) {
    canvas.save();
    canvas.clipPath(path);

    final tonePaint = Paint()
      ..color = toneColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final bounds = path.getBounds();
    final step = (100.0 / freq).clamp(4.0, 40.0);

    for (double x = bounds.left; x < bounds.right; x += step) {
      for (double y = bounds.top; y < bounds.bottom; y += step) {
        if (toneType == ScreenToneType.dot) {
          canvas.drawCircle(Offset(x, y), step * 0.25, tonePaint);
        } else if (toneType == ScreenToneType.line) {
          canvas.drawLine(
            Offset(x, y),
            Offset(x + step * 0.8, y + step * 0.8),
            tonePaint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        } else if (toneType == ScreenToneType.cross) {
          canvas.drawLine(
            Offset(x - 2, y - 2),
            Offset(x + 2, y + 2),
            tonePaint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
          canvas.drawLine(
            Offset(x + 2, y - 2),
            Offset(x - 2, y + 2),
            tonePaint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
      }
    }
    canvas.restore();
  }

  void _paintGridOverlay(Canvas canvas, Rect paperRect) {
    final gridPaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / zoom;

    const step = 50.0;
    for (double x = paperRect.left; x <= paperRect.right; x += step) {
      canvas.drawLine(
        Offset(x, paperRect.top),
        Offset(x, paperRect.bottom),
        gridPaint,
      );
    }
    for (double y = paperRect.top; y <= paperRect.bottom; y += step) {
      canvas.drawLine(
        Offset(paperRect.left, y),
        Offset(paperRect.right, y),
        gridPaint,
      );
    }
  }

  void _paintPixelGridOverlay(Canvas canvas, Rect paperRect) {
    final pxPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 / zoom;

    const step = 10.0;
    for (double x = paperRect.left; x <= paperRect.right; x += step * 4) {
      canvas.drawLine(
        Offset(x, paperRect.top),
        Offset(x, paperRect.bottom),
        pxPaint,
      );
    }
    for (double y = paperRect.top; y <= paperRect.bottom; y += step * 4) {
      canvas.drawLine(
        Offset(paperRect.left, y),
        Offset(paperRect.right, y),
        pxPaint,
      );
    }
  }

  void _paintPaperTexture(Canvas canvas, Rect paperRect) {
    if (payload.paperTexture == PaperTextureType.none) return;

    final texturePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Fast noise hatch pattern
    const step = 8.0;
    for (double x = paperRect.left; x < paperRect.right; x += step) {
      canvas.drawLine(
        Offset(x, paperRect.top),
        Offset(x + step * 2, paperRect.bottom),
        texturePaint,
      );
    }
  }

  void _paintMangaBleedGuidelines(Canvas canvas, Rect paperRect) {
    final margin = paperRect.width * 0.06;
    final liveRect = Rect.fromLTWH(
      paperRect.left + margin,
      paperRect.top + margin,
      paperRect.width - margin * 2,
      paperRect.height - margin * 2,
    );

    final guidePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / zoom;

    canvas.drawRect(liveRect, guidePaint);

    // Center crop tick marks
    final midX = paperRect.center.dx;
    final midY = paperRect.center.dy;
    canvas.drawLine(
      Offset(midX, paperRect.top - 10),
      Offset(midX, paperRect.top + 10),
      guidePaint,
    );
    canvas.drawLine(
      Offset(midX, paperRect.bottom - 10),
      Offset(midX, paperRect.bottom + 10),
      guidePaint,
    );
    canvas.drawLine(
      Offset(paperRect.left - 10, midY),
      Offset(paperRect.left + 10, midY),
      guidePaint,
    );
    canvas.drawLine(
      Offset(paperRect.right - 10, midY),
      Offset(paperRect.right + 10, midY),
      guidePaint,
    );
  }

  void _paintMangaPanelsAndBalloons(Canvas canvas, MangaStructure structure) {
    for (final panel in structure.panels) {
      canvas.drawRect(
        panel.rect,
        Paint()
          ..color = panel.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = panel.borderWidth,
      );
    }

    for (final b in structure.balloons) {
      final balloonRect = Rect.fromLTWH(
        b.position.dx,
        b.position.dy,
        b.size.width,
        b.size.height,
      );
      final rrect = RRect.fromRectAndRadius(
        balloonRect,
        Radius.circular(b.size.width * 0.35),
      );

      canvas.drawRRect(rrect, Paint()..color = b.balloonColor);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = b.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = b.borderWidth,
      );

      // Tail
      final tailPath = Path()
        ..moveTo(balloonRect.center.dx - 8, balloonRect.bottom - 2)
        ..lineTo(b.tailTarget.dx, b.tailTarget.dy)
        ..lineTo(balloonRect.center.dx + 8, balloonRect.bottom - 2)
        ..close();
      canvas.drawPath(tailPath, Paint()..color = b.balloonColor);
      canvas.drawPath(
        tailPath,
        Paint()
          ..color = b.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = b.borderWidth,
      );

      // Text inside balloon
      final textSpan = TextSpan(
        text: b.text,
        style: TextStyle(
          color: b.textColor,
          fontSize: b.fontSize,
          fontWeight: FontWeight.bold,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: b.size.width - 16);
      tp.paint(
        canvas,
        Offset(
          balloonRect.center.dx - tp.width / 2,
          balloonRect.center.dy - tp.height / 2,
        ),
      );
    }
  }

  void _paintRulers(Canvas canvas, Rect paperRect) {
    for (final r in rulers) {
      if (!r.active || !r.visible) continue;
      final rulerPaint = Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / zoom;

      switch (r.type) {
        case RulerType.straight:
          canvas.drawLine(r.origin, r.target, rulerPaint);
          break;
        case RulerType.circular:
          canvas.drawCircle(r.origin, r.radius, rulerPaint);
          break;
        case RulerType.radialFocus:
          for (int i = 0; i < 16; i++) {
            final angle = (i / 16) * 2 * pi;
            final endX = r.origin.dx + cos(angle) * paperRect.width;
            final endY = r.origin.dy + sin(angle) * paperRect.height;
            canvas.drawLine(r.origin, Offset(endX, endY), rulerPaint);
          }
          break;
        case RulerType.symmetryMirror:
          canvas.drawLine(
            Offset(paperRect.center.dx, paperRect.top),
            Offset(paperRect.center.dx, paperRect.bottom),
            rulerPaint..strokeWidth = 2.0 / zoom,
          );
          break;
        case RulerType.perspective1Point:
        case RulerType.perspective2Point:
        case RulerType.perspective3Point:
          for (final vp in r.vanishingPoints) {
            canvas.drawCircle(
              vp,
              6.0 / zoom,
              Paint()..color = const Color(0xFFEF4444),
            );
            for (int k = -5; k <= 5; k++) {
              canvas.drawLine(
                vp,
                Offset(paperRect.left + k * 100, paperRect.bottom),
                rulerPaint,
              );
            }
          }
          break;
      }
    }
  }

  void _paintSelectionOverlay(
    Canvas canvas,
    SelectionMask mask,
    Rect paperRect,
  ) {
    final antsPaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;

    if (mask.boundingBox != null) {
      canvas.drawRect(mask.boundingBox!, antsPaint);
    } else if (mask.outlinePoints.isNotEmpty) {
      final p = Path()
        ..moveTo(mask.outlinePoints.first.dx, mask.outlinePoints.first.dy);
      for (int i = 1; i < mask.outlinePoints.length; i++) {
        p.lineTo(mask.outlinePoints[i].dx, mask.outlinePoints[i].dy);
      }
      p.close();
      canvas.drawPath(p, antsPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StudioCanvasPainter oldDelegate) => true;
}
