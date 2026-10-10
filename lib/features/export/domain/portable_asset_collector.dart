import 'dart:typed_data';

import '../../../data/remote/supabase_storage_path_resolver.dart';
import '../../../domain/models/document_asset.dart';
import '../../../domain/models/document_asset_dependencies.dart';
import '../../../domain/models/document_package_archive.dart';
import '../../../domain/models/durable_asset_reference.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/media_timeline.dart';
import '../../ai/data/image_artifact_store.dart';
import '../../ai/data/video_artifact_store.dart';
import '../../assets/data/asset_service.dart';
import '../../assets/data/file_artifact_store.dart';
import '../../media/data/media_artifact_store.dart';
import '../../model3d/data/model3d_artifact_store.dart';

/// Transient bytes collected for a portable archive.
///
/// The bytes stay in memory until the archive is encoded. Only the resulting
/// archive contains embedded payloads; references and runtime delivery values
/// are never added to this result or written back to the document.
class PortableAssetCollection {
  final Map<String, Uint8List> assetBytes;
  final List<String> missingAssetIds;
  final List<String> invalidAssetIds;
  final List<String> invalidReferences;

  const PortableAssetCollection({
    this.assetBytes = const {},
    this.missingAssetIds = const [],
    this.invalidAssetIds = const [],
    this.invalidReferences = const [],
  });

  bool get isComplete =>
      missingAssetIds.isEmpty &&
      invalidAssetIds.isEmpty &&
      invalidReferences.isEmpty;
}

class PortableDependencyValidation {
  final List<String> missingAssetIds;
  final List<String> invalidAssetIds;
  final List<String> invalidReferences;

  const PortableDependencyValidation({
    this.missingAssetIds = const [],
    this.invalidAssetIds = const [],
    this.invalidReferences = const [],
  });

  bool get isValid =>
      missingAssetIds.isEmpty &&
      invalidAssetIds.isEmpty &&
      invalidReferences.isEmpty;
}

PortableDependencyValidation validatePortableDependencies({
  required DocumentAssetManifest manifest,
  required Iterable<CanvasNode> nodes,
}) {
  manifest.validateIdentity();
  final missing = <String>{};
  final invalid = <String>{};
  final invalidReferences = <String>{};
  final dependencies = collectDocumentAssetDependencies(nodes);

  for (final dependency in dependencies.dependencies) {
    final assetId = dependency.assetId;
    if (assetId != null) {
      final asset = manifest[assetId];
      if (asset == null) {
        missing.add(assetId);
        continue;
      }
      if (!_dependencyMatchesAsset(dependency, asset)) {
        invalid.add(assetId);
      }
      continue;
    }

    final reference = dependency.durableReference;
    final matches = manifest.items
        .where(
          (asset) =>
              asset.kind == dependency.kind &&
              reference != null &&
              asset.durableReference == reference,
        )
        .toList(growable: false);
    if (matches.length != 1) {
      invalidReferences.add(reference ?? 'unknown');
    }
  }

  return PortableDependencyValidation(
    missingAssetIds: missing.toList(growable: false),
    invalidAssetIds: invalid.toList(growable: false),
    invalidReferences: invalidReferences.toList(growable: false),
  );
}

bool _dependencyMatchesAsset(
  DocumentAssetDependency dependency,
  DocumentAsset asset,
) {
  if (dependency.kind != asset.kind) return false;
  final reference = dependency.durableReference;
  return reference == null || reference == asset.durableReference;
}

/// Reads document-referenced assets through their owned stores or private
/// Storage bytes before a portable archive is encoded.
///
/// This collector deliberately ignores [DocumentAsset.localPath] and
/// [DocumentAsset.remoteUrl]. Those values are runtime compatibility sources,
/// not portable identities. A missing source is reported while the caller can
/// still encode a non-portable archive with the remaining bytes.
class PortableAssetCollector {
  final ImageArtifactStore imageArtifactStore;
  final FileArtifactStore fileArtifactStore;
  final MediaArtifactStore mediaArtifactStore;
  final VideoArtifactStore videoArtifactStore;
  final Model3DArtifactStore model3DArtifactStore;
  final SupabaseStoragePathResolver? storageResolver;
  final String? projectId;
  final String? expectedUserId;

  const PortableAssetCollector({
    required this.imageArtifactStore,
    required this.fileArtifactStore,
    required this.mediaArtifactStore,
    required this.videoArtifactStore,
    required this.model3DArtifactStore,
    this.storageResolver,
    this.projectId,
    this.expectedUserId,
  });

