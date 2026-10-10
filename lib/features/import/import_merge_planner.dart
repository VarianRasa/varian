import '../../domain/models/connector_edge.dart';
import '../../domain/models/document.dart';
import '../../domain/models/document_asset.dart';
import '../../domain/models/document_asset_dependencies.dart';
import '../../domain/models/document_package_diagnostics.dart';
import '../../domain/models/node.dart';
import '../../domain/models/node_payload.dart';

class ImportMergePlan {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final DocumentAssetManifest assets;
  final Map<String, String> assetIdRemaps;
  final int skippedDanglingEdges;
  final bool remappedConflicts;

  const ImportMergePlan({
    required this.nodes,
    required this.edges,
    this.assets = const DocumentAssetManifest(),
    this.assetIdRemaps = const {},
    this.skippedDanglingEdges = 0,
    this.remappedConflicts = false,
  });
}

class ImportMergePlanner {
  ImportMergePlanner._();

  static ImportMergePlan plan({
    required Iterable<CanvasNode> importedNodes,
    required Iterable<CanvasEdge> importedEdges,
    required Iterable<String> existingNodeIds,
    required Iterable<String> existingEdgeIds,
    DocumentAssetManifest existingAssets = const DocumentAssetManifest(),
    DocumentAssetManifest importedAssets = const DocumentAssetManifest(),
    String collisionPrefix = 'import',
  }) {
    existingAssets.validateIdentity();
    importedAssets.validateIdentity();
    var nodes = List<CanvasNode>.from(importedNodes);
    final assetIdRemaps = <String, String>{};
    final usedAssetIds = <String>{
      ...existingAssets.entries.keys,
      ...importedAssets.entries.keys,
    };
    final mergedAssets = <String, DocumentAsset>{...existingAssets.entries};
    for (final entry in importedAssets.entries.entries) {
      var nextId = entry.key;
      if (existingAssets.entries.containsKey(nextId)) {
        nextId = '$collisionPrefix-asset-$nextId';
        var suffix = 2;
        while (usedAssetIds.contains(nextId)) {
          nextId = '$collisionPrefix-asset-${entry.key}-$suffix';
          suffix++;
        }
        assetIdRemaps[entry.key] = nextId;
      }
      usedAssetIds.add(nextId);
    }
    for (final entry in importedAssets.entries.entries) {
      final nextId = assetIdRemaps[entry.key] ?? entry.key;
      final remappedDuplicateOf = entry.value.duplicateOf == null
          ? null
          : assetIdRemaps[entry.value.duplicateOf!] ?? entry.value.duplicateOf;
      mergedAssets[nextId] =
          nextId == entry.key && remappedDuplicateOf == entry.value.duplicateOf
          ? entry.value
          : entry.value.copyWith(id: nextId, duplicateOf: remappedDuplicateOf);
    }
    if (assetIdRemaps.isNotEmpty) {
      nodes = nodes
          .map(
            (node) => node.copyWith(
              payload: _rewriteAssetIds(node.type, node.payload, assetIdRemaps),
            ),
          )
          .toList(growable: false);
    }
    final nodeIds = nodes.map((node) => node.id).toSet();
    var edges = importedEdges
        .where(
          (edge) =>
              (edge.sourceNodeId == null ||
                  nodeIds.contains(edge.sourceNodeId)) &&
              (edge.targetNodeId == null ||
                  nodeIds.contains(edge.targetNodeId)),
        )
        .toList(growable: false);
    final skippedDanglingEdges = importedEdges.length - edges.length;

    final currentNodeIds = existingNodeIds.toSet();
    final currentEdgeIds = existingEdgeIds.toSet();
    final hasNodeConflict = nodes.any(
      (node) => currentNodeIds.contains(node.id),
    );
    final hasEdgeConflict = edges.any(
      (edge) => currentEdgeIds.contains(edge.id),
    );
    final remappedConflicts = hasNodeConflict || hasEdgeConflict;
    if (remappedConflicts) {
      final merged = DocumentPackageDiagnostics.duplicateDocument(
        CanvasDocument(
          projectId: 'import',
          nodes: nodes,
          edges: edges,
          updatedAt: DateTime.now(),
        ),
        prefix: collisionPrefix,
      );
      nodes = merged.nodes;
      edges = merged.edges;
    }

    return ImportMergePlan(
      nodes: List.unmodifiable(nodes),
      edges: List.unmodifiable(edges),
      assets: DocumentAssetManifest(entries: mergedAssets),
      assetIdRemaps: Map.unmodifiable(assetIdRemaps),
      skippedDanglingEdges: skippedDanglingEdges,
      remappedConflicts: remappedConflicts || assetIdRemaps.isNotEmpty,
    );
  }

  /// Returns durable references and IDs that cannot be resolved uniquely.
  ///
  /// Keyed dependencies must match an asset of the same kind. Legacy payload
  /// fields that contain only an opaque durable reference must match exactly one
  /// manifest entry of the same kind; ambiguity is rejected rather than bound
  /// to an arbitrary asset.
  static Set<String> unresolvedDependencies({
    required Iterable<CanvasNode> nodes,
    required DocumentAssetManifest assets,
  }) {
    assets.validateIdentity();
    final unresolved = <String>{};
    final dependencies = collectDocumentAssetDependencies(nodes);
    for (final dependency in dependencies.dependencies) {
      if (dependency.assetId case final assetId?) {
        final asset = assets[assetId];
        if (asset == null || asset.kind != dependency.kind) {
          unresolved.add(assetId);
        }
        continue;
      }
      final reference = dependency.durableReference;
      if (reference == null) continue;
      final matches = assets.items
          .where(
            (asset) =>
                asset.kind == dependency.kind &&
                asset.durableReference == reference,
          )
          .length;
      if (matches != 1) unresolved.add(reference);
    }
    return unresolved;
  }

  static NodePayload _rewriteAssetIds(
    NodeType type,
    NodePayload payload,
    Map<String, String> remaps,
  ) {
    final json = Map<String, dynamic>.from(payload.toJson());

    Object? rewrite(Object? value) {
      if (value is Map) {
        return <String, dynamic>{
          for (final entry in value.entries)
            entry.key.toString():
                entry.key.toString() == 'assetId' && entry.value is String
                ? remaps[entry.value] ?? entry.value
                : rewrite(entry.value),
        };
      }
      if (value is List) return value.map(rewrite).toList(growable: false);
      return value;
    }

    final rewritten = rewrite(json);
    return NodePayload.fromJson(
      type,
      Map<String, dynamic>.from(rewritten as Map),
    );
  }
}
