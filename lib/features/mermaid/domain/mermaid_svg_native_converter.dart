import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../../domain/models/vector_path_payload.dart';
import 'mermaid_conversion.dart';
import 'mermaid_renderer.dart';
import 'mermaid_svg_sanitizer.dart';

/// Converts the passive SVG returned by Mermaid into ordinary canvas objects.
///
/// Mermaid has several grammars and adds new ones regularly. SVG is the stable
/// boundary shared by the Web and native renderers, so this converter keeps
/// every visible primitive editable without duplicating Mermaid's parser.
class MermaidSvgNativeConverter {
  MermaidSvgNativeConverter._();

  static MermaidConversionResult convert(CanvasNode sourceNode, String svg) {
    if (sourceNode.type != NodeType.mermaid ||
        sourceNode.payload is! MermaidPayload) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'INVALID_CONVERSION_SOURCE',
          message: 'Only a Mermaid source node can be converted.',
        ),
      );
    }

    final sourceDiagnostic = MermaidSourceLimits.validate(
      (sourceNode.payload as MermaidPayload).source,
    );
    if (sourceDiagnostic != null) {
      return MermaidConversionResult.failure(sourceDiagnostic);
    }

    try {
      final normalized = MermaidSvgSanitizer.normalizeForFlutter(svg);
      final document = XmlDocument.parse(normalized);
      final root = document.rootElement;
      final mapper = _SvgMapper.fromRoot(root, sourceNode);
      final primitives = <_SvgPrimitive>[];
      _SvgWalker(mapper: mapper, primitives: primitives).walk(root);
      return _buildResult(
        sourceNode,
        primitives,
        mapper,
        renderedSvg: normalized,
      );
    } on MermaidSvgSecurityException catch (error) {
      return MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: error.code,
          message: 'Mermaid renderer returned unsafe SVG output.',
        ),
      );
    } on _SvgConversionFailure catch (error) {
      return MermaidConversionResult.failure(error.diagnostic);
    } catch (_) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'SVG_NATIVE_CONVERSION_ERROR',
          message:
              'The Mermaid preview could not be converted to native objects.',
        ),
      );
    }
  }

  static MermaidConversionResult _buildResult(
    CanvasNode sourceNode,
    List<_SvgPrimitive> primitives,
    _SvgMapper mapper, {
    required String renderedSvg,
  }) {
    if (primitives.isEmpty) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'EMPTY_NATIVE_DIAGRAM',
          message: 'The Mermaid preview contains no editable geometry.',
        ),
      );
    }

    for (var index = 0; index < primitives.length; index++) {
      primitives[index].order = index;
    }
    final nodes = <CanvasNode>[];
    final nodeKeys = <String, String>{};
    final primitiveNodes = <_SvgPrimitive, CanvasNode>{};
    final pendingStrokes = <_SvgPrimitive>[];
    final pendingTexts = <_SvgPrimitive>[];

    for (final primitive in primitives) {
      switch (primitive.kind) {
        case _SvgPrimitiveKind.text:
          pendingTexts.add(primitive);
          continue;
        case _SvgPrimitiveKind.line:
        case _SvgPrimitiveKind.vector:
          pendingStrokes.add(primitive);
          continue;
        case _SvgPrimitiveKind.image:
          nodes.add(_toImageNode(sourceNode, primitive, nodes.length));
          continue;
        case _SvgPrimitiveKind.rectangle:
        case _SvgPrimitiveKind.ellipse:
          final node = _toShapeNode(
            sourceNode,
            primitive,
            nodes.length,
            mapper,
          );
          nodes.add(node);
          primitiveNodes[primitive] = node;
          _registerNodeKeys(nodeKeys, primitive, node);
          continue;
      }
    }

    final edges = <CanvasEdge>[];
    final warnings = <MermaidDiagnostic>[];
    for (final stroke in pendingStrokes) {
      final endpoints = _resolveEndpoints(stroke, nodeKeys, nodes);
      if (stroke.edgeCandidate &&
          endpoints != null &&
          !stroke.hasCurve &&
          !_hasUnsupportedMarker(stroke)) {
        final sourceNodeForEdge = nodes.firstWhere(
          (node) => node.id == endpoints.$1,
        );
        final targetNodeForEdge = nodes.firstWhere(
          (node) => node.id == endpoints.$2,
        );
        edges.add(
          _toCanvasEdge(
            sourceNode,
            stroke,
            sourceNodeForEdge,
            targetNodeForEdge,
            mapper,
            edges.length,
          ),
        );
        continue;
      }

      if (stroke.edgeCandidate && endpoints == null) {
        warnings.add(
          const MermaidDiagnostic(
            code: 'EDGE_ENDPOINT_UNRESOLVED',
            message:
                'A Mermaid connector was kept as an editable path because its endpoints were not identifiable.',
            severity: MermaidDiagnosticSeverity.warning,
          ),
        );
      }
      final node = _toStrokeNode(sourceNode, stroke, nodes.length, mapper);
      nodes.add(node);
    }

    for (final text in pendingTexts) {
      final node = _toTextNode(sourceNode, text, nodes.length, mapper);
      if (node != null) nodes.add(node);
    }

    if (nodes.isEmpty && edges.isEmpty) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'EMPTY_NATIVE_DIAGRAM',
          message: 'The Mermaid preview contains no editable geometry.',
        ),
      );
    }
    if (nodes.length + edges.length > MermaidSourceLimits.maxGeneratedObjects) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'GENERATED_OBJECTS_TOO_MANY',
          message: 'The Mermaid diagram contains too many native objects.',
        ),
      );
    }

    final payload = sourceNode.payload as MermaidPayload;
    return MermaidConversionResult(
      nodes: List<CanvasNode>.unmodifiable(nodes),
      edges: List<CanvasEdge>.unmodifiable(edges),
      diagramType: normalizeMermaidDiagramType(
        payload.diagramType == 'unknown'
            ? detectMermaidDiagramType(payload.source)
            : payload.diagramType,
      ),
      warnings: List<MermaidDiagnostic>.unmodifiable(warnings.take(32)),
      renderedSvg: renderedSvg,
    );
  }

  static void _registerNodeKeys(
    Map<String, String> nodeKeys,
    _SvgPrimitive primitive,
    CanvasNode node,
  ) {
    for (final key in _keyAliases(primitive.key)) {
      // Repeated aliases are common in sequence diagrams. Keep the first
      // registration; route geometry resolves ambiguous connector endpoints.
      nodeKeys.putIfAbsent(key, () => node.id);
    }
  }

  static Set<String> _keyAliases(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    final value = raw.trim();
    final normalized = _normalizeKey(value);
    final aliases = <String>{value, normalized};
    final withoutRendererPrefix = value.replaceFirst(
      RegExp(
        r'^(?:merman|diagram|node|state|flowchart|graph|class|er|sequence)-',
        caseSensitive: false,
      ),
      '',
    );
    aliases.add(withoutRendererPrefix);
    aliases.add(_normalizeKey(withoutRendererPrefix));
    return aliases.where((alias) => alias.isNotEmpty).toSet();
  }

  static String _normalizeKey(String value) {
    var result = value.trim();
    result = result.replaceFirst(
      RegExp(
        r'^(?:merman|diagram|node|flowchart|graph|state|class|er|sequence|journey|gantt|gitgraph|mindmap|timeline|requirement|quadrantchart|xychart|sankey|block|architecture|packet|kanban|radar|treemap|venn|zenuml)[-_]',
        caseSensitive: false,
      ),
      '',
    );
    result = result.replaceFirst(RegExp(r'-\d+$'), '');
    return result;
  }

  static (String, String)? _resolveEndpoints(
    _SvgPrimitive primitive,
    Map<String, String> nodeKeys,
    List<CanvasNode> nodes,
  ) {
    final route = primitive.metadataPoints ?? primitive.pathPoints;
    if (route.length >= 2 && nodes.isNotEmpty) {
      final routeSource = _nearestNode(route.first, nodes);
      final routeTarget = _nearestNode(
        route.last,
        nodes,
        excluding: routeSource,
      );
      if (routeSource != null && routeTarget != null) {
        return (routeSource.id, routeTarget.id);
      }
    }

    final source = _resolveKey(primitive.sourceKey, nodeKeys);
    final target = _resolveKey(primitive.targetKey, nodeKeys);
    if (source != null && target != null && source != target) {
      return (source, target);
    }

    final rawId = primitive.id ?? primitive.containerId;
    if (rawId != null) {
      var body = rawId
          .replaceFirst(RegExp(r'^(?:L|edge|message)-'), '')
          .replaceFirst(RegExp(r'-\d+$'), '');
      final known = nodeKeys.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final sourceKey in known) {
        if (!body.startsWith('$sourceKey-')) continue;
        final targetKey = body.substring(sourceKey.length + 1);
        final sourceId = nodeKeys[sourceKey];
        final targetId = _resolveKey(targetKey, nodeKeys);
        if (sourceId != null && targetId != null && sourceId != targetId) {
          return (sourceId, targetId);
        }
      }
    }

    if (route.length < 2 || nodes.isEmpty) return null;
    final start = route.first;
    final end = route.last;
    final sourceNode = _nearestNode(start, nodes);
    final targetNode = _nearestNode(end, nodes, excluding: sourceNode);
    if (sourceNode == null || targetNode == null) return null;
    return (sourceNode.id, targetNode.id);
  }

  static CanvasNode? _nearestNode(
    Offset point,
    List<CanvasNode> nodes, {
    CanvasNode? excluding,
  }) {
    CanvasNode? nearest;
    var nearestDistance = double.infinity;
    var secondNearestDistance = double.infinity;
    for (final node in nodes) {
      if (node == excluding) continue;
      final distance = _distanceToRect(point, node.bounds);
      if (distance < nearestDistance) {
        secondNearestDistance = nearestDistance;
        nearest = node;
        nearestDistance = distance;
      } else if (distance < secondNearestDistance) {
        secondNearestDistance = distance;
      }
    }
    if (nearest == null ||
        nearestDistance > MermaidSourceLimits.maxSvgEndpointDistance ||
        (secondNearestDistance.isFinite &&
            secondNearestDistance - nearestDistance <
                MermaidSourceLimits.maxSvgEndpointAmbiguity)) {
      return null;
    }
    return nearest;
  }

  static double _distanceToRect(Offset point, Rect rect) {
    final dx = math.max(
      rect.left - point.dx,
      math.max(0, point.dx - rect.right),
    );
    final dy = math.max(
      rect.top - point.dy,
      math.max(0, point.dy - rect.bottom),
    );
    return math.sqrt(dx * dx + dy * dy);
  }

  static String? _resolveKey(String? raw, Map<String, String> nodeKeys) {
    if (raw == null || raw.trim().isEmpty) return null;
    for (final key in _keyAliases(raw)) {
      final resolved = nodeKeys[key];
      if (resolved != null) return resolved;
    }
    return null;
  }

  static CanvasNode _toShapeNode(
    CanvasNode sourceNode,
    _SvgPrimitive primitive,
    int index,
    _SvgMapper mapper,
  ) {
    final bounds = _bounds(primitive.points);
    final width = math.max(1.0, bounds.width);
    final height = math.max(1.0, bounds.height);
    final style = primitive.style;
    final type = primitive.kind == _SvgPrimitiveKind.ellipse
        ? NodeType.ellipse
        : NodeType.rectangle;
    return CanvasNode(
      id: _nodeId(sourceNode, index),
      type: type,
      x: bounds.left,
      y: bounds.top,
      width: width,
      height: height,
      zIndex: sourceNode.zIndex + primitive.order + 1,
      parentId: sourceNode.parentId,
      mermaidSourceId: sourceNode.id,
      opacity: style.opacity,
      payload: ShapePayload(
        fill: style.fillColor ?? Colors.transparent,
        fillGradientEnd: style.fillGradientEnd,
        fillType: style.fillType,
        fillOpacity: style.fillOpacity,
        stroke: style.strokeColor ?? Colors.transparent,
        strokeWidth: style.strokeWidth * mapper.scale,
        cornerRadius: style.cornerRadius * mapper.scale,
        strokeStyle: style.strokeStyle,
      ),
    );
  }

  static CanvasNode _toImageNode(
    CanvasNode sourceNode,
    _SvgPrimitive primitive,
    int index,
  ) {
    final bounds = _bounds(primitive.points);
    return CanvasNode(
      id: _nodeId(sourceNode, index),
      type: NodeType.image,
      x: bounds.left,
      y: bounds.top,
      width: math.max(1.0, bounds.width),
      height: math.max(1.0, bounds.height),
      zIndex: sourceNode.zIndex + primitive.order + 1,
      parentId: sourceNode.parentId,
      mermaidSourceId: sourceNode.id,
      opacity: primitive.style.opacity,
      payload: ImagePayload(url: primitive.imageHref, fit: 'contain'),
    );
  }

  static CanvasNode _toStrokeNode(
    CanvasNode sourceNode,
    _SvgPrimitive primitive,
    int index,
    _SvgMapper mapper,
  ) {
    final points = primitive.pathPoints;
    final bounds = _pathBounds(primitive);
    final width = math.max(1.0, bounds.width);
    final height = math.max(1.0, bounds.height);
    final sourceSubpaths = primitive.subpaths.isEmpty
        ? <List<_PathPoint>>[primitive.path]
        : primitive.subpaths;
    final localSubpaths = sourceSubpaths
        .map(
          (subpath) => subpath
              .map(
                (point) => BezierPoint(
                  point: point.point - bounds.topLeft,
                  handleIn: point.handleIn,
                  handleOut: point.handleOut,
                  type:
                      point.handleIn == Offset.zero &&
                          point.handleOut == Offset.zero
                      ? PointType.corner
                      : PointType.disconnected,
                ),
              )
              .toList(growable: false),
        )
        .toList(growable: false);
    final localPoints = localSubpaths.isEmpty
        ? const <BezierPoint>[]
        : localSubpaths.first;
    final style = primitive.style;
    if (primitive.kind == _SvgPrimitiveKind.line) {
      final start = points.first - bounds.topLeft;
      final end = points.last - bounds.topLeft;
      return CanvasNode(
        id: _nodeId(sourceNode, index),
        type: primitive.endMarker == LineMarker.arrow
            ? NodeType.arrow
            : NodeType.line,
        x: bounds.left,
        y: bounds.top,
        width: width,
        height: height,
        zIndex: sourceNode.zIndex + primitive.order + 1,
        parentId: sourceNode.parentId,
        mermaidSourceId: sourceNode.id,
        opacity: style.opacity,
        payload: ShapePayload(
          fill: Colors.transparent,
          stroke: style.strokeColor ?? Colors.transparent,
          strokeWidth: style.strokeWidth * mapper.scale,
          strokeStyle: style.strokeStyle,
          startMarker: primitive.startMarker,
          endMarker: primitive.endMarker,
          startXRatio: width <= 1 ? 0 : start.dx / width,
          startYRatio: height <= 1 ? 0 : start.dy / height,
          endXRatio: width <= 1 ? 0 : end.dx / width,
          endYRatio: height <= 1 ? 0 : end.dy / height,
          lineRouting: primitive.hasCurve
              ? LineRouting.curved
              : LineRouting.straight,
        ),
      );
    }

    return CanvasNode(
      id: _nodeId(sourceNode, index),
      type: NodeType.vectorPath,
      x: bounds.left,
      y: bounds.top,
      width: width,
      height: height,
      zIndex: sourceNode.zIndex + primitive.order + 1,
      parentId: sourceNode.parentId,
      mermaidSourceId: sourceNode.id,
      opacity: style.opacity,
      payload: VectorPathPayload(
        points: localPoints,
        isClosed: primitive.closed,
        subpaths: localSubpaths,
        subpathClosed: primitive.subpathClosed,
        fillRule: primitive.style['fill-rule']?.toLowerCase() == 'evenodd'
            ? VectorFillRule.evenOdd
            : VectorFillRule.nonZero,
        fill:
            _applyOpacity(style.fillColor, style.fillOpacity) ??
            Colors.transparent,
        stroke: style.strokeColor ?? Colors.transparent,
        strokeWidth: style.strokeWidth * mapper.scale,
        strokeCap: style.strokeCap,
        strokeJoin: style.strokeJoin,
        dashPattern: style.dashPattern
            .map((value) => value * mapper.scale)
            .toList(growable: false),
        dashOffset: style.dashOffset * mapper.scale,
        isGradientFill: style.hasGradient && primitive.closed,
        gradientType: style.fillType,
        gradientEndColor:
            _applyOpacity(style.fillGradientEnd, style.fillOpacity) ??
            _applyOpacity(style.fillColor, style.fillOpacity) ??
            Colors.transparent,
      ),
    );
  }

  static CanvasNode? _toTextNode(
    CanvasNode sourceNode,
    _SvgPrimitive primitive,
    int index,
    _SvgMapper mapper,
  ) {
    final text = primitive.text?.trim();
    if (text == null || text.isEmpty || primitive.points.isEmpty) return null;
    final style = primitive.style;
    final fontSize = math.max(6.0, style.fontSize * mapper.scale);
    final measured = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontSize: fontSize,
          fontWeight: style.fontWeight,
          fontStyle: style.fontStyle,
          letterSpacing: style.letterSpacing * mapper.scale,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: primitive.textAnchor,
    )..layout();
    final width = math.max(1.0, measured.width);
    final height = math.max(fontSize * 1.25, measured.height);
    final anchor = primitive.points.first;
    final x = switch (primitive.textAnchor) {
      TextAlign.center => anchor.dx - width / 2,
      TextAlign.right => anchor.dx - width,
      _ => anchor.dx,
    };
    final baseline = primitive.dominantBaseline?.toLowerCase();
    final y = switch (baseline) {
      'middle' || 'central' => anchor.dy - height / 2,
      'hanging' || 'text-before-edge' || 'before-edge' => anchor.dy,
      'text-after-edge' || 'after-edge' => anchor.dy - height,
      _ => anchor.dy - fontSize,
    };
    return CanvasNode(
      id: _nodeId(sourceNode, index),
      type: NodeType.text,
      x: x,
      y: y,
      width: width,
      height: height,
      zIndex: sourceNode.zIndex + primitive.order + 1,
      parentId: sourceNode.parentId,
      mermaidSourceId: sourceNode.id,
      opacity: style.opacity,
      payload: TextPayload(
        text: text,
        fontSize: fontSize,
        fontWeight: style.fontWeight,
        textAlign: primitive.textAnchor,
        verticalAlign: TextVerticalAlign.top,
        color:
            _applyOpacity(
              style.fillColor ?? const Color(0xFF1F2937),
              style.fillOpacity,
            ) ??
            const Color(0xFF1F2937),
        strokeColor: style.strokeColor,
        strokeWidth: style.strokeColor == null
            ? 0.0
            : style.strokeWidth * mapper.scale,
        fontFamily: style.fontFamily,
        fontStyle: style.fontStyle,
        letterSpacing: style.letterSpacing * mapper.scale,
        lineHeight: 1.25,
        sizeMode: TextSizeMode.autoWidth,
      ),
    );
  }

  static CanvasEdge _toCanvasEdge(
    CanvasNode sourceNode,
    _SvgPrimitive primitive,
    CanvasNode source,
    CanvasNode target,
    _SvgMapper mapper,
    int index,
  ) {
    final route = primitive.metadataPoints ?? primitive.pathPoints;
    final start = route.first;
    final end = route.last;
    final sourceAnchor = _nearestAnchor(source, start);
    final targetAnchor = _nearestAnchor(target, end);
    final isCurved = primitive.hasCurve;
    final waypoints = isCurved
        ? const <Offset>[]
        : route.length > 2
        ? route
              .sublist(1, route.length - 1)
              .take(CanvasEdge.maxWaypoints)
              .toList(growable: false)
        : const <Offset>[];
    final routing = isCurved
        ? ConnectorRouting.curved
        : waypoints.isEmpty
        ? ConnectorRouting.straight
        : ConnectorRouting.orthogonal;
    return CanvasEdge(
      id: _edgeId(sourceNode, index),
      sourceNodeId: source.id,
      targetNodeId: target.id,
      sourceAnchor: sourceAnchor,
      targetAnchor: targetAnchor,
      sourcePoint: start,
      targetPoint: end,
      routing: routing,
      strokeColor: primitive.style.strokeColor ?? const Color(0xFF64748B),
      strokeWidth: primitive.style.strokeWidth * mapper.scale,
      strokeStyle: primitive.style.strokeStyle,
      startMarker: primitive.startMarker,
      endMarker: primitive.endMarker,
      waypoints: waypoints,
      mermaidSourceId: sourceNode.id,
    );
  }

  static AnchorPosition _nearestAnchor(CanvasNode node, Offset point) {
    final candidates = {
      AnchorPosition.top: Offset(node.x + node.width / 2, node.y),
      AnchorPosition.right: Offset(
        node.x + node.width,
        node.y + node.height / 2,
      ),
      AnchorPosition.bottom: Offset(
        node.x + node.width / 2,
        node.y + node.height,
      ),
      AnchorPosition.left: Offset(node.x, node.y + node.height / 2),
    };
    return candidates.entries
        .reduce(
          (best, entry) =>
              (entry.value - point).distance < (best.value - point).distance
              ? entry
              : best,
        )
        .key;
  }

  static Rect _pathBounds(_SvgPrimitive primitive) {
    final subpaths = primitive.subpaths.isEmpty
        ? <List<_PathPoint>>[primitive.path]
        : primitive.subpaths;
    final path = Path();
    for (var subpathIndex = 0; subpathIndex < subpaths.length; subpathIndex++) {
      final subpath = subpaths[subpathIndex];
      if (subpath.isEmpty) continue;
      path.moveTo(subpath.first.point.dx, subpath.first.point.dy);
      for (var index = 1; index < subpath.length; index++) {
        final previous = subpath[index - 1];
        final current = subpath[index];
        final cp1 = previous.point + previous.handleOut;
        final cp2 = current.point + current.handleIn;
        path.cubicTo(
          cp1.dx,
          cp1.dy,
          cp2.dx,
          cp2.dy,
          current.point.dx,
          current.point.dy,
        );
      }
      final closed = subpathIndex < primitive.subpathClosed.length
          ? primitive.subpathClosed[subpathIndex]
          : primitive.closed;
      if (closed && subpath.length > 1) {
        final previous = subpath.last;
        final current = subpath.first;
        final cp1 = previous.point + previous.handleOut;
        final cp2 = current.point + current.handleIn;
        path.cubicTo(
          cp1.dx,
          cp1.dy,
          cp2.dx,
          cp2.dy,
          current.point.dx,
          current.point.dy,
        );
      }
    }
    final bounds = path.getBounds();
    return bounds.isEmpty ? _bounds(primitive.pathPoints) : bounds;
  }

  static Rect _bounds(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx;
    var minY = points.first.dy;
    var maxX = minX;
    var maxY = minY;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static String _nodeId(CanvasNode source, int index) =>
      '${source.id}__mermaid_node_$index';

  static String _edgeId(CanvasNode source, int index) =>
      '${source.id}__mermaid_edge_$index';
}

