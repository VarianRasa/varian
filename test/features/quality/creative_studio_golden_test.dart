import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/presentation/painters/canvas_painter.dart';
import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';

void main() {
  testWidgets('creative studio visual smoke contract', (tester) async {
    const key = Key('creative-studio-golden-smoke');
    await tester.pumpWidget(
      const MaterialApp(
        home: ColoredBox(
          color: Color(0xFF111827),
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 240,
                height: 120,
                child: Row(
                  children: [
                    Expanded(child: ColoredBox(color: Color(0xFF2563EB))),
                    Expanded(child: ColoredBox(color: Color(0xFFF97316))),
                    Expanded(child: ColoredBox(color: Color(0xFF22C55E))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/creative_studio_smoke.png'),
    );
  });

  testWidgets('canvas selection and marquee rendering', (tester) async {
    await tester.pumpWidget(
      _canvasFixture(
        nodes: [
          _rectangle('selected', 48, 56, 148, 88),
          _rectangle('other', 260, 100, 120, 72),
        ],
        selectedNodeIds: const {'selected'},
        selectionMarquee: const Rect.fromLTWH(36, 42, 180, 122),
      ),
    );

    await expectLater(
      find.byKey(const Key('canvas-golden-fixture')),
      matchesGoldenFile('goldens/canvas_selection.png'),
    );
  });

  testWidgets('canvas rotated transform handles rendering', (tester) async {
    await tester.pumpWidget(
      _canvasFixture(
        nodes: [_rectangle('rotated', 152, 86, 156, 92, rotation: 0.32)],
        selectedNodeIds: const {'rotated'},
      ),
    );

    await expectLater(
      find.byKey(const Key('canvas-golden-fixture')),
      matchesGoldenFile('goldens/canvas_transform.png'),
    );
  });

  testWidgets('canvas nested frame clipping and selection rendering', (
    tester,
  ) async {
    await tester.pumpWidget(
      _canvasFixture(
        nodes: [
          CanvasNode(
            id: 'frame',
            type: NodeType.frame,
            x: 32,
            y: 34,
            width: 360,
            height: 212,
            zIndex: 0,
            payload: FramePayload(
              name: 'Nested board',
              background: const Color(0xFF1E293B),
              borderColor: const Color(0xFF38BDF8),
              borderWidth: 2,
              clipContent: true,
            ),
          ),
          _rectangle(
            'child',
            72,
            84,
            180,
            92,
            parentId: 'frame',
            fill: const Color(0xFF22C55E),
          ),
          _rectangle(
            'clipped-child',
            332,
            178,
            130,
            96,
            parentId: 'frame',
            fill: const Color(0xFFF97316),
          ),
        ],
        selectedNodeIds: const {'child'},
      ),
    );

    await expectLater(
      find.byKey(const Key('canvas-golden-fixture')),
      matchesGoldenFile('goldens/canvas_nesting.png'),
    );
  });

  testWidgets('canvas selected edge repair controls rendering', (tester) async {
    await tester.pumpWidget(
      _canvasFixture(
        nodes: [
          _rectangle('source', 44, 100, 112, 70),
          _rectangle('target', 312, 100, 112, 70),
        ],
        edges: const [
          CanvasEdge(
            id: 'edge',
            sourceNodeId: 'source',
            targetNodeId: 'target',
            routing: ConnectorRouting.orthogonal,
            waypoints: [Offset(220, 135), Offset(220, 62)],
            endMarker: LineMarker.arrow,
            label: 'Repair path',
          ),
        ],
        selectedNodeIds: const {'edge'},
      ),
    );

    await expectLater(
      find.byKey(const Key('canvas-golden-fixture')),
      matchesGoldenFile('goldens/canvas_edge_repair.png'),
    );
  });
}

Widget _canvasFixture({
  required List<CanvasNode> nodes,
  required Set<String> selectedNodeIds,
  List<CanvasEdge> edges = const [],
  Rect? selectionMarquee,
}) {
  return MaterialApp(
    home: ColoredBox(
      color: const Color(0xFF0B1120),
      child: Center(
        child: RepaintBoundary(
          key: const Key('canvas-golden-fixture'),
          child: SizedBox(
            width: 480,
            height: 300,
            child: CustomPaint(
              painter: CanvasPainter(
                nodes: nodes,
                edges: edges,
                viewport: const Viewport(),
                selectedNodeIds: selectedNodeIds,
                selectionMarquee: selectionMarquee,
                renderTokens: CanvasRenderTokens.dark,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

CanvasNode _rectangle(
  String id,
  double x,
  double y,
  double width,
  double height, {
  double rotation = 0,
  String? parentId,
  Color fill = const Color(0xFF2563EB),
}) {
  return CanvasNode(
    id: id,
    type: NodeType.rectangle,
    x: x,
    y: y,
    width: width,
    height: height,
    rotation: rotation,
    parentId: parentId,
    payload: ShapePayload(
      fill: fill,
      stroke: const Color(0xFF93C5FD),
      strokeWidth: 2,
      cornerRadius: 12,
    ),
  );
}
