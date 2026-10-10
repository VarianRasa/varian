import 'dart:convert';

import '../../../domain/models/document_asset.dart';
import '../../../domain/models/node.dart';

enum AICopilotContextScope { selection, frame, page, project, assetCollection }

extension AICopilotContextScopeLabel on AICopilotContextScope {
  String get label => switch (this) {
    AICopilotContextScope.selection => 'Selection',
    AICopilotContextScope.frame => 'Frame',
    AICopilotContextScope.page => 'Page',
    AICopilotContextScope.project => 'Project',
    AICopilotContextScope.assetCollection => 'Asset collection',
  };
}

class AICopilotContextSnapshot {
  final String projectId;
  final AICopilotContextScope scope;
  final String? frameId;
  final String? pageId;
  final List<String> selectedNodeIds;
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> assets;
  final DateTime capturedAt;

  const AICopilotContextSnapshot({
    required this.projectId,
    required this.scope,
    this.frameId,
    this.pageId,
    this.selectedNodeIds = const [],
    this.nodes = const [],
    this.assets = const [],
    required this.capturedAt,
  });

  factory AICopilotContextSnapshot.fromCanvas({
    required String projectId,
    required AICopilotContextScope scope,
    required Iterable<CanvasNode> allNodes,
    Iterable<DocumentAsset> assets = const [],
    Iterable<String> selectedNodeIds = const [],
    String? frameId,
    String? pageId,
    DateTime? capturedAt,
  }) {
    final sourceNodes = allNodes.toList(growable: false);
    final byId = {for (final node in sourceNodes) node.id: node};
    final selected = selectedNodeIds
        .where(byId.containsKey)
        .toSet()
        .toList(growable: false);
    final selectedNodes = selected.map((id) => byId[id]!).toList();
    final resolvedFrameId =
        frameId ??
        selectedNodes
            .map((node) => node.type.name == 'frame' ? node.id : node.parentId)
            .whereType<String>()
            .firstOrNull;
    final resolvedPageId =
        pageId ??
        selectedNodes
            .map((node) => node.pageId)
            .whereType<String>()
            .firstOrNull;

    bool belongsToFrame(CanvasNode node, String targetFrameId) {
      var current = node;
      final visited = <String>{};
      while (current.parentId != null && visited.add(current.id)) {
        if (current.parentId == targetFrameId) return true;
        final parent = byId[current.parentId];
        if (parent == null) return false;
        current = parent;
      }
      return current.id == targetFrameId;
    }

    final scopedNodes = switch (scope) {
      AICopilotContextScope.selection => selectedNodes,
      AICopilotContextScope.frame =>
        resolvedFrameId == null
            ? selectedNodes
            : sourceNodes
                  .where((node) => belongsToFrame(node, resolvedFrameId))
                  .toList(growable: false),
      AICopilotContextScope.page =>
        resolvedPageId == null
            ? sourceNodes
            : sourceNodes
                  .where((node) => node.pageId == resolvedPageId)
                  .toList(growable: false),
      AICopilotContextScope.project => sourceNodes,
      AICopilotContextScope.assetCollection => const <CanvasNode>[],
    };

    return AICopilotContextSnapshot(
      projectId: projectId,
      scope: scope,
      frameId: resolvedFrameId,
      pageId: resolvedPageId,
      selectedNodeIds: selected,
      nodes: scopedNodes.map(_nodeSummary).toList(growable: false),
      assets: assets.map(_assetSummary).toList(growable: false),
      capturedAt: (capturedAt ?? DateTime.now()).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'scope': scope.name,
    'frameId': frameId,
    'pageId': pageId,
    'selectedNodeIds': selectedNodeIds,
    'nodes': nodes,
    'assets': assets,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };

  factory AICopilotContextSnapshot.fromJson(Map<String, dynamic> json) {
    final scope = AICopilotContextScope.values.firstWhere(
      (value) => value.name == json['scope'],
      orElse: () => AICopilotContextScope.project,
    );
    return AICopilotContextSnapshot(
      projectId: json['projectId']?.toString() ?? '',
      scope: scope,
      frameId: json['frameId']?.toString(),
      pageId: json['pageId']?.toString(),
      selectedNodeIds: _stringList(json['selectedNodeIds']),
      nodes: _mapList(json['nodes']),
      assets: _mapList(json['assets']),
      capturedAt:
          DateTime.tryParse(json['capturedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  String toPrompt() {
    final encoded = jsonEncode(toJson());
    if (encoded.length <= 12000) return encoded;
    return '${encoded.substring(0, 12000)}…[context truncated]';
  }

  static Map<String, dynamic> _nodeSummary(CanvasNode node) => {
    'id': node.id,
    'type': node.type.name,
    'name': node.name,
    'x': node.x,
    'y': node.y,
    'width': node.width,
    'height': node.height,
    'rotation': node.rotation,
    'opacity': node.opacity,
    'visible': node.visible,
    'locked': node.locked,
    'parentId': node.parentId,
    'pageId': node.pageId,
  };

  static Map<String, dynamic> _assetSummary(DocumentAsset asset) => {
    'id': asset.id,
    'kind': asset.kind.name,
    'name': asset.name,
    'mimeType': asset.mimeType,
    'sizeBytes': asset.sizeBytes,
    'license': asset.license,
    'folderId': asset.folderId,
    'tags': asset.tags,
    'version': asset.version,
    'storage': asset.storage.name,
  };

  static List<String> _stringList(Object? raw) => raw is List
      ? raw
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
      : const [];

  static List<Map<String, dynamic>> _mapList(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList(growable: false)
      : const [];
}
