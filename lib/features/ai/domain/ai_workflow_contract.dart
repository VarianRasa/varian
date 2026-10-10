import 'dart:ui';

enum AIMaskOperation {
  inpaint,
  outpaint,
  replaceObject,
  removeObject,
  background,
}

class AIMaskStroke {
  final List<Offset> points;
  final double width;
  final bool erase;

  const AIMaskStroke({
    required this.points,
    required this.width,
    this.erase = false,
  });

  AIMaskStroke copyWith({List<Offset>? points, double? width, bool? erase}) =>
      AIMaskStroke(
        points: points ?? this.points,
        width: width ?? this.width,
        erase: erase ?? this.erase,
      );

  Map<String, dynamic> toJson() => {
    'points': [
      for (final point in points) {'x': point.dx, 'y': point.dy},
    ],
    'width': width,
    'erase': erase,
  };

  factory AIMaskStroke.fromJson(Map<String, dynamic> json) => AIMaskStroke(
    points: [
      for (final rawPoint in (json['points'] as List<dynamic>? ?? const []))
        if (rawPoint is Map)
          Offset(
            (rawPoint['x'] as num?)?.toDouble() ?? 0,
            (rawPoint['y'] as num?)?.toDouble() ?? 0,
          ),
    ],
    width: (json['width'] as num?)?.toDouble() ?? 24,
    erase: json['erase'] as bool? ?? false,
  );
}

class AIMaskDocument {
  final int width;
  final int height;
  final List<AIMaskStroke> strokes;
  final AIMaskOperation operation;

  const AIMaskDocument({
    required this.width,
    required this.height,
    required this.operation,
    this.strokes = const [],
  });

  bool get isEmpty => strokes.every((stroke) => stroke.points.isEmpty);

  AIMaskDocument copyWith({
    int? width,
    int? height,
    List<AIMaskStroke>? strokes,
    AIMaskOperation? operation,
  }) => AIMaskDocument(
    width: width ?? this.width,
    height: height ?? this.height,
    operation: operation ?? this.operation,
    strokes: strokes ?? this.strokes,
  );

  AIMaskDocument addStroke(AIMaskStroke stroke) => AIMaskDocument(
    width: width,
    height: height,
    operation: operation,
    strokes: [...strokes, stroke],
  );

  AIMaskDocument undo() => strokes.isEmpty
      ? this
      : AIMaskDocument(
          width: width,
          height: height,
          operation: operation,
          strokes: strokes.sublist(0, strokes.length - 1),
        );

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'operation': operation.name,
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(growable: false),
  };

  factory AIMaskDocument.fromJson(Map<String, dynamic> json) {
    final rawOperation = json['operation'] as String?;
    return AIMaskDocument(
      width: (json['width'] as num?)?.toInt() ?? 1,
      height: (json['height'] as num?)?.toInt() ?? 1,
      operation: AIMaskOperation.values.firstWhere(
        (value) => value.name == rawOperation,
        orElse: () => AIMaskOperation.inpaint,
      ),
      strokes: [
        for (final rawStroke in (json['strokes'] as List<dynamic>? ?? const []))
          if (rawStroke is Map)
            AIMaskStroke.fromJson(Map<String, dynamic>.from(rawStroke)),
      ],
    );
  }
}

class AIOutputVariant {
  final String id;
  final String? artifactReference;
  final int index;
  final bool favorite;
  final bool selectedForCompare;
  final String? license;
  final Map<String, dynamic> metadata;

  const AIOutputVariant({
    required this.id,
    required this.index,
    this.artifactReference,
    this.favorite = false,
    this.selectedForCompare = false,
    this.license,
    this.metadata = const {},
  });

  AIOutputVariant copyWith({
    Object? artifactReference = _sentinel,
    int? index,
    bool? favorite,
    bool? selectedForCompare,
    Object? license = _sentinel,
    Map<String, dynamic>? metadata,
  }) => AIOutputVariant(
    id: id,
    artifactReference: artifactReference == _sentinel
        ? this.artifactReference
        : artifactReference as String?,
    index: index ?? this.index,
    favorite: favorite ?? this.favorite,
    selectedForCompare: selectedForCompare ?? this.selectedForCompare,
    license: license == _sentinel ? this.license : license as String?,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'artifactReference': artifactReference,
    'index': index,
    'favorite': favorite,
    'selectedForCompare': selectedForCompare,
    'license': license,
    'metadata': metadata,
  };

