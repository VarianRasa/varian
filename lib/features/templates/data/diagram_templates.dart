import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/component_payload.dart';
import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import 'reusable_kits.dart';

enum DiagramTemplateKind { template, kit }

class DiagramTemplateMetadata {
  final String id;
  final String name;
  final String description;
  final DiagramTemplateKind kind;

  const DiagramTemplateMetadata({
    required this.id,
    required this.name,
    required this.description,
    this.kind = DiagramTemplateKind.template,
  });

  String get title => name;

  String get category => kind.name;

  bool get isKit => kind == DiagramTemplateKind.kit;
}

typedef TemplateMetadata = DiagramTemplateMetadata;

class DiagramTemplateInstance {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;

  const DiagramTemplateInstance({required this.nodes, required this.edges});
}

typedef TemplateInstance = DiagramTemplateInstance;

typedef _TemplateSource = ({List<CanvasNode> nodes, List<CanvasEdge> edges});

class _TemplateDefinition {
  final DiagramTemplateMetadata metadata;
  final _TemplateSource Function() source;

  const _TemplateDefinition({required this.metadata, required this.source});
}

class DiagramTemplates {
  const DiagramTemplates._();

  static final List<_TemplateDefinition> _definitions = [
    const _TemplateDefinition(
      metadata: DiagramTemplateMetadata(
        id: 'flowchart',
        name: 'Flowchart',
        description: 'A simple start, process, decision, and end flowchart.',
      ),
      source: _buildFlowchartSource,
    ),
    const _TemplateDefinition(
      metadata: DiagramTemplateMetadata(
        id: 'primary-button',
        name: 'Primary Button',
        description: 'A reusable component kit for a primary action button.',
        kind: DiagramTemplateKind.kit,
      ),
      source: _buildPrimaryButtonSource,
    ),
    const _TemplateDefinition(
      metadata: DiagramTemplateMetadata(
        id: 'moodboard',
        name: 'Moodboard',
        description: 'A visual direction board with image slots and notes.',
      ),
      source: _buildMoodboardSource,
    ),
    const _TemplateDefinition(
      metadata: DiagramTemplateMetadata(
        id: 'storyboard',
        name: 'Storyboard',
        description: 'A six-shot storyboard with captions and timing notes.',
      ),
      source: _buildStoryboardSource,
    ),
    const _TemplateDefinition(
      metadata: DiagramTemplateMetadata(
        id: 'pitch-deck',
        name: 'Pitch Deck',
        description:
            'A presentation outline with title, problem, solution, and next steps.',
      ),
      source: _buildPitchDeckSource,
    ),
  ];

  /// Returns the named templates and kits available for insertion.
  static List<DiagramTemplateMetadata> listTemplates() {
    return List.unmodifiable(
      _definitions.map((definition) => definition.metadata),
    );
  }

  /// Alias for consumers that prefer property access.
  static List<DiagramTemplateMetadata> get templates => listTemplates();

  /// Public registry view for callers that use registry terminology.
  static List<DiagramTemplateMetadata> get registry => listTemplates();

  /// Creates a fresh, document-safe instance of [templateId].
  ///
  /// [origin] is the top-left origin for the returned top-level nodes.
  /// Existing IDs are reserved before new node, nested-child, and edge IDs
  /// are generated, so an instance can be inserted into a live document.
  static DiagramTemplateInstance instantiate(
    String templateId, {
    Offset origin = Offset.zero,
    Iterable<String> existingNodeIds = const <String>[],
    Iterable<String> existingEdgeIds = const <String>[],
  }) {
    final definition = _definitions.firstWhere(
      (candidate) => candidate.metadata.id == templateId,
      orElse: () => throw ArgumentError.value(
        templateId,
        'templateId',
        'Unknown diagram template or reusable kit',
      ),
    );

    final source = definition.source();
    final usedIds = <String>{...existingNodeIds, ...existingEdgeIds};
    final idMap = <String, String>{};

    for (final node in source.nodes) {
      _reserveNodeIds(node, definition.metadata.id, usedIds, idMap);
    }

    final nodes = source.nodes
        .map((node) => _remapNode(node, idMap, offset: origin))
        .toList(growable: false);

    final edges = source.edges
        .map((edge) {
          final sourceNodeId = idMap[edge.sourceNodeId];
          final targetNodeId = idMap[edge.targetNodeId];
          if (sourceNodeId == null || targetNodeId == null) {
            throw StateError(
              'Template ${definition.metadata.id} contains an edge with a missing node',
            );
          }
          return edge.copyWith(
            id: _freshId(definition.metadata.id, usedIds),
            sourceNodeId: sourceNodeId,
            targetNodeId: targetNodeId,
          );
        })
        .toList(growable: false);

    return DiagramTemplateInstance(nodes: nodes, edges: edges);
  }

