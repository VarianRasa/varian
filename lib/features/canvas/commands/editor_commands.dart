import 'dart:ui';

import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';

abstract class EditorCommand {
  String get name;
  List<CanvasNode> execute(List<CanvasNode> currentNodes);
  List<CanvasNode> undo(List<CanvasNode> currentNodes);

  List<CanvasEdge> executeEdges(List<CanvasEdge> currentEdges) => currentEdges;

  List<CanvasEdge> undoEdges(List<CanvasEdge> currentEdges) => currentEdges;
}

class CompositeEditorCommand extends EditorCommand {
  final String label;
  final List<EditorCommand> commands;

  CompositeEditorCommand({
    required this.label,
    required List<EditorCommand> commands,
  }) : commands = List<EditorCommand>.unmodifiable(commands);

  @override
  String get name => label;

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    var next = currentNodes;
    for (final command in commands) {
      next = command.execute(next);
    }
    return next;
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    var next = currentNodes;
    for (final command in commands.reversed) {
      next = command.undo(next);
    }
    return next;
  }

  @override
  List<CanvasEdge> executeEdges(List<CanvasEdge> currentEdges) {
    var next = currentEdges;
    for (final command in commands) {
      next = command.executeEdges(next);
    }
    return next;
  }

  @override
  List<CanvasEdge> undoEdges(List<CanvasEdge> currentEdges) {
    var next = currentEdges;
    for (final command in commands.reversed) {
      next = command.undoEdges(next);
    }
    return next;
  }
}

class CreateNodeCommand extends EditorCommand {
  final CanvasNode node;

  CreateNodeCommand(this.node);

  @override
  String get name => 'Create Node';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    return [...currentNodes, node];
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    return currentNodes.where((n) => n.id != node.id).toList();
  }
}

class CreateNodesCommand extends EditorCommand {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;

  CreateNodesCommand({this.nodes = const [], this.edges = const []});

  @override
  String get name => 'Create Node(s)';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    final existingIds = currentNodes.map((node) => node.id).toSet();
    return [
      ...currentNodes,
      ...nodes.where((node) => existingIds.add(node.id)),
    ];
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    final createdIds = nodes.map((node) => node.id).toSet();
    return currentNodes
        .where((node) => !createdIds.contains(node.id))
        .toList(growable: false);
  }

  @override
  List<CanvasEdge> executeEdges(List<CanvasEdge> currentEdges) {
    final existingIds = currentEdges.map((edge) => edge.id).toSet();
    return [
      ...currentEdges,
      ...edges.where((edge) => existingIds.add(edge.id)),
    ];
  }

  @override
  List<CanvasEdge> undoEdges(List<CanvasEdge> currentEdges) {
    final createdIds = edges.map((edge) => edge.id).toSet();
    return currentEdges
        .where((edge) => !createdIds.contains(edge.id))
        .toList(growable: false);
  }
}

class DeleteNodeCommand extends EditorCommand {
  final List<CanvasNode> deletedNodes;
  final List<CanvasEdge> deletedEdges;
  final List<CanvasNode> updatedNodes;
  final List<CanvasNode> originalUpdatedNodes;

  DeleteNodeCommand(
    this.deletedNodes, {
    this.deletedEdges = const [],
    this.updatedNodes = const [],
    this.originalUpdatedNodes = const [],
  }) : assert(updatedNodes.length == originalUpdatedNodes.length);

  @override
  String get name => 'Delete Node(s)';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    final deletedIds = deletedNodes.map((e) => e.id).toSet();
    final updatedById = {
      for (var index = 0; index < updatedNodes.length; index++)
        originalUpdatedNodes[index].id: updatedNodes[index],
    };
    return currentNodes
        .where((node) => !deletedIds.contains(node.id))
        .map((node) => updatedById[node.id] ?? node)
        .toList();
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    final originalById = {
      for (var index = 0; index < originalUpdatedNodes.length; index++)
        updatedNodes[index].id: originalUpdatedNodes[index],
    };
    final restored = currentNodes
        .map((node) => originalById[node.id] ?? node)
        .toList();
    final existingIds = restored.map((node) => node.id).toSet();
    return [
      ...restored,
      ...deletedNodes.where((node) => !existingIds.contains(node.id)),
    ];
  }

  @override
  List<CanvasEdge> executeEdges(List<CanvasEdge> currentEdges) {
    return _removeDeletedEdges(currentEdges, deletedEdges);
  }

  @override
  List<CanvasEdge> undoEdges(List<CanvasEdge> currentEdges) {
    return _restoreDeletedEdges(currentEdges, deletedEdges);
  }
}

