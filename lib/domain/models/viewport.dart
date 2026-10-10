class Viewport {
  final double x;
  final double y;
  final double zoom;

  const Viewport({this.x = 0.0, this.y = 0.0, this.zoom = 1.0});

  Viewport copyWith({double? x, double? y, double? zoom}) {
    return Viewport(
      x: x ?? this.x,
      y: y ?? this.y,
      zoom: (zoom ?? this.zoom).clamp(0.1, 5.0),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'zoom': zoom};

  factory Viewport.fromJson(Map<String, dynamic> json) {
    return Viewport(
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      zoom: ((json['zoom'] as num?)?.toDouble() ?? 1.0).clamp(0.1, 5.0),
    );
  }
}
