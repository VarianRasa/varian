import 'dart:math';
import 'package:flutter/material.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'grid_painter.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/utils/connector_router.dart';

class EdgePainter {
  static void paint(
    Canvas canvas,
    CanvasEdge edge,
    Map<String, CanvasNode> nodeMap, {
    bool isSelected = false,
    double zoom = 1.0,
    CanvasRenderTokens renderTokens = CanvasRenderTokens.dark,
  }) {
    final points = ConnectorRouter.routePointsForEdge(edge, nodeMap);
    if (points.length < 2) return;
    final source = edge.sourceNodeId == null
        ? null
        : nodeMap[edge.sourceNodeId];
    final target = edge.targetNodeId == null
        ? null
        : nodeMap[edge.targetNodeId];
    if (source != null && !source.visible) return;
    if (target != null && !target.visible) return;

    final path = ConnectorRouter.routeEdge(
      points.first,
      edge.sourceAnchor,
      points.last,
      edge.targetAnchor,
      edge.routing,
      waypoints: edge.waypoints,
    );

    if (isSelected) {
      final selectionGlow = Paint()
        ..color = renderTokens.selection.withValues(alpha: 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(6.0, edge.strokeWidth + 6.0) / zoom
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, selectionGlow);
    }

    final linePaint = Paint()
      ..color = edge.strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (edge.strokeStyle == StrokeStyle.dashed) {
      _drawDashedPath(canvas, path, linePaint, dashWidth: 6, dashSpace: 4);
    } else if (edge.strokeStyle == StrokeStyle.dotted) {
      _drawDashedPath(canvas, path, linePaint, dashWidth: 2, dashSpace: 3);
    } else {
      canvas.drawPath(path, linePaint);
    }

    final startAngle = _segmentAngle(points.first, points[1]);
    final endAngle = _segmentAngle(points.last, points[points.length - 2]);
    _paintMarker(
      canvas,
      points.first,
      startAngle,
      edge.startMarker,
      edge.strokeColor,
      edge.strokeWidth,
    );
    _paintMarker(
      canvas,
      points.last,
      endAngle,
      edge.endMarker,
      edge.strokeColor,
      edge.strokeWidth,
    );

    if (edge.label != null && edge.label!.isNotEmpty) {
      final labelPoint = ConnectorRouter.pointAtRouteFraction(
        points,
        edge.normalizedLabelPosition,
      );
      _paintLabel(canvas, labelPoint, edge.label!);
    }
  }

