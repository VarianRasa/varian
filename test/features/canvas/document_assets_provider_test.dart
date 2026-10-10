import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';

void main() {
  test('provider rejects a manifest with mismatched asset identities', () {
    final now = DateTime.utc(2026, 9, 27);
    final asset = DocumentAsset(
      id: 'asset-id',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'image.png',
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );
    final malformed = DocumentAssetManifest(entries: {'manifest-key': asset});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container
          .read(documentAssetsProvider.notifier)
          .setManifest(malformed),
      throwsFormatException,
    );
    expect(container.read(documentAssetsProvider).entries, isEmpty);
  });

  test('publishes an owned copy of the supplied manifest', () {
    final now = DateTime.utc(2026, 9, 27);
    final asset = DocumentAsset(
      id: 'asset-id',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'image.png',
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );
    final entries = <String, DocumentAsset>{asset.id: asset};
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(documentAssetsProvider.notifier)
        .setManifest(DocumentAssetManifest(entries: entries));

    entries.clear();

    expect(
      container.read(documentAssetsProvider).entries.keys,
      contains(asset.id),
    );
  });
}
