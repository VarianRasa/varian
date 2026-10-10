import 'dart:math';
import 'dart:ui';
import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/drawing_payload.dart';
import '../../../domain/models/vector_path_payload.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../diagrams/domain/diagram_shape_catalog.dart';
import 'connector_router.dart';

export 'connector_router.dart' show ConnectorControlHit, ConnectorControlKind;

enum ResizeHandle {
  topLeft,
  topCenter,
  topRight,
  centerRight,
  bottomRight,
  bottomCenter,
  bottomLeft,
  centerLeft,
  startPoint,
  endPoint,
  cornerRadius,
  arcStart,
  arcSweep,
  innerRadius,
  skewHandle,
  curveControl,
  drawingPoint,
  vectorAnchor,
  vectorHandleIn,
  vectorHandleOut,
  rotation,
}

class CanvasSelectionGeometry {
  static const rotationHandleDistance = 24.0;

  const CanvasSelectionGeometry._();

  static Offset rotationHandlePosition(
    CanvasNode node, {
    required double zoom,
  }) {
    final safeZoom = zoom.isFinite && zoom > 0 ? zoom : 1.0;
    final rotation = node.rotation.isFinite ? node.rotation : 0.0;
    final center = Offset(node.width / 2, node.height / 2);
    final local = Offset(node.width / 2, -rotationHandleDistance / safeZoom);
    final offset = local - center;
    final cosine = cos(rotation);
    final sine = sin(rotation);
    return Offset(
      node.x + center.dx + offset.dx * cosine - offset.dy * sine,
      node.y + center.dy + offset.dx * sine + offset.dy * cosine,
    );
  }
}

