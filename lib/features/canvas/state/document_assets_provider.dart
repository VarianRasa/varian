import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/document_asset.dart';

final documentAssetsProvider =
    StateNotifierProvider<DocumentAssetsNotifier, DocumentAssetManifest>(
      (ref) => DocumentAssetsNotifier(),
    );

class DocumentAssetsNotifier extends StateNotifier<DocumentAssetManifest> {
  DocumentAssetsNotifier() : super(const DocumentAssetManifest());

  void setManifest(DocumentAssetManifest manifest) {
    manifest.validateIdentity();
    state = DocumentAssetManifest(
      version: manifest.version,
      entries: Map.unmodifiable(manifest.entries),
    );
  }

  void merge(DocumentAssetManifest manifest) {
    manifest.validateIdentity();
    state = state.merge(manifest);
  }

  void upsert(DocumentAsset asset) {
    state = state.upsert(asset);
  }

  void remove(String assetId) {
    state = state.remove(assetId);
  }

  void clear() {
    state = const DocumentAssetManifest();
  }
}
