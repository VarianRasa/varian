import 'dart:typed_data';

import '../../domain/models/component_payload.dart';
import '../../domain/models/document.dart';
import '../../domain/models/durable_asset_reference.dart';
import '../../domain/models/media_timeline.dart';
import '../../domain/models/model3d_payload.dart';
import '../../domain/models/node.dart';
import '../../domain/models/node_payload.dart';
import '../../features/ai/data/image_artifact_store.dart';
import '../../features/ai/data/video_artifact_store.dart';
import '../../features/assets/data/file_artifact_store.dart';
import '../../features/media/data/media_artifact_store.dart';
import '../../features/model3d/data/model3d_artifact_store.dart';

/// Reads stable private Storage paths without exposing the runtime URL.
typedef TransientStorageByteReader =
    Future<Uint8List?> Function({
      required String projectId,
      required String path,
      String? accountId,
      required int maxBytes,
    });

/// Runtime-only materialization boundary for durable canvas documents.
///
/// Durable documents contain only opaque artifact references and stable private
/// Storage metadata. This hydrator returns a copied render-facing document and
/// never writes, serializes, or mutates the supplied durable document. Signed
/// URLs are intentionally not part of this API; private Storage consumers must
/// read bytes through [TransientStorageByteReader].
class TransientArtifactHydrator {
  static const _maxImageBytes = 50 * 1024 * 1024;
  static const _maxVideoBytes = 100 * 1024 * 1024;
  static const _maxModel3DBytes = 64 * 1024 * 1024;
  static const _maxFileBytes = 50 * 1024 * 1024;

  final ImageArtifactStore imageArtifactStore;
  final VideoArtifactStore videoArtifactStore;
  final Model3DArtifactStore model3DArtifactStore;
  final MediaArtifactStore mediaArtifactStore;
  final FileArtifactStore fileArtifactStore;
  TransientStorageByteReader? storageByteReader;

  TransientArtifactHydrator({
    ImageArtifactStore? imageArtifactStore,
    VideoArtifactStore? videoArtifactStore,
    Model3DArtifactStore? model3DArtifactStore,
    MediaArtifactStore? mediaArtifactStore,
    FileArtifactStore? fileArtifactStore,
    this.storageByteReader,
  }) : imageArtifactStore = imageArtifactStore ?? createImageArtifactStore(),
       videoArtifactStore = videoArtifactStore ?? createVideoArtifactStore(),
       model3DArtifactStore =
           model3DArtifactStore ?? createModel3DArtifactStore(),
       mediaArtifactStore = mediaArtifactStore ?? createMediaArtifactStore(),
       fileArtifactStore = fileArtifactStore ?? createFileArtifactStore();

  void setStorageByteReader(TransientStorageByteReader? reader) {
    storageByteReader = reader;
  }

  /// Hydrates only validated opaque references and scoped private Storage paths.
  ///
  /// [projectId] and [accountId] are fencing context. They are never logged,
  /// serialized, or used to construct a delivery URL in this class.
  Future<CanvasDocument> hydrate(
    CanvasDocument document, {
    String? projectId,
    String? accountId,
  }) async {
    if (projectId != null &&
        (projectId.trim().isEmpty || document.projectId != projectId)) {
      return document;
    }
    final nodes = await _hydrateNodes(
      document.nodes,
      projectId: projectId,
      accountId: accountId,
    );
    return document.copyWith(nodes: nodes);
  }

  Future<List<CanvasNode>> _hydrateNodes(
    List<CanvasNode> nodes, {
    String? projectId,
    String? accountId,
  }) async {
    final hydrated = <CanvasNode>[];
    for (final node in nodes) {
      hydrated.add(
        await _hydrateNode(node, projectId: projectId, accountId: accountId),
      );
    }
    return List.unmodifiable(hydrated);
  }

  Future<CanvasNode> _hydrateNode(
    CanvasNode node, {
    String? projectId,
    String? accountId,
  }) async {
    var payload = await _hydratePayload(
      node.payload,
      projectId: projectId,
      accountId: accountId,
    );

    if (payload is NestedBoardPayload && payload.subNodes.isNotEmpty) {
      payload = payload.copyWith(
        subNodes: await _hydrateNodes(
          payload.subNodes,
          projectId: projectId,
          accountId: accountId,
        ),
      );
    }
    if (payload is ComponentPayload) {
      payload = await _hydrateComponentPayload(
        payload,
        projectId: projectId,
        accountId: accountId,
      );
    }

    return node.copyWith(payload: payload);
  }

