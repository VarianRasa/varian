import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../domain/models/durable_asset_reference.dart';
import '../../../domain/models/media_timeline.dart';
import '../domain/asset_library.dart';
import 'asset_service.dart';
import 'file_artifact_store_types.dart';
import '../../ai/data/image_artifact_store_types.dart';
import '../../ai/data/video_artifact_store_types.dart';
import '../../model3d/data/model3d_artifact_store_types.dart';
import '../../model3d/data/model3d_validation.dart';
import '../../media/data/media_artifact_store_types.dart';

const maxAssetLibraryMaterializationBytes = 512 * 1024 * 1024;

typedef AssetLibraryBytesReader =
    Future<Uint8List?> Function(AssetLibraryItem item);

/// A byte-backed catalog item that is safe to cross into the document layer.
///
/// The result deliberately contains no source path or delivery URL. The
/// caller receives only the owned opaque reference and validated metadata.
class AssetLibraryMaterializationResult {
  final String reference;
  final Uint8List bytes;
  final int sizeBytes;
  final String checksum;
  final String mimeType;
  final String fileName;

  const AssetLibraryMaterializationResult({
    required this.reference,
    required this.bytes,
    required this.sizeBytes,
    required this.checksum,
    required this.mimeType,
    required this.fileName,
  });
}

/// Materializes runtime/catalog sources into the owned artifact stores.
class AssetLibraryMaterializer {
  final ImageArtifactStore imageArtifactStore;
  final FileArtifactStore fileArtifactStore;
  final MediaArtifactStore mediaArtifactStore;
  final VideoArtifactStore videoArtifactStore;
  final Model3DArtifactStore model3DArtifactStore;
  final AssetLibraryBytesReader readBytes;
  final int maxBytes;
  final bool Function()? isCurrent;
  final Future<void> Function(Object artifact)? disposeArtifact;
  final String? activeProjectId;

  const AssetLibraryMaterializer({
    required this.imageArtifactStore,
    required this.fileArtifactStore,
    required this.mediaArtifactStore,
    required this.videoArtifactStore,
    required this.model3DArtifactStore,
    required this.readBytes,
    this.maxBytes = maxAssetLibraryMaterializationBytes,
    this.isCurrent,
    this.disposeArtifact,
    this.activeProjectId,
  });

  bool get _stillCurrent => isCurrent?.call() ?? true;

  bool _isProjectScopeValid(AssetLibraryItem item) {
    final active = activeProjectId?.trim();
    if (active == null || active.isEmpty) return true;
    if (item.scopeId != active) return false;
    final storagePath = item.storagePath;
    if (storagePath == null || storagePath.isEmpty) return true;
    final firstSegment = storagePath.split('/').first;
    return firstSegment == active;
  }

  Future<AssetLibraryMaterializationResult?> materialize(
    AssetLibraryItem item,
  ) async {
    if (maxBytes <= 0 ||
        item.status != AssetLibraryItemStatus.ready ||
        !_stillCurrent ||
        !_isProjectScopeValid(item)) {
      return null;
    }

    final mimeType = item.mimeType.trim().toLowerCase();
    final existingReference = _existingReference(item);
    if (existingReference != null) {
      final existing = await _readExisting(item, existingReference);
      if (!_stillCurrent) return null;
      if (existing != null) return existing;
    }

    Uint8List? bytes;
    try {
      bytes = await readBytes(item);
    } catch (_) {
      return null;
    }
    if (!_stillCurrent ||
        bytes == null ||
        bytes.isEmpty ||
        bytes.length > maxBytes) {
      return null;
    }

    final validated = _validateBytes(item, bytes, mimeType);
    if (!validated) return null;

    final checksum = sha256.convert(bytes).toString();
    if (!_matchesDeclaredMetadata(item, bytes, checksum)) return null;

    try {
      final saved = await _save(
        item,
        bytes,
        mimeType: mimeType,
        checksum: checksum,
      );
      if (saved == null) return null;
      if (!_stillCurrent) {
        await _disposeSaved(item.kind, saved);
        return null;
      }
      final reference = _referenceFor(item.kind, saved);
      if (reference == null) {
        await _disposeSaved(item.kind, saved);
        return null;
      }
      if (!_stillCurrent) {
        await _disposeSaved(item.kind, saved);
        return null;
      }
      final exists = await _exists(item.kind, saved);
      if (!_stillCurrent || !exists) {
        if (!_stillCurrent) await _disposeSaved(item.kind, saved);
        return null;
      }
      final storedBytes = await _read(item.kind, saved);
      if (!_stillCurrent ||
          storedBytes == null ||
          storedBytes.isEmpty ||
          storedBytes.length > maxBytes ||
          !_sameBytes(storedBytes, bytes)) {
        if (!_stillCurrent) await _disposeSaved(item.kind, saved);
        return null;
      }
      final result = AssetLibraryMaterializationResult(
        reference: reference,
        bytes: Uint8List.fromList(bytes),
        sizeBytes: bytes.length,
        checksum: checksum,
        mimeType: mimeType,
        fileName: item.name,
      );
      return _stillCurrent ? result : null;
    } catch (_) {
      return null;
    }
  }

