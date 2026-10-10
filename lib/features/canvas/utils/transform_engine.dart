import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/models/node.dart';
import '../../../domain/models/drawing_payload.dart';
import '../../../domain/models/vector_path_payload.dart';
import 'hit_tester.dart';

class CanvasTransformEngine {
  const CanvasTransformEngine._();

  static Rect resizeRect({
    required Rect original,
    required ResizeHandle handle,
    required Offset delta,
    bool lockAspect = false,
    bool fromCenter = false,
    double minimumSize = 10,
  }) {
    var left = original.left;
    var top = original.top;
    var width = original.width;
    var height = original.height;
    final horizontal = switch (handle) {
      ResizeHandle.topLeft ||
      ResizeHandle.centerLeft ||
      ResizeHandle.bottomLeft => -1,
      ResizeHandle.topRight ||
      ResizeHandle.centerRight ||
      ResizeHandle.bottomRight => 1,
      _ => 0,
    };
    final vertical = switch (handle) {
      ResizeHandle.topLeft ||
      ResizeHandle.topCenter ||
      ResizeHandle.topRight => -1,
      ResizeHandle.bottomLeft ||
      ResizeHandle.bottomCenter ||
      ResizeHandle.bottomRight => 1,
      _ => 0,
    };

    if (horizontal < 0) {
      left += delta.dx;
      width -= delta.dx;
    } else if (horizontal > 0) {
      width += delta.dx;
    }
    if (vertical < 0) {
      top += delta.dy;
      height -= delta.dy;
    } else if (vertical > 0) {
      height += delta.dy;
    }

    width = math.max(minimumSize, width);
    height = math.max(minimumSize, height);

    final isCorner = horizontal != 0 && vertical != 0;
    if (lockAspect && isCorner && original.width > 0 && original.height > 0) {
      final widthScale = width / original.width;
      final heightScale = height / original.height;
      final scale = math.max(
        math.max(widthScale, heightScale),
        math.max(minimumSize / original.width, minimumSize / original.height),
      );
      width = original.width * scale;
      height = original.height * scale;
    }

    if (fromCenter) {
      final center = original.center;
      left = center.dx - width / 2;
      top = center.dy - height / 2;
    } else {
      if (horizontal < 0) left = original.right - width;
      if (vertical < 0) top = original.bottom - height;
    }
    return Rect.fromLTWH(left, top, width, height);
  }

  static CanvasNode scaleNodeContent(
    CanvasNode node, {
    required double width,
    required double height,
  }) {
    if (node.width <= 0 || node.height <= 0) {
      return node.copyWith(width: width, height: height);
    }
    final scaleX = width / node.width;
    final scaleY = height / node.height;
    var payload = node.payload;
    if (payload is DrawingPayload) {
      payload = payload.copyWith(
        points: payload.points
            .map((point) => Offset(point.dx * scaleX, point.dy * scaleY))
            .toList(growable: false),
      );
    } else if (payload is VectorPathPayload) {
      payload = payload.copyWith(
        points: payload.points
            .map(
              (point) => BezierPoint(
                point: Offset(point.point.dx * scaleX, point.point.dy * scaleY),
                handleIn: Offset(
                  point.handleIn.dx * scaleX,
                  point.handleIn.dy * scaleY,
                ),
                handleOut: Offset(
                  point.handleOut.dx * scaleX,
                  point.handleOut.dy * scaleY,
                ),
              ),
            )
            .toList(growable: false),
      );
    }
    return node.copyWith(width: width, height: height, payload: payload);
  }

  static CanvasNode rotateNodeAround(
    CanvasNode node, {
    required Offset center,
    required double radians,
  }) {
    final nodeCenter = node.bounds.center;
    final offset = nodeCenter - center;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    final rotatedCenter = Offset(
      center.dx + offset.dx * cosine - offset.dy * sine,
      center.dy + offset.dx * sine + offset.dy * cosine,
    );
    return node.copyWith(
      x: rotatedCenter.dx - node.width / 2,
      y: rotatedCenter.dy - node.height / 2,
      rotation: node.rotation + radians,
    );
  }

  static List<CanvasNode> rotateSelection(
    Iterable<CanvasNode> nodes,
    double radians, {
    bool snapToQuarterTurns = false,
  }) {
    final targets = nodes.toList(growable: false);
    if (targets.isEmpty) return const [];
    final normalizedRadians = snapToQuarterTurns
        ? (radians / (math.pi / 2)).round() * (math.pi / 2)
        : radians;
    final bounds = targets.fold<Rect?>(null, (current, node) {
      final next = node.bounds;
      return current == null ? next : current.expandToInclude(next);
    })!;
    final center = bounds.center;
    return targets
        .map(
          (node) => rotateNodeAround(
            node,
            center: center,
            radians: normalizedRadians,
          ),
        )
        .toList(growable: false);
  }
}
