import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';

/// The persisted Focus Studio objects that can be selected independently.
enum FocusStudioItemKind {
  drawingStroke,
  vectorShapeObject,
  textObject,
  mangaPanelCut,
  speechBalloon,
}

/// Transient identity for one selectable Focus Studio object.
class FocusStudioItemReference {
  final FocusStudioItemKind kind;
  final String objectId;
  final String? layerId;

  const FocusStudioItemReference({
    required this.kind,
    required this.objectId,
    this.layerId,
  });

  const FocusStudioItemReference.drawingStroke({
    required String layerId,
    required String objectId,
  }) : this(
         kind: FocusStudioItemKind.drawingStroke,
         objectId: objectId,
         layerId: layerId,
       );

  const FocusStudioItemReference.vectorShapeObject({
    required String layerId,
    required String objectId,
  }) : this(
         kind: FocusStudioItemKind.vectorShapeObject,
         objectId: objectId,
         layerId: layerId,
       );

  const FocusStudioItemReference.textObject({
    required String layerId,
    required String objectId,
  }) : this(
         kind: FocusStudioItemKind.textObject,
         objectId: objectId,
         layerId: layerId,
       );

  const FocusStudioItemReference.mangaPanelCut({required String objectId})
    : this(kind: FocusStudioItemKind.mangaPanelCut, objectId: objectId);

  const FocusStudioItemReference.speechBalloon({required String objectId})
    : this(kind: FocusStudioItemKind.speechBalloon, objectId: objectId);

  @override
  bool operator ==(Object other) {
    return other is FocusStudioItemReference &&
        other.kind == kind &&
        other.objectId == objectId &&
        other.layerId == layerId;
  }

  @override
  int get hashCode => Object.hash(kind, objectId, layerId);

  @override
  String toString() =>
      'FocusStudioItemReference($kind, $objectId, layer: $layerId)';
}

/// Geometry shared by Focus Studio hit-testing and selection overlays.
class FocusStudioItemGeometry {
  const FocusStudioItemGeometry._();

  static Rect? boundsOf(Object item) {
    return switch (item) {
      DrawingStroke stroke => _strokeBounds(stroke),
      VectorShapeObject shape => _shapeBounds(shape),
      TextObjectData text => _textBounds(text),
      MangaPanelCut panel => _rotatedRectBounds(panel.rect, panel.rotation),
      SpeechBalloon balloon => _balloonBounds(balloon),
      _ => null,
    };
  }

  static bool hitTest(Object item, Offset point, {double tolerance = 0.0}) {
    switch (item) {
      case DrawingStroke stroke:
        return _hitStroke(stroke, point, tolerance);
      case VectorShapeObject shape:
        return _hitShape(shape, point, tolerance);
      case TextObjectData text:
        return _hitRotatedRect(text.bounds, text.rotation, point, tolerance);
      case MangaPanelCut panel:
        return _hitRotatedRect(panel.rect, panel.rotation, point, tolerance);
      case SpeechBalloon balloon:
        return _hitBalloon(balloon, point, tolerance);
      default:
        return false;
    }
  }

  static bool intersectsMarquee(Object item, Rect marquee) {
    final bounds = boundsOf(item);
    return bounds != null && bounds.overlaps(marquee);
  }

  static Rect _strokeBounds(DrawingStroke stroke) {
    if (stroke.points.isEmpty) return Rect.zero;
    final points = stroke.points.map((point) => point.offset).toList();
    return DrawingStroke.boundsOf(points).inflate(_strokeRadius(stroke));
  }

  static double _strokeRadius(DrawingStroke stroke) {
    final scale = switch (stroke.brush) {
      StudioBrushCategory.maruPen => 0.65,
      StudioBrushCategory.fudeBrush => 1.35,
      StudioBrushCategory.marker => 1.2,
      StudioBrushCategory.airbrush => 1.9,
      StudioBrushCategory.pencilRough => 0.85,
      StudioBrushCategory.oilPastel => 1.25,
      StudioBrushCategory.watercolor => 1.6,
      StudioBrushCategory.eraserSoft => 1.35,
      _ => 1.0,
    };
    return math.max(1.0, stroke.size * scale) / 2;
  }

  static Rect? _shapeBounds(VectorShapeObject shape) {
    final rawBounds = shape.bounds;
    if (rawBounds == null) return null;
    final rotated = shape.rotation == 0.0
        ? rawBounds
        : _rotatedRectBounds(rawBounds, shape.rotation);
    return rotated.inflate(shape.strokeWidth / 2);
  }

  static Rect _textBounds(TextObjectData text) {
    return _rotatedRectBounds(text.bounds, text.rotation);
  }

