import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf/pdf_annotation_coordinates.dart';

void main() {
  const pages = [
    Rect.fromLTWH(100, 50, 600, 800),
    Rect.fromLTWH(100, 900, 600, 800),
  ];

  test('locates the owning page and normalized position', () {
    final placement = locatePdfPage(const Offset(400, 450), pages);

    expect(placement?.pageNumber, 1);
    expect(placement?.relativePosition, const Offset(0.5, 0.5));
  });

  test('uses clicked page rather than current page', () {
    final placement = locatePdfPage(const Offset(400, 1300), pages);

    expect(placement?.pageNumber, 2);
    expect(placement?.relativePosition, const Offset(0.5, 0.5));
  });

  test('rejects page gaps', () {
    expect(locatePdfPage(const Offset(400, 875), pages), isNull);
  });

  test('round-trips normalized positions', () {
    const relative = Offset(0.2, 0.8);
    final point = relativeToPagePoint(relative, pages.first);

    expect(pagePointToRelative(point, pages.first), relative);
  });
}
