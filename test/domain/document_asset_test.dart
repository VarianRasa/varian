import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document_asset.dart';

void main() {
  final now = DateTime.utc(2026, 9, 24);

  test('persists only stable opaque asset metadata', () {
    final asset = DocumentAsset(
      id: 'image-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'Hero.png',
      mimeType: 'image/png',
      sizeBytes: 12,
      checksum: 'a' * 64,
      localPath: r'C:\\runtime\\hero.png',
      remoteUrl: 'https://cdn.example/hero.png?token=secret',
      durableReference: 'varian-image://hero-asset',
      createdAt: now,
      updatedAt: now,
    );

    final json = asset.toPersistenceJson();

    expect(json['durableReference'], 'varian-image://hero-asset');
    expect(json.containsKey('localPath'), isFalse);
    expect(json.containsKey('remoteUrl'), isFalse);
    expect(json.toString(), isNot(contains('token=secret')));
  });

  test('persists a durable remote-only opaque reference', () {
    final asset = DocumentAsset(
      id: 'remote-only',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.remote,
      name: 'remote.png',
      mimeType: 'image/png',
      remoteUrl: 'varian-image://remoteonly',
      createdAt: DateTime.utc(2026, 9, 26),
      updatedAt: DateTime.utc(2026, 9, 26),
    );

    final json = asset.toPersistenceJson();

    expect(json['durableReference'], 'varian-image://remoteonly');
    expect(json.containsKey('remoteUrl'), isFalse);
    final restored = DocumentAsset.fromJson(json);
    expect(
      restored.durableReference ?? restored.remoteUrl,
      'varian-image://remoteonly',
    );
  });

  test('persists safe catalog metadata without runtime delivery values', () {
    final asset = DocumentAsset(
      id: 'catalog-node',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'Catalog.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://catalogasset',
      metadata: const {
        'libraryItemId': 'catalog-item',
        'scopeId': 'project-1',
        'source': 'openverse',
        'licenseUrl': 'https://licenses.example/cc0',
        'runtimeUrl': 'https://cdn.example/image.png?token=secret',
        'localPath': r'C:\\runtime\\image.png',
        'inlineBytes': 'data:image/png;base64,AAAA',
      },
      createdAt: now,
      updatedAt: now,
    );

    final json = asset.toPersistenceJson();

    expect(json['metadata'], {
      'libraryItemId': 'catalog-item',
      'scopeId': 'project-1',
      'source': 'openverse',
    });
    expect(json.toString(), isNot(contains('token=secret')));
    expect(json.toString(), isNot(contains('image.png')));
  });

  test('keeps the non-durable asset JSON projection safe as well', () {
    final asset = DocumentAsset(
      id: 'runtime-leak',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'Runtime leak',
      mimeType: 'image/png',
      localPath: r'C:\\runtime\\leak.png',
      remoteUrl: 'https://cdn.example/leak.png?token=secret',
      durableReference: 'varian-image://runtime-leak',
      metadata: const {
        'safe': 'value',
        'runtimeUrl': 'https://cdn.example/leak.png?token=secret',
        'inlineBytes': 'data:image/png;base64,AAAA',
        'bad\nkey': 'discarded',
      },
      createdAt: now,
      updatedAt: now,
    );

    final json = asset.toJson();

    expect(json.containsKey('localPath'), isFalse);
    expect(json.containsKey('remoteUrl'), isFalse);
    expect(json['metadata'], {'safe': 'value'});
    expect(json.toString(), isNot(contains('token=secret')));
    expect(json.toString(), isNot(contains('leak.png')));
  });

  test('sanitizes unsafe runtime fields and metadata while hydrating', () {
    final restored = DocumentAsset.fromJson({
      'id': 'hydrated-runtime',
      'kind': 'image',
      'storage': 'local',
      'name': 'Hydrated image',
      'mimeType': 'image/png',
      'localPath': r'C:\\runtime\\hydrated.png',
      'remoteUrl': 'https://cdn.example/hydrated.png?token=secret',
      'durableReference': 'varian-image://hydrated',
      'metadata': {
        'safe': 'value',
        'runtimeUrl': 'https://cdn.example/hydrated.png?token=secret',
        'localPath': r'C:\\runtime\\hydrated.png',
        'inlineBytes': 'data:image/png;base64,AAAA',
        'bad\nkey': 'discarded',
      },
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    final durable = restored.toPersistenceJson();
    expect(restored.localPath, isNull);
    expect(restored.remoteUrl, isNull);
    expect(durable['metadata'], {'safe': 'value'});
    expect(durable.toString(), isNot(contains('token=secret')));
    expect(durable.toString(), isNot(contains('hydrated.png')));
  });

  test('round trips a manifest and rejects invalid typed references', () {
    final manifest = DocumentAssetManifest(
      entries: {
        'video-1': DocumentAsset(
          id: 'video-1',
          kind: DocumentAssetKind.video,
          storage: DocumentAssetStorage.local,
          name: 'Demo.mp4',
          mimeType: 'video/mp4',
          durableReference: 'varian-video://video-asset',
          createdAt: now,
          updatedAt: now,
        ),
      },
    );

    final restored = DocumentAssetManifest.fromJson(
      manifest.toPersistenceJson(),
    );
    expect(restored['video-1']!.durableReference, 'varian-video://video-asset');

    final invalid = DocumentAssetManifest.fromJson({
      'items': [
        {
          'id': 'bad',
          'kind': 'video',
          'storage': 'local',
          'name': 'Bad',
          'mimeType': 'video/mp4',
          'durableReference': 'varian-image://wrong-kind',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
      ],
    });
    expect(invalid['bad']!.durableReference, isNull);
  });

  test('manifest serialization rejects keys that differ from asset IDs', () {
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

    expect(malformed.toJson, throwsFormatException);
    expect(malformed.toPersistenceJson, throwsFormatException);
    expect(
      () => const DocumentAssetManifest().upsert(asset.copyWith(id: '')),
      throwsFormatException,
    );
  });

  test('manifest mutation rejects propagating an invalid identity map', () {
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

    expect(() => malformed.upsert(asset), throwsFormatException);
    expect(() => malformed.remove('manifest-key'), throwsFormatException);
    expect(
      () => malformed.replace('manifest-key', asset),
      throwsFormatException,
    );
    expect(
      () => malformed.merge(const DocumentAssetManifest()),
      throwsFormatException,
    );
    expect(
      () => const DocumentAssetManifest().merge(malformed),
      throwsFormatException,
    );
    expect(
      () => const DocumentAssetManifest().merge(
        DocumentAssetManifest(entries: {'manifest-key': asset}),
      ),
      throwsFormatException,
    );
  });

  test('manifest copyWith rejects keys that differ from asset IDs', () {
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

    expect(
      () => const DocumentAssetManifest().copyWith(
        entries: {'manifest-key': asset},
      ),
      throwsFormatException,
    );
    expect(() => malformed.copyWith(version: 2), throwsFormatException);
  });

  test('manifest upsert replaces matching IDs and preserves valid aliases', () {
    final original = DocumentAsset(
      id: 'asset-id',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'original.png',
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );
    final replacement = original.copyWith(name: 'replacement.png');
    final next = DocumentAssetManifest(
      entries: {'asset-id': original},
    ).upsert(replacement);

    expect(next.entries.keys, ['asset-id']);
    expect(next['asset-id']!.name, 'replacement.png');
  });

  test('manifest merge preserves the existing asset on an ID collision', () {
    final existing = DocumentAsset(
      id: 'shared',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'Existing.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://existing',
      createdAt: now,
      updatedAt: now,
    );
    final incoming = existing.copyWith(
      name: 'Incoming.png',
      durableReference: 'varian-image://incoming',
    );

    final merged = DocumentAssetManifest(
      entries: {existing.id: existing},
    ).merge(DocumentAssetManifest(entries: {incoming.id: incoming}));

    expect(merged[existing.id], same(existing));
    expect(merged[existing.id]!.durableReference, 'varian-image://existing');
  });

  test('relink rejects an identity that is invalid for the asset kind', () {
    final original = DocumentAsset(
      id: 'image-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.remote,
      name: 'Hero.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://heroasset',
      createdAt: now,
      updatedAt: now,
    );
    final manifest = DocumentAssetManifest(entries: {original.id: original});

    expect(
      () => manifest.relink(
        original.id,
        durableReference: 'varian-video://wrongkind',
      ),
      throwsArgumentError,
    );
  });

  test('relink preserves identity while advancing the asset version', () {
    final original = DocumentAsset(
      id: 'image-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.remote,
      name: 'Hero.png',
      mimeType: 'image/png',
      version: 4,
      durableReference: 'varian-image://heroasset',
      createdAt: now,
      updatedAt: now,
    );
    final manifest = DocumentAssetManifest(entries: {original.id: original});

    final relinked = manifest.relink(
      original.id,
      durableReference: 'varian-image://newheroasset',
    );
    final updated = relinked[original.id]!;

    expect(updated.id, original.id);
    expect(updated.version, original.version + 1);
    expect(updated.createdAt, original.createdAt);
    expect(updated.durableReference, 'varian-image://newheroasset');
  });
}
