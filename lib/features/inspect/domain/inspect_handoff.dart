import 'dart:convert';
import 'dart:ui';

import '../../../domain/models/document.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../export/export_service.dart';

enum InspectHandoffFormat { css, flutter, svg, json }

class InspectNodeSnapshot {
  final String id;
  final String type;
  final String name;
  final Rect bounds;
  final double rotation;
  final double opacity;
  final bool visible;
  final bool locked;
  final String? parentId;
  final String? pageId;
  final Map<String, dynamic> spacing;
  final Map<String, dynamic> styles;
  final Map<String, dynamic> typography;
  final Map<String, dynamic> tokens;
  final Map<String, dynamic> asset;
  final Map<String, dynamic> nodeData;

  const InspectNodeSnapshot({
    required this.id,
    required this.type,
    required this.name,
    required this.bounds,
    required this.rotation,
    required this.opacity,
    required this.visible,
    required this.locked,
    required this.parentId,
    required this.pageId,
    required this.spacing,
    required this.styles,
    required this.typography,
    required this.tokens,
    required this.asset,
    required this.nodeData,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'bounds': {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
    },
    'rotation': rotation,
    'opacity': opacity,
    'visible': visible,
    'locked': locked,
    'parentId': parentId,
    'pageId': pageId,
    'spacing': spacing,
    'styles': styles,
    'typography': typography,
    'tokens': tokens,
    'asset': asset,
    'node': nodeData,
  };
}

class InspectHandoffBundle {
  static const int schemaVersion = 1;

  final int documentSchemaVersion;
  final String projectId;
  final String canvasId;
  final Rect bounds;
  final List<String> sourceNodeIds;
  final List<InspectNodeSnapshot> nodes;

