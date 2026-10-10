import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';
import 'package:varian/features/drawing_paper/domain/models/selection_mask.dart';

import 'raster_canvas_engine.dart';

/// Composes Drawing Paper content for previews, thumbnails, and exports.
///
/// The payload remains the editable source. Raster surfaces and PNGs produced
/// here are derived output and may be rebuilt when a cache is unavailable.
class DrawingPaperRenderer {
  static const double defaultPreviewMaxDimension = 1024.0;
  static const double _legacyPageGap = 32.0;

  /// Returns the root paper and all embedded papers in one workspace space.
  ///
  /// Embedded payloads remain page-local so raster operations do not cross a
  /// tile boundary. Legacy pages created with the old 32px gap are normalized
  /// only when their coordinates exactly match that old lattice.
  static List<DrawingPaperPage> workspacePages(DrawingPaperPayload payload) {
    final pages = <DrawingPaperPage>[
      DrawingPaperPage(
        id: 'root-page',
        position: Offset.zero,
        payload: payload.copyWith(studioPages: const []),
      ),
      ...payload.studioPages.map(
        (page) => page.copyWith(
          payload: page.payload.copyWith(studioPages: const []),
        ),
      ),
    ];

    return pages
        .map(
          (page) => page.copyWith(
            position: page.id == 'root-page'
                ? Offset.zero
                : _normalizeLegacyPagePosition(page),
          ),
        )
        .toList();
  }

  static Rect workspaceBounds(DrawingPaperPayload payload) =>
      workspaceBoundsForPages(workspacePages(payload));

  static Rect workspaceBoundsForPages(Iterable<DrawingPaperPage> pages) {
    Rect? bounds;
    for (final page in pages) {
      final pageBounds = Rect.fromLTWH(
        page.position.dx,
        page.position.dy,
        page.payload.pixelWidth,
        page.payload.pixelHeight,
      );
      bounds = bounds == null ? pageBounds : bounds.expandToInclude(pageBounds);
    }
    return bounds ?? Rect.zero;
  }

  /// Maps updated workspace bounds into the canvas-node space used by the
  /// original workspace bounds and node rectangle.
  static Rect mapWorkspaceBoundsToCanvas({
    required Rect originalWorkspaceBounds,
    required Rect updatedWorkspaceBounds,
    required Rect canvasBounds,
  }) {
    final scaleX =
        canvasBounds.width / math.max(1.0, originalWorkspaceBounds.width);
    final scaleY =
        canvasBounds.height / math.max(1.0, originalWorkspaceBounds.height);
    return Rect.fromLTWH(
      canvasBounds.left +
          (updatedWorkspaceBounds.left - originalWorkspaceBounds.left) * scaleX,
      canvasBounds.top +
          (updatedWorkspaceBounds.top - originalWorkspaceBounds.top) * scaleY,
      updatedWorkspaceBounds.width * scaleX,
      updatedWorkspaceBounds.height * scaleY,
    );
  }

  static Offset _normalizeLegacyPagePosition(DrawingPaperPage page) {
    double normalize(double value, double size) {
      if (size <= 0 || value.abs() < 0.5) return value;
      final legacyStep = size + _legacyPageGap;
      final index = (value / legacyStep).round();
      if (index == 0) return value;
      final expected = index * legacyStep;
      return (value - expected).abs() <= 0.5 ? index * size : value;
    }

    return Offset(
      normalize(page.position.dx, page.payload.pixelWidth),
      normalize(page.position.dy, page.payload.pixelHeight),
    );
  }

  static ({RasterSurface surface, double scale}) buildWorkspacePreview(
    DrawingPaperPayload payload, {
    double? maxDimension = defaultPreviewMaxDimension,
  }) {
    final bounds = workspaceBounds(payload);
    final largestDimension = math.max(bounds.width, bounds.height);
    final resolvedScale =
        maxDimension != null && largestDimension > maxDimension
        ? maxDimension / largestDimension
        : 1.0;
    final scale = resolvedScale.isFinite && resolvedScale > 0
        ? resolvedScale
        : 1.0;
    final surface = RasterSurface.solid(
      math.max(1, (bounds.width * scale).round()),
      math.max(1, (bounds.height * scale).round()),
      payload.paperColor,
    );

    for (final page in workspacePages(payload)) {
      final pagePreview = buildRasterPreview(
        page.payload,
        maxDimension: null,
        scale: scale,
      );
      final offsetX = ((page.position.dx - bounds.left) * scale).round();
      final offsetY = ((page.position.dy - bounds.top) * scale).round();
      for (int y = 0; y < pagePreview.surface.height; y++) {
        for (int x = 0; x < pagePreview.surface.width; x++) {
          surface.setColor(
            offsetX + x,
            offsetY + y,
            pagePreview.surface.colorAt(x, y),
          );
        }
      }
    }

    return (surface: surface, scale: scale);
  }

