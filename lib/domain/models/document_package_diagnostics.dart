import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'connector_edge.dart';
import 'document.dart';
import 'document_asset.dart';
import 'document_migrations.dart';
import 'document_package.dart';
import 'node.dart';
import 'node_payload.dart';

enum DocumentPackageIssueSeverity { info, warning, error }

class DocumentPackageIssue {
  final String code;
  final String message;
  final String path;
  final DocumentPackageIssueSeverity severity;
  final bool repairable;

  const DocumentPackageIssue({
    required this.code,
    required this.message,
    this.path = '',
    this.severity = DocumentPackageIssueSeverity.error,
    this.repairable = false,
  });

  @override
  String toString() =>
      '${severity.name}: $code${path.isEmpty ? '' : ' [$path]'} $message';
}

class DocumentPackageHealthReport {
  final List<DocumentPackageIssue> issues;
  final String checksum;
  final int nodeCount;
  final int edgeCount;
  final int assetCount;

  const DocumentPackageHealthReport({
    required this.issues,
    required this.checksum,
    required this.nodeCount,
    required this.edgeCount,
    required this.assetCount,
  });

  bool get isHealthy => issues.every(
    (issue) => issue.severity != DocumentPackageIssueSeverity.error,
  );

  bool get canRepair => issues.any((issue) => issue.repairable);

  List<DocumentPackageIssue> get errors => issues
      .where((issue) => issue.severity == DocumentPackageIssueSeverity.error)
      .toList(growable: false);
}

class DocumentPackageMigrationPreview {
  final int? sourceVersion;
  final int? targetVersion;
  final List<String> appliedMigrations;
  final String? error;

  const DocumentPackageMigrationPreview({
    required this.sourceVersion,
    required this.targetVersion,
    required this.appliedMigrations,
    this.error,
  });

  bool get canApply => error == null;

  static DocumentPackageMigrationPreview fromJson(Map<String, dynamic> json) {
    try {
      final result = DocumentMigrations.migrate(json);
      return DocumentPackageMigrationPreview(
        sourceVersion: result.sourceVersion,
        targetVersion: result.targetVersion,
        appliedMigrations: result.appliedMigrations,
      );
    } on DocumentSchemaException catch (error) {
      return DocumentPackageMigrationPreview(
        sourceVersion: _readVersion(json['schemaVersion']),
        targetVersion: DocumentMigrations.currentVersion,
        appliedMigrations: const [],
        error: error.message,
      );
    } catch (error) {
      return DocumentPackageMigrationPreview(
        sourceVersion: _readVersion(json['schemaVersion']),
        targetVersion: DocumentMigrations.currentVersion,
        appliedMigrations: const [],
        error: '$error',
      );
    }
  }

  static int? _readVersion(Object? raw) => raw is num ? raw.toInt() : null;
}

class DocumentPackageRepairResult {
  final CanvasDocumentPackage package;
  final List<String> actions;
  final DocumentPackageHealthReport health;

  const DocumentPackageRepairResult({
    required this.package,
    required this.actions,
    required this.health,
  });

  bool get changed => actions.isNotEmpty;
}

class DocumentPackageDiagnostics {
  DocumentPackageDiagnostics._();