  static Rect _rotatedRectBounds(Rect rect, double angle) {
    final center = rect.center;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ].map((point) => _rotate(point, center, angle));
    final xs = corners.map((point) => point.dx);
    final ys = corners.map((point) => point.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  static bool _hitRotatedRect(
    Rect rect,
    double angle,
    Offset point,
    double tolerance,
  ) {
    final localPoint = angle == 0.0
        ? point
        : _rotate(point, rect.center, -angle);
    return rect.inflate(tolerance).contains(localPoint);
  }

  static Rect _balloonBounds(SpeechBalloon balloon) {
    final body = Rect.fromLTWH(
      balloon.position.dx,
      balloon.position.dy,
      balloon.size.width,
      balloon.size.height,
    );
    final rotatedBody = _rotatedRectBounds(body, balloon.rotation);
    final left = math.min(rotatedBody.left, balloon.tailTarget.dx);
    final top = math.min(rotatedBody.top, balloon.tailTarget.dy);
    final right = math.max(rotatedBody.right, balloon.tailTarget.dx);
    final bottom = math.max(rotatedBody.bottom, balloon.tailTarget.dy);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static bool _hitStroke(DrawingStroke stroke, Offset point, double tolerance) {
    final points = stroke.points.map((value) => value.offset).toList();
    if (points.isEmpty) return false;
    final radius = _strokeRadius(stroke) + tolerance;
    if (stroke.brush == StudioBrushCategory.bucketFill ||
        stroke.brush == StudioBrushCategory.lassoFill) {
      return _pointInPolygon(point, points) ||
          _distanceToPolygon(point, points) <= radius;
    }
    if (points.length == 1) return (points.first - point).distance <= radius;
    for (var index = 1; index < points.length; index++) {
      if (_distanceToSegment(point, points[index - 1], points[index]) <=
          radius) {
        return true;
      }
    }
    return false;
  }

  static bool _hitShape(
    VectorShapeObject shape,
    Offset point,
    double tolerance,
  ) {
    final rawBounds = shape.bounds;
    if (rawBounds == null) return false;
    final localPoint = shape.rotation == 0.0
        ? point
        : _rotate(point, rawBounds.center, -shape.rotation);

    if (shape.kind == ShapeKind.line || shape.kind == ShapeKind.arrow) {
      if (shape.points.length < 2) return false;
      return _distanceToSegment(
            localPoint,
            shape.points.first,
            shape.points.last,
          ) <=
          shape.strokeWidth + tolerance;
    }

    if (shape.kind == ShapeKind.ellipse) {
      final inflated = rawBounds.inflate(tolerance);
      if (inflated.width <= 0 || inflated.height <= 0) return false;
      final nx =
          (localPoint.dx - rawBounds.center.dx) /
          (rawBounds.width / 2 + tolerance);
      final ny =
          (localPoint.dy - rawBounds.center.dy) /
          (rawBounds.height / 2 + tolerance);
      return nx * nx + ny * ny <= 1.0;
    }

    return rawBounds.inflate(tolerance).contains(localPoint);
  }

  static bool _hitBalloon(
    SpeechBalloon balloon,
    Offset point,
    double tolerance,
  ) {
    final body = Rect.fromLTWH(
      balloon.position.dx,
      balloon.position.dy,
      balloon.size.width,
      balloon.size.height,
    );
    final localPoint = balloon.rotation == 0.0
        ? point
        : _rotate(point, body.center, -balloon.rotation);
    final localTailTarget = balloon.rotation == 0.0
        ? balloon.tailTarget
        : _rotate(balloon.tailTarget, body.center, -balloon.rotation);
    final tailTolerance = tolerance + balloon.borderWidth / 2;
    return body.inflate(tolerance).contains(localPoint) ||
        _distanceToSegment(
              localPoint,
              Offset(body.center.dx - 8, body.bottom - 2),
              localTailTarget,
            ) <=
            tailTolerance ||
        _distanceToSegment(
              localPoint,
              localTailTarget,
              Offset(body.center.dx + 8, body.bottom - 2),
            ) <=
            tailTolerance;
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

  static bool _pointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final currentPoint = polygon[index];
      final previousPoint = polygon[previous];
      final crosses =
          (currentPoint.dy > point.dy) != (previousPoint.dy > point.dy);
      if (crosses) {
        final xAtPoint =
            (previousPoint.dx - currentPoint.dx) *
                (point.dy - currentPoint.dy) /
                (previousPoint.dy - currentPoint.dy) +
            currentPoint.dx;
        if (point.dx < xAtPoint) inside = !inside;
      }
    }
    return inside;
  }

  static double _distanceToPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 2) return double.infinity;
    var distance = double.infinity;
    for (var index = 1; index < polygon.length; index++) {
      distance = math.min(
        distance,
        _distanceToSegment(point, polygon[index - 1], polygon[index]),
      );
    }
    if (polygon.length > 2) {
      distance = math.min(
        distance,
        _distanceToSegment(point, polygon.last, polygon.first),
      );
    }
    return distance;
  }

  static double _distanceToSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = segment.distanceSquared;
    if (lengthSquared == 0) return (point - start).distance;
    final projected =
        ((point - start).dx * segment.dx + (point - start).dy * segment.dy) /
        lengthSquared;
    final t = projected.clamp(0.0, 1.0).toDouble();
    return (point - (start + segment * t)).distance;
  }
}
