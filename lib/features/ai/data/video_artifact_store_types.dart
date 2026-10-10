import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../domain/models/durable_asset_reference.dart';
import 'video_media_validation.dart';
import 'video_provider.dart';

const maxVideoArtifactBytes = 100 * 1024 * 1024;

class VideoArtifact {
  final String? path;
  final String? url;
  final String? reference;
  final Uint8List? bytes;
  final String fileName;

  const VideoArtifact({
    this.path,
    this.url,
    this.reference,
    this.bytes,
    required this.fileName,
  });

  bool get isLocal => path != null && path!.isNotEmpty;
  bool get isWeb => url != null && url!.isNotEmpty;
  bool get isPersistent => reference != null && reference!.isNotEmpty;

  VideoArtifact copyWith({String? path, String? url, String? reference}) =>
      VideoArtifact(
        path: path ?? this.path,
        url: url ?? this.url,
        reference: reference ?? this.reference,
        bytes: bytes,
        fileName: fileName,
      );
}

abstract interface class VideoArtifactStore {
  Future<VideoArtifact> save(Uint8List bytes, {String fileName});
  Future<VideoArtifact?> hydrate(String reference, {String? fileName});
  Future<bool> exists(VideoArtifact artifact);
  Future<Uint8List?> read(VideoArtifact artifact);
  Future<void> dispose(VideoArtifact artifact);
}

class MemoryVideoArtifactStore implements VideoArtifactStore {
  final Map<String, Uint8List> _items = {};
  final Set<VideoArtifact> _disposedHandles = Set<VideoArtifact>.identity();

  @override
  Future<VideoArtifact> save(
    Uint8List bytes, {
    String fileName = 'video.mp4',
  }) async {
    validateVideoArtifactBytes(bytes);
    final safeName = sanitizeVideoFileName(fileName);
    final reference = 'varian-video://${const Uuid().v4()}';
    _items[reference] = Uint8List.fromList(bytes);
    return VideoArtifact(
      path: reference,
      reference: reference,
      bytes: Uint8List.fromList(bytes),
      fileName: safeName,
    );
  }

  @override
  Future<VideoArtifact?> hydrate(String reference, {String? fileName}) async {
    final normalized = validVideoArtifactReference(reference);
    if (normalized == null || !_items.containsKey(normalized)) return null;
    return VideoArtifact(
      path: normalized,
      reference: normalized,
      fileName: sanitizeVideoFileName(fileName ?? 'video.mp4'),
    );
  }

  @override
  Future<bool> exists(VideoArtifact artifact) async {
    final reference = validVideoArtifactReference(artifact.reference);
    if (reference != null && _items.containsKey(reference)) return true;
    if (artifact.path == null) return artifact.bytes?.isNotEmpty == true;
    return _items.containsKey(artifact.path);
  }

  @override
  Future<Uint8List?> read(VideoArtifact artifact) async {
    if (_disposedHandles.contains(artifact)) return null;
    final path = artifact.path;
    if (path != null && _items[path] != null) {
      return Uint8List.fromList(_items[path]!);
    }
    return null;
  }

  @override
  Future<void> dispose(VideoArtifact artifact) async {
    _disposedHandles.add(artifact);
    // A hydrated handle can point at a document-referenced durable artifact.
    // Releasing that handle must not delete the source bytes.
  }
}

void validateVideoArtifactBytes(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxVideoArtifactBytes) {
    throw const VideoProviderException(
      'VIDEO_DOWNLOAD_ERROR',
      'Video content is empty or too large.',
    );
  }
  if (!isValidMp4Bytes(bytes)) {
    throw const VideoProviderException(
      'VIDEO_DOWNLOAD_ERROR',
      'Video content is not a valid MP4.',
    );
  }
}

String sanitizeVideoFileName(String value) {
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
  final name = safeBase.isEmpty ? 'generated-video' : safeBase;
  return '${name.substring(0, name.length > 120 ? 120 : name.length)}.mp4';
}
