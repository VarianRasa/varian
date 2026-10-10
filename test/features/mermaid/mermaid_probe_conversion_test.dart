import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/mermaid/domain/mermaid_svg_native_converter.dart';
import 'package:varian/features/mermaid/domain/mermaid_svg_sanitizer.dart';

void main() {
  const sources = <String, String>{
    'flowchart': 'flowchart TD\n  A[Start] --> B[End]',
    'sequence': 'sequenceDiagram\n  Alice->>Bob: Hello',
    'class': 'classDiagram\n  class User',
    'state': 'stateDiagram-v2\n  [*] --> Idle',
    'er': 'erDiagram\n  USER ||--o{ ORDER : places',
    'journey': 'journey\n  title Work\n  section Day\n    Code: 5: Me',
    'gantt': 'gantt\n  title Plan\n  section Work\n  t1: task, 2024-01-01, 2d',
    'gitGraph': 'gitGraph\n  commit',
    'mindmap': 'mindmap\n  root((Mind Map))',
    'timeline': 'timeline\n  2020 : Start',
    'pie': 'pie title Pets\n  "Dogs" : 1',
    'quadrant':
        'quadrantChart\n  x-axis Low --> High\n  y-axis Low --> High\n  Item: [0.2, 0.3]',
    'requirement':
        'requirementDiagram\n  requirement test {\n    id: 1\n    verifymethod: test\n  }',
    'xychart': 'xychart-beta\n  x-axis [A, B]\n  bar [1, 2]',
    'sankey': 'sankey-beta\n  A,B,10',
    'block': 'block-beta\n  A',
    'architecture': 'architecture-beta\n  service api(server)[API]',
    'packet': 'packet-beta\n  0-7: "Version"',
    'kanban': 'kanban\n  Todo\n    [Task]',
    'radar': 'radar-beta\n  axis A, B\n  curve C{1, 2}',
    'treemap': 'treemap-beta\n  "Root"\n    "Child": 10',
    'zenuml': 'zenuml\n  Alice->Bob: Hello',
    'c4context':
        'C4Context\n  title System Context\n  Person(user, "User")\n  System(app, "App")\n  Rel(user, app, "Uses")',
    'c4container':
        'C4Container\n  title Container diagram\n  Person(user, "User")\n  System_Boundary(app, "App") {\n    Container(web, "Web")\n  }\n  Rel(user, web, "Uses")',
    'c4component':
        'C4Component\n  title Component diagram\n  Container_Boundary(app, "App") {\n    Component(web, "Web")\n  }',
    'c4dynamic':
        'C4Dynamic\n  title Dynamic diagram\n  Person(user, "User")\n  System(app, "App")\n  Rel(user, app, "Uses")',
    'c4deployment':
        'C4Deployment\n  title Deployment diagram\n  Person(user, "User")\n  Deployment_Node(node, "Node") {\n    Container(app, "App")\n  }\n  Rel(user, app, "Uses")',
  };

  test('converts durable local SVG fixtures for every renderer family', () {
    for (final entry in sources.entries) {
      final family = entry.key;
      final source = CanvasNode(
        id: 'source-$family',
        type: NodeType.mermaid,
        x: 0,
        y: 0,
        width: 1000,
        height: 700,
        payload: MermaidPayload(source: entry.value),
      );
      final svg = File(
        'test/features/mermaid/fixtures/probe_$family.svg',
      ).readAsStringSync();
      final normalized = MermaidSvgSanitizer.normalizeForFlutter(svg);
      final result = MermaidSvgNativeConverter.convert(source, normalized);

      expect(result.isSuccess, isTrue, reason: family);
      expect(result.nodes, isNotEmpty, reason: family);
      expect(
        result.nodes.every((node) => node.mermaidSourceId == source.id),
        isTrue,
        reason: family,
      );
      expect(
        result.nodes.map((node) => node.id).toSet(),
        hasLength(result.nodes.length),
        reason: family,
      );
      expect(
        result.edges.map((edge) => edge.id).toSet(),
        hasLength(result.edges.length),
        reason: family,
      );
    }
  });
}