  Future<PortableAssetCollection> collect(
    DocumentAssetManifest manifest, {
    Iterable<CanvasNode> nodes = const [],
  }) async {
    final bytesById = <String, Uint8List>{};
    final missing = <String>[];
    final invalid = <String>[];
    final invalidReferences = <String>[];
    final dependencyValidation = validatePortableDependencies(
      manifest: manifest,
      nodes: nodes,
    );
    missing.addAll(dependencyValidation.missingAssetIds);
    invalid.addAll(dependencyValidation.invalidAssetIds);
    invalidReferences.addAll(dependencyValidation.invalidReferences);
    // The package manifest remains the complete policy-selected manifest. The
    // dependency closure validates reachability, but must not silently drop
    // unrelated entries and make the archive appear portable with missing
    // manifest payloads.
    for (final asset in manifest.items) {
      final result = await _readAsset(asset);
      if (result == null) {
        missing.add(asset.id);
        continue;
      }
      if (!_matchesMetadata(asset, result)) {
        invalid.add(asset.id);
        continue;
      }
      bytesById[asset.id] = result;
    }

    return PortableAssetCollection(
      assetBytes: bytesById,
      missingAssetIds: missing.toSet().toList(growable: false),
      invalidAssetIds: invalid.toSet().toList(growable: false),
      invalidReferences: invalidReferences.toSet().toList(growable: false),
    );
  }

  Future<Uint8List?> _readAsset(DocumentAsset asset) async {
    final reference = asset.durableReference;
    final bytes = await _readOwnedArtifact(asset, reference);
    if (bytes != null) return bytes;

    final storagePath = durableAssetReference(reference);
    if (storagePath == null || storageResolver == null || projectId == null) {
      return null;
    }
    try {
      final result = await storageResolver!.readBytes(
        projectId: projectId!,
        storagePath: storagePath,
        expectedUserId: expectedUserId,
        maxBytes: _maxBytesFor(asset.kind),
      );
      return result == null || result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _readOwnedArtifact(
    DocumentAsset asset,
    String? rawReference,
  ) async {
    final reference = _typedReference(asset.kind, rawReference);
    if (reference == null) return null;

    try {
      switch (asset.kind) {
        case DocumentAssetKind.image:
          final artifact = await imageArtifactStore.hydrate(
            reference,
            fileName: asset.name,
          );
          if (artifact == null) return null;
          try {
            return await imageArtifactStore.read(artifact);
          } finally {
            await imageArtifactStore.dispose(artifact);
          }
        case DocumentAssetKind.document:
          final artifact = await fileArtifactStore.hydrate(
            reference,
            fileName: asset.name,
          );
          if (artifact == null) return null;
          try {
            return await fileArtifactStore.read(artifact);
          } finally {
            await fileArtifactStore.dispose(artifact);
          }
        case DocumentAssetKind.audio:
          final artifact = await mediaArtifactStore.hydrate(
            reference,
            kind: MediaArtifactKind.original,
            mimeType: asset.mimeType,
            checksum: _checksumValue(asset.checksum),
            fileName: asset.name,
          );
          if (artifact == null) return null;
          try {
            return await mediaArtifactStore.read(artifact);
          } finally {
            await mediaArtifactStore.dispose(artifact);
          }
        case DocumentAssetKind.video:
          final artifact = await videoArtifactStore.hydrate(
            reference,
            fileName: asset.name,
          );
          if (artifact == null) return null;
          try {
            return await videoArtifactStore.read(artifact);
          } finally {
            await videoArtifactStore.dispose(artifact);
          }
        case DocumentAssetKind.model3d:
          final artifact = await model3DArtifactStore.hydrate(
            reference,
            fileName: asset.name,
          );
          if (artifact == null) return null;
          try {
            return await model3DArtifactStore.read(artifact);
          } finally {
            await model3DArtifactStore.dispose(artifact);
          }
        case DocumentAssetKind.drawing:
        case DocumentAssetKind.font:
        case DocumentAssetKind.other:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  String? _typedReference(DocumentAssetKind kind, String? value) {
    return switch (kind) {
      DocumentAssetKind.image => validImageArtifactReference(value),
      DocumentAssetKind.audio => validMediaArtifactReference(value),
      DocumentAssetKind.video => validVideoArtifactReference(value),
      DocumentAssetKind.model3d => validModel3DArtifactReference(value),
      DocumentAssetKind.document => validFileArtifactReference(value),
      _ => null,
    };
  }

  bool _matchesMetadata(DocumentAsset asset, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxBytesFor(asset.kind)) return false;
    if (asset.sizeBytes != null && asset.sizeBytes != bytes.length) {
      return false;
    }
    if (!assetBytesMatchMimeSignature(bytes, asset.mimeType)) return false;
    final rawChecksum = asset.checksum?.trim();
    if (rawChecksum == null || rawChecksum.isEmpty) return true;
    final expectedChecksum = _checksumValue(rawChecksum);
    if (expectedChecksum == null) return false;
    return DocumentPackageArchiveChecksum.sha256(bytes) == expectedChecksum;
  }

  int _maxBytesFor(DocumentAssetKind kind) => switch (kind) {
    DocumentAssetKind.image => 50 * 1024 * 1024,
    DocumentAssetKind.video => 100 * 1024 * 1024,
    DocumentAssetKind.model3d => 100 * 1024 * 1024,
    _ => 512 * 1024 * 1024,
  };

  String? _checksumValue(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    final checksum = normalized.startsWith('sha256:')
        ? normalized.substring('sha256:'.length)
        : normalized;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ? checksum : null;
  }
}
