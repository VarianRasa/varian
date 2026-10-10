import '../../../domain/models/document_asset.dart';
import '../../../domain/models/durable_asset_reference.dart';

String? _validatedDurableExportReference(DocumentAsset asset) {
  final value = durableAssetReference(asset.durableReference);
  if (value != null) return value;
  return switch (asset.kind) {
    DocumentAssetKind.image => validImageArtifactReference(
      asset.durableReference,
    ),
    DocumentAssetKind.audio => validMediaArtifactReference(
      asset.durableReference,
    ),
    DocumentAssetKind.video => validVideoArtifactReference(
      asset.durableReference,
    ),
    DocumentAssetKind.model3d => validModel3DArtifactReference(
      asset.durableReference,
    ),
    DocumentAssetKind.document => validFileArtifactReference(
      asset.durableReference,
    ),
    _ => null,
  };
}

bool _isSafeThumbnailReference(String value) =>
    durableAssetReference(value) != null ||
    validImageArtifactReference(value) != null ||
    validMediaArtifactReference(value) != null;

bool _hasUnsafeExportReference(DocumentAsset asset) =>
    asset.localPath != null ||
    asset.remoteUrl != null ||
    (asset.durableReference != null &&
        _validatedDurableExportReference(asset) == null);

bool _hasSafeDurableExportReference(DocumentAsset asset) =>
    !_hasUnsafeExportReference(asset) &&
    _validatedDurableExportReference(asset) != null;

class AssetExportPolicy {
  final Set<DocumentAssetKind> includedKinds;
  final Set<String> includedAssetIds;
  final Set<String> excludedAssetIds;
  final Set<String> allowedLicenses;
  final bool includeMissingSources;
  final bool includeThumbnails;

  const AssetExportPolicy({
    this.includedKinds = const {},
    this.includedAssetIds = const {},
    this.excludedAssetIds = const {},
    this.allowedLicenses = const {},
    this.includeMissingSources = false,
    this.includeThumbnails = false,
  });

  bool includes(DocumentAsset asset, {bool hasSuppliedBytes = false}) {
    if (excludedAssetIds.contains(asset.id)) return false;
    if (includedAssetIds.isNotEmpty && !includedAssetIds.contains(asset.id)) {
      return false;
    }
    if (includedKinds.isNotEmpty && !includedKinds.contains(asset.kind)) {
      return false;
    }
    if (allowedLicenses.isNotEmpty &&
        !allowedLicenses.contains(asset.license ?? 'unknown')) {
      return false;
    }
    if (_hasUnsafeExportReference(asset) ||
        (!includeMissingSources &&
            !hasSuppliedBytes &&
            !_hasSafeDurableExportReference(asset))) {
      return false;
    }
    return true;
  }

  DocumentAssetManifest apply(
    DocumentAssetManifest manifest, {
    Set<String> suppliedAssetIds = const {},
  }) {
    manifest.validateIdentity();
    return manifest.copyWith(
      entries: {
        for (final asset in manifest.items)
          if (includes(
            asset,
            hasSuppliedBytes: suppliedAssetIds.contains(asset.id),
          ))
            asset.id:
                includeThumbnails &&
                    (asset.thumbnailReference == null ||
                        _isSafeThumbnailReference(asset.thumbnailReference!))
                ? asset
                : asset.copyWith(thumbnailReference: null),
      },
    );
  }
}
