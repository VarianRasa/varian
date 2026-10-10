import 'dart:math';
import 'package:flutter/material.dart';
import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';

enum ConnectorControlKind {
  sourceEndpoint,
  targetEndpoint,
  waypoint,
  segment,
  label,
}

class ConnectorControlHit {
  final String edgeId;
  final ConnectorControlKind kind;
  final int? waypointIndex;
  final int? segmentIndex;

  const ConnectorControlHit({
    required this.edgeId,
    required this.kind,
    this.waypointIndex,
    this.segmentIndex,
  });
}

class ConnectorRouter {
  static Offset getAnchorPoint(CanvasNode node, AnchorPosition anchor) {
    switch (anchor) {
      case AnchorPosition.top:
        return Offset(node.x + node.width / 2, node.y);
      case AnchorPosition.right:
        return Offset(node.x + node.width, node.y + node.height / 2);
      case AnchorPosition.bottom:
        return Offset(node.x + node.width / 2, node.y + node.height);
      case AnchorPosition.left:
        return Offset(node.x, node.y + node.height / 2);
    }
  }

  static AnchorPosition nearestAnchor(CanvasNode node, Offset point) {
    final anchors = {
      AnchorPosition.top: getAnchorPoint(node, AnchorPosition.top),
      AnchorPosition.right: getAnchorPoint(node, AnchorPosition.right),
      AnchorPosition.bottom: getAnchorPoint(node, AnchorPosition.bottom),
      AnchorPosition.left: getAnchorPoint(node, AnchorPosition.left),
    };
    return anchors.entries
        .reduce(
          (nearest, entry) =>
              (entry.value - point).distance < (nearest.value - point).distance
              ? entry
              : nearest,
        )
        .key;
  }

  static (AnchorPosition, Offset)? nearestAnchorWithin(
    CanvasNode node,
    Offset point, {
    double radius = 24.0,
  }) {
    final anchor = nearestAnchor(node, point);
    final anchorPoint = getAnchorPoint(node, anchor);
    return (anchorPoint - point).distance <= radius
        ? (anchor, anchorPoint)
        : null;
  }

  static Offset? endpointPointForEdge(
    CanvasEdge edge,
    Map<String, CanvasNode> nodeMap, {
    required bool source,
  }) {
    final explicitPoint = source ? edge.sourcePoint : edge.targetPoint;
    if (explicitPoint != null) return explicitPoint;

    final nodeId = source ? edge.sourceNodeId : edge.targetNodeId;
    final node = nodeId == null ? null : nodeMap[nodeId];
    if (node != null) {
      return getAnchorPoint(
        node,
        source ? edge.sourceAnchor : edge.targetAnchor,
      );
    }
    return null;
  }

  static List<Offset> routePointsForEdge(
    CanvasEdge edge,
    Map<String, CanvasNode> nodeMap,
  ) {
    final start = endpointPointForEdge(edge, nodeMap, source: true);
    final end = endpointPointForEdge(edge, nodeMap, source: false);
    if (start == null || end == null) return const [];
    return _routePoints(
      start,
      edge.sourceAnchor,
      end,
      edge.targetAnchor,
      edge.routing,
      edge.waypoints,
    );
  }

  static Offset? labelPointForEdge(
    CanvasEdge edge,
    Map<String, CanvasNode> nodeMap,
  ) {
    if (edge.label == null || edge.label!.isEmpty) return null;
    final route = routePointsForEdge(edge, nodeMap);
    if (route.length < 2) return null;
    return pointAtRouteFraction(route, edge.normalizedLabelPosition);
  }

