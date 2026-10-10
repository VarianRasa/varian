import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';

void main() {
  test('derived Mermaid render state does not create an undo command', () {
    final node = CanvasNode(
      id: 'mermaid-node',
      type: NodeType.mermaid,
      x: 0,
      y: 0,
      width: 320,
      height: 220,
      payload: MermaidPayload(
        source: 'flowchart TD\n  A --> B',
        sourceRevision: 1,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        documentNodesProvider.overrideWith(
          (ref) => DocumentNodesNotifier(ref, initialNodes: [node]),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(documentNodesProvider.notifier)
        .updateDerivedNode(
          node.copyWith(
            payload: (node.payload as MermaidPayload).copyWith(
              diagramType: 'flowchart',
              cachedSvg: '<svg viewBox="0 0 10 10"/>',
              cachedSvgRevision: 1,
            ),
          ),
        );

    final stored = container.read(documentNodesProvider).single;
    expect((stored.payload as MermaidPayload).cachedSvgRevision, 1);
    expect(container.read(historyProvider).undoStack, isEmpty);
  });
}
