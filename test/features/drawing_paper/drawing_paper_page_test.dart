import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';

void main() {
  test('normalizes the legacy paper gap without changing page content', () {
    final payload = DrawingPaperPayload(
      pixelWidth: 240,
      pixelHeight: 180,
      studioPages: [
        DrawingPaperPage(
          id: 'legacy-right',
          position: const Offset(272, 0),
          payload: DrawingPaperPayload(
            pixelWidth: 240,
            pixelHeight: 180,
            rasterDocumentId: 'legacy-raster',
          ),
        ),
      ],
    );

    final pages = DrawingPaperRenderer.workspacePages(payload);

    expect(pages[1].position, const Offset(240, 0));
    expect(pages[1].payload.rasterDocumentId, 'legacy-raster');
    expect(DrawingPaperRenderer.workspaceBounds(payload).width, 480);
  });

  test(
    'maps expanded negative workspace bounds from the existing node frame',
    () {
      final mapped = DrawingPaperRenderer.mapWorkspaceBoundsToCanvas(
        originalWorkspaceBounds: const Rect.fromLTWH(-240, 0, 480, 180),
        updatedWorkspaceBounds: const Rect.fromLTWH(-480, -180, 960, 360),
        canvasBounds: const Rect.fromLTWH(100, 200, 480, 180),
      );

      expect(mapped, const Rect.fromLTWH(-140, 20, 960, 360));
    },
  );

  test('round trips embedded Focus Studio pages', () {
    final payload = DrawingPaperPayload(
      rasterDocumentId: 'root-page',
      pixelWidth: 240,
      pixelHeight: 180,
      studioPages: [
        DrawingPaperPage(
          id: 'right-page',
          position: const Offset(240, 0),
          payload: DrawingPaperPayload(
            rasterDocumentId: 'right-page-raster',
            presetName: 'Test Paper',
            pixelWidth: 240,
            pixelHeight: 180,
          ),
        ),
      ],
    );

    final restored = DrawingPaperPayload.fromJson(payload.toJson());

    expect(restored.studioPages, hasLength(1));
    expect(restored.studioPages.single.id, 'right-page');
    expect(restored.studioPages.single.position, const Offset(240, 0));
    expect(
      restored.studioPages.single.payload.rasterDocumentId,
      'right-page-raster',
    );
    expect(restored.studioPages.single.payload.pixelSize, payload.pixelSize);
  });
}
