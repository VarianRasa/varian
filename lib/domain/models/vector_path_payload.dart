import 'package:flutter/material.dart';
import 'node_payload.dart';

enum PointType {
  corner, // sharp corner without handles (or independent sharp)
  mirrored, // symmetric / mirrored handles
  disconnected, // broken / asymmetrical angle handles
}

enum VectorStrokeCap { round, butt, square }

enum VectorStrokeJoin { round, miter, bevel }

enum VectorFillRule { nonZero, evenOdd }

enum VectorMaskMode { alpha, luminance, invertedLuminance }

enum VectorEffectType { dropShadow, innerShadow, blur, outline }

class VectorEffect {
  final VectorEffectType type;
  final bool enabled;
  final Color color;
  final double blurRadius;
  final Offset offset;
  final double spread;

  const VectorEffect({
    required this.type,
    this.enabled = true,
    this.color = const Color(0x66000000),
    this.blurRadius = 0.0,
    this.offset = Offset.zero,
    this.spread = 0.0,
  });

  VectorEffect copyWith({
    VectorEffectType? type,
    bool? enabled,
    Color? color,
    double? blurRadius,
    Offset? offset,
    double? spread,
  }) => VectorEffect(
    type: type ?? this.type,
    enabled: enabled ?? this.enabled,
    color: color ?? this.color,
    blurRadius: blurRadius ?? this.blurRadius,
    offset: offset ?? this.offset,
    spread: spread ?? this.spread,
  );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'enabled': enabled,
    'color': color.toARGB32(),
    'blurRadius': blurRadius,
    'offsetX': offset.dx,
    'offsetY': offset.dy,
    'spread': spread,
  };

  factory VectorEffect.fromJson(Map<String, dynamic> json) => VectorEffect(
    type: VectorEffectType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => VectorEffectType.dropShadow,
    ),
    enabled: json['enabled'] as bool? ?? true,
    color: Color((json['color'] as num?)?.toInt() ?? 0x66000000),
    blurRadius: ((json['blurRadius'] as num?)?.toDouble() ?? 0.0).clamp(
      0.0,
      1000.0,
    ),
    offset: Offset(
      ((json['offsetX'] as num?)?.toDouble() ?? 0.0).clamp(
        -1000000.0,
        1000000.0,
      ),
      ((json['offsetY'] as num?)?.toDouble() ?? 0.0).clamp(
        -1000000.0,
        1000000.0,
      ),
    ),
    spread: ((json['spread'] as num?)?.toDouble() ?? 0.0).clamp(
      -1000.0,
      1000.0,
    ),
  );
}

class BezierPoint {
  final Offset point;
  final Offset handleIn;
  final Offset handleOut;
  final PointType type;
  final double cornerRadius;

  const BezierPoint({
    required this.point,
    this.handleIn = Offset.zero,
    this.handleOut = Offset.zero,
    this.type = PointType.mirrored,
    this.cornerRadius = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'px': point.dx,
    'py': point.dy,
    'hix': handleIn.dx,
    'hiy': handleIn.dy,
    'hox': handleOut.dx,
    'hoy': handleOut.dy,
    'type': type.name,
    'cornerRadius': cornerRadius,
  };

  factory BezierPoint.fromJson(Map<String, dynamic> json) => BezierPoint(
    point: Offset(
      (json['px'] as num).toDouble(),
      (json['py'] as num).toDouble(),
    ),
    handleIn: Offset(
      (json['hix'] as num?)?.toDouble() ?? 0.0,
      (json['hiy'] as num?)?.toDouble() ?? 0.0,
    ),
    handleOut: Offset(
      (json['hox'] as num?)?.toDouble() ?? 0.0,
      (json['hoy'] as num?)?.toDouble() ?? 0.0,
    ),
    type: PointType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => PointType.mirrored,
    ),
    cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 0.0,
  );

  BezierPoint copyWith({
    Offset? point,
    Offset? handleIn,
    Offset? handleOut,
    PointType? type,
    double? cornerRadius,
  }) {
    return BezierPoint(
      point: point ?? this.point,
      handleIn: handleIn ?? this.handleIn,
      handleOut: handleOut ?? this.handleOut,
      type: type ?? this.type,
      cornerRadius: cornerRadius ?? this.cornerRadius,
    );
  }
}

