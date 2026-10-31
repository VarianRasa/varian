import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/mermaid/domain/mermaid_renderer.dart';
import 'package:varian/features/mermaid/domain/mermaid_svg_native_converter.dart';

const _nativeFixture = '''
<svg xmlns="http://www.w3.org/2000/svg" width="240" height="160" viewBox="0 0 120 80">
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M 0 0 L 10 5 L 0 10 z" />
    </marker>
  </defs>
  <g id="node-a" class="node" transform="translate(5 4)">
    <rect x="5" y="6" width="30" height="16" rx="3" style="fill:#2563EB;stroke:#60A5FA;stroke-width:2" />
    <text x="20" y="16" text-anchor="middle" style="fill:#FFFFFF;font-size:8px">Start</text>
  </g>
  <g id="node-b" class="node">
    <ellipse cx="85" cy="14" rx="15" ry="8" style="fill:#059669;stroke:#34D399;stroke-width:2" />
    <text x="85" y="16" text-anchor="middle" style="fill:#FFFFFF;font-size:8px">Done</text>
  </g>
  <g id="edge-node-a-node-b-0" class="edgePath">
    <path data-source-id="node-a" data-target-id="node-b" d="M 40 14 L 70 14" marker-end="url(#arrow)" style="fill:none;stroke:#94A3B8;stroke-width:2" />
  </g>
</svg>
''';

const _realMetadataFixture = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M 0 0 L 10 5 L 0 10 z" />
    </marker>
  </defs>
  <g id="diagram-node-a" data-et="participant" data-type="participant" data-id="Alice">
    <rect x="5" y="10" width="30" height="16" />
  </g>
  <g id="diagram-node-b" data-et="participant" data-type="participant" data-id="Bob">
    <rect x="65" y="70" width="30" height="16" />
  </g>
  <line id="message-0" data-et="message" data-id="i0" data-from="Alice" data-to="Bob" x1="20" y1="26" x2="80" y2="70" marker-end="url(#arrow)" />
  <path id="edge-route" data-edge="true" data-et="edge" data-id="edge-route" data-points='[{"x":20,"y":26},{"x":50,"y":50},{"x":80,"y":70}]' d="M20 26 L50 50 L80 70" marker-end="url(#arrow)" />