  static DocumentPackageHealthReport inspect(
    CanvasDocumentPackage package, {
    String? expectedChecksum,
  }) {
    final document = package.document;
    final issues = <DocumentPackageIssue>[];
    final assets = package.assets;
    final documentAssets = package.document.assets;
    final effectiveAssets = assets.items.isEmpty ? documentAssets : assets;
    final nodeIds = <String>{};
    final duplicateNodeIds = <String>{};

    for (var index = 0; index < document.nodes.length; index++) {
      final node = document.nodes[index];
      final path = 'document.nodes[$index]';
      final id = node.id.trim();
      if (id.isEmpty) {
        issues.add(
          DocumentPackageIssue(
            code: 'empty_node_id',
            message: 'Node ID is empty.',
            path: '$path.id',
            repairable: true,
          ),
        );
      } else if (!nodeIds.add(id)) {
        duplicateNodeIds.add(id);
        issues.add(
          DocumentPackageIssue(
            code: 'duplicate_node_id',
            message: 'Node ID $id is repeated.',
            path: '$path.id',
            repairable: true,
          ),
        );
      }
      if (!node.x.isFinite || !node.y.isFinite) {
        issues.add(
          DocumentPackageIssue(
            code: 'invalid_node_position',
            message: 'Node position must be finite.',
            path: path,
            repairable: true,
          ),
        );
      }
      if (!node.width.isFinite ||
          !node.height.isFinite ||
          node.width < 0 ||
          node.height < 0) {
        issues.add(
          DocumentPackageIssue(
            code: 'invalid_node_size',
            message: 'Node size must be finite and non-negative.',
            path: path,
            repairable: true,
          ),
        );
      }
    }

    final knownNodeIds = nodeIds.toSet();
    for (var index = 0; index < document.nodes.length; index++) {
      final node = document.nodes[index];
      if (node.parentId != null && !knownNodeIds.contains(node.parentId)) {
        issues.add(
          DocumentPackageIssue(
            code: 'missing_parent_node',
            message: 'Parent node ${node.parentId} does not exist.',
            path: 'document.nodes[$index].parentId',
            severity: DocumentPackageIssueSeverity.warning,
            repairable: true,
          ),
        );
      }
      if (node.variantOfNodeId != null &&
          !knownNodeIds.contains(node.variantOfNodeId)) {
        issues.add(
          DocumentPackageIssue(
            code: 'missing_variant_node',
            message: 'Variant source ${node.variantOfNodeId} does not exist.',
            path: 'document.nodes[$index].variantOfNodeId',
            severity: DocumentPackageIssueSeverity.warning,
            repairable: true,
          ),
        );
      }
      for (final entry in _assetReferences(node.payload.toJson()).entries) {
        if (!effectiveAssets.entries.containsKey(entry.value) ||
            effectiveAssets[entry.value]!.id != entry.value) {
          issues.add(
            DocumentPackageIssue(
              code: 'missing_asset_reference',
              message: 'Asset ${entry.value} is not present in the manifest.',
              path: 'document.nodes[$index].${entry.key}',
              severity: DocumentPackageIssueSeverity.warning,
            ),
          );
        }
      }
    }

    final edgeIds = <String>{};
    for (var index = 0; index < document.edges.length; index++) {
      final edge = document.edges[index];
      final path = 'document.edges[$index]';
      final id = edge.id.trim();
      if (id.isEmpty) {
        issues.add(
          DocumentPackageIssue(
            code: 'empty_edge_id',
            message: 'Edge ID is empty.',
            path: '$path.id',
            repairable: true,
          ),
        );
      } else if (!edgeIds.add(id)) {
        issues.add(
          DocumentPackageIssue(
            code: 'duplicate_edge_id',
            message: 'Edge ID $id is repeated.',
            path: '$path.id',
            repairable: true,
          ),
        );
      }
      if (edge.sourceNodeId != null &&
          !knownNodeIds.contains(edge.sourceNodeId)) {
        issues.add(
          DocumentPackageIssue(
            code: 'dangling_edge_source',
            message: 'Source node ${edge.sourceNodeId} does not exist.',
            path: '$path.sourceNodeId',
            repairable: true,
          ),
        );
      }
      if (edge.targetNodeId != null &&
          !knownNodeIds.contains(edge.targetNodeId)) {
        issues.add(
          DocumentPackageIssue(
            code: 'dangling_edge_target',
            message: 'Target node ${edge.targetNodeId} does not exist.',
            path: '$path.targetNodeId',
            repairable: true,
          ),
        );
      }
    }

    final manifestKeys = <String>{};
    for (final entry in effectiveAssets.entries.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || entry.value.id.trim() != key) {
        issues.add(
          DocumentPackageIssue(
            code: 'asset_manifest_key_mismatch',
            message: 'Asset manifest key does not match the asset ID.',
            path: 'assets.items.${entry.key}',
            severity: DocumentPackageIssueSeverity.warning,
            repairable: true,
          ),
        );
      }
      if (!manifestKeys.add(key)) {
        issues.add(
          DocumentPackageIssue(
            code: 'duplicate_asset_id',
            message: 'Asset ID $key is repeated.',
            path: 'assets.items.$key',
            repairable: true,
          ),
        );
      }
      if (entry.value.checksum?.trim().isEmpty == true) {
        issues.add(
          DocumentPackageIssue(
            code: 'empty_asset_checksum',
            message: 'Asset checksum is empty.',
            path: 'assets.items.$key.checksum',
            severity: DocumentPackageIssueSeverity.warning,
          ),
        );
      }
    }

    var checksum = '';
    try {
      checksum = checksumFor(package);
    } on FormatException catch (error) {
      issues.add(
        DocumentPackageIssue(
          code: 'invalid_asset_manifest_identity',
          message: error.message,
          path: 'assets',
          repairable: true,
        ),
      );
    }
    if (expectedChecksum != null &&
        !_checksumEquals(checksum, expectedChecksum)) {
      issues.add(
        const DocumentPackageIssue(
          code: 'package_checksum_mismatch',
          message: 'Package checksum does not match the expected checksum.',
        ),
      );
    }

    if (duplicateNodeIds.isNotEmpty) {
      issues.add(
        DocumentPackageIssue(
          code: 'duplicate_node_summary',
          message: '${duplicateNodeIds.length} duplicate node ID(s) detected.',
          severity: DocumentPackageIssueSeverity.info,
        ),
      );
    }

