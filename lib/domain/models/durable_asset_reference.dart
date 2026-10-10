/// Returns true for values that are runtime-only asset references or signed
/// delivery URLs and must not enter durable document/catalog JSON.
bool isTransientAssetReference(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return true;
  if (normalized.startsWith('data:') ||
      normalized.startsWith('blob:') ||
      normalized.startsWith('content:') ||
      normalized.startsWith('memory://') ||
      normalized.startsWith('internal://') ||
      normalized.startsWith('raster://')) {
    return true;
  }
  final uri = Uri.tryParse(value!.trim());
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    // Supabase signed delivery and other temporary credentials are carried in
    // the query string. Durable asset metadata must never retain them.
    return uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        value.codeUnits.any((code) => code <= 0x20 || code == 0x7f);
  }
  return false;
}

/// Keeps a stable, project-scoped Storage path while dropping runtime
/// delivery values. Public/provider URLs remain compatibility-only sources.
String? durableAssetReference(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty || value != normalized) {
    return null;
  }
  if (isTransientAssetReference(normalized)) return null;

  final uri = Uri.tryParse(normalized);
  if (uri != null && uri.scheme == 'https') {
    // Public delivery URLs are compatibility-only runtime sources. Durable
    // documents may keep stable private Storage metadata or opaque owned
    // references, never a provider/public URL.
    return null;
  }
  if (uri != null && uri.scheme == 'http') return null;
  if (uri != null && uri.scheme.isNotEmpty) return null;
  if (normalized.startsWith('/') ||
      normalized.startsWith('\\') ||
      normalized.contains('?') ||
      normalized.contains('#') ||
      normalized.contains('\\') ||
      normalized
          .split('/')
          .any(
            (segment) => segment.isEmpty || segment == '.' || segment == '..',
          ) ||
      normalized.codeUnits.any((code) => code <= 0x1f || code == 0x7f)) {
    return null;
  }
  return normalized;
}

/// Keeps only an opaque, scheme-scoped artifact handle in durable JSON.
/// Runtime paths, object URLs, signed URLs, and inline bytes are rejected.
String? durableOpaqueArtifactReference(String? value, String scheme) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty || normalized != value) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      uri.scheme != scheme ||
      uri.host.isEmpty ||
      uri.path.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.userInfo.isNotEmpty ||
      normalized.codeUnits.any((code) => code <= 0x20 || code == 0x7f) ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$').hasMatch(uri.host)) {
    return null;
  }
  return normalized;
}

String? validImageArtifactReference(String? value) =>
    durableOpaqueArtifactReference(value, 'varian-image');

String? validVideoArtifactReference(String? value) =>
    durableOpaqueArtifactReference(value, 'varian-video');

String? validModel3DArtifactReference(String? value) =>
    durableOpaqueArtifactReference(value, 'varian-model3d');

String? validFileArtifactReference(String? value) =>
    durableOpaqueArtifactReference(value, 'varian-file');

/// Validates a durable reference emitted by [MediaArtifactStore].
///
/// Media references encode policy, checksum, and artifact kind in the URI
/// path. Only the durable policy may cross a document boundary.
String? validMediaArtifactReference(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty || normalized != value) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      uri.scheme != 'varian-media' ||
      uri.host != 'durable' ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.userInfo.isNotEmpty ||
      normalized.codeUnits.any((code) => code <= 0x20 || code == 0x7f)) {
    return null;
  }
  final segments = uri.pathSegments;
  if (segments.length != 2 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(segments[0]) ||
      !RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(segments[1])) {
    return null;
  }
  return normalized;
}

String? mediaArtifactReferenceValue(String? value) =>
    validMediaArtifactReference(value);
