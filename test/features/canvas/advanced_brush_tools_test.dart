import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/utils/brush_eraser_engine.dart';
import 'package:varian/features/canvas/utils/brush_path_smoother.dart';

void main() {
  group('BrushPathSmoother tests', () {
    test('buildSmoothPath handles empty, single, and multiple points', () {
      final emptyPath = BrushPathSmoother.buildSmoothPath([]);
      expect(emptyPath.getBounds(), Rect.zero);

      final singlePath = BrushPathSmoother.buildSmoothPath([
        const Offset(10, 10),
      ]);
      expect(singlePath.getBounds().isEmpty, false);

      final pts = [
        const Offset(0, 0),
        const Offset(10, 20),
        const Offset(20, 10),
        const Offset(30, 30),
      ];
      final smoothPath = BrushPathSmoother.buildSmoothPath(pts);
      final bounds = smoothPath.getBounds();
      expect(bounds.left, 0.0);
      expect(bounds.right, 30.0);
    });

    test('buildLinearPath creates straight segments', () {
      final pts = [const Offset(0, 0), const Offset(50, 50)];
      final linearPath = BrushPathSmoother.buildLinearPath(pts);
      expect(linearPath.getBounds(), const Rect.fromLTRB(0, 0, 50, 50));
    });
  });

  group('BrushEraserEngine tests', () {
    test('intersectsDrawingNode detects intersection with line segments', () {
      final drawingNode = CanvasNode(
        id: 'stroke_1',
        type: NodeType.drawing,
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        payload: DrawingPayload(
          points: [
            const Offset(0, 0),
            const Offset(50, 50),
            const Offset(100, 100),
          ],
          strokeWidth: 4.0,
        ),
      );

      // Hit directly near middle of stroke (World Pos: 150, 150)
      final hit = BrushEraserEngine.intersectsDrawingNode(
        drawingNode,
        const Offset(150, 150),
        8.0,
      );
      expect(hit, isTrue);

      // Far away point should not hit
      final miss = BrushEraserEngine.intersectsDrawingNode(
        drawingNode,
        const Offset(400, 400),
        8.0,
      );
      expect(miss, isFalse);
    });

    test('applyCutout adds precise circular cutout masks', () {
      final drawingNode = CanvasNode(
        id: 'stroke_cut',
        type: NodeType.drawing,
        x: 0,
        y: 0,
        width: 100,
        height: 10,
        payload: DrawingPayload(
          points: [
            const Offset(0, 0),
            const Offset(50, 0),
            const Offset(100, 0),
          ],
          strokeWidth: 2.0,
        ),
      );

      final result = BrushEraserEngine.applyCutout(
        drawingNode,
        const Offset(50, 0),
        4.0,
      );

      expect(result, isNotNull);
      final payload = result!.payload as DrawingPayload;
      expect(payload.cutouts.length, 1);
      expect(payload.cutouts.first.position, const Offset(50, 0));
      expect(payload.cutouts.first.radius, 4.0);
    });
  });
}
