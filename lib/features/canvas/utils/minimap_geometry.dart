import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Maps document/world coordinates into the fixed minimap rectangle.
///
/// The transform deliberately has no dependency on widget state so coordinate
/// math can be tested without pumping the full canvas editor.
class MinimapTransform {
  final Rect worldBounds;
  final Rect mapRect;
  final double scale;
  final Offset origin;

  const MinimapTransform({
    required this.worldBounds,
    required this.mapRect,
    required this.scale,
    required this.origin,
  });

  factory MinimapTransform.fromWorldBounds(
    Rect bounds,
    Size mapSize, {
    double padding = 8.0,
    double minWorldExtent = 200.0,
  }) {
    final safeSize = Size(
      _finitePositive(mapSize.width, 1.0),
      _finitePositive(mapSize.height, 1.0),
    );
    final safeBounds = _expandDegenerate(_sanitizeRect(bounds), minWorldExtent);
    final inset = padding.clamp(
      0.0,
      math.min(safeSize.width, safeSize.height) / 2,
    );
    final inner = Rect.fromLTWH(
      inset,
      inset,
      math.max(1.0, safeSize.width - inset * 2),
      math.max(1.0, safeSize.height - inset * 2),
    );
    final scale = math.min(
      inner.width / safeBounds.width,
      inner.height / safeBounds.height,
    );
    final safeScale = scale.isFinite && scale > 0 ? scale : 1.0;
    final contentSize = Size(
      safeBounds.width * safeScale,
      safeBounds.height * safeScale,
    );
    final origin =
        inner.topLeft +
        Offset(
          (inner.width - contentSize.width) / 2,
          (inner.height - contentSize.height) / 2,
        );

    return MinimapTransform(
      worldBounds: safeBounds,
      mapRect: Rect.fromLTWH(0, 0, safeSize.width, safeSize.height),
      scale: safeScale,
      origin: origin,
    );
  }

  Offset worldToMinimap(Offset worldPoint) {
    return origin + (worldPoint - worldBounds.topLeft) * scale;
  }

  Offset minimapToWorld(Offset minimapPoint) {
    return worldBounds.topLeft + (minimapPoint - origin) / scale;
  }

  Rect worldRectToMinimap(Rect worldRect) {
    return Rect.fromPoints(
      worldToMinimap(worldRect.topLeft),
      worldToMinimap(worldRect.bottomRight),
    );
  }

  Rect minimapRectToWorld(Rect minimapRect) {
    return Rect.fromPoints(
      minimapToWorld(minimapRect.topLeft),
      minimapToWorld(minimapRect.bottomRight),
    );
  }

  bool contains(Offset point) => mapRect.contains(point);

  static Rect worldBoundsFor({
    required Iterable<Rect> nodeBounds,
    Rect? viewportBounds,
    Rect fallback = const Rect.fromLTWH(-100, -100, 200, 200),
  }) {
    Rect? result;
    for (final raw in nodeBounds) {
      final rect = _finiteRect(raw);
      if (rect == null) continue;
      result = result == null ? rect : result.expandToInclude(rect);
    }

    final viewport = viewportBounds == null
        ? null
        : _finiteRect(viewportBounds);
    if (viewport != null) {
      result = result == null ? viewport : result.expandToInclude(viewport);
    }

    return _expandDegenerate(result ?? _sanitizeRect(fallback), 200.0);
  }

  static Rect _sanitizeRect(Rect rect) {
    final left = rect.left.isFinite ? rect.left : -100.0;
    final top = rect.top.isFinite ? rect.top : -100.0;
    final right = rect.right.isFinite ? rect.right : left + 200.0;
    final bottom = rect.bottom.isFinite ? rect.bottom : top + 200.0;
    return Rect.fromLTRB(
      math.min(left, right),
      math.min(top, bottom),
      math.max(left, right),
      math.max(top, bottom),
    );
  }

  static Rect? _finiteRect(Rect rect) {
    if (!rect.left.isFinite ||
        !rect.top.isFinite ||
        !rect.right.isFinite ||
        !rect.bottom.isFinite) {
      return null;
    }
    return Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );
  }

  static Rect _expandDegenerate(Rect rect, double minExtent) {
    final extent = _finitePositive(minExtent, 200.0);
    var result = rect;
    if (result.width < extent) {
      final half = extent / 2;
      result = result.inflate(half - result.width / 2);
    }
    if (result.height < extent) {
      final half = extent / 2;
      result = result.inflate(half - result.height / 2);
    }
    return result;
  }

  static double _finitePositive(double value, double fallback) {
    return value.isFinite && value > 0 ? value : fallback;
  }
}
