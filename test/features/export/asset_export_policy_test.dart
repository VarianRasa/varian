import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/features/export/domain/asset_export_policy.dart';

void main() {
  test('asset package policy filters missing sources and thumbnails', () {
    final now = DateTime.utc(2026, 9, 11);
    final durable = DocumentAsset(
      id: 'durable',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'durable.png',
      mimeType: 'image/png',
      durableReference: 'project/assets/durable.png',
      thumbnailReference: 'thumb://durable',
      createdAt: now,
      updatedAt: now,
    );
    final missing = DocumentAsset(
      id: 'missing',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.unknown,
      name: 'missing.png',
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );
    final manifest = DocumentAssetManifest(
      entries: {durable.id: durable, missing.id: missing},
    );

    final filtered = const AssetExportPolicy().apply(manifest);
    expect(filtered.items.map((asset) => asset.id), ['durable']);
    expect(filtered['durable']?.thumbnailReference, isNull);
  });

  test('asset package policy can include only selected kinds and licenses', () {
    final now = DateTime.utc(2026, 9, 11);
    final image = DocumentAsset(
      id: 'image',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.remote,
      name: 'image.png',
      mimeType: 'image/png',
      durableReference: 'project/assets/image.png',
      license: 'CC0',
      createdAt: now,
      updatedAt: now,
    );
    final video = DocumentAsset(
      id: 'video',
      kind: DocumentAssetKind.video,
      storage: DocumentAssetStorage.remote,
      name: 'video.mp4',
      mimeType: 'video/mp4',
      durableReference: 'project/assets/video.mp4',
      license: 'Proprietary',
      createdAt: now,
      updatedAt: now,
    );
    final filtered = const AssetExportPolicy(
      includedKinds: {DocumentAssetKind.image},
      allowedLicenses: {'CC0'},
    ).apply(DocumentAssetManifest(entries: {image.id: image, video.id: video}));

    expect(filtered.items.single.id, 'image');
  });

  test('rejects native paths and provider URLs as export sources', () {
    final now = DateTime.utc(2026, 9, 11);
    final manifest = DocumentAssetManifest(
      entries: {
        'path': DocumentAsset(
          id: 'path',
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.local,
          name: 'path.png',
          mimeType: 'image/png',
          localPath: 'C:/assets/path.png',
          createdAt: now,
          updatedAt: now,
        ),
        'url': DocumentAsset(
          id: 'url',
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.remote,
          name: 'url.png',
          mimeType: 'image/png',
          remoteUrl: 'https://cdn.example.test/url.png',
          createdAt: now,
          updatedAt: now,
        ),
      },
    );

    expect(
      const AssetExportPolicy(
        includeMissingSources: true,
      ).apply(manifest).items,
      isEmpty,
    );
  });

  test('excludes unsafe references even when missing sources are included', () {
    final now = DateTime.utc(2026, 9, 11);
    final unsafe = DocumentAsset(
      id: 'unsafe',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.unknown,
      name: 'unsafe.png',
      mimeType: 'image/png',
      durableReference: 'data:image/png;base64,AA==',
      remoteUrl: 'https://cdn.example.test/unsafe.png?token=secret',
      createdAt: now,
      updatedAt: now,
    );
    final missing = DocumentAsset(
      id: 'missing',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.unknown,
      name: 'missing.png',
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );

    final filtered = const AssetExportPolicy(includeMissingSources: true).apply(
      DocumentAssetManifest(entries: {unsafe.id: unsafe, missing.id: missing}),
    );

    expect(filtered.items.map((asset) => asset.id), ['missing']);
  });
}