/// Async dispatcher that projects the same rendered SVG used by the preview.
class MermaidNativeConverter {
  final MermaidRenderer renderer;

  MermaidNativeConverter({required this.renderer});

  Future<MermaidConversionResult> convert(
    CanvasNode sourceNode, {
    String? cachedSvg,
  }) async {
    if (sourceNode.type != NodeType.mermaid ||
        sourceNode.payload is! MermaidPayload) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'INVALID_CONVERSION_SOURCE',
          message: 'Only a Mermaid source node can be converted.',
        ),
      );
    }

    final payload = sourceNode.payload as MermaidPayload;
    final sourceDiagnostic = MermaidSourceLimits.validate(payload.source);
    if (sourceDiagnostic != null) {
      return MermaidConversionResult.failure(sourceDiagnostic);
    }

    final svg = cachedSvg;
    if (svg != null && svg.isNotEmpty) {
      final cached = MermaidSvgNativeConverter.convert(sourceNode, svg);
      if (cached.isSuccess) return cached;
    }

    late final MermaidRenderResult rendered;
    try {
      rendered = await renderer
          .render(
            payload.source,
            config: MermaidRenderConfig(
              theme: payload.theme,
              direction: payload.direction,
              overrides: payload.config,
            ),
          )
          .timeout(const Duration(seconds: 10));
    } on Exception catch (_) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'NATIVE_CONVERSION_RENDER_ERROR',
          message: 'The Mermaid diagram could not be rendered for conversion.',
        ),
      );
    }
    if (rendered.svg == null || rendered.diagnostic != null) {
      return MermaidConversionResult.failure(
        rendered.diagnostic ??
            const MermaidDiagnostic(
              code: 'NATIVE_CONVERSION_RENDER_ERROR',
              message:
                  'The Mermaid diagram could not be rendered for conversion.',
            ),
      );
    }
    return MermaidSvgNativeConverter.convert(sourceNode, rendered.svg!);
  }
}

