import 'dart:math' as math;
import 'dart:ui' show Offset, Path, PathMetric;

import 'package:flutter/material.dart';

import '../../../domain/models/node_payload.dart';

class TextPathGlyphPlacement {
  final String glyph;
  final Offset position;
  final double angle;
  final double width;
  final double height;
  final TextStyle style;

  const TextPathGlyphPlacement({
    required this.glyph,
    required this.position,
    required this.angle,
    required this.width,
    required this.height,
    required this.style,
  });
}

class TextOnPathLayout {
  const TextOnPathLayout._();

  static List<TextPathGlyphPlacement> layout({
    required String text,
    required Path path,
    required TextStyle style,
    List<TextStyle>? glyphStyles,
    TextPathAlignment alignment = TextPathAlignment.start,
    double offset = 0.0,
    bool reversed = false,
  }) {
    final glyphs = text
        .replaceAll('\n', ' ')
        .runes
        .map(String.fromCharCode)
        .where((glyph) => glyph.isNotEmpty)
        .toList(growable: false);
    if (glyphs.isEmpty) return const [];

    final metric = _longestMetric(path);
    if (metric == null || metric.length <= 0) return const [];

    final measurements = <({double width, double height})>[];
    final resolvedStyles = <TextStyle>[];
    for (var index = 0; index < glyphs.length; index++) {
      final glyph = glyphs[index];
      final glyphStyle = glyphStyles != null && index < glyphStyles.length
          ? glyphStyles[index]
          : style;
      final painter = TextPainter(
        text: TextSpan(text: glyph, style: glyphStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      measurements.add((width: painter.width, height: painter.height));
      resolvedStyles.add(glyphStyle);
    }

    final totalWidth = measurements.fold<double>(
      0.0,
      (sum, measurement) => sum + measurement.width,
    );
    final alignmentOffset = switch (alignment) {
      TextPathAlignment.start => 0.0,
      TextPathAlignment.center => (metric.length - totalWidth) / 2,
      TextPathAlignment.end => metric.length - totalWidth,
    };
    var cursor = (offset + alignmentOffset).clamp(-totalWidth, metric.length);
    final result = <TextPathGlyphPlacement>[];

    for (var index = 0; index < glyphs.length; index++) {
      final measurement = measurements[index];
      final centerDistance = reversed
          ? metric.length - cursor - measurement.width / 2
          : cursor + measurement.width / 2;
      final safeDistance = centerDistance.clamp(0.0, metric.length);
      final tangent = metric.getTangentForOffset(safeDistance);
      if (tangent != null) {
        result.add(
          TextPathGlyphPlacement(
            glyph: glyphs[index],
            position: tangent.position,
            angle: tangent.angle + (reversed ? math.pi : 0.0),
            width: measurement.width,
            height: measurement.height,
            style: resolvedStyles[index],
          ),
        );
      }
      cursor += measurement.width;
    }
    return result;
  }

  static PathMetric? _longestMetric(Path path) {
    PathMetric? longest;
    for (final metric in path.computeMetrics()) {
      if (longest == null || metric.length > longest.length) longest = metric;
    }
    return longest;
  }
}
