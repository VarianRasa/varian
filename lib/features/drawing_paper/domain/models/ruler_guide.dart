import 'dart:ui';

enum RulerType {
  straight,
  circular,
  radialFocus,
  symmetryMirror,
  perspective1Point,
  perspective2Point,
  perspective3Point,
}

class RulerGuide {
  final String id;
  final RulerType type;
  final bool active;
  final bool visible;
  final Offset origin;
  final Offset target;
  final double radius;
  final int symmetrySlices; // 2, 4, 8, etc.
  final List<Offset> vanishingPoints;

  const RulerGuide({
    required this.id,
    required this.type,
    this.active = true,
    this.visible = true,
    this.origin = const Offset(100, 100),
    this.target = const Offset(300, 100),
    this.radius = 120.0,
    this.symmetrySlices = 2,
    this.vanishingPoints = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'active': active,
    'visible': visible,
    'origin': {'x': origin.dx, 'y': origin.dy},
    'target': {'x': target.dx, 'y': target.dy},
    'radius': radius,
    'symmetrySlices': symmetrySlices,
    'vanishingPoints': vanishingPoints
        .map((v) => {'x': v.dx, 'y': v.dy})
        .toList(),
  };

  factory RulerGuide.fromJson(Map<String, dynamic> json) => RulerGuide(
    id:
        json['id'] as String? ??
        'ruler_${DateTime.now().microsecondsSinceEpoch}',
    type: RulerType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => RulerType.straight,
    ),
    active: json['active'] as bool? ?? true,
    visible: json['visible'] as bool? ?? true,
    origin: Offset(
      (json['origin']?['x'] as num?)?.toDouble() ?? 100.0,
      (json['origin']?['y'] as num?)?.toDouble() ?? 100.0,
    ),
    target: Offset(
      (json['target']?['x'] as num?)?.toDouble() ?? 300.0,
      (json['target']?['y'] as num?)?.toDouble() ?? 100.0,
    ),
    radius: (json['radius'] as num?)?.toDouble() ?? 120.0,
    symmetrySlices: (json['symmetrySlices'] as num?)?.toInt() ?? 2,
    vanishingPoints:
        (json['vanishingPoints'] as List<dynamic>?)
            ?.map(
              (v) => Offset(
                (v['x'] as num).toDouble(),
                (v['y'] as num).toDouble(),
              ),
            )
            .toList() ??
        const [],
  );

  RulerGuide copyWith({
    String? id,
    RulerType? type,
    bool? active,
    bool? visible,
    Offset? origin,
    Offset? target,
    double? radius,
    int? symmetrySlices,
    List<Offset>? vanishingPoints,
  }) => RulerGuide(
    id: id ?? this.id,
    type: type ?? this.type,
    active: active ?? this.active,
    visible: visible ?? this.visible,
    origin: origin ?? this.origin,
    target: target ?? this.target,
    radius: radius ?? this.radius,
    symmetrySlices: symmetrySlices ?? this.symmetrySlices,
    vanishingPoints: vanishingPoints ?? this.vanishingPoints,
  );
}
