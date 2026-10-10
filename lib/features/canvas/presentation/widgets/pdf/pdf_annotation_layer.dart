import 'package:flutter/material.dart';
import 'package:varian/domain/models/pdf_annotation.dart';

export 'package:varian/domain/models/pdf_annotation.dart';

class PdfAnnotationPainter extends CustomPainter {
  PdfAnnotationPainter({required this.strokes, required this.pageSize});

  final List<PdfStroke> strokes;
  final Size pageSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.relativePoints.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.isHighlighter
            ? stroke.color.withValues(alpha: 0.38)
            : stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.strokeWidth
        ..style = PaintingStyle.stroke;
      final path = Path();
      final first = stroke.relativePoints.first;
      path.moveTo(first.dx * pageSize.width, first.dy * pageSize.height);
      for (final point in stroke.relativePoints.skip(1)) {
        path.lineTo(point.dx * pageSize.width, point.dy * pageSize.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PdfAnnotationPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.pageSize != pageSize;
}
