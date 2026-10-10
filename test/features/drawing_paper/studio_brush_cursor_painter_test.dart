import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/presentation/studio/painters/studio_brush_cursor_painter.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

void main() {
  test('assigns a distinct cursor shape to every brush category', () {
    final shapes = {
      for (final brush in StudioBrushCategory.values)
        StudioBrushCursorPainter.shapeFor(brush),
    };

    expect(shapes, hasLength(StudioBrushCategory.values.length));
    expect(
      StudioBrushCursorPainter.shapeFor(StudioBrushCategory.gPen),
      StudioBrushCursorShape.gPen,
    );
    expect(
      StudioBrushCursorPainter.shapeFor(StudioBrushCategory.lassoFill),
      StudioBrushCursorShape.lassoFill,
    );
    expect(
      StudioBrushCursorPainter.shapeForTool(
        StudioBrushCategory.gPen,
        StudioTool.eraser,
      ),
      StudioBrushCursorShape.hardEraser,
    );
    expect(
      StudioBrushCursorPainter.shapeForTool(
        StudioBrushCategory.gPen,
        StudioTool.bucketFill,
      ),
      StudioBrushCursorShape.bucketFill,
    );
  });
}