class _SvgWalker {
  final _SvgMapper mapper;
  final List<_SvgPrimitive> primitives;
  final Map<String, _SvgGradient> _gradients = <String, _SvgGradient>{};
  final Map<String, XmlElement> _definitions = <String, XmlElement>{};
  final Map<String, XmlElement> _markers = <String, XmlElement>{};
  var _useExpansions = 0;

  _SvgWalker({required this.mapper, required this.primitives});

  void walk(XmlElement root) {
    _collectGradients(root);
    _collectDefinitions(root);
    _visit(
      root,
      const _Affine.identity(),
      const _SvgStyle(),
      null,
      const <String>{},
      false,
      true,
      const <String>{},
    );
  }

  void _collectDefinitions(XmlElement root) {
    for (final element in root.descendants.whereType<XmlElement>()) {
      final id = element.getAttribute('id')?.trim();
      if (id == null ||
          id.isEmpty ||
          _definitions.length >= MermaidSourceLimits.maxSvgElements) {
        continue;
      }
      final name = element.name.local;
      if (name == 'marker') {
        _markers.putIfAbsent(id, () => element);
      } else if (name == 'symbol' ||
          name == 'g' ||
          name == 'path' ||
          name == 'rect' ||
          name == 'circle' ||
          name == 'ellipse' ||
          name == 'line' ||
          name == 'polygon' ||
          name == 'polyline' ||
          name == 'image' ||
          name == 'text') {
        _definitions.putIfAbsent(id, () => element);
      }
    }
  }

  void _collectGradients(XmlElement root) {
    for (final element in root.descendants.whereType<XmlElement>()) {
      final type = switch (element.name.local) {
        'linearGradient' => FillType.linearGradient,
        'radialGradient' => FillType.radialGradient,
        _ => null,
      };
      final id = element.getAttribute('id')?.trim();
      if (type == null || id == null || id.isEmpty) continue;
      final colors = <Color>[];
      for (final stop in element.children.whereType<XmlElement>()) {
        if (stop.name.local != 'stop') continue;
        final style = const _SvgStyle().merge(stop);
        final color = _parseColor(
          stop.getAttribute('stop-color') ?? style['stop-color'],
        );
        if (color == null) continue;
        final opacity =
            (_number(
                      stop.getAttribute('stop-opacity') ??
                          style['stop-opacity'],
                    ) ??
                    1.0)
                .clamp(0.0, 1.0);
        colors.add(color.withValues(alpha: color.a * opacity));
      }
      if (colors.isNotEmpty) {
        _gradients[id] = _SvgGradient(type: type, colors: colors);
      }
    }
  }

  _SvgStyle _resolveStyle(_SvgStyle style) {
    final rawFill = style['fill']?.trim() ?? '';
    final match = RegExp(
      r'^url\(\s*#([A-Za-z0-9_.:-]+)\s*\)$',
    ).firstMatch(rawFill);
    return style.copyWithGradient(
      match == null ? null : _gradients[match.group(1)],
    );
  }

  void _visit(
    XmlElement element,
    _Affine parentTransform,
    _SvgStyle parentStyle,
    String? containerId,
    Set<String> parentClasses,
    bool inDefs,
    bool isRoot,
    Set<String> useStack,
  ) {
    final name = element.name.local;
    if (inDefs || name == 'defs') return;
    if (name == 'style' || name == 'tspan' || name == 'title') return;

    final style = _resolveStyle(parentStyle.merge(element));
    var transform = parentTransform.multiply(
      _Affine.fromSvgTransform(element.getAttribute('transform')),
    );
    if (name == 'svg' && !isRoot) {
      transform = transform.multiply(_nestedSvgViewportTransform(element));
    }
    final id =
        element.getAttribute('id') ??
        element.getAttribute('data-id') ??
        containerId;
    final key = element.getAttribute('data-id') ?? containerId ?? id;
    final classes = <String>{
      ...parentClasses,
      ...(element.getAttribute('class') ?? '')
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty),
    };
    final edgeCandidate =
        classes.any((value) => value.toLowerCase().contains('edge')) ||
        (id?.toLowerCase().startsWith('l-') ?? false) ||
        (id?.toLowerCase().startsWith('edge-') ?? false) ||
        element.getAttribute('data-edge')?.toLowerCase() == 'true' ||
        element.getAttribute('data-et')?.toLowerCase() == 'edge' ||
        element.getAttribute('data-source-id') != null ||
        element.getAttribute('data-source') != null ||
        element.getAttribute('data-from') != null;
    final routePoints = _readRoutePoints(element, transform);