class VectorPathPayload extends NodePayload {
  final List<BezierPoint> points;
  final bool isClosed;
  final List<List<BezierPoint>> subpaths;
  final List<bool> subpathClosed;
  final VectorFillRule fillRule;
  final Color fill;
  final Color stroke;
  final double strokeWidth;
  final VectorStrokeCap strokeCap;
  final VectorStrokeJoin strokeJoin;
  final List<double> dashPattern;
  final double dashOffset;
  final bool isGradientFill;
  final FillType gradientType;
  final Color gradientEndColor;
  final String? maskNodeId;
  final VectorMaskMode maskMode;
  final List<VectorEffect> effects;

  VectorPathPayload({
    List<BezierPoint> points = const [],
    this.isClosed = true,
    this.subpaths = const [],
    this.subpathClosed = const [],
    this.fillRule = VectorFillRule.nonZero,
    this.fill = const Color(0xFFF97316), // Signal Orange
    this.stroke = const Color(0xFFFDBA74),
    this.strokeWidth = 2.0,
    this.strokeCap = VectorStrokeCap.round,
    this.strokeJoin = VectorStrokeJoin.round,
    this.dashPattern = const [],
    this.dashOffset = 0.0,
    this.isGradientFill = false,
    this.gradientType = FillType.linearGradient,
    this.gradientEndColor = const Color(0xFFEA580C),
    this.maskNodeId,
    this.maskMode = VectorMaskMode.alpha,
    this.effects = const [],
  }) : points = subpaths.isEmpty
           ? points
           : List<BezierPoint>.unmodifiable(subpaths.expand((path) => path));

  List<List<BezierPoint>> get allSubpaths => subpaths.isNotEmpty
      ? subpaths
      : points.isEmpty
      ? const []
      : <List<BezierPoint>>[points];

  List<bool> get allSubpathClosed => subpaths.isEmpty
      ? points.isEmpty
            ? const []
            : <bool>[isClosed]
      : List<bool>.generate(
          subpaths.length,
          (index) =>
              index < subpathClosed.length ? subpathClosed[index] : isClosed,
        );