class DeleteEdgesCommand extends EditorCommand {
  final List<CanvasEdge> deletedEdges;
  final List<CanvasNode> updatedNodes;
  final List<CanvasNode> originalUpdatedNodes;

  DeleteEdgesCommand(
    this.deletedEdges, {
    this.updatedNodes = const [],
    this.originalUpdatedNodes = const [],
  }) : assert(updatedNodes.length == originalUpdatedNodes.length);

  @override
  String get name => 'Delete Connector(s)';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    final updatedById = {
      for (var index = 0; index < updatedNodes.length; index++)
        originalUpdatedNodes[index].id: updatedNodes[index],
    };
    return currentNodes.map((node) => updatedById[node.id] ?? node).toList();
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    final originalById = {
      for (var index = 0; index < originalUpdatedNodes.length; index++)
        updatedNodes[index].id: originalUpdatedNodes[index],
    };
    return currentNodes.map((node) => originalById[node.id] ?? node).toList();
  }

  @override
  List<CanvasEdge> executeEdges(List<CanvasEdge> currentEdges) {
    return _removeDeletedEdges(currentEdges, deletedEdges);
  }

  @override
  List<CanvasEdge> undoEdges(List<CanvasEdge> currentEdges) {
    return _restoreDeletedEdges(currentEdges, deletedEdges);
  }
}

List<CanvasEdge> _removeDeletedEdges(
  List<CanvasEdge> currentEdges,
  List<CanvasEdge> deletedEdges,
) {
  if (deletedEdges.isEmpty) return currentEdges;
  final deletedIds = deletedEdges.map((edge) => edge.id).toSet();
  return currentEdges.where((edge) => !deletedIds.contains(edge.id)).toList();
}

List<CanvasEdge> _restoreDeletedEdges(
  List<CanvasEdge> currentEdges,
  List<CanvasEdge> deletedEdges,
) {
  if (deletedEdges.isEmpty) return currentEdges;
  final existingIds = currentEdges.map((edge) => edge.id).toSet();
  return [
    ...currentEdges,
    ...deletedEdges.where((edge) => !existingIds.contains(edge.id)),
  ];
}

class ReassignParentCommand extends EditorCommand {
  final List<CanvasNode> childrenWithOldParent;
  final List<CanvasNode> childrenWithNewParent;

  ReassignParentCommand({
    required this.childrenWithOldParent,
    required this.childrenWithNewParent,
  });

  @override
  String get name => 'Update Frame Parenting';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    return _apply(currentNodes, childrenWithNewParent);
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    return _apply(currentNodes, childrenWithOldParent);
  }

  List<CanvasNode> _apply(
    List<CanvasNode> currentNodes,
    List<CanvasNode> replacements,
  ) {
    final byId = {for (final n in replacements) n.id: n};
    return currentNodes.map((n) => byId[n.id] ?? n).toList();
  }
}

class MoveNodeCommand extends EditorCommand {
  final List<String> nodeIds;
  final double dx;
  final double dy;

  MoveNodeCommand({required this.nodeIds, required this.dx, required this.dy});

  @override
  String get name => 'Move Node(s)';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    final targetIds = nodeIds.toSet();
    return currentNodes.map((n) {
      if (targetIds.contains(n.id)) {
        return n.copyWith(x: n.x + dx, y: n.y + dy);
      }
      return n;
    }).toList();
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    final targetIds = nodeIds.toSet();
    return currentNodes.map((n) {
      if (targetIds.contains(n.id)) {
        return n.copyWith(x: n.x - dx, y: n.y - dy);
      }
      return n;
    }).toList();
  }

  @override
  List<CanvasEdge> executeEdges(List<CanvasEdge> currentEdges) =>
      _translateAttachedEdgePoints(
        currentEdges,
        nodeIds.toSet(),
        Offset(dx, dy),
      );

  @override
  List<CanvasEdge> undoEdges(List<CanvasEdge> currentEdges) =>
      _translateAttachedEdgePoints(
        currentEdges,
        nodeIds.toSet(),
        Offset(-dx, -dy),
      );
}

