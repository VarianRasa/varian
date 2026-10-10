import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';

class DrawioXmlException implements Exception {
  final String message;

  const DrawioXmlException(this.message);

  @override
  String toString() => 'DrawioXmlException: $message';
}

class DrawioImportResult {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;

  const DrawioImportResult({this.nodes = const [], this.edges = const []});

  bool get isSuccess => nodes.isNotEmpty || edges.isNotEmpty;
}

/// Bounded Draw.io/mxGraph XML codec.
///
/// Only local XML data is parsed. External entities, scripts, and remote
/// references are not resolved by package:xml and are rejected explicitly.
class DrawioXmlCodec {
  DrawioXmlCodec._();

  static const maxXmlBytes = 2 * 1024 * 1024;
  static const maxCells = 12000;
  static const maxLabelLength = 16 * 1024;
  static const maxStyleLength = 16 * 1024;
  static const maxWaypoints = CanvasEdge.maxWaypoints;
  static const maxChartMetadataBytes = 128 * 1024;
  static const _chartMetadataAttribute = 'data-varian-chart';

  static DrawioImportResult importDocument(String rawXml) {
    _validateRawXml(rawXml);

    late final XmlDocument document;
    try {
      document = XmlDocument.parse(rawXml);
    } on XmlParserException catch (error) {
      throw DrawioXmlException('Malformed Draw.io XML: ${error.message}');
    } catch (_) {
      throw const DrawioXmlException('Malformed Draw.io XML.');
    }

    final model = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'mxGraphModel')
        .firstOrNull;
    if (model == null) {
      throw const DrawioXmlException('Expected an mxGraphModel root element.');
    }