  factory VectorPathPayload.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? [];
    final rawSubpaths = json['subpaths'] as List<dynamic>? ?? [];
    final rawClosed = json['subpathClosed'] as List<dynamic>? ?? [];
    final rawDashes = json['dashPattern'] as List<dynamic>? ?? [];
    if (rawSubpaths.length > 256 ||
        rawClosed.length > 256 ||
        rawDashes.length > 128) {
      throw const FormatException('Vector geometry exceeds storage limits.');
    }
    final parsedSubpaths = rawSubpaths.map(_readPoints).toList(growable: false);
    if (parsedSubpaths.fold<int>(0, (sum, path) => sum + path.length) > 4096) {
      throw const FormatException('Too many vector points.');
    }
    return VectorPathPayload(
      points: _readPoints(rawPoints),
      isClosed: json['isClosed'] as bool? ?? true,
      subpaths: parsedSubpaths,
      subpathClosed: rawClosed
          .take(256)
          .map((value) => value == true)
          .toList(growable: false),
      fillRule: VectorFillRule.values.firstWhere(
        (e) => e.name == json['fillRule'],
        orElse: () => VectorFillRule.nonZero,
      ),
      fill: Color((json['fill'] as num?)?.toInt() ?? 0xFF6366F1),
      stroke: Color((json['stroke'] as num?)?.toInt() ?? 0xFF818CF8),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      strokeCap: VectorStrokeCap.values.firstWhere(
        (e) => e.name == json['strokeCap'],
        orElse: () => VectorStrokeCap.round,
      ),
      strokeJoin: VectorStrokeJoin.values.firstWhere(
        (e) => e.name == json['strokeJoin'],
        orElse: () => VectorStrokeJoin.round,
      ),
      dashPattern: _readDashes(rawDashes),
      dashOffset: _readFiniteNumber(json['dashOffset']) ?? 0.0,
      isGradientFill: json['isGradientFill'] as bool? ?? false,
      gradientType: FillType.values.firstWhere(
        (e) => e.name == json['gradientType'],
        orElse: () => FillType.linearGradient,
      ),
      gradientEndColor: Color(
        (json['gradientEndColor'] as num?)?.toInt() ?? 0xFFEA580C,
      ),
      maskNodeId: json['maskNodeId'] as String?,
      maskMode: VectorMaskMode.values.firstWhere(
        (value) => value.name == json['maskMode'],
        orElse: () => VectorMaskMode.alpha,
      ),
      effects: (json['effects'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .take(32)
          .map(
            (value) => VectorEffect.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false),
    );
  }

  static double? _readFiniteNumber(Object? value) {
    if (value is! num || !value.isFinite || value.abs() > 10000000) {
      if (value == null) return null;
      throw const FormatException('Invalid vector number.');
    }
    return value.toDouble();
  }

  static List<double> _readDashes(List<dynamic> raw) {
    return raw
        .map((value) {
          final number = _readFiniteNumber(value);
          if (number == null || number < 0) {
            throw const FormatException('Invalid vector dash pattern.');
          }
          return number;
        })
        .toList(growable: false);
  }

  static List<BezierPoint> _readPoints(Object? raw) {
    if (raw is! List || raw.length > 4096) {
      throw const FormatException('Invalid vector point list.');
    }
    return raw
        .map((value) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Invalid vector point.');
          }
          for (final key in [
            'px',
            'py',
            'hix',
            'hiy',
            'hox',
            'hoy',
            'cornerRadius',
          ]) {
            final number = value[key];
            if (number == null && key != 'px' && key != 'py') continue;
            if (number is! num || !number.isFinite || number.abs() > 10000000) {
              throw const FormatException('Invalid vector coordinate.');
            }
          }
          return BezierPoint.fromJson(value);
        })
        .toList(growable: false);
  }

  Path toPath({bool closeOpenSubpaths = false}) {
    final path = Path()
      ..fillType = fillRule == VectorFillRule.evenOdd
          ? PathFillType.evenOdd
          : PathFillType.nonZero;
    final contours = allSubpaths;
    final closed = allSubpathClosed;
    void segment(BezierPoint from, BezierPoint to) {
      if (from.handleOut == Offset.zero && to.handleIn == Offset.zero) {
        path.lineTo(to.point.dx, to.point.dy);
      } else {
        final a = from.point + from.handleOut;
        final b = to.point + to.handleIn;
        path.cubicTo(a.dx, a.dy, b.dx, b.dy, to.point.dx, to.point.dy);
      }
    }

    for (var index = 0; index < contours.length; index++) {
      final points = contours[index];
      if (points.isEmpty) continue;
      path.moveTo(points.first.point.dx, points.first.point.dy);
      for (var i = 1; i < points.length; i++) {
        segment(points[i - 1], points[i]);
      }
      if (closed[index] || closeOpenSubpaths) {
        if (points.length > 1) segment(points.last, points.first);
        path.close();
      }
    }
    return path;
  }

  String toSvgPathData({Offset offset = Offset.zero}) {
    final result = StringBuffer();
    final contours = allSubpaths;
    final closed = allSubpathClosed;
    void segment(BezierPoint from, BezierPoint to) {
      final end = to.point + offset;
      if (from.handleOut == Offset.zero && to.handleIn == Offset.zero) {
        result.write('L ${end.dx} ${end.dy} ');
      } else {
        final a = from.point + from.handleOut + offset;
        final b = to.point + to.handleIn + offset;
        result.write('C ${a.dx} ${a.dy} ${b.dx} ${b.dy} ${end.dx} ${end.dy} ');
      }
    }

    for (var index = 0; index < contours.length; index++) {
      final points = contours[index];
      if (points.isEmpty) continue;
      final start = points.first.point + offset;
      result.write('M ${start.dx} ${start.dy} ');
      for (var i = 1; i < points.length; i++) {
        segment(points[i - 1], points[i]);
      }
      if (closed[index]) {
        if (points.length > 1) segment(points.last, points.first);
        result.write('Z ');
      }
    }
    return result.toString().trimRight();
  }

  @override
  Map<String, dynamic> toJson() => {
    'points': (subpaths.isEmpty ? points : subpaths.first)
        .map((p) => p.toJson())
        .toList(),
    'isClosed': isClosed,
    if (subpaths.isNotEmpty)
      'subpaths': subpaths
          .map((subpath) => subpath.map((p) => p.toJson()).toList())
          .toList(),
    if (subpathClosed.isNotEmpty) 'subpathClosed': subpathClosed,
    'fillRule': fillRule.name,
    'fill': fill.toARGB32(),
    'stroke': stroke.toARGB32(),
    'strokeWidth': strokeWidth,
    'strokeCap': strokeCap.name,
    'strokeJoin': strokeJoin.name,
    'dashPattern': dashPattern,
    'dashOffset': dashOffset,
    'isGradientFill': isGradientFill,
    'gradientType': gradientType.name,
    'gradientEndColor': gradientEndColor.toARGB32(),
    'maskNodeId': maskNodeId,
    'maskMode': maskMode.name,
    'effects': effects.map((effect) => effect.toJson()).toList(growable: false),
  };

  @override
  VectorPathPayload clone() => VectorPathPayload(
    points: List.of(points),
    isClosed: isClosed,
    subpaths: subpaths
        .map((subpath) => List<BezierPoint>.of(subpath))
        .toList(growable: false),
    subpathClosed: List<bool>.of(subpathClosed),
    fillRule: fillRule,
    fill: fill,
    stroke: stroke,
    strokeWidth: strokeWidth,
    strokeCap: strokeCap,
    strokeJoin: strokeJoin,
    dashPattern: List.of(dashPattern),
    dashOffset: dashOffset,
    isGradientFill: isGradientFill,
    gradientType: gradientType,
    gradientEndColor: gradientEndColor,
    maskNodeId: maskNodeId,
    maskMode: maskMode,
    effects: effects.map((effect) => effect.copyWith()).toList(growable: false),
  );

  VectorPathPayload copyWith({
    List<BezierPoint>? points,
    bool? isClosed,
    List<List<BezierPoint>>? subpaths,
    List<bool>? subpathClosed,
    VectorFillRule? fillRule,
    Color? fill,
    Color? stroke,
    double? strokeWidth,
    VectorStrokeCap? strokeCap,
    VectorStrokeJoin? strokeJoin,
    List<double>? dashPattern,
    double? dashOffset,
    bool? isGradientFill,
    FillType? gradientType,
    Color? gradientEndColor,
    Object? maskNodeId = _sentinel,
    VectorMaskMode? maskMode,
    List<VectorEffect>? effects,
  }) {
    var contours = subpaths ?? this.subpaths;
    if (points != null && subpaths == null && contours.isNotEmpty) {
      if (points.length != this.points.length) {
        throw ArgumentError(
          'Edit contours explicitly when changing point count.',
        );
      }
      var offset = 0;
      contours = contours
          .map((contour) {
            final updated = points.sublist(offset, offset + contour.length);
            offset += contour.length;
            return updated;
          })
          .toList(growable: false);
    }
    return VectorPathPayload(
      points: points ?? this.points,
      isClosed: isClosed ?? this.isClosed,
      subpaths: contours,
      subpathClosed:
          subpathClosed ??
          (isClosed == null
              ? this.subpathClosed
              : List.filled(contours.length, isClosed)),
      fillRule: fillRule ?? this.fillRule,
      fill: fill ?? this.fill,
      stroke: stroke ?? this.stroke,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeCap: strokeCap ?? this.strokeCap,
      strokeJoin: strokeJoin ?? this.strokeJoin,
      dashPattern: dashPattern ?? this.dashPattern,
      dashOffset: dashOffset ?? this.dashOffset,
      isGradientFill: isGradientFill ?? this.isGradientFill,
      gradientType: gradientType ?? this.gradientType,
      gradientEndColor: gradientEndColor ?? this.gradientEndColor,
      maskNodeId: maskNodeId == _sentinel
          ? this.maskNodeId
          : maskNodeId as String?,
      maskMode: maskMode ?? this.maskMode,
      effects: effects ?? this.effects,
    );
  }

  static const Object _sentinel = Object();
}
