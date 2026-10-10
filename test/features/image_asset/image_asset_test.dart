import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImagePayload Model & Serialization Tests', () {
    test('normalizes crop selections and converts image coordinates', () {
      const imageSize = Size(1000, 500);
      final selection = ImageCropSelection.fromImageRect(
        const Rect.fromLTWH(100, 50, 700, 300),
        imageSize,
      );

      expect(selection.x, 0.1);
      expect(selection.y, 0.1);
      expect(selection.width, 0.7);
      expect(selection.height, 0.6);
      expect(
        selection.toImageRect(imageSize),
        const Rect.fromLTWH(100, 50, 700, 300),
      );
    });

    test('clamps crop selections that extend beyond the source image', () {
      final selection = const ImageCropSelection(
        x: -0.2,
        y: 0.8,
        width: 1.5,
        height: 0.8,
      ).normalized;

      expect(selection.x, 0.0);
      expect(selection.y, 0.8);
      expect(selection.width, 1.0);
      expect(selection.height, closeTo(0.2, 0.000001));
    });

    test('default initialization has proper defaults', () {
      final payload = ImagePayload();
      expect(payload.fit, 'cover');
      expect(payload.cornerRadius, 0.0);
      expect(payload.grayscale, false);
      expect(payload.sepia, false);
      expect(payload.invert, false);
      expect(payload.brightness, 0.0);
      expect(payload.contrast, 1.0);
      expect(payload.blur, 0.0);
      expect(payload.flipHorizontal, false);
      expect(payload.flipVertical, false);
    });

    test(
      'serializes and deserializes filters, styling and corners correctly',
      () {
        final payload = ImagePayload(
          assetId: 'banner.png',
          localPath: '/tmp/test.png',
          url: 'https://example.com/test.png',
          fit: 'contain',
          caption: 'Hero Banner',
          cornerRadius: 12.0,
          independentCorners: true,
          topLeftRadius: 10,
          topRightRadius: 20,
          bottomRightRadius: 30,
          bottomLeftRadius: 40,
          strokeColor: const Color(0xFFEF4444),
          strokeWidth: 3.5,
          strokeStyle: StrokeStyle.dashed,
          hasShadow: true,
          shadowColor: const Color(0xFF000000),
          shadowBlur: 16.0,
          grayscale: true,
          sepia: false,
          invert: true,
          brightness: 0.25,
          contrast: 1.5,
          blur: 4.0,
          flipHorizontal: true,
          flipVertical: false,
        );

        final json = payload.toJson();
        final parsed = ImagePayload.fromJson(json);

        expect(parsed.assetId, 'banner.png');
        // Runtime paths and delivery URLs are hydrated outside the durable
        // document envelope and must not survive this round trip.
        expect(parsed.localPath, isNull);
        expect(parsed.url, isNull);
        expect(parsed.fit, 'contain');
        expect(parsed.caption, 'Hero Banner');
        expect(parsed.independentCorners, true);
        expect(parsed.topLeftRadius, 10.0);
        expect(parsed.topRightRadius, 20.0);
        expect(parsed.bottomRightRadius, 30.0);
        expect(parsed.bottomLeftRadius, 40.0);
        expect(parsed.strokeColor, const Color(0xFFEF4444));
        expect(parsed.strokeWidth, 3.5);
        expect(parsed.strokeStyle, StrokeStyle.dashed);
        expect(parsed.hasShadow, true);
        expect(parsed.grayscale, true);
        expect(parsed.invert, true);
        expect(parsed.brightness, 0.25);
        expect(parsed.contrast, 1.5);
        expect(parsed.blur, 4.0);
        expect(parsed.flipHorizontal, true);
        expect(parsed.flipVertical, false);
      },
    );

    test('clone and copyWith maintain all image properties', () {
      final original = ImagePayload(
        caption: 'Design Concept',
        fit: 'fill',
        cornerRadius: 15.0,
        grayscale: true,
      );

      final cloned = original.clone();
      expect(cloned.caption, 'Design Concept');
      expect(cloned.fit, 'fill');
      expect(cloned.cornerRadius, 15.0);
      expect(cloned.grayscale, true);

      final updated = original.copyWith(caption: 'Updated Title', sepia: true);
      expect(updated.caption, 'Updated Title');
      expect(updated.sepia, true);
      expect(updated.fit, 'fill');
    });

    test('round-trips focal point, adjustment stack, and background mask', () {
      final payload = ImagePayload(
        cropX: 0.1,
        cropY: 0.2,
        cropWidth: 0.65,
        cropHeight: 0.7,
        focalPointX: 0.8,
        focalPointY: 0.25,
        adjustments: const [
          ImageAdjustment(
            id: 'sat-1',
            type: ImageAdjustmentType.saturation,
            amount: 1.35,
          ),
          ImageAdjustment(
            id: 'blur-1',
            type: ImageAdjustmentType.blur,
            amount: 3.0,
            enabled: false,
          ),
        ],
        backgroundMask: const ImageMask(
          assetId: 'mask.png',
          imageArtifactReference: 'varian-image://mask-fixture',
          url: 'https://example.com/mask.png',
          mode: ImageMaskMode.luminance,
          opacity: 0.85,
        ),
      );

      final restored = ImagePayload.fromJson(payload.toJson());

      expect(restored.cropX, 0.1);
      expect(restored.cropY, 0.2);
      expect(restored.cropWidth, 0.65);
      expect(restored.cropHeight, 0.7);
      expect(restored.focalPointX, 0.8);
      expect(restored.focalPointY, 0.25);
      expect(restored.adjustments, hasLength(2));
      expect(restored.adjustments.first.type, ImageAdjustmentType.saturation);
      expect(restored.adjustments.first.amount, 1.35);
      expect(restored.adjustments.last.enabled, isFalse);
      expect(restored.backgroundMask?.mode, ImageMaskMode.luminance);
      expect(restored.backgroundMask?.opacity, 0.85);
      expect(restored.backgroundMask?.sourceKey, 'varian-image://mask-fixture');
      expect(restored.backgroundMask?.url, isNull);
    });

    test('durable serialization keeps only opaque image references', () {
      final payload = ImagePayload(
        imageArtifactReference: 'varian-image://image-fixture',
        storagePath: 'project-1/images/source.png',
        localPath: r'C:\\Users\\user\\image.png',
        url: 'https://cdn.example.com/image.png?token=runtime',
      );

      final json = payload.toJson();

      expect(json['imageArtifactReference'], 'varian-image://image-fixture');
      expect(json['storagePath'], 'project-1/images/source.png');
      expect(json.containsKey('localPath'), isFalse);
      expect(json.containsKey('url'), isFalse);
    });

    test('clone deep-copies image editing metadata', () {
      final original = ImagePayload(
        adjustments: const [
          ImageAdjustment(
            id: 'exposure-1',
            type: ImageAdjustmentType.exposure,
            amount: 0.5,
          ),
        ],
        backgroundMask: const ImageMask(assetId: 'mask'),
      );

      final cloned = original.clone();

      expect(cloned.adjustments, isNot(same(original.adjustments)));
      expect(cloned.adjustments.single.id, 'exposure-1');
      expect(cloned.backgroundMask, isNot(same(original.backgroundMask)));
      expect(cloned.backgroundMask?.assetId, 'mask');
    });
  });

  group('NodePainter Image Rendering Tests', () {
    test('renders placeholder without crashing when image is not loaded', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final node = CanvasNode(
        id: 'img_test_1',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 300,
        height: 200,
        payload: ImagePayload(
          caption: 'Sample Image',
          cornerRadius: 8.0,
          strokeColor: Colors.blue,
          strokeWidth: 2.0,
        ),
      );

      expect(() => NodePainter.paint(canvas, node), returnsNormally);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test(
      'renders loaded image adjustments and mask with degenerate crop',
      () async {
        final source = await _solidImage(const Color(0xFF3366CC));
        final mask = await _solidImage(const Color(0xFFFFFFFF));
        final cache = CanvasImageCache.instance;
        cache.clear();
        cache.cacheImage('source', source);
        cache.cacheImage('mask', mask);

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final node = CanvasNode(
          id: 'img_test_loaded',
          type: NodeType.image,
          x: 0,
          y: 0,
          width: 300,
          height: 200,
          payload: ImagePayload(
            url: 'source',
            cropX: 1.0,
            cropY: 1.0,
            cropWidth: 0.0,
            cropHeight: 0.0,
            focalPointX: 0.9,
            focalPointY: 0.1,
            adjustments: const [
              ImageAdjustment(
                id: 'brightness',
                type: ImageAdjustmentType.brightness,
                amount: 0.2,
              ),
              ImageAdjustment(
                id: 'blur',
                type: ImageAdjustmentType.blur,
                amount: 2.0,
              ),
            ],
            backgroundMask: const ImageMask(
              url: 'mask',
              mode: ImageMaskMode.luminance,
              opacity: 0.8,
            ),
          ),
        );

        expect(() => NodePainter.paint(canvas, node), returnsNormally);
        final picture = recorder.endRecording();
        expect(picture, isNotNull);
        picture.dispose();
        // CanvasImageCache owns images after cacheImage and disposes them when
        // the cache is cleared. Do not dispose source or mask a second time.
        cache.clear();
      },
    );
  });
}

Future<ui.Image> _solidImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  picture.dispose();
  return image;
}
