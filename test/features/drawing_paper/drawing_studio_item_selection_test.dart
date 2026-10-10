import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/selection_mask.dart';
import 'package:varian/features/drawing_paper/domain/models/studio_item_selection.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

void main() {
  test('selects, moves, and undoes structured Focus Studio items', () {
    const stroke = DrawingStroke(
      id: 'stroke-1',
      brush: StudioBrushCategory.gPen,
      color: Colors.black,
      size: 4,
      opacity: 1,
      points: [
        DrawingStrokePoint(x: 4, y: 4),
        DrawingStrokePoint(x: 12, y: 12),
      ],
    );
    const shape = VectorShapeObject(
      id: 'shape-1',
      kind: ShapeKind.rectangle,
      points: [Offset(20, 20), Offset(30, 30)],
    );
    const text = TextObjectData(id: 'text-1', x: 40, y: 40);
    const balloon = SpeechBalloon(
      id: 'balloon-1',
      position: Offset(5, 50),
      size: Size(30, 20),
      tailTarget: Offset(20, 80),
    );
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(
        pixelWidth: 100,
        pixelHeight: 100,
        layers: const [
          DrawingLayer(
            id: 'layer-1',
            name: 'Ink',
            strokes: [stroke],
            shapes: [shape],
            texts: [text],
          ),
        ],
        mangaStructure: const MangaStructure(balloons: [balloon]),
      ),
    );

    const strokeRef = FocusStudioItemReference.drawingStroke(
      layerId: 'layer-1',
      objectId: 'stroke-1',
    );
    const textRef = FocusStudioItemReference.textObject(
      layerId: 'layer-1',
      objectId: 'text-1',
    );
    const balloonRef = FocusStudioItemReference.speechBalloon(
      objectId: 'balloon-1',
    );

    notifier.setTool(StudioTool.itemSelection);
    notifier.selectItems([strokeRef, textRef, balloonRef]);
    expect(
      notifier.state.selectedItems,
      containsAll([strokeRef, textRef, balloonRef]),
    );
    expect(notifier.selectedItemsBounds, isNotNull);

    notifier.moveSelectedItems(const Offset(10, 5));
    expect(
      notifier.state.payload.layers.single.strokes.single.points.first.offset,
      const Offset(14, 9),
    );
    expect(notifier.state.payload.layers.single.texts.single.x, 50);
    expect(
      notifier.state.payload.mangaStructure!.balloons.single.position,
      const Offset(15, 55),
    );
    expect(notifier.state.undoCount, 1);

    notifier.undo();
    expect(
      notifier.state.payload.layers.single.strokes.single.points.first.offset,
      const Offset(4, 4),
    );
    expect(
      notifier.state.selectedItems,
      containsAll([strokeRef, textRef, balloonRef]),
    );
    notifier.redo();
    expect(notifier.state.payload.layers.single.texts.single.x, 50);

    notifier.dispose();
  });

  test('resizes and rotates a selected vector object with history', () {
    const shape = VectorShapeObject(
      id: 'shape-1',
      kind: ShapeKind.rectangle,
      points: [Offset(10, 10), Offset(30, 30)],
      strokeWidth: 0,
    );
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(
        pixelWidth: 64,
        pixelHeight: 64,
        layers: const [
          DrawingLayer(id: 'layer-1', name: 'Layer', shapes: [shape]),
        ],
      ),
    );
    const reference = FocusStudioItemReference.vectorShapeObject(
      layerId: 'layer-1',
      objectId: 'shape-1',
    );
    notifier.setTool(StudioTool.itemSelection);
    notifier.selectItems([reference]);
    notifier.resizeSelectedItems(const Rect.fromLTWH(10, 10, 40, 40));
    expect(notifier.state.payload.layers.single.shapes.single.points, [
      const Offset(10, 10),
      const Offset(50, 50),
    ]);
    expect(notifier.state.undoCount, 1);

    notifier.undo();
    notifier.selectItems([reference]);
    notifier.rotateSelectedItems(0.5);
    expect(
      notifier.state.payload.layers.single.shapes.single.rotation,
      closeTo(0.5, 0.0001),
    );
    notifier.dispose();
  });

  test('keeps pixel selection separate from item selection', () {
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(pixelWidth: 32, pixelHeight: 32),
    );
    const pixelSelection = SelectionMask(
      toolType: SelectionToolType.rectangle,
      boundingBox: Rect.fromLTWH(2, 2, 8, 8),
    );

    notifier.setTool(StudioTool.selection);
    notifier.setSelection(pixelSelection);
    notifier.setTool(StudioTool.itemSelection);

    expect(notifier.state.selection, pixelSelection);
    expect(notifier.state.selectedItems, isEmpty);
    notifier.dispose();
  });

  test(
    'replacing the Focus Studio page clears item selection and clipboard',
    () {
      const shape = VectorShapeObject(
        id: 'shape-1',
        kind: ShapeKind.rectangle,
        points: [Offset(2, 2), Offset(12, 12)],
      );
      final notifier = DrawingStudioNotifier(
        DrawingPaperPayload(
          pixelWidth: 32,
          pixelHeight: 32,
          layers: const [
            DrawingLayer(id: 'layer-1', name: 'Layer', shapes: [shape]),
          ],
        ),
      );
      const reference = FocusStudioItemReference.vectorShapeObject(
        layerId: 'layer-1',
        objectId: 'shape-1',
      );
      notifier.setTool(StudioTool.itemSelection);
      notifier.selectItems([reference]);
      notifier.copySelectedItems();
      expect(notifier.state.itemClipboard, isNotEmpty);

      notifier.replacePayload(
        DrawingPaperPayload(pixelWidth: 32, pixelHeight: 32),
      );

      expect(notifier.state.selectedItems, isEmpty);
      expect(notifier.state.itemClipboard, isEmpty);
      notifier.dispose();
    },
  );

  test('select all excludes hidden and locked layer content', () {
    const visibleStroke = DrawingStroke(
      id: 'visible',
      brush: StudioBrushCategory.gPen,
      color: Colors.black,
      size: 2,
      opacity: 1,
      points: [DrawingStrokePoint(x: 1, y: 1), DrawingStrokePoint(x: 2, y: 2)],
    );
    const hiddenStroke = DrawingStroke(
      id: 'hidden',
      brush: StudioBrushCategory.gPen,
      color: Colors.black,
      size: 2,
      opacity: 1,
      points: [DrawingStrokePoint(x: 3, y: 3), DrawingStrokePoint(x: 4, y: 4)],
    );
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(
        pixelWidth: 32,
        pixelHeight: 32,
        layers: const [
          DrawingLayer(
            id: 'visible-layer',
            name: 'Visible',
            strokes: [visibleStroke],
          ),
          DrawingLayer(
            id: 'hidden-layer',
            name: 'Hidden',
            visible: false,
            strokes: [hiddenStroke],
          ),
        ],
      ),
    );

    notifier.selectAllItems();

    expect(notifier.state.selectedItems, [
      const FocusStudioItemReference.drawingStroke(
        layerId: 'visible-layer',
        objectId: 'visible',
      ),
    ]);
    notifier.dispose();
  });

  test('duplicates, copies, pastes, and deletes selected items', () {
    const shape = VectorShapeObject(
      id: 'shape-1',
      kind: ShapeKind.rectangle,
      points: [Offset(2, 2), Offset(12, 12)],
    );
    final notifier = DrawingStudioNotifier(
      DrawingPaperPayload(
        pixelWidth: 32,
        pixelHeight: 32,
        layers: [
          const DrawingLayer(id: 'layer-1', name: 'Layer', shapes: [shape]),
        ],
      ),
    );
    const reference = FocusStudioItemReference.vectorShapeObject(
      layerId: 'layer-1',
      objectId: 'shape-1',
    );
    notifier.setTool(StudioTool.itemSelection);
    notifier.selectItems([reference]);
    notifier.copySelectedItems();
    notifier.duplicateSelectedItems();

    expect(notifier.state.payload.layers.single.shapes, hasLength(2));
    expect(notifier.state.selectedItems, hasLength(1));
    final duplicate = notifier.state.payload.layers.single.shapes.last;
    expect(duplicate.points.first, const Offset(26, 26));

    notifier.deleteSelectedItems();
    expect(notifier.state.payload.layers.single.shapes, hasLength(1));
    notifier.pasteSelectedItems();
    expect(notifier.state.payload.layers.single.shapes, hasLength(2));

    notifier.dispose();
  });
}