    switch (name) {
      case 'svg':
      case 'g':
        for (final child in element.children.whereType<XmlElement>()) {
          _visit(child, transform, style, key, classes, false, false, useStack);
        }
        return;
      case 'use':
        _visitUse(element, transform, style, id, classes, useStack);
        return;
      case 'image':
        _addImage(element, transform, style, id, edgeCandidate);
        return;
      case 'rect':
        _addRect(element, transform, style, id, classes, edgeCandidate);
        return;
      case 'ellipse':
      case 'circle':
        _addEllipse(element, transform, style, id, classes, edgeCandidate);
        return;
      case 'line':
        _addLine(element, transform, style, id, edgeCandidate, routePoints);
        return;
      case 'polyline':
      case 'polygon':
        _addPolygon(
          element,
          transform,
          style,
          id,
          edgeCandidate,
          routePoints,
          closed: name == 'polygon',
        );
        return;
      case 'path':
        _addPath(element, transform, style, id, edgeCandidate, routePoints);
        return;
      case 'text':
        _addText(element, transform, style, id);
        return;
      case 'marker':
      case 'symbol':
      case 'clipPath':
      case 'mask':
      case 'filter':
      case 'feDropShadow':
      case 'linearGradient':
      case 'radialGradient':
      case 'stop':
      case 'switch':
        // Definition elements affect rendering but do not represent a
        // standalone editable object in the canvas.
        return;
      default:
        throw _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_ELEMENT_NOT_SUPPORTED',
            message: 'Mermaid SVG element "$name" cannot be converted safely.',
          ),
        );
    }
  }

  void _visitUse(
    XmlElement element,
    _Affine transform,
    _SvgStyle style,
    String? containerId,
    Set<String> classes,
    Set<String> useStack,
  ) {
    final rawHref =
        element.getAttribute('href') ?? element.getAttribute('xlink:href');
    if (rawHref == null || !rawHref.startsWith('#') || rawHref.length <= 1) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_USE_INVALID',
          message: 'Mermaid SVG use reference is invalid.',
        ),
      );
    }
    final targetId = rawHref.substring(1);
    final target = _definitions[targetId];
    if (target == null || useStack.contains(targetId)) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_USE_RECURSIVE',
          message: 'Mermaid SVG use reference is unresolved or recursive.',
        ),
      );
    }
    if (useStack.length >= MermaidSourceLimits.maxSvgUseDepth ||
        ++_useExpansions > MermaidSourceLimits.maxSvgUseExpansions) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_USE_TOO_COMPLEX',
          message: 'Mermaid SVG use expansion is too complex.',
        ),
      );
    }

    final x = _number(element.getAttribute('x')) ?? 0;
    final y = _number(element.getAttribute('y')) ?? 0;
    final targetStyle = _resolveStyle(style.merge(target));
    final targetClasses = <String>{
      ...classes,
      ...(target.getAttribute('class') ?? '')
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty),
    };
    var expansionTransform = transform.multiply(_Affine(1, 0, 0, 1, x, y));
    if (target.name.local == 'symbol') {
      final viewBox = _numberList(target.getAttribute('viewBox') ?? '');
      if (viewBox.length != 4 || viewBox[2] <= 0 || viewBox[3] <= 0) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_USE_VIEWBOX_INVALID',
            message: 'Mermaid SVG symbol has invalid viewport dimensions.',
          ),
        );
      }
      final width =
          _number(element.getAttribute('width')) ??
          _number(target.getAttribute('width')) ??
          viewBox[2];
      final height =
          _number(element.getAttribute('height')) ??
          _number(target.getAttribute('height')) ??
          viewBox[3];
      if (width <= 0 || height <= 0) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_USE_VIEWPORT_INVALID',
            message: 'Mermaid SVG use viewport is invalid.',
          ),
        );
      }
      final fit = _fitSvgViewport(
        viewportWidth: width,
        viewportHeight: height,
        viewBoxX: viewBox[0],
        viewBoxY: viewBox[1],
        viewBoxWidth: viewBox[2],
        viewBoxHeight: viewBox[3],
        preserveAspectRatio: target.getAttribute('preserveAspectRatio'),
      );
      expansionTransform = transform.multiply(
        _Affine(fit.scaleX, 0, 0, fit.scaleY, x + fit.offsetX, y + fit.offsetY),
      );
    }

    final nextStack = {...useStack, targetId};
    if (target.name.local == 'symbol') {
      for (final child in target.children.whereType<XmlElement>()) {
        _visit(
          child,
          expansionTransform,
          targetStyle,
          targetId,
          targetClasses,
          false,
          false,
          nextStack,
        );
      }
    } else {
      _visit(
        target,
        expansionTransform,
        targetStyle,
        containerId,
        targetClasses,
        false,
        false,
        nextStack,
      );
    }
  }

  _Affine _nestedSvgViewportTransform(XmlElement element) {
    final x = _number(element.getAttribute('x')) ?? 0;
    final y = _number(element.getAttribute('y')) ?? 0;
    final rawViewBox = element.getAttribute('viewBox');
    final values = _numberList(rawViewBox ?? '');
    if (values.isEmpty) return _Affine(1, 0, 0, 1, x, y);
    if (values.length != 4) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_VIEWBOX_INVALID',
          message: 'Mermaid nested SVG has invalid dimensions.',
        ),
      );
    }
    final width = _number(element.getAttribute('width')) ?? values[2];
    final height = _number(element.getAttribute('height')) ?? values[3];
    final fit = _fitSvgViewport(
      viewportWidth: width,
      viewportHeight: height,
      viewBoxX: values[0],
      viewBoxY: values[1],
      viewBoxWidth: values[2],
      viewBoxHeight: values[3],
      preserveAspectRatio: element.getAttribute('preserveAspectRatio'),
    );
    return _Affine(
      fit.scaleX,
      0,
      0,
      fit.scaleY,
      x + fit.offsetX,
      y + fit.offsetY,
    );
  }

  List<Offset>? _readRoutePoints(XmlElement element, _Affine transform) {
    final raw = element.getAttribute('data-points');
    if (raw == null) return null;
    if (raw.length > MermaidSourceLimits.maxSvgEdgePointsBytes) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_EDGE_POINTS_INVALID',
          message: 'Mermaid connector point metadata is too large.',
        ),
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      try {
        final normalized = raw
            .replaceAll(RegExp(r'\s+'), '')
            .replaceAll('-', '+')
            .replaceAll('_', '/');
        decoded = jsonDecode(utf8.decode(base64Decode(normalized)));
      } catch (_) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_EDGE_POINTS_INVALID',
            message: 'Mermaid connector point metadata is invalid.',
          ),
        );
      }
    }

    final pointsValue = decoded is Map ? decoded['points'] : decoded;
    if (pointsValue is! List ||
        pointsValue.length < 2 ||
        pointsValue.length > MermaidSourceLimits.maxSvgEdgePoints) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_EDGE_POINTS_INVALID',
          message: 'Mermaid connector point metadata is invalid.',
        ),
      );
    }

    final points = <Offset>[];
    for (final rawPoint in pointsValue) {
      double? x;
      double? y;
      if (rawPoint is Map) {
        x = (rawPoint['x'] as num?)?.toDouble();
        y = (rawPoint['y'] as num?)?.toDouble();
      } else if (rawPoint is List && rawPoint.length == 2) {
        x = (rawPoint[0] as num?)?.toDouble();
        y = (rawPoint[1] as num?)?.toDouble();
      }
      if (x == null ||
          y == null ||
          !x.isFinite ||
          !y.isFinite ||
          x.abs() > MermaidSourceLimits.maxSvgCoordinate ||
          y.abs() > MermaidSourceLimits.maxSvgCoordinate) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_EDGE_POINTS_INVALID',
            message: 'Mermaid connector point metadata is invalid.',
          ),
        );
      }
      points.add(mapper.world(transform.apply(Offset(x, y))));
    }
    return points;
  }

  static String? _endpointKey(XmlElement element, {required bool source}) {
    final names = source
        ? const ['data-source-id', 'data-source', 'data-from']
        : const ['data-target-id', 'data-target', 'data-to'];
    for (final name in names) {
      final value = element.getAttribute(name)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  void _addImage(
    XmlElement element,
    _Affine transform,
    _SvgStyle style,
    String? id,
    bool edgeCandidate,
  ) {
    final x = _number(element.getAttribute('x')) ?? 0;
    final y = _number(element.getAttribute('y')) ?? 0;
    final width = _number(element.getAttribute('width')) ?? 0;
    final height = _number(element.getAttribute('height')) ?? 0;
    final href = element.getAttribute('xlink:href')?.trim();
    if (width <= 0 || height <= 0 || href == null || href.isEmpty) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_IMAGE_INVALID',
          message: 'Mermaid SVG contains an invalid local image.',
        ),
      );
    }
    final points = [
      mapper.world(transform.apply(Offset(x, y))),
      mapper.world(transform.apply(Offset(x + width, y))),
      mapper.world(transform.apply(Offset(x + width, y + height))),
      mapper.world(transform.apply(Offset(x, y + height))),
    ];
    primitives.add(
      _SvgPrimitive(
        kind: _SvgPrimitiveKind.image,
        points: points,
        path: [for (final point in points) _PathPoint(point: point)],
        closed: true,
        style: style,
        key: null,
        id: element.getAttribute('id'),
        containerId: id,
        edgeCandidate: edgeCandidate,
        imageHref: href,
      ),
    );
  }

  void _addRect(
    XmlElement element,
    _Affine transform,
    _SvgStyle style,
    String? id,
    Set<String> classes,
    bool edgeCandidate,
  ) {
    final x = _number(element.getAttribute('x')) ?? 0;
    final y = _number(element.getAttribute('y')) ?? 0;
    final width = _number(element.getAttribute('width')) ?? 0;
    final height = _number(element.getAttribute('height')) ?? 0;
    if (width <= 0 || height <= 0) return;
    final points = [
      mapper.world(transform.apply(Offset(x, y))),
      mapper.world(transform.apply(Offset(x + width, y))),
      mapper.world(transform.apply(Offset(x + width, y + height))),
      mapper.world(transform.apply(Offset(x, y + height))),
    ];
    final axisAligned = _isAxisAligned(points);
    primitives.add(
      _SvgPrimitive(
        kind: axisAligned
            ? _SvgPrimitiveKind.rectangle
            : _SvgPrimitiveKind.vector,
        points: points,
        path: [for (final point in points) _PathPoint(point: point)],
        closed: true,
        style: style,
        key: id,
        id: element.getAttribute('id'),
        containerId: id,
        edgeCandidate: edgeCandidate,
      ),
    );
  }

  void _addEllipse(
    XmlElement element,
    _Affine transform,
    _SvgStyle style,
    String? id,
    Set<String> classes,
    bool edgeCandidate,
  ) {
    final cx = _number(element.getAttribute('cx')) ?? 0;
    final cy = _number(element.getAttribute('cy')) ?? 0;
    final rx = element.name.local == 'circle'
        ? (_number(element.getAttribute('r')) ?? 0)
        : (_number(element.getAttribute('rx')) ?? 0);
    final ry = element.name.local == 'circle'
        ? rx
        : (_number(element.getAttribute('ry')) ?? 0);
    if (rx <= 0 || ry <= 0) return;

    final corners = [
      mapper.world(transform.apply(Offset(cx - rx, cy - ry))),
      mapper.world(transform.apply(Offset(cx + rx, cy + ry))),
    ];
    final points = [corners[0], corners[1]];
    final axisAligned = _isAxisAlignedTransform(transform);
    if (axisAligned) {
      primitives.add(
        _SvgPrimitive(
          kind: _SvgPrimitiveKind.ellipse,
          points: points,
          path: [
            _PathPoint(point: corners[0]),
            _PathPoint(point: corners[1]),
          ],
          closed: true,
          style: style,
          key: id,
          id: element.getAttribute('id'),
          containerId: id,
          edgeCandidate: edgeCandidate,
        ),
      );
      return;
    }

    const kappa = 0.5522847498307936;
    final path = <_PathPoint>[];
    for (var index = 0; index < 4; index++) {
      final angle = index * math.pi / 2;
      final point = Offset(
        cx + math.cos(angle) * rx,
        cy + math.sin(angle) * ry,
      );
      final tangent = Offset(
        -math.sin(angle) * ry * kappa,
        math.cos(angle) * rx * kappa,
      );
      path.add(
        _PathPoint(
          point: mapper.world(transform.apply(point)),
          handleIn: mapper.worldVector(transform, -tangent),
          handleOut: mapper.worldVector(transform, tangent),
        ),
      );
    }
    primitives.add(
      _SvgPrimitive(
        kind: _SvgPrimitiveKind.vector,
        points: [for (final point in path) point.point],
        path: path,
        closed: true,
        style: style,
        key: id,
        id: element.getAttribute('id'),
        containerId: id,
        edgeCandidate: edgeCandidate,
      ),
    );
  }

  void _addLine(
    XmlElement element,
    _Affine transform,
    _SvgStyle style,
    String? id,
    bool edgeCandidate,
    List<Offset>? routePoints,
  ) {
    final start = mapper.world(
      transform.apply(
        Offset(
          _number(element.getAttribute('x1')) ?? 0,
          _number(element.getAttribute('y1')) ?? 0,
        ),
      ),
    );
    final end = mapper.world(
      transform.apply(
        Offset(
          _number(element.getAttribute('x2')) ?? 0,
          _number(element.getAttribute('y2')) ?? 0,
        ),
      ),
    );
    final geometryPoints = routePoints == null || routePoints.length < 2
        ? [start, end]
        : routePoints;
    final linePath = [
      for (final point in geometryPoints) _PathPoint(point: point),
    ];
    primitives.add(
      _SvgPrimitive(
        kind: _SvgPrimitiveKind.line,
        points: geometryPoints,
        path: linePath,
        closed: false,
        style: style,
        key: null,
        id: element.getAttribute('id'),
        containerId: id,
        edgeCandidate: edgeCandidate,
        startMarker: style.startMarker,
        endMarker: style.endMarker,
        sourceKey: _endpointKey(element, source: true),
        targetKey: _endpointKey(element, source: false),
        metadataPoints: routePoints,
      ),
    );
    _addMarkersForPath(style, id, linePath, element.getAttribute('id'));
  }

  void _addPolygon(
    XmlElement element,
    _Affine transform,
    _SvgStyle style,
    String? id,
    bool edgeCandidate,
    List<Offset>? routePoints, {
    required bool closed,
  }) {
    final raw = element.getAttribute('points') ?? '';
    final values = _numberList(raw);
    if (values.length < 4 || values.length.isOdd) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_GEOMETRY_INVALID',
          message: 'Mermaid SVG polygon geometry is invalid.',
        ),
      );
    }
    final points = <Offset>[];
    for (var index = 0; index < values.length; index += 2) {
      points.add(
        mapper.world(transform.apply(Offset(values[index], values[index + 1]))),
      );
    }
    final geometryPoints =
        edgeCandidate && routePoints != null && routePoints.length >= 2
        ? routePoints
        : points;
    primitives.add(
      _SvgPrimitive(
        kind: _SvgPrimitiveKind.vector,
        points: geometryPoints,
        path: [for (final point in geometryPoints) _PathPoint(point: point)],
        closed: closed,
        style: style,
        key: id,
        id: element.getAttribute('id'),
        containerId: id,
        edgeCandidate: edgeCandidate,
        sourceKey: _endpointKey(element, source: true),
        targetKey: _endpointKey(element, source: false),
        metadataPoints: routePoints,
      ),
    );
  }

  void _addPath(
    XmlElement element,
    _Affine transform,
    _SvgStyle style,
    String? id,
    bool edgeCandidate,
    List<Offset>? routePoints,
  ) {
    final raw = element.getAttribute('d') ?? '';
    final parsed = _SvgPathParser.parse(raw);
    final transformedSubpaths = parsed.subpaths
        .map(
          (subpath) => subpath
              .map(
                (point) => _PathPoint(
                  point: mapper.world(transform.apply(point.point)),
                  handleIn: mapper.worldVector(transform, point.handleIn),
                  handleOut: mapper.worldVector(transform, point.handleOut),
                ),
              )
              .toList(growable: false),
        )
        .toList(growable: false);
    final path = transformedSubpaths.expand((subpath) => subpath).toList();
    if (path.isEmpty) return;
    primitives.add(
      _SvgPrimitive(
        kind: _SvgPrimitiveKind.vector,
        points: [for (final point in path) point.point],
        path: path,
        subpaths: transformedSubpaths,
        subpathClosed: parsed.subpathClosed,
        closed: parsed.closed,
        style: style,
        key: id,
        id: element.getAttribute('id'),
        containerId: id,
        edgeCandidate:
            edgeCandidate ||
            style.startMarker != LineMarker.none ||
            style.endMarker != LineMarker.none,
        startMarker: style.startMarker,
        endMarker: style.endMarker,
        hasCurve: parsed.hasCurve,
        sourceKey: _endpointKey(element, source: true),
        targetKey: _endpointKey(element, source: false),
        metadataPoints: routePoints,
      ),
    );
    _addMarkersForPath(style, id, path, element.getAttribute('id'));
  }

  void _addMarkersForPath(
    _SvgStyle style,
    String? containerId,
    List<_PathPoint> path,
    String? sourceId,
  ) {
    if (path.length < 2) return;
    _addMarker(
      style.startMarker,
      style['marker-start'],
      path.first.point,
      _pathDirection(path, start: true),
      style,
      containerId,
      sourceId,
    );
    _addMarker(
      style.endMarker,
      style['marker-end'],
      path.last.point,
      _pathDirection(path, start: false),
      style,
      containerId,
      sourceId,
    );
    for (var index = 1; index < path.length - 1; index++) {
      final incoming = path[index].point - path[index - 1].point;
      final outgoing = path[index + 1].point - path[index].point;
      final direction = incoming + outgoing;
      _addMarker(
        LineMarker.none,
        style.midMarker,
        path[index].point,
        direction.distance < 0.001 ? outgoing : direction,
        style,
        containerId,
        sourceId,
      );
    }
  }

  Offset _pathDirection(List<_PathPoint> path, {required bool start}) {
    final point = start ? path.first : path.last;
    final control = start
        ? point.point + point.handleOut
        : point.point + point.handleIn;
    if ((control - point.point).distance > 0.001) {
      return start ? point.point - control : point.point - control;
    }
    final other = start ? path[1].point : path[path.length - 2].point;
    return start ? point.point - other : point.point - other;
  }

  void _addMarker(
    LineMarker marker,
    String? rawMarker,
    Offset endpoint,
    Offset direction,
    _SvgStyle ownerStyle,
    String? containerId,
    String? sourceId,
  ) {
    if (marker != LineMarker.none ||
        rawMarker == null ||
        rawMarker.toLowerCase().contains('none') ||
        direction.distance < 0.001) {
      return;
    }
    final markerId = _markerId(rawMarker);
    if (markerId == null) return;
    final definition = _markers[markerId];
    if (definition == null) return;
    final children = definition.children
        .whereType<XmlElement>()
        .where((child) => child.name.local == 'path')
        .toList(growable: false);
    if (children.isEmpty) return;
    final child = children.first;
    final parsed = _SvgPathParser.parse(child.getAttribute('d') ?? '');
    final markerWidth = _number(definition.getAttribute('markerWidth')) ?? 3;
    final markerHeight = _number(definition.getAttribute('markerHeight')) ?? 3;
    final refX = _number(definition.getAttribute('refX')) ?? 0;
    final refY = _number(definition.getAttribute('refY')) ?? 0;
    final viewBox = _numberList(definition.getAttribute('viewBox') ?? '');
    final usesViewBox = viewBox.length == 4 && viewBox[2] > 0 && viewBox[3] > 0;
    final markerScale =
        definition.getAttribute('markerUnits') == 'userSpaceOnUse'
        ? mapper.scale
        : ownerStyle.strokeWidth * mapper.scale;
    final viewportScaleX = usesViewBox ? markerWidth / viewBox[2] : 1.0;
    final viewportScaleY = usesViewBox ? markerHeight / viewBox[3] : 1.0;
    final ref = Offset(
      usesViewBox ? (refX - viewBox[0]) * viewportScaleX : refX,
      usesViewBox ? (refY - viewBox[1]) * viewportScaleY : refY,
    );
    final angle =
        (definition.getAttribute('orient')?.toLowerCase() == 'auto' ||
            definition.getAttribute('orient') == null)
        ? math.atan2(direction.dy, direction.dx)
        : (_number(definition.getAttribute('orient')) ?? 0) * math.pi / 180;
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    Offset place(Offset point) {
      final local = Offset(
        (usesViewBox ? (point.dx - viewBox[0]) * viewportScaleX : point.dx) -
            ref.dx,
        (usesViewBox ? (point.dy - viewBox[1]) * viewportScaleY : point.dy) -
            ref.dy,
      );
      final scaled = local * markerScale;
      return endpoint +
          Offset(
            scaled.dx * cosine - scaled.dy * sine,
            scaled.dx * sine + scaled.dy * cosine,
          );
    }

    final markerStyle = _resolveStyle(
      ownerStyle.merge(definition).merge(child),
    );
    final converted = parsed.subpaths
        .map(
          (subpath) => subpath
              .map(
                (point) => _PathPoint(
                  point: place(point.point),
                  handleIn:
                      place(point.point + point.handleIn) - place(point.point),
                  handleOut:
                      place(point.point + point.handleOut) - place(point.point),
                ),
              )
              .toList(growable: false),
        )
        .toList(growable: false);
    final flattened = converted.expand((subpath) => subpath).toList();
    if (flattened.isEmpty) return;
    primitives.add(
      _SvgPrimitive(
        kind: _SvgPrimitiveKind.vector,
        points: [for (final point in flattened) point.point],
        path: flattened,
        subpaths: converted,
        subpathClosed: parsed.subpathClosed,
        closed: parsed.closed,
        style: markerStyle,
        key: null,
        id: sourceId == null ? null : '$sourceId-marker-$markerId',
        containerId: containerId,
        edgeCandidate: false,
        hasCurve: parsed.hasCurve,
      ),
    );
  }

  void _addText(
    XmlElement element,
    _Affine transform,
    _SvgStyle style,
    String? id,
  ) {
    final parentX = _number(element.getAttribute('x')) ?? 0;
    final parentY = _number(element.getAttribute('y')) ?? 0;
    var currentX = parentX + (_number(element.getAttribute('dx')) ?? 0);
    var currentY = parentY + (_number(element.getAttribute('dy')) ?? 0);
    final tspans = element.children
        .whereType<XmlElement>()
        .where((child) => child.name.local == 'tspan')
        .toList(growable: false);

    void addRun(String rawText, _SvgStyle runStyle, double x, double y) {
      final text = rawText.replaceAll('\r', '').trim();
      if (text.isEmpty) return;
      final anchor = mapper.world(transform.apply(Offset(x, y)));
      final textAnchor = switch (runStyle['text-anchor']?.toLowerCase()) {
        'middle' => TextAlign.center,
        'end' => TextAlign.right,
        _ => TextAlign.left,
      };
      final dominantBaseline =
          runStyle['dominant-baseline'] ?? runStyle['alignment-baseline'];
      primitives.add(
        _SvgPrimitive(
          kind: _SvgPrimitiveKind.text,
          points: [anchor],
          path: [_PathPoint(point: anchor)],
          closed: false,
          style: runStyle,
          key: null,
          id: element.getAttribute('id'),
          containerId: id,
          edgeCandidate: false,
          text: text,
          textAnchor: textAnchor,
          dominantBaseline: dominantBaseline,
        ),
      );
    }

    if (tspans.isEmpty) {
      addRun(element.innerText, style, currentX, currentY);
      return;
    }

    for (final tspan in tspans) {
      final runStyle = style.merge(tspan);
      final x = _number(tspan.getAttribute('x')) ?? currentX;
      final y = _number(tspan.getAttribute('y')) ?? currentY;
      final runX = x + (_number(tspan.getAttribute('dx')) ?? 0);
      final runY = y + (_number(tspan.getAttribute('dy')) ?? 0);
      addRun(tspan.innerText, runStyle, runX, runY);
      currentX = runX;
      currentY = runY;
    }
  }
}

