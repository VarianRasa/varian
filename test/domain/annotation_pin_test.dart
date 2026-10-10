import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  group('AnnotatedImage & ImageAnnotationPin Model Tests', () {
    test('Pin model serialization and copyWith', () {
      final pin = ImageAnnotationPin(
        id: 'pin-1',
        position: const Offset(50, 60),
        text: 'Fix typo on header',
        author: 'Alice',
        createdAt: DateTime(2025, 1, 1, 10, 0),
        status: AnnotationPinStatus.issue,
        color: const Color(0xFFEF4444),
        isResolved: false,
      );

      final json = pin.toJson();
      expect(json['id'], 'pin-1');
      expect(json['x'], 50.0);
      expect(json['y'], 60.0);
      expect(json['text'], 'Fix typo on header');
      expect(json['author'], 'Alice');
      expect(json['status'], 'issue');
      expect(json['isResolved'], false);

      final restored = ImageAnnotationPin.fromJson(json);
      expect(restored.id, pin.id);
      expect(restored.position, pin.position);
      expect(restored.text, pin.text);
      expect(restored.author, pin.author);
      expect(restored.status, AnnotationPinStatus.issue);
      expect(restored.isResolved, false);

      final updated = pin.copyWith(
        isResolved: true,
        status: AnnotationPinStatus.resolved,
      );
      expect(updated.isResolved, true);
      expect(updated.status, AnnotationPinStatus.resolved);
    });

    test('AnnotatedImagePayload serialization and defaults', () {
      final payload = AnnotatedImagePayload(
        assetId: 'annotation-fixture',
        imageArtifactReference: 'varian-image://annotation-fixture',
        imagePath: 'assets/demo.png',
        showCornerBadge: true,
        showLeaderLines: true,
        pins: [
          ImageAnnotationPin(
            id: 'pin-1',
            position: const Offset(20, 30),
            text: 'Check contrast',
          ),
        ],
      );

      final json = payload.toJson();
      expect(json['assetId'], 'annotation-fixture');
      expect(
        json['imageArtifactReference'],
        'varian-image://annotation-fixture',
      );
      expect(json['imagePath'], 'assets/demo.png');
      expect(json['showCornerBadge'], true);
      expect(json['showLeaderLines'], true);
      expect((json['pins'] as List).length, 1);

      final restored = AnnotatedImagePayload.fromJson(json);
      expect(restored.assetId, 'annotation-fixture');
      expect(
        restored.imageArtifactReference,
        'varian-image://annotation-fixture',
      );
      expect(restored.imagePath, 'assets/demo.png');
      expect(restored.showCornerBadge, true);
      expect(restored.pins.length, 1);
      expect(restored.pins.first.text, 'Check contrast');
    });

    test(
      'NodePainter paints annotated image with badge and pins without crash',
      () {
        final node = CanvasNode(
          id: 'node-ann-1',
          type: NodeType.annotatedImage,
          x: 0,
          y: 0,
          width: 300,
          height: 200,
          payload: AnnotatedImagePayload(
            showCornerBadge: true,
            showLeaderLines: true,
            pins: [
              ImageAnnotationPin(
                id: 'p1',
                position: const Offset(40, 50),
                text: 'Needs adjustment',
                status: AnnotationPinStatus.issue,
              ),
              ImageAnnotationPin(
                id: 'p2',
                position: const Offset(120, 80),
                text: 'Approved section',
                isResolved: true,
              ),
            ],
          ),
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        expect(() => NodePainter.paint(canvas, node), returnsNormally);
        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      },
    );

    test('ExportService generates SVG with corner badge and styled pins', () {
      final node = CanvasNode(
        id: 'node-ann-2',
        type: NodeType.annotatedImage,
        x: 10,
        y: 10,
        width: 400,
        height: 300,
        payload: AnnotatedImagePayload(
          showCornerBadge: true,
          pins: [
            ImageAnnotationPin(
              id: 'p1',
              position: const Offset(50, 50),
              text: 'Issue here',
              status: AnnotationPinStatus.issue,
            ),
          ],
        ),
      );

      final doc = CanvasDocument(
        projectId: 'project_ann',
        nodes: [node],
        edges: [],
        viewport: const Viewport(x: 0, y: 0, zoom: 1),
        updatedAt: DateTime.now(),
      );

      final svg = ExportService.exportVectorSvg(doc);
      expect(svg, contains('<rect'));
      expect(svg, contains('<circle'));
      expect(svg, contains('PIN 1'));
    });
  });
}
