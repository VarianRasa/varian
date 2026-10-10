import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  test(
    'composite PNG includes visible overlays and preserves dimensions',
    () async {
      final payload = DrawingPaperPayload(
        pixelWidth: 64,
        pixelHeight: 48,
        paperColor: Colors.white,
        layers: const [
          DrawingLayer(
            id: 'child',
            name: 'Hidden child',
            parentFolderId: 'folder',
            shapes: [
              VectorShapeObject(
                id: 'hidden_shape',
                kind: ShapeKind.rectangle,
                points: [Offset(28, 8), Offset(44, 24)],
                fill: Color(0xFF00FF00),
                stroke: Colors.transparent,
              ),
            ],
          ),
          DrawingLayer(
            id: 'folder',
            name: 'Hidden folder',
            type: LayerType.folder,
            visible: false,
          ),
          DrawingLayer(
            id: 'visible',
            name: 'Visible shape',
            shapes: [
              VectorShapeObject(
                id: 'visible_shape',
                kind: ShapeKind.rectangle,
                points: [Offset(8, 8), Offset(24, 24)],
                fill: Color(0xFFFF0000),
                stroke: Colors.transparent,
              ),
            ],
          ),
        ],
        mangaStructure: const MangaStructure(
          panels: [
            MangaPanelCut(
              id: 'panel',
              rect: Rect.fromLTWH(2, 2, 56, 42),
              backgroundColor: Colors.transparent,
            ),
          ],
        ),
      );

      final bytes = await DrawingPaperRenderer.renderPng(
        payload,
        maxDimension: null,
      );
      expect(bytes, isNotNull);

      final codec = await ui.instantiateImageCodec(bytes!);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      expect(image.width, 64);
      expect(image.height, 48);
      expect(_pixel(raw!, image.width, 12, 12), const Color(0xFFFF0000));
      expect(_pixel(raw, image.width, 32, 16), Colors.white);

      image.dispose();
      codec.dispose();
    },
  );

  test('workspace preview composes adjacent paper tiles', () {
    final payload = DrawingPaperPayload(
      pixelWidth: 4,
      pixelHeight: 4,
      paperColor: Colors.white,
      layers: const [
        DrawingLayer(
          id: 'root-layer',
          name: 'Root',
          strokes: [
            DrawingStroke(
              id: 'root-stroke',
              brush: StudioBrushCategory.gPen,
              color: Colors.red,
              size: 2,
              opacity: 1,
              points: [
                DrawingStrokePoint(x: 0, y: 1),
                DrawingStrokePoint(x: 3, y: 1),
              ],
            ),
          ],
        ),
      ],
      studioPages: [
        DrawingPaperPage(
          id: 'right-page',
          position: const Offset(4, 0),
          payload: DrawingPaperPayload(
            pixelWidth: 4,
            pixelHeight: 4,
            paperColor: Colors.white,
            layers: const [
              DrawingLayer(
                id: 'child-layer',
                name: 'Child',
                strokes: [
                  DrawingStroke(
                    id: 'child-stroke',
                    brush: StudioBrushCategory.gPen,
                    color: Colors.blue,
                    size: 2,
                    opacity: 1,
                    points: [
                      DrawingStrokePoint(x: 0, y: 1),
                      DrawingStrokePoint(x: 3, y: 1),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final preview = DrawingPaperRenderer.buildWorkspacePreview(
      payload,
      maxDimension: null,
    );

    expect(preview.surface.width, 8);
    expect(preview.surface.height, 4);
    expect(
      preview.surface.sample(const Offset(1, 1)).toARGB32(),
      Colors.red.toARGB32(),
    );
    expect(
      preview.surface.sample(const Offset(5, 1)).toARGB32(),
      Colors.blue.toARGB32(),
    );
  });

  test('workspace preview keeps child raster edits inside child tile', () {
    final payload = DrawingPaperPayload(
      pixelWidth: 4,
      pixelHeight: 4,
      paperColor: Colors.white,
      layers: const [DrawingLayer(id: 'root-layer', name: 'Root')],
      studioPages: [
        DrawingPaperPage(
          id: 'child-page',
          position: const Offset(4, 0),
          payload: DrawingPaperPayload(
            pixelWidth: 4,
            pixelHeight: 4,
            paperColor: Colors.white,
            layers: const [DrawingLayer(id: 'child-layer', name: 'Child')],
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

    final preview = DrawingPaperRenderer.buildWorkspacePreview(
      payload,
      maxDimension: null,
    );

    expect(
      preview.surface.sample(const Offset(1, 1)).toARGB32(),
      Colors.white.toARGB32(),
    );
    expect(
      preview.surface.sample(const Offset(5, 1)).toARGB32(),
      Colors.blue.toARGB32(),
    );
  });

  test(
    'Drawing Paper export supports bounded previews and full resolution',
    () async {
      final payload = DrawingPaperPayload(pixelWidth: 1200, pixelHeight: 600);

      final preview = await ExportService.exportDrawingPaperPng(
        payload,
        fullResolution: false,
      );
      final full = await ExportService.exportDrawingPaperPng(
        payload,
        fullResolution: true,
      );

      expect(await _dimensions(preview!), (1024, 512));
      expect(await _dimensions(full!), (1200, 600));
    },
  );
}

Future<(int, int)> _dimensions(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final dimensions = (image.width, image.height);
  image.dispose();
  codec.dispose();
  return dimensions;
}

Color _pixel(ByteData data, int width, int x, int y) {
  final index = (y * width + x) * 4;
  return Color.fromARGB(
    data.getUint8(index + 3),
    data.getUint8(index),
    data.getUint8(index + 1),
    data.getUint8(index + 2),
  );
}
