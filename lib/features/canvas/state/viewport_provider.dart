import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/domain/canvas_navigation.dart';

final viewportProvider = StateNotifierProvider<ViewportNotifier, Viewport>((
  ref,
) {
  return ViewportNotifier();
});

class ViewportNotifier extends StateNotifier<Viewport> {
  ViewportNotifier() : super(const Viewport());

  void pan(double dx, double dy) {
    state = state.copyWith(x: state.x + dx, y: state.y + dy);
  }

  void setPosition(double x, double y) {
    state = state.copyWith(x: x, y: y);
  }

  void setViewport(Viewport viewport) {
    state = viewport.copyWith();
  }

  void zoomBy(double delta, Offset focalPoint) {
    final double oldZoom = state.zoom;
    final double newZoom = (oldZoom * delta).clamp(0.1, 5.0);
    if (oldZoom == newZoom) return;

    final double newX =
        focalPoint.dx - (focalPoint.dx - state.x) * (newZoom / oldZoom);
    final double newY =
        focalPoint.dy - (focalPoint.dy - state.y) * (newZoom / oldZoom);

    state = Viewport(x: newX, y: newY, zoom: newZoom);
  }

  void setZoom(double newZoom) {
    state = state.copyWith(zoom: newZoom.clamp(0.1, 5.0));
  }

  void reset() {
    state = const Viewport(x: 0, y: 0, zoom: 1.0);
  }

  void zoomToNode(Rect bounds, Size screenSize) {
    state = CanvasNavigationMath.fitBounds(
      bounds,
      screenSize,
      minZoom: 0.2,
      maxZoom: 2.0,
    );
  }

  void zoomToContent(Iterable<Rect> bounds, Size screenSize) {
    var contentBounds = Rect.zero;
    var hasContent = false;
    for (final boundsRect in bounds) {
      if (boundsRect.isEmpty) continue;
      contentBounds = hasContent
          ? contentBounds.expandToInclude(boundsRect)
          : boundsRect;
      hasContent = true;
    }
    if (!hasContent) return;
    state = CanvasNavigationMath.fitBounds(contentBounds, screenSize);
  }

  void panToNodeCenter(Rect bounds, Size screenSize) {
    final double nodeCenterX = bounds.center.dx;
    final double nodeCenterY = bounds.center.dy;

    final double newX = (screenSize.width / 2.0) - (nodeCenterX * state.zoom);
    final double newY = (screenSize.height / 2.0) - (nodeCenterY * state.zoom);

    state = state.copyWith(x: newX, y: newY);
  }

  Offset toWorld(Offset screenOffset) {
    return Offset(
      (screenOffset.dx - state.x) / state.zoom,
      (screenOffset.dy - state.y) / state.zoom,
    );
  }

  Offset toScreen(Offset worldOffset) {
    return Offset(
      worldOffset.dx * state.zoom + state.x,
      worldOffset.dy * state.zoom + state.y,
    );
  }

  Rect toWorldRect(Rect screenRect) {
    final topLeft = toWorld(screenRect.topLeft);
    final bottomRight = toWorld(screenRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  Rect toScreenRect(Rect worldRect) {
    final topLeft = toScreen(worldRect.topLeft);
    final bottomRight = toScreen(worldRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }
}
