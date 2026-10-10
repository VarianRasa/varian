import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/commands/editor_commands.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';

void main() {
  test('UpdateEdgeCommand applies and reverses an edge edit', () {
    const before = CanvasEdge(
      id: 'edge-1',
      sourcePoint: Offset(10, 20),
      targetPoint: Offset(100, 120),
    );
    const after = CanvasEdge(
      id: 'edge-1',
      sourcePoint: Offset(20, 30),
      targetPoint: Offset(100, 120),
      waypoints: [Offset(60, 30)],
    );
    final command = UpdateEdgeCommand(oldEdge: before, newEdge: after);

    expect(command.executeEdges([before]), [after]);
    expect(command.undoEdges([after]), [before]);
  });

  test(
    'moving imported Mermaid nodes translates attached endpoints and routes',
    () {
      const edge = CanvasEdge(
        id: 'edge-1',
        sourceNodeId: 'source',
        targetNodeId: 'target',
        sourcePoint: Offset(10, 20),
        targetPoint: Offset(100, 120),
        waypoints: [Offset(50, 60)],
      );
      final command = MoveNodeCommand(
        nodeIds: const ['source', 'target'],
        dx: 7,
        dy: -3,
      );
      final moved = command.executeEdges([edge]).single;
      expect(moved.sourcePoint, const Offset(17, 17));
      expect(moved.targetPoint, const Offset(107, 117));
      expect(moved.waypoints, [const Offset(57, 57)]);
      final undone = command.undoEdges([moved]).single;
      expect(undone.sourcePoint, edge.sourcePoint);
      expect(undone.targetPoint, edge.targetPoint);
      expect(undone.waypoints, edge.waypoints);

      final sourceOnly = MoveNodeCommand(
        nodeIds: const ['source'],
        dx: 7,
        dy: -3,
      ).executeEdges([edge]).single;
      expect(sourceOnly.sourcePoint, const Offset(17, 17));
      expect(sourceOnly.targetPoint, edge.targetPoint);
      expect(sourceOnly.waypoints, edge.waypoints);
    },
  );

  test('edge edits create one history step and mark native Mermaid edited', () {
    final source = CanvasNode(
      id: 'mermaid-source',
      type: NodeType.mermaid,
      x: 0,
      y: 0,
      width: 300,
      height: 200,
      payload: MermaidPayload(
        source: 'flowchart LR\n  A --> B',
        renderMode: MermaidRenderMode.native,
        conversionStatus: MermaidConversionStatus.converted,
        nativeEdgeIds: ['edge-1'],
      ),
    );
    const before = CanvasEdge(
      id: 'edge-1',
      sourceNodeId: 'native-a',
      targetNodeId: 'native-b',
      mermaidSourceId: 'mermaid-source',
    );
    final after = before.copyWith(
      sourceNodeId: null,
      sourcePoint: const Offset(24, 48),
      waypoints: const [Offset(80, 48)],
    );
    final container = ProviderContainer(
      overrides: [
        documentNodesProvider.overrideWith(
          (ref) => DocumentNodesNotifier(ref, initialNodes: [source]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(documentEdgesProvider.notifier).setEdges([before]);

    final notifier = container.read(documentNodesProvider.notifier);
    notifier.updateEdge(after);

    expect(container.read(documentEdgesProvider), [after]);
    final editedSource = container.read(documentNodesProvider).single;
    expect(
      (editedSource.payload as MermaidPayload).conversionStatus,
      MermaidConversionStatus.nativeEdited,
    );
    expect(container.read(historyProvider).undoStack, hasLength(1));

    notifier.undo();
    expect(container.read(documentEdgesProvider), [before]);
    expect(
      (container.read(documentNodesProvider).single.payload as MermaidPayload)
          .conversionStatus,
      MermaidConversionStatus.converted,
    );

    notifier.redo();
    expect(container.read(documentEdgesProvider), [after]);
  });
}
