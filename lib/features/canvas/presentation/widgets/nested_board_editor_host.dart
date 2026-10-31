import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/responsive.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../../../domain/models/connector_edge.dart';
import '../../../../domain/models/document_asset_dependencies.dart';
import '../../../../domain/models/node.dart';
import '../../../../domain/models/node_payload.dart';
import '../../../../domain/models/prototype_interaction.dart';
import '../../../../domain/models/vector_path_payload.dart';
import '../../../collaboration/state/collaboration_provider.dart';
import '../../../history/history_provider.dart';
import '../../../link_card/state/link_preview_controller.dart';
import '../../state/canvas_panel_preferences_provider.dart';
import '../../state/document_edges_provider.dart';
import '../../state/document_nodes_provider.dart';
import '../../state/selection_provider.dart';
import '../../state/tool_provider.dart';
import '../../state/viewport_provider.dart';
import 'canvas_editor_panel_controller.dart';
import 'canvas_editor_services.dart';
import 'canvas_editor_surface.dart';

class ImportedNestedDocument {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;

  const ImportedNestedDocument({required this.nodes, required this.edges});
}

class NestedDocumentCodec {
  static ImportedNestedDocument parse(
    String source, {
    Iterable<String> existingNodeIds = const [],
    Iterable<String> existingEdgeIds = const [],
  }) {
    final decoded = jsonDecode(source.trim());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The root value must be a JSON object.');
    }

    final rawNodes = decoded['nodes'] ?? decoded['subNodes'];
    final rawEdges = decoded['edges'] ?? decoded['subEdges'];
    if (rawNodes is! List<dynamic>) {
      throw const FormatException('JSON must contain a nodes array.');
    }
    if (rawEdges != null && rawEdges is! List<dynamic>) {
      throw const FormatException('The edges value must be an array.');
    }
    final rawEdgeList = rawEdges as List<dynamic>? ?? const <dynamic>[];
    _validateRawGroupChildReferences(rawNodes);
    _validateRawMermaidIdLists(rawNodes, rawEdges: rawEdgeList);

    final validExistingNodeIds = existingNodeIds.toSet();
    final usedNodeIds = Set<String>.from(validExistingNodeIds);
    final sourceIds = <String>{};
    final parsedNodes = <CanvasNode>[];
    for (final rawNode in rawNodes) {
      if (rawNode is! Map<String, dynamic>) {
        throw const FormatException('Every node must be a JSON object.');
      }
      final parsed = CanvasNode.fromJson(rawNode);
      if (!sourceIds.add(parsed.id)) {
        throw FormatException('Duplicate node ID: ${parsed.id}');
      }
      parsedNodes.add(parsed);
    }

    final parsedEdges = <CanvasEdge>[];
    final sourceEdgeIds = <String>{};
    for (final rawEdge in rawEdgeList) {
      if (rawEdge is! Map<String, dynamic>) {
        throw const FormatException('Every edge must be a JSON object.');
      }
      final parsed = CanvasEdge.fromJson(rawEdge);
      if (!sourceEdgeIds.add(parsed.id)) {
        throw FormatException('Duplicate edge ID: ${parsed.id}');
      }
      parsedEdges.add(parsed);
    }

    final nodeIdMap = <String, String>{};
    for (final node in parsedNodes) {
      final newId = _uniqueId(usedNodeIds);
      usedNodeIds.add(newId);
      nodeIdMap[node.id] = newId;
    }

    final usedEdgeIds = Set<String>.from(existingEdgeIds);
    final edgeIdMap = <String, String>{};
    for (final edge in parsedEdges) {
      final newId = _uniqueId(usedEdgeIds);
      usedEdgeIds.add(newId);
      edgeIdMap[edge.id] = newId;
    }
    final importedMermaidNodes = <String>{};
    final importedMermaidEdges = <String>{};
    final mermaidNodeOwners = <String, String>{};
    final mermaidEdgeOwners = <String, String>{};
    for (final node in parsedNodes) {
      final payload = node.payload;
      if (payload is! MermaidPayload) continue;
      for (final sourceNodeId in payload.nativeNodeIds) {
        if (!sourceIds.contains(sourceNodeId) ||
            !importedMermaidNodes.add(sourceNodeId)) {
          throw FormatException(
            'nativeNodeIds must reference unique imported nodes: $sourceNodeId',
          );
        }
        final nativeNode = parsedNodes.firstWhere(
          (candidate) => candidate.id == sourceNodeId,
        );
        if (nativeNode.mermaidSourceId != null &&
            nativeNode.mermaidSourceId != node.id) {
          throw FormatException(
            'nativeNodeIds contains a node owned by another Mermaid node: $sourceNodeId',
          );
        }
        mermaidNodeOwners[sourceNodeId] = node.id;
      }
    }
    for (final node in parsedNodes) {
      final payload = node.payload;
      if (payload is! MermaidPayload) continue;
      for (final sourceEdgeId in payload.nativeEdgeIds) {
        if (!sourceEdgeIds.contains(sourceEdgeId) ||
            !importedMermaidEdges.add(sourceEdgeId)) {
          throw FormatException(
            'nativeEdgeIds must reference unique imported edges: $sourceEdgeId',
          );
        }
        final edge = parsedEdges.firstWhere(
          (candidate) => candidate.id == sourceEdgeId,
        );
        if (edge.mermaidSourceId != null && edge.mermaidSourceId != node.id) {
          throw FormatException(
            'nativeEdgeIds contains an edge owned by another Mermaid node: $sourceEdgeId',
          );
        }
        mermaidEdgeOwners[sourceEdgeId] = node.id;
      }
    }

