import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/utils/align_engine.dart';

void main() {
  group('AlignEngine Tests', () {
    test('calculate bounding box for multi nodes', () {
      final nodeA = CanvasNode(
        id: '1',
        type: NodeType.rectangle,
        x: 10,
        y: 20,
        width: 100,
        height: 50,
        payload: ShapePayload(),
      );
      final nodeB = CanvasNode(
        id: '2',
        type: NodeType.ellipse,
        x: 150,
        y: 40,
        width: 60,
        height: 60,
        payload: ShapePayload(),
      );

      final bounds = AlignEngine.getSelectionBounds([nodeA, nodeB]);
      expect(bounds.left, 10.0);
      expect(bounds.top, 20.0);
      expect(bounds.right, 210.0);
      expect(bounds.bottom, 100.0);
    });

    test('align left aligns all nodes to leftmost X', () {
      final nodeA = CanvasNode(
        id: '1',
        type: NodeType.rectangle,
        x: 10,
        y: 20,
        width: 100,
        height: 50,
        payload: ShapePayload(),
      );
      final nodeB = CanvasNode(
        id: '2',
        type: NodeType.rectangle,
        x: 50,
        y: 100,
        width: 80,
        height: 40,
        payload: ShapePayload(),
      );

      final aligned = AlignEngine.align([nodeA, nodeB], AlignmentType.left);
      expect(aligned[0].x, 10.0);
      expect(aligned[1].x, 10.0);
    });

    test('align top aligns all nodes to topmost Y', () {
      final nodeA = CanvasNode(
        id: '1',
        type: NodeType.rectangle,
        x: 10,
        y: 20,
        width: 100,
        height: 50,
        payload: ShapePayload(),
      );
      final nodeB = CanvasNode(
        id: '2',
        type: NodeType.rectangle,
        x: 50,
        y: 80,
        width: 80,
        height: 40,
        payload: ShapePayload(),
      );

      final aligned = AlignEngine.align([nodeA, nodeB], AlignmentType.top);
      expect(aligned[0].y, 20.0);
      expect(aligned[1].y, 20.0);
    });

    test('distribute horizontal sets equal gap between 3 nodes', () {
      final nodeA = CanvasNode(
        id: '1',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 50,
        height: 50,
        payload: ShapePayload(),
      );
      final nodeB = CanvasNode(
        id: '2',
        type: NodeType.rectangle,
        x: 100,
        y: 0,
        width: 50,
        height: 50,
        payload: ShapePayload(),
      );
      final nodeC = CanvasNode(
        id: '3',
        type: NodeType.rectangle,
        x: 300,
        y: 0,
        width: 50,
        height: 50,
        payload: ShapePayload(),
      );

      final distributed = AlignEngine.distribute([
        nodeA,
        nodeB,
        nodeC,
      ], DistributionType.horizontal);

      expect(distributed[0].x, 0.0);
      expect(distributed[1].x, 150.0);
      expect(distributed[2].x, 300.0);
    });
  });

  group('Grouping and Ungrouping State Tests', () {
    test('grouping and ungrouping updates hierarchy and undo stack', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(documentNodesProvider.notifier);

      final nodeA = CanvasNode(
        id: 'node-1',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );
      final nodeB = CanvasNode(
        id: 'node-2',
        type: NodeType.ellipse,
        x: 150,
        y: 50,
        width: 50,
        height: 50,
        payload: ShapePayload(),
      );

      notifier.addNode(nodeA);
      notifier.addNode(nodeB);

      expect(container.read(documentNodesProvider).length, 2);

      final groupId = notifier.groupNodes(['node-1', 'node-2']);
      expect(groupId, isNotNull);

      final nodesAfterGroup = container.read(documentNodesProvider);
      expect(nodesAfterGroup.length, 3); // 2 children + 1 group

      final groupNode = nodesAfterGroup.firstWhere((n) => n.id == groupId);
      expect(groupNode.type, NodeType.group);
      expect((groupNode.payload as GroupPayload).childNodeIds, [
        'node-1',
        'node-2',
      ]);

      final childA = nodesAfterGroup.firstWhere((n) => n.id == 'node-1');
      expect(childA.parentId, groupId);

      // Test ungroup
      notifier.ungroupNodes(groupId!);
      final nodesAfterUngroup = container.read(documentNodesProvider);
      expect(nodesAfterUngroup.length, 2);
      expect(nodesAfterUngroup.any((n) => n.id == groupId), isFalse);
      expect(
        nodesAfterUngroup.firstWhere((n) => n.id == 'node-1').parentId,
        isNull,
      );

      // Test Undo
      notifier.undo();
      final nodesAfterUndo = container.read(documentNodesProvider);
      expect(nodesAfterUndo.length, 3);
      expect(nodesAfterUndo.any((n) => n.id == groupId), isTrue);
    });

    test('duplicates selected nodes and connectors as one undoable action', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(documentNodesProvider.notifier);
      final source = CanvasNode(
        id: 'duplicate-source',
        type: NodeType.rectangle,
        x: 20,
        y: 30,
        width: 100,
        height: 60,
        payload: ShapePayload(label: 'Source'),
      );
      final target = CanvasNode(
        id: 'duplicate-target',
        type: NodeType.ellipse,
        x: 260,
        y: 30,
        width: 100,
        height: 60,
        payload: ShapePayload(label: 'Target'),
      );
      notifier.addNode(source);
      notifier.addNode(target);
      container.read(documentEdgesProvider.notifier).setEdges([
        const CanvasEdge(
          id: 'duplicate-edge',
          sourceNodeId: 'duplicate-source',
          targetNodeId: 'duplicate-target',
          waypoints: [Offset(180, 60)],
        ),
      ]);
      container.read(historyProvider.notifier).clear();

      final duplicatedBySource = notifier.duplicateNodesWithMap([
        source.id,
        target.id,
      ]);
      final newIds = duplicatedBySource.values.toList(growable: false);

      expect(duplicatedBySource.keys, containsAll([source.id, target.id]));
      expect(newIds, hasLength(2));
      expect(container.read(documentNodesProvider), hasLength(4));
      final duplicatedNodes = container
          .read(documentNodesProvider)
          .where((node) => newIds.contains(node.id))
          .toList();
      expect(duplicatedNodes.map((node) => node.x), [40, 280]);
      expect(container.read(documentEdgesProvider), hasLength(2));
      expect(
        container.read(documentEdgesProvider).last.sourceNodeId,
        newIds.first,
      );
      expect(
        container.read(documentEdgesProvider).last.targetNodeId,
        newIds.last,
      );
      expect(container.read(historyProvider).undoStack, hasLength(1));

      notifier.undo();
      expect(container.read(documentNodesProvider), hasLength(2));
      expect(container.read(documentEdgesProvider), hasLength(1));

      notifier.redo();
      expect(container.read(documentNodesProvider), hasLength(4));
      expect(container.read(documentEdgesProvider), hasLength(2));
    });
  });
}
