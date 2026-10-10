import 'dart:ui';

import '../../../domain/models/node.dart';

class CanvasSpatialIndex {
  final double cellSize;
  final Map<_CellKey, List<CanvasNode>> _cells;
  final List<CanvasNode> _largeNodes;

  CanvasSpatialIndex._({
    required this.cellSize,
    required this._cells,
    required this._largeNodes,
  });

  factory CanvasSpatialIndex.build(
    Iterable<CanvasNode> nodes, {
    double cellSize = 512,
  }) {
    if (!cellSize.isFinite || cellSize <= 0) {
      throw ArgumentError.value(cellSize, 'cellSize');
    }
    final cells = <_CellKey, List<CanvasNode>>{};
    final largeNodes = <CanvasNode>[];
    for (final node in nodes) {
      final bounds = node.bounds;
      final minColumn = _cellCoordinate(bounds.left, cellSize);
      final maxColumn = _cellCoordinate(bounds.right, cellSize);
      final minRow = _cellCoordinate(bounds.top, cellSize);
      final maxRow = _cellCoordinate(bounds.bottom, cellSize);
      final cellCount = (maxColumn - minColumn + 1) * (maxRow - minRow + 1);
      if (cellCount > 64) {
        largeNodes.add(node);
        continue;
      }
      for (var column = minColumn; column <= maxColumn; column++) {
        for (var row = minRow; row <= maxRow; row++) {
          cells.putIfAbsent(_CellKey(column, row), () => []).add(node);
        }
      }
    }
    return CanvasSpatialIndex._(
      cellSize: cellSize,
      cells: cells,
      largeNodes: List<CanvasNode>.unmodifiable(largeNodes),
    );
  }

  List<CanvasNode> query(Rect bounds) {
    if (bounds.isEmpty) return const [];
    final result = <String, CanvasNode>{};
    final minColumn = _cellCoordinate(bounds.left, cellSize);
    final maxColumn = _cellCoordinate(bounds.right, cellSize);
    final minRow = _cellCoordinate(bounds.top, cellSize);
    final maxRow = _cellCoordinate(bounds.bottom, cellSize);
    for (var column = minColumn; column <= maxColumn; column++) {
      for (var row = minRow; row <= maxRow; row++) {
        for (final node in _cells[_CellKey(column, row)] ?? const []) {
          if (node.bounds.overlaps(bounds) ||
              node.bounds.contains(bounds.center)) {
            result[node.id] = node;
          }
        }
      }
    }
    for (final node in _largeNodes) {
      if (node.bounds.overlaps(bounds) || node.bounds.contains(bounds.center)) {
        result[node.id] = node;
      }
    }
    return result.values.toList(growable: false);
  }

  static int _cellCoordinate(double value, double cellSize) {
    return (value / cellSize).floor();
  }
}

class _CellKey {
  final int column;
  final int row;

  const _CellKey(this.column, this.row);

  @override
  bool operator ==(Object other) =>
      other is _CellKey && other.column == column && other.row == row;

  @override
  int get hashCode => Object.hash(column, row);
}