  Future<AssetLibraryMaterializationResult?> _readExisting(
    AssetLibraryItem item,
    String reference,
  ) async {
    try {
      final artifact = await switch (item.kind) {
        AssetLibraryItemKind.image ||
        AssetLibraryItemKind.graphic ||
        AssetLibraryItemKind.icon ||
        AssetLibraryItemKind.illustration => imageArtifactStore.hydrate(
          reference,
          fileName: item.name,
        ),
        AssetLibraryItemKind.file => fileArtifactStore.hydrate(
          reference,
          fileName: item.name,
        ),
        AssetLibraryItemKind.audio => mediaArtifactStore.hydrate(
          reference,
          kind: MediaArtifactKind.original,
          mimeType: item.mimeType,
          checksum: _checksumFromReference(reference),
          fileName: item.name,
        ),
        AssetLibraryItemKind.video => videoArtifactStore.hydrate(
          reference,
          fileName: item.name,
        ),
        AssetLibraryItemKind.model3d => model3DArtifactStore.hydrate(
          reference,
          fileName: item.name,
        ),
      };
      if (artifact == null || !_stillCurrent) {
        return null;
      }

      Uint8List? bytes;
      switch (item.kind) {
        case AssetLibraryItemKind.image:
        case AssetLibraryItemKind.graphic:
        case AssetLibraryItemKind.icon:
        case AssetLibraryItemKind.illustration:
          final image = artifact as ImageArtifact;
          bytes = await imageArtifactStore.read(image);
          await imageArtifactStore.dispose(image);
        case AssetLibraryItemKind.file:
          final file = artifact as FileArtifact;
          bytes = await fileArtifactStore.read(file);
          await fileArtifactStore.dispose(file);
        case AssetLibraryItemKind.audio:
          final audio = artifact as MediaArtifact;
          bytes = await mediaArtifactStore.read(audio);
          await mediaArtifactStore.dispose(audio);
        case AssetLibraryItemKind.video:
          final video = artifact as VideoArtifact;
          bytes = await videoArtifactStore.read(video);
          await videoArtifactStore.dispose(video);
        case AssetLibraryItemKind.model3d:
          final model = artifact as Model3DArtifact;
          bytes = await model3DArtifactStore.read(model);
          await model3DArtifactStore.dispose(model);
      }
      if (!_stillCurrent ||
          bytes == null ||
          bytes.isEmpty ||
          bytes.length > maxBytes) {
        return null;
      }
      final mimeType = item.mimeType.trim().toLowerCase();
      final checksum = sha256.convert(bytes).toString();
      if (!_validateBytes(item, bytes, mimeType) ||
          !_matchesDeclaredMetadata(item, bytes, checksum)) {
        return null;
      }
      final result = AssetLibraryMaterializationResult(
        reference: reference,
        bytes: Uint8List.fromList(bytes),
        sizeBytes: bytes.length,
        checksum: checksum,
        mimeType: mimeType,
        fileName: item.name,
      );
      return _stillCurrent ? result : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _disposeSaved(AssetLibraryItemKind kind, Object artifact) async {
    try {
      switch (kind) {
        case AssetLibraryItemKind.image:
        case AssetLibraryItemKind.graphic:
        case AssetLibraryItemKind.icon:
        case AssetLibraryItemKind.illustration:
          await imageArtifactStore.dispose(artifact as ImageArtifact);
        case AssetLibraryItemKind.file:
          await fileArtifactStore.dispose(artifact as FileArtifact);
        case AssetLibraryItemKind.audio:
          await mediaArtifactStore.dispose(artifact as MediaArtifact);
        case AssetLibraryItemKind.video:
          await videoArtifactStore.dispose(artifact as VideoArtifact);
        case AssetLibraryItemKind.model3d:
          await model3DArtifactStore.dispose(artifact as Model3DArtifact);
      }
    } catch (_) {
      await disposeArtifact?.call(artifact);
    }
  }

  Future<Object?> _save(
    AssetLibraryItem item,
    Uint8List bytes, {
    required String mimeType,
    required String checksum,
  }) => switch (item.kind) {
    AssetLibraryItemKind.image ||
    AssetLibraryItemKind.graphic ||
    AssetLibraryItemKind.icon ||
    AssetLibraryItemKind.illustration => imageArtifactStore.save(
      bytes,
      fileName: item.name,
    ),
    AssetLibraryItemKind.file => fileArtifactStore.save(
      bytes,
      fileName: item.name,
    ),
    AssetLibraryItemKind.audio => mediaArtifactStore.save(
      bytes,
      kind: MediaArtifactKind.original,
      mimeType: mimeType,
      checksum: checksum,
      fileName: item.name,
      storagePolicy: MediaStoragePolicy.durable,
    ),
    AssetLibraryItemKind.video => videoArtifactStore.save(
      bytes,
      fileName: item.name,
    ),
    AssetLibraryItemKind.model3d => model3DArtifactStore.save(
      bytes,
      fileName: item.name,
    ),
  };

  Future<bool> _exists(AssetLibraryItemKind kind, Object artifact) =>
      switch (kind) {
        AssetLibraryItemKind.image ||
        AssetLibraryItemKind.graphic ||
        AssetLibraryItemKind.icon ||
        AssetLibraryItemKind.illustration => imageArtifactStore.exists(
          artifact as ImageArtifact,
        ),
        AssetLibraryItemKind.file => fileArtifactStore.exists(
          artifact as FileArtifact,
        ),
        AssetLibraryItemKind.audio => mediaArtifactStore.exists(
          artifact as MediaArtifact,
        ),
        AssetLibraryItemKind.video => videoArtifactStore.exists(
          artifact as VideoArtifact,
        ),
        AssetLibraryItemKind.model3d => model3DArtifactStore.exists(
          artifact as Model3DArtifact,
        ),
      };

  Future<Uint8List?> _read(AssetLibraryItemKind kind, Object artifact) =>
      switch (kind) {
        AssetLibraryItemKind.image ||
        AssetLibraryItemKind.graphic ||
        AssetLibraryItemKind.icon ||
        AssetLibraryItemKind.illustration => imageArtifactStore.read(
          artifact as ImageArtifact,
        ),
        AssetLibraryItemKind.file => fileArtifactStore.read(
          artifact as FileArtifact,
        ),
        AssetLibraryItemKind.audio => mediaArtifactStore.read(
          artifact as MediaArtifact,
        ),
        AssetLibraryItemKind.video => videoArtifactStore.read(
          artifact as VideoArtifact,
        ),
        AssetLibraryItemKind.model3d => model3DArtifactStore.read(
          artifact as Model3DArtifact,
        ),
      };

  String? _referenceFor(AssetLibraryItemKind kind, Object artifact) =>
      switch (kind) {
        AssetLibraryItemKind.image ||
        AssetLibraryItemKind.graphic ||
        AssetLibraryItemKind.icon ||
        AssetLibraryItemKind.illustration => validImageArtifactReference(
          (artifact as ImageArtifact).reference,
        ),
        AssetLibraryItemKind.file => validFileArtifactReference(
          (artifact as FileArtifact).reference,
        ),
        AssetLibraryItemKind.audio => validMediaArtifactReference(
          (artifact as MediaArtifact).reference,
        ),
        AssetLibraryItemKind.video => validVideoArtifactReference(
          (artifact as VideoArtifact).reference,
        ),
        AssetLibraryItemKind.model3d => validModel3DArtifactReference(
          (artifact as Model3DArtifact).reference,
        ),
      };

  String? _existingReference(AssetLibraryItem item) {
    final value = item.metadata[_metadataKey(item.kind)]?.toString();
    return _referenceForValue(item.kind, value);
  }

  String? _referenceForValue(AssetLibraryItemKind kind, String? value) =>
      switch (kind) {
        AssetLibraryItemKind.image ||
        AssetLibraryItemKind.graphic ||
        AssetLibraryItemKind.icon ||
        AssetLibraryItemKind.illustration => validImageArtifactReference(value),
        AssetLibraryItemKind.file => validFileArtifactReference(value),
        AssetLibraryItemKind.audio => validMediaArtifactReference(value),
        AssetLibraryItemKind.video => validVideoArtifactReference(value),
        AssetLibraryItemKind.model3d => validModel3DArtifactReference(value),
      };

  String _metadataKey(AssetLibraryItemKind kind) => switch (kind) {
    AssetLibraryItemKind.image ||
    AssetLibraryItemKind.graphic ||
    AssetLibraryItemKind.icon ||
    AssetLibraryItemKind.illustration => 'imageArtifactReference',
    AssetLibraryItemKind.file => 'fileArtifactReference',
    AssetLibraryItemKind.audio => 'audioArtifactReference',
    AssetLibraryItemKind.video => 'videoArtifactReference',
    AssetLibraryItemKind.model3d => 'model3dArtifactReference',
  };

  String? _checksumFromReference(String reference) {
    final uri = Uri.tryParse(reference);
    final segments = uri?.pathSegments ?? const <String>[];
    if (segments.length != 2) return null;
    return segments.first;
  }

  bool _validateBytes(AssetLibraryItem item, Uint8List bytes, String mimeType) {
    if (bytes.length > maxAssetLibraryMaterializationBytes) return false;
    if (!assetBytesMatchMimeSignature(bytes, mimeType)) return false;
    return switch (item.kind) {
      AssetLibraryItemKind.image ||
      AssetLibraryItemKind.graphic ||
      AssetLibraryItemKind.icon ||
      AssetLibraryItemKind.illustration =>
        bytes.length <= maxImageArtifactBytes,
      AssetLibraryItemKind.file => bytes.length <= maxFileArtifactBytes,
      AssetLibraryItemKind.audio => bytes.length <= maxMediaArtifactBytes,
      AssetLibraryItemKind.video => bytes.length <= maxVideoArtifactBytes,
      AssetLibraryItemKind.model3d => bytes.length <= maxModel3DBytes,
    };
  }

  bool _matchesDeclaredMetadata(
    AssetLibraryItem item,
    Uint8List bytes,
    String checksum,
  ) {
    if (item.sizeBytes != null && item.sizeBytes != bytes.length) return false;
    final declaredChecksum = _normalizedChecksum(item.checksum);
    return declaredChecksum == null || declaredChecksum == checksum;
  }

  String? _normalizedChecksum(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    final checksum = normalized.startsWith('sha256:')
        ? normalized.substring('sha256:'.length)
        : normalized;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ? checksum : null;
  }

  bool _sameBytes(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

typedef AssetLibraryMaterialization = AssetLibraryMaterializationResult;