class _SvgMapper {
  final CanvasNode sourceNode;
  final double viewBoxX;
  final double viewBoxY;
  final double viewBoxWidth;
  final double viewBoxHeight;
  final double scale;
  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;

  const _SvgMapper({
    required this.sourceNode,
    required this.viewBoxX,
    required this.viewBoxY,
    required this.viewBoxWidth,
    required this.viewBoxHeight,
    required this.scale,
    required this.scaleX,
    required this.scaleY,
    required this.offsetX,
    required this.offsetY,
  });

  factory _SvgMapper.fromRoot(XmlElement root, CanvasNode sourceNode) {
    final rawViewBox = root.getAttribute('viewBox');
    final values = _numberList(rawViewBox ?? '');
    final intrinsicWidth =
        _number(root.getAttribute('width')) ?? sourceNode.width;
    final intrinsicHeight =
        _number(root.getAttribute('height')) ?? sourceNode.height;
    final viewBox = values.length == 4
        ? values
        : <double>[0, 0, intrinsicWidth, intrinsicHeight];
    if (values.isNotEmpty && values.length != 4 ||
        viewBox[2] <= 0 ||
        viewBox[3] <= 0) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_VIEWBOX_INVALID',
          message: 'Mermaid SVG has invalid dimensions.',
        ),
      );
    }
    final fit = _fitSvgViewport(
      viewportWidth: sourceNode.width,
      viewportHeight: sourceNode.height,
      viewBoxX: viewBox[0],
      viewBoxY: viewBox[1],
      viewBoxWidth: viewBox[2],
      viewBoxHeight: viewBox[3],
      preserveAspectRatio: root.getAttribute('preserveAspectRatio'),
    );
    return _SvgMapper(
      sourceNode: sourceNode,
      viewBoxX: viewBox[0],
      viewBoxY: viewBox[1],
      viewBoxWidth: viewBox[2],
      viewBoxHeight: viewBox[3],
      scale: math.min(fit.scaleX.abs(), fit.scaleY.abs()),
      scaleX: fit.scaleX,
      scaleY: fit.scaleY,
      offsetX: fit.offsetX,
      offsetY: fit.offsetY,
    );
  }

  Offset world(Offset point) => Offset(
    sourceNode.x + offsetX + point.dx * scaleX,
    sourceNode.y + offsetY + point.dy * scaleY,
  );

  Offset worldVector(_Affine transform, Offset vector) {
    final transformed = transform.applyVector(vector);
    return Offset(transformed.dx * scaleX, transformed.dy * scaleY);
  }
}