  /// Alias for callers that name the operation explicitly.
  static DiagramTemplateInstance instantiateTemplate(
    String templateId, {
    Offset origin = Offset.zero,
    Iterable<String> existingNodeIds = const <String>[],
    Iterable<String> existingEdgeIds = const <String>[],
  }) {
    return instantiate(
      templateId,
      origin: origin,
      existingNodeIds: existingNodeIds,
      existingEdgeIds: existingEdgeIds,
    );
  }

  /// Backward-compatible flowchart factory used by existing callers.
  static (List<CanvasNode>, List<CanvasEdge>) createFlowchart() {
    final instance = instantiate('flowchart', origin: const Offset(100, 100));
    return (instance.nodes, instance.edges);
  }

  static void _reserveNodeIds(
    CanvasNode node,
    String templateId,
    Set<String> usedIds,
    Map<String, String> idMap,
  ) {
    idMap.putIfAbsent(node.id, () => _freshId(templateId, usedIds));
    final payload = node.payload;
    if (payload is ComponentPayload) {
      idMap.putIfAbsent(
        payload.masterComponentId,
        () => _freshId(templateId, usedIds),
      );
      for (final child in payload.templateChildren) {
        _reserveNodeIds(child, templateId, usedIds, idMap);
      }
    }
  }

  static CanvasNode _remapNode(
    CanvasNode node,
    Map<String, String> idMap, {
    Offset offset = Offset.zero,
  }) {
    final parentId = node.parentId == null
        ? null
        : idMap[node.parentId!] ?? node.parentId;
    return node.copyWith(
      id: idMap[node.id] ?? node.id,
      x: node.x + offset.dx,
      y: node.y + offset.dy,
      parentId: parentId,
      payload: _remapPayload(node.payload, idMap),
    );
  }

  static NodePayload _remapPayload(
    NodePayload payload,
    Map<String, String> idMap,
  ) {
    if (payload is ComponentPayload) {
      return payload.copyWith(
        masterComponentId:
            idMap[payload.masterComponentId] ?? payload.masterComponentId,
        templateChildren: payload.templateChildren
            .map((child) => _remapNode(child, idMap))
            .toList(growable: false),
      );
    }
    if (payload is GroupPayload) {
      return payload.copyWith(
        childNodeIds: payload.childNodeIds
            .map((childId) => idMap[childId] ?? childId)
            .toList(growable: false),
      );
    }
    return payload.clone();
  }

  static String _freshId(String templateId, Set<String> usedIds) {
    String id;
    do {
      id = '${templateId}_${const Uuid().v4()}';
    } while (!usedIds.add(id));
    return id;
  }

  static _TemplateSource _buildFlowchartSource() {
    final startNode = CanvasNode(
      id: 'flow_start',
      type: NodeType.ellipse,
      x: 0,
      y: 0,
      width: 120,
      height: 60,
      payload: ShapePayload(fill: const Color(0xFF10B981)),
    );

    final processNode = CanvasNode(
      id: 'flow_process',
      type: NodeType.rectangle,
      x: 0,
      y: 120,
      width: 120,
      height: 70,
      payload: ShapePayload(fill: const Color(0xFF3B82F6)),
    );

    final decisionNode = CanvasNode(
      id: 'flow_decision',
      type: NodeType.diamond,
      x: -15,
      y: 250,
      width: 150,
      height: 100,
      payload: ShapePayload(fill: const Color(0xFF8B5CF6)),
    );

    final endNode = CanvasNode(
      id: 'flow_end',
      type: NodeType.ellipse,
      x: 0,
      y: 410,
      width: 120,
      height: 60,
      payload: ShapePayload(fill: const Color(0xFFEF4444)),
    );

    return (
      nodes: [startNode, processNode, decisionNode, endNode],
      edges: [
        const CanvasEdge(
          id: 'e1',
          sourceNodeId: 'flow_start',
          sourceAnchor: AnchorPosition.bottom,
          targetNodeId: 'flow_process',
          targetAnchor: AnchorPosition.top,
        ),
        const CanvasEdge(
          id: 'e2',
          sourceNodeId: 'flow_process',
          sourceAnchor: AnchorPosition.bottom,
          targetNodeId: 'flow_decision',
          targetAnchor: AnchorPosition.top,
        ),
        const CanvasEdge(
          id: 'e3',
          sourceNodeId: 'flow_decision',
          sourceAnchor: AnchorPosition.bottom,
          targetNodeId: 'flow_end',
          targetAnchor: AnchorPosition.top,
          label: 'Yes',
        ),
      ],
    );
  }

