import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextPayload & Advanced Typography Tests', () {
    test('TextPayload serialization and defaults', () {
      final payload = TextPayload(
        text: 'Custom Typography',
        fontFamily: 'Poppins',
        fontSize: 24.0,
        fontWeight: FontWeight.bold,
        fontStyle: FontStyle.italic,
        underline: true,
        strikethrough: true,
        lineHeight: 1.5,
        letterSpacing: 2.0,
        textTransform: TextTransformCase.uppercase,
        verticalAlign: TextVerticalAlign.middle,
        sizeMode: TextSizeMode.autoHeight,
        renderMode: TextRenderMode.markdown,
        strokeColor: const Color(0xFFFF0000),
        strokeWidth: 2.0,
        shadowColor: const Color(0x80000000),
        shadowBlurRadius: 6.0,
        shadowOffset: const Offset(2, 4),
        backgroundColor: const Color(0xFF1F2937),
        backgroundRadius: 8.0,
        backgroundPadding: 12.0,
      );

      final json = payload.toJson();
      final fromJson = TextPayload.fromJson(json);

      expect(fromJson.text, 'Custom Typography');
      expect(fromJson.fontFamily, 'Poppins');
      expect(fromJson.fontSize, 24.0);
      expect(fromJson.fontWeight, FontWeight.bold);
      expect(fromJson.fontStyle, FontStyle.italic);
      expect(fromJson.underline, true);
      expect(fromJson.strikethrough, true);
      expect(fromJson.lineHeight, 1.5);
      expect(fromJson.letterSpacing, 2.0);
      expect(fromJson.textTransform, TextTransformCase.uppercase);
      expect(fromJson.verticalAlign, TextVerticalAlign.middle);
      expect(fromJson.sizeMode, TextSizeMode.autoHeight);
      expect(fromJson.renderMode, TextRenderMode.markdown);
      expect(fromJson.strokeColor, const Color(0xFFFF0000));
      expect(fromJson.strokeWidth, 2.0);
      expect(fromJson.shadowColor, const Color(0x80000000));
      expect(fromJson.shadowBlurRadius, 6.0);
      expect(fromJson.shadowOffset, const Offset(2, 4));
      expect(fromJson.backgroundColor, const Color(0xFF1F2937));
      expect(fromJson.backgroundRadius, 8.0);
      expect(fromJson.backgroundPadding, 12.0);
    });

    test(
      'NodePainter paints text with typography, stroke, shadow, and badge without error',
      () {
        final payload = TextPayload(
          text: 'Typography Canvas Test',
          fontFamily: 'Fira Code',
          fontSize: 20.0,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          underline: true,
          strikethrough: false,
          lineHeight: 1.4,
          letterSpacing: 1.2,
          textTransform: TextTransformCase.capitalize,
          verticalAlign: TextVerticalAlign.middle,
          strokeColor: const Color(0xFF38BDF8),
          strokeWidth: 1.5,
          shadowColor: const Color(0xFF000000),
          shadowBlurRadius: 4.0,
          backgroundColor: const Color(0xFF334155),
          backgroundRadius: 6.0,
          backgroundPadding: 8.0,
        );

        final node = CanvasNode(
          id: 'text_test_1',
          type: NodeType.text,
          x: 100,
          y: 100,
          width: 300,
          height: 120,
          payload: payload,
        );

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        expect(() => NodePainter.paint(canvas, node), returnsNormally);
        final picture = recorder.endRecording();
        picture.dispose();
      },
    );
  });
}
