class Model3DCameraBookmark {
  final String id;
  final String label;
  final double positionX;
  final double positionY;
  final double positionZ;
  final double targetX;
  final double targetY;
  final double targetZ;

  const Model3DCameraBookmark({
    required this.id,
    this.label = 'Camera view',
    this.positionX = 0,
    this.positionY = 0.35,
    this.positionZ = 3.2,
    this.targetX = 0,
    this.targetY = 0,
    this.targetZ = 0,
  });

  Model3DCameraBookmark normalized() => Model3DCameraBookmark(
    id: id.trim().isEmpty ? 'camera' : id.trim(),
    label: label.trim().isEmpty ? 'Camera view' : label.trim(),
    positionX: _finite(positionX, 0),
    positionY: _finite(positionY, 0.35),
    positionZ: _finite(positionZ, 3.2),
    targetX: _finite(targetX, 0),
    targetY: _finite(targetY, 0),
    targetZ: _finite(targetZ, 0),
  );

  factory Model3DCameraBookmark.fromJson(Map<String, dynamic> json) =>
      Model3DCameraBookmark(
        id: json['id'] as String? ?? 'camera',
        label: json['label'] as String? ?? 'Camera view',
        positionX: _number(json['positionX'], 0),
        positionY: _number(json['positionY'], 0.35),
        positionZ: _number(json['positionZ'], 3.2),
        targetX: _number(json['targetX'], 0),
        targetY: _number(json['targetY'], 0),
        targetZ: _number(json['targetZ'], 0),
      ).normalized();

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'positionX': positionX,
    'positionY': positionY,
    'positionZ': positionZ,
    'targetX': targetX,
    'targetY': targetY,
    'targetZ': targetZ,
  };

  Model3DCameraBookmark copyWith({
    String? id,
    String? label,
    double? positionX,
    double? positionY,
    double? positionZ,
    double? targetX,
    double? targetY,
    double? targetZ,
  }) => Model3DCameraBookmark(
    id: id ?? this.id,
    label: label ?? this.label,
    positionX: positionX ?? this.positionX,
    positionY: positionY ?? this.positionY,
    positionZ: positionZ ?? this.positionZ,
    targetX: targetX ?? this.targetX,
    targetY: targetY ?? this.targetY,
    targetZ: targetZ ?? this.targetZ,
  );
}

class Model3DAnnotation {
  final String id;
  final String label;
  final String text;
  final double x;
  final double y;
  final double z;
  final int colorArgb;
  final bool visible;

  const Model3DAnnotation({
    required this.id,
    this.label = 'Annotation',
    this.text = '',
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.colorArgb = 0xFFFFA726,
    this.visible = true,
  });

  Model3DAnnotation normalized() => Model3DAnnotation(
    id: id.trim().isEmpty ? 'annotation' : id.trim(),
    label: label.trim().isEmpty ? 'Annotation' : label.trim(),
    text: text.trim(),
    x: _finite(x, 0),
    y: _finite(y, 0),
    z: _finite(z, 0),
    colorArgb: colorArgb.clamp(0, 0xFFFFFFFF).toInt(),
    visible: visible,
  );

  factory Model3DAnnotation.fromJson(Map<String, dynamic> json) =>
      Model3DAnnotation(
        id: json['id'] as String? ?? 'annotation',
        label: json['label'] as String? ?? 'Annotation',
        text: json['text'] as String? ?? '',
        x: _number(json['x'], 0),
        y: _number(json['y'], 0),
        z: _number(json['z'], 0),
        colorArgb: (json['colorArgb'] as num?)?.toInt() ?? 0xFFFFA726,
        visible: json['visible'] as bool? ?? true,
      ).normalized();

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'text': text,
    'x': x,
    'y': y,
    'z': z,
    'colorArgb': colorArgb,
    'visible': visible,
  };

  Model3DAnnotation copyWith({
    String? id,
    String? label,
    String? text,
    double? x,
    double? y,
    double? z,
    int? colorArgb,
    bool? visible,
  }) => Model3DAnnotation(
    id: id ?? this.id,
    label: label ?? this.label,
    text: text ?? this.text,
    x: x ?? this.x,
    y: y ?? this.y,
    z: z ?? this.z,
    colorArgb: colorArgb ?? this.colorArgb,
    visible: visible ?? this.visible,
  );
}

enum Model3DLightingPreset { studio, neutral, dramatic, flat }

class Model3DSnapshot {
  final String id;
  final String label;

  /// Stable manifest identity for the persisted snapshot image.
  final String? assetId;
  final String? cameraBookmarkId;
  final String? artifactReference;
  final int width;
  final int height;
  final String createdAt;

  const Model3DSnapshot({
    required this.id,
    this.label = 'Snapshot',
    this.assetId,
    this.cameraBookmarkId,
    this.artifactReference,
    this.width = 0,
    this.height = 0,
    this.createdAt = '',
  });

  Model3DSnapshot normalized() => Model3DSnapshot(
    id: id.trim().isEmpty ? 'snapshot' : id.trim(),
    label: label.trim().isEmpty ? 'Snapshot' : label.trim(),
    assetId: _clean(assetId),
    cameraBookmarkId: _clean(cameraBookmarkId),
    artifactReference: _clean(artifactReference),
    width: width.clamp(0, 16_384).toInt(),
    height: height.clamp(0, 16_384).toInt(),
    createdAt: createdAt.trim(),
  );

  factory Model3DSnapshot.fromJson(Map<String, dynamic> json) =>
      Model3DSnapshot(
        id: json['id'] as String? ?? 'snapshot',
        label: json['label'] as String? ?? 'Snapshot',
        assetId: json['assetId'] as String?,
        cameraBookmarkId: json['cameraBookmarkId'] as String?,
        artifactReference: json['artifactReference'] as String?,
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
      ).normalized();

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'assetId': assetId,
    'cameraBookmarkId': cameraBookmarkId,
    'artifactReference': artifactReference,
    'width': width,
    'height': height,
    'createdAt': createdAt,
  };

  Model3DSnapshot copyWith({
    String? id,
    String? label,
    Object? assetId = _sentinel,
    Object? cameraBookmarkId = _sentinel,
    Object? artifactReference = _sentinel,
    int? width,
    int? height,
    String? createdAt,
  }) => Model3DSnapshot(
    id: id ?? this.id,
    label: label ?? this.label,
    assetId: assetId == _sentinel ? this.assetId : assetId as String?,
    cameraBookmarkId: cameraBookmarkId == _sentinel
        ? this.cameraBookmarkId
        : cameraBookmarkId as String?,
    artifactReference: artifactReference == _sentinel
        ? this.artifactReference
        : artifactReference as String?,
    width: width ?? this.width,
    height: height ?? this.height,
    createdAt: createdAt ?? this.createdAt,
  );

  static const Object _sentinel = Object();
}

double _number(Object? raw, double fallback) =>
    raw is num && raw.toDouble().isFinite ? raw.toDouble() : fallback;

double _finite(double value, double fallback) =>
    value.isFinite ? value : fallback;

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
