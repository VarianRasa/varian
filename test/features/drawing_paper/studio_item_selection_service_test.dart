import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/studio_item_selection.dart';
import 'package:varian/features/drawing_paper/domain/services/studio_item_selection_service.dart';

void main() {
  const stroke = DrawingStroke(
    id: 'stroke-1',
    brush: StudioBrushCategory.gPen,
    color: Colors.black,
    size: 4,
    opacity: 1,
    points: [
      DrawingStrokePoint(x: 10, y: 10),
      DrawingStrokePoint(x: 20, y: 10),
    ],
  );
  const shape = VectorShapeObject(
    id: 'shape-1',
    kind: ShapeKind.rectangle,
    points: [Offset(30, 10), Offset(50, 30)],
    strokeWidth: 2,
  );
  const text = TextObjectData(
    id: 'text-1',
    x: 60,
    y: 10,
    width: 40,
    fontSize: 10,
  );
  const panel = MangaPanelCut(
    id: 'panel-1',
    rect: Rect.fromLTWH(10, 60, 40, 30),
  );
  const balloon = SpeechBalloon(
    id: 'balloon-1',
    position: Offset(60, 60),
    size: Size(40, 30),
    tailTarget: Offset(80, 110),
  );

  DrawingPaperPayload payload({bool includeHidden = false}) {
    return DrawingPaperPayload(
      pixelWidth: 160,
      pixelHeight: 160,
      layers: [
        const DrawingLayer(
          id: 'top',
          name: 'Top',
          texts: [text],
          shapes: [shape],
          strokes: [stroke],
        ),
        if (includeHidden)
          const DrawingLayer(
            id: 'hidden',
            name: 'Hidden',
            visible: false,
            strokes: [
              DrawingStroke(
                id: 'hidden-stroke',
                brush: StudioBrushCategory.gPen,
                color: Colors.black,
                size: 4,
                opacity: 1,
                points: [
                  DrawingStrokePoint(x: 1, y: 1),
                  DrawingStrokePoint(x: 2, y: 2),
                ],
              ),
            ],
          ),
      ],
      mangaStructure: const MangaStructure(
        panels: [panel],
        balloons: [balloon],
      ),
    );
  }

  test(
    'catalogs visible items in topmost-first order and filters locked items',
    () {
      final entries = FocusStudioItemCatalog.all(payload(includeHidden: true));

      expect(entries.map((entry) => entry.reference.objectId), [
        'balloon-1',
        'panel-1',
        'text-1',
        'shape-1',
        'stroke-1',
      ]);
      expect(
        FocusStudioItemCatalog.editable(payload(includeHidden: true)),
        hasLength(5),
      );

      final lockedPayload = payload().copyWith(
        layers: [payload().layers.first.copyWith(locked: true)],
      );
      expect(
        FocusStudioItemCatalog.editable(
          lockedPayload,
        ).map((entry) => entry.reference.objectId),
        ['balloon-1', 'panel-1'],
      );
    },
  );

  test('translates, scales, and rotates supported items', () {
    final movedStroke =
        FocusStudioItemCatalog.translate(stroke, const Offset(5, 7))
            as DrawingStroke;
    expect(movedStroke.points.first.offset, const Offset(15, 17));

    final resizedText =
        FocusStudioItemCatalog.scale(
              text,
              text.bounds,
              const Rect.fromLTWH(100, 100, 80, 40),
            )
            as TextObjectData;
    expect(resizedText.x, 100);
    expect(resizedText.y, 100);
    expect(resizedText.width, 80);

    final rotatedPanel =
        FocusStudioItemCatalog.rotate(panel, math.pi / 2, panel.rect.center)
            as MangaPanelCut;
    expect(rotatedPanel.rotation, closeTo(math.pi / 2, 0.0001));
    expect(rotatedPanel.rect, panel.rect);

    final rotatedBalloon =
        FocusStudioItemCatalog.rotate(balloon, math.pi / 2, Offset.zero)
            as SpeechBalloon;
    expect(rotatedBalloon.position.dx, closeTo(-95, 0.0001));
    expect(rotatedBalloon.position.dy, closeTo(65, 0.0001));
    expect(rotatedBalloon.tailTarget.dx, closeTo(-110, 0.0001));
    expect(rotatedBalloon.tailTarget.dy, closeTo(80, 0.0001));
    expect(rotatedBalloon.rotation, closeTo(math.pi / 2, 0.0001));
  });

  test('applies updates, removes items, and inserts clipboard clones', () {
    const shapeRef = FocusStudioItemReference.vectorShapeObject(
      layerId: 'top',
      objectId: 'shape-1',
    );
    final updatedShape = shape.copyWith(
      points: const [Offset(1, 1), Offset(2, 2)],
    );
    final updated = FocusStudioItemCatalog.applyUpdates(payload(), {
      shapeRef: updatedShape,
    });
    expect(updated.layers.first.shapes.single.points.first, const Offset(1, 1));

    final removed = FocusStudioItemCatalog.remove(updated, {
      shapeRef,
      const FocusStudioItemReference.mangaPanelCut(objectId: 'panel-1'),
    });
    expect(removed.layers.first.shapes, isEmpty);
    expect(removed.mangaStructure!.panels, isEmpty);

    final inserted = FocusStudioItemCatalog.addClipboardItems(removed, [
      FocusStudioClipboardItem(
        reference: shapeRef,
        item: shape.copyWith(id: 'shape-2'),
      ),
    ]);
    expect(inserted.layers.first.shapes.single.id, 'shape-2');
  });
}
