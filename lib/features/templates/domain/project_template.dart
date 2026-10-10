import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';
import '../data/diagram_templates.dart';
import 'package:uuid/uuid.dart';

enum ProjectTemplateScope { builtIn, personal, team }

class ProjectTemplate {
  final String id;
  final String name;
  final String description;
  final ProjectTemplateScope scope;
  final String? diagramTemplateId;
  final List<CanvasNode> selectionNodes;
  final List<CanvasEdge> selectionEdges;
  final List<String> tags;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProjectTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.scope,
    this.diagramTemplateId,
    this.selectionNodes = const [],
    this.selectionEdges = const [],
    this.tags = const [],
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isBuiltIn => scope == ProjectTemplateScope.builtIn;

  ProjectTemplate copyWith({
    String? name,
    String? description,
    ProjectTemplateScope? scope,
    Object? diagramTemplateId = _sentinel,
    List<CanvasNode>? selectionNodes,
    List<CanvasEdge>? selectionEdges,
    List<String>? tags,
    bool? favorite,
    DateTime? updatedAt,
  }) => ProjectTemplate(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    scope: scope ?? this.scope,
    diagramTemplateId: diagramTemplateId == _sentinel
        ? this.diagramTemplateId
        : diagramTemplateId as String?,
    selectionNodes: selectionNodes ?? this.selectionNodes,
    selectionEdges: selectionEdges ?? this.selectionEdges,
    tags: tags ?? this.tags,
    favorite: favorite ?? this.favorite,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  DiagramTemplateInstance instantiate({
    Iterable<String> existingNodeIds = const <String>[],
    Iterable<String> existingEdgeIds = const <String>[],
  }) {
    if (selectionNodes.isNotEmpty) {
      return _instantiateSelection(
        existingNodeIds: existingNodeIds,
        existingEdgeIds: existingEdgeIds,
      );
    }
    final templateId = diagramTemplateId;
    if (templateId == null || templateId.trim().isEmpty) {
      return const DiagramTemplateInstance(nodes: [], edges: []);
    }
    return DiagramTemplates.instantiate(
      templateId,
      existingNodeIds: existingNodeIds,
      existingEdgeIds: existingEdgeIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'scope': scope.name,
    if (diagramTemplateId != null) 'diagramTemplateId': diagramTemplateId,
    if (selectionNodes.isNotEmpty)
      'selectionNodes': selectionNodes.map((node) => node.toJson()).toList(),
    if (selectionEdges.isNotEmpty)
      'selectionEdges': selectionEdges.map((edge) => edge.toJson()).toList(),
    if (tags.isNotEmpty) 'tags': tags,
    'favorite': favorite,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory ProjectTemplate.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final rawScope = json['scope'] as String?;
    final scope = ProjectTemplateScope.values.firstWhere(
      (value) => value.name == rawScope,
      orElse: () => ProjectTemplateScope.personal,
    );
    return ProjectTemplate(
      id: json['id'] as String? ?? 'template-${now.microsecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Untitled template',
      description: json['description'] as String? ?? '',
      scope: scope,
      diagramTemplateId: json['diagramTemplateId'] as String?,
      selectionNodes:
          (json['selectionNodes'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (item) => CanvasNode.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          const [],
      selectionEdges:
          (json['selectionEdges'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (item) => CanvasEdge.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          const [],
      tags:
          (json['tags'] as List<dynamic>?)?.whereType<String>().toList() ??
          const [],
      favorite: json['favorite'] as bool? ?? false,
      createdAt: createdAt?.toUtc() ?? now,
      updatedAt: updatedAt?.toUtc() ?? now,
    );
  }

  static const Object _sentinel = Object();

  DiagramTemplateInstance _instantiateSelection({
    required Iterable<String> existingNodeIds,
    required Iterable<String> existingEdgeIds,
  }) {
    final usedNodeIds = {
      ...existingNodeIds,
      ...selectionNodes.map((node) => node.id),
    };
    final usedEdgeIds = {
      ...existingEdgeIds,
      ...selectionEdges.map((edge) => edge.id),
    };
    final nodeIdMap = <String, String>{};
    for (final node in selectionNodes) {
      var id = const Uuid().v4();
      while (usedNodeIds.contains(id)) {
        id = const Uuid().v4();
      }
      usedNodeIds.add(id);
      nodeIdMap[node.id] = id;
    }
    final edgeIdMap = <String, String>{};
    for (final edge in selectionEdges) {
      var id = const Uuid().v4();
      while (usedEdgeIds.contains(id)) {
        id = const Uuid().v4();
      }
      usedEdgeIds.add(id);
      edgeIdMap[edge.id] = id;
    }
    String? remap(String? id) => id == null ? null : nodeIdMap[id];
    return DiagramTemplateInstance(
      nodes: [
        for (final node in selectionNodes)
          node.copyWith(
            id: nodeIdMap[node.id],
            parentId: remap(node.parentId),
            variantOfNodeId: remap(node.variantOfNodeId),
            mermaidSourceId: remap(node.mermaidSourceId),
          ),
      ],
      edges: [
        for (final edge in selectionEdges)
          edge.copyWith(
            id: edgeIdMap[edge.id],
            sourceNodeId: remap(edge.sourceNodeId),
            targetNodeId: remap(edge.targetNodeId),
            parentId: remap(edge.parentId),
            mermaidSourceId: remap(edge.mermaidSourceId),
          ),
      ],
    );
  }
}

class ProjectTemplateMergeResult {
  final ProjectTemplateCatalog catalog;
  final List<ProjectTemplate> localWins;
  final List<ProjectTemplate> remoteWins;
  final List<ProjectTemplate> remoteOnly;

  const ProjectTemplateMergeResult({
    required this.catalog,
    this.localWins = const [],
    this.remoteWins = const [],
    this.remoteOnly = const [],
  });
}

class ProjectTemplateSyncResult {
  final ProjectTemplateCatalog catalog;
  final List<ProjectTemplate> uploaded;
  final List<ProjectTemplate> failedUploads;

  const ProjectTemplateSyncResult({
    required this.catalog,
    this.uploaded = const [],
    this.failedUploads = const [],
  });
}

class ProjectTemplateCatalog {
  final List<ProjectTemplate> templates;

  const ProjectTemplateCatalog({this.templates = const []});

  factory ProjectTemplateCatalog.withBuiltIns({
    Iterable<ProjectTemplate> custom = const [],
  }) {
    final now = DateTime.now().toUtc();
    final builtIns = [
      for (final metadata in DiagramTemplates.listTemplates())
        ProjectTemplate(
          id: 'builtin:${metadata.id}',
          name: metadata.name,
          description: metadata.description,
          scope: ProjectTemplateScope.builtIn,
          diagramTemplateId: metadata.id,
          tags: [metadata.category],
          createdAt: now,
          updatedAt: now,
        ),
    ];
    return ProjectTemplateCatalog(templates: [...builtIns, ...custom]);
  }

  List<ProjectTemplate> search({
    String query = '',
    ProjectTemplateScope? scope,
    Iterable<String> tags = const [],
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final requiredTags = tags
        .map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    return templates
        .where((template) {
          if (scope != null && template.scope != scope) return false;
          if (!requiredTags.every(
            (tag) => template.tags.any((item) => item.toLowerCase() == tag),
          )) {
            return false;
          }
          if (normalizedQuery.isEmpty) return true;
          return '${template.name} ${template.description} ${template.tags.join(' ')}'
              .toLowerCase()
              .contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  ProjectTemplateMergeResult mergeRemote(ProjectTemplateCatalog remote) {
    final localCustom = <String, ProjectTemplate>{
      for (final template in templates)
        if (!template.isBuiltIn) template.id: template,
    };
    final remoteCustom = <String, ProjectTemplate>{
      for (final template in remote.templates)
        if (!template.isBuiltIn) template.id: template,
    };
    final ids = <String>{...localCustom.keys, ...remoteCustom.keys};
    var merged = ProjectTemplateCatalog.withBuiltIns();
    final localWins = <ProjectTemplate>[];
    final remoteWins = <ProjectTemplate>[];
    final remoteOnly = <ProjectTemplate>[];

    for (final id in ids) {
      final localTemplate = localCustom[id];
      final remoteTemplate = remoteCustom[id];
      if (localTemplate == null) {
        if (remoteTemplate != null) {
          merged = merged.upsert(remoteTemplate);
          remoteOnly.add(remoteTemplate);
        }
        continue;
      }
      if (remoteTemplate == null) {
        merged = merged.upsert(localTemplate);
        localWins.add(localTemplate);
        continue;
      }
      if (localTemplate.updatedAt.isAfter(remoteTemplate.updatedAt)) {
        merged = merged.upsert(localTemplate);
        localWins.add(localTemplate);
      } else {
        merged = merged.upsert(remoteTemplate);
        remoteWins.add(remoteTemplate);
      }
    }

    return ProjectTemplateMergeResult(
      catalog: merged,
      localWins: List.unmodifiable(localWins),
      remoteWins: List.unmodifiable(remoteWins),
      remoteOnly: List.unmodifiable(remoteOnly),
    );
  }

  ProjectTemplateCatalog upsert(ProjectTemplate template) {
    final next = [...templates];
    final index = next.indexWhere((item) => item.id == template.id);
    if (index < 0) {
      next.add(template);
    } else {
      next[index] = template;
    }
    return ProjectTemplateCatalog(templates: next);
  }

  ProjectTemplateCatalog remove(String id) {
    return ProjectTemplateCatalog(
      templates: templates.where((template) => template.id != id).toList(),
    );
  }

  ProjectTemplateCatalog toggleFavorite(String id) {
    final template = templates.where((item) => item.id == id).firstOrNull;
    if (template == null) return this;
    return upsert(
      template.copyWith(
        favorite: !template.favorite,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

class StarterProjectRequest {
  final String projectName;
  final String? templateId;
  final bool includeSampleAssets;

  const StarterProjectRequest({
    required this.projectName,
    this.templateId,
    this.includeSampleAssets = false,
  });
}

class StarterProjectInstance {
  final String projectName;
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final bool includesSampleAssets;

  const StarterProjectInstance({
    required this.projectName,
    required this.nodes,
    required this.edges,
    required this.includesSampleAssets,
  });
}