class CanvasHitTester {
  static CanvasNode? hitTest(List<CanvasNode> nodes, Offset worldPoint) {
    final sorted = List<CanvasNode>.from(nodes)
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));

    CanvasNode? frameHit;
    for (final node in sorted) {
      if (!node.visible || node.locked) continue;
      if (!node.bounds.contains(worldPoint)) continue;
      if (node.type == NodeType.frame) {
        frameHit ??= node;
        continue;
      }
      return node;
    }
    return frameHit;
  }

  static CanvasEdge? hitTestEdge(
    List<CanvasEdge> edges,
    Map<String, CanvasNode> nodeMap,
    Offset worldPoint, {
    double tolerance = 12.0,
  }) {
    for (final edge in edges.reversed) {
      final start = ConnectorRouter.endpointPointForEdge(
        edge,
        nodeMap,
        source: true,
      );
      final end = ConnectorRouter.endpointPointForEdge(
        edge,
        nodeMap,
        source: false,
      );
      if (start == null || end == null) continue;
      final source = edge.sourceNodeId == null
          ? null
          : nodeMap[edge.sourceNodeId];
      final target = edge.targetNodeId == null
          ? null
          : nodeMap[edge.targetNodeId];
      if (source != null && !source.visible) continue;
      if (target != null && !target.visible) continue;

      final path = ConnectorRouter.routeEdge(
        start,
        edge.sourceAnchor,
        end,
        edge.targetAnchor,
        edge.routing,
        waypoints: edge.waypoints,
      );

      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        final length = metric.length;
        const sampleStep = 4.0;
        for (double d = 0; d <= length; d += sampleStep) {
          final tangent = metric.getTangentForOffset(d);
          if (tangent != null) {
            if ((tangent.position - worldPoint).distance <= tolerance) {
              return edge;
            }
          }
        }
      }
    }
    return null;
  }

  static ConnectorControlHit? hitTestConnectorControl(
    List<CanvasEdge> edges,
    Map<String, CanvasNode> nodeMap,
    Set<String> selectedEdgeIds,
    Offset worldPoint, {
    double zoom = 1.0,
  }) {
    final hitRadius = 10.0 / zoom;
    for (final edge in edges.reversed) {
      if (!selectedEdgeIds.contains(edge.id)) continue;
      final points = ConnectorRouter.routePointsForEdge(edge, nodeMap);
      if (points.length < 2) continue;

      if ((worldPoint - points.first).distance <= hitRadius) {
        return ConnectorControlHit(
          edgeId: edge.id,
          kind: ConnectorControlKind.sourceEndpoint,
        );
      }
      if ((worldPoint - points.last).distance <= hitRadius) {
        return ConnectorControlHit(
          edgeId: edge.id,
          kind: ConnectorControlKind.targetEndpoint,
        );
      }

      final labelBounds = ConnectorRouter.labelBoundsForEdge(edge, nodeMap);
      if (labelBounds != null &&
          labelBounds.inflate(hitRadius).contains(worldPoint)) {
        return ConnectorControlHit(
          edgeId: edge.id,
          kind: ConnectorControlKind.label,
        );
      }

      for (var index = 1; index < points.length - 1; index++) {
        if ((worldPoint - points[index]).distance <= hitRadius) {
          return ConnectorControlHit(
            edgeId: edge.id,
            kind: ConnectorControlKind.waypoint,
            waypointIndex: index - 1,
          );
        }
      }

      if (edge.routing != ConnectorRouting.orthogonal) continue;
      for (var index = 0; index < points.length - 1; index++) {
        final distance = _distanceToSegment(
          worldPoint,
          points[index],
          points[index + 1],
        );
        if (distance <= hitRadius) {
          return ConnectorControlHit(
            edgeId: edge.id,
            kind: ConnectorControlKind.segment,
            segmentIndex: index,
          );
        }
      }
    }
    return null;
  }

  static double _distanceToSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared == 0) return (point - start).distance;
    final projection =
        ((point - start).dx * segment.dx + (point - start).dy * segment.dy) /
        lengthSquared;
    final t = projection.clamp(0.0, 1.0);
    final closest = Offset(
      start.dx + segment.dx * t,
      start.dy + segment.dy * t,
    );
    return (point - closest).distance;
  }

  static List<CanvasNode> hitTestMarquee(
    List<CanvasNode> nodes,
    Rect worldRect,
  ) {
    return nodes.where((node) {
      if (!node.visible || node.locked) return false;
      return node.bounds.overlaps(worldRect);
    }).toList();
  }

  static (String, ResizeHandle)? hitTestHandle(
    List<CanvasNode> nodes,
    Set<String> selectedIds,
    Offset worldPoint,
    double zoom,
  ) {
    if (selectedIds.isEmpty) return null;
    final hitRadius = 8.0 / zoom;

    for (final id in selectedIds) {
      final match = nodes
          .where((n) => n.id == id && n.visible && !n.locked)
          .toList();
      if (match.isEmpty) continue;
      final node = match.first;
      final rect = Rect.fromLTWH(node.x, node.y, node.width, node.height);

      if (selectedIds.length == 1) {
        final rotationHandle = CanvasSelectionGeometry.rotationHandlePosition(
          node,
          zoom: zoom,
        );
        if ((worldPoint - rotationHandle).distance <= hitRadius) {
          return (node.id, ResizeHandle.rotation);
        }
      }

      if (node.type == NodeType.vectorPath &&
          node.payload is VectorPathPayload) {
        final vp = node.payload as VectorPathPayload;
        final vectorPoints = vp.allSubpaths.expand((subpath) => subpath);
        // Check handles first (so they have priority over anchors when offset).
        for (final bp in vectorPoints) {
          final anchor = Offset(node.x + bp.point.dx, node.y + bp.point.dy);
          if (bp.handleOut != Offset.zero &&
              (worldPoint - anchor - bp.handleOut).distance <= hitRadius) {
            return (node.id, ResizeHandle.vectorHandleOut);
          }
          if (bp.handleIn != Offset.zero &&
              (worldPoint - anchor - bp.handleIn).distance <= hitRadius) {
            return (node.id, ResizeHandle.vectorHandleIn);
          }
        }
        for (final bp in vp.allSubpaths.expand((subpath) => subpath)) {
          final anchor = Offset(node.x + bp.point.dx, node.y + bp.point.dy);
          if ((worldPoint - anchor).distance <= hitRadius) {
            return (node.id, ResizeHandle.vectorAnchor);
          }
        }
        // Fallback to bounding box handles if not hitting points directly
      }

      if (node.type == NodeType.drawing && node.payload is DrawingPayload) {
        final dp = node.payload as DrawingPayload;
        if (dp.points.isNotEmpty) {
          final start = Offset(
            node.x + dp.points.first.dx,
            node.y + dp.points.first.dy,
          );
          final end = Offset(
            node.x + dp.points.last.dx,
            node.y + dp.points.last.dy,
          );
          if ((worldPoint - start).distance <= hitRadius) {
            return (node.id, ResizeHandle.startPoint);
          }
          if ((worldPoint - end).distance <= hitRadius) {
            return (node.id, ResizeHandle.endPoint);
          }
          for (final idx in dp.controlPointIndices) {
            if (idx >= 0 && idx < dp.points.length) {
              final pt = Offset(
                node.x + dp.points[idx].dx,
                node.y + dp.points[idx].dy,
              );
              if ((worldPoint - pt).distance <= hitRadius) {
                return (node.id, ResizeHandle.drawingPoint);
              }
            }
          }
        }
        continue;
      }

      if (node.type == NodeType.line || node.type == NodeType.arrow) {
        final p = node.payload is ShapePayload
            ? node.payload as ShapePayload
            : null;
        final sx = p != null ? p.startXRatio : 0.0;
        final sy = p != null ? p.startYRatio : 0.0;
        final ex = p != null ? p.endXRatio : 1.0;
        final ey = p != null ? p.endYRatio : 1.0;
        final start = Offset(
          node.x + sx * node.width,
          node.y + sy * node.height,
        );
        final end = Offset(node.x + ex * node.width, node.y + ey * node.height);
        if ((worldPoint - start).distance <= hitRadius) {
          return (node.id, ResizeHandle.startPoint);
        }
        if ((worldPoint - end).distance <= hitRadius) {
          return (node.id, ResizeHandle.endPoint);
        }
        if (p?.lineRouting == LineRouting.curved) {
          final midX = (start.dx + end.dx) / 2;
          final midY = (start.dy + end.dy) / 2;
          final dx = end.dx - start.dx;
          final dy = end.dy - start.dy;
          final depth = p?.curveDepth ?? 0.25;
          final perpX = -dy * depth;
          final perpY = dx * depth;
          final controlPt = Offset(midX + perpX, midY + perpY);
          if ((worldPoint - controlPt).distance <= hitRadius) {
            return (node.id, ResizeHandle.curveControl);
          }
        }
        continue;
      }

      final handles = <ResizeHandle, Offset>{
        ResizeHandle.topLeft: rect.topLeft,
        ResizeHandle.topCenter: rect.topCenter,
        ResizeHandle.topRight: rect.topRight,
        ResizeHandle.centerRight: rect.centerRight,
        ResizeHandle.bottomRight: rect.bottomRight,
        ResizeHandle.bottomCenter: rect.bottomCenter,
        ResizeHandle.bottomLeft: rect.bottomLeft,
        ResizeHandle.centerLeft: rect.centerLeft,
      };

      final shapePayload = node.payload is ShapePayload
          ? node.payload as ShapePayload
          : null;
      final diagramDefinition = shapePayload == null
          ? null
          : DiagramShapeCatalog.resolve(
              shapePayload.diagramShapeId ?? 'rectangle',
            );
      final cornerHandle = diagramDefinition?.cornerRadiusHandlePosition(
        Size(node.width, node.height),
        shapePayload?.cornerRadius ?? 0.0,
      );
      if (cornerHandle != null) {
        handles[ResizeHandle.cornerRadius] = Offset(
          node.x + cornerHandle.dx,
          node.y + cornerHandle.dy,
        );
      }

      if (node.type == NodeType.ellipse && node.payload is ShapePayload) {
        final payload = node.payload as ShapePayload;
        final center = rect.center;
        Offset polar(double angle, double ratio) {
          final radians = (angle - 90.0) * pi / 180.0;
          return Offset(
            center.dx + cos(radians) * rect.width / 2 * ratio,
            center.dy + sin(radians) * rect.height / 2 * ratio,
          );
        }

        handles[ResizeHandle.arcStart] = polar(payload.startAngle, 1.0);
        handles[ResizeHandle.arcSweep] = polar(
          payload.startAngle + payload.sweepAngle,
          1.0,
        );
        handles[ResizeHandle.innerRadius] = polar(
          payload.startAngle + payload.sweepAngle / 2,
          payload.innerRadiusRatio,
        );
      } else if (node.type == NodeType.parallelogram &&
          node.payload is ShapePayload) {
        final payload = node.payload as ShapePayload;
        final skewOffset = (payload.skewRatio * node.width).clamp(
          -node.width * 0.48,
          node.width * 0.48,
        );
        final baseTopLeftX = skewOffset >= 0 ? skewOffset : 0.0;
        handles[ResizeHandle.skewHandle] = Offset(
          node.x + baseTopLeftX,
          node.y,
        );
      }

      for (final entry in handles.entries) {
        if ((worldPoint - entry.value).distance <= hitRadius) {
          return (node.id, entry.key);
        }
      }
    }
    return null;
  }
}
