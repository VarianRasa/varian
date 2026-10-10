import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/studio_item_selection.dart';

void main() {
  group('FocusStudioItemGeometry', () {
    test('computes bounds for strokes and speech balloon tails', () {
      const stroke = DrawingStroke(
        id: 'stroke-1',
        brush: StudioBrushCategory.gPen,
        color: Colors.black,
        size: 10,
        opacity: 1,
        points: [
          DrawingStrokePoint(x: 10, y: 20),
          DrawingStrokePoint(x: 40, y: 20),
        ],
      );
      const balloon = SpeechBalloon(
        id: 'balloon-1',
        position: Offset(10, 10),
        size: Size(30, 20),
        tailTarget: Offset(60, 70),
      );

      expect(
        FocusStudioItemGeometry.boundsOf(stroke),
        const Rect.fromLTRB(5, 15, 45, 25),
      );
      expect(
        FocusStudioItemGeometry.boundsOf(balloon),
        const Rect.fromLTRB(10, 10, 60, 70),
      );
    });

    test('rotates vector shape bounds around its model bounds center', () {
      const shape = VectorShapeObject(
        id: 'shape-1',
        kind: ShapeKind.rectangle,
        points: [Offset(0, 0), Offset(20, 10)],
        strokeWidth: 0,
        rotation: math.pi / 2,
      );

      final bounds = FocusStudioItemGeometry.boundsOf(shape)!;

      expect(bounds.left, closeTo(5, 0.0001));
      expect(bounds.top, closeTo(-5, 0.0001));
      expect(bounds.right, closeTo(15, 0.0001));
      expect(bounds.bottom, closeTo(15, 0.0001));
    });

    test('keeps rotated balloon tails in world-space geometry', () {
      const balloon = SpeechBalloon(
        id: 'balloon-1',
        position: Offset(10, 10),
        size: Size(30, 20),
        tailTarget: Offset(60, 70),
        rotation: math.pi / 2,
      );

      expect(
        FocusStudioItemGeometry.hitTest(
          balloon,
          balloon.tailTarget,
          tolerance: 0,
        ),
        isTrue,
      );
      final bounds = FocusStudioItemGeometry.boundsOf(balloon)!;
      expect(bounds.left, closeTo(15, 0.0001));
      expect(bounds.top, closeTo(5, 0.0001));
      expect(bounds.right, closeTo(60, 0.0001));
      expect(bounds.bottom, closeTo(70, 0.0001));
    });

    test('hit-tests each item independently without z-order state', () {
      const stroke = DrawingStroke(
        id: 'stroke-1',
        brush: StudioBrushCategory.gPen,
        color: Colors.black,
        size: 10,
        opacity: 1,
        points: [
          DrawingStrokePoint(x: 10, y: 20),
          DrawingStrokePoint(x: 40, y: 20),
        ],
      );
      const shape = VectorShapeObject(
        id: 'shape-1',
        kind: ShapeKind.rectangle,
        points: [Offset(0, 0), Offset(20, 10)],
        strokeWidth: 0,
        rotation: math.pi / 2,
      );
      const text = TextObjectData(
        id: 'text-1',
        x: 50,
        y: 50,
        width: 80,
        fontSize: 20,
      );
      const panel = MangaPanelCut(
        id: 'panel-1',
        rect: Rect.fromLTWH(100, 100, 40, 30),
      );
      const balloon = SpeechBalloon(
        id: 'balloon-1',
        position: Offset(150, 10),
        size: Size(30, 20),
        tailTarget: Offset(180, 60),
      );

      expect(
        FocusStudioItemGeometry.hitTest(stroke, const Offset(25, 25)),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.hitTest(stroke, const Offset(25, 31)),
        isFalse,
      );
      expect(
        FocusStudioItemGeometry.hitTest(shape, const Offset(15, 5)),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.hitTest(shape, const Offset(30, 5)),
        isFalse,
      );
      expect(
        FocusStudioItemGeometry.hitTest(text, const Offset(60, 60)),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.hitTest(text, const Offset(140, 60)),
        isFalse,
      );
      expect(
        FocusStudioItemGeometry.hitTest(panel, const Offset(120, 115)),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.hitTest(panel, const Offset(145, 115)),
        isFalse,
      );
      expect(
        FocusStudioItemGeometry.hitTest(balloon, const Offset(180, 60)),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.hitTest(balloon, const Offset(190, 60)),
        isFalse,
      );
    });

    test('applies point tolerance to stroke and vector path edges', () {
      const stroke = DrawingStroke(
        id: 'stroke-1',
        brush: StudioBrushCategory.gPen,
        color: Colors.black,
        size: 4,
        opacity: 1,
        points: [
          DrawingStrokePoint(x: 0, y: 0),
          DrawingStrokePoint(x: 20, y: 0),
        ],
      );
      const shape = VectorShapeObject(
        id: 'shape-1',
        kind: ShapeKind.line,
        points: [Offset(0, 0), Offset(20, 0)],
        strokeWidth: 2,
      );

      expect(
        FocusStudioItemGeometry.hitTest(
          stroke,
          const Offset(10, 7),
          tolerance: 5,
        ),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.hitTest(
          shape,
          const Offset(10, 4),
          tolerance: 2,
        ),
        isTrue,
      );
    });

    test('hit-tests filled strokes along polygon edges', () {
      const stroke = DrawingStroke(
        id: 'lasso-1',
        brush: StudioBrushCategory.lassoFill,
        color: Colors.black,
        size: 2,
        opacity: 1,
        points: [
          DrawingStrokePoint(x: 0, y: 0),
          DrawingStrokePoint(x: 20, y: 0),
          DrawingStrokePoint(x: 20, y: 20),
          DrawingStrokePoint(x: 0, y: 20),
        ],
      );

      expect(
        FocusStudioItemGeometry.hitTest(stroke, const Offset(10, 0)),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.hitTest(stroke, const Offset(10, 10)),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.hitTest(stroke, const Offset(30, 10)),
        isFalse,
      );
    });

    test('uses geometry bounds for marquee intersection', () {
      const stroke = DrawingStroke(
        id: 'stroke-1',
        brush: StudioBrushCategory.gPen,
        color: Colors.black,
        size: 4,
        opacity: 1,
        points: [
          DrawingStrokePoint(x: 0, y: 0),
          DrawingStrokePoint(x: 20, y: 0),
        ],
      );
      const shape = VectorShapeObject(
        id: 'shape-1',
        kind: ShapeKind.rectangle,
        points: [Offset(0, 0), Offset(20, 10)],
        strokeWidth: 0,
        rotation: math.pi / 2,
      );
      const text = TextObjectData(
        id: 'text-1',
        x: 50,
        y: 50,
        width: 40,
        fontSize: 20,
      );
      const panel = MangaPanelCut(
        id: 'panel-1',
        rect: Rect.fromLTWH(100, 100, 40, 30),
      );
      const balloon = SpeechBalloon(
        id: 'balloon-1',
        position: Offset(150, 10),
        size: Size(30, 20),
        tailTarget: Offset(180, 60),
      );

      expect(
        FocusStudioItemGeometry.intersectsMarquee(
          stroke,
          const Rect.fromLTWH(10, -1, 4, 4),
        ),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.intersectsMarquee(
          shape,
          const Rect.fromLTWH(5, 14, 4, 4),
        ),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.intersectsMarquee(
          text,
          const Rect.fromLTWH(80, 50, 20, 20),
        ),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.intersectsMarquee(
          panel,
          const Rect.fromLTWH(130, 120, 20, 20),
        ),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.intersectsMarquee(
          balloon,
          const Rect.fromLTWH(175, 55, 10, 10),
        ),
        isTrue,
      );
      expect(
        FocusStudioItemGeometry.intersectsMarquee(
          panel,
          const Rect.fromLTWH(0, 0, 20, 20),
        ),
        isFalse,
      );
    });
  });

  group('FocusStudioItemReference', () {
    test('has stable identity from kind, layer, and object id', () {
      const first = FocusStudioItemReference.drawingStroke(
        layerId: 'layer-1',
        objectId: 'stroke-1',
      );
      const equal = FocusStudioItemReference.drawingStroke(
        layerId: 'layer-1',
        objectId: 'stroke-1',
      );
      const differentLayer = FocusStudioItemReference.drawingStroke(
        layerId: 'layer-2',
        objectId: 'stroke-1',
      );
      const differentKind = FocusStudioItemReference.vectorShapeObject(
        layerId: 'layer-1',
        objectId: 'stroke-1',
      );
      const panel = FocusStudioItemReference.mangaPanelCut(objectId: 'panel-1');

      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first, isNot(differentLayer));
      expect(first, isNot(differentKind));
      expect(first, isNot(panel));
      expect(first.objectId, 'stroke-1');
      expect(first.layerId, 'layer-1');
      expect(panel.layerId, isNull);
    });
  });
}
