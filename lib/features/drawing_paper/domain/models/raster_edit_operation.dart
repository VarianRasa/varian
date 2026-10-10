import 'package:flutter/material.dart';

import 'selection_mask.dart';

enum RasterEditKind { bucketFill, smudge, blur, transform }

/// A compact, replayable edit. Pixel buffers stay out of CanvasDocument JSON.
class RasterEditOperation {
  final String id;
  final RasterEditKind kind;
  final Offset seedPoint;
  final List<Offset> points;
  final Rect? bounds;
  final Color color;
  final double tolerance;
  final double radius;
  final double strength;
  final double scale;
  final double rotation;
  final bool flipH;
  final bool flipV;
  final SelectionMask? selection;

  const RasterEditOperation({
    required this.id,
    required this.kind,
    this.seedPoint = Offset.zero,
    this.points = const [],
    this.bounds,
    this.color = Colors.transparent,
    this.tolerance = 24.0,
    this.radius = 24.0,
    this.strength = 0.65,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.flipH = false,
    this.flipV = false,
    this.selection,
  });

  factory RasterEditOperation.bucketFill({
    required Offset seedPoint,
    required Color color,
    double tolerance = 24.0,
    SelectionMask? selection,
  }) => RasterEditOperation(
    id: 'raster_fill_${DateTime.now().microsecondsSinceEpoch}',
    kind: RasterEditKind.bucketFill,
    seedPoint: seedPoint,
    color: color,
    tolerance: tolerance,
    selection: selection,
  );

  factory RasterEditOperation.smudge({
    required List<Offset> points,
    required double radius,
    double strength = 0.65,
    SelectionMask? selection,
  }) => RasterEditOperation(
    id: 'raster_smudge_${DateTime.now().microsecondsSinceEpoch}',
    kind: RasterEditKind.smudge,
    points: List.unmodifiable(points),
    radius: radius,
    strength: strength,
    selection: selection,
  );

  factory RasterEditOperation.blur({
    required List<Offset> points,
    required double radius,
    double strength = 0.65,
    SelectionMask? selection,
  }) => RasterEditOperation(
    id: 'raster_blur_${DateTime.now().microsecondsSinceEpoch}',
    kind: RasterEditKind.blur,
    points: List.unmodifiable(points),
    radius: radius,
    strength: strength,
    selection: selection,
  );

  factory RasterEditOperation.transform({
    required Rect bounds,
    Offset translation = Offset.zero,
    double scale = 1.0,
    double rotation = 0.0,
    bool flipH = false,
    bool flipV = false,
    SelectionMask? selection,
  }) => RasterEditOperation(
    id: 'raster_transform_${DateTime.now().microsecondsSinceEpoch}',
    kind: RasterEditKind.transform,
    points: [translation],
    bounds: bounds,
    scale: scale,
    rotation: rotation,
    flipH: flipH,
    flipV: flipV,
    selection: selection,
  );

  Offset get translation => points.isEmpty ? Offset.zero : points.first;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'seed': {'x': seedPoint.dx, 'y': seedPoint.dy},
    'points': points.map((point) => {'x': point.dx, 'y': point.dy}).toList(),
    'bounds': bounds == null
        ? null
        : {
            'l': bounds!.left,
            't': bounds!.top,
            'w': bounds!.width,
            'h': bounds!.height,
          },
    'color': color.toARGB32(),
    'tolerance': tolerance,
    'radius': radius,
    'strength': strength,
    'scale': scale,
    'rotation': rotation,
    'flipH': flipH,
    'flipV': flipV,
    'selection': selection?.toJson(),
  };

  factory RasterEditOperation.fromJson(Map<String, dynamic> json) {
    Offset readOffset(Object? raw, Offset fallback) {
      if (raw is! Map) return fallback;
      return Offset(
        (raw['x'] as num?)?.toDouble() ?? fallback.dx,
        (raw['y'] as num?)?.toDouble() ?? fallback.dy,
      );
    }

    final rawBounds = json['bounds'];
    final parsedBounds = rawBounds is Map
        ? Rect.fromLTWH(
            (rawBounds['l'] as num?)?.toDouble() ?? 0,
            (rawBounds['t'] as num?)?.toDouble() ?? 0,
            (rawBounds['w'] as num?)?.toDouble() ?? 0,
            (rawBounds['h'] as num?)?.toDouble() ?? 0,
          )
        : null;
    final rawPoints = json['points'];
    final parsedPoints = rawPoints is List
        ? rawPoints
              .whereType<Map>()
              .map((point) => readOffset(point, Offset.zero))
              .toList()
        : const <Offset>[];
    final rawSelection = json['selection'];

    return RasterEditOperation(
      id:
          json['id'] as String? ??
          'raster_${DateTime.now().microsecondsSinceEpoch}',
      kind: RasterEditKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => RasterEditKind.bucketFill,
      ),
      seedPoint: readOffset(json['seed'], Offset.zero),
      points: parsedPoints,
      bounds: parsedBounds,
      color: Color((json['color'] as num?)?.toInt() ?? 0x00000000),
      tolerance: (json['tolerance'] as num?)?.toDouble() ?? 24.0,
      radius: (json['radius'] as num?)?.toDouble() ?? 24.0,
      strength: (json['strength'] as num?)?.toDouble() ?? 0.65,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      flipH: json['flipH'] as bool? ?? false,
      flipV: json['flipV'] as bool? ?? false,
      selection: rawSelection is Map
          ? SelectionMask.fromJson(Map<String, dynamic>.from(rawSelection))
          : null,
    );
  }
}
