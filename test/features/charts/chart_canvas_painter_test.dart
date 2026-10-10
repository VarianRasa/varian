import 'dart:ui' as ui;

import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';
import 'package:varian/features/charts/presentation/chart_canvas_painter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';

void main() {
  test('native chart fallback uses active surface tokens', () async {
    for (final tokens in [CanvasRenderTokens.light, CanvasRenderTokens.dark]) {
      final recorder = ui.PictureRecorder();
      ChartCanvasPainter.paint(
        ui.Canvas(recorder),
        CanvasNode(
          id: 'theme-chart',
          type: NodeType.chart,
          x: 0,
          y: 0,
          width: 120,
          height: 240,
          payload: ChartPayload(title: '', showLegend: false),
        ),
        ChartPayload(title: '', showLegend: false),
        tokens: tokens,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(120, 240);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (210 * 120 + 30) * 4;
      final pixel = ui.Color.fromARGB(
        bytes!.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );

      expect(pixel, tokens.panelElevated);
      image.dispose();
      picture.dispose();
    }
  });
  test('native canvas fallback paints every supported chart family', () {
    for (final chartType in ChartType.values) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final node = CanvasNode(
        id: 'chart-${chartType.name}',
        type: NodeType.chart,
        x: 0,
        y: 0,
        width: 360,
        height: 240,
        payload: ChartPayload(
          chartType: chartType,
          categories: const ['A', 'B', 'C', 'D'],
          series: [
            ChartSeries(
              name: 'Primary',
              values: const [4, 7, 5, 9],
              points: [
                ChartPoint(x: 0, y: 4),
                ChartPoint(x: 1, y: 7),
                ChartPoint(x: 2, y: 5),
                ChartPoint(x: 3, y: 9),
              ],
            ),
          ],
        ),
      );

      NodePainter.paint(canvas, node);
      final picture = recorder.endRecording();
      picture.dispose();
    }
  });
}