    final cells = model.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'mxCell')
        .toList(growable: false);
    if (cells.length > maxCells) {
      throw const DrawioXmlException('Draw.io XML contains too many cells.');
    }

    final infos = <_CellInfo>[];
    for (final cell in cells) {
      final id = cell.getAttribute('id');
      if (id == null || id.isEmpty || id == '0' || id == '1') continue;

      final style = cell.getAttribute('style') ?? '';
      if (style.length > maxStyleLength) {
        throw const DrawioXmlException('Draw.io style is too large.');
      }
      final value = cell.getAttribute('value') ?? '';
      if (value.length > maxLabelLength) {
        throw const DrawioXmlException('Draw.io label is too large.');
      }

      final isVertex = cell.getAttribute('vertex') == '1';
      final isEdge = cell.getAttribute('edge') == '1';
      final isLayer =
          !isVertex && !isEdge && cell.getAttribute('parent') == '0';
      if (!isVertex && !isEdge && !isLayer) continue;

      final geometry = cell.childElements
          .where((element) => element.name.local == 'mxGeometry')
          .firstOrNull;
      final points = geometry == null
          ? const <Offset>[]
          : geometry.descendants
                .whereType<XmlElement>()
                .where((element) => element.name.local == 'mxPoint')
                .take(maxWaypoints)
                .map(_pointFromElement)
                .whereType<Offset>()
                .toList(growable: false);

      infos.add(
        _CellInfo(
          id: id,
          value: value,
          style: isLayer && style.isEmpty ? 'shape=group;' : style,
          parentId: cell.getAttribute('parent'),
          sourceId: cell.getAttribute('source'),
          targetId: cell.getAttribute('target'),
          isVertex: isVertex || isLayer,
          isEdge: isEdge,
          x: _number(geometry?.getAttribute('x')),
          y: _number(geometry?.getAttribute('y')),
          width: _positiveNumber(geometry?.getAttribute('width'), 120),
          height: _positiveNumber(geometry?.getAttribute('height'), 70),
          points: points,
          chartMetadata: cell.getAttribute(_chartMetadataAttribute),
          xml: cell.toXmlString(),
        ),
      );
    }

    final vertexInfos = infos.where((info) => info.isVertex).toList();
    final vertexById = <String, _CellInfo>{
      for (final info in vertexInfos) info.id: info,
    };
    final resolvedPositions = <String, Offset>{};
    final resolving = <String>{};

    Offset positionFor(_CellInfo info) {
      final cached = resolvedPositions[info.id];
      if (cached != null) return cached;
      if (!resolving.add(info.id)) {
        throw const DrawioXmlException('Draw.io cell hierarchy is recursive.');
      }
      final parent = vertexById[info.parentId];
      final parentPosition = parent == null ? Offset.zero : positionFor(parent);
      final position = Offset(info.x, info.y) + parentPosition;
      resolving.remove(info.id);
      resolvedPositions[info.id] = position;
      return position;
    }

    var nodes = <CanvasNode>[];
    for (final info in vertexInfos) {
      final position = positionFor(info);
      nodes.add(_nodeFromCell(info, position));
    }
    final childrenByParent = <String, List<String>>{};
    for (final node in nodes) {
      final parentId = node.parentId;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(node.id);
      }
    }
    nodes = nodes
        .map((node) {
          if (node.type != NodeType.group || node.payload is! GroupPayload) {
            return node;
          }
          final payload = node.payload as GroupPayload;
          return node.copyWith(
            payload: payload.copyWith(
              childNodeIds: childrenByParent[node.id] ?? const [],
            ),
          );
        })
        .toList(growable: false);

    final nodeIds = nodes.map((node) => node.id).toSet();
    final edges = <CanvasEdge>[];
    for (final info in infos.where((info) => info.isEdge)) {
      final source = info.sourceId;
      final target = info.targetId;
      if (source == null || target == null) continue;
      if (!nodeIds.contains(source)) {
        throw DrawioXmlException(
          'Draw.io edge ${info.id} references unknown source node: $source',
        );
      }
      if (!nodeIds.contains(target)) {
        throw DrawioXmlException(
          'Draw.io edge ${info.id} references unknown target node: $target',
        );
      }
      edges.add(_edgeFromCell(info));
    }

    if (nodes.isEmpty && edges.isEmpty) {
      throw const DrawioXmlException('No drawable Draw.io cells found.');
    }
    return DrawioImportResult(nodes: nodes, edges: edges);
  }

  static String exportDocument({
    required List<CanvasNode> nodes,
    List<CanvasEdge> edges = const [],
  }) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'mxGraphModel',
      attributes: const {
        'dx': '1200',
        'dy': '800',
        'grid': '1',
        'gridSize': '10',
        'page': '1',
        'pageScale': '1',
      },
      nest: () {
        builder.element(
          'root',
          nest: () {
            builder.element('mxCell', attributes: const {'id': '0'});
            builder.element(
              'mxCell',
              attributes: const {'id': '1', 'parent': '0'},
            );

            final orderedNodes = List<CanvasNode>.from(nodes)
              ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
            for (final node in orderedNodes) {
              _writeNode(builder, node, nodes);
            }
            for (final edge in edges) {
              _writeEdge(builder, edge);
            }
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: true);
  }

  static void _writeNode(
    XmlBuilder builder,
    CanvasNode node,
    List<CanvasNode> allNodes,
  ) {
    final payload = node.payload is ShapePayload
        ? node.payload as ShapePayload
        : null;
    final value = switch (node.payload) {
      TextPayload text => text.text,
      StickyNotePayload note => note.text,
      ShapePayload shape => shape.label,
      FramePayload frame => frame.name,
      GroupPayload group => group.name,
      _ => node.name ?? '',
    };
    final style = _styleForNode(node, payload);
    final parentNode = allNodes
        .where((candidate) => candidate.id == node.parentId)
        .firstOrNull;
    final parent = parentNode == null ? '1' : parentNode.id;
    final geometryX = node.x - (parentNode?.x ?? 0.0);
    final geometryY = node.y - (parentNode?.y ?? 0.0);
    final rawCellXml = switch (node.payload) {
      ShapePayload shape => shape.rawDrawioCellXml,
      FramePayload frame => frame.rawDrawioCellXml,
      GroupPayload group => group.rawDrawioCellXml,
      _ => null,
    };

    builder.element(
      'mxCell',
      attributes: {
        ..._rawCellAttributes(rawCellXml, const {
          'id',
          'value',
          'style',
          'vertex',
          'edge',
          'parent',
          _chartMetadataAttribute,
        }),
        if (node.payload case final ChartPayload chart)
          _chartMetadataAttribute: _encodeChartMetadata(chart),
        'id': node.id,
        'value': value,
        'style': style,
        'vertex': '1',
        'parent': parent,
      },
      nest: () {
        builder.element(
          'mxGeometry',
          attributes: {
            'x': _format(geometryX),
            'y': _format(geometryY),
            'width': _format(node.width),
            'height': _format(node.height),
            'as': 'geometry',
          },
        );
      },
    );
  }

  static void _writeEdge(XmlBuilder builder, CanvasEdge edge) {
    final attributes = <String, String>{
      ..._rawCellAttributes(edge.rawDrawioCellXml, const {
        'id',
        'value',
        'style',
        'vertex',
        'edge',
        'parent',
        'source',
        'target',
      }),
      'id': edge.id,
      'value': edge.label ?? '',
      'style': _styleForEdge(edge),
      'edge': '1',
      'parent': edge.parentId ?? '1',
    };
    if (edge.sourceNodeId != null) attributes['source'] = edge.sourceNodeId!;
    if (edge.targetNodeId != null) attributes['target'] = edge.targetNodeId!;

    builder.element(
      'mxCell',
      attributes: attributes,
      nest: () {
        builder.element(
          'mxGeometry',
          attributes: const {'relative': '1', 'as': 'geometry'},
          nest: () {
            if (edge.waypoints.isNotEmpty) {
              builder.element(
                'Array',
                attributes: const {'as': 'points'},
                nest: () {
                  for (final point in edge.waypoints.take(maxWaypoints)) {
                    builder.element(
                      'mxPoint',
                      attributes: {
                        'x': _format(point.dx),
                        'y': _format(point.dy),
                      },
                    );
                  }
                },
              );
            }
          },
        );
      },
    );
  }

  static CanvasNode _nodeFromCell(_CellInfo info, Offset position) {
    final style = _parseStyle(info.style);
    final chartPayload = _decodeChartMetadata(info.chartMetadata);
    final shapeId = _shapeId(style);
    final type = chartPayload == null
        ? _nodeTypeForShape(shapeId, style)
        : NodeType.chart;
    final shape = ShapePayload(
      fill: _color(style['fillColor'], const Color(0xFF2563EB)),
      fillOpacity: _opacity(style['fillOpacity']),
      stroke: _color(style['strokeColor'], const Color(0xFF60A5FA)),
      strokeWidth: _number(style['strokeWidth'], fallback: 2).clamp(0.0, 64.0),
      cornerRadius: _cornerRadius(style),
      hasShadow: style['shadow'] == '1',
      strokeStyle: style['dashed'] == '1'
          ? StrokeStyle.dashed
          : StrokeStyle.solid,
      label: info.value,
      labelColor: _color(style['fontColor'], Colors.white),
      labelFontSize: _number(style['fontSize'], fallback: 14).clamp(6.0, 96.0),
      diagramShapeId: shapeId,
      rawDrawioStyle: info.style.isEmpty ? null : info.style,
      rawDrawioCellXml: info.xml,
    );

    final payload = switch (type) {
      NodeType.frame => FramePayload(
        name: info.value.isEmpty ? 'Container' : info.value,
        cornerRadius: _cornerRadius(style),
        background: shape.fill,
        borderColor: shape.stroke,
        borderWidth: shape.strokeWidth,
        isDashedBorder: shape.strokeStyle == StrokeStyle.dashed,
        hasShadow: shape.hasShadow,
        rawDrawioStyle: info.style.isEmpty ? null : info.style,
        rawDrawioCellXml: info.xml,
      ),
      NodeType.stickyNote => StickyNotePayload(
        text: info.value.isEmpty ? 'Note' : info.value,
      ),
      NodeType.group => GroupPayload(
        name: info.value.isEmpty ? 'Group' : info.value,
        rawDrawioStyle: info.style.isEmpty ? null : info.style,
        rawDrawioCellXml: info.xml,
      ),
      NodeType.chart => chartPayload ?? ChartPayload(),
      _ => shape,
    };

    return CanvasNode(
      id: info.id,
      type: type,
      x: position.dx,
      y: position.dy,
      width: info.width,
      height: info.height,
      rotation: math.pi * _number(style['rotation']) / 180.0,
      opacity: _opacity(style['opacity']),
      parentId: info.parentId == '0' || info.parentId == '1'
          ? null
          : info.parentId,
      payload: payload,
    );
  }

  static CanvasEdge _edgeFromCell(_CellInfo info) {
    final style = _parseStyle(info.style);
    return CanvasEdge(
      id: info.id,
      sourceNodeId: info.sourceId,
      targetNodeId: info.targetId,
      routing: _routing(style),
      strokeColor: _color(style['strokeColor'], const Color(0xFF94A3B8)),
      strokeWidth: _number(style['strokeWidth'], fallback: 2).clamp(0.5, 64.0),
      strokeStyle: style['dashed'] == '1'
          ? StrokeStyle.dashed
          : StrokeStyle.solid,
      startMarker: _marker(style['startArrow']),
      endMarker: _marker(style['endArrow'], fallback: LineMarker.arrow),
      label: info.value.isEmpty ? null : info.value,
      waypoints: info.points,
      parentId: info.parentId == '0' || info.parentId == '1'
          ? null
          : info.parentId,
      rawDrawioStyle: info.style.isEmpty ? null : info.style,
      rawDrawioCellXml: info.xml,
    );
  }

  static NodeType _nodeTypeForShape(String shapeId, Map<String, String> style) {
    final normalized = shapeId.toLowerCase();
    if (normalized == 'group' || normalized == 'layer') {
      return NodeType.group;
    }
    if (normalized.contains('swimlane') ||
        normalized.contains('pool') ||
        normalized.contains('lane') ||
        normalized == 'frame' ||
        normalized == 'container') {
      return NodeType.frame;
    }
    if (normalized == 'note' || normalized == 'callout') {
      return NodeType.stickyNote;
    }
    if (normalized == 'ellipse' ||
        normalized == 'circle' ||
        normalized.contains('event') ||
        normalized.contains('usecase') ||
        normalized.contains('entity')) {
      return NodeType.ellipse;
    }
    if (normalized == 'rhombus' ||
        normalized == 'diamond' ||
        normalized.contains('decision') ||
        normalized.contains('gateway')) {
      return NodeType.diamond;
    }
    if (normalized == 'cylinder' || normalized == 'database') {
      return NodeType.cylinder;
    }
    if (normalized == 'parallelogram' || normalized == 'data') {
      return NodeType.parallelogram;
    }
    return NodeType.rectangle;
  }

  static String _shapeId(Map<String, String> style) {
    final raw = style['shape']?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    if (style['rounded'] == '1') return 'roundedRectangle';
    return 'rectangle';
  }

  static String _styleForNode(CanvasNode node, ShapePayload? payload) {
    final frame = node.payload is FramePayload
        ? node.payload as FramePayload
        : null;
    final group = node.payload is GroupPayload
        ? node.payload as GroupPayload
        : null;
    final rawStyle = payload?.rawDrawioStyle ?? frame?.rawDrawioStyle;
    if (payload == null && frame == null && group?.rawDrawioStyle != null) {
      return group!.rawDrawioStyle!;
    }

    final parts = _parseStyle(rawStyle ?? '');
    final shape =
        payload?.diagramShapeId ??
        parts['shape'] ??
        switch (node.type) {
          NodeType.ellipse => 'ellipse',
          NodeType.diamond => 'rhombus',
          NodeType.cylinder => 'cylinder',
          NodeType.parallelogram => 'parallelogram',
          NodeType.frame => 'swimlane',
          NodeType.group => 'group',
          NodeType.stickyNote => 'note',
          _ => 'rectangle',
        };
    parts['shape'] = _drawioShapeKey(shape);
    parts.putIfAbsent('whiteSpace', () => 'wrap');
    parts.putIfAbsent('html', () => '1');

    final fill = payload?.fill ?? frame?.background;
    final stroke = payload?.stroke ?? frame?.borderColor;
    final strokeWidth = payload?.strokeWidth ?? frame?.borderWidth;
    if (fill != null) parts['fillColor'] = _hex(fill);
    if (stroke != null) parts['strokeColor'] = _hex(stroke);
    if (strokeWidth != null) {
      parts['strokeWidth'] = _format(strokeWidth);
    }
    parts['opacity'] = '${(node.opacity.clamp(0.0, 1.0) * 100).round()}';
    final rotationDegrees = node.rotation * 180.0 / math.pi;
    if (rotationDegrees.abs() > 0.001) {
      parts['rotation'] = _format(rotationDegrees);
    } else {
      parts.remove('rotation');
    }
    if (payload != null) {
      parts['fontColor'] = _hex(payload.labelColor);
      parts['fontSize'] = _format(payload.labelFontSize);
    }

    final hasShadow = payload?.hasShadow ?? frame?.hasShadow;
    if (hasShadow != null) {
      if (hasShadow) {
        parts['shadow'] = '1';
      } else {
        parts.remove('shadow');
      }
    }

    final cornerRadius = payload?.cornerRadius ?? frame?.cornerRadius;
    if (cornerRadius != null) {
      if (cornerRadius > 0) {
        parts['rounded'] = '1';
      } else {
        parts.remove('rounded');
      }
    }
    final strokeStyle = payload?.strokeStyle;
    if (strokeStyle != null) {
      if (strokeStyle == StrokeStyle.dashed) {
        parts['dashed'] = '1';
      } else {
        parts.remove('dashed');
      }
    } else if (frame != null) {
      if (frame.isDashedBorder) {
        parts['dashed'] = '1';
      } else {
        parts.remove('dashed');
      }
    }
    if (payload != null && payload.fillOpacity < 1.0) {
      parts['fillOpacity'] =
          '${(payload.fillOpacity.clamp(0.0, 1.0) * 100).round()}';
    } else {
      parts.remove('fillOpacity');
    }
    return '${parts.entries.map((entry) => '${entry.key}=${entry.value}').join(';')};';
  }

  static String _styleForEdge(CanvasEdge edge) {
    final routing = switch (edge.routing) {
      ConnectorRouting.orthogonal => 'orthogonalEdgeStyle',
      ConnectorRouting.curved => 'sideToSideEdgeStyle',
      ConnectorRouting.straight => 'none',
    };
    final parts = _parseStyle(edge.rawDrawioStyle ?? '');
    parts['edgeStyle'] = routing;
    parts.putIfAbsent('rounded', () => '0');
    parts['strokeColor'] = _hex(edge.strokeColor);
    parts['strokeWidth'] = _format(edge.strokeWidth);
    parts['startArrow'] = _drawioMarker(edge.startMarker);
    parts['endArrow'] = _drawioMarker(edge.endMarker);
    if (edge.strokeStyle == StrokeStyle.dashed) {
      parts['dashed'] = '1';
    } else {
      parts.remove('dashed');
    }
    return '${parts.entries.map((entry) => '${entry.key}=${entry.value}').join(';')};';
  }

  static String _drawioShapeKey(String id) {
    if (id.startsWith('flowchart.')) {
      return switch (id.substring('flowchart.'.length)) {
        'decision' => 'rhombus',
        'terminator' => 'terminator',
        'start' => 'ellipse',
        'process' => 'process',
        'document' => 'document',
        _ => id.substring('flowchart.'.length),
      };
    }
    if (id == 'roundedRectangle') return 'rectangle';
    return id;
  }

  static String _encodeChartMetadata(ChartPayload payload) {
    final bytes = utf8.encode(jsonEncode(payload.toJson()));
    if (bytes.length > maxChartMetadataBytes) return '';
    return base64UrlEncode(bytes);
  }

  static ChartPayload? _decodeChartMetadata(String? encoded) {
    if (encoded == null || encoded.isEmpty || encoded.length > 256 * 1024) {
      return null;
    }
    try {
      final bytes = base64Url.decode(encoded);
      if (bytes.length > maxChartMetadataBytes) return null;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      return ChartPayload.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _rawCellAttributes(
    String? rawXml,
    Set<String> reserved,
  ) {
    if (rawXml == null || rawXml.isEmpty || rawXml.length > maxXmlBytes) {
      return const {};
    }
    try {
      _validateRawXml(rawXml);
      final document = XmlDocument.parse(rawXml);
      final cell = document.rootElement;
      if (cell.name.local != 'mxCell') return const {};
      final attributes = <String, String>{};
      for (final attribute in cell.attributes.take(64)) {
        final name = attribute.name.local;
        if (reserved.contains(name) || name.isEmpty) continue;
        final value = attribute.value;
        if (value.length <= maxStyleLength) attributes[name] = value;
      }
      return attributes;
    } catch (_) {
      return const {};
    }
  }

  static Map<String, String> _parseStyle(String style) {
    final result = <String, String>{};
    for (final item in style.split(';')) {
      final token = item.trim();
      if (token.isEmpty) continue;
      final separator = token.indexOf('=');
      if (separator <= 0) {
        result.putIfAbsent('shape', () => token);
        continue;
      }
      final key = token.substring(0, separator).trim();
      final value = token.substring(separator + 1).trim();
      if (key.isEmpty) continue;
      result[key] = value;
    }
    return result;
  }

  static double _cornerRadius(Map<String, String> style) {
    if (style['rounded'] != '1') return 0.0;
    final arcSize = _number(style['arcSize'], fallback: 12);
    return arcSize.clamp(0.0, 100.0);
  }

  static ConnectorRouting _routing(Map<String, String> style) {
    if (style['curved'] == '1' || style['edgeStyle'] == 'sideToSideEdgeStyle') {
      return ConnectorRouting.curved;
    }
    if (style['edgeStyle'] == 'orthogonalEdgeStyle' ||
        style['orthogonalLoop'] == '1') {
      return ConnectorRouting.orthogonal;
    }
    return ConnectorRouting.straight;
  }

  static LineMarker _marker(
    String? value, {
    LineMarker fallback = LineMarker.none,
  }) {
    return switch (value?.toLowerCase()) {
      'classic' || 'block' || 'open' || 'async' => LineMarker.arrow,
      'oval' || 'circle' => LineMarker.circle,
      'diamond' => LineMarker.diamond,
      'none' || null || '' => LineMarker.none,
      _ => fallback,
    };
  }

  static String _drawioMarker(LineMarker marker) => switch (marker) {
    LineMarker.arrow => 'classic',
    LineMarker.circle => 'oval',
    LineMarker.diamond => 'diamond',
    LineMarker.none => 'none',
  };

  static Offset? _pointFromElement(XmlElement element) {
    final x = double.tryParse(element.getAttribute('x') ?? '');
    final y = double.tryParse(element.getAttribute('y') ?? '');
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    if (x.abs() > 10000000 || y.abs() > 10000000) return null;
    return Offset(x, y);
  }

  static double _number(String? raw, {double fallback = 0.0}) {
    final value = double.tryParse(raw ?? '');
    return value != null && value.isFinite && value.abs() <= 10000000
        ? value
        : fallback;
  }

  static double _positiveNumber(String? raw, double fallback) {
    return _number(raw, fallback: fallback).clamp(0.01, 10000000);
  }

  static double _opacity(String? raw) {
    final value = _number(raw, fallback: 100);
    return (value > 1 ? value / 100 : value).clamp(0.0, 1.0);
  }

  static Color _color(String? raw, Color fallback) {
    if (raw == null || raw.isEmpty || raw == 'none') {
      return raw == 'none' ? const Color(0x00000000) : fallback;
    }
    final value = raw.replaceFirst('#', '');
    if (value.length != 6 && value.length != 8) return fallback;
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return fallback;
    return Color(value.length == 6 ? 0xFF000000 | parsed : parsed);
  }

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  static String _format(double value) => value.toStringAsFixed(1);

  static void _validateRawXml(String rawXml) {
    if (utf8.encode(rawXml).length > maxXmlBytes) {
      throw const DrawioXmlException('Draw.io XML exceeds the size limit.');
    }
    if (RegExp(
      r'<\s*!DOCTYPE|<!\[CDATA\[|<\s*script\b',
      caseSensitive: false,
    ).hasMatch(rawXml)) {
      throw const DrawioXmlException('Unsupported or unsafe XML content.');
    }
  }
}

class _CellInfo {
  final String id;
  final String value;
  final String style;
  final String? parentId;
  final String? sourceId;
  final String? targetId;
  final bool isVertex;
  final bool isEdge;
  final double x;
  final double y;
  final double width;
  final double height;
  final List<Offset> points;
  final String? chartMetadata;
  final String xml;

  const _CellInfo({
    required this.id,
    required this.value,
    required this.style,
    required this.parentId,
    required this.sourceId,
    required this.targetId,
    required this.isVertex,
    required this.isEdge,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.points,
    required this.chartMetadata,
    required this.xml,
  });
}