class _SvgViewportFit {
  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;

  const _SvgViewportFit({
    required this.scaleX,
    required this.scaleY,
    required this.offsetX,
    required this.offsetY,
  });
}

_SvgViewportFit _fitSvgViewport({
  required double viewportWidth,
  required double viewportHeight,
  required double viewBoxX,
  required double viewBoxY,
  required double viewBoxWidth,
  required double viewBoxHeight,
  required String? preserveAspectRatio,
}) {
  if (!viewportWidth.isFinite ||
      !viewportHeight.isFinite ||
      viewportWidth <= 0 ||
      viewportHeight <= 0 ||
      !viewBoxWidth.isFinite ||
      !viewBoxHeight.isFinite ||
      viewBoxWidth <= 0 ||
      viewBoxHeight <= 0) {
    throw const _SvgConversionFailure(
      MermaidDiagnostic(
        code: 'SVG_VIEWBOX_INVALID',
        message: 'Mermaid SVG has invalid viewport dimensions.',
      ),
    );
  }

  final tokens = (preserveAspectRatio ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isNotEmpty && tokens.first.toLowerCase() == 'defer') {
    tokens.removeAt(0);
  }
  final alignment = tokens.isEmpty ? 'xmidymid' : tokens.first.toLowerCase();
  if (alignment == 'none') {
    return _SvgViewportFit(
      scaleX: viewportWidth / viewBoxWidth,
      scaleY: viewportHeight / viewBoxHeight,
      offsetX: -viewBoxX * viewportWidth / viewBoxWidth,
      offsetY: -viewBoxY * viewportHeight / viewBoxHeight,
    );
  }

  const alignments = {
    'xminymin': (0.0, 0.0),
    'xmidymin': (0.5, 0.0),
    'xmaxymin': (1.0, 0.0),
    'xminymid': (0.0, 0.5),
    'xmidymid': (0.5, 0.5),
    'xmaxymid': (1.0, 0.5),
    'xminymax': (0.0, 1.0),
    'xmidymax': (0.5, 1.0),
    'xmaxymax': (1.0, 1.0),
  };
  final alignmentOffset = alignments[alignment];
  if (alignmentOffset == null) {
    throw const _SvgConversionFailure(
      MermaidDiagnostic(
        code: 'SVG_PRESERVE_ASPECT_RATIO_INVALID',
        message: 'Mermaid SVG preserveAspectRatio is invalid.',
      ),
    );
  }
  final mode = tokens.length > 1 ? tokens[1].toLowerCase() : 'meet';
  if (mode != 'meet' && mode != 'slice') {
    throw const _SvgConversionFailure(
      MermaidDiagnostic(
        code: 'SVG_PRESERVE_ASPECT_RATIO_INVALID',
        message: 'Mermaid SVG preserveAspectRatio is invalid.',
      ),
    );
  }
  final scale = mode == 'slice'
      ? math.max(viewportWidth / viewBoxWidth, viewportHeight / viewBoxHeight)
      : math.min(viewportWidth / viewBoxWidth, viewportHeight / viewBoxHeight);
  final extraX = viewportWidth - viewBoxWidth * scale;
  final extraY = viewportHeight - viewBoxHeight * scale;
  return _SvgViewportFit(
    scaleX: scale,
    scaleY: scale,
    offsetX: extraX * alignmentOffset.$1 - viewBoxX * scale,
    offsetY: extraY * alignmentOffset.$2 - viewBoxY * scale,
  );
}

class _SvgPrimitive {
  int order = 0;
  final _SvgPrimitiveKind kind;
  final List<Offset> points;
  final List<_PathPoint> path;
  final List<List<_PathPoint>> subpaths;
  final List<bool> subpathClosed;
  final bool closed;
  final _SvgStyle style;
  final String? key;
  final String? id;
  final String? containerId;
  final bool edgeCandidate;
  final LineMarker startMarker;
  final LineMarker endMarker;
  final bool hasCurve;
  final String? sourceKey;
  final String? targetKey;
  final List<Offset>? metadataPoints;
  final String? imageHref;
  final String? text;
  final TextAlign textAnchor;
  final String? dominantBaseline;

  _SvgPrimitive({
    required this.kind,
    required this.points,
    required this.path,
    this.subpaths = const [],
    this.subpathClosed = const [],
    required this.closed,
    required this.style,
    required this.key,
    required this.id,
    required this.containerId,
    required this.edgeCandidate,
    this.startMarker = LineMarker.none,
    this.endMarker = LineMarker.none,
    this.hasCurve = false,
    this.sourceKey,
    this.targetKey,
    this.metadataPoints,
    this.imageHref,
    this.text,
    this.textAnchor = TextAlign.left,
    this.dominantBaseline,
  });

  List<Offset> get pathPoints => [for (final point in path) point.point];
}

enum _SvgPrimitiveKind { rectangle, ellipse, line, vector, image, text }

bool _hasUnsupportedMarker(_SvgPrimitive primitive) {
  bool custom(String? value, LineMarker marker) {
    return value != null &&
        !value.toLowerCase().contains('none') &&
        marker == LineMarker.none;
  }

  return custom(primitive.style['marker-start'], primitive.startMarker) ||
      custom(primitive.style['marker-end'], primitive.endMarker) ||
      primitive.style.midMarker != null &&
          !primitive.style.midMarker!.toLowerCase().contains('none');
}

class _PathPoint {
  final Offset point;
  final Offset handleIn;
  final Offset handleOut;

  const _PathPoint({
    required this.point,
    this.handleIn = Offset.zero,
    this.handleOut = Offset.zero,
  });
}

class _SvgGradient {
  final FillType type;
  final List<Color> colors;

  const _SvgGradient({required this.type, required this.colors});
}

class _SvgStyle {
  final Map<String, String> values;
  final _SvgGradient? gradient;

  const _SvgStyle([this.values = const {}, this.gradient]);

  String? operator [](String key) => values[key];

  _SvgStyle copyWithGradient(_SvgGradient? value) => _SvgStyle(values, value);

  static String? _inlineStyleValue(String? style, String key) {
    if (style == null) return null;
    for (final declaration in style.split(';')) {
      final separator = declaration.indexOf(':');
      if (separator <= 0) continue;
      if (declaration.substring(0, separator).trim().toLowerCase() == key) {
        return declaration.substring(separator + 1).trim();
      }
    }
    return null;
  }

  bool get hasGradient => gradient != null && gradient!.colors.length >= 2;
  FillType get fillType => hasGradient ? gradient!.type : FillType.solid;
  Color? get fillGradientEnd => hasGradient ? gradient!.colors.last : null;

  _SvgStyle merge(XmlElement element) {
    final inheritedOpacity = _number(values['opacity']) ?? 1.0;
    final ownOpacity =
        _number(element.getAttribute('opacity')) ??
        _number(_inlineStyleValue(element.getAttribute('style'), 'opacity')) ??
        1.0;
    final next = Map<String, String>.from(values);
    for (final attribute in element.attributes) {
      final key = attribute.name.local.toLowerCase();
      if (_styleKeys.contains(key)) next[key] = attribute.value.trim();
    }
    final inline = element.getAttribute('style');
    if (inline != null) {
      for (final declaration in inline.split(';')) {
        final separator = declaration.indexOf(':');
        if (separator <= 0) continue;
        final key = declaration.substring(0, separator).trim().toLowerCase();
        if (_styleKeys.contains(key)) {
          next[key] = declaration.substring(separator + 1).trim();
        }
      }
    }
    next['opacity'] = (inheritedOpacity * ownOpacity)
        .clamp(0.0, 1.0)
        .toString();
    return _SvgStyle(next);
  }

  Color? get fillColor {
    final rawFill = values['fill']?.trim().toLowerCase();
    if (rawFill == 'none') return null;
    return gradient?.colors.first ??
        _parseColor(
          rawFill == 'currentcolor' ? values['color'] : values['fill'],
        ) ??
        Colors.black;
  }

  Color? get strokeColor => _applyOpacity(
    _parseColor(
      values['stroke']?.toLowerCase() == 'currentcolor'
          ? values['color']
          : values['stroke'],
    ),
    _number(values['stroke-opacity']) ?? 1.0,
  );
  double get fillOpacity =>
      (_number(values['fill-opacity']) ?? 1.0).clamp(0.0, 1.0);
  double get opacity => (_number(values['opacity']) ?? 1.0).clamp(0.0, 1.0);
  double get strokeWidth =>
      math.max(0.0, _number(values['stroke-width']) ?? 1.0);
  double get fontSize => math.max(1.0, _number(values['font-size']) ?? 14.0);
  String get fontFamily => values['font-family']?.trim() ?? 'Inter';
  double get letterSpacing => _number(values['letter-spacing']) ?? 0.0;
  FontStyle get fontStyle => values['font-style']?.toLowerCase() == 'italic'
      ? FontStyle.italic
      : FontStyle.normal;
  FontWeight get fontWeight {
    final raw = values['font-weight']?.toLowerCase();
    if (raw == 'bold' || (int.tryParse(raw ?? '') ?? 0) >= 600) {
      return FontWeight.bold;
    }
    return FontWeight.normal;
  }

  double get cornerRadius => math.max(0.0, _number(values['rx']) ?? 0.0);
  StrokeStyle get strokeStyle {
    final dash = dashPattern;
    if (dash.isEmpty) return StrokeStyle.solid;
    return dash.length >= 2 && dash[0] <= 3 && dash[1] <= 4
        ? StrokeStyle.dotted
        : StrokeStyle.dashed;
  }

  List<double> get dashPattern => _numberList(values['stroke-dasharray'] ?? '');
  double get dashOffset => _number(values['stroke-dashoffset']) ?? 0.0;
  VectorStrokeCap get strokeCap => switch (values['stroke-linecap']) {
    'butt' => VectorStrokeCap.butt,
    'square' => VectorStrokeCap.square,
    _ => VectorStrokeCap.round,
  };
  VectorStrokeJoin get strokeJoin => switch (values['stroke-linejoin']) {
    'miter' => VectorStrokeJoin.miter,
    'bevel' => VectorStrokeJoin.bevel,
    _ => VectorStrokeJoin.round,
  };
  LineMarker get startMarker => _marker(values['marker-start']);
  LineMarker get endMarker => _marker(values['marker-end']);
  String? get midMarker => values['marker-mid'];

