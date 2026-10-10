import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  group('SketchCard Feature & Serialization Tests', () {
    test('SketchCardPayload serialization and copyWith', () {
      final original = SketchCardPayload(
        title: 'App Architecture',
        strokes: [
          [const Offset(10, 10), const Offset(20, 20), const Offset(30, 15)],
          [const Offset(50, 60), const Offset(70, 80)],
        ],
        strokeColor: const Color(0xFF10B981),
        strokeWidth: 3.5,
        backgroundColor: const Color(0xFF111827),
        cardPattern: 'grid',
        smoothCurves: true,
      );

      final json = original.toJson();
      final restored = SketchCardPayload.fromJson(json);

      expect(restored.title, equals('App Architecture'));
      expect(restored.strokes.length, equals(2));
      expect(restored.strokes.first.length, equals(3));
      expect(restored.strokeColor, equals(const Color(0xFF10B981)));
      expect(restored.strokeWidth, equals(3.5));
      expect(restored.backgroundColor, equals(const Color(0xFF111827)));
      expect(restored.cardPattern, equals('grid'));
      expect(restored.smoothCurves, isTrue);

      final cloned = original.clone();
      expect(cloned.title, equals(original.title));
      expect(cloned.strokes.length, equals(original.strokes.length));

      final updated = original.copyWith(
        title: 'Updated Title',
        cardPattern: 'dots',
      );
      expect(updated.title, equals('Updated Title'));
      expect(updated.cardPattern, equals('dots'));
      expect(updated.strokeColor, equals(original.strokeColor));
    });

    test(
      'SketchCardPayload backward compatibility with legacy single-stroke array JSON',
      () {
        final legacyJson = {
          'title': 'Legacy Sketch',
          'strokes': [
            {'x': 12.0, 'y': 14.0},
            {'x': 25.0, 'y': 30.0},
          ],
        };

        final restored = SketchCardPayload.fromJson(legacyJson);
        expect(restored.title, equals('Legacy Sketch'));
        expect(restored.strokes.length, equals(1));
        expect(restored.strokes.first.length, equals(2));
        expect(restored.strokes.first[0], equals(const Offset(12.0, 14.0)));
      },
    );

    test('NodePainter paints SketchCard with patterns and smooth curves', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      final node = CanvasNode(
        id: 'sketch_1',
        type: NodeType.sketchCard,
        x: 100,
        y: 100,
        width: 240,
        height: 160,
        payload: SketchCardPayload(
          title: 'UI Mock',
          strokes: [
            [const Offset(10, 20), const Offset(30, 40), const Offset(50, 25)],
          ],
          cardPattern: 'dots',
          smoothCurves: true,
        ),
      );

      expect(() => NodePainter.paint(canvas, node), returnsNormally);

      final gridNode = node.copyWith(
        payload: (node.payload as SketchCardPayload).copyWith(
          cardPattern: 'grid',
          smoothCurves: false,
        ),
      );
      expect(() => NodePainter.paint(canvas, gridNode), returnsNormally);
    });

    test('ExportService generates SVG with SketchCard multi-strokes', () {
      final node = CanvasNode(
        id: 'sketch_svg_1',
        type: NodeType.sketchCard,
        x: 0,
        y: 0,
        width: 200,
        height: 150,
        payload: SketchCardPayload(
          title: 'Svg Test',
          strokes: [
            [const Offset(10, 10), const Offset(50, 50)],
          ],
        ),
      );

      final doc = CanvasDocument(
        projectId: 'project_1',
        nodes: [node],
        edges: [],
        viewport: const Viewport(x: 0, y: 0, zoom: 1),
        updatedAt: DateTime.now(),
      );

      final svg = ExportService.exportVectorSvg(doc);
      expect(svg, contains('Svg Test'));
      expect(svg, contains('path d="M 10.0 10.0 L 50.0 50.0 '));
    });
  });
}