  static void paintControls(
    Canvas canvas,
    CanvasEdge edge,
    Map<String, CanvasNode> nodeMap, {
    double zoom = 1.0,
    CanvasRenderTokens renderTokens = CanvasRenderTokens.dark,
  }) {
    final points = ConnectorRouter.routePointsForEdge(edge, nodeMap);
    if (points.length < 2) return;

    final handleRadius = 5.0 / zoom;
    final handleFill = Paint()
      ..color = renderTokens.handle
      ..style = PaintingStyle.fill;
    final handleStroke = Paint()
      ..color = renderTokens.selection
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;

    for (final point in [points.first, points.last]) {
      canvas.drawCircle(point, handleRadius, handleFill);
      canvas.drawCircle(point, handleRadius, handleStroke);
    }
    for (final point in points.skip(1).take(points.length - 2)) {
      final waypointRect = Rect.fromCenter(
        center: point,
        width: handleRadius * 1.8,
        height: handleRadius * 1.8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          waypointRect,
          Radius.circular(handleRadius * 0.35),
        ),
        handleFill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          waypointRect,
          Radius.circular(handleRadius * 0.35),
        ),
        handleStroke,
      );
    }

    if (edge.routing != ConnectorRouting.orthogonal) return;
    final segmentPaint = Paint()
      ..color = renderTokens.selection.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      if ((end - start).distance < 32) continue;
      for (final guide in ConnectorRouter.segmentHandleGuides(
        start,
        end,
        length: 20.0 / zoom,
        separation: 6.0 / zoom,
      )) {
        canvas.drawLine(guide.$1, guide.$2, segmentPaint);
      }
    }

    for (final corner in ConnectorRouter.rightAngleCorners(
      points,
      minSegmentLength: 8.0 / zoom,
    )) {
      _paintRightAngleTrigger(
        canvas,
        corner.$1,
        corner.$2,
        corner.$3,
        zoom,
        renderTokens,
      );
    }
  }

  static void _paintRightAngleTrigger(
    Canvas canvas,
    Offset previous,
    Offset corner,
    Offset next,
    double zoom,
    CanvasRenderTokens renderTokens,
  ) {
    final incomingLength = (previous - corner).distance;
    final outgoingLength = (next - corner).distance;
    final armLength = min(
      10.0 / zoom,
      min(incomingLength, outgoingLength) / 3.0,
    );
    if (!armLength.isFinite || armLength <= 0) return;

    final incoming = (previous - corner) / incomingLength;
    final outgoing = (next - corner) / outgoingLength;
    final first = corner + incoming * armLength;
    final middle = first + outgoing * armLength;
    final last = corner + outgoing * armLength;

    final glowPaint = Paint()
      ..color = renderTokens.success.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0 / zoom
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final markerPaint = Paint()
      ..color = renderTokens.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / zoom
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawLine(first, middle, glowPaint);
    canvas.drawLine(middle, last, glowPaint);
    canvas.drawLine(first, middle, markerPaint);
    canvas.drawLine(middle, last, markerPaint);
  }

  static double _segmentAngle(Offset from, Offset to) {
    final delta = from - to;
    if (delta.distance == 0) return 0;
    return atan2(delta.dy, delta.dx);
  }

  static void _paintMarker(
    Canvas canvas,
    Offset point,
    double angle,
    LineMarker marker,
    Color color,
    double strokeWidth,
  ) {
    if (marker == LineMarker.none) return;
    final double size = max(8.0, strokeWidth * 3.5);
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    if (marker == LineMarker.arrow) {
      final arrowPath = Path()
        ..moveTo(point.dx, point.dy)
        ..lineTo(
          point.dx - size * cos(angle - pi / 6.5),
          point.dy - size * sin(angle - pi / 6.5),
        )
        ..lineTo(
          point.dx - size * 0.75 * cos(angle),
          point.dy - size * 0.75 * sin(angle),
        )
        ..lineTo(
          point.dx - size * cos(angle + pi / 6.5),
          point.dy - size * sin(angle + pi / 6.5),
        )
        ..close();
      canvas.drawPath(arrowPath, fillPaint);
    } else if (marker == LineMarker.circle) {
      canvas.drawCircle(point, size * 0.4, fillPaint);
    } else if (marker == LineMarker.diamond) {
      final dP = Path()
        ..moveTo(point.dx, point.dy)
        ..lineTo(
          point.dx - size * 0.6 * cos(angle - pi / 4),
          point.dy - size * 0.6 * sin(angle - pi / 4),
        )
        ..lineTo(point.dx - size * cos(angle), point.dy - size * sin(angle))
        ..lineTo(
          point.dx - size * 0.6 * cos(angle + pi / 4),
          point.dy - size * 0.6 * sin(angle + pi / 4),
        )
        ..close();
      canvas.drawPath(dP, fillPaint);
    }
  }

  static void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dashWidth = 6.0,
    double dashSpace = 4.0,
  }) {
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final len = min(dashWidth, metric.length - distance);
        final extract = metric.extractPath(distance, distance + len);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  static void _paintLabel(Canvas canvas, Offset center, String text) {
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
      ..layout();

    final bgRect = Rect.fromCenter(
      center: center,
      width: tp.width + 12,
      height: tp.height + 6,
    );

    final bgPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      bgPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      borderPaint,
    );

    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }
}