  static const _styleKeys = <String>{
    'fill',
    'fill-opacity',
    'fill-rule',
    'color',
    'stroke',
    'stroke-opacity',
    'stroke-width',
    'stroke-dasharray',
    'stroke-dashoffset',
    'stroke-linecap',
    'stroke-linejoin',
    'marker-start',
    'marker-mid',
    'marker-end',
    'font-family',
    'font-size',
    'font-style',
    'font-weight',
    'letter-spacing',
    'text-anchor',
    'dominant-baseline',
    'alignment-baseline',
    'dx',
    'dy',
    'opacity',
    'rx',
    'stop-color',
    'stop-opacity',
  };
}

class _Affine {
  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  const _Affine(this.a, this.b, this.c, this.d, this.e, this.f);

  const _Affine.identity() : this(1, 0, 0, 1, 0, 0);

  Offset apply(Offset point) =>
      Offset(a * point.dx + c * point.dy + e, b * point.dx + d * point.dy + f);

  Offset applyVector(Offset vector) =>
      Offset(a * vector.dx + c * vector.dy, b * vector.dx + d * vector.dy);

  _Affine multiply(_Affine other) => _Affine(
    a * other.a + c * other.b,
    b * other.a + d * other.b,
    a * other.c + c * other.d,
    b * other.c + d * other.d,
    a * other.e + c * other.f + e,
    b * other.e + d * other.f + f,
  );

  static _Affine fromSvgTransform(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const _Affine.identity();
    var result = const _Affine.identity();
    final pattern = RegExp(r'([A-Za-z]+)\s*\(([^)]*)\)');
    var consumed = 0;
    for (final match in pattern.allMatches(raw)) {
      if (raw.substring(consumed, match.start).trim().isNotEmpty) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_TRANSFORM_INVALID',
            message: 'Mermaid SVG transform data is invalid.',
          ),
        );
      }
      consumed = match.end;
      final name = match.group(1)!.toLowerCase();
      final values = _numberList(match.group(2) ?? '');
      final operation = switch (name) {
        'translate' when values.length == 1 || values.length == 2 => _Affine(
          1,
          0,
          0,
          1,
          values[0],
          values.length == 2 ? values[1] : 0,
        ),
        'scale' when values.length == 1 || values.length == 2 => _Affine(
          values[0],
          0,
          0,
          values.length == 2 ? values[1] : values[0],
          0,
          0,
        ),
        'rotate' when values.length == 1 || values.length == 3 => () {
          final radians = values[0] * math.pi / 180;
          final rotation = _Affine(
            math.cos(radians),
            math.sin(radians),
            -math.sin(radians),
            math.cos(radians),
            0,
            0,
          );
          if (values.length == 1) return rotation;
          final center = Offset(values[1], values[2]);
          return _Affine(1, 0, 0, 1, center.dx, center.dy)
              .multiply(rotation)
              .multiply(_Affine(1, 0, 0, 1, -center.dx, -center.dy));
        }(),
        'matrix' when values.length == 6 => _Affine(
          values[0],
          values[1],
          values[2],
          values[3],
          values[4],
          values[5],
        ),
        _ => throw _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_TRANSFORM_INVALID',
            message: 'Mermaid SVG transform "$name" is not supported.',
          ),
        ),
      };
      result = result.multiply(operation);
    }
    if (raw.substring(consumed).trim().isNotEmpty) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_TRANSFORM_INVALID',
          message: 'Mermaid SVG transform data is invalid.',
        ),
      );
    }
    return result;
  }
}

class _SvgPathData {
  final List<_PathPoint> points;
  final List<List<_PathPoint>> subpaths;
  final List<bool> subpathClosed;
  final bool closed;
  final bool hasCurve;

  const _SvgPathData({
    required this.points,
    required this.subpaths,
    required this.subpathClosed,
    required this.closed,
    required this.hasCurve,
  });
}

class _SvgPathParser {
  _SvgPathParser._();

  static _SvgPathData parse(String raw) {
    final matches = RegExp(
      r'[A-Za-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
    ).allMatches(raw).toList();
    var consumed = 0;
    for (final match in matches) {
      final separator = raw.substring(consumed, match.start);
      if (separator.replaceAll(RegExp(r'[\s,]'), '').isNotEmpty) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_PATH_INVALID',
            message: 'Mermaid SVG path contains invalid separators.',
          ),
        );
      }
      consumed = match.end;
    }
    if (raw.substring(consumed).replaceAll(RegExp(r'[\s,]'), '').isNotEmpty) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_PATH_INVALID',
          message: 'Mermaid SVG path contains invalid separators.',
        ),
      );
    }
    final tokens = matches.map((match) => match.group(0)!).toList();
    if (tokens.isEmpty ||
        tokens.length > 4096 ||
        !RegExp(r'^[Mm]$').hasMatch(tokens.first)) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_PATH_INVALID',
          message: 'Mermaid SVG path data is invalid or too complex.',
        ),
      );
    }

    final points = <_MutablePathPoint>[];
    var index = 0;
    String? command;
    Offset current = Offset.zero;
    Offset start = Offset.zero;
    Offset previousCubicControl = Offset.zero;
    Offset previousQuadraticControl = Offset.zero;
    var previousCommand = '';
    var closed = false;
    var currentSubpathClosed = false;
    var hasCurve = false;
    final subpathStarts = <int>[];
    final subpathClosed = <bool>[];

    bool isCommand(String token) => RegExp(r'^[A-Za-z]$').hasMatch(token);
    double number() {
      if (index >= tokens.length || isCommand(tokens[index])) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_PATH_INVALID',
            message: 'Mermaid SVG path data is incomplete.',
          ),
        );
      }
      final value = double.tryParse(tokens[index++]);
      if (value == null ||
          !value.isFinite ||
          value.abs() > MermaidSourceLimits.maxSvgCoordinate) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_PATH_INVALID',
            message: 'Mermaid SVG path contains an invalid number.',
          ),
        );
      }
      return value;
    }

    Offset relative(Offset value, bool isRelative) =>
        isRelative ? current + value : value;
    void addLine(Offset endpoint) {
      points.add(_MutablePathPoint(point: endpoint));
      current = endpoint;
      previousCubicControl = Offset.zero;
      previousQuadraticControl = Offset.zero;
    }

    void addCubic(Offset cp1, Offset cp2, Offset endpoint) {
      if (points.isNotEmpty) points.last.handleOut = cp1 - current;
      points.add(_MutablePathPoint(point: endpoint, handleIn: cp2 - endpoint));
      current = endpoint;
      previousCubicControl = cp2;
      previousQuadraticControl = Offset.zero;
      hasCurve = true;
    }

    while (index < tokens.length) {
      if (isCommand(tokens[index])) {
        command = tokens[index++];
      } else if (command == null) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_PATH_INVALID',
            message: 'Mermaid SVG path must begin with a command.',
          ),
        );
      }
      final rawCommand = command;
      final upper = rawCommand.toUpperCase();
      final isRelative = rawCommand != upper;
      if (upper == 'Z') {
        current = start;
        closed = true;
        currentSubpathClosed = true;
        previousCommand = upper;
        command = null;
        continue;
      }
      final count = switch (upper) {
        'M' || 'L' || 'T' => 2,
        'H' || 'V' => 1,
        'C' => 6,
        'S' || 'Q' => 4,
        'A' => 7,
        _ => 0,
      };
      if (count == 0) {
        throw _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_PATH_INVALID',
            message: 'Mermaid SVG command "$upper" is not supported.',
          ),
        );
      }
      if (index + count > tokens.length || isCommand(tokens[index])) {
        throw const _SvgConversionFailure(
          MermaidDiagnostic(
            code: 'SVG_PATH_INVALID',
            message: 'Mermaid SVG path data is incomplete.',
          ),
        );
      }

      switch (upper) {
        case 'M':
          if (subpathStarts.isNotEmpty) {
            subpathClosed.add(currentSubpathClosed);
          }
          subpathStarts.add(points.length);
          currentSubpathClosed = false;
          final endpoint = relative(Offset(number(), number()), isRelative);
          current = endpoint;
          start = endpoint;
          points.add(_MutablePathPoint(point: endpoint));
          previousCubicControl = Offset.zero;
          previousQuadraticControl = Offset.zero;
          previousCommand = upper;
          command = isRelative ? 'l' : 'L';
        case 'L':
          addLine(relative(Offset(number(), number()), isRelative));
          previousCommand = upper;
        case 'H':
          final value = number();
          addLine(Offset(isRelative ? current.dx + value : value, current.dy));
          previousCommand = upper;
        case 'V':
          final value = number();
          addLine(Offset(current.dx, isRelative ? current.dy + value : value));
          previousCommand = upper;
        case 'C':
          final cp1 = relative(Offset(number(), number()), isRelative);
          final cp2 = relative(Offset(number(), number()), isRelative);
          final endpoint = relative(Offset(number(), number()), isRelative);
          addCubic(cp1, cp2, endpoint);
          previousCommand = upper;
        case 'S':
          final cp1 = (previousCommand == 'C' || previousCommand == 'S')
              ? current * 2 - previousCubicControl
              : current;
          final cp2 = relative(Offset(number(), number()), isRelative);
          final endpoint = relative(Offset(number(), number()), isRelative);
          addCubic(cp1, cp2, endpoint);
          previousCommand = upper;
        case 'Q':
          final control = relative(Offset(number(), number()), isRelative);
          final endpoint = relative(Offset(number(), number()), isRelative);
          final cp1 = current + (control - current) * (2 / 3);
          final cp2 = endpoint + (control - endpoint) * (2 / 3);
          addCubic(cp1, cp2, endpoint);
          previousQuadraticControl = control;
          previousCommand = upper;
        case 'T':
          final control = (previousCommand == 'Q' || previousCommand == 'T')
              ? current * 2 - previousQuadraticControl
              : current;
          final endpoint = relative(Offset(number(), number()), isRelative);
          final cp1 = current + (control - current) * (2 / 3);
          final cp2 = endpoint + (control - endpoint) * (2 / 3);
          addCubic(cp1, cp2, endpoint);
          previousQuadraticControl = control;
          previousCommand = upper;
        case 'A':
          final rx = number().abs();
          final ry = number().abs();
          final rotation = number();
          final largeArcValue = number();
          final sweepValue = number();
          if ((largeArcValue != 0 && largeArcValue != 1) ||
              (sweepValue != 0 && sweepValue != 1)) {
            throw const _SvgConversionFailure(
              MermaidDiagnostic(
                code: 'SVG_PATH_INVALID',
                message: 'Mermaid arc flags must be zero or one.',
              ),
            );
          }
          final largeArc = largeArcValue == 1;
          final sweep = sweepValue == 1;
          final endpoint = relative(Offset(number(), number()), isRelative);
          _appendArc(
            points,
            current,
            endpoint,
            rx,
            ry,
            rotation,
            largeArc,
            sweep,
          );
          current = endpoint;
          previousCubicControl = Offset.zero;
          previousQuadraticControl = Offset.zero;
          hasCurve = true;
          previousCommand = upper;
      }
    }

    if (subpathStarts.isNotEmpty) {
      subpathClosed.add(currentSubpathClosed);
    }
    final convertedPoints = [
      for (final point in points)
        _PathPoint(
          point: point.point,
          handleIn: point.handleIn,
          handleOut: point.handleOut,
        ),
    ];
    final convertedSubpaths = subpathStarts.isEmpty
        ? <List<_PathPoint>>[convertedPoints]
        : <List<_PathPoint>>[
            for (
              var pathIndex = 0;
              pathIndex < subpathStarts.length;
              pathIndex++
            )
              convertedPoints.sublist(
                subpathStarts[pathIndex],
                pathIndex + 1 < subpathStarts.length
                    ? subpathStarts[pathIndex + 1]
                    : convertedPoints.length,
              ),
          ];
    return _SvgPathData(
      points: convertedPoints,
      subpaths: convertedSubpaths,
      subpathClosed: subpathStarts.isEmpty ? <bool>[closed] : subpathClosed,
      closed: closed,
      hasCurve: hasCurve,
    );
  }

  static void _appendArc(
    List<_MutablePathPoint> points,
    Offset start,
    Offset end,
    double rx,
    double ry,
    double rotation,
    bool largeArc,
    bool sweep,
  ) {
    if ((start - end).distance < 0.001 || rx == 0 || ry == 0) {
      points.add(_MutablePathPoint(point: end));
      return;
    }
    final phi = rotation * math.pi / 180;
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final dx = (start.dx - end.dx) / 2;
    final dy = (start.dy - end.dy) / 2;
    final xPrime = cosPhi * dx + sinPhi * dy;
    final yPrime = -sinPhi * dx + cosPhi * dy;
    final lambda = xPrime * xPrime / (rx * rx) + yPrime * yPrime / (ry * ry);
    if (lambda > 1) {
      final factor = math.sqrt(lambda);
      rx *= factor;
      ry *= factor;
    }
    final numerator =
        rx * rx * ry * ry -
        rx * rx * yPrime * yPrime -
        ry * ry * xPrime * xPrime;
    final denominator = rx * rx * yPrime * yPrime + ry * ry * xPrime * xPrime;
    final coefficient = denominator == 0
        ? 0.0
        : (largeArc == sweep ? -1 : 1) *
              math.sqrt(math.max(0.0, numerator / denominator));
    final cxPrime = coefficient * (rx * yPrime / ry);
    final cyPrime = coefficient * (-ry * xPrime / rx);
    final center = Offset(
      cosPhi * cxPrime - sinPhi * cyPrime + (start.dx + end.dx) / 2,
      sinPhi * cxPrime + cosPhi * cyPrime + (start.dy + end.dy) / 2,
    );
    double angle(Offset u, Offset v) {
      final dot = u.dx * v.dx + u.dy * v.dy;
      final cross = u.dx * v.dy - u.dy * v.dx;
      return math.atan2(cross, dot);
    }

    final u = Offset((xPrime - cxPrime) / rx, (yPrime - cyPrime) / ry);
    final v = Offset((-xPrime - cxPrime) / rx, (-yPrime - cyPrime) / ry);
    var delta = angle(const Offset(1, 0), v) - angle(const Offset(1, 0), u);
    if (!sweep && delta > 0) delta -= 2 * math.pi;
    if (sweep && delta < 0) delta += 2 * math.pi;
    final segmentCount = math.min(
      32,
      math.max(1, (delta.abs() / (math.pi / 8)).ceil()),
    );
    final startAngle = angle(const Offset(1, 0), u);
    Offset ellipsePoint(double theta) => Offset(
      center.dx + rx * math.cos(theta) * cosPhi - ry * math.sin(theta) * sinPhi,
      center.dy + rx * math.cos(theta) * sinPhi + ry * math.sin(theta) * cosPhi,
    );
    Offset tangent(double theta) => Offset(
      -rx * math.sin(theta) * cosPhi - ry * math.cos(theta) * sinPhi,
      -rx * math.sin(theta) * sinPhi + ry * math.cos(theta) * cosPhi,
    );
    for (var index = 1; index <= segmentCount; index++) {
      final theta0 = startAngle + delta * (index - 1) / segmentCount;
      final theta1 = startAngle + delta * index / segmentCount;
      final deltaTheta = theta1 - theta0;
      final factor = 4 / 3 * math.tan(deltaTheta / 4);
      final startPoint = ellipsePoint(theta0);
      final endPoint = ellipsePoint(theta1);
      final cp1 = startPoint + tangent(theta0) * factor;
      final cp2 = endPoint - tangent(theta1) * factor;
      if (points.isNotEmpty) {
        points.last.handleOut = cp1 - points.last.point;
      }
      points.add(_MutablePathPoint(point: endPoint, handleIn: cp2 - endPoint));
    }
  }
}