  static Rect? labelBoundsForEdge(
    CanvasEdge edge,
    Map<String, CanvasNode> nodeMap,
  ) {
    final center = labelPointForEdge(edge, nodeMap);
    if (center == null) return null;
    final textPainter = TextPainter(
      text: TextSpan(
        text: edge.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return Rect.fromCenter(
      center: center,
      width: textPainter.width + 12,
      height: textPainter.height + 6,
    );
  }

  static Path routeEdge(
    Offset start,
    AnchorPosition startAnchor,
    Offset end,
    AnchorPosition endAnchor,
    ConnectorRouting routing, {
    List<Offset> waypoints = const [],
  }) {
    final path = Path();
    path.moveTo(start.dx, start.dy);

    if (routing == ConnectorRouting.curved && waypoints.isEmpty) {
      final double dx = (end.dx - start.dx).abs() * 0.5;
      final double dy = (end.dy - start.dy).abs() * 0.5;
      final cp1 = _controlPoint(start, startAnchor, max(dx, 30), max(dy, 30));
      final cp2 = _controlPoint(end, endAnchor, max(dx, 30), max(dy, 30));
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
      return path;
    }

    final points = _routePoints(
      start,
      startAnchor,
      end,
      endAnchor,
      routing,
      waypoints,
    );
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }

  static Offset pointAtRouteFraction(List<Offset> route, double fraction) {
    if (route.isEmpty) return Offset.zero;
    if (route.length == 1) return route.first;

    final totalLength = _routeLength(route);
    if (totalLength <= 0) return route.first;

    var remaining = totalLength * _clampRouteFraction(fraction);
    for (var index = 0; index < route.length - 1; index++) {
      final start = route[index];
      final end = route[index + 1];
      final segmentLength = (end - start).distance;
      if (segmentLength <= 0) continue;
      if (remaining <= segmentLength) {
        final ratio = remaining / segmentLength;
        return Offset.lerp(start, end, ratio)!;
      }
      remaining -= segmentLength;
    }
    return route.last;
  }

  static double routeFractionForPoint(List<Offset> route, Offset point) {
    if (route.length < 2 || !point.dx.isFinite || !point.dy.isFinite) {
      return 0.0;
    }

    final totalLength = _routeLength(route);
    if (totalLength <= 0) return 0.0;

    var distanceBefore = 0.0;
    var bestDistance = double.infinity;
    var bestDistanceAlongRoute = 0.0;
    for (var index = 0; index < route.length - 1; index++) {
      final start = route[index];
      final end = route[index + 1];
      final segment = end - start;
      final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
      if (lengthSquared <= 0) continue;

      final segmentLength = sqrt(lengthSquared);
      final projection =
          (((point - start).dx * segment.dx + (point - start).dy * segment.dy) /
                  lengthSquared)
              .clamp(0.0, 1.0)
              .toDouble();
      final projected = Offset.lerp(start, end, projection)!;
      final distance = (point - projected).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestDistanceAlongRoute = distanceBefore + segmentLength * projection;
      }
      distanceBefore += segmentLength;
    }

    return (bestDistanceAlongRoute / totalLength).clamp(0.0, 1.0).toDouble();
  }

  static double _routeLength(List<Offset> route) {
    var length = 0.0;
    for (var index = 0; index < route.length - 1; index++) {
      length += (route[index + 1] - route[index]).distance;
    }
    return length;
  }

  static double _clampRouteFraction(double fraction) {
    if (!fraction.isFinite) return 0.5;
    return fraction.clamp(0.0, 1.0).toDouble();
  }

  static List<(Offset, Offset)> segmentHandleGuides(
    Offset start,
    Offset end, {
    double length = 20.0,
    double separation = 6.0,
  }) {
    final delta = end - start;
    final segmentLength = delta.distance;
    if (!segmentLength.isFinite || segmentLength <= 0) return const [];
    if (!length.isFinite || length <= 0) return const [];
    if (!separation.isFinite || separation < 0) return const [];

    final direction = Offset(
      delta.dx / segmentLength,
      delta.dy / segmentLength,
    );
    final normal = Offset(-direction.dy, direction.dx);
    final center = Offset.lerp(start, end, 0.5)!;
    final halfLength = min(length / 2, segmentLength / 4);
    final halfLine = direction * halfLength;
    final offset = normal * (separation / 2);

    return [
      (center - halfLine + offset, center + halfLine + offset),
      (center - halfLine - offset, center + halfLine - offset),
    ];
  }

  static bool isRightAngle(
    Offset previous,
    Offset corner,
    Offset next, {
    double toleranceDegrees = 8.0,
    double minSegmentLength = 1.0,
  }) {
    if (!toleranceDegrees.isFinite ||
        toleranceDegrees < 0 ||
        !minSegmentLength.isFinite ||
        minSegmentLength <= 0) {
      return false;
    }

    final incoming = previous - corner;
    final outgoing = next - corner;
    final incomingLength = incoming.distance;
    final outgoingLength = outgoing.distance;
    if (!incomingLength.isFinite ||
        !outgoingLength.isFinite ||
        incomingLength < minSegmentLength ||
        outgoingLength < minSegmentLength) {
      return false;
    }

    final cosine =
        (incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
        (incomingLength * outgoingLength);
    final tolerance = toleranceDegrees.clamp(0.0, 89.9).toDouble() * pi / 180.0;
    return cosine.abs() <= sin(tolerance);
  }

  static List<(Offset, Offset, Offset)> rightAngleCorners(
    List<Offset> route, {
    double toleranceDegrees = 8.0,
    double minSegmentLength = 8.0,
  }) {
    if (route.length < 3) return const [];

    final corners = <(Offset, Offset, Offset)>[];
    for (var index = 1; index < route.length - 1; index++) {
      final previous = route[index - 1];
      final corner = route[index];
      final next = route[index + 1];
      if (isRightAngle(
        previous,
        corner,
        next,
        toleranceDegrees: toleranceDegrees,
        minSegmentLength: minSegmentLength,
      )) {
        corners.add((previous, corner, next));
      }
    }
    return corners;
  }

  static Offset? snapCornerToRightAngle(
    Offset previous,
    Offset corner,
    Offset next, {
    double tolerance = 12.0,
    double minSegmentLength = 1.0,
  }) {
    if (!tolerance.isFinite ||
        tolerance < 0 ||
        !minSegmentLength.isFinite ||
        minSegmentLength <= 0) {
      return null;
    }

    final candidates = [
      Offset(previous.dx, next.dy),
      Offset(next.dx, previous.dy),
    ];
    Offset? closest;
    var closestDistance = double.infinity;
    for (final candidate in candidates) {
      final distance = (candidate - corner).distance;
      if (distance > tolerance || distance >= closestDistance) continue;
      if (!isRightAngle(
        previous,
        candidate,
        next,
        toleranceDegrees: 0,
        minSegmentLength: minSegmentLength,
      )) {
        continue;
      }
      closest = candidate;
      closestDistance = distance;
    }
    return closest;
  }

  static List<Offset> moveWaypoint(
    CanvasEdge edge,
    Map<String, CanvasNode> nodeMap, {
    required int waypointIndex,
    required Offset point,
  }) {
    final waypoints = edge.waypoints.isEmpty
        ? _generatedWaypoints(edge, nodeMap)
        : List<Offset>.from(edge.waypoints);
    if (waypointIndex < 0 || waypointIndex >= waypoints.length) {
      return waypoints;
    }
    waypoints[waypointIndex] = point;
    return waypoints;
  }

  static List<Offset> moveSegment(
    CanvasEdge edge,
    Map<String, CanvasNode> nodeMap, {
    required int segmentIndex,
    required Offset delta,
  }) {
    final route = routePointsForEdge(edge, nodeMap);
    if (segmentIndex < 0 || segmentIndex >= route.length - 1) {
      return List<Offset>.from(edge.waypoints);
    }

    final start = route[segmentIndex];
    final end = route[segmentIndex + 1];
    final isHorizontal = (end.dx - start.dx).abs() >= (end.dy - start.dy).abs();
    final normalDelta = isHorizontal
        ? Offset(0, delta.dy)
        : Offset(delta.dx, 0);
    final moved = edge.waypoints.isEmpty
        ? _generatedWaypoints(edge, nodeMap)
        : List<Offset>.from(edge.waypoints);

    const firstWaypointRouteIndex = 1;
    for (var routeIndex = 1; routeIndex < route.length - 1; routeIndex++) {
      if (routeIndex != segmentIndex && routeIndex != segmentIndex + 1) {
        continue;
      }
      final waypointIndex = routeIndex - firstWaypointRouteIndex;
      if (waypointIndex >= 0 && waypointIndex < moved.length) {
        moved[waypointIndex] += normalDelta;
      }
    }
    return moved;
  }

  static List<Offset> _routePoints(
    Offset start,
    AnchorPosition startAnchor,
    Offset end,
    AnchorPosition endAnchor,
    ConnectorRouting routing,
    List<Offset> waypoints,
  ) {
    if (waypoints.isNotEmpty || routing != ConnectorRouting.orthogonal) {
      return [start, ...waypoints, end];
    }
    return _orthogonalPoints(start, startAnchor, end, endAnchor);
  }

  static List<Offset> _orthogonalPoints(
    Offset start,
    AnchorPosition startAnchor,
    Offset end,
    AnchorPosition endAnchor,
  ) {
    final verticalAnchors = _isVertical(startAnchor) && _isVertical(endAnchor);
    final horizontalAnchors =
        _isHorizontal(startAnchor) && _isHorizontal(endAnchor);

    if (verticalAnchors) {
      if ((start.dx - end.dx).abs() < 0.1) return [start, end];
      final midY = (start.dy + end.dy) / 2;
      return [start, Offset(start.dx, midY), Offset(end.dx, midY), end];
    }
    if (horizontalAnchors) {
      if ((start.dy - end.dy).abs() < 0.1) return [start, end];
      final midX = (start.dx + end.dx) / 2;
      return [start, Offset(midX, start.dy), Offset(midX, end.dy), end];
    }

    if (_isHorizontal(startAnchor)) {
      return [start, Offset(end.dx, start.dy), end];
    }
    return [start, Offset(start.dx, end.dy), end];
  }

  static List<Offset> _generatedWaypoints(
    CanvasEdge edge,
    Map<String, CanvasNode> nodeMap,
  ) {
    final route = routePointsForEdge(
      edge.copyWith(waypoints: const []),
      nodeMap,
    );
    if (route.length < 3) return [];
    return route.sublist(1, route.length - 1);
  }

  static bool _isVertical(AnchorPosition anchor) =>
      anchor == AnchorPosition.top || anchor == AnchorPosition.bottom;

  static bool _isHorizontal(AnchorPosition anchor) => !_isVertical(anchor);

  static Offset _controlPoint(
    Offset point,
    AnchorPosition anchor,
    double dx,
    double dy,
  ) {
    switch (anchor) {
      case AnchorPosition.top:
        return Offset(point.dx, point.dy - dy);
      case AnchorPosition.right:
        return Offset(point.dx + dx, point.dy);
      case AnchorPosition.bottom:
        return Offset(point.dx, point.dy + dy);
      case AnchorPosition.left:
        return Offset(point.dx - dx, point.dy);
    }
  }
}