    for (final node in parsedNodes) {
      final ownerId = mermaidNodeOwners[node.id] ?? node.mermaidSourceId;
      if (ownerId == null || !nodeIdMap.containsKey(ownerId)) continue;
      nodeIdMap[node.id] = _remapOwnedMermaidId(
        id: node.id,
        ownerId: ownerId,
        idMap: nodeIdMap,
        ownerIdMap: nodeIdMap,
        kind: 'node',
        occupiedIds: _idOccupancyMap(nodeIdMap, validExistingNodeIds),
      );
    }
    for (final edge in parsedEdges) {
      final ownerId = mermaidEdgeOwners[edge.id] ?? edge.mermaidSourceId;
      if (ownerId == null || !nodeIdMap.containsKey(ownerId)) continue;
      edgeIdMap[edge.id] = _remapOwnedMermaidId(
        id: edge.id,
        ownerId: ownerId,
        idMap: edgeIdMap,
        ownerIdMap: nodeIdMap,
        kind: 'edge',
        occupiedIds: _idOccupancyMap(edgeIdMap, existingEdgeIds.toSet()),
      );
    }
    _validateRemappedMermaidIds(
      nodeIdMap: nodeIdMap,
      edgeIdMap: edgeIdMap,
      existingNodeIds: validExistingNodeIds,
      existingEdgeIds: existingEdgeIds.toSet(),
    );

    final importedNodes = parsedNodes.map((node) {
      final parentId = _remapOptionalId(
        node.parentId,
        nodeIdMap,
        sourceIds,
        'parentId',
      );
      final variantOfNodeId = _remapOptionalId(
        node.variantOfNodeId,
        nodeIdMap,
        sourceIds,
        'variantOfNodeId',
      );
      return node.copyWith(
        id: nodeIdMap[node.id],
        parentId: parentId,
        variantOfNodeId: variantOfNodeId,
        mermaidSourceId: _remapOptionalIdAllowingExisting(
          node.mermaidSourceId,
          nodeIdMap,
          sourceIds,
          validExistingNodeIds,
          'mermaidSourceId',
        ),
        prototypeInteractions: _remapPrototypeInteractions(
          node.prototypeInteractions,
          nodeIdMap,
          sourceIds,
          validExistingNodeIds,
        ),
        payload: _remapPayload(
          node.payload,
          nodeIdMap,
          sourceIds,
          edgeIdMap,
          sourceEdgeIds,
          validExistingNodeIds,
        ),
      );
    }).toList();

    final importedEdges = <CanvasEdge>[];
    for (final parsed in parsedEdges) {
      final sourceId = _remapEndpointId(
        parsed.sourceNodeId,
        nodeIdMap,
        validExistingNodeIds,
        'sourceNodeId',
      );
      final targetId = _remapEndpointId(
        parsed.targetNodeId,
        nodeIdMap,
        validExistingNodeIds,
        'targetNodeId',
      );
      final parentId = _remapEndpointId(
        parsed.parentId,
        nodeIdMap,
        validExistingNodeIds,
        'parentId',
      );
      importedEdges.add(
        parsed.copyWith(
          id: edgeIdMap[parsed.id],
          sourceNodeId: sourceId,
          targetNodeId: targetId,
          parentId: parentId,
          mermaidSourceId: _remapOptionalIdAllowingExisting(
            parsed.mermaidSourceId,
            nodeIdMap,
            sourceIds,
            validExistingNodeIds,
            'mermaidSourceId',
          ),
        ),
      );
    }

