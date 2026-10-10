import 'dart:convert';

import '../../domain/models/document.dart';

class DocumentVersionDiff {
  final int addedNodes;
  final int removedNodes;
  final int changedNodes;
  final int addedEdges;
  final int removedEdges;
  final int changedEdges;
  final bool nodeOrderChanged;
  final bool edgeOrderChanged;
  final bool viewportChanged;
  final bool navigationChanged;
  final bool metadataChanged;
  final bool assetsChanged;
  final bool tokensChanged;

  const DocumentVersionDiff({
    this.addedNodes = 0,
    this.removedNodes = 0,
    this.changedNodes = 0,
    this.addedEdges = 0,
    this.removedEdges = 0,
    this.changedEdges = 0,
    this.nodeOrderChanged = false,
    this.edgeOrderChanged = false,
    this.viewportChanged = false,
    this.navigationChanged = false,
    this.metadataChanged = false,
    this.assetsChanged = false,
    this.tokensChanged = false,
  });

  factory DocumentVersionDiff.compare(
    CanvasDocument before,
    CanvasDocument after,
  ) {
    final beforeNodes = _indexById(before.nodes, (node) => node.id);
    final afterNodes = _indexById(after.nodes, (node) => node.id);
    final beforeEdges = _indexById(before.edges, (edge) => edge.id);
    final afterEdges = _indexById(after.edges, (edge) => edge.id);

    return DocumentVersionDiff(
      addedNodes: _countOnlyIn(afterNodes, beforeNodes),
      removedNodes: _countOnlyIn(beforeNodes, afterNodes),
      changedNodes: _countChanged(beforeNodes, afterNodes),
      addedEdges: _countOnlyIn(afterEdges, beforeEdges),
      removedEdges: _countOnlyIn(beforeEdges, afterEdges),
      changedEdges: _countChanged(beforeEdges, afterEdges),
      nodeOrderChanged: !_sameSequence(
        _orderedIds(before.nodes),
        _orderedIds(after.nodes),
      ),
      edgeOrderChanged: !_sameSequence(
        _orderedIds(before.edges),
        _orderedIds(after.edges),
      ),
      viewportChanged:
          _encoded(before.viewport.toJson()) !=
          _encoded(after.viewport.toJson()),
      navigationChanged:
          _encoded(before.navigation) != _encoded(after.navigation),
      metadataChanged: _encoded(before.metadata) != _encoded(after.metadata),
      assetsChanged:
          _encoded(before.assets.toJson()) != _encoded(after.assets.toJson()),
      tokensChanged:
          _encoded(before.tokens.toJson()) != _encoded(after.tokens.toJson()),
    );
  }

  bool get isEmpty => totalChanges == 0;

  int get totalChanges =>
      addedNodes +
      removedNodes +
      changedNodes +
      addedEdges +
      removedEdges +
      changedEdges +
      (nodeOrderChanged ? 1 : 0) +
      (edgeOrderChanged ? 1 : 0) +
      (viewportChanged ? 1 : 0) +
      (navigationChanged ? 1 : 0) +
      (metadataChanged ? 1 : 0) +
      (assetsChanged ? 1 : 0) +
      (tokensChanged ? 1 : 0);

  Map<String, dynamic> toJson() => {
    'addedNodes': addedNodes,
    'removedNodes': removedNodes,
    'changedNodes': changedNodes,
    'addedEdges': addedEdges,
    'removedEdges': removedEdges,
    'changedEdges': changedEdges,
    'nodeOrderChanged': nodeOrderChanged,
    'edgeOrderChanged': edgeOrderChanged,
    'viewportChanged': viewportChanged,
    'navigationChanged': navigationChanged,
    'metadataChanged': metadataChanged,
    'assetsChanged': assetsChanged,
    'tokensChanged': tokensChanged,
    'totalChanges': totalChanges,
  };

  List<String> summaryLines() {
    final lines = <String>[];
    if (addedNodes > 0) lines.add('$addedNodes node ditambahkan');
    if (removedNodes > 0) lines.add('$removedNodes node dihapus');
    if (changedNodes > 0) lines.add('$changedNodes node diubah');
    if (addedEdges > 0) lines.add('$addedEdges konektor ditambahkan');
    if (removedEdges > 0) lines.add('$removedEdges konektor dihapus');
    if (changedEdges > 0) lines.add('$changedEdges konektor diubah');
    if (nodeOrderChanged) lines.add('Urutan node berubah');
    if (edgeOrderChanged) lines.add('Urutan konektor berubah');
    if (viewportChanged) lines.add('Viewport berubah');
    if (navigationChanged) lines.add('Navigation berubah');
    if (metadataChanged) lines.add('Metadata berubah');
    if (assetsChanged) lines.add('Manifest asset berubah');
    if (tokensChanged) lines.add('Design token berubah');
    return lines;
  }

  static Map<String, String> _indexById<T>(
    Iterable<T> values,
    String Function(T value) idOf,
  ) => {
    for (final value in values)
      idOf(value): _encoded((value as dynamic).toJson()),
  };

  static int _countOnlyIn(
    Map<String, String> first,
    Map<String, String> second,
  ) => first.keys.where((key) => !second.containsKey(key)).length;

  static int _countChanged(
    Map<String, String> first,
    Map<String, String> second,
  ) => first.keys
      .where((key) => second.containsKey(key) && first[key] != second[key])
      .length;

  static List<String> _orderedIds<T>(Iterable<T> values) => [
    for (final value in values) (value as dynamic).id.toString(),
  ];

  static bool _sameSequence(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  static String _encoded(Object? value) => jsonEncode(value);
}