List<CanvasEdge> _translateAttachedEdgePoints(
  List<CanvasEdge> edges,
  Set<String> movedNodeIds,
  Offset delta,
) {
  return edges
      .map((edge) {
        final moveSource =
            edge.sourceNodeId != null &&
            movedNodeIds.contains(edge.sourceNodeId);
        final moveTarget =
            edge.targetNodeId != null &&
            movedNodeIds.contains(edge.targetNodeId);
        if (!moveSource && !moveTarget) return edge;

        final moveRoute = moveSource && moveTarget && edge.waypoints.isNotEmpty;
        return edge.copyWith(
          sourcePoint: moveSource && edge.sourcePoint != null
              ? edge.sourcePoint! + delta
              : edge.sourcePoint,
          targetPoint: moveTarget && edge.targetPoint != null
              ? edge.targetPoint! + delta
              : edge.targetPoint,
          waypoints: moveRoute
              ? edge.waypoints
                    .map((point) => point + delta)
                    .toList(growable: false)
              : edge.waypoints,
        );
      })
      .toList(growable: false);
}

class UpdateNodeCommand extends EditorCommand {
  final CanvasNode oldNode;
  final CanvasNode newNode;
  final List<CanvasNode> additionalOldNodes;
  final List<CanvasNode> additionalNewNodes;

  UpdateNodeCommand({
    required this.oldNode,
    required this.newNode,
    this.additionalOldNodes = const [],
    this.additionalNewNodes = const [],
  });

  @override
  String get name => 'Update Node';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    final replacements = {
      oldNode.id: newNode,
      for (var index = 0; index < additionalOldNodes.length; index++)
        additionalOldNodes[index].id: additionalNewNodes[index],
    };
    return currentNodes.map((node) => replacements[node.id] ?? node).toList();
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    final replacements = {
      newNode.id: oldNode,
      for (var index = 0; index < additionalNewNodes.length; index++)
        additionalNewNodes[index].id: additionalOldNodes[index],
    };
    return currentNodes.map((node) => replacements[node.id] ?? node).toList();
  }
}

class ReplaceNodesCommand extends EditorCommand {
  final String label;
  final List<CanvasNode> beforeNodes;
  final List<CanvasNode> afterNodes;
  final List<CanvasEdge> beforeEdges;
  final List<CanvasEdge> afterEdges;

  ReplaceNodesCommand({
    this.label = 'Transform Node(s)',
    required this.beforeNodes,
    required this.afterNodes,
    this.beforeEdges = const [],
    this.afterEdges = const [],
  }) : assert(beforeNodes.length == afterNodes.length);

  @override
  String get name => label;

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) =>
      _replaceNodes(currentNodes, afterNodes);

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) =>
      _replaceNodes(currentNodes, beforeNodes);

  @override
  List<CanvasEdge> executeEdges(List<CanvasEdge> currentEdges) =>
      _replaceEdges(currentEdges, afterEdges);

  @override
  List<CanvasEdge> undoEdges(List<CanvasEdge> currentEdges) =>
      _replaceEdges(currentEdges, beforeEdges);

  List<CanvasNode> _replaceNodes(
    List<CanvasNode> current,
    List<CanvasNode> replacements,
  ) {
    final byId = {for (final node in replacements) node.id: node};
    return current.map((node) => byId[node.id] ?? node).toList(growable: false);
  }

  List<CanvasEdge> _replaceEdges(
    List<CanvasEdge> current,
    List<CanvasEdge> replacements,
  ) {
    if (replacements.isEmpty) return current;
    final ids = replacements.map((edge) => edge.id).toSet();
    final existing = current
        .where((edge) => !ids.contains(edge.id))
        .toList(growable: false);
    return [...existing, ...replacements];
  }
}

class UpdateEdgeCommand extends EditorCommand {
  final CanvasEdge oldEdge;
  final CanvasEdge newEdge;
  final CanvasNode? oldMermaidSource;
  final CanvasNode? newMermaidSource;

  UpdateEdgeCommand({
    required this.oldEdge,
    required this.newEdge,
    this.oldMermaidSource,
    this.newMermaidSource,
  }) : assert(oldEdge.id == newEdge.id),
       assert(
         (oldMermaidSource == null && newMermaidSource == null) ||
             (oldMermaidSource != null && newMermaidSource != null),
       );

