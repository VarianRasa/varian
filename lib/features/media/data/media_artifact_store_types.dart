import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:varian/domain/models/media_timeline.dart';

const maxMediaArtifactBytes = 512 * 1024 * 1024;

class MediaArtifactStoreException implements Exception {
  final String message;

  const MediaArtifactStoreException(this.message);

  @override
  String toString() => message;
}

abstract interface class MediaArtifactStore {
  Future<MediaArtifact> save(
    Uint8List bytes, {
    required MediaArtifactKind kind,
    required String mimeType,
    required String checksum,
    required String fileName,
    MediaStoragePolicy storagePolicy,
  });

  Future<bool> exists(MediaArtifact artifact);

  Future<Uint8List?> read(MediaArtifact artifact);

  Future<MediaArtifact?> hydrate(
    String reference, {
    MediaArtifactKind? kind,
    String? mimeType,
    String? checksum,
    String? fileName,
  });

  Future<void> dispose(MediaArtifact artifact);
}

class MemoryMediaArtifactStore implements MediaArtifactStore {
  final Map<String, Uint8List> _items = {};

  @override
  Future<MediaArtifact> save(
    Uint8List bytes, {
    required MediaArtifactKind kind,
    required String mimeType,
    required String checksum,
    required String fileName,
    MediaStoragePolicy storagePolicy = MediaStoragePolicy.cache,
  }) async {
    validateMediaArtifactBytes(bytes);
    final suppliedChecksum = checksum.trim();
    final actualChecksum = mediaArtifactChecksum(bytes);
    final normalizedChecksum =
        RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(suppliedChecksum)
        ? suppliedChecksum.toLowerCase()
        : actualChecksum;
    if (normalizedChecksum != actualChecksum) {
      throw const MediaArtifactStoreException(
        'Media artifact checksum does not match its bytes.',
      );
    }
    final reference = storagePolicy == MediaStoragePolicy.durable
        ? mediaArtifactReference(storagePolicy, normalizedChecksum, kind)
        : 'memory://${storagePolicy.name}/$normalizedChecksum/${kind.name}';
    _items[reference] = Uint8List.fromList(bytes);
    return MediaArtifact(
      kind: kind,
      path: reference,
      reference: reference,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      checksum: normalizedChecksum,
    );
  }

  @override
  Future<bool> exists(MediaArtifact artifact) async {
    final path = artifact.path;
    if (path != null && _items.containsKey(path)) return true;
    final reference = artifact.reference;
    return reference != null && _items.containsKey(reference);
  }

  @override
  Future<Uint8List?> read(MediaArtifact artifact) async {
    final key = artifact.path ?? artifact.reference;
    final bytes = key == null ? null : _items[key];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<MediaArtifact?> hydrate(
    String reference, {
    MediaArtifactKind? kind,
    String? mimeType,
    String? checksum,
    String? fileName,
  }) async {
    if (!_items.containsKey(reference)) return null;
    final bytes = _items[reference]!;
    if (bytes.isEmpty || bytes.length > maxMediaArtifactBytes) return null;
    final resolvedKind = kind ?? _kindFromReference(reference);
    final resolvedChecksum = checksum ?? _checksumFromReference(reference);
    if (resolvedKind == null || resolvedChecksum == null) return null;
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(resolvedChecksum) &&
        mediaArtifactChecksum(bytes) != resolvedChecksum) {
      return null;
    }
    return MediaArtifact(
      kind: resolvedKind,
      path: reference,
      reference: reference,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      checksum: resolvedChecksum,
    );
  }

  @override
  Future<void> dispose(MediaArtifact artifact) async {
    // Durable media references outlive transient hydration handles. Cleanup of
    // the backing bytes belongs to explicit artifact-retention policy, not a
    // reader or exporter releasing its handle.
  }
}

void validateMediaArtifactBytes(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxMediaArtifactBytes) {
    throw const MediaArtifactStoreException(
      'Media artifact is empty or exceeds the size limit.',
    );
  }
}

String mediaArtifactChecksum(Uint8List bytes) =>
    sha256.convert(bytes).toString();

String sanitizeMediaArtifactFileName(
  String value, {
  required MediaArtifactKind kind,
  required String mimeType,
}) {
  final base = value
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[<>:"|?*\u0000-\u001F]'), '_')
      .trim();
  final withoutExtension = base.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final safeBase = withoutExtension
      .trim()
      .replaceFirst(RegExp(r'^\.+'), '')
      .trim();
  final name = safeBase.isEmpty ? kind.name : safeBase;
  final extension = mediaArtifactExtension(kind, mimeType);
  return '${name.substring(0, name.length > 120 ? 120 : name.length)}.$extension';
}

String mediaArtifactExtension(MediaArtifactKind kind, String mimeType) {
  final normalized = mimeType.toLowerCase().split(';').first.trim();
  if (normalized == 'image/svg+xml') return 'svg';
  if (normalized == 'image/png') return 'png';
  if (normalized == 'image/jpeg') return 'jpg';
  if (normalized == 'image/webp') return 'webp';
  if (normalized == 'application/json') return 'json';
  if (normalized == 'video/webm') return 'webm';
  if (normalized == 'video/quicktime') return 'mov';
  if (normalized == 'audio/mpeg') return 'mp3';
  if (normalized == 'audio/wav' || normalized == 'audio/x-wav') return 'wav';
  if (normalized == 'video/mp4') return 'mp4';
  return switch (kind) {
    MediaArtifactKind.thumbnail => 'bin',
    MediaArtifactKind.waveform => 'json',
    _ => 'bin',
  };
}

String mediaArtifactReference(
  MediaStoragePolicy storagePolicy,
  String checksum,
  MediaArtifactKind kind,
) => 'varian-media://${storagePolicy.name}/$checksum/${kind.name}';

MediaArtifactKind? mediaArtifactKindFromReference(String reference) {
  final segments = Uri.tryParse(reference)?.pathSegments ?? const [];
  if (segments.isEmpty) return null;
  final name = segments.last;
  for (final value in MediaArtifactKind.values) {
    if (value.name == name) return value;
  }
  return null;
}

String? mediaArtifactChecksumFromReference(String reference) {
  final segments = Uri.tryParse(reference)?.pathSegments ?? const [];
  return segments.length >= 2 && segments[segments.length - 2].isNotEmpty
      ? segments[segments.length - 2]
      : null;
}

String? normalizeMediaArtifactReference(String? reference) {
  final normalized = reference?.trim();
  if (normalized == null || normalized != reference) return null;
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      uri.scheme != 'varian-media' ||
      uri.host.isEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.pathSegments.length != 2) {
    return null;
  }
  final policy = mediaStoragePolicyFromReference(normalized);
  final checksum = mediaArtifactChecksumFromReference(normalized);
  final kind = mediaArtifactKindFromReference(normalized);
  if (policy == null || checksum == null || kind == null) return null;
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) return null;
  return normalized;
}

MediaStoragePolicy? mediaStoragePolicyFromReference(String reference) {
  final uri = Uri.tryParse(reference);
  if (uri?.scheme != 'varian-media') return null;
  for (final value in MediaStoragePolicy.values) {
    if (value.name == uri!.host) return value;
  }
  return null;
}

MediaArtifactKind? _kindFromReference(String reference) =>
    mediaArtifactKindFromReference(reference);

String? _checksumFromReference(String reference) =>
    mediaArtifactChecksumFromReference(reference);
