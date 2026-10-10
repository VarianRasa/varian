import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';
import 'package:varian/features/drawing_paper/domain/models/ruler_guide.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

void main() {
  test(
    'bucket fill is replayable and undoable through the studio notifier',
    () {
      final notifier = DrawingStudioNotifier(
        DrawingPaperPayload(
          pixelWidth: 32,
          pixelHeight: 32,
          paperColor: Colors.white,
        ),
      );

      final changed = notifier.applyRasterOperation(
        RasterEditOperation.bucketFill(
          seedPoint: const Offset(16, 16),
          color: Colors.red,
        ),
      );

      expect(changed, greaterThan(0));
      expect(
        notifier.state.rasterSurface!.sample(const Offset(16, 16)).toARGB32(),
        Colors.red.toARGB32(),
      );
      expect(notifier.state.payload.rasterOperations, hasLength(1));

      notifier.undo();
      expect(
        notifier.state.rasterSurface!.sample(const Offset(16, 16)).toARGB32(),
        Colors.white.toARGB32(),
      );

      notifier.redo();
      expect(
        notifier.state.rasterSurface!.sample(const Offset(16, 16)).toARGB32(),
        Colors.red.toARGB32(),
      );
    },
  );

  test('keeps the full document raster resolution for Focus Studio', () {
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(
        pixelWidth: 1200,
        pixelHeight: 600,
        paperColor: Colors.white,
      ),
    );

    expect(notifier.state.rasterPreviewScale, 1.0);
    expect(notifier.state.rasterSurface!.width, 1200);
    expect(notifier.state.rasterSurface!.height, 600);
  });

  test('editing a text object updates the existing layer object', () {
    const text = TextObjectData(id: 'text_1', text: 'Before');
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(
        pixelWidth: 32,
        pixelHeight: 32,
        layers: const [
          DrawingLayer(id: 'layer_1', name: 'Layer', texts: [text]),
        ],
      ),
    );

    notifier.updateTextObject(text.copyWith(text: 'After'));

    expect(notifier.state.payload.layers.single.texts.single.text, 'After');
    expect(notifier.state.undoCount, 1);
  });

  test('manga panels and rulers are undoable payload objects', () {
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(pixelWidth: 64, pixelHeight: 64),
    );

    notifier.addMangaPanel(
      const MangaPanelCut(id: 'panel_1', rect: Rect.fromLTWH(4, 6, 24, 30)),
    );
    expect(notifier.state.payload.mangaStructure!.panels, hasLength(1));
    expect(notifier.state.undoCount, 1);

    notifier.addRuler(
      const RulerGuide(
        id: 'ruler_1',
        type: RulerType.straight,
        origin: Offset(2, 2),
        target: Offset(40, 20),
      ),
    );
    expect(notifier.state.payload.rulers, hasLength(1));
    expect(notifier.state.undoCount, 2);

    notifier.undo();
    expect(notifier.state.payload.rulers, isEmpty);
    notifier.undo();
    expect(notifier.state.payload.mangaStructure, isNull);
  });

  test('speech balloon text can be edited without replacing the object', () {
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(pixelWidth: 64, pixelHeight: 64),
    );
    const balloon = SpeechBalloon(
      id: 'balloon_1',
      position: Offset(8, 8),
      size: Size(32, 20),
      tailTarget: Offset(16, 40),
    );

    notifier.addSpeechBalloon(balloon);
    notifier.updateSpeechBalloon(balloon.copyWith(text: 'Hello'));

    expect(
      notifier.state.payload.mangaStructure!.balloons.single.text,
      'Hello',
    );
    expect(notifier.state.undoCount, 2);
  });

  test('active straight ruler snaps committed stroke points', () {
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(pixelWidth: 64, pixelHeight: 64),
    );
    notifier.addRuler(
      const RulerGuide(
        id: 'ruler_1',
        type: RulerType.straight,
        origin: Offset(4, 4),
        target: Offset(40, 4),
      ),
    );

    notifier.addStrokeToActiveLayer(
      const DrawingStroke(
        id: 'stroke_1',
        brush: StudioBrushCategory.gPen,
        color: Colors.black,
        size: 4,
        opacity: 1,
        points: [
          DrawingStrokePoint(x: 8, y: 12),
          DrawingStrokePoint(x: 32, y: 20),
        ],
      ),
    );

    final points = notifier.state.payload.layers.single.strokes.single.points;
    expect(points[0].y, 4);
    expect(points[1].y, 4);
  });

  test('clear layer removes raster, shape, and text content', () {
    const layer = DrawingLayer(
      id: 'layer_1',
      name: 'Layer',
      strokes: [
        DrawingStroke(
          id: 'stroke_1',
          brush: StudioBrushCategory.gPen,
          color: Colors.black,
          size: 4,
          opacity: 1,
          points: [
            DrawingStrokePoint(x: 4, y: 4),
            DrawingStrokePoint(x: 12, y: 12),
          ],
        ),
      ],
      shapes: [
        VectorShapeObject(
          id: 'shape_1',
          kind: ShapeKind.rectangle,
          points: [Offset(2, 2), Offset(10, 10)],
        ),
      ],
      texts: [TextObjectData(id: 'text_1')],
    );
    const raster = RasterEditOperation(
      id: 'raster_1',
      kind: RasterEditKind.bucketFill,
      seedPoint: Offset(6, 6),
      color: Color(0xFF00FF00),
    );
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(
        pixelWidth: 64,
        pixelHeight: 64,
        layers: [layer],
        rasterOperations: [raster],
      ),
    );

    notifier.clearActiveLayer();

    final cleared = notifier.state.payload.layers.single;
    expect(cleared.strokes, isEmpty);
    expect(cleared.shapes, isEmpty);
    expect(cleared.texts, isEmpty);
    expect(notifier.state.payload.rasterOperations, isEmpty);
  });

  test('new layers created with a folder active are parented to it', () {
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(pixelWidth: 64, pixelHeight: 64),
    );

    notifier.addFolderLayer(name: 'Panels');
    final folderId = notifier.state.activeLayer!.id;
    notifier.addLayer(name: 'Ink');

    expect(notifier.state.activeLayer!.name, 'Ink');
    expect(notifier.state.activeLayer!.parentFolderId, folderId);
  });

  test('hidden folders hide their child raster content', () {
    const child = DrawingLayer(
      id: 'child',
      name: 'Ink',
      parentFolderId: 'folder',
      strokes: [
        DrawingStroke(
          id: 'stroke_1',
          brush: StudioBrushCategory.gPen,
          color: Colors.black,
          size: 4,
          opacity: 1,
          points: [
            DrawingStrokePoint(x: 8, y: 8),
            DrawingStrokePoint(x: 16, y: 16),
          ],
        ),
      ],
    );
    const folder = DrawingLayer(
      id: 'folder',
      name: 'Folder',
      type: LayerType.folder,
      visible: false,
    );
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(
        pixelWidth: 32,
        pixelHeight: 32,
        paperColor: Colors.white,
        layers: [child, folder],
      ),
    );

    expect(
      notifier.state.rasterSurface!.sample(const Offset(8, 8)).toARGB32(),
      Colors.white.toARGB32(),
    );
  });

  test('layer row mutations target the requested layer index', () {
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(
        pixelWidth: 32,
        pixelHeight: 32,
        layers: const [
          DrawingLayer(id: 'top', name: 'Top'),
          DrawingLayer(id: 'bottom', name: 'Bottom'),
        ],
      ),
    );

    notifier.updateLayerAt(1, (layer) => layer.copyWith(visible: false));

    expect(notifier.state.payload.layers[0].visible, isTrue);
    expect(notifier.state.payload.layers[1].visible, isFalse);
    expect(notifier.state.activeLayerIndex, 0);
  });
}