</svg>
''';

CanvasNode _sourceNode(String source) => CanvasNode(
  id: 'mermaid-source',
  type: NodeType.mermaid,
  x: 100,
  y: 200,
  width: 480,
  height: 320,
  payload: MermaidPayload(source: source),
);

class _FakeRenderer implements MermaidRenderer {
  _FakeRenderer(this.svg);

  final String svg;

  @override
  String get rendererVersion => 'fake-renderer-1';

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async => MermaidValidationResult.valid(
    diagramType: detectMermaidDiagramType(source),
  );

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async => MermaidRenderResult(
    svg: svg,
    diagramType: detectMermaidDiagramType(source),
  );
}

void main() {
  test('decomposes safe Mermaid SVG into editable shapes, text, and edge', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('sequenceDiagram\n  Alice->>Bob: Hello'),
      _nativeFixture,
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.nodes.map((node) => node.type),
      containsAll([NodeType.rectangle, NodeType.ellipse, NodeType.text]),
    );
    expect(result.edges, hasLength(1));
    expect(result.edges.single.sourceNodeId, contains('node_'));
    expect(result.edges.single.targetNodeId, contains('node_'));
    expect(result.edges.single.endMarker, LineMarker.arrow);
    expect(
      result.nodes.every((node) => node.mermaidSourceId == 'mermaid-source'),
      isTrue,
    );
    expect(result.edges.single.mermaidSourceId, 'mermaid-source');
  });

  test('maps viewBox, transforms, styles, opacity, and text metrics', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('classDiagram\n  class User'),
      _nativeFixture,
    );

    final rectangle = result.nodes.firstWhere(
      (node) => node.type == NodeType.rectangle,
    );
    final rectanglePayload = rectangle.payload as ShapePayload;
    final label = result.nodes.firstWhere(
      (node) =>
          node.type == NodeType.text &&
          (node.payload as TextPayload).text == 'Start',
    );
    final labelPayload = label.payload as TextPayload;

    expect(rectangle.x, closeTo(140, 0.01));
    expect(rectangle.y, closeTo(240, 0.01));
    expect(rectangle.width, closeTo(120, 0.01));
    expect(rectangle.height, closeTo(64, 0.01));
    expect(rectanglePayload.fill, const Color(0xFF2563EB));
    expect(rectanglePayload.stroke, const Color(0xFF60A5FA));
    expect(labelPayload.color, Colors.white);
    expect(labelPayload.fontSize, closeTo(32, 0.01));
    expect(labelPayload.textAlign, TextAlign.center);
  });

  test('flattens foreignObject labels at their transformed fitted origin', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('mindmap\n  root((Mind Map))'),
      '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <g transform="translate(10 20)">
    <foreignObject x="5" y="7" width="30" height="16">
      <div xmlns="http://www.w3.org/1999/xhtml" style="font-size:8px"><p>Label</p></div>
    </foreignObject>
  </g>
</svg>
''',
    );

    expect(result.isSuccess, isTrue);
    final label = result.nodes.singleWhere((node) {
      return node.type == NodeType.text &&
          (node.payload as TextPayload).text == 'Label';
    });
    expect(label.x, closeTo(212.0, 0.02));
    expect(label.y, closeTo(296.0, 0.01));
  });

  test('uses intrinsic SVG dimensions when viewBox is omitted', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('timeline\n  2020 : Start'),
      '''
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">
  <rect x="10" y="10" width="20" height="20" />
</svg>
''',
    );

    expect(result.isSuccess, isTrue);
    final rectangle = result.nodes.single;
    expect(rectangle.x, closeTo(140, 0.01));
    expect(rectangle.y, closeTo(240, 0.01));
    expect(rectangle.width, closeTo(80, 0.01));
    expect(rectangle.height, closeTo(80, 0.01));
  });

  test('honors nonuniform viewBox fitting and nested SVG viewports', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('timeline\n  2020 : Start'),
      '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" preserveAspectRatio="none">
  <svg x="10" y="20" width="40" height="30" viewBox="0 0 20 10" preserveAspectRatio="none">
    <rect x="0" y="0" width="20" height="10" />
  </svg>
</svg>
''',
    );

    expect(result.isSuccess, isTrue);
    final rectangle = result.nodes.singleWhere(
      (node) => node.type == NodeType.rectangle,
    );
    expect(rectangle.x, closeTo(148, 0.01));
    expect(rectangle.y, closeTo(264, 0.01));
    expect(rectangle.width, closeTo(192, 0.01));
    expect(rectangle.height, closeTo(96, 0.01));
  });

  test('promotes renderer metadata into native connector edges', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('sequenceDiagram\n  Alice->>Bob: Hello'),
      _realMetadataFixture,
    );

    expect(result.isSuccess, isTrue);
    expect(result.edges, hasLength(2));
    expect(
      result.edges.map((edge) => edge.sourceNodeId),
      everyElement(contains('mermaid_node_')),
    );
    expect(
      result.edges.map((edge) => edge.targetNodeId),
      everyElement(contains('mermaid_node_')),
    );
    expect(
      result.nodes.where((node) => node.type == NodeType.vectorPath),
      isEmpty,
    );
  });

  test(
    'keeps a distant connector editable when geometry cannot identify endpoints',
    () {
      final result = MermaidSvgNativeConverter.convert(
        _sourceNode('sequenceDiagram\n  Alice->>Bob: Hello'),
        '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect id="Alice" x="10" y="10" width="20" height="20" />
  <rect id="Bob" x="70" y="70" width="20" height="20" />
  <path data-edge="true" d="M45 45 L55 55" />
</svg>
''',
      );

      expect(result.isSuccess, isTrue);
      expect(result.edges, isEmpty);
      expect(
        result.nodes.where((node) => node.type == NodeType.vectorPath),
        isNotEmpty,
      );
      expect(result.warnings.single.code, 'EDGE_ENDPOINT_UNRESOLVED');
    },
  );

  test('decodes base64 route points and preserves SVG gradients', () {
    final routePoints = base64Encode(
      utf8.encode(
        jsonEncode([
          {'x': 30, 'y': 20},
          {'x': 50, 'y': 50},
          {'x': 70, 'y': 80},
        ]),
      ),
    );
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('flowchart TD\n  A --> B'),
      '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs>
    <linearGradient id="node-fill" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#112233" />
      <stop offset="1" stop-color="#AABBCC" />
    </linearGradient>
  </defs>
  <rect id="A" x="10" y="10" width="20" height="20" fill="url(#node-fill)" />
  <rect id="B" x="70" y="70" width="20" height="20" />
  <path data-edge="true" data-points="$routePoints" d="M30 20 L50 50 L70 80" />
</svg>
''',
    );

    expect(result.isSuccess, isTrue);
    final gradientNode = result.nodes.firstWhere(
      (node) => node.id.endsWith('node_0'),
    );
    final shape = gradientNode.payload as ShapePayload;
    expect(shape.fillType, FillType.linearGradient);
    expect(shape.fill, const Color(0xFF112233));
    expect(shape.fillGradientEnd, const Color(0xFFAABBCC));
    expect(result.edges, hasLength(1));
    expect(result.edges.single.waypoints, hasLength(1));
  });

  test('preserves inherited font family, style, and letter spacing', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('timeline\n  2020 : Start'),
      '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50">
  <style>.caption{font-family:monospace;font-style:italic;letter-spacing:2px;fill:#123456}</style>
  <text class="caption" x="20" y="25">Caption</text>
</svg>
''',
    );

    expect(result.isSuccess, isTrue);
    final payload = result.nodes.single.payload as TextPayload;
    expect(payload.fontFamily, 'monospace');
    expect(payload.fontStyle, FontStyle.italic);
    expect(payload.letterSpacing, closeTo(9.6, 0.01));
    expect(payload.color, const Color(0xFF123456));
  });

  test('preserves CSS cascade specificity for descendant text styles', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('timeline\n  2020 : Start'),
      '''
<svg xmlns="http://www.w3.org/2000/svg" id="diagram" viewBox="0 0 100 50">
  <style>#diagram{fill:#111111;font-family:serif}.label{fill:#222222}</style>
  <g><text class="label" x="20" y="25">Caption</text></g>
</svg>
''',
    );

    expect(result.isSuccess, isTrue);
    final payload = result.nodes.single.payload as TextPayload;
    expect(payload.color, const Color(0xFF222222));
    expect(payload.fontFamily, 'serif');
  });

  test('preserves HSL and CSS class styles in native payloads', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('quadrantChart\n  Item: [0.2, 0.3]'),
      '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50">
  <style>.chart-node{fill:hsl(120, 100%, 50%);stroke:rgb(0, 0, 255);stroke-width:4;font-size:10px}</style>
  <rect class="chart-node" x="10" y="10" width="20" height="12" />
</svg>
''',
    );

    expect(result.isSuccess, isTrue);
    final payload = result.nodes.single.payload as ShapePayload;
    expect(payload.fill, const Color(0xFF00FF00));
    expect(payload.stroke, const Color(0xFF0000FF));
    expect(payload.strokeWidth, closeTo(19.2, 0.01));
  });

  test('rejects malformed metadata without partial output', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('stateDiagram-v2\n  [*] --> Idle'),
      '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect x="10" y="10" width="20" height="20" />
  <path data-edge="true" data-points="not-json" d="M20 20 L80 80" />
</svg>
''',
    );

    expect(result.isSuccess, isFalse);
    expect(result.nodes, isEmpty);
    expect(result.edges, isEmpty);
    expect(result.diagnostic?.code, 'SVG_EDGE_POINTS_INVALID');
  });

  test('produces deterministic native IDs and JSON for the same SVG', () {
    final source = _sourceNode('mindmap\n  root((Mind Map))');

    final first = MermaidSvgNativeConverter.convert(source, _nativeFixture);
    final second = MermaidSvgNativeConverter.convert(source, _nativeFixture);

    expect(
      first.nodes.map((node) => node.toJson()).toList(),
      second.nodes.map((node) => node.toJson()).toList(),
    );
    expect(
      first.edges.map((edge) => edge.toJson()).toList(),
      second.edges.map((edge) => edge.toJson()).toList(),
    );
  });

  test('converts every supported Mermaid family through the local renderer', () async {
    const sources = {
      'flowchart TD\n  A --> B',
      'sequenceDiagram\n  Alice->>Bob: Hello',
      'classDiagram\n  class User',
      'stateDiagram-v2\n  [*] --> Idle',
      'erDiagram\n  USER ||--o{ ORDER : places',
      'journey\n  title Work\n  section Day\n    Code: 5: Me',
      'gantt\n  title Plan\n  section Work\n  Task: t1, 2024-01-01, 2d',
      'gitGraph\n  commit',
      'mindmap\n  root((Mind Map))',
      'timeline\n  2020 : Start',
      'pie title Pets\n  "Dogs" : 1',
      'quadrantChart\n  x-axis Low --> High\n  y-axis Low --> High\n  Item: [0.2, 0.3]',
      'requirementDiagram\n  requirement test { id: 1 }',
      'xychart-beta\n  x-axis [A]\n  bar [1]',
      'sankey-beta\n  A,B,10',
      'block-beta\n  A',
      'architecture-beta\n  service api(server)[API]',
      'packet-beta\n  0-7: "Version"',
      'kanban\n  Todo\n    [Task]',
      'radar-beta\n  axis A, B\n  curve C{1, 2}',
      'treemap-beta\n  "Root"\n    "Child": 10',
      'zenuml\n  Alice->Bob: Hello',
      'C4Context\n  Person(user, "User")\n  System(app, "App")\n  Rel(user, app, "Uses")',
      'C4Container\n  Person(user, "User")\n  System_Boundary(app, "App") {\n    Container(web, "Web")\n  }\n  Rel(user, web, "Uses")',
      'C4Component\n  Container_Boundary(app, "App") {\n    Component(web, "Web")\n  }',
      'C4Dynamic\n  Person(user, "User")\n  System(app, "App")\n  Rel(user, app, "Uses")',
      'C4Deployment\n  Person(user, "User")\n  Deployment_Node(node, "Node") {\n    Container(app, "App")\n  }\n  Rel(user, app, "Uses")',
    };
    final converter = MermaidNativeConverter(
      renderer: _FakeRenderer(_nativeFixture),
    );

    for (final source in sources) {
      final result = await converter.convert(_sourceNode(source));
      expect(result.isSuccess, isTrue, reason: source.split('\n').first);
      expect(result.nodes, isNotEmpty, reason: source.split('\n').first);
      expect(
        result.diagramType,
        isNot('unknown'),
        reason: source.split('\n').first,
      );
    }
  });

  test(
    'falls back from rich flowchart syntax without partial output',
    () async {
      final result =
          await MermaidNativeConverter(
            renderer: _FakeRenderer(_nativeFixture),
          ).convert(
            _sourceNode('''flowchart TD
  subgraph Users
    A[User] --> B[Service]
  end'''),
          );

      expect(result.isSuccess, isTrue);
      expect(result.nodes, isNotEmpty);
      expect(result.diagnostic, isNull);
    },
  );

  test('rejects malformed SVG numeric geometry without partial output', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('timeline\n  2020 : Start'),
      '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="oops 0 0 100 100">
  <rect x="10" y="10" width="20" height="20" />
</svg>
''',
    );

    expect(result.isSuccess, isFalse);
    expect(result.nodes, isEmpty);
    expect(result.edges, isEmpty);
    expect(result.diagnostic?.code, 'SVG_NUMBER_INVALID');
  });

  test('rejects remote image references without partial output', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('pie title Unsafe\n  "X" : 1'),
      '''
<svg xmlns="http://www.w3.org/2000/svg">
  <image x="0" y="0" width="20" height="20" xlink:href="https://example.test/icon.png" />
</svg>
''',
    );

    expect(result.isSuccess, isFalse);
    expect(result.nodes, isEmpty);
    expect(result.edges, isEmpty);
    expect(result.diagnostic?.code, 'SVG_EXTERNAL_REFERENCE');
  });

  test('rejects unsafe SVG and returns no native objects', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('pie title Unsafe\n  "X" : 1'),
      '<svg><script>alert(1)</script></svg>',
    );

    expect(result.isSuccess, isFalse);
    expect(result.nodes, isEmpty);
    expect(result.edges, isEmpty);
    expect(result.diagnostic?.code, isNotNull);
  });

  test('rejects visible unsupported SVG elements instead of dropping them', () {
    final result = MermaidSvgNativeConverter.convert(
      _sourceNode('timeline\n  2020 : Start'),
      '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject><div>Text</div></foreignObject></svg>',
    );

    expect(result.isSuccess, isFalse);
    expect(result.nodes, isEmpty);
    expect(result.edges, isEmpty);
  });
}
