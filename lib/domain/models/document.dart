import 'connector_edge.dart';
import 'document_asset.dart';
import 'document_migrations.dart';
import 'durable_asset_reference.dart';
import 'design_tokens.dart';
import 'node.dart';
import 'viewport.dart';

class CanvasDocument {
  final int schemaVersion;
  final String projectId;
  final String canvasId;
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final Viewport viewport;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> navigation;
  final DocumentAssetManifest assets;
  final DesignTokenSet tokens;
  final DateTime updatedAt;

  const CanvasDocument({
    this.schemaVersion = DocumentMigrations.currentVersion,
    required this.projectId,
    this.canvasId = 'canvas_main',
    this.nodes = const [],
    this.edges = const [],
    this.viewport = const Viewport(),
    this.metadata = const {},
    this.navigation = const {},
    this.assets = const DocumentAssetManifest(),
    this.tokens = const DesignTokenSet(),
    required this.updatedAt,
  });

  CanvasDocument copyWith({
    int? schemaVersion,
    String? projectId,
    String? canvasId,
    List<CanvasNode>? nodes,
    List<CanvasEdge>? edges,
    Viewport? viewport,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? navigation,
    DocumentAssetManifest? assets,
    DesignTokenSet? tokens,
    DateTime? updatedAt,
  }) {
    return CanvasDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      projectId: projectId ?? this.projectId,
      canvasId: canvasId ?? this.canvasId,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      viewport: viewport ?? this.viewport,
      metadata: metadata ?? this.metadata,
      navigation: navigation ?? this.navigation,
      assets: assets ?? this.assets,
      tokens: tokens ?? this.tokens,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => _toJson(
    nodes.map((node) => node.toJson()).toList(growable: false),
    durable: false,
  );

  /// Durable document projection. This is the only document representation
  /// permitted for local/cloud persistence, recovery, history, CRDT state,
  /// publication, sharing, and export envelopes.
  Map<String, dynamic> toPersistenceJson() => _toJson(
    nodes.map((node) => node.toPersistenceJson()).toList(growable: false),
    durable: true,
  );

  Map<String, dynamic> _toJson(
    List<Map<String, dynamic>> nodeJson, {
    required bool durable,
  }) => {
    'schemaVersion': schemaVersion,
    'projectId': projectId,
    'canvasId': canvasId,
    'nodes': nodeJson,
    'edges': edges
        .map((e) => durable ? e.toPersistenceJson() : e.toJson())
        .toList(),
    'viewport': viewport.toJson(),
    'metadata': durable ? _durableMetadata(metadata) : metadata,
    'navigation': durable ? _durableMetadata(navigation) : navigation,
    'assets': durable ? assets.toPersistenceJson() : assets.toJson(),
    'tokens': tokens.toJson(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static Map<String, dynamic> _durableMetadata(Map<String, dynamic> values) {
    final result = <String, dynamic>{};
    for (final entry in values.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || _unsafeMetadataKey(key)) continue;
      final value = _durableMetadataValue(entry.value, depth: 0);
      if (value != null) result[key] = value;
    }
    return result;
  }

  static dynamic _durableMetadataValue(Object? value, {required int depth}) {
    if (depth > 5) return null;
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : null;
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty || isTransientAssetReference(normalized)) {
        return null;
      }
      final durable = durableAssetReference(normalized);
      if (durable != null) return durable;
      final uri = Uri.tryParse(normalized);
      if (uri?.scheme.isNotEmpty == true ||
          normalized.startsWith('/') ||
          normalized.startsWith('\\\\') ||
          RegExp(r'^[a-z]:[\\\\/]').hasMatch(normalized)) {
        return null;
      }
      return normalized.length > 4096
          ? normalized.substring(0, 4096)
          : normalized;
    }
    if (value is List) {
      return [
        for (final child in value)
          ?_durableMetadataValue(child, depth: depth + 1),
      ];
    }
    if (value is Map) {
      return _durableMetadata(Map<String, dynamic>.from(value));
    }
    return null;
  }

  static bool _unsafeMetadataKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('path') ||
        normalized.contains('url') ||
        normalized.contains('bytes') ||
        normalized.contains('base64') ||
        normalized.contains('token') ||
        normalized.contains('secret');
  }

  factory CanvasDocument.fromJson(Map<String, dynamic> json) {
    final migrated = DocumentMigrations.migrate(json).json;
    return CanvasDocument(
      schemaVersion:
          migrated['schemaVersion'] as int? ??
          DocumentMigrations.currentVersion,
      projectId: migrated['projectId'] as String? ?? 'default_proj',
      canvasId: migrated['canvasId'] as String? ?? 'canvas_main',
      nodes:
          (migrated['nodes'] as List<dynamic>?)
              ?.map((e) => CanvasNode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      edges:
          (migrated['edges'] as List<dynamic>?)
              ?.map((e) => CanvasEdge.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      viewport: migrated['viewport'] != null
          ? Viewport.fromJson(migrated['viewport'] as Map<String, dynamic>)
          : const Viewport(),
      metadata: migrated['metadata'] is Map
          ? Map<String, dynamic>.from(migrated['metadata'] as Map)
          : {},
      navigation: migrated['navigation'] is Map
          ? Map<String, dynamic>.from(migrated['navigation'] as Map)
          : {},
      assets: DocumentAssetManifest.fromJson(migrated['assets']),
      tokens: DesignTokenSet.fromJson(migrated['tokens']),
      updatedAt: migrated['updatedAt'] != null
          ? DateTime.tryParse(migrated['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