  @override
  String get name => 'Update Connector';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) =>
      _replaceMermaidSource(currentNodes, newMermaidSource);

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) =>
      _replaceMermaidSource(currentNodes, oldMermaidSource);

  @override
  List<CanvasEdge> executeEdges(List<CanvasEdge> currentEdges) =>
      _replaceEdge(currentEdges, newEdge);

  @override
  List<CanvasEdge> undoEdges(List<CanvasEdge> currentEdges) =>
      _replaceEdge(currentEdges, oldEdge);

  List<CanvasNode> _replaceMermaidSource(
    List<CanvasNode> currentNodes,
    CanvasNode? replacement,
  ) {
    final source = oldMermaidSource ?? newMermaidSource;
    if (source == null || replacement == null) return currentNodes;
    return currentNodes
        .map((node) => node.id == source.id ? replacement : node)
        .toList();
  }

  List<CanvasEdge> _replaceEdge(
    List<CanvasEdge> currentEdges,
    CanvasEdge replacement,
  ) {
    return currentEdges
        .map((edge) => edge.id == replacement.id ? replacement : edge)
        .toList();
  }
}

/// Replaces the complete Mermaid lifecycle snapshot in one history step.
///
/// The snapshots are taken from the current node and edge stores, so unrelated
/// canvas content remains part of the transaction and is restored exactly by
/// undo/redo.
class MermaidLifecycleCommand extends EditorCommand {
  final String action;
  final List<CanvasNode> beforeNodes;
  final List<CanvasNode> afterNodes;
  final List<CanvasEdge> beforeEdges;
  final List<CanvasEdge> afterEdges;

  MermaidLifecycleCommand({
    required this.action,
    required this.beforeNodes,
    required this.afterNodes,
    required this.beforeEdges,
    required this.afterEdges,
  });

  @override
  String get name => 'Mermaid $action';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) => afterNodes;

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) => beforeNodes;

  @override
  List<CanvasEdge> executeEdges(List<CanvasEdge> currentEdges) => afterEdges;

  @override
  List<CanvasEdge> undoEdges(List<CanvasEdge> currentEdges) => beforeEdges;
}

class ReorderNodeCommand extends EditorCommand {
  final List<CanvasNode> previousOrder;
  final List<CanvasNode> newOrder;

  ReorderNodeCommand({required this.previousOrder, required this.newOrder});

  @override
  String get name => 'Reorder Layers';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) => newOrder;

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) => previousOrder;
}

class AlignNodesCommand extends EditorCommand {
  final List<CanvasNode> previousNodes;
  final List<CanvasNode> alignedNodes;

  AlignNodesCommand({required this.previousNodes, required this.alignedNodes});

  @override
  String get name => 'Align / Distribute';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    final alignedMap = {for (final n in alignedNodes) n.id: n};
    return currentNodes.map((n) => alignedMap[n.id] ?? n).toList();
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    final prevMap = {for (final n in previousNodes) n.id: n};
    return currentNodes.map((n) => prevMap[n.id] ?? n).toList();
  }
}

class GroupNodesCommand extends EditorCommand {
  final CanvasNode groupNode;
  final List<CanvasNode> originalChildren;
  final List<CanvasNode> updatedChildren;

  GroupNodesCommand({
    required this.groupNode,
    required this.originalChildren,
    required this.updatedChildren,
  });

  @override
  String get name => 'Group Selection';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    final updatedMap = {for (final n in updatedChildren) n.id: n};
    final updatedList = currentNodes.map((n) => updatedMap[n.id] ?? n).toList();
    return [...updatedList, groupNode];
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    final origMap = {for (final n in originalChildren) n.id: n};
    return currentNodes
        .where((n) => n.id != groupNode.id)
        .map((n) => origMap[n.id] ?? n)
        .toList();
  }
}

class UngroupNodesCommand extends EditorCommand {
  final CanvasNode groupNode;
  final List<CanvasNode> childrenWithParent;
  final List<CanvasNode> childrenWithoutParent;

  UngroupNodesCommand({
    required this.groupNode,
    required this.childrenWithParent,
    required this.childrenWithoutParent,
  });

  @override
  String get name => 'Ungroup Selection';

  @override
  List<CanvasNode> execute(List<CanvasNode> currentNodes) {
    final updatedMap = {for (final n in childrenWithoutParent) n.id: n};
    return currentNodes
        .where((n) => n.id != groupNode.id)
        .map((n) => updatedMap[n.id] ?? n)
        .toList();
  }

  @override
  List<CanvasNode> undo(List<CanvasNode> currentNodes) {
    final prevMap = {for (final n in childrenWithParent) n.id: n};
    final restoredList = currentNodes.map((n) => prevMap[n.id] ?? n).toList();
    return [...restoredList, groupNode];
  }
}
