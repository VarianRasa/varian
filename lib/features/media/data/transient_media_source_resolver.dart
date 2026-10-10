import 'dart:typed_data';

import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/features/ai/data/video_artifact_store.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';
import 'package:varian/features/media/data/media_artifact_store.dart';

import 'transient_media_source_types.dart';

/// Resolves media payload sources without mutating the durable payload.
///
/// Stable Storage metadata is resolved to bytes through the shared private
/// Storage resolver. Signed delivery URLs never escape this byte-first boundary.
class TransientMediaSourceResolver {
  TransientMediaSourceResolver({
    this.fileResolver = const TransientFileSourceResolver(),
    MediaArtifactStore? artifactStore,
    VideoArtifactStore? videoArtifactStore,
    ArtifactStoreBundle? artifactStoreBundle,
  }) : artifactStore =
           artifactStore ??
           artifactStoreBundle?.mediaArtifactStore ??
           createMediaArtifactStore(),
       videoArtifactStore =
           videoArtifactStore ??
           artifactStoreBundle?.videoArtifactStore ??
           createVideoArtifactStore();

  final TransientFileSourceResolver fileResolver;
  final MediaArtifactStore artifactStore;
  final VideoArtifactStore videoArtifactStore;

  Future<TransientMediaSource> resolveAudio(
    AudioPayload payload, {
    int maxBytes = maxTransientFileBytes,
  }) => _resolve(
    storagePath: payload.storagePath,
    localPath: payload.audioPath,
    url: payload.audioUrl,
    artifactReference: payload.audioArtifactReference,
    isAudio: true,
    fileName:
        'audio.${_extension(payload.audioUrl ?? payload.storagePath, fallback: 'mp3')}',
    mimeType: _audioMimeType(
      _extension(payload.audioUrl ?? payload.storagePath, fallback: 'mp3'),
    ),
    maxBytes: maxBytes,
  );

  Future<TransientMediaSource> resolveVideo(
    VideoPayload payload, {
    int maxBytes = maxTransientFileBytes,
  }) => _resolve(
    storagePath: payload.storagePath,
    localPath: payload.videoPath,
    url: payload.videoUrl,
    artifactReference: payload.videoArtifactReference,
    fileName:
        'video.${_extension(payload.videoUrl ?? payload.storagePath, fallback: 'mp4')}',
    mimeType: _videoMimeType(
      _extension(payload.videoUrl ?? payload.storagePath, fallback: 'mp4'),
    ),
    maxBytes: maxBytes,
  );

  Future<TransientMediaSource> resolveFile(
    FilePayload payload, {
    int maxBytes = maxTransientFileBytes,
  }) async {
    final bytes = await fileResolver.resolveBytes(payload, maxBytes: maxBytes);
    if (bytes != null && bytes.isNotEmpty) {
      return TransientMediaSource(bytes: bytes);
    }
    final uri = fileResolver.publicUri(payload.remoteUrl);
    if (uri != null) return TransientMediaSource(uri: uri);
    return const TransientMediaSource();
  }

  Future<TransientMediaSource> _resolve({
    required String? storagePath,
    required String? localPath,
    required String? url,
    String? artifactReference,
    bool isAudio = false,
    required String fileName,
    required String mimeType,
    required int maxBytes,
  }) async {
    final extension = _extension(url ?? storagePath, fallback: 'bin');
    final payload = FilePayload(
      storagePath: storagePath,
      localPath: localPath,
      remoteUrl: url,
      fileName: fileName,
      fileExtension: extension,
    );
    if (artifactReference != null && artifactReference.trim().isNotEmpty) {
      final artifact = isAudio
          ? await _readMediaArtifactReference(
              artifactReference,
              kind: MediaArtifactKind.original,
              mimeType: mimeType,
              fileName: fileName,
              maxBytes: maxBytes,
            )
          : await _readVideoArtifactReference(
              artifactReference,
              fileName: fileName,
              maxBytes: maxBytes,
            );
      if (artifact != null && artifact.isNotEmpty) {
        return _materialize(
          artifact,
          kind: MediaArtifactKind.original,
          mimeType: mimeType,
          fileName: fileName,
        );
      }
    }
    final bytes = await fileResolver.resolveBytes(payload, maxBytes: maxBytes);
    if (bytes != null && bytes.isNotEmpty) {
      return _materialize(
        bytes,
        kind: MediaArtifactKind.original,
        mimeType: mimeType,
        fileName: fileName,
      );
    }
    // Query-free provider URLs are retained only as a compatibility source;
    // private Storage and opaque artifacts are always resolved above.
    final uri = fileResolver.publicUri(url);
    if (uri != null) return TransientMediaSource(uri: uri);
    return const TransientMediaSource();
  }

