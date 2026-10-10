import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/viewport.dart';

void main() {
  group('Document & Node Serialization Tests', () {
    test('CanvasNode serialize and deserialize correctly for all 8 types', () {
      final textNode = CanvasNode(
        id: 'node_1',
        type: NodeType.text,
        x: 100,
        y: 150,
        width: 200,
        height: 50,
        payload: TextPayload(text: 'Hello World', fontSize: 24),
      );

      final shapeNode = CanvasNode(
        id: 'node_2',
        type: NodeType.rectangle,
        x: 300,
        y: 400,
        width: 150,
        height: 150,
        variantOfNodeId: 'source-node',
        payload: ShapePayload(fill: const Color(0xFF10B981)),
      );

      final stickyNode = CanvasNode(
        id: 'node_3',
        type: NodeType.stickyNote,
        x: 500,
        y: 200,
        width: 120,
        height: 120,
        payload: StickyNotePayload(text: 'Remember to check MVP'),
      );

      final doc = CanvasDocument(
        projectId: 'test_project',
        nodes: [textNode, shapeNode, stickyNode],
        viewport: const Viewport(x: 10, y: 20, zoom: 1.5),
        navigation: const {'schemaVersion': 2, 'activePageId': 'page-1'},
        updatedAt: DateTime.now(),
      );

      final json = doc.toJson();
      final deserialized = CanvasDocument.fromJson(json);

      expect(deserialized.projectId, 'test_project');
      expect(deserialized.nodes.length, 3);
      expect(deserialized.nodes[0].type, NodeType.text);
      expect(
        (deserialized.nodes[0].payload as TextPayload).text,
        'Hello World',
      );
      expect(deserialized.nodes[1].type, NodeType.rectangle);
      expect(deserialized.nodes[1].variantOfNodeId, 'source-node');
      expect(deserialized.viewport.zoom, 1.5);
      expect(deserialized.navigation['activePageId'], 'page-1');
    });

    test('legacy node JSON defaults variant provenance to null', () {
      final node = CanvasNode.fromJson({
        'id': 'legacy',
        'type': 'rectangle',
        'x': 0,
        'y': 0,
        'width': 100,
        'height': 100,
        'payload': <String, dynamic>{},
      });

      expect(node.variantOfNodeId, isNull);
    });

    test('persists stable Storage metadata without MP4 bytes', () {
      final node = CanvasNode(
        id: 'video',
        type: NodeType.videoCard,
        x: 0,
        y: 0,
        width: 200,
        height: 120,
        payload: VideoPayload(
          storagePath: 'test_project/videos/artifact-1.mp4',
          videoArtifactReference: 'varian-video://artifact-1',
          videoUrl: 'blob:https://example.test/runtime-url',
        ),
      );
      final json = node.toJson();
      final restored = CanvasNode.fromJson(json).payload as VideoPayload;

      expect(json.toString(), isNot(contains('Uint8List')));
      expect(restored.storagePath, 'test_project/videos/artifact-1.mp4');
      expect(restored.videoArtifactReference, 'varian-video://artifact-1');
      expect(restored.videoUrl, isNull);
    });

    test(
      'keeps stable Storage references when temporary runtime sources are omitted',
      () {
        final json = VideoPayload(
          storagePath: 'test_project/videos/artifact-2.mp4',
          videoArtifactReference: 'varian-video://artifact-2',
          videoUrl: 'blob:https://example.test/runtime-url',
          videoPath: 'C:\\temp\\video.mp4',
          isTemporary: true,
        ).toJson();

        expect(json['storagePath'], 'test_project/videos/artifact-2.mp4');
        expect(json['videoArtifactReference'], 'varian-video://artifact-2');
        expect(json['videoUrl'], isNull);
        expect(json['videoPath'], isNull);
      },
    );

    test('omits runtime audio sources and non-durable timeline artifacts', () {
      final payload = AudioPayload(
        audioPath: r'C:\\temp\\voice.mp3',
        audioUrl: 'https://storage.example.test/signed.mp3?token=secret',
        mediaTimeline: const MediaTimeline(
          artifacts: MediaArtifactManifest(
            items: [
              MediaArtifact(
                kind: MediaArtifactKind.proxy,
                reference: 'varian-media://cache/checksum/proxy',
              ),
            ],
          ),
        ),
      );

      final json = payload.toPersistenceJson();

      expect(json['audioPath'], isNull);
      expect(json['audioUrl'], isNull);
      expect(json['mediaTimeline']['artifacts']['items'], isEmpty);
    });

    test(
      'durable document metadata does not retain runtime artifact values',
      () {
        final document = CanvasDocument(
          projectId: 'metadata-boundary',
          metadata: {
            'localPath': r'C:\\Users\\tester\\image.png',
            'signedUrl': 'https://storage.example.test/image.png?token=secret',
            'inlineBytes': 'data:image/png;base64,AAECAw==',
            'safeLabel': 'Reference image',
          },
          updatedAt: DateTime.utc(2026, 9, 26),
        );

        final metadata =
            document.toPersistenceJson()['metadata'] as Map<String, dynamic>;

        expect(metadata, {'safeLabel': 'Reference image'});
      },
    );

    test('annotated images and drawing paper omit runtime image sources', () {
      final annotated = AnnotatedImagePayload(
        assetId: 'annotated-asset',
        imageArtifactReference: 'blob:https://example.test/runtime',
        imagePath: r'C:\\temp\\annotated.png',
      );
      final drawingPaper = DrawingPaperPayload(
        compositePreviewRef: 'data:image/png;base64,AAECAw==',
        referenceConfig: const ReferenceImageConfig(
          storagePath: 'project/reference/source.png',
          localPath: r'C:\\temp\\reference.png',
          url: 'https://storage.example.test/reference.png?token=secret',
        ),
      );

      final annotatedJson = annotated.toPersistenceJson();
      final drawingJson = drawingPaper.toPersistenceJson();
      final referenceJson =
          drawingJson['referenceConfig'] as Map<String, dynamic>;

      expect(annotatedJson['imageArtifactReference'], isNull);
      expect(annotatedJson['imagePath'], isNull);
      expect(drawingJson['compositePreviewRef'], isNull);
      expect(referenceJson['storagePath'], 'project/reference/source.png');
      expect(referenceJson['localPath'], isNull);
      expect(referenceJson['url'], isNull);
    });
  });
}
