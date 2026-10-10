import 'package:flutter/material.dart';

class PdfPagePlacement {
  const PdfPagePlacement({
    required this.pageNumber,
    required this.relativePosition,
  });

  final int pageNumber;
  final Offset relativePosition;
}

PdfPagePlacement? locatePdfPage(Offset documentPoint, List<Rect> pageRects) {
  final index = pageRects.indexWhere((rect) => rect.contains(documentPoint));
  if (index < 0) return null;
  return PdfPagePlacement(
    pageNumber: index + 1,
    relativePosition: pagePointToRelative(documentPoint, pageRects[index]),
  );
}

Offset pagePointToRelative(Offset documentPoint, Rect pageRect) => Offset(
  ((documentPoint.dx - pageRect.left) / pageRect.width).clamp(0, 1),
  ((documentPoint.dy - pageRect.top) / pageRect.height).clamp(0, 1),
);

Offset relativeToPagePoint(Offset relative, Rect pageRect) => Offset(
  pageRect.left + relative.dx.clamp(0, 1) * pageRect.width,
  pageRect.top + relative.dy.clamp(0, 1) * pageRect.height,
);