  const InspectHandoffBundle({
    required this.documentSchemaVersion,
    required this.projectId,
    required this.canvasId,
    required this.bounds,
    required this.sourceNodeIds,
    required this.nodes,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'documentSchemaVersion': documentSchemaVersion,
    'projectId': projectId,
    'canvasId': canvasId,
    'bounds': {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
    },
    'sourceNodeIds': sourceNodeIds,
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
  };

  String encodeJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class InspectHandoffService {
  const InspectHandoffService._();

  static InspectHandoffBundle inspect(
    CanvasDocument document, {
    Iterable<String>? nodeIds,
  }) {
    final requestedIds = nodeIds?.toSet() ?? const <String>{};
    final visibleNodes =
        document.nodes
            .where((node) => node.visible)
            .where(
              (node) => requestedIds.isEmpty || requestedIds.contains(node.id),
            )
            .toList()
          ..sort((first, second) {
            final zOrder = first.zIndex.compareTo(second.zIndex);
            return zOrder == 0 ? first.id.compareTo(second.id) : zOrder;
          });
    final nodesById = {for (final node in document.nodes) node.id: node};
    final selectionBounds = _boundsOf(visibleNodes);

    return InspectHandoffBundle(
      documentSchemaVersion: document.schemaVersion,
      projectId: document.projectId,
      canvasId: document.canvasId,
      bounds: selectionBounds,
      sourceNodeIds: visibleNodes
          .map((node) => node.id)
          .toList(growable: false),
      nodes: visibleNodes
          .map(
            (node) => _snapshot(
              node,
              allNodes: nodesById,
              selectedNodes: visibleNodes,
            ),
          )
          .toList(growable: false),
    );
  }

  static String export(
    CanvasDocument document, {
    Iterable<String>? nodeIds,
    required InspectHandoffFormat format,
  }) {
    final bundle = inspect(document, nodeIds: nodeIds);
    switch (format) {
      case InspectHandoffFormat.css:
        return _exportCss(bundle);
      case InspectHandoffFormat.flutter:
        return _exportFlutter(bundle);
      case InspectHandoffFormat.svg:
        return _exportSvg(document, bundle);
      case InspectHandoffFormat.json:
        return bundle.encodeJson();
    }
  }

  static String _exportCss(InspectHandoffBundle bundle) {
    final output = StringBuffer()
      ..writeln('/* Varian inspect handoff */')
      ..writeln('/* documentSchemaVersion: ${bundle.documentSchemaVersion} */')
      ..writeln('.varian-handoff {')
      ..writeln('  position: relative;')
      ..writeln('  width: ${_cssNumber(bundle.bounds.width)}px;')
      ..writeln('  height: ${_cssNumber(bundle.bounds.height)}px;')
      ..writeln('}')
      ..writeln();

    for (final node in bundle.nodes) {
      final className = _cssIdentifier(node.id);
      final left = node.bounds.left - bundle.bounds.left;
      final top = node.bounds.top - bundle.bounds.top;
      output
        ..writeln('.varian-node--$className {')
        ..writeln('  position: absolute;')
        ..writeln('  left: ${_cssNumber(left)}px;')
        ..writeln('  top: ${_cssNumber(top)}px;')
        ..writeln('  width: ${_cssNumber(node.bounds.width)}px;')
        ..writeln('  height: ${_cssNumber(node.bounds.height)}px;')
        ..writeln('  opacity: ${_cssNumber(node.opacity)};');
      if (node.rotation != 0) {
        output.writeln('  transform: rotate(${_cssNumber(node.rotation)}deg);');
      }
      _writeCssMap(output, node.styles);
      _writeCssMap(output, node.typography);
      output
        ..writeln('}')
        ..writeln();
    }
    return output.toString().trimRight();
  }

  static String _exportFlutter(InspectHandoffBundle bundle) {
    final output = StringBuffer()
      ..writeln('Widget buildVarianHandoff() {')
      ..writeln('  return SizedBox(')
      ..writeln('    width: ${_dartNumber(bundle.bounds.width)},')
      ..writeln('    height: ${_dartNumber(bundle.bounds.height)},')
      ..writeln('    child: Stack(')
      ..writeln('      children: [');

    for (final node in bundle.nodes) {
      final left = node.bounds.left - bundle.bounds.left;
      final top = node.bounds.top - bundle.bounds.top;
      output
        ..writeln('        Positioned(')
        ..writeln('          left: ${_dartNumber(left)},')
        ..writeln('          top: ${_dartNumber(top)},')
        ..writeln('          width: ${_dartNumber(node.bounds.width)},')
        ..writeln('          height: ${_dartNumber(node.bounds.height)},')
        ..writeln('          child: ${_flutterNode(node)},')
        ..writeln('        ),');
    }
    output
      ..writeln('      ],')
      ..writeln('    ),')
      ..writeln('  );')
      ..writeln('}');
    return output.toString().trimRight();
  }

  static String _exportSvg(
    CanvasDocument document,
    InspectHandoffBundle bundle,
  ) {
    final selectedIds = bundle.sourceNodeIds.toSet();
    final selectedNodes = document.nodes
        .where((node) => selectedIds.contains(node.id))
        .toList(growable: false);
    final selectedEdges = document.edges
        .where(
          (edge) =>
              selectedIds.contains(edge.sourceNodeId) &&
              selectedIds.contains(edge.targetNodeId),
        )
        .toList(growable: false);
    final subset = document.copyWith(
      nodes: selectedNodes,
      edges: selectedEdges,
    );
    return ExportService.exportVectorSvg(subset, sourceNodes: document.nodes);
  }

  static InspectNodeSnapshot _snapshot(
    CanvasNode node, {
    required Map<String, CanvasNode> allNodes,
    required List<CanvasNode> selectedNodes,
  }) {
    final payloadJson = node.payload.toJson();
    return InspectNodeSnapshot(
      id: node.id,
      type: node.type.name,
      name: node.name ?? _payloadName(node.payload) ?? node.type.name,
      bounds: node.bounds,
      rotation: node.rotation,
      opacity: node.opacity,
      visible: node.visible,
      locked: node.locked,
      parentId: node.parentId,
      pageId: node.pageId,
      spacing: _spacing(node, allNodes: allNodes, selectedNodes: selectedNodes),
      styles: _styleValues(payloadJson),
      typography: _typographyValues(node.payload, payloadJson),
      tokens: _tokenValues(payloadJson),
      asset: _assetValues(payloadJson),
      nodeData: _stableMap(node.toJson()),
    );
  }

  static Rect _boundsOf(Iterable<CanvasNode> nodes) {
    Rect? bounds;
    for (final node in nodes) {
      bounds = bounds == null
          ? node.bounds
          : bounds.expandToInclude(node.bounds);
    }
    return bounds ?? Rect.zero;
  }

  static Map<String, dynamic> _spacing(
    CanvasNode node, {
    required Map<String, CanvasNode> allNodes,
    required List<CanvasNode> selectedNodes,
  }) {
    final values = <String, dynamic>{};
    final parent = node.parentId == null ? null : allNodes[node.parentId];
    if (parent != null) {
      values['parent'] = {
        'id': parent.id,
        'left': _round(node.x - parent.x),
        'top': _round(node.y - parent.y),
        'right': _round(parent.x + parent.width - node.x - node.width),
        'bottom': _round(parent.y + parent.height - node.y - node.height),
      };
      final parentPayload = parent.payload.toJson();
      final parentSpacing = <String, dynamic>{};
      for (final key in const [
        'paddingLeft',
        'paddingTop',
        'paddingRight',
        'paddingBottom',
        'itemSpacing',
        'layoutDirection',
      ]) {
        if (parentPayload.containsKey(key)) {
          parentSpacing[key] = parentPayload[key];
        }
      }
      if (parentSpacing.isNotEmpty) values['parentLayout'] = parentSpacing;
    }

    final siblings = selectedNodes
        .where(
          (candidate) =>
              candidate.id != node.id &&
              candidate.parentId == node.parentId &&
              candidate.pageId == node.pageId,
        )
        .toList(growable: false);
    final horizontalGaps = <double>[];
    final verticalGaps = <double>[];
    for (final sibling in siblings) {
      if (node.bounds.overlaps(
        Rect.fromLTRB(
          sibling.x,
          node.y,
          sibling.x + sibling.width,
          node.y + node.height,
        ),
      )) {
        final gap = sibling.x >= node.x
            ? sibling.x - node.x - node.width
            : node.x - sibling.x - sibling.width;
        if (gap >= 0) horizontalGaps.add(gap);
      }
      if (node.bounds.overlaps(
        Rect.fromLTRB(
          node.x,
          sibling.y,
          node.x + node.width,
          sibling.y + sibling.height,
        ),
      )) {
        final gap = sibling.y >= node.y
            ? sibling.y - node.y - node.height
            : node.y - sibling.y - sibling.height;
        if (gap >= 0) verticalGaps.add(gap);
      }
    }
    if (horizontalGaps.isNotEmpty) {
      values['nearestHorizontalGap'] = _round(horizontalGaps.reduce(_min));
    }
    if (verticalGaps.isNotEmpty) {
      values['nearestVerticalGap'] = _round(verticalGaps.reduce(_min));
    }
    return _stableMap(values);
  }

  static Map<String, dynamic> _styleValues(Map<String, dynamic> payload) {
    final values = <String, dynamic>{};
    for (final entry in payload.entries) {
      final key = entry.key;
      final lowerKey = key.toLowerCase();
      final isStyle =
          lowerKey.contains('color') ||
          lowerKey.contains('fill') ||
          lowerKey.contains('stroke') ||
          lowerKey.contains('background') ||
          lowerKey.contains('shadow') ||
          lowerKey.contains('gradient') ||
          lowerKey.contains('radius') ||
          lowerKey.contains('opacity') ||
          lowerKey.contains('blur') ||
          lowerKey.contains('brightness') ||
          lowerKey.contains('contrast') ||
          lowerKey.contains('grayscale') ||
          lowerKey.contains('sepia') ||
          lowerKey.contains('invert') ||
          lowerKey == 'fit' ||
          lowerKey == 'strokeStyle';
      if (isStyle && _isScalar(entry.value)) {
        values[key] = _formatValue(key, entry.value);
      }
    }
    return _stableMap(values);
  }

  static Map<String, dynamic> _typographyValues(
    NodePayload payload,
    Map<String, dynamic> payloadJson,
  ) {
    final values = <String, dynamic>{};
    for (final entry in payloadJson.entries) {
      final key = entry.key;
      final lowerKey = key.toLowerCase();
      final isTypography =
          lowerKey.contains('font') ||
          lowerKey.contains('textalign') ||
          lowerKey.contains('lineheight') ||
          lowerKey.contains('letterspacing') ||
          lowerKey.contains('texttransform') ||
          lowerKey.contains('wrapmode') ||
          lowerKey == 'textalign' ||
          lowerKey == 'underline' ||
          lowerKey == 'strikethrough';
      if (isTypography && _isScalar(entry.value)) {
        values[key] = entry.value;
      }
    }
    if (payload is TextPayload) {
      values['text'] = payload.text;
      values['fontSize'] = payload.fontSize;
      values['fontWeight'] = payload.fontWeight.value;
      values['fontFamily'] = payload.fontFamily;
      values['lineHeight'] = payload.lineHeight;
      values['letterSpacing'] = payload.letterSpacing;
    }
    return _stableMap(values);
  }

  static Map<String, dynamic> _tokenValues(Map<String, dynamic> payload) {
    final values = <String, dynamic>{};
    for (final entry in payload.entries) {
      final lowerKey = entry.key.toLowerCase();
      final value = entry.value;
      if (lowerKey.contains('token') ||
          (value is String &&
              (value.startsWith('token:') || value.startsWith('\$')))) {
        values[entry.key] = value;
      }
    }
    return _stableMap(values);
  }

  static Map<String, dynamic> _assetValues(Map<String, dynamic> payload) {
    final values = <String, dynamic>{};
    for (final entry in payload.entries) {
      final lowerKey = entry.key.toLowerCase();
      final isAsset =
          lowerKey == 'assetid' ||
          lowerKey == 'localpath' ||
          lowerKey == 'url' ||
          lowerKey == 'filename' ||
          lowerKey == 'caption' ||
          lowerKey == 'source' ||
          lowerKey == 'provider' ||
          lowerKey == 'model' ||
          lowerKey == 'license' ||
          lowerKey == 'provenance';
      if (!isAsset || entry.value == null || !_isScalar(entry.value)) continue;
      values[entry.key] = lowerKey == 'url'
          ? _redactUrl(entry.value.toString())
          : entry.value;
    }
    return _stableMap(values);
  }

  static String? _payloadName(NodePayload payload) {
    final value = payload.toJson()['name'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static bool _isScalar(Object? value) =>
      value == null || value is String || value is num || value is bool;

  static dynamic _formatValue(String key, dynamic value) {
    if (value is num && _looksLikeColor(key)) {
      final argb = value.toInt() & 0xFFFFFFFF;
      final alpha = (argb >> 24) & 0xFF;
      final rgb = argb & 0xFFFFFF;
      final rgbHex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
      if (alpha == 0xFF) return '#$rgbHex';
      return '#$rgbHex${alpha.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    }
    return value;
  }

  static bool _looksLikeColor(String key) {
    final lowerKey = key.toLowerCase();
    return lowerKey.contains('color') ||
        lowerKey == 'fill' ||
        lowerKey == 'stroke' ||
        lowerKey == 'background';
  }

  static String _redactUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return value;
    return uri.replace(query: '', fragment: '').toString();
  }

  static Map<String, dynamic> _stableMap(Map<String, dynamic> values) {
    final keys = values.keys.toList()..sort();
    return {
      for (final key in keys)
        key: values[key] is Map
            ? _stableMap(Map<String, dynamic>.from(values[key] as Map))
            : values[key],
    };
  }

  static String _cssIdentifier(String value) {
    final normalized = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
    return normalized.isEmpty ? 'node' : normalized;
  }

  static void _writeCssMap(StringBuffer output, Map<String, dynamic> values) {
    for (final entry in values.entries) {
      final property = _cssProperty(entry.key);
      if (property == null) continue;
      final cssValue = _cssValue(entry.key, entry.value);
      if (cssValue == null) continue;
      output.writeln('  $property: $cssValue;');
    }
  }

  static String? _cssProperty(String key) {
    final mappings = <String, String>{
      'fill': 'background',
      'background': 'background',
      'stroke': 'border-color',
      'strokeWidth': 'border-width',
      'cornerRadius': 'border-radius',
      'backgroundRadius': 'border-radius',
      'fontFamily': 'font-family',
      'fontSize': 'font-size',
      'fontWeight': 'font-weight',
      'lineHeight': 'line-height',
      'letterSpacing': 'letter-spacing',
      'textAlign': 'text-align',
      'textTransform': 'text-transform',
      'color': 'color',
      'backgroundColor': 'background',
      'strokeColor': 'color',
      'opacity': 'opacity',
    };
    return mappings[key];
  }

  static String? _cssValue(String key, dynamic value) {
    if (value == null) return null;
    if (value is num &&
        (key.toLowerCase().contains('width') ||
            key.toLowerCase().contains('radius') ||
            key.toLowerCase().contains('size') ||
            key.toLowerCase().contains('spacing') ||
            key == 'letterSpacing')) {
      return '${_cssNumber(value.toDouble())}px';
    }
    if (value is num) return _cssNumber(value.toDouble());
    if (value is String) return value.contains(' ') ? '"$value"' : value;
    return value.toString();
  }

  static String _flutterNode(InspectNodeSnapshot node) {
    final text = node.typography['text'];
    if (node.type == 'text' && text is String) {
      final family = node.typography['fontFamily'];
      final size = node.typography['fontSize'];
      final color = node.styles['color'];
      final style = StringBuffer('Text(${jsonEncode(text)}');
      final arguments = <String>[];
      if (size is num) {
        arguments.add('fontSize: ${_dartNumber(size.toDouble())}');
      }
      if (family is String) arguments.add('fontFamily: ${jsonEncode(family)}');
      final colorExpression = _flutterColorExpression(color);
      if (colorExpression != null) arguments.add('color: $colorExpression');
      if (arguments.isEmpty) return '$style)';
      return '$style, style: TextStyle(${arguments.join(', ')}))';
    }
    if (node.type == 'image') {
      final source = node.asset['url'] ?? node.asset['localPath'];
      if (source is String && source.isNotEmpty && source.startsWith('http')) {
        return 'Image.network(${jsonEncode(source)}, fit: BoxFit.cover)';
      }
    }
    final background =
        node.styles['fill'] ??
        node.styles['backgroundColor'] ??
        node.styles['background'];
    final color = background is String && background.length == 9
        ? int.tryParse(background.substring(1), radix: 16)
        : null;
    final colorExpression = color == null
        ? 'Colors.transparent'
        : 'Color(0x${color.toRadixString(16).padLeft(8, '0')})';
    return 'Container(color: $colorExpression)';
  }

  static String? _flutterColorExpression(Object? value) {
    if (value is! String || !value.startsWith('#')) return null;
    final hex = value.substring(1);
    if (hex.length == 6) return 'Color(0xFF$hex)';
    if (hex.length == 8) {
      final red = hex.substring(0, 2);
      final green = hex.substring(2, 4);
      final blue = hex.substring(4, 6);
      final alpha = hex.substring(6, 8);
      return 'Color(0x$alpha$red$green$blue)';
    }
    return null;
  }

  static String _cssNumber(double value) => _formatNumber(value);

  static String _dartNumber(double value) => _formatNumber(value);

  static String _formatNumber(double value) {
    if (!value.isFinite) return '0';
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(3));

  static double _min(double first, double second) =>
      first < second ? first : second;
}
