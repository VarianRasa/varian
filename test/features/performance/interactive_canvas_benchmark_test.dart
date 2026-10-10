import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/presentation/painters/canvas_painter.dart';
import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';
import 'package:varian/features/canvas/utils/hit_tester.dart';
import 'package:varian/features/performance/domain/creative_studio_benchmark.dart';

void main() {
  testWidgets('large canvas benchmark exercises real paint and gestures', (
    tester,
  ) async {
    final scenario = CreativeStudioBenchmark.scenarios.last;
    final nodes = _benchmarkNodes(scenario.nodeCount);
    final viewport = ValueNotifier(const Viewport());
    var rebuildCount = 0;
    final startupWatch = Stopwatch()..start();

    await tester.pumpWidget(
      _benchmarkCanvas(nodes, viewport, () => rebuildCount++),
    );
    await tester.pump();
    startupWatch.stop();

    final operationWatch = Stopwatch()..start();
    for (var step = 0; step < 12; step++) {
      viewport.value = Viewport(
        x: step * -24.0,
        y: step * -12.0,
        zoom: 1.0 + step * 0.02,
      );
      await tester.pump();
    }
    await tester.drag(
      find.byKey(const Key('interactive-benchmark-canvas')),
      const Offset(120, 72),
    );
    await tester.pump();
    operationWatch.stop();

    expect(CanvasHitTester.hitTest(nodes, const Offset(62, 62)), isNotNull);
    expect(nodes, hasLength(scenario.nodeCount));
    expect(nodes.map((node) => node.id).toSet(), hasLength(nodes.length));
    expect(rebuildCount, greaterThanOrEqualTo(14));
    expect(startupWatch.elapsed, lessThanOrEqualTo(scenario.startupBudget));
    expect(operationWatch.elapsed, lessThan(const Duration(seconds: 8)));
  });
}

Widget _benchmarkCanvas(
  List<CanvasNode> nodes,
  ValueNotifier<Viewport> viewport,
  VoidCallback onBuild,
) => MaterialApp(
  home: ColoredBox(
    color: const Color(0xFF0B1120),
    child: Center(
      child: SizedBox(
        width: 800,
        height: 500,
        child: GestureDetector(
          key: const Key('interactive-benchmark-canvas'),
          onPanUpdate: (details) {
            viewport.value = viewport.value.copyWith(
              x: viewport.value.x + details.delta.dx,
              y: viewport.value.y + details.delta.dy,
            );
          },
          child: ValueListenableBuilder<Viewport>(
            valueListenable: viewport,
            builder: (context, value, _) {
              onBuild();
              return CustomPaint(
                size: const Size(800, 500),
                painter: CanvasPainter(
                  nodes: nodes,
                  viewport: value,
                  selectedNodeIds: const {},
                  renderTokens: CanvasRenderTokens.dark,
                ),
              );
            },
          ),
        ),
      ),
    ),
  ),
);

List<CanvasNode> _benchmarkNodes(int count) =>
    List<CanvasNode>.generate(count, (index) {
      final x = (index % 100) * 120.0;
      final y = (index ~/ 100) * 86.0;
      if (index % 257 == 0) {
        return CanvasNode(
          id: 'video-$index',
          type: NodeType.videoCard,
          x: x,
          y: y,
          width: 108,
          height: 68,
          payload: VideoPayload(title: 'Benchmark video'),
        );
      }
      if (index % 193 == 0) {
        return CanvasNode(
          id: 'glb-$index',
          type: NodeType.model3d,
          x: x,
          y: y,
          width: 108,
          height: 68,
          payload: Model3DPayload(fileName: 'benchmark.glb'),
        );
      }
      if (index % 89 == 0) {
        return CanvasNode(
          id: 'image-$index',
          type: NodeType.image,
          x: x,
          y: y,
          width: 108,
          height: 68,
          payload: ImagePayload(assetId: 'benchmark-image-'),
        );
      }
      if (index % 47 == 0) {
        return CanvasNode(
          id: 'stroke-$index',
          type: NodeType.drawing,
          x: x,
          y: y,
          width: 108,
          height: 68,
          payload: DrawingPayload(
            points: const [
              Offset(0, 10),
              Offset(24, 44),
              Offset(54, 16),
              Offset(96, 52),
            ],
          ),
        );
      }
      return CanvasNode(
        id: 'node-$index',
        type: NodeType.rectangle,
        x: x,
        y: y,
        width: 108,
        height: 68,
        payload: ShapePayload(
          fill: Color(0xFF2563EB + (index % 6) * 0x00050000),
          stroke: const Color(0xFF93C5FD),
          cornerRadius: 8,
        ),
      );
    }, growable: false);