  static void paintWorkspaceOverlays(
    Canvas canvas,
    DrawingPaperPayload payload, {
    Rect? bounds,
    double scale = 1.0,
  }) {
    final workspace = bounds ?? workspaceBounds(payload);
    for (final page in workspacePages(payload)) {
      canvas.save();
      canvas.translate(
        (page.position.dx - workspace.left) * scale,
        (page.position.dy - workspace.top) * scale,
      );
      canvas.clipRect(
        Rect.fromLTWH(
          0,
          0,
          page.payload.pixelWidth * scale,
          page.payload.pixelHeight * scale,
        ),
      );
      paintOverlays(canvas, page.payload, scaleX: scale, scaleY: scale);
      canvas.restore();
    }
  }

  /// Paints the vector portion of a complete workspace into the caller's
  /// node-sized canvas. Raster operations stay in the page preview path.
  static void paintWorkspaceVectorContent(
    Canvas canvas,
    DrawingPaperPayload payload, {
    required Rect bounds,
    required double scaleX,
    required double scaleY,
  }) {
    canvas.save();
    canvas.translate(-bounds.left * scaleX, -bounds.top * scaleY);
    canvas.scale(scaleX, scaleY);
    for (final page in workspacePages(payload)) {
      canvas.save();
      canvas.translate(page.position.dx, page.position.dy);
      final pageRect = Rect.fromLTWH(
        0,
        0,
        page.payload.pixelWidth,
        page.payload.pixelHeight,
      );
      canvas.drawRect(pageRect, Paint()..color = page.payload.paperColor);
      canvas.clipRect(pageRect);
      for (int i = page.payload.layers.length - 1; i >= 0; i--) {
        final layer = page.payload.layers[i];
        if (!_isLayerVisible(page.payload, layer) ||
            layer.type == LayerType.folder) {
          continue;
        }
        for (final stroke in layer.strokes) {
          _paintVectorStroke(canvas, stroke, layer.opacity, page.payload);
        }
      }
      paintOverlays(canvas, page.payload);
      canvas.restore();
    }
    canvas.restore();
  }