    return ImportedNestedDocument(nodes: importedNodes, edges: importedEdges);
  }

  static NodePayload _remapPayload(
    NodePayload payload,
    Map<String, String> nodeIdMap,
    Set<String> sourceNodeIds,
    Map<String, String> edgeIdMap,
    Set<String> sourceEdgeIds,
    Set<String> validExistingNodeIds,
  ) {
    if (payload is GroupPayload) {
      final childNodeIds = payload.childNodeIds.map((childId) {
        if (!sourceNodeIds.contains(childId)) {
          throw FormatException(
            'childNodeIds references an unknown node: $childId',
          );
        }
        return nodeIdMap[childId]!;
      }).toList();
      return payload.copyWith(childNodeIds: childNodeIds);
    }
    if (payload is MermaidPayload) {
      return payload.copyWith(
        nativeNodeIds: payload.nativeNodeIds
            .map((id) => nodeIdMap[id]!)
            .toList(growable: false),
        nativeEdgeIds: payload.nativeEdgeIds
            .map((id) => edgeIdMap[id]!)
            .toList(growable: false),
        hotspotTargetFrameId: _remapOptionalIdAllowingExisting(
          payload.hotspotTargetFrameId,
          nodeIdMap,
          sourceNodeIds,
          validExistingNodeIds,
          'hotspotTargetFrameId',
        ),
      );
    }
    if (payload is TextPayload) {
      return payload.copyWith(
        textPathNodeId: _remapOptionalIdAllowingExisting(
          payload.textPathNodeId,
          nodeIdMap,
          sourceNodeIds,
          validExistingNodeIds,
          'textPathNodeId',
        ),
      );
    }
    if (payload is VectorPathPayload) {
      return payload.copyWith(
        maskNodeId: _remapOptionalIdAllowingExisting(
          payload.maskNodeId,
          nodeIdMap,
          sourceNodeIds,
          validExistingNodeIds,
          'maskNodeId',
        ),
      );
    }
    if (payload is NestedBoardPayload) {
      return _remapNestedBoardPayload(payload);
    }
    return payload.clone();
  }

  static void _validateRawMermaidIdLists(
    List<dynamic> rawNodes, {
    required List<dynamic> rawEdges,
  }) {
    final nodeIds = <String>{};
    final edgeIds = <String>{};
    for (final rawNode in rawNodes) {
      if (rawNode is Map<String, dynamic> && rawNode['id'] is String) {
        nodeIds.add(rawNode['id'] as String);
      }
    }
    for (final rawEdge in rawEdges) {
      if (rawEdge is Map && rawEdge['id'] is String) {
        edgeIds.add(rawEdge['id'] as String);
      }
    }

    for (final rawNode in rawNodes) {
      if (rawNode is! Map<String, dynamic>) continue;
      final rawPayload = rawNode['payload'];
      if (rawPayload is! Map || rawNode['type'] != NodeType.nestedBoard.name) {
        continue;
      }
      final nestedNodes = rawPayload['subNodes'];
      final nestedEdges = rawPayload['subEdges'];
      if (nestedNodes is List) {
        _validateRawMermaidIdLists(
          nestedNodes,
          rawEdges: nestedEdges is List ? nestedEdges : const [],
        );
      }
    }

    for (final rawNode in rawNodes) {
      if (rawNode is! Map<String, dynamic> ||
          rawNode['type'] != NodeType.mermaid.name) {
        continue;
      }
      final rawPayload = rawNode['payload'];
      if (rawPayload is! Map) continue;
      for (final field in const ['nativeNodeIds', 'nativeEdgeIds']) {
        final ids = rawPayload[field];
        if (ids == null) continue;
        if (ids is! List) {
          throw FormatException('Mermaid $field must be an array.');
        }
        final seen = <String>{};
        for (final id in ids) {
          if (id is! String || !seen.add(id)) {
            throw FormatException(
              'Mermaid $field must contain unique strings.',
            );
          }
          final validIds = field == 'nativeNodeIds' ? nodeIds : edgeIds;
          if (!validIds.contains(id)) {
            throw FormatException('Mermaid $field references unknown ID: $id');
          }
        }
      }
    }
  }

  static void _validateRawGroupChildReferences(List<dynamic> rawNodes) {
    final nodeIds = <String>{};
    for (final rawNode in rawNodes) {
      if (rawNode is! Map<String, dynamic>) continue;
      final id = rawNode['id'];
      if (id is String) nodeIds.add(id);
    }

    for (final rawNode in rawNodes) {
      if (rawNode is! Map<String, dynamic>) continue;
      final payload = rawNode['payload'];
      if (rawNode['type'] == NodeType.group.name && payload is Map) {
        final rawChildren = payload['childNodeIds'];
        if (rawChildren != null && rawChildren is! List) {
          throw const FormatException('Group childNodeIds must be an array.');
        }
        final childIds = <String>{};
        for (final rawChildId in rawChildren as List? ?? const []) {
          if (rawChildId is! String) {
            throw const FormatException(
              'Every group child ID must be a string.',
            );
          }
          if (!childIds.add(rawChildId)) {
            throw FormatException('Duplicate group child ID: $rawChildId');
          }
          if (!nodeIds.contains(rawChildId)) {
            throw FormatException(
              'childNodeIds references an unknown node: $rawChildId',
            );
          }
        }
      }
      if (rawNode['type'] != NodeType.nestedBoard.name || payload is! Map) {
        continue;
      }
      final rawSubNodes = payload['subNodes'];
      if (rawSubNodes == null) continue;
      if (rawSubNodes is! List) {
        throw const FormatException('Nested subNodes must be an array.');
      }
      _validateRawGroupChildReferences(rawSubNodes);
    }
  }

  static NestedBoardPayload _remapNestedBoardPayload(
    NestedBoardPayload payload,
  ) {
    final sourceNodeIds = <String>{};
    for (final node in payload.subNodes) {
      if (!sourceNodeIds.add(node.id)) {
        throw FormatException('Duplicate nested node ID: ${node.id}');
      }
    }
    final sourceEdgeIds = <String>{};
    for (final edge in payload.subEdges) {
      if (!sourceEdgeIds.add(edge.id)) {
        throw FormatException('Duplicate nested edge ID: ${edge.id}');
      }
    }

    final usedNodeIds = <String>{};
    final nodeIdMap = <String, String>{};
    for (final node in payload.subNodes) {
      final newId = _uniqueId(usedNodeIds);
      usedNodeIds.add(newId);
      nodeIdMap[node.id] = newId;
    }
    final importedMermaidNodes = <String>{};
    final nodeOwners = <String, String>{};
    for (final node in payload.subNodes) {
      final nodePayload = node.payload;
      if (nodePayload is! MermaidPayload) continue;
      for (final nativeNodeId in nodePayload.nativeNodeIds) {
        if (!sourceNodeIds.contains(nativeNodeId) ||
            !importedMermaidNodes.add(nativeNodeId)) {
          throw FormatException(
            'nested nativeNodeIds must reference unique imported nodes: $nativeNodeId',
          );
        }
        final nativeNode = payload.subNodes.firstWhere(
          (candidate) => candidate.id == nativeNodeId,
        );
        if (nativeNode.mermaidSourceId != null &&
            nativeNode.mermaidSourceId != node.id) {
          throw FormatException(
            'nested nativeNodeIds contains a node owned by another Mermaid node: $nativeNodeId',
          );
        }
        nodeOwners[nativeNodeId] = node.id;
      }
    }
    for (final node in payload.subNodes) {
      final ownerId = nodeOwners[node.id] ?? node.mermaidSourceId;
      if (ownerId != null && nodeIdMap.containsKey(ownerId)) {
        nodeIdMap[node.id] = _remapOwnedMermaidId(
          id: node.id,
          ownerId: ownerId,
          idMap: nodeIdMap,
          ownerIdMap: nodeIdMap,
          kind: 'node',
          occupiedIds: _idOccupancyMap(nodeIdMap, const {}),
        );
      }
    }

    final usedEdgeIds = <String>{};
    final edgeIdMap = <String, String>{};
    for (final edge in payload.subEdges) {
      final newId = _uniqueId(usedEdgeIds);
      usedEdgeIds.add(newId);
      edgeIdMap[edge.id] = newId;
    }
    final importedMermaidEdges = <String>{};
    final edgeOwners = <String, String>{};
    for (final node in payload.subNodes) {
      final nodePayload = node.payload;
      if (nodePayload is! MermaidPayload) continue;
      for (final nativeEdgeId in nodePayload.nativeEdgeIds) {
        if (!sourceEdgeIds.contains(nativeEdgeId) ||
            !importedMermaidEdges.add(nativeEdgeId)) {
          throw FormatException(
            'nested nativeEdgeIds must reference unique imported edges: $nativeEdgeId',
          );
        }
        final nativeEdge = payload.subEdges.firstWhere(
          (candidate) => candidate.id == nativeEdgeId,
        );
        if (nativeEdge.mermaidSourceId != null &&
            nativeEdge.mermaidSourceId != node.id) {
          throw FormatException(
            'nested nativeEdgeIds contains an edge owned by another Mermaid node: $nativeEdgeId',
          );
        }
        edgeOwners[nativeEdgeId] = node.id;
      }
    }
    for (final edge in payload.subEdges) {
      final ownerId = edgeOwners[edge.id] ?? edge.mermaidSourceId;
      if (ownerId != null && nodeIdMap.containsKey(ownerId)) {
        edgeIdMap[edge.id] = _remapOwnedMermaidId(
          id: edge.id,
          ownerId: ownerId,
          idMap: edgeIdMap,
          ownerIdMap: nodeIdMap,
          kind: 'edge',
          occupiedIds: _idOccupancyMap(edgeIdMap, const {}),
        );
      }
    }
    _validateRemappedMermaidIds(
      nodeIdMap: nodeIdMap,
      edgeIdMap: edgeIdMap,
      existingNodeIds: const {},
      existingEdgeIds: const {},
    );

    final importedNodes = payload.subNodes
        .map((node) {
          final parentId = _remapOptionalId(
            node.parentId,
            nodeIdMap,
            sourceNodeIds,
            'nested parentId',
          );
          final variantOfNodeId = _remapOptionalId(
            node.variantOfNodeId,
            nodeIdMap,
            sourceNodeIds,
            'nested variantOfNodeId',
          );
          return node.copyWith(
            id: nodeIdMap[node.id],
            parentId: parentId,
            variantOfNodeId: variantOfNodeId,
            mermaidSourceId: _remapOptionalId(
              node.mermaidSourceId,
              nodeIdMap,
              sourceNodeIds,
              'nested mermaidSourceId',
            ),
            prototypeInteractions: _remapPrototypeInteractions(
              node.prototypeInteractions,
              nodeIdMap,
              sourceNodeIds,
            ),
            payload: _remapPayload(
              node.payload,
              nodeIdMap,
              sourceNodeIds,
              edgeIdMap,
              sourceEdgeIds,
              const {},
            ),
          );
        })
        .toList(growable: false);

    final importedEdges = payload.subEdges
        .map((edge) {
          final sourceId = _remapScopedEndpointId(
            edge.sourceNodeId,
            nodeIdMap,
            sourceNodeIds,
            'nested sourceNodeId',
          );
          final targetId = _remapScopedEndpointId(
            edge.targetNodeId,
            nodeIdMap,
            sourceNodeIds,
            'nested targetNodeId',
          );
          final parentId = _remapScopedEndpointId(
            edge.parentId,
            nodeIdMap,
            sourceNodeIds,
            'nested parentId',
          );
          return edge.copyWith(
            id: edgeIdMap[edge.id],
            sourceNodeId: sourceId,
            targetNodeId: targetId,
            parentId: parentId,
            mermaidSourceId: _remapOptionalId(
              edge.mermaidSourceId,
              nodeIdMap,
              sourceNodeIds,
              'nested edge mermaidSourceId',
            ),
          );
        })
        .toList(growable: false);

    final sourceCanvasId = payload.subCanvasId.trim();
    return payload.copyWith(
      subCanvasId: sourceCanvasId.isEmpty
          ? sourceCanvasId
          : 'nested-${const Uuid().v4()}',
      subNodes: importedNodes,
      subEdges: importedEdges,
    );
  }

  static List<PrototypeInteraction> _remapPrototypeInteractions(
    List<PrototypeInteraction> interactions,
    Map<String, String> nodeIdMap,
    Set<String> sourceNodeIds, [
    Set<String> validExistingNodeIds = const {},
  ]) => interactions
      .map(
        (interaction) => interaction.copyWith(
          targetFrameId: _remapOptionalIdAllowingExisting(
            interaction.targetFrameId,
            nodeIdMap,
            sourceNodeIds,
            validExistingNodeIds,
            'prototype targetFrameId',
          ),
          targetNodeId: _remapOptionalIdAllowingExisting(
            interaction.targetNodeId,
            nodeIdMap,
            sourceNodeIds,
            validExistingNodeIds,
            'prototype targetNodeId',
          ),
        ),
      )
      .toList(growable: false);

  static String? _remapScopedEndpointId(
    String? sourceId,
    Map<String, String> nodeIdMap,
    Set<String> sourceIds,
    String field,
  ) {
    if (sourceId == null) return null;
    if (!sourceIds.contains(sourceId)) {
      throw FormatException('$field references an unknown node: $sourceId');
    }
    return nodeIdMap[sourceId];
  }

  static String? _remapOptionalId(
    String? sourceId,
    Map<String, String> nodeIdMap,
    Set<String> sourceIds,
    String field,
  ) {
    if (sourceId == null) return null;
    if (!sourceIds.contains(sourceId)) {
      throw FormatException('$field references an unknown node: $sourceId');
    }
    return nodeIdMap[sourceId];
  }

  static String? _remapOptionalIdAllowingExisting(
    String? sourceId,
    Map<String, String> nodeIdMap,
    Set<String> sourceIds,
    Set<String> validExistingIds,
    String field,
  ) {
    if (sourceId == null) return null;
    return _remapRequiredId(
      sourceId,
      nodeIdMap,
      sourceIds,
      validExistingIds,
      field,
    );
  }

  static String _remapRequiredId(
    String sourceId,
    Map<String, String> idMap,
    Set<String> sourceIds,
    Set<String> validExistingIds,
    String field,
  ) {
    final remapped = idMap[sourceId];
    if (remapped != null) return remapped;
    if (sourceIds.contains(sourceId)) {
      throw FormatException('$field could not be remapped: $sourceId');
    }
    if (validExistingIds.contains(sourceId)) return sourceId;
    throw FormatException('$field references an unknown ID: $sourceId');
  }

  static String? _remapEndpointId(
    String? sourceId,
    Map<String, String> nodeIdMap,
    Set<String> validIds,
    String field,
  ) {
    if (sourceId == null) return null;
    return _remapRequiredId(
      sourceId,
      nodeIdMap,
      nodeIdMap.keys.toSet(),
      validIds,
      field,
    );
  }

  static Map<String, String> _idOccupancyMap(
    Map<String, String> idMap,
    Set<String> existingIds,
  ) {
    final occupied = <String, String>{
      for (final id in existingIds) id: id,
      for (final id in idMap.keys) id: id,
      for (final entry in idMap.entries) entry.value: entry.key,
    };
    return occupied;
  }

  static void _validateRemappedMermaidIds({
    required Map<String, String> nodeIdMap,
    required Map<String, String> edgeIdMap,
    required Set<String> existingNodeIds,
    required Set<String> existingEdgeIds,
  }) {
    final nodeIds = Set<String>.from(existingNodeIds);
    for (final id in nodeIdMap.values) {
      if (!nodeIds.add(id)) {
        throw FormatException('Duplicate remapped node ID: $id');
      }
    }
    final edgeIds = Set<String>.from(existingEdgeIds);
    for (final id in edgeIdMap.values) {
      if (!edgeIds.add(id)) {
        throw FormatException('Duplicate remapped edge ID: $id');
      }
    }
  }

  static String _remapOwnedMermaidId({
    required String id,
    required String ownerId,
    required Map<String, String> idMap,
    required Map<String, String> ownerIdMap,
    required String kind,
    required Map<String, String> occupiedIds,
  }) {
    final prefix = '${ownerId}__mermaid_${kind}_';
    if (!id.startsWith(prefix)) return idMap[id] ?? id;
    final suffix = id.substring(prefix.length);
    if (int.tryParse(suffix) == null) return idMap[id] ?? id;
    final remappedOwnerId = ownerIdMap[ownerId];
    if (remappedOwnerId == null) return idMap[id] ?? id;
    final remappedId = '${remappedOwnerId}__mermaid_${kind}_$suffix';
    final occupyingSourceId = occupiedIds[remappedId];
    if (occupyingSourceId != null && occupyingSourceId != id) {
      throw FormatException('Remapped Mermaid ID conflicts: $remappedId');
    }
    return remappedId;
  }

  static String _uniqueId(Set<String> used) {
    var id = const Uuid().v4();
    while (used.contains(id)) {
      id = const Uuid().v4();
    }
    return id;
  }
}