  Future<Uint8List?> _readMediaArtifactReference(
    String reference, {
    required MediaArtifactKind kind,
    required String mimeType,
    required String fileName,
    required int maxBytes,
  }) async {
    final normalized = validMediaArtifactReference(reference);
    if (normalized == null) return null;
    final artifact = await artifactStore.hydrate(
      normalized,
      kind: kind,
      mimeType: mimeType,
      fileName: fileName,
    );
    if (artifact == null) return null;
    try {
      final bytes = await artifactStore.read(artifact);
      return bytes != null && bytes.length <= maxBytes ? bytes : null;
    } finally {
      await artifactStore.dispose(artifact);
    }
  }

  Future<Uint8List?> _readVideoArtifactReference(
    String reference, {
    required String fileName,
    required int maxBytes,
  }) async {
    final normalized = validVideoArtifactReference(reference);
    if (normalized == null) return null;
    final artifact = await videoArtifactStore.hydrate(
      normalized,
      fileName: fileName,
    );
    if (artifact != null) {
      try {
        final bytes = await videoArtifactStore.read(artifact);
        return bytes != null && bytes.length <= maxBytes ? bytes : null;
      } finally {
        await videoArtifactStore.dispose(artifact);
      }
    }
    final bytes = await videoArtifactStore.read(
      VideoArtifact(reference: normalized, fileName: fileName),
    );
    return bytes != null && bytes.length <= maxBytes ? bytes : null;
  }

  Future<TransientMediaSource> _materialize(
    Uint8List bytes, {
    required MediaArtifactKind kind,
    required String mimeType,
    required String fileName,
  }) async {
    try {
      final artifact = await artifactStore.save(
        bytes,
        kind: kind,
        mimeType: mimeType,
        checksum: mediaArtifactChecksum(bytes),
        fileName: fileName,
        storagePolicy: MediaStoragePolicy.ephemeral,
      );
      var disposed = false;
      Future<void> disposeArtifact() async {
        if (disposed) return;
        disposed = true;
        await artifactStore.dispose(artifact);
      }

      final path = artifact.path?.trim();
      if (path != null && path.isNotEmpty) {
        return TransientMediaSource(
          path: path,
          mimeType: mimeType,
          disposeCallback: disposeArtifact,
          readBytesCallback: () => artifactStore.read(artifact),
        );
      }
      final url = artifact.url?.trim();
      final uri = url == null || url.isEmpty ? null : Uri.tryParse(url);
      if (uri != null) {
        return TransientMediaSource(
          uri: uri,
          mimeType: mimeType,
          disposeCallback: disposeArtifact,
          readBytesCallback: () => artifactStore.read(artifact),
        );
      }
      await disposeArtifact();
    } catch (_) {
      // Keep a byte-only source as a bounded fallback. Native consumers may
      // reject it, but the caller still gets a safe unavailable state instead
      // of a signed URL or an unowned temporary path.
    }
    return TransientMediaSource(bytes: bytes, mimeType: mimeType);
  }

  static String _extension(String? value, {required String fallback}) {
    final raw = value?.split('?').first.split('#').first ?? '';
    final slash = raw.lastIndexOf('/');
    final dot = raw.lastIndexOf('.');
    if (dot > slash && dot + 1 < raw.length) {
      final extension = raw.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)) return extension;
    }
    return fallback;
  }

  static String _audioMimeType(String extension) => switch (extension) {
    'aac' => 'audio/aac',
    'flac' => 'audio/flac',
    'm4a' => 'audio/mp4',
    'ogg' => 'audio/ogg',
    'opus' => 'audio/opus',
    'wav' => 'audio/wav',
    _ => 'audio/mpeg',
  };

  static String _videoMimeType(String extension) => switch (extension) {
    'm3u8' => 'application/vnd.apple.mpegurl',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    _ => 'video/mp4',
  };
}
