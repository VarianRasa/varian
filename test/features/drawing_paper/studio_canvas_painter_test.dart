import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/presentation/studio/painters/studio_canvas_painter.dart';

void main() {
  test(
    'renders regular strokes as vector content after raster decode',
    () async {
      final payload = DrawingPaperPayload(
        pixelWidth: 32,
        pixelHeight: 32,
        paperColor: Colors.white,
        layers: const [
          DrawingLayer(
            id: 'layer_1',
            name: 'Layer',
            strokes: [
              DrawingStroke(
                id: 'stroke_1',
                brush: StudioBrushCategory.gPen,
                color: Colors.black,
                size: 6,
                opacity: 1,
                points: [
                  DrawingStrokePoint(x: 4, y: 4),
                  DrawingStrokePoint(x: 28, y: 28),
                ],
              ),
            ],
          ),
        ],
      );
      final decodedRaster = await _solidImage(32, 32, Colors.red);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      StudioCanvasPainter(
        payload: payload,
        rasterImage: decodedRaster,
        canvasPixelSize: payload.pixelSize,
        applyTransform: false,
      ).paint(canvas, payload.pixelSize);

      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 32);
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      expect(_pixel(raw!, 32, 28, 4), Colors.white);
      expect(_pixel(raw, 32, 16, 16), Colors.black);

      image.dispose();
      decodedRaster.dispose();
      picture.dispose();
    },
  );
}

Future<ui.Image> _solidImage(int width, int height, Color color) {
  final argb = color.toARGB32();
  final pixels = Uint8List(width * height * 4);
  for (int i = 0; i < width * height; i++) {
    final offset = i * 4;
    pixels[offset] = (argb >> 16) & 0xff;
    pixels[offset + 1] = (argb >> 8) & 0xff;
    pixels[offset + 2] = argb & 0xff;
    pixels[offset + 3] = (argb >> 24) & 0xff;
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Color _pixel(ByteData data, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}