class _MutablePathPoint {
  final Offset point;
  Offset handleIn;
  Offset handleOut = Offset.zero;

  _MutablePathPoint({required this.point, this.handleIn = Offset.zero});
}

class _SvgConversionFailure implements Exception {
  final MermaidDiagnostic diagnostic;

  const _SvgConversionFailure(this.diagnostic);
}

bool _isAxisAligned(List<Offset> points) {
  if (points.length < 4) return false;
  final bounds = _boundsForPoints(points);
  return points.every(
        (point) =>
            (point.dx - bounds.left).abs() < 0.01 ||
            (point.dx - bounds.right).abs() < 0.01,
      ) &&
      points.every(
        (point) =>
            (point.dy - bounds.top).abs() < 0.01 ||
            (point.dy - bounds.bottom).abs() < 0.01,
      );
}

bool _isAxisAlignedTransform(_Affine transform) =>
    transform.b.abs() < 0.0001 && transform.c.abs() < 0.0001;

Rect _boundsForPoints(List<Offset> points) {
  if (points.isEmpty) return Rect.zero;
  var minX = points.first.dx;
  var minY = points.first.dy;
  var maxX = minX;
  var maxY = minY;
  for (final point in points.skip(1)) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double? _number(String? raw) {
  if (raw == null) return null;
  final match = RegExp(
    r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).firstMatch(raw);
  final value = match == null ? null : double.tryParse(match.group(0)!);
  return value != null && value.isFinite ? value : null;
}

List<double> _numberList(String raw) {
  if (raw.trim().isEmpty || raw.trim().toLowerCase() == 'none') {
    return const [];
  }

  final values = <double>[];
  final pattern = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
  var consumed = 0;
  for (final match in pattern.allMatches(raw)) {
    final separator = raw.substring(consumed, match.start);
    if (separator.replaceAll(RegExp(r'[\s,]'), '').isNotEmpty) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_NUMBER_INVALID',
          message: 'Mermaid SVG contains invalid numeric geometry.',
        ),
      );
    }
    final value = double.tryParse(match.group(0)!);
    if (value == null || !value.isFinite) {
      throw const _SvgConversionFailure(
        MermaidDiagnostic(
          code: 'SVG_NUMBER_INVALID',
          message: 'Mermaid SVG contains invalid numeric geometry.',
        ),
      );
    }
    values.add(value);
    consumed = match.end;
  }
  if (values.isEmpty ||
      raw.substring(consumed).replaceAll(RegExp(r'[\s,]'), '').isNotEmpty) {
    throw const _SvgConversionFailure(
      MermaidDiagnostic(
        code: 'SVG_NUMBER_INVALID',
        message: 'Mermaid SVG contains invalid numeric geometry.',
      ),
    );
  }
  return values;
}

Color? _applyOpacity(Color? color, double opacity) {
  if (color == null) return null;
  return color.withValues(alpha: (color.a * opacity).clamp(0.0, 1.0));
}

Color? _parseColor(String? raw) {
  if (raw == null) return null;
  final value = raw.trim().toLowerCase();
  if (value.isEmpty || value == 'none') return null;
  const named = {
    'black': Color(0xFF000000),
    'white': Color(0xFFFFFFFF),
    'red': Color(0xFFFF0000),
    'green': Color(0xFF008000),
    'blue': Color(0xFF0000FF),
    'gray': Color(0xFF808080),
    'grey': Color(0xFF808080),
    'transparent': Color(0x00000000),
  };
  if (named[value] != null) return named[value];
  if (value.startsWith('#')) {
    final hex = value.substring(1);
    if (hex.length == 3) {
      final r = int.parse('${hex[0]}${hex[0]}', radix: 16);
      final g = int.parse('${hex[1]}${hex[1]}', radix: 16);
      final b = int.parse('${hex[2]}${hex[2]}', radix: 16);
      return Color.from(alpha: 1, red: r / 255, green: g / 255, blue: b / 255);
    }
    if (hex.length == 6 || hex.length == 8) {
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      final alpha = hex.length == 8
          ? int.parse(hex.substring(6, 8), radix: 16) / 255
          : 1.0;
      return Color.from(
        alpha: alpha,
        red: r / 255,
        green: g / 255,
        blue: b / 255,
      );
    }
  }
  final rgb = RegExp(r'rgba?\(([^)]*)\)').firstMatch(value);
  if (rgb != null) {
    final parts = rgb.group(1)!.split(',').map((part) => part.trim()).toList();
    if (parts.length >= 3) {
      double channel(String part) => part.endsWith('%')
          ? (double.tryParse(part.substring(0, part.length - 1)) ?? 0) * 2.55
          : (double.tryParse(part) ?? 0);
      final alpha = parts.length == 4
          ? (double.tryParse(parts[3]) ?? 1).clamp(0.0, 1.0)
          : 1.0;
      return Color.from(
        alpha: alpha,
        red: channel(parts[0]).clamp(0, 255) / 255,
        green: channel(parts[1]).clamp(0, 255) / 255,
        blue: channel(parts[2]).clamp(0, 255) / 255,
      );
    }
  }

  final hsl = RegExp(r'hsla?\(([^)]*)\)').firstMatch(value);
  if (hsl != null) {
    final parts = hsl
        .group(1)!
        .split(',')
        .map((part) => part.trim().replaceAll('%', ''))
        .toList();
    if (parts.length >= 3) {
      final hue = (double.tryParse(parts[0]) ?? 0) % 360;
      final saturation = (double.tryParse(parts[1]) ?? 0).clamp(0, 100) / 100;
      final lightness = (double.tryParse(parts[2]) ?? 0).clamp(0, 100) / 100;
      final alpha = parts.length == 4
          ? (double.tryParse(parts[3]) ?? 1).clamp(0.0, 1.0)
          : 1.0;
      return HSLColor.fromAHSL(alpha, hue, saturation, lightness).toColor();
    }
  }
  return null;
}

String? _markerId(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'url\(\s*#([A-Za-z0-9_.:-]+)\s*\)').firstMatch(raw);
  return match?.group(1);
}

LineMarker _marker(String? raw) {
  if (raw == null || raw.isEmpty || raw.toLowerCase().contains('none')) {
    return LineMarker.none;
  }
  final lower = raw.toLowerCase();
  if (lower.contains('circle')) return LineMarker.circle;
  if (lower.contains('diamond')) return LineMarker.diamond;
  if (lower.contains('arrow') ||
      lower.contains('point') ||
      lower.contains('triangle')) {
    return LineMarker.arrow;
  }
  return LineMarker.none;
}
