import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../domain/models/durable_asset_reference.dart';
import 'video_artifact_store.dart';
import 'video_media_validation.dart';

class VideoDownloadArtifact {
  final String fileName;
  final Uint8List bytes;

  const VideoDownloadArtifact({required this.fileName, required this.bytes});
}

class VideoDownloadService {
  final Future<void> Function(String fileName, Uint8List bytes) _saveBytes;

  VideoDownloadService({
    Future<void> Function(String fileName, Uint8List bytes)? saveBytes,
    Object? client,
  }) : _saveBytes = saveBytes ?? _saveWithPicker;

  Future<void> downloadSource({
    required String fileName,
    String? path,
    String? url,
    String? videoArtifactReference,
    Uint8List? bytes,
    VideoArtifactStore? store,
  }) async {
    final directBytes = bytes;
    if (directBytes != null) {
      await download(
        VideoDownloadArtifact(fileName: fileName, bytes: directBytes),
      );
      return;
    }
    final artifactStore = store;
    final validReference = validVideoArtifactReference(videoArtifactReference);
    if (validReference != null && artifactStore != null) {
      final hydrated = await artifactStore.hydrate(
        validReference,
        fileName: fileName,
      );
      final stored = hydrated == null
          ? await artifactStore.read(
              VideoArtifact(
                path: path,
                reference: validReference,
                fileName: fileName,
              ),
            )
          : await artifactStore.read(hydrated);
      if (stored != null) {
        await download(
          VideoDownloadArtifact(fileName: fileName, bytes: stored),
        );
        return;
      }
    }
    if (path != null && artifactStore != null) {
      final stored = await artifactStore.read(
        VideoArtifact(path: path, fileName: fileName),
      );
      if (stored != null) {
        await download(
          VideoDownloadArtifact(fileName: fileName, bytes: stored),
        );
        return;
      }
    }
    if (url != null && store != null) {
      final stored = await store.read(
        VideoArtifact(url: url, fileName: fileName),
      );
      if (stored != null) {
        await download(
          VideoDownloadArtifact(fileName: fileName, bytes: stored),
        );
        return;
      }
    }
    if (videoArtifactReference != null && validReference == null) {
      throw StateError('Video artifact reference is invalid.');
    }
    if (validReference != null && artifactStore == null) {
      throw StateError('Video artifact store is unavailable.');
    }
    if (url != null && url.trim().isNotEmpty) {
      // Runtime delivery URLs, including signed URLs and provider URLs, are
      // intentionally not a download source. Resolve the durable reference or
      // pass hydrated bytes from the render boundary instead.
      throw StateError('Video download requires an owned artifact.');
    }
    throw StateError('Video artifact is no longer available.');
  }

  Future<void> download(
    VideoDownloadArtifact artifact, {
    String? suggestedName,
  }) async {
    final name = sanitizeVideoFileName(suggestedName ?? artifact.fileName);
    if (!isValidMp4Bytes(artifact.bytes)) {
      throw StateError('Video artifact is invalid.');
    }
    await _saveBytes(name, artifact.bytes);
  }

  Future<void> downloadArtifact(
    VideoArtifact artifact, {
    required VideoArtifactStore store,
    String? suggestedName,
  }) async {
    final bytes = artifact.bytes ?? await store.read(artifact);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Video artifact is no longer available.');
    }
    await download(
      VideoDownloadArtifact(fileName: artifact.fileName, bytes: bytes),
      suggestedName: suggestedName,
    );
  }

  static Future<void> _saveWithPicker(String fileName, Uint8List bytes) async {
    await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'video/mp4',
      dialogTitle: 'Save video',
    );
  }
}

String videoDownloadFileName(String? name) =>
    sanitizeVideoFileName(name ?? 'generated-video');
