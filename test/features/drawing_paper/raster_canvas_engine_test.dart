import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';
import 'package:varian/features/drawing_paper/domain/models/selection_mask.dart';
import 'package:varian/features/drawing_paper/domain/services/raster_canvas_engine.dart';

void main() {
  test('bucket fill only changes the connected region', () {
    final surface = RasterSurface.solid(5, 5, const Color(0xFFFFFFFF));
    for (int y = 0; y < 5; y++) {
      surface.setColor(2, y, const Color(0xFF000000));
    }

    final changed = RasterCanvasEngine(
      surface,
    ).bucketFill(seedPoint: const Offset(0, 0), color: const Color(0xFFFF0000));

    expect(changed, 10);
    expect(surface.colorAt(0, 4), const Color(0xFFFF0000));
    expect(surface.colorAt(4, 4), const Color(0xFFFFFFFF));
    expect(surface.colorAt(2, 2), const Color(0xFF000000));
  });

  test('selection limits blur and smudge edits', () {
    final surface = RasterSurface.solid(7, 7, const Color(0xFFFFFFFF));
    surface.setColor(1, 3, const Color(0xFF000000));
    const selection = SelectionMask(
      toolType: SelectionToolType.rectangle,
      boundingBox: Rect.fromLTWH(0, 0, 3, 7),
    );

    final changed = RasterCanvasEngine(
      surface,
    ).blur(points: const [Offset(1, 3)], radius: 2, selection: selection);

    expect(changed, greaterThan(0));
    expect(surface.colorAt(6, 6), const Color(0xFFFFFFFF));
  });

  test('transform moves selected pixels without duplicating the source', () {
    final surface = RasterSurface.solid(8, 4, const Color(0xFFFFFFFF));
    surface.setColor(1, 1, const Color(0xFF000000));
    const selection = SelectionMask(
      toolType: SelectionToolType.rectangle,
      boundingBox: Rect.fromLTWH(1, 1, 1, 1),
    );

    final changed = RasterCanvasEngine(surface).transform(
      bounds: const Rect.fromLTWH(1, 1, 1, 1),
      translation: const Offset(3, 0),
      selection: selection,
    );

    expect(changed, greaterThan(0));
    expect(surface.colorAt(1, 1), const Color(0x00000000));
    expect(surface.colorAt(4, 1), const Color(0xFF000000));
  });

  test('brush profiles change edge softness', () {
    final hard = RasterSurface.solid(9, 9, const Color(0x00000000));
    final soft = RasterSurface.solid(9, 9, const Color(0x00000000));

    RasterCanvasEngine(hard).drawStroke(
      points: const [Offset(4, 4)],
      color: const Color(0xFF000000),
      size: 6,
      brush: StudioBrushCategory.gPen,
    );
    RasterCanvasEngine(soft).drawStroke(
      points: const [Offset(4, 4)],
      color: const Color(0xFF000000),
      size: 6,
      brush: StudioBrushCategory.airbrush,
    );

    final hardEdgeAlpha = (hard.colorAt(4, 1).toARGB32() >> 24) & 0xff;
    final softEdgeAlpha = (soft.colorAt(4, 1).toARGB32() >> 24) & 0xff;
    expect(hardEdgeAlpha, 255);
    expect(softEdgeAlpha, lessThan(hardEdgeAlpha));
  });

  test('raster edit operation round-trips through JSON', () {
    final operation = RasterEditOperation.bucketFill(
      seedPoint: const Offset(3, 4),
      color: const Color(0xFF12AB34),
      tolerance: 18,
    );
    final restored = RasterEditOperation.fromJson(operation.toJson());

    expect(restored.kind, operation.kind);
    expect(restored.seedPoint, operation.seedPoint);
    expect(restored.color, operation.color);
    expect(restored.tolerance, operation.tolerance);
  });
}
