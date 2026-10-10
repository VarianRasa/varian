import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/ai_workflow_contract.dart';

class AIMaskRenderer {
  static Future<Uint8List> render(AIMaskDocument mask) async {
    _validateSize(mask.width, mask.height);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    for (final stroke in mask.strokes) {
      _drawStroke(canvas, stroke);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(mask.width, mask.height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      throw StateError('Could not encode the AI mask as PNG.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static void _drawStroke(ui.Canvas canvas, AIMaskStroke stroke) {
    if (stroke.points.isEmpty || !stroke.width.isFinite || stroke.width <= 0) {
      return;
    }
    final paint = ui.Paint()
      ..color = stroke.erase
          ? const ui.Color(0xFF000000)
          : const ui.Color(0xFFFFFFFF)
      ..strokeWidth = stroke.width
      ..strokeCap = ui.StrokeCap.round
      ..style = ui.PaintingStyle.stroke;
    if (stroke.points.length == 1) {
      canvas.drawCircle(stroke.points.single, stroke.width / 2, paint);
      return;
    }
    final path = ui.Path()
      ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  static void _validateSize(int width, int height) {
    if (width <= 0 || height <= 0 || width > 8192 || height > 8192) {
      throw ArgumentError(
        'AI mask dimensions must be between 1 and 8192 pixels.',
      );
    }
    if (width.toDouble() * height > 25000000) {
      throw ArgumentError('AI mask is too large to render safely.');
    }
  }
}
