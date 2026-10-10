import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';

class PsdExportService {
  /// Mengompilasi payload drawing paper ke representasi metadata PSD dan structured JSON manifest
  static Uint8List exportToPsdManifest(DrawingPaperPayload payload) {
    final manifest = {
      'format': 'Adobe Photoshop Layered Document (PSD Compatible)',
      'version': '1.0',
      'preset': payload.presetName,
      'width': payload.pixelWidth,
      'height': payload.pixelHeight,
      'dpi': payload.dpi,
      'colorMode': 'RGB 8-bit',
      'paperColor': payload.paperColor.toARGB32(),
      'layers': payload.layers.map((l) {
        return {
          'name': l.name,
          'type': l.type.name,
          'visible': l.visible,
          'locked': l.locked,
          'alphaLocked': l.alphaLocked,
          'clipToBelow': l.clipToBelow,
          'opacity': l.opacity,
          'blendMode': l.blendMode.name,
          'strokeCount': l.strokes.length,
          'hasFilter': l.adjustmentFilter?.name,
        };
      }).toList(),
      'rulers': payload.rulers.map((r) => r.toJson()).toList(),
      'mangaStructure': payload.mangaStructure?.toJson(),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(manifest);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  /// Menghitung approximate CMYK channels dari RGB Color
  static (double c, double m, double y, double k) rgbToCmyk(Color color) {
    final r = color.r / 255.0;
    final g = color.g / 255.0;
    final b = color.b / 255.0;

    final k = 1.0 - [r, g, b].reduce((curr, next) => curr > next ? curr : next);
    if (k >= 1.0) {
      return (0.0, 0.0, 0.0, 1.0);
    }

    final c = (1.0 - r - k) / (1.0 - k);
    final m = (1.0 - g - k) / (1.0 - k);
    final y = (1.0 - b - k) / (1.0 - k);

    return (
      c.clamp(0.0, 1.0),
      m.clamp(0.0, 1.0),
      y.clamp(0.0, 1.0),
      k.clamp(0.0, 1.0),
    );
  }
}