class NestedBoardEditorHost extends StatefulWidget {
  final CanvasNode node;
  final ValueChanged<CanvasNode> onSave;

  const NestedBoardEditorHost({
    required this.node,
    required this.onSave,
    super.key,
  });

  @override
  State<NestedBoardEditorHost> createState() => _NestedBoardEditorHostState();
}

class _NestedBoardEditorHostState extends State<NestedBoardEditorHost> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final CanvasEditorPanelController _panelController;
  late NestedBoardPayload _payload;
  late final List<Override> _localOverrides;

  @override
  void initState() {
    super.initState();
    _payload = widget.node.payload is NestedBoardPayload
        ? (widget.node.payload as NestedBoardPayload).clone()
        : NestedBoardPayload();
    _titleController = TextEditingController(text: _payload.boardName);
    _descriptionController = TextEditingController(text: _payload.description);
    _panelController = CanvasEditorPanelController(
      initialShowLayers: true,
      initialShowInspector: true,
    );

    final initialNodes = _payload.subNodes
        .map((node) => node.copyWith(payload: node.payload.clone()))
        .toList();
    final initialEdges = _payload.subEdges
        .map((edge) => edge.copyWith())
        .toList();

    _localOverrides = [
      documentNodesProvider.overrideWith(
        (ref) => DocumentNodesNotifier(ref, initialNodes: initialNodes),
      ),
      documentEdgesProvider.overrideWith((ref) {
        final notifier = DocumentEdgesNotifier();
        notifier.setEdges(initialEdges);
        return notifier;
      }),
      selectionProvider.overrideWith((ref) => SelectionNotifier()),
      viewportProvider.overrideWith((ref) => ViewportNotifier()),
      activeToolProvider.overrideWith((ref) => ActiveToolNotifier()),
      activeBrushConfigProvider.overrideWith(
        (ref) => ActiveBrushConfigNotifier(),
      ),
      historyProvider.overrideWith((ref) => HistoryNotifier()),
      boardHistoryProvider.overrideWith((ref) => BoardHistoryNotifier()),
      nodeHistoryProvider.overrideWith((ref) => NodeHistoryNotifier()),
      commentsProvider.overrideWith((ref) => CommentsNotifier()),
      remoteCursorsProvider.overrideWith((ref) => RemoteCursorsNotifier()),
      linkPreviewControllerProvider.overrideWith(
        (ref) => LinkPreviewController(ref),
      ),
    ];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _panelController.dispose();
    super.dispose();
  }

  String get _surfaceProjectId => _payload.subCanvasId.trim().isEmpty
      ? 'nested-${widget.node.id}'
      : _payload.subCanvasId;

  void _syncMetadata() {
    final boardName = _titleController.text.trim().isEmpty
        ? 'Nested Board'
        : _titleController.text.trim();
    _payload = _payload.copyWith(
      boardName: boardName,
      description: _descriptionController.text.trim(),
      childNodeCount: _payload.subNodes.length,
    );
    widget.onSave(widget.node.copyWith(name: boardName, payload: _payload));
    if (mounted) setState(() {});
  }

  void _syncChildDocument(List<CanvasNode> nodes, List<CanvasEdge> edges) {
    final clonedNodes = nodes
        .map((node) => node.copyWith(payload: node.payload.clone()))
        .toList();
    final clonedEdges = edges.map((edge) => edge.copyWith()).toList();
    _payload = _payload.copyWith(
      subNodes: clonedNodes,
      subEdges: clonedEdges,
      childNodeCount: clonedNodes.length,
    );
    widget.onSave(
      widget.node.copyWith(name: _payload.boardName, payload: _payload),
    );
  }

  void _close() => Navigator.of(context).pop();

  void _copyJson() {
    final json = const JsonEncoder.withIndent('  ').convert({
      'boardName': _payload.boardName,
      'description': _payload.description,
      'tags': _payload.tags,
      'nodes': _payload.subNodes.map((node) => node.toJson()).toList(),
      'edges': _payload.subEdges.map((edge) => edge.toJson()).toList(),
    });
    Clipboard.setData(ClipboardData(text: json));
    showUiToast(
      context,
      'Nested board JSON copied to clipboard.',
      variant: UiToastVariant.success,
    );
  }

  Future<void> _importJson(WidgetRef ref) => showUiDialog<void>(
    context: context,
    builder: (dialogContext) => _NestedJsonImportDialog(
      onCancel: () => Navigator.pop(dialogContext),
      onImport: (source) => _applyImportedJson(dialogContext, ref, source),
    ),
  );

  void _applyImportedJson(
    BuildContext dialogContext,
    WidgetRef ref,
    String source,
  ) {
    try {
      final decoded = jsonDecode(source.trim());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('The root value must be a JSON object.');
      }
      const unsupportedAssetFields = {
        'assets',
        'assetManifest',
        'assetBytes',
        'transientAssetBytes',
        'transientPayloadBytes',
      };
      final unsupportedField = decoded.keys
          .map((key) => key.toString())
          .firstWhere(unsupportedAssetFields.contains, orElse: () => '');
      if (unsupportedField.isNotEmpty) {
        throw const FormatException(
          'Nested asset-bearing imports require the project import flow.',
        );
      }

      final imported = NestedDocumentCodec.parse(
        source,
        existingNodeIds: _payload.subNodes.map((node) => node.id),
        existingEdgeIds: _payload.subEdges.map((edge) => edge.id),
      );
      final dependencies = collectDocumentAssetDependencies(imported.nodes);
      if (dependencies.dependencies.isNotEmpty) {
        throw const FormatException(
          'Nested asset-bearing imports require the project import flow.',
        );
      }
      _payload = _payload.copyWith(
        boardName: decoded['boardName'] as String? ?? _payload.boardName,
        description: decoded['description'] as String? ?? _payload.description,
        subNodes: [..._payload.subNodes, ...imported.nodes],
        subEdges: [..._payload.subEdges, ...imported.edges],
        tags: _readTags(decoded['tags']) ?? _payload.tags,
      );
      final currentNodes = ref.read(documentNodesProvider);
      final currentEdges = ref.read(documentEdgesProvider);
      ref.read(documentNodesProvider.notifier).setNodes([
        ...currentNodes,
        ...imported.nodes,
      ]);
      ref.read(documentEdgesProvider.notifier).setEdges([
        ...currentEdges,
        ...imported.edges,
      ]);
      _titleController.text = _payload.boardName;
      _descriptionController.text = _payload.description;
      widget.onSave(
        widget.node.copyWith(name: _payload.boardName, payload: _payload),
      );
      if (mounted) setState(() {});
      Navigator.pop(dialogContext);
      showUiToast(
        context,
        'Imported ${imported.nodes.length} items and ${imported.edges.length} edges.',
        variant: UiToastVariant.success,
      );
    } catch (error) {
      showUiToast(
        context,
        'Import failed: $error',
        variant: UiToastVariant.error,
      );
    }
  }

  List<String>? _readTags(Object? rawTags) {
    if (rawTags == null) return null;
    if (rawTags is! List<dynamic>) {
      throw const FormatException('The tags value must be an array.');
    }
    return rawTags
        .map((tag) {
          if (tag is! String) {
            throw const FormatException('Every tag must be a string.');
          }
          return tag.trim();
        })
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _showBoardSettings() => showUiDialog<void>(
    context: context,
    builder: (dialogContext) => _NestedBoardSettingsDialog(
      initialTags: _payload.tags,
      onSave: (tags) {
        _payload = _payload.copyWith(tags: tags);
        widget.onSave(
          widget.node.copyWith(name: _payload.boardName, payload: _payload),
        );
        if (mounted) setState(() {});
        Navigator.pop(dialogContext);
      },
    ),
  );

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: _localOverrides,
    child: _NestedBoardEditorContent(
      payload: _payload,
      titleController: _titleController,
      panelController: _panelController,
      surfaceProjectId: _surfaceProjectId,
      onMetadataChanged: _syncMetadata,
      onChildDocumentChanged: _syncChildDocument,
      onClose: _close,
      onImport: _importJson,
      onCopy: _copyJson,
      onSettings: _showBoardSettings,
    ),
  );
}