  Future<NodePayload> _hydratePayload(
    NodePayload payload, {
    String? projectId,
    String? accountId,
  }) async {
    if (payload is ImagePayload) {
      final reference = validImageArtifactReference(
        payload.imageArtifactReference,
      );
      if (reference != null) {
        final artifact = await _safeImageHydrate(reference);
        if (_hasImageDelivery(artifact)) {
          payload = payload.copyWith(
            localPath: artifact!.path,
            url: artifact.url,
            clearLocalPath: artifact.path == null,
            clearUrl: artifact.url == null,
          );
        }
      }
      if (!_hasImagePayloadDelivery(payload)) {
        final bytes = await _readStorageBytes(
          payload.storagePath,
          projectId: projectId,
          accountId: accountId,
          maxBytes: _maxImageBytes,
        );
        final artifact = bytes == null
            ? null
            : await _safeImageSave(bytes, fileName: 'image.png');
        if (_hasImageDelivery(artifact)) {
          payload = payload.copyWith(
            localPath: artifact!.path,
            url: artifact.url,
            clearLocalPath: artifact.path == null,
            clearUrl: artifact.url == null,
          );
        }
      }
    }

    if (payload is VideoPayload) {
      final reference = validVideoArtifactReference(
        payload.videoArtifactReference,
      );
      if (reference != null) {
        final artifact = await _safeVideoHydrate(reference);
        if (_hasVideoDelivery(artifact)) {
          payload = payload.copyWith(
            videoPath: artifact!.path,
            videoUrl: artifact.url,
            isTemporary: true,
          );
        }
      }
      if (!_hasVideoPayloadDelivery(payload)) {
        final bytes = await _readStorageBytes(
          payload.storagePath,
          projectId: projectId,
          accountId: accountId,
          maxBytes: _maxVideoBytes,
        );
        final artifact = bytes == null
            ? null
            : await _safeVideoSave(bytes, fileName: 'video.mp4');
        if (_hasVideoDelivery(artifact)) {
          payload = payload.copyWith(
            videoPath: artifact!.path,
            videoUrl: artifact.url,
            isTemporary: true,
          );
        }
      }
      payload = await _hydrateMediaTimeline(
        payload,
        projectId: projectId,
        accountId: accountId,
      );
      if (payload is VideoPayload) {
        payload = await _hydrateVideoPoster(
          payload,
          projectId: projectId,
          accountId: accountId,
        );
      }
    } else if (payload is AudioPayload) {
      payload = await _hydrateMediaTimeline(
        payload,
        projectId: projectId,
        accountId: accountId,
      );
      var audioPayload = payload as AudioPayload;
      final reference = validMediaArtifactReference(
        audioPayload.audioArtifactReference,
      );
      if (reference != null) {
        final artifact = await _safeMediaHydrate(
          reference,
          kind: MediaArtifactKind.original,
          mimeType: 'audio/mpeg',
          fileName: audioPayload.trackName,
        );
        if (artifact != null && artifact.isAvailable) {
          audioPayload = audioPayload.copyWith(
            audioPath: artifact.path,
            audioUrl: artifact.url,
          );
          payload = audioPayload;
        }
      }
      if (!_hasAudioPayloadDelivery(audioPayload)) {
        final bytes = await _readStorageBytes(
          audioPayload.storagePath,
          projectId: projectId,
          accountId: accountId,
          maxBytes: _maxVideoBytes,
        );
        final artifact = bytes == null
            ? null
            : await _safeMediaSave(
                bytes,
                kind: MediaArtifactKind.original,
                mimeType: 'audio/mpeg',
                fileName: 'audio.mp3',
              );
        if (artifact != null && artifact.isAvailable) {
          payload = audioPayload.copyWith(
            audioPath: artifact.path,
            audioUrl: artifact.url,
          );
        }
      }
    } else if (payload is FilePayload) {
      final reference = validFileArtifactReference(payload.artifactReference);
      if (reference != null) {
        final artifact = await _safeFileHydrate(
          reference,
          fileName: payload.fileName,
        );
        if (artifact != null) {
          payload = payload.copyWith(
            artifactReference:
                validFileArtifactReference(artifact.reference) ?? reference,
            localPath: artifact.path,
            remoteUrl: artifact.url,
            clearLocalPath: artifact.path == null,
            clearRemoteUrl: artifact.url == null,
            clearBase64Data: true,
          );
        }
      }
      if (payload.localPath == null &&
          payload.remoteUrl == null &&
          payload.storagePath != null) {
        final bytes = await _readStorageBytes(
          payload.storagePath,
          projectId: projectId,
          accountId: accountId,
          maxBytes: _maxFileBytes,
        );
        final artifact = bytes == null
            ? null
            : await _safeFileSave(bytes, fileName: payload.fileName);
        if (artifact != null) {
          payload = payload.copyWith(
            localPath: artifact.path,
            remoteUrl: artifact.url,
            artifactReference: artifact.reference,
            clearLocalPath: artifact.path == null,
            clearRemoteUrl: artifact.url == null,
            clearBase64Data: true,
          );
        }
      }
    }

    if (payload is Model3DPayload) {
      final reference = validModel3DArtifactReference(
        payload.artifactReference,
      );
      if (reference != null) {
        final artifact = await _safeModel3DHydrate(reference);
        if (_hasModel3DDelivery(artifact)) {
          payload = payload.copyWith(
            modelPath: artifact!.path,
            modelUrl: artifact.url,
            isTemporary: true,
          );
        }
      }
      if (!_hasModel3DPayloadDelivery(payload)) {
        final bytes = await _readStorageBytes(
          payload.storagePath,
          projectId: projectId,
          accountId: accountId,
          maxBytes: _maxModel3DBytes,
        );
        final artifact = bytes == null
            ? null
            : await _safeModel3DSave(bytes, fileName: payload.fileName);
        if (_hasModel3DDelivery(artifact)) {
          payload = payload.copyWith(
            modelPath: artifact!.path,
            modelUrl: artifact.url,
            isTemporary: true,
          );
        }
      }
    }

    return payload;
  }

