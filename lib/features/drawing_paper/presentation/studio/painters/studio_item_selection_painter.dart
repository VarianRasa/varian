import 'package:flutter/material.dart';
import 'package:varian/features/drawing_paper/domain/models/studio_item_selection.dart';
import 'package:varian/features/drawing_paper/domain/services/studio_item_selection_service.dart';

class StudioItemSelectionPainter {
  const StudioItemSelectionPainter._();

  static void paint(
    Canvas canvas, {
    required List<FocusStudioItemEntry> items,
    required double zoom,
  }) {
    if (items.isEmpty) return;
    final itemPaint = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / zoom;
    Rect? selectionBounds;
    for (final entry in items) {
      final bounds = FocusStudioItemGeometry.boundsOf(entry.item);
      if (bounds == null || bounds.isEmpty) continue;
      selectionBounds = selectionBounds == null
          ? bounds
          : selectionBounds.expandToInclude(bounds);
      canvas.drawRect(bounds, itemPaint);
    }
    if (selectionBounds == null || selectionBounds.isEmpty) return;

    final boundsPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    canvas.drawRect(selectionBounds, boundsPaint);

    final handleSize = 8.0 / zoom;
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final handleBorder = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / zoom;
    for (final point in _handlePoints(selectionBounds)) {
      final handle = Rect.fromCenter(
        center: point,
        width: handleSize,
        height: handleSize,
      );
      canvas.drawRect(handle, handlePaint);
      canvas.drawRect(handle, handleBorder);
    }

    final rotationAnchor = Offset(
      selectionBounds.center.dx,
      selectionBounds.top - 28.0 / zoom,
    );
    canvas.drawLine(
      Offset(selectionBounds.center.dx, selectionBounds.top),
      rotationAnchor,
      boundsPaint,
    );
    canvas.drawCircle(rotationAnchor, 5.0 / zoom, handlePaint);
    canvas.drawCircle(rotationAnchor, 5.0 / zoom, handleBorder);
  }

  static void paintMarquee(Canvas canvas, Rect marquee, double zoom) {
    if (marquee.isEmpty) return;
    final fill = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRect(marquee, fill);
    final paint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / zoom;
    canvas.drawRect(marquee, paint);
  }

  static List<Offset> _handlePoints(Rect bounds) => [
    bounds.topLeft,
    Offset(bounds.center.dx, bounds.top),
    bounds.topRight,
    Offset(bounds.left, bounds.center.dy),
    Offset(bounds.right, bounds.center.dy),
    bounds.bottomLeft,
    Offset(bounds.center.dx, bounds.bottom),
    bounds.bottomRight,
  ];
}
