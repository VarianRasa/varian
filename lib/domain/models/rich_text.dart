import 'package:flutter/material.dart';

enum RichTextBlockType { paragraph, heading, bullet, numbered, quote, code }

class RichTextSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final Color? color;
  final Color? highlight;
  final String? linkUrl;
  final String? fontFamily;
  final double? fontSize;
  final FontWeight? fontWeight;
  final Map<String, double> fontAxes;

  const RichTextSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.color,
    this.highlight,
    this.linkUrl,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.fontAxes = const {},
  });

  RichTextSpan copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    Object? color = _unset,
    Object? highlight = _unset,
    Object? linkUrl = _unset,
    Object? fontFamily = _unset,
    Object? fontSize = _unset,
    Object? fontWeight = _unset,
    Map<String, double>? fontAxes,
  }) {
    return RichTextSpan(
      text: text ?? this.text,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      color: color == _unset ? this.color : color as Color?,
      highlight: highlight == _unset ? this.highlight : highlight as Color?,
      linkUrl: linkUrl == _unset ? this.linkUrl : linkUrl as String?,
      fontFamily: fontFamily == _unset
          ? this.fontFamily
          : fontFamily as String?,
      fontSize: fontSize == _unset ? this.fontSize : fontSize as double?,
      fontWeight: fontWeight == _unset
          ? this.fontWeight
          : fontWeight as FontWeight?,
      fontAxes: fontAxes ?? this.fontAxes,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'bold': bold,
    'italic': italic,
    'underline': underline,
    'strikethrough': strikethrough,
    'color': color?.toARGB32(),
    'highlight': highlight?.toARGB32(),
    'linkUrl': linkUrl,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fontWeight': fontWeight?.value,
    'fontAxes': fontAxes,
  };

  factory RichTextSpan.fromJson(Map<String, dynamic> json) => RichTextSpan(
    text: json['text'] as String? ?? '',
    bold: json['bold'] as bool? ?? false,
    italic: json['italic'] as bool? ?? false,
    underline: json['underline'] as bool? ?? false,
    strikethrough: json['strikethrough'] as bool? ?? false,
    color: _readColor(json['color']),
    highlight: _readColor(json['highlight']),
    linkUrl: json['linkUrl'] as String?,
    fontFamily: json['fontFamily'] as String?,
    fontSize: _readFiniteDouble(json['fontSize']),
    fontWeight: _readFontWeight(json['fontWeight']),
    fontAxes: _readAxes(json['fontAxes']),
  );

  static Color? _readColor(Object? value) {
    return value is num ? Color(value.toInt()) : null;
  }

  static double? _readFiniteDouble(Object? value) {
    if (value is! num || !value.isFinite) return null;
    return value.toDouble();
  }

  static FontWeight? _readFontWeight(Object? value) {
    if (value == null) return null;
    final normalized = value.toString();
    return FontWeight.values.firstWhere(
      (candidate) =>
          candidate.value.toString() == normalized ||
          candidate.toString() == normalized,
      orElse: () => FontWeight.normal,
    );
  }

  static Map<String, double> _readAxes(Object? value) {
    if (value is! Map) return const {};
    final axes = <String, double>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      final number = entry.value;
      if (key.isEmpty || key.length > 4 || number is! num || !number.isFinite) {
        continue;
      }
      axes[key] = number.toDouble().clamp(-1000.0, 1000.0);
    }
    return axes;
  }

  static const Object _unset = Object();
}

class RichTextBlock {
  final RichTextBlockType type;
  final List<RichTextSpan> spans;
  final TextAlign? alignment;
  final int indent;
  final double spacingBefore;
  final double spacingAfter;

  const RichTextBlock({
    this.type = RichTextBlockType.paragraph,
    this.spans = const [],
    this.alignment,
    this.indent = 0,
    this.spacingBefore = 0.0,
    this.spacingAfter = 0.0,
  });

  String get plainText => spans.map((span) => span.text).join();

  RichTextBlock copyWith({
    RichTextBlockType? type,
    List<RichTextSpan>? spans,
    Object? alignment = _unset,
    int? indent,
    double? spacingBefore,
    double? spacingAfter,
  }) {
    return RichTextBlock(
      type: type ?? this.type,
      spans: spans ?? this.spans,
      alignment: alignment == _unset ? this.alignment : alignment as TextAlign?,
      indent: indent ?? this.indent,
      spacingBefore: spacingBefore ?? this.spacingBefore,
      spacingAfter: spacingAfter ?? this.spacingAfter,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'spans': spans.map((span) => span.toJson()).toList(),
    'alignment': alignment?.name,
    'indent': indent,
    'spacingBefore': spacingBefore,
    'spacingAfter': spacingAfter,
  };

  factory RichTextBlock.fromJson(Map<String, dynamic> json) => RichTextBlock(
    type: RichTextBlockType.values.firstWhere(
      (candidate) => candidate.name == json['type'],
      orElse: () => RichTextBlockType.paragraph,
    ),
    spans:
        (json['spans'] as List<dynamic>?)
            ?.whereType<Map>()
            .map(
              (span) => RichTextSpan.fromJson(Map<String, dynamic>.from(span)),
            )
            .toList() ??
        const [],
    alignment: TextAlign.values.firstWhereOrNull(
      (candidate) => candidate.name == json['alignment'],
    ),
    indent: ((json['indent'] as num?)?.toInt() ?? 0).clamp(0, 12),
    spacingBefore: ((json['spacingBefore'] as num?)?.toDouble() ?? 0.0).clamp(
      0.0,
      500.0,
    ),
    spacingAfter: ((json['spacingAfter'] as num?)?.toDouble() ?? 0.0).clamp(
      0.0,
      500.0,
    ),
  );

  static const Object _unset = Object();
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
