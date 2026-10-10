import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/mermaid/domain/mermaid_flowchart_converter.dart';

void main() {
  CanvasNode sourceNode(String source) => CanvasNode(
    id: 'source-node',
    type: NodeType.mermaid,
    x: 100,
    y: 200,
    width: 480,
    height: 320,
    payload: MermaidPayload(source: source),
  );

  test('converts the bounded flowchart subset to native nodes and edges', () {
    final result = MermaidFlowchartConverter.convert(
      sourceNode('''
flowchart LR
  A[Start] --> B{Ready?}
  B -.-> C((Done))
'''),
    );

    expect(result.isSuccess, isTrue);
    expect(result.nodes.map((node) => node.type), [
      NodeType.rectangle,
      NodeType.diamond,
      NodeType.ellipse,
    ]);
    expect(result.nodes.map((node) => (node.payload as ShapePayload).label), [
      'Start',
      'Ready?',
      'Done',
    ]);
    expect(result.edges, hasLength(2));
    expect(result.edges.first.endMarker, LineMarker.arrow);
    expect(result.edges.first.routing, ConnectorRouting.orthogonal);
    expect(result.edges.last.strokeStyle, StrokeStyle.dotted);
    expect(result.edges.last.sourceNodeId, result.nodes[1].id);
    expect(result.edges.last.targetNodeId, result.nodes[2].id);
    expect(result.nativeNodeIds, result.nodes.map((node) => node.id).toList());
    expect(result.nativeEdgeIds, result.edges.map((edge) => edge.id).toList());
    expect(
      result.nodes.every((node) => node.mermaidSourceId == 'source-node'),
      isTrue,
    );
    expect(
      result.edges.every((edge) => edge.mermaidSourceId == 'source-node'),
      isTrue,
    );
    expect(
      CanvasNode.fromJson(result.nodes.first.toJson()).mermaidSourceId,
      'source-node',
    );
    expect(
      CanvasEdge.fromJson(result.edges.first.toJson()).mermaidSourceId,
      'source-node',
    );
  });

  test('maps supported shapes and edge labels without losing semantics', () {
    final result = MermaidFlowchartConverter.convert(
      sourceNode('''
flowchart TD
  A[/Input/] -->|yes| B[(Store)]
  B ==> C[\\Output\\]
'''),
    );

    expect(result.isSuccess, isTrue);
    expect(result.nodes.map((node) => node.type), [
      NodeType.parallelogram,
      NodeType.cylinder,
      NodeType.parallelogram,
    ]);
    expect(result.edges.first.label, 'yes');
    expect(result.edges.first.strokeStyle, StrokeStyle.solid);
    expect(result.edges.last.strokeWidth, 3);
    expect(result.edges.last.endMarker, LineMarker.arrow);
  });

  test('honors all supported directions with matching anchors', () {
    final expectations = {
      'TD': (AnchorPosition.bottom, AnchorPosition.top, false, true),
      'BT': (AnchorPosition.top, AnchorPosition.bottom, false, false),
      'LR': (AnchorPosition.right, AnchorPosition.left, true, false),
      'RL': (AnchorPosition.left, AnchorPosition.right, false, false),
    };

    for (final entry in expectations.entries) {
      final result = MermaidFlowchartConverter.convert(
        sourceNode('flowchart ${entry.key}\n  A --> B'),
      );

      expect(result.isSuccess, isTrue, reason: entry.key);
      expect(result.edges.single.sourceAnchor, entry.value.$1);
      expect(result.edges.single.targetAnchor, entry.value.$2);
      expect(
        result.nodes[1].x > result.nodes[0].x,
        entry.value.$3,
        reason: entry.key,
      );
      expect(
        result.nodes[1].y > result.nodes[0].y,
        entry.value.$4,
        reason: entry.key,
      );
    }
  });

  test('produces deterministic IDs and layout for the same source node', () {
    final source = sourceNode('flowchart TD\n  A[One] --> B[Two]');

    final first = MermaidFlowchartConverter.convert(source);
    final second = MermaidFlowchartConverter.convert(source);

    expect(
      first.nodes.map((node) => node.toJson()).toList(),
      second.nodes.map((node) => node.toJson()).toList(),
    );
    expect(
      first.edges.map((edge) => edge.toJson()).toList(),
      second.edges.map((edge) => edge.toJson()).toList(),
    );
  });

  test('uses the Mermaid header direction when direction is automatic', () {
    final result = MermaidFlowchartConverter.convert(
      sourceNode('''
flowchart LR
  A[Start] --> B[First branch]
  A --> C[Second branch]
'''),
    );
    final byLabel = {
      for (final node in result.nodes)
        (node.payload as ShapePayload).label: node,
    };

    expect(result.isSuccess, isTrue);
    expect(byLabel['First branch']!.x, byLabel['Second branch']!.x);
    expect(byLabel['First branch']!.y, isNot(byLabel['Second branch']!.y));
    expect(byLabel['First branch']!.x, greaterThan(byLabel['Start']!.x));
  });

  test('layers cyclic branches according to every supported direction', () {
    const graph = '''
  A[Start] --> B[Login]
  B --> C{Ready?}
  C --> D[Input]
  D --> E[Validate]
  E --> F[Error]
  F --> C
  E --> G[System]
  G --> H[Done]
''';

    final expectations = {
      'TD': (true, true),
      'BT': (true, false),
      'LR': (false, true),
      'RL': (false, false),
    };

    for (final entry in expectations.entries) {
      final result = MermaidFlowchartConverter.convert(
        sourceNode('flowchart ${entry.key}\n$graph'),
      );
      final byLabel = {
        for (final node in result.nodes)
          (node.payload as ShapePayload).label: node,
      };
      final branchA = byLabel['Error']!;
      final branchB = byLabel['System']!;
      final start = byLabel['Start']!;
      final done = byLabel['Done']!;

      expect(result.isSuccess, isTrue, reason: entry.key);
      expect(
        entry.value.$1 ? branchA.y == branchB.y : branchA.x == branchB.x,
        isTrue,
        reason: entry.key,
      );
      expect(
        entry.value.$1 ? branchA.x != branchB.x : branchA.y != branchB.y,
        isTrue,
        reason: entry.key,
      );
      expect(
        branchA.bounds.overlaps(branchB.bounds),
        isFalse,
        reason: entry.key,
      );
      expect(
        entry.value.$2
            ? (entry.value.$1 ? start.y < done.y : start.x < done.x)
            : (entry.value.$1 ? start.y > done.y : start.x > done.x),
        isTrue,
        reason: entry.key,
      );
    }
  });

  test(
    'rejects unsupported syntax without returning partial native content',
    () {
      final result = MermaidFlowchartConverter.convert(
        sourceNode('''
flowchart TD
  subgraph Users
    A[User]
  end
'''),
      );

      expect(result.isSuccess, isFalse);
      expect(result.nodes, isEmpty);
      expect(result.edges, isEmpty);
      expect(result.diagnostic?.code, 'UNSUPPORTED_CONVERSION');
      expect(result.diagnostic?.line, 2);
    },
  );

  test('reports malformed edge syntax with a source location', () {
    final result = MermaidFlowchartConverter.convert(
      sourceNode('flowchart TD\n  A[Start] -->'),
    );

    expect(result.isSuccess, isFalse);
    expect(result.nodes, isEmpty);
    expect(result.edges, isEmpty);
    expect(result.diagnostic?.code, 'MALFORMED_FLOWCHART');
    expect(result.diagnostic?.line, 2);
    expect(result.diagnostic?.column, greaterThan(0));
  });

  test('enforces the generated object limit before returning a graph', () {
    final declarations = List<String>.generate(
      2001,
      (index) => 'N$index[Node $index]',
    ).join('\n');
    final result = MermaidFlowchartConverter.convert(
      sourceNode('flowchart TD\n$declarations'),
    );

    expect(result.isSuccess, isFalse);
    expect(result.nodes, isEmpty);
    expect(result.edges, isEmpty);
    expect(result.diagnostic?.code, 'GENERATED_OBJECTS_TOO_MANY');
  });
}
