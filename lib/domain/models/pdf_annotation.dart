import 'package:flutter/material.dart';

double _unit(num? value) => (value ?? 0).toDouble().clamp(0, 1);
Offset _offsetFromJson(Map<String, dynamic> json) =>
    Offset(_unit(json['x'] as num?), _unit(json['y'] as num?));
Map<String, dynamic> _offsetToJson(Offset value) => {
  'x': value.dx,
  'y': value.dy,
};

class PdfStickyNote {
  const PdfStickyNote({
    required this.id,
    required this.pageNumber,
    required this.relativePosition,
    required this.text,
    required this.color,
    required this.createdAt,
  });

  final String id;
  final int pageNumber;
  final Offset relativePosition;
  final String text;
  final Color color;
  final DateTime createdAt;

  factory PdfStickyNote.fromJson(Map<String, dynamic> json) => PdfStickyNote(
    id: json['id'] as String,
    pageNumber: (json['pageNumber'] as num).toInt(),
    relativePosition: _offsetFromJson(
      json['relativePosition'] as Map<String, dynamic>,
    ),
    text: json['text'] as String? ?? '',
    color: Color(json['color'] as int? ?? Colors.amber.toARGB32()),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'pageNumber': pageNumber,
    'relativePosition': _offsetToJson(relativePosition),
    'text': text,
    'color': color.toARGB32(),
    'createdAt': createdAt.toIso8601String(),
  };

  PdfStickyNote copyWith({String? text, Color? color}) => PdfStickyNote(
    id: id,
    pageNumber: pageNumber,
    relativePosition: relativePosition,
    text: text ?? this.text,
    color: color ?? this.color,
    createdAt: createdAt,
  );
}

class PdfStroke {
  const PdfStroke({
    required this.id,
    required this.pageNumber,
    required this.relativePoints,
    required this.color,
    required this.strokeWidth,
    this.isHighlighter = false,
  });

  final String id;
  final int pageNumber;
  final List<Offset> relativePoints;
  final Color color;
  final double strokeWidth;
  final bool isHighlighter;

  factory PdfStroke.fromJson(Map<String, dynamic> json) => PdfStroke(
    id: json['id'] as String,
    pageNumber: (json['pageNumber'] as num).toInt(),
    relativePoints: (json['relativePoints'] as List<dynamic>)
        .map((item) => _offsetFromJson(item as Map<String, dynamic>))
        .toList(),
    color: Color(json['color'] as int),
    strokeWidth: (json['strokeWidth'] as num).toDouble(),
    isHighlighter: json['isHighlighter'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'pageNumber': pageNumber,
    'relativePoints': relativePoints.map(_offsetToJson).toList(),
    'color': color.toARGB32(),
    'strokeWidth': strokeWidth,
    'isHighlighter': isHighlighter,
  };
}

class PdfPageAnchor {
  const PdfPageAnchor({required this.pageNumber, required this.relativeRects});

  final int pageNumber;
  final List<Rect> relativeRects;

  factory PdfPageAnchor.fromJson(Map<String, dynamic> json) => PdfPageAnchor(
    pageNumber: (json['pageNumber'] as num).toInt(),
    relativeRects: (json['relativeRects'] as List<dynamic>).map((item) {
      final rect = item as Map<String, dynamic>;
      final left = _unit(rect['left'] as num?);
      final top = _unit(rect['top'] as num?);
      final right = _unit(rect['right'] as num?);
      final bottom = _unit(rect['bottom'] as num?);
      return Rect.fromLTRB(left, top, right, bottom);
    }).toList(),
  );

  Map<String, dynamic> toJson() => {
    'pageNumber': pageNumber,
    'relativeRects': relativeRects
        .map(
          (rect) => {
            'left': rect.left,
            'top': rect.top,
            'right': rect.right,
            'bottom': rect.bottom,
          },
        )
        .toList(),
  };
}

class PdfTextComment {
  const PdfTextComment({
    required this.id,
    required this.quote,
    required this.comment,
    required this.anchors,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String quote;
  final String comment;
  final List<PdfPageAnchor> anchors;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PdfTextComment.fromJson(Map<String, dynamic> json) => PdfTextComment(
    id: json['id'] as String,
    quote: json['quote'] as String? ?? '',
    comment: json['comment'] as String? ?? '',
    anchors: (json['anchors'] as List<dynamic>)
        .map((item) => PdfPageAnchor.fromJson(item as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'quote': quote,
    'comment': comment,
    'anchors': anchors.map((anchor) => anchor.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class PdfAnnotationData {
  const PdfAnnotationData({
    this.stickyNotes = const [],
    this.strokes = const [],
    this.textComments = const [],
  });

  final List<PdfStickyNote> stickyNotes;
  final List<PdfStroke> strokes;
  final List<PdfTextComment> textComments;

  bool get isEmpty =>
      stickyNotes.isEmpty && strokes.isEmpty && textComments.isEmpty;

  factory PdfAnnotationData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PdfAnnotationData();
    return PdfAnnotationData(
      stickyNotes: (json['stickyNotes'] as List<dynamic>? ?? const [])
          .map((item) => PdfStickyNote.fromJson(item as Map<String, dynamic>))
          .toList(),
      strokes: (json['strokes'] as List<dynamic>? ?? const [])
          .map((item) => PdfStroke.fromJson(item as Map<String, dynamic>))
          .toList(),
      textComments: (json['textComments'] as List<dynamic>? ?? const [])
          .map((item) => PdfTextComment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'stickyNotes': stickyNotes.map((item) => item.toJson()).toList(),
    'strokes': strokes.map((item) => item.toJson()).toList(),
    'textComments': textComments.map((item) => item.toJson()).toList(),
  };

  PdfAnnotationData copyWith({
    List<PdfStickyNote>? stickyNotes,
    List<PdfStroke>? strokes,
    List<PdfTextComment>? textComments,
  }) => PdfAnnotationData(
    stickyNotes: stickyNotes ?? this.stickyNotes,
    strokes: strokes ?? this.strokes,
    textComments: textComments ?? this.textComments,
  );
}