  Future<ComponentPayload> _hydrateComponentPayload(
    ComponentPayload payload, {
    String? projectId,
    String? accountId,
  }) async {
    final templateChildren = await _hydrateNodes(
      payload.templateChildren,
      projectId: projectId,
      accountId: accountId,
    );
    final slots = <ComponentSlot>[];
    for (final slot in payload.slots) {
      slots.add(
        slot.copyWith(
          fallbackChildren: await _hydrateNodes(
            slot.fallbackChildren,
            projectId: projectId,
            accountId: accountId,
          ),
        ),
      );
    }
    final slotContent = <String, List<CanvasNode>>{};
    for (final entry in payload.slotContent.entries) {
      slotContent[entry.key] = await _hydrateNodes(
        entry.value,
        projectId: projectId,
        accountId: accountId,
      );
    }
    return payload.copyWith(
      templateChildren: templateChildren,
      slots: List.unmodifiable(slots),
      slotContent: slotContent,
    );
  }

  Future<VideoPayload> _hydrateVideoPoster(
    VideoPayload payload, {
    required String? projectId,
    required String? accountId,
  }) async {
    final reference = validImageArtifactReference(
      payload.posterArtifactReference,
    );
    if (reference != null) {
      final artifact = await _safeImageHydrate(reference);
      if (_hasImageDelivery(artifact)) {
        return payload.copyWith(
          posterPath: artifact!.path,
          posterUrl: artifact.url,
          clearPosterPath: artifact.path == null,
          clearPosterUrl: artifact.url == null,
        );
      }
    }
    if (projectId == null || payload.posterStoragePath == null) return payload;
    final bytes = await _readStorageBytes(
      payload.posterStoragePath,
      projectId: projectId,
      accountId: accountId,
      maxBytes: _maxImageBytes,
    );
    final artifact = bytes == null
        ? null
        : await _safeImageSave(bytes, fileName: 'poster.png');
    if (!_hasImageDelivery(artifact)) return payload;
    return payload.copyWith(
      posterPath: artifact!.path,
      posterUrl: artifact.url,
      clearPosterPath: artifact.path == null,
      clearPosterUrl: artifact.url == null,
    );
  }

  Future<NodePayload> _hydrateMediaTimeline(
    NodePayload payload, {
    String? projectId,
    String? accountId,
  }) async {
    final timeline = switch (payload) {
      VideoPayload value => value.mediaTimeline,
      AudioPayload value => value.mediaTimeline,
      _ => null,
    };
    if (timeline == null || timeline.artifacts.items.isEmpty) return payload;

    var manifest = timeline.artifacts;
    for (final artifact in timeline.artifacts.items) {
      final reference = _validMediaReference(artifact.reference);
      if (reference == null) continue;
      final hydrated = await _safeMediaHydrate(
        reference,
        kind: artifact.kind,
        mimeType: artifact.mimeType,
        checksum: artifact.checksum,
        fileName: null,
      );
      if (hydrated != null) manifest = manifest.upsert(hydrated);
    }
    final hydratedTimeline = timeline.copyWith(artifacts: manifest);
    return switch (payload) {
      VideoPayload value => value.copyWith(mediaTimeline: hydratedTimeline),
      AudioPayload value => value.copyWith(mediaTimeline: hydratedTimeline),
      _ => payload,
    };
  }