    return DocumentPackageHealthReport(
      issues: List.unmodifiable(issues),
      checksum: checksum,
      nodeCount: document.nodes.length,
      edgeCount: document.edges.length,
      assetCount: effectiveAssets.entries.length,
    );
  }

  static DocumentPackageRepairResult repair(
    CanvasDocumentPackage package, {
    bool removeDanglingEdges = true,
    bool normalizeGeometry = true,
  }) {
    final actions = <String>[];
    final nodes = <CanvasNode>[];
    final idMap = <String, String>{};
    final usedIds = <String>{};

    for (var index = 0; index < package.document.nodes.length; index++) {
      final original = package.document.nodes[index];
      final oldId = original.id.trim();
      final candidate = oldId.isEmpty ? 'repaired-node-${index + 1}' : oldId;
      if (usedIds.contains(candidate)) {
        actions.add('Removed duplicate node $candidate.');
        continue;
      }
      usedIds.add(candidate);
      if (oldId.isNotEmpty) idMap[oldId] = candidate;
      if (oldId.isEmpty) {
        actions.add('Assigned ID $candidate to an empty node ID.');
      }
      var node = original.copyWith(id: candidate);
      if (normalizeGeometry) {
        final x = original.x.isFinite ? original.x : 0.0;
        final y = original.y.isFinite ? original.y : 0.0;
        final width = original.width.isFinite
            ? math.max(0, original.width).toDouble()
            : 0.0;
        final height = original.height.isFinite
            ? math.max(0, original.height).toDouble()
            : 0.0;
        final rotation = original.rotation.isFinite ? original.rotation : 0.0;
        final opacity = original.opacity.isFinite
            ? original.opacity.clamp(0.0, 1.0).toDouble()
            : 1.0;
        if (x != original.x ||
            y != original.y ||
            width != original.width ||
            height != original.height ||
            rotation != original.rotation ||
            opacity != original.opacity) {
          actions.add('Normalized geometry for node $candidate.');
        }
        node = node.copyWith(
          x: x,
          y: y,
          width: width,
          height: height,
          rotation: rotation,
          opacity: opacity,
        );
      }
      nodes.add(node);
    }

    String? remapNodeId(String? id) {
      final value = id?.trim();
      if (value == null || value.isEmpty) return null;
      final mapped = idMap[value];
      return mapped != null && usedIds.contains(mapped) ? mapped : null;
    }

    final normalizedNodes = nodes
        .map(
          (node) => node.copyWith(
            parentId: remapNodeId(node.parentId),
            variantOfNodeId: remapNodeId(node.variantOfNodeId),
            prototypeInteractions: node.prototypeInteractions
                .map(
                  (interaction) => interaction.copyWith(
                    targetFrameId: remapNodeId(interaction.targetFrameId),
                    targetNodeId: remapNodeId(interaction.targetNodeId),
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);

    final edges = <CanvasEdge>[];
    final edgeIds = <String>{};
    for (var index = 0; index < package.document.edges.length; index++) {
      final original = package.document.edges[index];
      final candidate = original.id.trim().isEmpty
          ? 'repaired-edge-${index + 1}'
          : original.id.trim();
      if (!edgeIds.add(candidate)) {
        actions.add('Removed duplicate edge $candidate.');
        continue;
      }
      final source = remapNodeId(original.sourceNodeId);
      final target = remapNodeId(original.targetNodeId);
      if (removeDanglingEdges &&
          ((original.sourceNodeId != null && source == null) ||
              (original.targetNodeId != null && target == null))) {
        actions.add('Removed dangling edge $candidate.');
        continue;
      }
      edges.add(
        original.copyWith(
          id: candidate,
          sourceNodeId: source,
          targetNodeId: target,
          parentId: remapNodeId(original.parentId),
        ),
      );
      if (candidate != original.id) {
        actions.add('Assigned ID $candidate to an empty edge ID.');
      }
    }

    final sourceAssets = package.assets.items.isEmpty
        ? package.document.assets
        : package.assets;
    final assetIdMap = <String, String>{};
    final assetEntries = <String, DocumentAsset>{};
    for (final entry in sourceAssets.entries.entries) {
      final oldId = entry.value.id.trim().isEmpty
          ? entry.key.trim()
          : entry.value.id.trim();
      if (oldId.isEmpty || assetEntries.containsKey(oldId)) {
        actions.add(
          'Removed duplicate or empty asset manifest entry ${entry.key}.',
        );
        continue;
      }
      assetIdMap[entry.key] = oldId;
      assetIdMap[entry.value.id] = oldId;
      assetEntries[oldId] = entry.value.copyWith(id: oldId);
      if (entry.key != oldId) {
        actions.add('Normalized asset manifest key ${entry.key} to $oldId.');
      }
    }
    final assets = DocumentAssetManifest(
      version: sourceAssets.version,
      entries: assetEntries,
    );
    NodePayload remapAssetReferences(NodeType type, NodePayload payload) {
      final json = Map<String, dynamic>.from(payload.toJson());
      Object? rewrite(Object? value) {
        if (value is Map) {
          return <String, dynamic>{
            for (final entry in value.entries)
              entry.key.toString():
                  entry.key.toString() == 'assetId' && entry.value is String
                  ? assetIdMap[entry.value] ?? entry.value
                  : rewrite(entry.value),
          };
        }
        if (value is List) return value.map(rewrite).toList(growable: false);
        return value;
      }

      return NodePayload.fromJson(
        type,
        Map<String, dynamic>.from(rewrite(json) as Map),
      );
    }

    final repairedNodes = normalizedNodes
        .map(
          (node) => node.copyWith(
            payload: remapAssetReferences(node.type, node.payload),
          ),
        )
        .toList(growable: false);
    final document = package.document.copyWith(
      nodes: repairedNodes,
      edges: edges.cast(),
      assets: assets,
    );
    final repaired = CanvasDocumentPackage(document: document, assets: assets);
    return DocumentPackageRepairResult(
      package: repaired,
      actions: List.unmodifiable(actions),
      health: inspect(repaired),
    );
  }

  static CanvasDocument duplicateDocument(
    CanvasDocument source, {
    String? projectId,
    String? canvasId,
    String prefix = 'copy',
  }) {
    final normalizedPrefix = prefix.trim().isEmpty ? 'copy' : prefix.trim();
    final nodeIds = <String, String>{};
    for (final node in source.nodes) {
      nodeIds[node.id] = '$normalizedPrefix-${node.id}';
    }
    final nodes = source.nodes
        .map(
          (node) => node.copyWith(
            id: nodeIds[node.id],
            parentId: node.parentId == null ? null : nodeIds[node.parentId],
            variantOfNodeId: node.variantOfNodeId == null
                ? null
                : nodeIds[node.variantOfNodeId],
            prototypeInteractions: node.prototypeInteractions
                .map(
                  (interaction) => interaction.copyWith(
                    targetFrameId: interaction.targetFrameId == null
                        ? null
                        : nodeIds[interaction.targetFrameId],
                    targetNodeId: interaction.targetNodeId == null
                        ? null
                        : nodeIds[interaction.targetNodeId],
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    final edges = source.edges
        .map(
          (edge) => edge.copyWith(
            id: '$normalizedPrefix-${edge.id}',
            sourceNodeId: edge.sourceNodeId == null
                ? null
                : nodeIds[edge.sourceNodeId],
            targetNodeId: edge.targetNodeId == null
                ? null
                : nodeIds[edge.targetNodeId],
            parentId: edge.parentId == null ? null : nodeIds[edge.parentId],
          ),
        )
        .toList(growable: false);
    return source.copyWith(
      projectId: projectId ?? '${source.projectId}-copy',
      canvasId: canvasId ?? '${source.canvasId}-copy',
      nodes: nodes,
      edges: edges,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  static String checksumFor(CanvasDocumentPackage package) {
    final assets = package.assets;
    final documentAssets = package.document.assets;
    if (assets.items.isEmpty) {
      assets.validateIdentity();
      documentAssets.validateIdentity();
    } else {
      assets.validateIdentity();
    }
    final effectiveAssets = assets.items.isEmpty ? documentAssets : assets;
    final normalizedPackage = CanvasDocumentPackage(
      document: package.document.copyWith(assets: effectiveAssets),
      assets: effectiveAssets,
    );
    return sha256
        .convert(utf8.encode(_canonicalJson(normalizedPackage.toJson())))
        .toString();
  }

  static String _canonicalJson(Object? value) {
    final canonical = _canonicalize(value);
    return jsonEncode(canonical);
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }

  static Map<String, String> _assetReferences(Map<String, dynamic> json) {
    final references = <String, String>{};
    void visit(Object? value, String path) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          final childPath = path.isEmpty ? key : '$path.$key';
          if (key == 'assetId' &&
              entry.value is String &&
              (entry.value as String).trim().isNotEmpty) {
            references[childPath] = (entry.value as String).trim();
          }
          visit(entry.value, childPath);
        }
      } else if (value is Iterable) {
        var index = 0;
        for (final item in value) {
          visit(item, '$path[$index]');
          index++;
        }
      }
    }

    visit(json, 'payload');
    return references;
  }

  static bool _checksumEquals(String actual, String expected) {
    final normalized = expected.trim().toLowerCase();
    final withoutPrefix = normalized.startsWith('sha256:')
        ? normalized.substring('sha256:'.length)
        : normalized;
    return actual.toLowerCase() == withoutPrefix;
  }
}
