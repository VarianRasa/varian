import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/pdf_annotation.dart';

void main() {
  test('annotation collection survives JSON round-trip', () {
    final data = PdfAnnotationData(
      stickyNotes: [
        PdfStickyNote(
          id: 'n1',
          pageNumber: 1,
          relativePosition: const Offset(0.25, 0.75),
          text: 'Review',
          color: Colors.amber,
          createdAt: DateTime.utc(2026),
        ),
      ],
      strokes: const [
        PdfStroke(
          id: 's1',
          pageNumber: 2,
          relativePoints: [Offset(0.1, 0.2), Offset(0.3, 0.4)],
          color: Colors.red,
          strokeWidth: 2,
        ),
      ],
      textComments: [
        PdfTextComment(
          id: 'c1',
          quote: 'selected text',
          comment: 'Explain this',
          anchors: const [
            PdfPageAnchor(
              pageNumber: 1,
              relativeRects: [Rect.fromLTWH(0.1, 0.2, 0.5, 0.1)],
            ),
            PdfPageAnchor(
              pageNumber: 2,
              relativeRects: [Rect.fromLTWH(0.1, 0.1, 0.4, 0.1)],
            ),
          ],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ],
    );

    final restored = PdfAnnotationData.fromJson(data.toJson());

    expect(restored.stickyNotes.single.pageNumber, 1);
    expect(restored.strokes.single.pageNumber, 2);
    expect(restored.textComments.single.anchors.length, 2);
  });
}
