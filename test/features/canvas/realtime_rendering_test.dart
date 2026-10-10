import 'dart:ui';

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/presentation/painters/canvas_painter.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Real-Time Live Canvas Preview & Rendering Tests', () {
    test(
      'CanvasPainter renders active brush stroke and creation preview correctly without throwing',
      () {
        const painter = CanvasPainter(
          nodes: [],
          viewport: Viewport(),
          selectedNodeIds: {},
          activeBrushStroke: [Offset(10, 10), Offset(20, 25), Offset(35, 40)],
          activeBrushType: BrushType.ink,
          activeBrushColor: Colors.orange,
          activeBrushWidth: 4.0,
          activeCreationTool: CanvasTool.rectangle,
          creationPreviewRect: Rect.fromLTWH(50, 50, 120, 80),
          connectorPreview: (Offset(100, 100), Offset(250, 250)),
          activePenPoints: [
            BezierPoint(point: Offset(0, 0), handleOut: Offset(10, 20)),
            BezierPoint(point: Offset(100, 100), handleIn: Offset(-10, -20)),
          ],
          penHoverPosition: Offset(150, 120),
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(800, 600));
        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      },
    );

    test('CanvasPainter renders a right-angle trigger on selected routes', () {
      const edge = CanvasEdge(
        id: 'right-angle-trigger',
        sourcePoint: Offset(40, 40),
        targetPoint: Offset(200, 120),
        waypoints: [Offset(100, 40), Offset(100, 120)],
      );
      const painter = CanvasPainter(
        nodes: [],
        edges: [edge],
        viewport: Viewport(),
        selectedNodeIds: {'right-angle-trigger'},
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 200));
      final picture = recorder.endRecording();

      expect(picture, isNotNull);
    });

    test('ActiveBrushConfigNotifier updates stroke properties properly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(activeBrushConfigProvider).brushType,
        BrushType.ink,
      );
      container
          .read(activeBrushConfigProvider.notifier)
          .setBrushType(BrushType.marker);
      expect(
        container.read(activeBrushConfigProvider).brushType,
        BrushType.marker,
      );

      container.read(activeBrushConfigProvider.notifier).setStrokeWidth(8.0);
      expect(container.read(activeBrushConfigProvider).strokeWidth, 8.0);

      container.read(activeBrushConfigProvider.notifier).setStrokeWidth(0.5);
      expect(
        container.read(activeBrushConfigProvider).strokeWidth,
        minBrushWidth,
      );

      container.read(activeBrushConfigProvider.notifier).setStrokeWidth(120);
      expect(
        container.read(activeBrushConfigProvider).strokeWidth,
        maxBrushWidth,
      );

      container.read(activeBrushConfigProvider.notifier).setStrokeWidth(12.5);
      expect(container.read(activeBrushConfigProvider).strokeWidth, 12.5);
    });

    test(
      'ActiveBrushConfigNotifier persists and restores brush color',
      () async {
        final first = ActiveBrushConfigNotifier();
        addTearDown(first.dispose);
        await first.ready;

        const color = Color(0xCC123456);
        await first.setColor(color);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('canvas_brush_color'), color.toARGB32());

        final restored = ActiveBrushConfigNotifier();
        addTearDown(restored.dispose);
        await restored.ready;

        expect(restored.state.color, color);
      },
    );
  });
}