  factory AIOutputVariant.fromJson(Map<String, dynamic> json) =>
      AIOutputVariant(
        id: json['id'] as String? ?? 'variant-${json['index'] ?? 0}',
        artifactReference: json['artifactReference'] as String?,
        index: (json['index'] as num?)?.toInt() ?? 0,
        favorite: json['favorite'] as bool? ?? false,
        selectedForCompare: json['selectedForCompare'] as bool? ?? false,
        license: json['license'] as String?,
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
      );

  static const Object _sentinel = Object();
}

class AIVariantSet {
  final String id;
  final List<AIOutputVariant> variants;

  const AIVariantSet({required this.id, this.variants = const []});

  Map<String, dynamic> toJson() => {
    'id': id,
    'variants': variants.map((variant) => variant.toJson()).toList(),
  };

  factory AIVariantSet.fromJson(Map<String, dynamic> json) => AIVariantSet(
    id: json['id'] as String? ?? 'variant-group',
    variants: [
      for (final item in (json['variants'] as List<dynamic>? ?? const []))
        if (item is Map)
          AIOutputVariant.fromJson(Map<String, dynamic>.from(item)),
    ],
  );

  AIVariantSet toggleFavorite(String variantId) => _update(
    variantId,
    (variant) => variant.copyWith(favorite: !variant.favorite),
  );

  AIVariantSet toggleCompare(String variantId) {
    final selectedCount = variants
        .where((item) => item.selectedForCompare)
        .length;
    return _update(
      variantId,
      (variant) => variant.copyWith(
        selectedForCompare: variant.selectedForCompare
            ? false
            : selectedCount < 2,
      ),
    );
  }

  List<AIOutputVariant> get compareSelection => variants
      .where((variant) => variant.selectedForCompare)
      .take(2)
      .toList(growable: false);

  AIVariantSet _update(
    String variantId,
    AIOutputVariant Function(AIOutputVariant variant) update,
  ) => AIVariantSet(
    id: id,
    variants: [
      for (final variant in variants)
        variant.id == variantId ? update(variant) : variant,
    ],
  );
}

enum AIProviderStatus { healthy, degraded, unavailable, experimental }

class AIProviderHealth {
  final String provider;
  final AIProviderStatus status;
  final DateTime checkedAt;
  final String? message;
  final Duration? latency;

  const AIProviderHealth({
    required this.provider,
    required this.status,
    required this.checkedAt,
    this.message,
    this.latency,
  });

  bool get canStartJob =>
      status == AIProviderStatus.healthy ||
      status == AIProviderStatus.experimental;
}

class AIQuotaSnapshot {
  final String scope;
  final double used;
  final double limit;
  final String unit;
  final DateTime? resetsAt;

  const AIQuotaSnapshot({
    required this.scope,
    required this.used,
    required this.limit,
    required this.unit,
    this.resetsAt,
  });

  double get remaining => (limit - used).clamp(0, limit).toDouble();
  bool get exhausted => remaining <= 0;
  bool allows(double amount) => amount >= 0 && used + amount <= limit;
}

class AIProvenanceNotice {
  final String provider;
  final String? model;
  final String? license;
  final String? sourceAttribution;
  final bool requiresDisclosure;
  final Map<String, dynamic> metadata;

  const AIProvenanceNotice({
    required this.provider,
    this.model,
    this.license,
    this.sourceAttribution,
    this.requiresDisclosure = true,
    this.metadata = const {},
  });

  String get disclosure {
    final pieces = <String>['Generated with $provider'];
    if (model != null && model!.isNotEmpty) pieces.add('model $model');
    if (license != null && license!.isNotEmpty) pieces.add('license $license');
    return pieces.join(' · ');
  }
}
