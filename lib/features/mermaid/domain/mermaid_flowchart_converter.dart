import 'package:flutter/material.dart';

import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import 'mermaid_conversion.dart';

export 'mermaid_conversion.dart';

/// Converts only the lossless, source-backed flowchart subset.
///
/// The converter deliberately does not try to interpret Mermaid directives,
/// HTML, callbacks, styles, or subgraphs. Returning a complete failure rather
/// than partial objects keeps a failed conversion reversible and predictable.
class MermaidFlowchartConverter {
  MermaidFlowchartConverter._();

  static MermaidConversionResult convert(
    CanvasNode sourceNode, {
    MermaidDirection? direction,
  }) {
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
    final source = payload.source;
    final sourceDiagnostic = MermaidSourceLimits.validate(source);
    if (sourceDiagnostic != null) {
      return MermaidConversionResult.failure(sourceDiagnostic);
    }

    final lines = source.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.startsWith('%%{')) {
        return MermaidConversionResult.failure(
          _diagnostic(
            'UNSUPPORTED_CONVERSION',
            'Mermaid init directives are not part of the lossless native subset.',
            line: index + 1,
            column: 1,
          ),
        );
      }
      if (line.isNotEmpty && !line.startsWith('%%')) break;
    }
    final header = _findHeader(lines);
    if (header == null) {
      return MermaidConversionResult.failure(
        _diagnostic(
          'UNSUPPORTED_CONVERSION',
          'Only flowchart and graph Mermaid sources can be converted.',
          line: _firstContentLine(lines),
        ),
      );
    }

    final nodesByKey = <String, _FlowNode>{};
    final edges = <_FlowEdge>[];
    var edgeOrder = 0;

    for (var index = header.lineIndex + 1; index < lines.length; index++) {
      final rawLine = lines[index];
      final line = rawLine.trim();
      final lineNumber = index + 1;
      if (line.isEmpty || line.startsWith('%%')) {
        if (line.startsWith('%%{')) {
          return MermaidConversionResult.failure(
            _diagnostic(
              'UNSUPPORTED_CONVERSION',
              'Mermaid init directives are not part of the lossless native subset.',
              line: lineNumber,
              column: 1,
            ),
          );
        }
        continue;
      }

      if (_isUnsupportedDirective(line)) {
        return MermaidConversionResult.failure(
          _diagnostic(
            'UNSUPPORTED_CONVERSION',
            'This Mermaid directive is not part of the lossless native subset.',
            line: lineNumber,
            column: 1,
          ),
        );
      }

      if (line.contains(';')) {
        return MermaidConversionResult.failure(
          _diagnostic(
            'UNSUPPORTED_CONVERSION',
            'Multiple Mermaid statements on one line are not supported.',
            line: lineNumber,
            column: line.indexOf(';') + 1,
          ),
        );
      }

      try {
        final parsed = _parseLine(line, lineNumber);
        if (parsed.diagnostic != null) {
          return MermaidConversionResult.failure(parsed.diagnostic!);
        }

        for (final edge in parsed.edges) {
          _mergeNode(nodesByKey, edge.source);
          _mergeNode(nodesByKey, edge.target);
          edges.add(edge.copyWith(order: edgeOrder++));
        }
        if (parsed.node != null) {
          _mergeNode(nodesByKey, parsed.node!);
        }
      } on _ConversionFailure catch (failure) {
        return MermaidConversionResult.failure(failure.diagnostic);
      }

      if (nodesByKey.length + edges.length >
          MermaidSourceLimits.maxGeneratedObjects) {
        return MermaidConversionResult.failure(
          _diagnostic(
            'GENERATED_OBJECTS_TOO_MANY',
            'The Mermaid graph contains too many native objects.',
            line: lineNumber,
            column: 1,
          ),
        );
      }
    }

    if (nodesByKey.isEmpty) {
      return MermaidConversionResult.failure(
        _diagnostic(
          'MALFORMED_FLOWCHART',
          'The Mermaid flowchart does not contain any nodes.',
          line: header.lineIndex + 1,
          column: 1,
        ),
      );
    }

    final resolvedDirection = direction ?? header.direction;
    final orderedNodes = nodesByKey.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final positions = _layout(
      sourceNode,
      orderedNodes,
      edges,
      resolvedDirection,
    );
    final nativeNodes = [
      for (final node in orderedNodes)
        _toCanvasNode(sourceNode, node, positions),
    ];
    final nativeEdges = [
      for (final edge in edges)
        _toCanvasEdge(sourceNode, edge, resolvedDirection, nodesByKey),
    ];

    return MermaidConversionResult(
      nodes: nativeNodes,
      edges: nativeEdges,
      diagramType: 'flowchart',
    );
  }

  static _FlowHeader? _findHeader(List<String> lines) {
    final pattern = RegExp(
      r'^(?:flowchart|graph)(?:\s+(TD|TB|BT|LR|RL))?$',
      caseSensitive: false,
    );
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty || line.startsWith('%%')) continue;
      final match = pattern.firstMatch(line);
      if (match == null) return null;
      final token = match.group(1)?.toUpperCase() ?? 'TD';
      return _FlowHeader(
        lineIndex: index,
        direction: token == 'TB'
            ? MermaidDirection.topDown
            : MermaidDirection.values.firstWhere(
                (direction) => direction.value == token,
              ),
      );
    }
    return null;
  }

  static _ParsedLine _parseLine(String line, int lineNumber) {
    final first = _parseNodeRef(line, 0, lineNumber);
    if (first.node == null) {
      return _ParsedLine.failure(first.diagnostic!);
    }

    var cursor = first.nextIndex;
    final parsedEdges = <_FlowEdge>[];
    var current = first.node!;
    while (true) {
      final operator = _parseOperator(line, cursor, lineNumber);
      if (operator == null) {
        if (line.substring(cursor).trim().isNotEmpty) {
          return _ParsedLine.failure(
            _diagnostic(
              'UNSUPPORTED_CONVERSION',
              'This flowchart statement is not part of the lossless native subset.',
              line: lineNumber,
              column: cursor + 1,
            ),
          );
        }
        return _ParsedLine(node: current, edges: parsedEdges);
      }

      final target = _parseNodeRef(line, operator.nextIndex, lineNumber);
      if (target.node == null) {
        return _ParsedLine.failure(target.diagnostic!);
      }
      parsedEdges.add(
        _FlowEdge(
          source: current,
          target: target.node!,
          label: operator.label,
          strokeStyle: operator.strokeStyle,
          strokeWidth: operator.strokeWidth,
          startMarker: operator.startMarker,
          endMarker: operator.endMarker,
          order: parsedEdges.length,
        ),
      );
      current = target.node!;
      cursor = target.nextIndex;
    }
  }

  static _ParsedNode _parseNodeRef(
    String line,
    int startIndex,
    int lineNumber,
  ) {
    var index = startIndex;
    while (index < line.length && _isWhitespace(line.codeUnitAt(index))) {
      index++;
    }

    final idMatch = RegExp(
      r'[A-Za-z][A-Za-z0-9_-]*',
    ).matchAsPrefix(line, index);
    if (idMatch == null) {
      return _ParsedNode.failure(
        _diagnostic(
          'MALFORMED_FLOWCHART',
          'Expected a Mermaid node identifier.',
          line: lineNumber,
          column: index + 1,
        ),
      );
    }

    final id = idMatch.group(0)!;
    index = idMatch.end;
    while (index < line.length && _isWhitespace(line.codeUnitAt(index))) {
      index++;
    }

    var shape = _FlowShape.rectangle;
    var label = id;
    var hasExplicitLabel = false;
    final shapes = <String, _FlowShape>{
      '[(': _FlowShape.cylinder,
      '[[': _FlowShape.rectangle,
      '((': _FlowShape.ellipse,
      '([': _FlowShape.ellipse,
      '[/': _FlowShape.parallelogram,
      '[\\': _FlowShape.parallelogram,
      '{': _FlowShape.diamond,
      '(': _FlowShape.ellipse,
      '[': _FlowShape.rectangle,
    };

    String? opening;
    for (final candidate in shapes.keys) {
      if (line.startsWith(candidate, index)) {
        opening = candidate;
        break;
      }
    }

    if (opening != null) {
      final close = _closingDelimiter(opening);
      final contentStart = index + opening.length;
      final closeIndex = line.indexOf(close, contentStart);
      if (closeIndex < 0) {
        return _ParsedNode.failure(
          _diagnostic(
            'MALFORMED_FLOWCHART',
            'Mermaid node shape is not closed.',
            line: lineNumber,
            column: index + 1,
          ),
        );
      }
      label = line.substring(contentStart, closeIndex).trim();
      if (label.isEmpty) {
        return _ParsedNode.failure(
          _diagnostic(
            'MALFORMED_FLOWCHART',
            'Mermaid node labels cannot be empty in the native subset.',
            line: lineNumber,
            column: contentStart + 1,
          ),
        );
      }
      shape = shapes[opening]!;
      hasExplicitLabel = true;
      index = closeIndex + close.length;
    }

    final labelDiagnostic = _validateLabel(label, lineNumber, startIndex);
    if (labelDiagnostic != null) {
      return _ParsedNode.failure(labelDiagnostic);
    }

    return _ParsedNode(
      node: _FlowNode(
        key: id,
        label: label,
        shape: shape,
        order: 0,
        hasExplicitLabel: hasExplicitLabel,
      ),
      nextIndex: index,
    );
  }

  static _FlowOperator? _parseOperator(
    String line,
    int startIndex,
    int lineNumber,
  ) {
    var index = startIndex;
    while (index < line.length && _isWhitespace(line.codeUnitAt(index))) {
      index++;
    }
    if (index >= line.length) return null;

    final operators = [
      ('-->', StrokeStyle.solid, 2.0, LineMarker.none, LineMarker.arrow),
      ('-.->', StrokeStyle.dotted, 2.0, LineMarker.none, LineMarker.arrow),
      ('-.-', StrokeStyle.dotted, 2.0, LineMarker.none, LineMarker.none),
      ('==>', StrokeStyle.solid, 3.0, LineMarker.none, LineMarker.arrow),
      ('===', StrokeStyle.solid, 3.0, LineMarker.none, LineMarker.none),
      ('--o', StrokeStyle.solid, 2.0, LineMarker.none, LineMarker.circle),
      ('o--', StrokeStyle.solid, 2.0, LineMarker.circle, LineMarker.none),
      ('---', StrokeStyle.solid, 2.0, LineMarker.none, LineMarker.none),
    ];

    String? matched;
    for (final candidate in operators) {
      if (line.startsWith(candidate.$1, index)) {
        matched = candidate.$1;
        break;
      }
    }

    String? label;
    if (matched == null && line.startsWith('--', index)) {
      final end = line.indexOf('-->', index + 2);
      if (end > index + 2) {
        label = line.substring(index + 2, end).trim();
        matched = '-->'; // Labelled solid edge: A -- yes --> B.
        index = end;
      }
    }

    if (matched == null) {
      if (line.startsWith('--x', index) ||
          line.startsWith('x--', index) ||
          line.startsWith('~~~', index)) {
        throw _ConversionFailure(
          _diagnostic(
            'UNSUPPORTED_CONVERSION',
            'This Mermaid edge marker is not supported by the native canvas.',
            line: lineNumber,
            column: index + 1,
          ),
        );
      }
      throw _ConversionFailure(
        _diagnostic(
          'MALFORMED_FLOWCHART',
          'Unsupported or malformed Mermaid edge operator.',
          line: lineNumber,
          column: index + 1,
        ),
      );
    }

    final candidate = operators.firstWhere((entry) => entry.$1 == matched);
    index += matched.length;
    while (index < line.length && _isWhitespace(line.codeUnitAt(index))) {
      index++;
    }

    if (index < line.length && line[index] == '|') {
      final close = line.indexOf('|', index + 1);
      if (close < 0) {
        throw _ConversionFailure(
          _diagnostic(
            'MALFORMED_FLOWCHART',
            'Mermaid edge label is not closed.',
            line: lineNumber,
            column: index + 1,
          ),
        );
      }
      final inlineLabel = line.substring(index + 1, close).trim();
      if (inlineLabel.isEmpty) {
        throw _ConversionFailure(
          _diagnostic(
            'MALFORMED_FLOWCHART',
            'Mermaid edge labels cannot be empty.',
            line: lineNumber,
            column: index + 1,
          ),
        );
      }
      label = inlineLabel;
      index = close + 1;
    }

    final labelDiagnostic = label == null
        ? null
        : _validateLabel(label, lineNumber, startIndex);
    if (labelDiagnostic != null) throw _ConversionFailure(labelDiagnostic);

    return _FlowOperator(
      label: label,
      strokeStyle: candidate.$2,
      strokeWidth: candidate.$3,
      startMarker: candidate.$4,
      endMarker: candidate.$5,
      nextIndex: index,
    );
  }

  static void _mergeNode(Map<String, _FlowNode> nodesByKey, _FlowNode node) {
    final existing = nodesByKey[node.key];
    if (existing == null) {
      node.order = nodesByKey.length;
      nodesByKey[node.key] = node;
      return;
    }
    if (node.hasExplicitLabel) {
      if (existing.hasExplicitLabel &&
          (existing.label != node.label || existing.shape != node.shape)) {
        throw const _ConversionFailure(
          MermaidDiagnostic(
            code: 'MALFORMED_FLOWCHART',
            message: 'A Mermaid node has conflicting declarations.',
          ),
        );
      }
      existing
        ..label = node.label
        ..shape = node.shape
        ..hasExplicitLabel = true;
    }
  }

  /// ponytail: deterministic layering is sufficient for the bounded native
  /// subset; use a graph layout engine only if exact Mermaid routing is needed.
  static Map<String, _Position> _layout(
    CanvasNode sourceNode,
    List<_FlowNode> nodes,
    List<_FlowEdge> edges,
    MermaidDirection direction,
  ) {
    final rank = <String, int>{};
    final indegree = {for (final node in nodes) node.key: 0};
    final outgoing = <String, List<_FlowEdge>>{};
    for (final edge in edges) {
      indegree[edge.target.key] = (indegree[edge.target.key] ?? 0) + 1;
      outgoing.putIfAbsent(edge.source.key, () => []).add(edge);
    }

    final queue = <String>[];
    var highestRank = -1;
    for (final node in nodes) {
      if (indegree[node.key] == 0) {
        rank[node.key] = 0;
        queue.add(node.key);
        highestRank = 0;
      }
    }

    var cursor = 0;
    final processed = <String>{};
    while (processed.length < nodes.length) {
      if (cursor >= queue.length) {
        // Break a cycle at the first remaining declaration, while preserving
        // any rank already assigned by an incoming path.
        final forced = nodes.firstWhere(
          (node) => !processed.contains(node.key),
        );
        final forcedRank = rank[forced.key] ?? highestRank + 1;
        rank[forced.key] = forcedRank;
        if (forcedRank > highestRank) highestRank = forcedRank;
        queue.add(forced.key);
      }

      final key = queue[cursor++];
      if (!processed.add(key)) continue;
      final currentRank = rank[key] ?? 0;
      if (currentRank > highestRank) highestRank = currentRank;

      for (final edge in outgoing[key] ?? const <_FlowEdge>[]) {
        if (!processed.contains(edge.target.key)) {
          final nextRank = currentRank + 1;
          final targetRank = rank[edge.target.key];
          if (targetRank == null || nextRank > targetRank) {
            rank[edge.target.key] = nextRank;
            if (nextRank > highestRank) highestRank = nextRank;
          }
        }
        indegree[edge.target.key] = indegree[edge.target.key]! - 1;
        if (indegree[edge.target.key] == 0 &&
            !processed.contains(edge.target.key)) {
          queue.add(edge.target.key);
        }
      }
    }

    final byRank = <int, List<_FlowNode>>{};
    for (final node in nodes) {
      byRank.putIfAbsent(rank[node.key]!, () => []).add(node);
    }
    final orderedRanks = byRank.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    const crossGap = 48.0;
    const primaryGap = 72.0;
    final isVertical =
        direction == MermaidDirection.topDown ||
        direction == MermaidDirection.bottomTop;
    final rankSpans = <int, double>{};
    var maxCrossSpan = 0.0;
    for (final entry in orderedRanks) {
      final span = entry.value.fold<double>(0, (total, node) {
        final size = _flowNodeSize(node.shape);
        return total + (isVertical ? size.$1 : size.$2);
      });
      final withGaps = span + (entry.value.length - 1) * crossGap;
      rankSpans[entry.key] = withGaps;
      if (withGaps > maxCrossSpan) maxCrossSpan = withGaps;
    }

    final primaryOffsets = <int, double>{};
    var primaryOffset = 0.0;
    for (final entry in orderedRanks) {
      primaryOffsets[entry.key] = primaryOffset;
      final maxPrimarySize = entry.value.fold<double>(0, (maxSize, node) {
        final size = _flowNodeSize(node.shape);
        final primarySize = isVertical ? size.$2 : size.$1;
        return primarySize > maxSize ? primarySize : maxSize;
      });
      primaryOffset += maxPrimarySize + primaryGap;
    }

    final origin = _Position(sourceNode.x + 24, sourceNode.y + 24);
    final positions = <String, _Position>{};
    for (final entry in orderedRanks) {
      var crossOffset = (maxCrossSpan - rankSpans[entry.key]!) / 2;
      for (final node in entry.value) {
        final size = _flowNodeSize(node.shape);
        final position = switch (direction) {
          MermaidDirection.topDown => _Position(
            origin.x + crossOffset,
            origin.y + primaryOffsets[entry.key]!,
          ),
          MermaidDirection.bottomTop => _Position(
            origin.x + crossOffset,
            origin.y - primaryOffsets[entry.key]!,
          ),
          MermaidDirection.leftToRight => _Position(
            origin.x + primaryOffsets[entry.key]!,
            origin.y + crossOffset,
          ),
          MermaidDirection.rightToLeft => _Position(
            origin.x - primaryOffsets[entry.key]!,
            origin.y + crossOffset,
          ),
        };
        positions[node.key] = position;
        crossOffset += (isVertical ? size.$1 : size.$2) + crossGap;
      }
    }
    return positions;
  }

  static (double, double) _flowNodeSize(_FlowShape shape) => switch (shape) {
    _FlowShape.rectangle => (160.0, 72.0),
    _FlowShape.ellipse => (160.0, 72.0),
    _FlowShape.diamond => (180.0, 96.0),
    _FlowShape.cylinder => (160.0, 88.0),
    _FlowShape.parallelogram => (176.0, 72.0),
  };

  static CanvasNode _toCanvasNode(
    CanvasNode sourceNode,
    _FlowNode node,
    Map<String, _Position> positions,
  ) {
    final size = _flowNodeSize(node.shape);
    final type = switch (node.shape) {
      _FlowShape.rectangle => NodeType.rectangle,
      _FlowShape.ellipse => NodeType.ellipse,
      _FlowShape.diamond => NodeType.diamond,
      _FlowShape.cylinder => NodeType.cylinder,
      _FlowShape.parallelogram => NodeType.parallelogram,
    };
    final colors = switch (node.shape) {
      _FlowShape.rectangle => (
        const Color(0xFF2563EB),
        const Color(0xFF60A5FA),
      ),
      _FlowShape.ellipse => (const Color(0xFF059669), const Color(0xFF34D399)),
      _FlowShape.diamond => (const Color(0xFFD97706), const Color(0xFFFBBF24)),
      _FlowShape.cylinder => (const Color(0xFF7C3AED), const Color(0xFFA78BFA)),
      _FlowShape.parallelogram => (
        const Color(0xFF0F766E),
        const Color(0xFF2DD4BF),
      ),
    };
    final position = positions[node.key]!;
    final payload = ShapePayload(
      fill: colors.$1,
      stroke: colors.$2,
      strokeWidth: 2,
      cornerRadius: node.shape == _FlowShape.rectangle ? 8 : 4,
      label: node.label,
      labelColor: const Color(0xFFFFFFFF),
      labelFontSize: 14,
      cylinderCapRatio: node.shape == _FlowShape.cylinder ? 0.25 : 0.25,
      skewRatio: node.shape == _FlowShape.parallelogram ? 0.2 : 0.2,
    );
    return CanvasNode(
      id: '${sourceNode.id}__mermaid_node_${node.order}',
      type: type,
      x: position.x,
      y: position.y,
      width: size.$1,
      height: size.$2,
      zIndex: sourceNode.zIndex + node.order + 1,
      parentId: sourceNode.parentId,
      mermaidSourceId: sourceNode.id,
      payload: payload,
    );
  }

  static CanvasEdge _toCanvasEdge(
    CanvasNode sourceNode,
    _FlowEdge edge,
    MermaidDirection direction,
    Map<String, _FlowNode> nodesByKey,
  ) {
    final sourceOrder = nodesByKey[edge.source.key]!.order;
    final targetOrder = nodesByKey[edge.target.key]!.order;
    final vertical =
        direction == MermaidDirection.topDown ||
        direction == MermaidDirection.bottomTop;
    final sourceAnchor = vertical
        ? (direction == MermaidDirection.topDown
              ? AnchorPosition.bottom
              : AnchorPosition.top)
        : (direction == MermaidDirection.leftToRight
              ? AnchorPosition.right
              : AnchorPosition.left);
    final targetAnchor = vertical
        ? (direction == MermaidDirection.topDown
              ? AnchorPosition.top
              : AnchorPosition.bottom)
        : (direction == MermaidDirection.leftToRight
              ? AnchorPosition.left
              : AnchorPosition.right);
    return CanvasEdge(
      id: '${sourceNode.id}__mermaid_edge_${edge.order}',
      sourceNodeId: '${sourceNode.id}__mermaid_node_$sourceOrder',
      targetNodeId: '${sourceNode.id}__mermaid_node_$targetOrder',
      sourceAnchor: sourceAnchor,
      targetAnchor: targetAnchor,
      routing: ConnectorRouting.orthogonal,
      strokeColor: const Color(0xFF94A3B8),
      strokeWidth: edge.strokeWidth,
      strokeStyle: edge.strokeStyle,
      startMarker: edge.startMarker,
      endMarker: edge.endMarker,
      label: edge.label,
      mermaidSourceId: sourceNode.id,
    );
  }

  static MermaidDiagnostic? _validateLabel(
    String label,
    int lineNumber,
    int column,
  ) {
    if (label.contains('<') ||
        label.contains('>') ||
        label.contains('`') ||
        label.contains('**')) {
      return _diagnostic(
        'UNSUPPORTED_CONVERSION',
        'HTML and unsupported Markdown labels cannot be converted safely.',
        line: lineNumber,
        column: column + 1,
      );
    }
    return null;
  }

  static bool _isUnsupportedDirective(String line) {
    final lower = line.toLowerCase();
    return lower.startsWith('subgraph ') ||
        lower == 'end' ||
        lower.startsWith('style ') ||
        lower.startsWith('classdef ') ||
        lower.startsWith('class ') ||
        lower.startsWith('click ') ||
        lower.startsWith('link ') ||
        lower.startsWith('linkstyle ') ||
        lower.startsWith('direction ');
  }

  static String _closingDelimiter(String opening) => switch (opening) {
    '[(' => ')]',
    '[[' => ']]',
    '((' => '))',
    '([' => '])',
    '[/' => '/]',
    r'[\' => r'\]',
    '{' => '}',
    '(' => ')',
    '[' => ']',
    _ => '',
  };

  static int _firstContentLine(List<String> lines) {
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trim().isNotEmpty) return index + 1;
    }
    return 1;
  }

  static MermaidDiagnostic _diagnostic(
    String code,
    String message, {
    int? line,
    int? column,
  }) => MermaidDiagnostic(
    code: code,
    message: message,
    line: line,
    column: column,
  );

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0D;
}

