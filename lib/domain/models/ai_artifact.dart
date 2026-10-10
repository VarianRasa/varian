import 'dart:typed_data';

import 'durable_asset_reference.dart';

enum AIArtifactKind { image, video, model3d }

class AIArtifact {
  final AIArtifactKind kind;
  final String? path;
  final String? url;
  final String? reference;
  final String? fileName;
  final String? mimeType;
  final int? byteLength;
  final String? previewUrl;
  final String? provider;

  /// Runtime-only bytes supplied by a provider or owned artifact store. This
  /// field is intentionally omitted from every durable serializer.
  final Uint8List? bytes;

  const AIArtifact({
    required this.kind,
    this.path,
    this.url,
    this.reference,
    this.fileName,
    this.mimeType,
    this.byteLength,
    this.previewUrl,
    this.provider,
    this.bytes,
  });

  bool get hasSource => _hasText(path) || _hasText(url) || _hasText(reference);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    // Runtime paths, URLs, object URLs, and provider references are never
    // persisted in AI history. Only typed opaque handles or stable Storage
    // metadata are retained.
    'path': null,
    'url': null,
    'reference': _durableReferenceForKind(kind, reference),
    'fileName': fileName,
    'mimeType': mimeType,
    'byteLength': byteLength,
    'previewUrl': null,
    'provider': provider,
  };

  factory AIArtifact.fromJson(Map<String, dynamic> json) => AIArtifact(
    kind: _kindFromJson(json['kind']),
    path: null,
    url: null,
    reference: _durableReferenceForKind(
      _kindFromJson(json['kind']),
      json['reference'] as String?,
    ),
    fileName: json['fileName'] as String?,
    mimeType: json['mimeType'] as String?,
    byteLength: (json['byteLength'] as num?)?.toInt(),
    previewUrl: null,
    provider: json['provider'] as String?,
  );

  static String? _durableReferenceForKind(AIArtifactKind kind, String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return switch (kind) {
      AIArtifactKind.image => validImageArtifactReference(normalized),
      AIArtifactKind.video => validVideoArtifactReference(normalized),
      // Model3D imports may already point at a stable bucket-relative Storage
      // path. Local runtime paths and signed URLs remain rejected.
      AIArtifactKind.model3d =>
        validModel3DArtifactReference(normalized) ??
            durableAssetReference(normalized),
    };
  }

  static AIArtifactKind _kindFromJson(Object? value) =>
      AIArtifactKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => AIArtifactKind.model3d,
      );

  static bool _hasText(String? value) => value?.trim().isNotEmpty == true;
}
