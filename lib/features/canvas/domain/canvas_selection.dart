import 'dart:ui';

import '../../../domain/models/node.dart';

enum CanvasSelectionMode { direct, deep, selectThrough }

class CanvasSelectionPreferences {
  final CanvasSelectionMode mode;
  final String? isolateNodeId;
  final bool showLocked;
  final bool showHidden;

  const CanvasSelectionPreferences({
    this.mode = CanvasSelectionMode.deep,
    this.isolateNodeId,
    this.showLocked = false,
    this.showHidden = false,
  });

  CanvasSelectionPreferences copyWith({
    CanvasSelectionMode? mode,
    Object? isolateNodeId = _sentinel,
    bool? showLocked,
    bool? showHidden,
  }) => CanvasSelectionPreferences(
    mode: mode ?? this.mode,
    isolateNodeId: isolateNodeId == _sentinel
        ? this.isolateNodeId
        : isolateNodeId as String?,
    showLocked: showLocked ?? this.showLocked,
    showHidden: showHidden ?? this.showHidden,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'isolateNodeId': isolateNodeId,
    'showLocked': showLocked,
    'showHidden': showHidden,
  };

  factory CanvasSelectionPreferences.fromJson(Object? raw) {
    if (raw is! Map) return const CanvasSelectionPreferences();
    final modeName = raw['mode']?.toString();
    return CanvasSelectionPreferences(
      mode: CanvasSelectionMode.values.firstWhere(
        (value) => value.name == modeName,
        orElse: () => CanvasSelectionMode.deep,
      ),
      isolateNodeId: raw['isolateNodeId']?.toString(),
      showLocked: raw['showLocked'] as bool? ?? false,
      showHidden: raw['showHidden'] as bool? ?? false,
    );
  }

  static const Object _sentinel = Object();
}

class CanvasSelectionMath {
  const CanvasSelectionMath._();

  static List<CanvasNode> hitCandidates(
    Iterable<CanvasNode> nodes,
    Offset worldPoint, {
    bool includeLocked = false,
    bool includeHidden = false,
    String? isolateNodeId,
  }) {
    final all = nodes.toList(growable: false);
    final byId = {for (final node in all) node.id: node};
    final result = all.where((node) {
      if (!includeHidden && !node.visible) return false;
      if (!includeLocked && node.locked) return false;
      if (!node.bounds.contains(worldPoint)) return false;
      if (isolateNodeId != null && !isInIsolate(node.id, isolateNodeId, byId)) {
        return false;
      }
      return true;
    }).toList();

    result.sort((a, b) {
      final z = b.zIndex.compareTo(a.zIndex);
      if (z != 0) return z;
      final depth = depthOf(b.id, byId).compareTo(depthOf(a.id, byId));
      if (depth != 0) return depth;
      return a.id.compareTo(b.id);
    });
    return result;
  }

  static CanvasNode? pickAt(
    Iterable<CanvasNode> nodes,
    Offset worldPoint, {
    CanvasSelectionMode mode = CanvasSelectionMode.deep,
    int cycleIndex = 0,
    bool includeLocked = false,
    bool includeHidden = false,
    String? isolateNodeId,
  }) {
    final candidates = hitCandidates(
      nodes,
      worldPoint,
      includeLocked: includeLocked,
      includeHidden: includeHidden,
      isolateNodeId: isolateNodeId,
    );
    if (candidates.isEmpty) return null;

    switch (mode) {
      case CanvasSelectionMode.deep:
        return candidates.first;
      case CanvasSelectionMode.selectThrough:
        final index = cycleIndex < 0 ? 0 : cycleIndex % candidates.length;
        return candidates[index];
      case CanvasSelectionMode.direct:
        final byId = {for (final node in candidates) node.id: node};
        return candidates.firstWhere(
          (node) => node.parentId == null || !byId.containsKey(node.parentId),
          orElse: () => candidates.first,
        );
    }
  }

  static List<String> ancestorPath(
    String nodeId,
    Map<String, CanvasNode> nodesById,
  ) {
    final result = <String>[];
    final seen = <String>{};
    String? current = nodeId;
    while (current != null && seen.add(current)) {
      result.add(current);
      current = nodesById[current]?.parentId;
    }
    return result.reversed.toList(growable: false);
  }

  static int depthOf(String nodeId, Map<String, CanvasNode> nodesById) =>
      ancestorPath(nodeId, nodesById).length - 1;

  static bool isInIsolate(
    String nodeId,
    String isolateNodeId,
    Map<String, CanvasNode> nodesById,
  ) {
    if (nodeId == isolateNodeId) return true;
    return ancestorPath(nodeId, nodesById).contains(isolateNodeId);
  }

  static Set<String> safeDeleteIds(
    Iterable<String> selectedIds,
    Iterable<CanvasNode> nodes,
  ) {
    final all = nodes.toList(growable: false);
    final byParent = <String, List<CanvasNode>>{};
    for (final node in all) {
      final parentId = node.parentId;
      if (parentId != null) {
        byParent.putIfAbsent(parentId, () => []).add(node);
      }
    }

    final result = <String>{};
    final queue = selectedIds.toList(growable: true);
    for (final id in queue) {
      final node = all.where((candidate) => candidate.id == id).firstOrNull;
      if (node != null && !node.locked) result.add(id);
    }
    var index = 0;
    while (index < queue.length) {
      final parentId = queue[index++];
      for (final child in byParent[parentId] ?? const <CanvasNode>[]) {
        if (child.locked) continue;
        if (result.add(child.id)) queue.add(child.id);
      }
    }
    return result;
  }

  static Map<String, String> batchRename(
    Iterable<CanvasNode> nodes,
    String pattern, {
    int startIndex = 1,
  }) {
    final normalized = pattern.trim();
    if (normalized.isEmpty) return const {};
    final result = <String, String>{};
    var index = startIndex;
    for (final node in nodes) {
      var name = normalized
          .replaceAll('{index}', index.toString())
          .replaceAll(
            '{name}',
            node.name?.trim().isNotEmpty == true
                ? node.name!.trim()
                : node.type.name,
          );
      name = name.replaceAllMapped(RegExp(r'\{index:(\d+)\}'), (match) {
        final width = int.tryParse(match.group(1) ?? '') ?? 1;
        return index.toString().padLeft(width, '0');
      });
      name = name.replaceAll('#', index.toString());
      result[node.id] = name.trim();
      index++;
    }
    return result;
  }

  static const List<int> layerColorPalette = [
    0xFFF87171,
    0xFFFB923C,
    0xFFFACC15,
    0xFF4ADE80,
    0xFF2DD4BF,
    0xFF60A5FA,
    0xFFA78BFA,
    0xFFF472B6,
  ];
}