class _NestedJsonImportDialog extends StatefulWidget {
  final VoidCallback onCancel;
  final ValueChanged<String> onImport;

  const _NestedJsonImportDialog({
    required this.onCancel,
    required this.onImport,
  });

  @override
  State<_NestedJsonImportDialog> createState() =>
      _NestedJsonImportDialogState();
}

class _NestedJsonImportDialogState extends State<_NestedJsonImportDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiDialog(
    constraints: AppResponsive.dialogConstraints(
      context,
      maxWidth: 520,
      maxHeight: 560,
    ),
    builder: (context, style) => SizedBox(
      width: AppResponsive.dialogWidth(context, preferred: 520),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: AppResponsive.dialogHeight(context, preferred: 560),
        ),
        child: SingleChildScrollView(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Import Sub-Board JSON', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              UiTextField(
                controller: _controller,
                minLines: 8,
                maxLines: 8,
                hint: 'Paste Canvas / Nested Board JSON here...',
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    onPressed: widget.onCancel,
                    variant: UiButtonVariant.ghost,
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    onPressed: () => widget.onImport(_controller.text),
                    child: const Text('Import'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NestedBoardSettingsDialog extends StatefulWidget {
  final List<String> initialTags;
  final ValueChanged<List<String>> onSave;

  const _NestedBoardSettingsDialog({
    required this.initialTags,
    required this.onSave,
  });

  @override
  State<_NestedBoardSettingsDialog> createState() =>
      _NestedBoardSettingsDialogState();
}

class _NestedBoardSettingsDialogState
    extends State<_NestedBoardSettingsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTags.join(', '));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final tags = _controller.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    widget.onSave(tags);
  }

  @override
  Widget build(BuildContext context) => UiDialog(
    constraints: AppResponsive.dialogConstraints(
      context,
      maxWidth: 420,
      maxHeight: 360,
    ),
    builder: (context, style) => SizedBox(
      width: AppResponsive.dialogWidth(context, preferred: 420),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: AppResponsive.dialogHeight(context, preferred: 360),
        ),
        child: SingleChildScrollView(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nested Board Settings', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              UiTextField(
                controller: _controller,
                label: 'Tags',
                hint: 'Design, Sprint, Product',
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  onPressed: _save,
                  child: const Text('Save Settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NestedBoardEditorContent extends ConsumerStatefulWidget {
  final NestedBoardPayload payload;
  final TextEditingController titleController;
  final CanvasEditorPanelController panelController;
  final String surfaceProjectId;
  final VoidCallback onMetadataChanged;
  final void Function(List<CanvasNode>, List<CanvasEdge>)
  onChildDocumentChanged;
  final VoidCallback onClose;
  final Future<void> Function(WidgetRef) onImport;
  final VoidCallback onCopy;
  final VoidCallback onSettings;

  const _NestedBoardEditorContent({
    required this.payload,
    required this.titleController,
    required this.panelController,
    required this.surfaceProjectId,
    required this.onMetadataChanged,
    required this.onChildDocumentChanged,
    required this.onClose,
    required this.onImport,
    required this.onCopy,
    required this.onSettings,
  });

  @override
  ConsumerState<_NestedBoardEditorContent> createState() =>
      _NestedBoardEditorContentState();
}

class _NestedBoardEditorContentState
    extends ConsumerState<_NestedBoardEditorContent> {
  ProviderSubscription<List<CanvasNode>>? _nodesSubscription;
  ProviderSubscription<List<CanvasEdge>>? _edgesSubscription;

  @override
  void initState() {
    super.initState();
    widget.panelController.addListener(_onPanelControllerChanged);
    _nodesSubscription = ref.listenManual<List<CanvasNode>>(
      documentNodesProvider,
      (_, nodes) => _emitDocument(nodes, ref.read(documentEdgesProvider)),
    );
    _edgesSubscription = ref.listenManual<List<CanvasEdge>>(
      documentEdgesProvider,
      (_, edges) => _emitDocument(ref.read(documentNodesProvider), edges),
    );
  }

  @override
  void dispose() {
    widget.panelController.removeListener(_onPanelControllerChanged);
    _nodesSubscription?.close();
    _edgesSubscription?.close();
    super.dispose();
  }

  void _onPanelControllerChanged() {
    if (mounted) setState(() {});
  }

  void _emitDocument(List<CanvasNode> nodes, List<CanvasEdge> edges) {
    widget.onChildDocumentChanged(nodes, edges);
  }

  Widget _buildTopBar(BuildContext context) {
    final tokens = context.appTokens;
    final panelPreferences = ref.watch(canvasPanelPreferencesProvider);
    return UiSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md - AppSpacing.xxs,
        vertical: AppSpacing.xs + AppSpacing.xxs,
      ),
      color: tokens.panel,
      borderRadius: BorderRadius.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleWidth = constraints.maxWidth < 480
              ? (constraints.maxWidth - 20).clamp(180.0, 280.0)
              : 280.0;
          return Wrap(
            spacing: AppSpacing.xs + AppSpacing.xxs,
            runSpacing: AppSpacing.xs + AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              UiIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Return to Main Canvas',
                onPressed: widget.onClose,
              ),
              SizedBox(
                width: titleWidth,
                child: Semantics(
                  textField: true,
                  label: 'Nested board title',
                  child: UiTextField(
                    controller: widget.titleController,
                    label: 'Board title',
                    hint: 'Board name',
                    onChanged: (_) => widget.onMetadataChanged(),
                  ),
                ),
              ),
              if (panelPreferences.showLayersButton)
                UiIconButton(
                  key: const ValueKey('nested-toggle-object-tree'),
                  icon: Icons.layers_outlined,
                  iconWidget: SidebarPanelToggleIcon(
                    side: SidebarPanelSide.left,
                    expanded: widget.panelController.showLayers,
                  ),
                  tooltip: widget.panelController.showLayers
                      ? 'Hide Object Tree'
                      : 'Show Object Tree',
                  selected: widget.panelController.showLayers,
                  onPressed: widget.panelController.toggleLayers,
                ),
              if (panelPreferences.showInspectorButton)
                UiIconButton(
                  key: const ValueKey('nested-toggle-inspector'),
                  icon: Icons.tune_outlined,
                  iconWidget: SidebarPanelToggleIcon(
                    side: SidebarPanelSide.right,
                    expanded: widget.panelController.showInspector,
                  ),
                  tooltip: widget.panelController.showInspector
                      ? 'Hide Inspector'
                      : 'Show Inspector',
                  selected: widget.panelController.showInspector,
                  onPressed: widget.panelController.toggleInspector,
                ),
              UiButton(
                onPressed: widget.onSettings,
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.tune, size: 14),
                child: Text('Tags (${widget.payload.tags.length})'),
              ),
              UiButton(
                onPressed: () => widget.onImport(ref),
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.download_rounded, size: 14),
                child: const Text('Import JSON'),
              ),
              UiButton(
                onPressed: widget.onCopy,
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.copy_rounded, size: 14),
                child: const Text('Copy JSON'),
              ),
              UiButton(
                onPressed: widget.onClose,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.check, size: 14),
                child: const Text('Save & Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: CanvasEditorSurface(
            projectId: widget.surfaceProjectId,
            projectName: widget.payload.boardName,
            services: CanvasEditorServices.embedded,
            panelController: widget.panelController,
          ),
        ),
      ],
    ),
  );
}