  static _TemplateSource _buildPrimaryButtonSource() {
    return (
      nodes: [
        CanvasNode(
          id: 'primary_button',
          type: NodeType.component,
          x: 0,
          y: 0,
          width: 180,
          height: 56,
          payload: ReusableKits.primaryButton(
            masterComponentId: 'primary_button',
          ),
        ),
      ],
      edges: const [],
    );
  }

  static _TemplateSource _buildMoodboardSource() {
    final nodes = <CanvasNode>[
      CanvasNode(
        id: 'moodboard_frame',
        type: NodeType.frame,
        x: 0,
        y: 0,
        width: 1120,
        height: 760,
        payload: FramePayload(
          name: 'Moodboard',
          background: const Color(0xFF111827),
          borderColor: const Color(0xFF334155),
          cornerRadius: 24,
          hasShadow: true,
        ),
      ),
      CanvasNode(
        id: 'moodboard_title',
        type: NodeType.text,
        x: 48,
        y: 36,
        width: 700,
        height: 54,
        payload: TextPayload(
          text: 'Visual direction',
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      CanvasNode(
        id: 'moodboard_subtitle',
        type: NodeType.text,
        x: 50,
        y: 92,
        width: 800,
        height: 32,
        payload: TextPayload(
          text: 'Collect references, colors, materials, and language.',
          fontSize: 16,
          color: const Color(0xFFCBD5E1),
        ),
      ),
      for (var index = 0; index < 4; index++)
        CanvasNode(
          id: 'moodboard_image_$index',
          type: NodeType.image,
          x: 52 + (index % 2) * 500,
          y: 160 + (index ~/ 2) * 240,
          width: 440,
          height: 200,
          payload: ImagePayload(
            caption: 'Drop reference image ${index + 1}',
            cornerRadius: 18,
            strokeColor: const Color(0xFF475569),
            strokeWidth: 1,
          ),
        ),
      CanvasNode(
        id: 'moodboard_note',
        type: NodeType.stickyNote,
        x: 830,
        y: 36,
        width: 240,
        height: 100,
        payload: StickyNotePayload(
          text: 'Add a short creative brief here.',
          backgroundColor: const Color(0xFFFDE68A),
        ),
      ),
    ];
    return (nodes: nodes, edges: const []);
  }

  static _TemplateSource _buildStoryboardSource() {
    final nodes = <CanvasNode>[
      CanvasNode(
        id: 'storyboard_title',
        type: NodeType.text,
        x: 0,
        y: 0,
        width: 700,
        height: 48,
        payload: TextPayload(
          text: 'Storyboard',
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      for (var index = 0; index < 6; index++)
        CanvasNode(
          id: 'storyboard_shot_$index',
          type: NodeType.frame,
          x: (index % 3) * 380,
          y: 90 + (index ~/ 3) * 280,
          width: 340,
          height: 230,
          payload: FramePayload(
            name: 'Shot ${index + 1}',
            background: const Color(0xFF1E293B),
            borderColor: const Color(0xFF475569),
            cornerRadius: 16,
            clipContent: true,
          ),
        ),
      for (var index = 0; index < 6; index++)
        CanvasNode(
          id: 'storyboard_caption_$index',
          type: NodeType.text,
          x: (index % 3) * 380 + 16,
          y: 330 + (index ~/ 3) * 280,
          width: 310,
          height: 36,
          payload: TextPayload(
            text: 'Describe action, camera, and duration.',
            fontSize: 13,
            color: const Color(0xFFCBD5E1),
          ),
        ),
    ];
    return (nodes: nodes, edges: const []);
  }

  static _TemplateSource _buildPitchDeckSource() {
    const slideNames = ['Title', 'Problem', 'Solution', 'Proof', 'Next steps'];
    final nodes = <CanvasNode>[
      for (var index = 0; index < slideNames.length; index++)
        CanvasNode(
          id: 'pitch_slide_$index',
          type: NodeType.frame,
          x: (index % 2) * 620,
          y: (index ~/ 2) * 400,
          width: 560,
          height: 320,
          payload: FramePayload(
            name: 'Slide ${index + 1} — ${slideNames[index]}',
            background: index == 0
                ? const Color(0xFF312E81)
                : const Color(0xFF0F172A),
            borderColor: const Color(0xFF6366F1),
            cornerRadius: 20,
            hasShadow: true,
          ),
        ),
      for (var index = 0; index < slideNames.length; index++)
        CanvasNode(
          id: 'pitch_copy_$index',
          type: NodeType.text,
          x: (index % 2) * 620 + 32,
          y: (index ~/ 2) * 400 + 38,
          width: 480,
          height: 190,
          payload: TextPayload(
            text: index == 0
                ? 'Company / project name\nOne-line promise'
                : 'Add the key message for ${slideNames[index].toLowerCase()}.',
            fontSize: index == 0 ? 28 : 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
    ];
    return (nodes: nodes, edges: const []);
  }
}