  String? _validMediaReference(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty || normalized != value) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme != 'varian-media' ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        mediaStoragePolicyFromReference(normalized) == null ||
        mediaArtifactKindFromReference(normalized) == null ||
        mediaArtifactChecksumFromReference(normalized) == null) {
      return null;
    }
    return normalized;
  }

  Future<Uint8List?> _readStorageBytes(
    String? path, {
    required String? projectId,
    required String? accountId,
    required int maxBytes,
  }) async {
    final value = path;
    final reader = storageByteReader;
    if (reader == null ||
        projectId == null ||
        projectId.trim().isEmpty ||
        value == null ||
        value.isEmpty) {
      return null;
    }
    try {
      return await reader(
        projectId: projectId,
        path: value,
        accountId: accountId,
        maxBytes: maxBytes,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ImageArtifact?> _safeImageHydrate(String reference) async {
    try {
      return await imageArtifactStore.hydrate(reference);
    } catch (_) {
      return null;
    }
  }

  Future<ImageArtifact?> _safeImageSave(
    Uint8List bytes, {
    required String fileName,
  }) async {
    try {
      return await imageArtifactStore.save(bytes, fileName: fileName);
    } catch (_) {
      return null;
    }
  }

  Future<VideoArtifact?> _safeVideoHydrate(String reference) async {
    try {
      return await videoArtifactStore.hydrate(reference);
    } catch (_) {
      return null;
    }
  }

  Future<VideoArtifact?> _safeVideoSave(
    Uint8List bytes, {
    required String fileName,
  }) async {
    try {
      return await videoArtifactStore.save(bytes, fileName: fileName);
    } catch (_) {
      return null;
    }
  }

  Future<Model3DArtifact?> _safeModel3DHydrate(String reference) async {
    try {
      return await model3DArtifactStore.hydrate(reference);
    } catch (_) {
      return null;
    }
  }

  Future<Model3DArtifact?> _safeModel3DSave(
    Uint8List bytes, {
    required String fileName,
  }) async {
    try {
      return await model3DArtifactStore.save(bytes, fileName: fileName);
    } catch (_) {
      return null;
    }
  }

  Future<FileArtifact?> _safeFileHydrate(
    String reference, {
    required String fileName,
  }) async {
    try {
      return await fileArtifactStore.hydrate(reference, fileName: fileName);
    } catch (_) {
      return null;
    }
  }

  Future<FileArtifact?> _safeFileSave(
    Uint8List bytes, {
    required String fileName,
  }) async {
    try {
      return await fileArtifactStore.save(bytes, fileName: fileName);
    } catch (_) {
      return null;
    }
  }

  Future<MediaArtifact?> _safeMediaHydrate(
    String reference, {
    required MediaArtifactKind kind,
    String? mimeType,
    String? checksum,
    String? fileName,
  }) async {
    try {
      return await mediaArtifactStore.hydrate(
        reference,
        kind: kind,
        mimeType: mimeType,
        checksum: checksum,
        fileName: fileName,
      );
    } catch (_) {
      return null;
    }
  }

  Future<MediaArtifact?> _safeMediaSave(
    Uint8List bytes, {
    required MediaArtifactKind kind,
    required String mimeType,
    required String fileName,
  }) async {
    try {
      return await mediaArtifactStore.save(
        bytes,
        kind: kind,
        mimeType: mimeType,
        checksum: mediaArtifactChecksum(bytes),
        fileName: fileName,
        storagePolicy: MediaStoragePolicy.ephemeral,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _hasImageDelivery(ImageArtifact? artifact) =>
      artifact?.path?.isNotEmpty == true || artifact?.url?.isNotEmpty == true;

  static bool _hasImagePayloadDelivery(ImagePayload payload) =>
      payload.localPath?.isNotEmpty == true || payload.url?.isNotEmpty == true;

  static bool _hasVideoDelivery(VideoArtifact? artifact) =>
      artifact?.path?.isNotEmpty == true || artifact?.url?.isNotEmpty == true;

  static bool _hasVideoPayloadDelivery(VideoPayload payload) =>
      payload.videoPath?.isNotEmpty == true ||
      payload.videoUrl?.isNotEmpty == true;

  static bool _hasAudioPayloadDelivery(AudioPayload payload) =>
      payload.audioPath?.isNotEmpty == true ||
      payload.audioUrl?.isNotEmpty == true;

  static bool _hasModel3DDelivery(Model3DArtifact? artifact) =>
      artifact?.path?.isNotEmpty == true || artifact?.url?.isNotEmpty == true;

  static bool _hasModel3DPayloadDelivery(Model3DPayload payload) =>
      payload.modelPath?.isNotEmpty == true ||
      payload.modelUrl?.isNotEmpty == true;
}
