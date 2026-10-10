import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_persistence.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';

void main() {
  test('drawing paper node preview paints persisted overlays', () {
    final payload = DrawingPaperPayload(
      pixelWidth: 100,
      pixelHeight: 100,
      layers: [
        const DrawingLayer(
          id: 'layer_1',
          name: 'Ink',
          shapes: [
            VectorShapeObject(
              id: 'shape_1',
              kind: ShapeKind.rectangle,
              points: [Offset(8, 8), Offset(42, 34)],
              fill: Color(0xFFFF0000),
            ),
          ],
          texts: [TextObjectData(id: 'text_1', text: 'Panel')],
        ),
      ],
      mangaStructure: const MangaStructure(
        panels: [
          MangaPanelCut(id: 'panel_1', rect: Rect.fromLTWH(4, 4, 80, 80)),
        ],
      ),
    );
    final node = CanvasNode(
      id: 'paper_1',
      type: NodeType.drawingPaper,
      x: 0,
      y: 0,
      width: 200,
      height: 200,
      payload: payload,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    NodePainter.paint(canvas, node);

    final picture = recorder.endRecording();
    expect(picture, isNotNull);
    picture.dispose();
  });

  test('drawing paper node preview uses persisted raster content', () async {
    final payload = DrawingPaperPayload(
      pixelWidth: 10,
      pixelHeight: 10,
      paperColor: Colors.white,
      layers: const [DrawingLayer(id: 'root', name: 'Root')],
      rasterOperations: const [
        RasterEditOperation(
          id: 'root-fill',
          kind: RasterEditKind.bucketFill,
          seedPoint: Offset(2, 2),
          color: Colors.blue,
        ),
      ],
    );
    final reference = DrawingPaperPersistence.previewReferenceForPayload(
      payload,
      nodeId: 'paper',
    );
    final bytes = await DrawingPaperRenderer.renderPng(
      payload,
      maxDimension: null,
    );
    expect(bytes, isNotNull);

    CanvasImageCache.instance.clear();
    addTearDown(CanvasImageCache.instance.clear);
    await CanvasImageCache.instance.decodeAndCacheBytes(reference, bytes!);

    final node = CanvasNode(
      id: 'paper',
      type: NodeType.drawingPaper,
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      payload: payload.copyWith(compositePreviewRef: reference),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    NodePainter.paint(canvas, node);

    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 10);
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(_pixel(raw!, image.width, 2, 2).toARGB32(), Colors.blue.toARGB32());

    image.dispose();
    picture.dispose();
  });

  test('drawing paper node preview paints embedded workspace pages', () async {
    final payload = DrawingPaperPayload(
      pixelWidth: 10,
      pixelHeight: 10,
      paperColor: Colors.white,
      layers: const [DrawingLayer(id: 'root', name: 'Root')],
      studioPages: [
        DrawingPaperPage(
          id: 'right-page',
          position: const Offset(10, 0),
          payload: DrawingPaperPayload(
            pixelWidth: 10,
            pixelHeight: 10,
            paperColor: Colors.white,
            layers: const [
              DrawingLayer(
                id: 'child',
                name: 'Child',
                shapes: [
                  VectorShapeObject(
                    id: 'child-shape',
                    kind: ShapeKind.rectangle,
                    points: [Offset(1, 1), Offset(9, 9)],
                    fill: Colors.blue,
                    stroke: Colors.transparent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final node = CanvasNode(
      id: 'workspace-paper',
      type: NodeType.drawingPaper,
      x: 0,
      y: 0,
      width: 20,
      height: 10,
      payload: payload,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    NodePainter.paint(canvas, node);

    final picture = recorder.endRecording();
    final image = await picture.toImage(20, 10);
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(_pixel(raw!, image.width, 15, 5).toARGB32(), Colors.blue.toARGB32());

    image.dispose();
    picture.dispose();
  });

  test(
    'drawing paper node preview uses persisted workspace raster content',
    () async {
      final payload = DrawingPaperPayload(
        pixelWidth: 10,
        pixelHeight: 10,
        paperColor: Colors.white,
        layers: const [DrawingLayer(id: 'root', name: 'Root')],
        studioPages: [
          DrawingPaperPage(
            id: 'right-page',
            position: const Offset(10, 0),
            payload: DrawingPaperPayload(
              pixelWidth: 10,
              pixelHeight: 10,
              paperColor: Colors.white,
              layers: const [DrawingLayer(id: 'child', name: 'Child')],
              rasterOperations: const [
                RasterEditOperation(
                  id: 'child-fill',
                  kind: RasterEditKind.bucketFill,
                  seedPoint: Offset(2, 2),
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ],
      );
      final reference = DrawingPaperPersistence.previewReferenceForPayload(
        payload,
        nodeId: 'workspace-paper',
      );
      final bytes = await DrawingPaperRenderer.renderPng(
        payload,
        maxDimension: null,
      );
      expect(bytes, isNotNull);

      CanvasImageCache.instance.clear();
      addTearDown(CanvasImageCache.instance.clear);
      await CanvasImageCache.instance.decodeAndCacheBytes(reference, bytes!);

      final node = CanvasNode(
        id: 'workspace-paper',
        type: NodeType.drawingPaper,
        x: 0,
        y: 0,
        width: 20,
        height: 10,
        payload: payload.copyWith(compositePreviewRef: reference),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      NodePainter.paint(canvas, node);

      final picture = recorder.endRecording();
      final image = await picture.toImage(20, 10);
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      expect(
        _pixel(raw!, image.width, 15, 5).toARGB32(),
        Colors.blue.toARGB32(),
      );

      image.dispose();
      picture.dispose();
    },
  );
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