class _FlowHeader {
  final int lineIndex;
  final MermaidDirection direction;

  const _FlowHeader({required this.lineIndex, required this.direction});
}

enum _FlowShape { rectangle, ellipse, diamond, cylinder, parallelogram }

class _FlowNode {
  final String key;
  String label;
  _FlowShape shape;
  int order;
  bool hasExplicitLabel;

  _FlowNode({
    required this.key,
    required this.label,
    required this.shape,
    required this.order,
    required this.hasExplicitLabel,
  });
}

class _FlowEdge {
  final _FlowNode source;
  final _FlowNode target;
  final String? label;
  final StrokeStyle strokeStyle;
  final double strokeWidth;
  final LineMarker startMarker;
  final LineMarker endMarker;
  final int order;

  const _FlowEdge({
    required this.source,
    required this.target,
    required this.label,
    required this.strokeStyle,
    required this.strokeWidth,
    required this.startMarker,
    required this.endMarker,
    required this.order,
  });

  _FlowEdge copyWith({int? order}) => _FlowEdge(
    source: source,
    target: target,
    label: label,
    strokeStyle: strokeStyle,
    strokeWidth: strokeWidth,
    startMarker: startMarker,
    endMarker: endMarker,
    order: order ?? this.order,
  );
}

class _FlowOperator {
  final String? label;
  final StrokeStyle strokeStyle;
  final double strokeWidth;
  final LineMarker startMarker;
  final LineMarker endMarker;
  final int nextIndex;

  const _FlowOperator({
    required this.label,
    required this.strokeStyle,
    required this.strokeWidth,
    required this.startMarker,
    required this.endMarker,
    required this.nextIndex,
  });
}

class _ParsedNode {
  final _FlowNode? node;
  final int nextIndex;
  final MermaidDiagnostic? diagnostic;

  const _ParsedNode({this.node, this.nextIndex = 0, this.diagnostic});

  _ParsedNode.failure(MermaidDiagnostic diagnostic)
    : this(diagnostic: diagnostic);
}

class _ParsedLine {
  final _FlowNode? node;
  final List<_FlowEdge> edges;
  final MermaidDiagnostic? diagnostic;

  const _ParsedLine({this.node, this.edges = const [], this.diagnostic});

  _ParsedLine.failure(MermaidDiagnostic diagnostic)
    : this(diagnostic: diagnostic);
}

class _Position {
  final double x;
  final double y;

  const _Position(this.x, this.y);
}

class _ConversionFailure implements Exception {
  final MermaidDiagnostic diagnostic;

  const _ConversionFailure(this.diagnostic);
}
