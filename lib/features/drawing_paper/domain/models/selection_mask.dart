import 'dart:ui';

enum SelectionToolType { rectangle, ellipse, lasso, magicWand, quickMaskBrush }

enum SelectionOperation { replace, add, subtract, intersect }

class SelectionMask {
  final SelectionToolType toolType;
  final List<Offset> outlinePoints;
  final Rect? boundingBox;
  final bool inverted;
  final double featherRadius;

  const SelectionMask({
    this.toolType = SelectionToolType.lasso,
    this.outlinePoints = const [],
    this.boundingBox,
    this.inverted = false,
    this.featherRadius = 0.0,
  });

  bool get isEmpty => outlinePoints.isEmpty && boundingBox == null;
  bool get isNotEmpty => !isEmpty;

  static Rect? boundsOf(List<Offset> pts) {
    if (pts.isEmpty) return null;
    double l = double.infinity,
        t = double.infinity,
        r = -double.infinity,
        b = -double.infinity;
    for (final p in pts) {
      if (p.dx < l) l = p.dx;
      if (p.dy < t) t = p.dy;
      if (p.dx > r) r = p.dx;
      if (p.dy > b) b = p.dy;
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  Map<String, dynamic> toJson() => {
    'toolType': toolType.name,
    'outlinePoints': outlinePoints.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    'boundingBox': boundingBox != null
        ? {
            'l': boundingBox!.left,
            't': boundingBox!.top,
            'w': boundingBox!.width,
            'h': boundingBox!.height,
          }
        : null,
    'inverted': inverted,
    'featherRadius': featherRadius,
  };

  factory SelectionMask.fromJson(Map<String, dynamic> json) => SelectionMask(
    toolType: SelectionToolType.values.firstWhere(
      (t) => t.name == json['toolType'],
      orElse: () => SelectionToolType.lasso,
    ),
    outlinePoints:
        (json['outlinePoints'] as List<dynamic>?)
            ?.map(
              (p) => Offset(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ),
            )
            .toList() ??
        const [],
    boundingBox: json['boundingBox'] != null
        ? Rect.fromLTWH(
            (json['boundingBox']['l'] as num).toDouble(),
            (json['boundingBox']['t'] as num).toDouble(),
            (json['boundingBox']['w'] as num).toDouble(),
            (json['boundingBox']['h'] as num).toDouble(),
          )
        : null,
    inverted: json['inverted'] as bool? ?? false,
    featherRadius: (json['featherRadius'] as num?)?.toDouble() ?? 0.0,
  );

  SelectionMask clone() => SelectionMask(
    toolType: toolType,
    outlinePoints: List.of(outlinePoints),
    boundingBox: boundingBox,
    inverted: inverted,
    featherRadius: featherRadius,
  );

  SelectionMask copyWith({
    SelectionToolType? toolType,
    List<Offset>? outlinePoints,
    Rect? boundingBox,
    bool? inverted,
    double? featherRadius,
  }) => SelectionMask(
    toolType: toolType ?? this.toolType,
    outlinePoints: outlinePoints ?? this.outlinePoints,
    boundingBox: boundingBox ?? this.boundingBox,
    inverted: inverted ?? this.inverted,
    featherRadius: featherRadius ?? this.featherRadius,
  );
}
