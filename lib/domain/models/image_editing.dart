import 'dart:math' as math;
import 'dart:ui';

import 'durable_asset_reference.dart';

class ImageCropSelection {
  final double x;
  final double y;
  final double width;
  final double height;

  const ImageCropSelection({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  const ImageCropSelection.full() : x = 0.0, y = 0.0, width = 1.0, height = 1.0;

  ImageCropSelection get normalized {
    final left = x.clamp(0.0, 1.0).toDouble();
    final top = y.clamp(0.0, 1.0).toDouble();
    final right = (x + width).clamp(left, 1.0).toDouble();
    final bottom = (y + height).clamp(top, 1.0).toDouble();
    return ImageCropSelection(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  factory ImageCropSelection.fromImageRect(Rect area, Size imageSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return const ImageCropSelection.full();
    }
    return ImageCropSelection(
      x: area.left / imageSize.width,
      y: area.top / imageSize.height,
      width: area.width / imageSize.width,
      height: area.height / imageSize.height,
    ).normalized;
  }

  Rect toImageRect(Size imageSize) {
    final selection = normalized;
    return Rect.fromLTWH(
      selection.x * imageSize.width,
      selection.y * imageSize.height,
      math.max(1.0, selection.width * imageSize.width),
      math.max(1.0, selection.height * imageSize.height),
    );
  }
}

enum ImageAdjustmentType {
  brightness,
  contrast,
  saturation,
  exposure,
  temperature,
  highlights,
  shadows,
  grayscale,
  sepia,
  invert,
  blur,
  opacity,
}

class ImageAdjustment {
  final String id;
  final ImageAdjustmentType type;
  final double amount;
  final bool enabled;

  const ImageAdjustment({
    required this.id,
    required this.type,
    required this.amount,
    this.enabled = true,
  });

  factory ImageAdjustment.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? '';
    return ImageAdjustment(
      id: json['id']?.toString() ?? 'adjustment',
      type: ImageAdjustmentType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => ImageAdjustmentType.brightness,
      ),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'amount': amount,
    'enabled': enabled,
  };

  ImageAdjustment copyWith({
    String? id,
    ImageAdjustmentType? type,
    double? amount,
    bool? enabled,
  }) => ImageAdjustment(
    id: id ?? this.id,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    enabled: enabled ?? this.enabled,
  );
}

enum ImageMaskMode { alpha, luminance, invertedLuminance }

class ImageMask {
  final String? assetId;

  /// Opaque owned image artifact reference for the mask source.
  final String? imageArtifactReference;

  /// Stable project-scoped Storage metadata for the mask source.
  final String? storagePath;
  final String? localPath;
  final String? url;
  final ImageMaskMode mode;
  final double opacity;
  final bool enabled;

  const ImageMask({
    this.assetId,
    this.imageArtifactReference,
    this.storagePath,
    this.localPath,
    this.url,
    this.mode = ImageMaskMode.alpha,
    this.opacity = 1.0,
    this.enabled = true,
  });

  String? get sourceKey {
    if (imageArtifactReference != null && imageArtifactReference!.isNotEmpty) {
      return imageArtifactReference;
    }
    if (storagePath != null && storagePath!.isNotEmpty) return storagePath;
    if (localPath != null && localPath!.isNotEmpty) return localPath;
    if (url != null && url!.isNotEmpty) return url;
    return null;
  }

  factory ImageMask.fromJson(Map<String, dynamic> json) => ImageMask(
    assetId: json['assetId'] as String?,
    imageArtifactReference: validImageArtifactReference(
      json['imageArtifactReference'] as String?,
    ),
    storagePath: durableAssetReference(json['storagePath'] as String?),
    // Local paths and runtime delivery URLs are restored only by the
    // transient hydration layer, never from durable document JSON.
    localPath: null,
    url: null,
    mode: ImageMaskMode.values.firstWhere(
      (value) => value.name == json['mode'],
      orElse: () => ImageMaskMode.alpha,
    ),
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    enabled: json['enabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'imageArtifactReference': ?validImageArtifactReference(
      imageArtifactReference,
    ),
    'storagePath': ?durableAssetReference(storagePath),
    'mode': mode.name,
    'opacity': opacity,
    'enabled': enabled,
  };

  ImageMask copyWith({
    String? assetId,
    String? imageArtifactReference,
    String? storagePath,
    String? localPath,
    String? url,
    ImageMaskMode? mode,
    double? opacity,
    bool? enabled,
  }) => ImageMask(
    assetId: assetId ?? this.assetId,
    imageArtifactReference:
        imageArtifactReference ?? this.imageArtifactReference,
    storagePath: storagePath ?? this.storagePath,
    localPath: localPath ?? this.localPath,
    url: url ?? this.url,
    mode: mode ?? this.mode,
    opacity: opacity ?? this.opacity,
    enabled: enabled ?? this.enabled,
  );
}