  static void _paintVectorStroke(
    Canvas canvas,
    DrawingStroke stroke,
    double layerOpacity,
    DrawingPaperPayload payload,
  ) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = stroke.isEraser
          ? payload.paperColor
          : stroke.color.withValues(
              alpha: stroke.opacity * layerOpacity.clamp(0.0, 1.0),
            )
      ..strokeWidth = math.max(1.0, stroke.size)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.blendMode;
    final path = Path()..moveTo(stroke.points.first.x, stroke.points.first.y);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].x, stroke.points[i].y);
    }
    if (stroke.brush == StudioBrushCategory.bucketFill ||
        stroke.brush == StudioBrushCategory.lassoFill) {
      final fill = Path.from(path)..close();
      canvas.drawPath(
        fill,
        Paint()
          ..color = stroke.color.withValues(
            alpha: stroke.opacity * layerOpacity.clamp(0.0, 1.0),
          )
          ..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawPath(path, paint);
    }
  }

  static ({RasterSurface surface, double scale}) buildRasterPreview(
    DrawingPaperPayload payload, {
    double? maxDimension = defaultPreviewMaxDimension,
    double? scale,
  }) {
    final largestDimension = math.max(payload.pixelWidth, payload.pixelHeight);
    final resolvedScale =
        scale ??
        (maxDimension != null && largestDimension > maxDimension
            ? maxDimension / largestDimension
            : 1.0);
    final previewScale = resolvedScale.isFinite && resolvedScale > 0
        ? resolvedScale
        : 1.0;
    final surface = RasterSurface.solid(
      math.max(1, (payload.pixelWidth * previewScale).round()),
      math.max(1, (payload.pixelHeight * previewScale).round()),
      payload.paperColor,
    );
    final engine = RasterCanvasEngine(surface);

    for (int i = payload.layers.length - 1; i >= 0; i--) {
      final layer = payload.layers[i];
      if (!_isLayerVisible(payload, layer) || layer.type == LayerType.folder) {
        continue;
      }
      for (final stroke in layer.strokes) {
        engine.drawStroke(
          points: stroke.points
              .map((point) => point.offset * previewScale)
              .toList(),
          pressures: stroke.points.map((point) => point.pressure).toList(),
          color: stroke.color,
          size: stroke.size * previewScale,
          opacity: stroke.opacity * layer.opacity,
          eraser: stroke.isEraser,
          soft:
              stroke.brush == StudioBrushCategory.airbrush ||
              stroke.brush == StudioBrushCategory.watercolor ||
              stroke.brush == StudioBrushCategory.eraserSoft,
          brush: stroke.brush,
        );
      }
    }

    SelectionMask? scaleSelection(SelectionMask? selection) {
      if (selection == null) return null;
      return selection.copyWith(
        outlinePoints: selection.outlinePoints
            .map((point) => point * previewScale)
            .toList(),
        boundingBox: selection.boundingBox == null
            ? null
            : Rect.fromLTWH(
                selection.boundingBox!.left * previewScale,
                selection.boundingBox!.top * previewScale,
                selection.boundingBox!.width * previewScale,
                selection.boundingBox!.height * previewScale,
              ),
      );
    }

    for (final operation in payload.rasterOperations) {
      final selection = scaleSelection(operation.selection);
      switch (operation.kind) {
        case RasterEditKind.bucketFill:
          engine.bucketFill(
            seedPoint: operation.seedPoint * previewScale,
            color: operation.color,
            tolerance: operation.tolerance,
            selection: selection,
          );
        case RasterEditKind.smudge:
          engine.smudge(
            points: operation.points
                .map((point) => point * previewScale)
                .toList(),
            radius: operation.radius * previewScale,
            strength: operation.strength,
            selection: selection,
          );
        case RasterEditKind.blur:
          engine.blur(
            points: operation.points
                .map((point) => point * previewScale)
                .toList(),
            radius: operation.radius * previewScale,
            strength: operation.strength,
            selection: selection,
          );
        case RasterEditKind.transform:
          final bounds = operation.bounds;
          if (bounds != null) {
            engine.transform(
              bounds: Rect.fromLTWH(
                bounds.left * previewScale,
                bounds.top * previewScale,
                bounds.width * previewScale,
                bounds.height * previewScale,
              ),
              translation: operation.translation * previewScale,
              scale: operation.scale,
              rotation: operation.rotation,
              flipH: operation.flipH,
              flipV: operation.flipV,
              selection: selection,
            );
          }
      }
    }

    return (surface: surface, scale: previewScale);
  }

  /// Paints all persisted non-raster objects in payload coordinates.
  static void paintOverlays(
    Canvas canvas,
    DrawingPaperPayload payload, {
    double scaleX = 1.0,
    double scaleY = 1.0,
  }) {
    canvas.save();
    if (scaleX != 1.0 || scaleY != 1.0) canvas.scale(scaleX, scaleY);

    for (final layer in payload.layers.reversed) {
      if (!_isLayerVisible(payload, layer) || layer.type == LayerType.folder) {
        continue;
      }
      final opacity = layer.opacity.clamp(0.0, 1.0).toDouble();
      if (opacity <= 0.0) continue;

      canvas.saveLayer(
        null,
        Paint()
          ..blendMode = layer.blendMode
          ..color = Colors.white.withValues(alpha: opacity),
      );
      for (final shape in layer.shapes) {
        _paintShape(canvas, shape);
      }
      for (final text in layer.texts) {
        _paintText(canvas, text);
      }
      canvas.restore();
    }

    final structure = payload.mangaStructure;
    if (structure != null) _paintMangaStructure(canvas, structure);
    canvas.restore();
  }

  static Future<Uint8List?> renderPng(
    DrawingPaperPayload payload, {
    double? maxDimension = defaultPreviewMaxDimension,
  }) async {
    final hasEmbeddedPages = payload.studioPages.isNotEmpty;
    final preview = hasEmbeddedPages
        ? buildWorkspacePreview(payload, maxDimension: maxDimension)
        : buildRasterPreview(payload, maxDimension: maxDimension);
    final rasterImage = await _decodeSurface(preview.surface);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final outputRect = Rect.fromLTWH(
      0,
      0,
      preview.surface.width.toDouble(),
      preview.surface.height.toDouble(),
    );
    canvas.drawImageRect(
      rasterImage,
      Rect.fromLTWH(
        0,
        0,
        rasterImage.width.toDouble(),
        rasterImage.height.toDouble(),
      ),
      outputRect,
      Paint(),
    );
    if (hasEmbeddedPages) {
      paintWorkspaceOverlays(canvas, payload, scale: preview.scale);
    } else {
      paintOverlays(
        canvas,
        payload,
        scaleX: preview.scale,
        scaleY: preview.scale,
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      preview.surface.width,
      preview.surface.height,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    rasterImage.dispose();
    image.dispose();
    picture.dispose();
    return bytes?.buffer.asUint8List();
  }

  static Future<ui.Image> _decodeSurface(RasterSurface surface) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(surface.pixels),
      surface.width,
      surface.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static bool _isLayerVisible(DrawingPaperPayload payload, DrawingLayer layer) {
    if (!layer.visible) return false;
    final visited = <String>{};
    var parentId = layer.parentFolderId;
    while (parentId != null && visited.add(parentId)) {
      final parent = payload.layers.firstWhere(
        (candidate) => candidate.id == parentId,
        orElse: () => const DrawingLayer(id: '', name: '', visible: false),
      );
      if (!parent.visible) return false;
      parentId = parent.parentFolderId;
    }
    return true;
  }

  static void _paintShape(Canvas canvas, VectorShapeObject shape) {
    final path = shape.toPath();
    final bounds = shape.bounds;
    if (bounds == null) return;
    canvas.save();
    if (shape.rotation != 0.0) {
      canvas.translate(bounds.center.dx, bounds.center.dy);
      canvas.rotate(shape.rotation);
      canvas.translate(-bounds.center.dx, -bounds.center.dy);
    }

    if (shape.toneType != ScreenToneType.none) {
      _paintScreenToneArea(
        canvas,
        path,
        shape.toneType,
        shape.toneFrequency,
        shape.toneAngle,
        shape.stroke,
      );
    } else if (shape.fill.a > 0) {
      canvas.drawPath(path, Paint()..color = shape.fill);
    }
    if (shape.stroke.a > 0 && shape.strokeWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = shape.stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = shape.strokeWidth,
      );
    }
    canvas.restore();
  }

  static void _paintText(Canvas canvas, TextObjectData text) {
    if (text.text.isEmpty) return;
    final style = TextStyle(
      color: text.color,
      fontFamily: text.fontFamily,
      fontSize: text.fontSize,
      fontWeight: text.fontWeight,
      decoration: text.hasDecoration ? TextDecoration.underline : null,
      decorationColor: text.decorationColor,
    );
    canvas.save();
    canvas.translate(text.x, text.y);
    final localCenter = Offset(
      text.width / 2,
      math.max(
            text.fontSize * 1.2,
            text.fontSize * text.text.split('\n').length * 1.2,
          ) /
          2,
    );
    if (text.rotation != 0.0) {
      canvas.translate(localCenter.dx, localCenter.dy);
      canvas.rotate(text.rotation);
      canvas.translate(-localCenter.dx, -localCenter.dy);
    }
    if (text.isVertical) {
      double y = 0;
      for (final character in text.text.split('')) {
        final painter = TextPainter(
          text: TextSpan(text: character, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(0, y));
        y += painter.height * 0.9;
      }
    } else {
      if (text.outlineWidth > 0 && text.outlineColor.a > 0) {
        final outlinePainter = TextPainter(
          text: TextSpan(
            text: text.text,
            style: style.copyWith(
              foreground: Paint()
                ..color = text.outlineColor
                ..style = PaintingStyle.stroke
                ..strokeWidth = text.outlineWidth,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: text.textAlign,
        )..layout(maxWidth: math.max(1.0, text.width));
        outlinePainter.paint(canvas, Offset.zero);
      }
      final painter = TextPainter(
        text: TextSpan(text: text.text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: text.textAlign,
      )..layout(maxWidth: math.max(1.0, text.width));
      painter.paint(canvas, Offset.zero);
    }
    canvas.restore();
  }

  static void _paintMangaStructure(Canvas canvas, MangaStructure structure) {
    for (final panel in structure.panels) {
      canvas.save();
      canvas.translate(panel.rect.center.dx, panel.rect.center.dy);
      canvas.rotate(panel.rotation);
      canvas.translate(-panel.rect.center.dx, -panel.rect.center.dy);
      if (panel.backgroundColor.a > 0) {
        canvas.drawRect(panel.rect, Paint()..color = panel.backgroundColor);
      }
      canvas.drawRect(
        panel.rect,
        Paint()
          ..color = panel.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = panel.borderWidth,
      );
      canvas.restore();
    }

    for (final balloon in structure.balloons) {
      _paintBalloon(canvas, balloon);
    }
  }

  static void _paintBalloon(Canvas canvas, SpeechBalloon balloon) {
    final rect = Rect.fromLTWH(
      balloon.position.dx,
      balloon.position.dy,
      balloon.size.width,
      balloon.size.height,
    );
    canvas.save();
    if (balloon.rotation != 0.0) {
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(balloon.rotation);
      canvas.translate(-rect.center.dx, -rect.center.dy);
    }
    final body = _balloonPath(balloon, rect);
    canvas.drawPath(body, Paint()..color = balloon.balloonColor);
    canvas.drawPath(
      body,
      Paint()
        ..color = balloon.borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = balloon.borderWidth,
    );

    final tailTarget = balloon.rotation == 0.0
        ? balloon.tailTarget
        : _rotate(balloon.tailTarget, rect.center, -balloon.rotation);
    final tail = Path()
      ..moveTo(rect.center.dx - 8, rect.bottom - 2)
      ..lineTo(tailTarget.dx, tailTarget.dy)
      ..lineTo(rect.center.dx + 8, rect.bottom - 2)
      ..close();
    canvas.drawPath(tail, Paint()..color = balloon.balloonColor);
    canvas.drawPath(
      tail,
      Paint()
        ..color = balloon.borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = balloon.borderWidth,
    );

    if (balloon.isVerticalText) {
      double y = rect.top + 8;
      for (final character in balloon.text.split('')) {
        final painter = TextPainter(
          text: TextSpan(
            text: character,
            style: TextStyle(
              color: balloon.textColor,
              fontSize: balloon.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(rect.center.dx - painter.width / 2, y));
        y += painter.height * 0.9;
      }
      canvas.restore();
      return;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: balloon.text,
        style: TextStyle(
          color: balloon.textColor,
          fontSize: balloon.fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: math.max(1.0, rect.width - 16));
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
    canvas.restore();
  }

  static Path _balloonPath(SpeechBalloon balloon, Rect rect) {
    final path = Path();
    switch (balloon.type) {
      case SpeechBalloonType.speechOval:
        path.addOval(rect);
        break;
      case SpeechBalloonType.thoughtCloud:
        path.addRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(rect.shortestSide * 0.35),
          ),
        );
        break;
      case SpeechBalloonType.squareWhisper:
        path.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
        break;
      case SpeechBalloonType.shoutExplosion:
        final center = rect.center;
        final radius = rect.shortestSide / 2;
        const points = 16;
        for (int i = 0; i < points; i++) {
          final angle = -math.pi / 2 + i * 2 * math.pi / points;
          final currentRadius = i.isEven ? radius : radius * 0.72;
          final point = Offset(
            center.dx + math.cos(angle) * currentRadius,
            center.dy + math.sin(angle) * currentRadius,
          );
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
        break;
    }
    return path;
  }

  static void _paintScreenToneArea(
    Canvas canvas,
    Path path,
    ScreenToneType toneType,
    double frequency,
    double angle,
    Color color,
  ) {
    canvas.save();
    canvas.clipPath(path);
    final bounds = path.getBounds();
    final step = (100.0 / math.max(1.0, frequency)).clamp(4.0, 40.0);
    final tonePaint = Paint()
      ..color = color.withValues(alpha: color.a * 0.6)
      ..style = PaintingStyle.fill;
    final radians = angle * math.pi / 180.0;
    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.rotate(radians);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    for (
      double x = bounds.left - bounds.height;
      x < bounds.right + bounds.height;
      x += step
    ) {
      for (
        double y = bounds.top - bounds.width;
        y < bounds.bottom + bounds.width;
        y += step
      ) {
        final point = Offset(x, y);
        switch (toneType) {
          case ScreenToneType.dot:
            canvas.drawCircle(point, step * 0.25, tonePaint);
            break;
          case ScreenToneType.line:
          case ScreenToneType.wave:
            canvas.drawLine(
              point,
              Offset(x + step * 0.8, y + step * 0.8),
              tonePaint
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
            break;
          case ScreenToneType.cross:
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
              tonePaint,
            );
            break;
          case ScreenToneType.none:
            break;
        }
      }
    }
    canvas.restore();
  }

  static Offset _rotate(Offset point, Offset center, double angle) {
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return Offset(
      center.dx + dx * cosA - dy * sinA,
      center.dy + dx * sinA + dy * cosA,
    );
  }
}
