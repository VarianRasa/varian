import 'package:flutter/material.dart';
import 'package:varian/domain/models/collaboration.dart';

class CursorPainter {
  static void paint(Canvas canvas, RemoteCursor cursor, double zoom) {
    final cursorPaint = Paint()
      ..color = cursor.userColor
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(cursor.x, cursor.y)
      ..lineTo(cursor.x, cursor.y + 16.0 / zoom)
      ..lineTo(cursor.x + 4.5 / zoom, cursor.y + 12.0 / zoom)
      ..lineTo(cursor.x + 12.0 / zoom, cursor.y + 12.0 / zoom)
      ..close();

    canvas.drawPath(path, cursorPaint);

    final textSpan = TextSpan(
      text: cursor.userName,
      style: TextStyle(
        color: Colors.white,
        fontSize: 10.0 / zoom,
        fontWeight: FontWeight.bold,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
      ..layout();

    final bgRect = Rect.fromLTWH(
      cursor.x + 12.0 / zoom,
      cursor.y + 10.0 / zoom,
      tp.width + 8.0 / zoom,
      tp.height + 4.0 / zoom,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, Radius.circular(3.0 / zoom)),
      cursorPaint,
    );
    tp.paint(canvas, Offset(cursor.x + 16.0 / zoom, cursor.y + 12.0 / zoom));
  }
}
