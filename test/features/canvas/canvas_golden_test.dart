import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import '../../support/tolerant_golden_file_comparator.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/presentation/painters/canvas_painter.dart';
import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';

void main() {
  allowLinuxGoldenRasterizationDifference(
    'test/features/canvas/canvas_golden_test.dart',
  );

  testWidgets('selection and transform rendering remains stable', (
    tester,
  ) async {
    final selected = CanvasNode(
      id: 'transform',
      type: NodeType.rectangle,
      x: 120,
      y: 90,
      width: 190,
      height: 110,
      rotation: 0.18,
      payload: ShapePayload(
        fill: const Color(0xFF2563EB),
        stroke: const Color(0xFF93C5FD),
        cornerRadius: 16,
        label: 'Transform',
      ),
    );
    final secondary = CanvasNode(
      id: 'secondary',
      type: NodeType.ellipse,
      x: 370,
      y: 145,
      width: 100,
      height: 70,
      payload: ShapePayload(
        fill: const Color(0xFF7C3AED),
        stroke: const Color(0xFFC4B5FD),
      ),
    );

    await _pumpCanvas(
      tester,
      CanvasPainter(
        nodes: [selected, secondary],
        viewport: const Viewport(),
        selectedNodeIds: const {'transform'},
        selectionMarquee: const Rect.fromLTWH(80, 55, 300, 205),
        renderTokens: CanvasRenderTokens.dark,
      ),
    );

    await expectLater(
      find.byKey(_canvasKey),
      matchesGoldenFile('goldens/canvas_selection_transform.png'),
    );
  });

  testWidgets('nested frame clipping remains stable', (tester) async {
    final frame = CanvasNode(
      id: 'frame',
      type: NodeType.frame,
      x: 60,
      y: 50,
      width: 300,
      height: 220,
      zIndex: 0,
      payload: FramePayload(
        name: 'Clipped Frame',
        background: const Color(0xFF1E293B),
        backgroundGradientEnd: const Color(0xFF334155),
        clipContent: true,
        cornerRadius: 18,
        borderColor: const Color(0xFF818CF8),
      ),
    );
    final clippedChild = CanvasNode(
      id: 'clipped-child',
      type: NodeType.rectangle,
      x: 255,
      y: 175,
      width: 180,
      height: 120,
      zIndex: 1,
      parentId: frame.id,
      payload: ShapePayload(
        fill: const Color(0xFFF97316),
        stroke: const Color(0xFFFED7AA),
        cornerRadius: 12,
        label: 'Clipped',
      ),
    );
    final innerChild = CanvasNode(
      id: 'inner-child',
      type: NodeType.rectangle,
      x: 95,
      y: 95,
      width: 125,
      height: 70,
      zIndex: 1,
      parentId: frame.id,
      payload: ShapePayload(
        fill: const Color(0xFF0EA5E9),
        stroke: const Color(0xFFBAE6FD),
        cornerRadius: 10,
      ),
    );

    await _pumpCanvas(
      tester,
      CanvasPainter(
        nodes: [frame, clippedChild, innerChild],
        viewport: const Viewport(),
        selectedNodeIds: const {'clipped-child'},
        renderTokens: CanvasRenderTokens.dark,
      ),
    );

    await expectLater(
      find.byKey(_canvasKey),
      matchesGoldenFile('goldens/canvas_nested_clipping.png'),
    );
  });

  testWidgets('selected orthogonal edge repair controls remain stable', (
    tester,
  ) async {
    final source = CanvasNode(
      id: 'source',
      type: NodeType.rectangle,
      x: 55,
      y: 90,
      width: 125,
      height: 80,
      payload: ShapePayload(
        fill: const Color(0xFF166534),
        stroke: const Color(0xFF86EFAC),
        cornerRadius: 10,
      ),
    );
    final target = CanvasNode(
      id: 'target',
      type: NodeType.rectangle,
      x: 380,
      y: 230,
      width: 125,
      height: 80,
      payload: ShapePayload(
        fill: const Color(0xFF991B1B),
        stroke: const Color(0xFFFCA5A5),
        cornerRadius: 10,
      ),
    );
    const edge = CanvasEdge(
      id: 'edge-repair',
      sourceNodeId: 'source',
      sourceAnchor: AnchorPosition.right,
      targetNodeId: 'target',
      targetAnchor: AnchorPosition.left,
      routing: ConnectorRouting.orthogonal,
      waypoints: [Offset(255, 130), Offset(255, 270)],
      label: 'Repair',
    );

    await _pumpCanvas(
      tester,
      CanvasPainter(
        nodes: [source, target],
        edges: const [edge],
        viewport: const Viewport(),
        selectedNodeIds: const {'edge-repair'},
        renderTokens: CanvasRenderTokens.dark,
      ),
    );

    await expectLater(
      find.byKey(_canvasKey),
      matchesGoldenFile('goldens/canvas_edge_repair.png'),
    );
  });

  testWidgets('locked hidden and text nodes remain stable at high DPI', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final text = CanvasNode(
      id: 'text',
      type: NodeType.text,
      x: 82,
      y: 78,
      width: 300,
      height: 112,
      locked: true,
      payload: TextPayload(
        text: 'Creative Studio',
        fontSize: 30,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
        color: const Color(0xFFF8FAFC),
        backgroundColor: const Color(0xFF1D4ED8),
        backgroundRadius: 14,
        backgroundPadding: 14,
      ),
    );
    final visibleShape = CanvasNode(
      id: 'visible-shape',
      type: NodeType.rectangle,
      x: 360,
      y: 210,
      width: 126,
      height: 82,
      payload: ShapePayload(
        fill: const Color(0xFFEA580C),
        stroke: const Color(0xFFFED7AA),
        cornerRadius: 14,
      ),
    );
    final hiddenShape = CanvasNode(
      id: 'hidden-shape',
      type: NodeType.ellipse,
      x: 140,
      y: 226,
      width: 150,
      height: 82,
      visible: false,
      payload: ShapePayload(
        fill: const Color(0xFF22C55E),
        stroke: const Color(0xFFBBF7D0),
      ),
    );

    await _pumpCanvas(
      tester,
      CanvasPainter(
        nodes: [text, visibleShape, hiddenShape],
        viewport: const Viewport(),
        selectedNodeIds: const {'text'},
        renderTokens: CanvasRenderTokens.dark,
      ),
    );

    // Linux CI differs by 0.42% on this high-DPI text golden.
    final previousComparator = goldenFileComparator;
    allowLinuxGoldenRasterizationDifference(
      'test/features/canvas/canvas_golden_test.dart',
      precisionTolerance: 0.005,
    );
    try {
      await expectLater(
        find.byKey(_canvasKey),
        matchesGoldenFile('goldens/canvas_locked_hidden_text_hidpi.png'),
      );
    } finally {
      goldenFileComparator = previousComparator;
    }
  });
}

const _canvasKey = ValueKey<String>('canvas-golden');

Future<void> _pumpCanvas(WidgetTester tester, CanvasPainter painter) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 560,
          height: 360,
          child: RepaintBoundary(
            key: _canvasKey,
            child: ColoredBox(
              color: CanvasRenderTokens.dark.canvas,
              child: CustomPaint(painter: painter),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
