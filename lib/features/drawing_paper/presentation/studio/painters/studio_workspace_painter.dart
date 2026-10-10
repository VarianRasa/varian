import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/ruler_guide.dart';
import 'package:varian/features/drawing_paper/domain/models/selection_mask.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';
import 'package:varian/features/drawing_paper/domain/services/studio_item_selection_service.dart';

import 'studio_canvas_painter.dart';

class StudioPageRenderData {
  final DrawingPaperPage page;
  final ui.Image? rasterImage;
  final double rasterImageScale;

  const StudioPageRenderData({
    required this.page,
    this.rasterImage,
    this.rasterImageScale = 1.0,
  });
}

class StudioWorkspacePainter extends CustomPainter {
  final List<StudioPageRenderData> pages;
  final String activePageId;
  final Offset workspaceCenter;
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
  final double zoom;
  final double rotation;
  final Offset pan;
  final int activeLayerIndex;

  const StudioWorkspacePainter({
    required this.pages,
    required this.activePageId,
    required this.workspaceCenter,
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
    this.zoom = 1.0,
    this.rotation = 0.0,
    this.pan = Offset.zero,
    this.activeLayerIndex = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2 + pan.dx, size.height / 2 + pan.dy);
    if (rotation != 0) canvas.rotate(rotation);
    canvas.scale(zoom, zoom);
    canvas.translate(-workspaceCenter.dx, -workspaceCenter.dy);

    final workspaceRect = DrawingPaperRenderer.workspaceBoundsForPages(
      pages.map((pageData) => pageData.page),
    );
    if (!workspaceRect.isEmpty) {
      canvas.drawShadow(
        Path()..addRect(workspaceRect),
        Colors.black,
        16.0,
        true,
      );
      canvas.drawRect(
        workspaceRect,
        Paint()..color = pages.first.page.payload.paperColor,
      );
    }

    for (final pageData in pages) {
      final page = pageData.page;
      final isActive = page.id == activePageId;
      canvas.save();
      canvas.translate(page.position.dx, page.position.dy);
      StudioCanvasPainter(
        payload: page.payload,
        rasterImage: pageData.rasterImage,
        rasterImageScale: pageData.rasterImageScale,
        activePoints: isActive ? activePoints : const [],
        activeBrush: activeBrush,
        activeColor: activeColor,
        activeSize: activeSize,
        activeOpacity: activeOpacity,
        isEraser: isActive && isEraser,
        selection: isActive ? selection : null,
        selectedItems: isActive ? selectedItems : const [],
        itemMarquee: isActive ? itemMarquee : null,
        rulers: isActive ? rulers : const [],
        mangaStructure: page.payload.mangaStructure,
        zoom: zoom,
        canvasPixelSize: page.payload.pixelSize,
        activeLayerIndex: isActive ? activeLayerIndex : 0,
        applyTransform: false,
        paintPaperChrome: false,
      ).paint(canvas, page.payload.pixelSize);
      canvas.restore();
    }

    if (!workspaceRect.isEmpty) {
      canvas.drawRect(
        workspaceRect,
        Paint()
          ..color = const Color(0xFF64748B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / zoom,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StudioWorkspacePainter oldDelegate) => true;
}
