import 'dart:typed_data';

/// Runtime-only media source returned by a hydration boundary.
///
/// [path], [uri], and [bytes] must never be copied into a durable payload.
class TransientMediaSource {
  const TransientMediaSource({
    this.path,
    this.uri,
    this.bytes,
    this.mimeType,
    this.disposeCallback,
    this.readBytesCallback,
  });

  final String? path;
  final Uri? uri;
  final Uint8List? bytes;

  /// The validated content type inferred before hydration. It remains runtime
  /// metadata and is never copied into a durable payload.
  final String? mimeType;
  final Future<void> Function()? disposeCallback;
  final Future<Uint8List?> Function()? readBytesCallback;

  bool get isEmpty => path == null && uri == null && bytes == null;

  Future<Uint8List?> readBytes() async {
    final inline = bytes;
    if (inline != null && inline.isNotEmpty) return inline;
    return readBytesCallback?.call();
  }

  Future<void> dispose() async {
    await disposeCallback?.call();
  }
}

/// Accepts only runtime-safe external media URLs or local/runtime paths.
///
/// HTTP(S) query strings and fragments are rejected because they may carry
/// signed Storage credentials. Local paths and non-HTTP runtime handles are
/// preserved for platform-specific consumers.
String? safeTransientMediaSource(String? value) {
  final normalized = value?.trim();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized != value ||
      normalized.codeUnits.any((code) => code <= 0x20 || code == 0x7f)) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.scheme.isEmpty) return normalized;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    return normalized;
  }
  if (scheme == 'blob' || scheme == 'data') {
    if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) return null;
    return normalized;
  }
  return normalized;
}
