import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/features/assets/domain/asset_library.dart';

void main() {
  test('treats an existing owned artifact reference as insertable', () {
    final item = AssetLibraryItem(
      id: 'artifact-item',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Hero.png',
      mimeType: 'image/png',
      metadata: const {'imageArtifactReference': 'varian-image://memory-1'},
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );

    expect(item.isInsertable, isTrue);
  });

  test('round trips folders without allowing self-parenting', () {
    final folder = AssetLibraryFolder(
      id: 'folder-1',
      scopeId: 'project-1',
      name: 'Brand',
      parentId: 'root',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    expect(AssetLibraryFolder.fromJson(folder.toJson()).name, 'Brand');
    expect(
      () =>
          AssetLibraryFolder.fromJson({...folder.toJson(), 'id': ' folder-1'}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => AssetLibraryFolder(
        id: 'folder-1',
        scopeId: 'project-1',
        name: 'Brand',
        parentId: 'folder-1',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
  });

  test('round trips a catalog item and preserves provenance', () {
    final item = AssetLibraryItem(
      id: 'openverse:image-1',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.openverse,
      name: 'Mountain lake',
      creator: 'Example artist',
      sourceUrl: 'https://example.org/original.jpg',
      previewUrl: 'https://example.org/thumb.jpg',
      mimeType: 'image/jpeg',
      license: 'CC0',
      licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
      attribution: 'Example artist / Example source',
      tags: const ['nature', 'hero'],
      favorite: true,
      width: 1200,
      height: 800,
      metadata: const {'providerAssetId': 'image-1'},
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    final restored = AssetLibraryItem.fromJson(item.toJson());

    expect(restored.id, item.id);
    expect(restored.source, AssetLibrarySource.openverse);
    expect(restored.license, 'CC0');
    expect(restored.tags, ['nature', 'hero']);
    expect(restored.favorite, isTrue);
    expect(restored.metadata['providerAssetId'], 'image-1');
    final invalidStatus = item.toJson()..['status'] = 'unexpected';
    expect(
      () => AssetLibraryItem.fromJson(invalidStatus),
      throwsA(isA<FormatException>()),
    );
  });

  test('maps a catalog item to one durable document asset', () {
    final item = AssetLibraryItem(
      id: 'upload-1',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Brand mark.png',
      mimeType: 'image/png',
      localPath: 'C:/assets/brand.png',
      checksum:
          'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      license: 'User supplied',
      tags: const ['brand'],
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    final asset = item.toDocumentAsset();

    expect(asset.id, 'upload-1');
    expect(asset.kind, DocumentAssetKind.image);
    expect(asset.storage, DocumentAssetStorage.unknown);
    expect(asset.localPath, isNull);
    expect(asset.remoteUrl, isNull);
    expect(asset.durableReference, isNull);
    expect(
      asset.checksum,
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(asset.metadata['libraryItemId'], 'upload-1');

    final portable = item
        .copyWith(
          localPath: 'C:/assets/brand.png',
          storagePath: 'project-1/library/brand.png',
          downloadUrl: 'https://cdn.example.org/brand.png',
        )
        .toDocumentAsset();
    expect(portable.storage, DocumentAssetStorage.remote);
    expect(portable.durableReference, 'project-1/library/brand.png');
  });

  test(
    'retains a materialized opaque image reference without runtime values',
    () {
      final item = AssetLibraryItem(
        id: 'remote-image',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.openverse,
        name: 'Materialized image',
        sourceUrl: 'https://provider.example/image.png',
        downloadUrl: 'https://provider.example/image.png',
        localPath: r'C:\\Users\\user\\image.png',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      );

      final asset = item.toDocumentAsset(
        imageArtifactReference: 'varian-image://materialized-image',
      );

      expect(asset.storage, DocumentAssetStorage.local);
      expect(asset.durableReference, 'varian-image://materialized-image');
      expect(asset.localPath, isNull);
      expect(asset.remoteUrl, isNull);
      expect(
        asset.toPersistenceJson()['durableReference'],
        'varian-image://materialized-image',
      );
    },
  );

  test('only durable catalog items are insertable', () {
    final missing = AssetLibraryItem(
      id: 'missing-source',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Missing source',
      status: AssetLibraryItemStatus.ready,
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );
    final remote = missing.copyWith(
      id: 'remote-source',
      source: AssetLibrarySource.remote,
      sourceUrl: 'https://example.org/image.png',
    );
    final bundled = missing.copyWith(
      id: 'bundled-shape',
      source: AssetLibrarySource.bundled,
    );

    expect(missing.hasDurableReference, isFalse);
    expect(remote.hasDurableReference, isFalse);
    expect(bundled.hasDurableReference, isTrue);
    expect(remote.isInsertable, isTrue);
    expect(
      remote.copyWith(status: AssetLibraryItemStatus.syncing).isInsertable,
      isFalse,
    );
    final storageOnly = missing.copyWith(
      id: 'storage-only',
      storagePath: 'project-1/library/object.png',
    );
    // Private Storage paths are durable references. Rendering hydrates them
    // through the runtime resolver after insertion, so the catalog item remains
    // insertable without persisting a signed URL.
    expect(storageOnly.isInsertable, isTrue);
    expect(storageOnly.toDocumentAsset().hasDurableReference, isTrue);
    expect(
      storageOnly.toDocumentAsset().durableReference,
      storageOnly.storagePath,
    );
  });

  test('filters query results by category, tags and favorites', () {
    final items = [
      AssetLibraryItem(
        id: 'one',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.upload,
        name: 'Brand hero',
        tags: const ['brand', 'approved'],
        favorite: true,
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      AssetLibraryItem(
        id: 'two',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.audio,
        source: AssetLibrarySource.upload,
        name: 'Brand voiceover',
        tags: const ['brand'],
        createdAt: DateTime.utc(2026, 9, 14),
        updatedAt: DateTime.utc(2026, 9, 14),
      ),
    ];

    final result = filterAssetLibraryItems(
      items,
      const AssetLibraryQuery(
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        tags: ['brand'],
        favoritesOnly: true,
      ),
    );

    expect(result.map((item) => item.id), ['one']);
  });

  test('rejects invalid catalog identifiers and unsafe provider URLs', () {
    expect(
      () => AssetLibraryItem(
        id: '',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.openverse,
        name: 'Image',
        sourceUrl: 'javascript:alert(1)',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssetLibraryItem(
        id: 'insecure-preview',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.openverse,
        name: 'Image',
        previewUrl: 'http://example.org/image.png',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssetLibraryItem(
        id: 'credential-url',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.openverse,
        name: 'Image',
        sourceUrl: 'https://user:secret@example.org/image.png',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssetLibraryItem(
        id: 'whitespace-url',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.openverse,
        name: 'Image',
        sourceUrl: 'https://example.org/image.png\n',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssetLibraryItem(
        id: 'whitespace-license',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.upload,
        name: 'Image',
        license: ' User supplied',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsA(
        predicate<ArgumentError>(
          (error) =>
              error.message ==
              'Asset license cannot contain surrounding whitespace',
        ),
      ),
    );
    expect(
      () => AssetLibraryItem(
        id: 'whitespace-local-path',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.upload,
        name: 'Image',
        localPath: r' C:\\assets\\image.png ',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssetLibraryItem(
        id: 'whitespace-tag',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.upload,
        name: 'Image',
        tags: const [' brand '],
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssetLibraryItem(
        id: 'invalid-mime',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.file,
        source: AssetLibrarySource.upload,
        name: 'File',
        mimeType: 'not-a-mime',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
    final validJson = <String, dynamic>{
      'id': 'typed-record',
      'scopeId': 'project-1',
      'kind': 'file',
      'source': 'upload',
      'status': 'ready',
      'name': 'File',
      'createdAt': '2026-09-15T00:00:00Z',
      'updatedAt': '2026-09-15T00:00:00Z',
    };
    expect(
      () => AssetLibraryItem.fromJson({...validJson, 'id': 42}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => AssetLibraryItem.fromJson({...validJson, 'tags': 'brand'}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => AssetLibraryItem.fromJson({...validJson, 'id': ' typed-record'}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => AssetLibraryItem.fromJson({
        ...validJson,
        'tags': ['brand '],
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => AssetLibraryItem(
        id: 'trailing-control\n',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.file,
        source: AssetLibrarySource.upload,
        name: 'File',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssetLibraryItem(
        id: 'unsafe-storage-path',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.file,
        source: AssetLibrarySource.upload,
        name: 'File',
        storagePath: 'project-1/library/file.bin\n',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
      throwsArgumentError,
    );
    final safeTags = AssetLibraryItem(
      id: 'safe-tags',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.file,
      source: AssetLibrarySource.upload,
      name: 'File',
      tags: const ['safe', 'unsafe\nvalue'],
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );
    expect(safeTags.tags, ['safe']);
  });

  test('does not promote in-memory data previews into document metadata', () {
    final item = AssetLibraryItem(
      id: 'preview-only',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Preview only',
      previewUrl: 'data:image/png;base64,AA==',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    expect(item.toJson()['previewUrl'], isNull);
    final filePreview = item.copyWith(previewUrl: 'file:///tmp/preview.png');
    expect(filePreview.toJson()['previewUrl'], isNull);
    final asset = item.toDocumentAsset();
    expect(asset.hasDurableReference, isFalse);
    expect(asset.thumbnailReference, isNull);

    final uppercaseData = item.copyWith(
      previewUrl: 'DATA:image/png;base64,AA==',
      localPath: 'data:image/png;base64,AA==',
    );
    expect(uppercaseData.toJson()['previewUrl'], isNull);
    expect(uppercaseData.toJson()['localPath'], isNull);
    expect(uppercaseData.toDocumentAsset().hasDurableReference, isFalse);

    final metadataSafe = item.copyWith(
      metadata: {
        'nested': {'preview': 'data:image/png;base64,AA==', 'label': 'safe'},
        'bad\nkey': 'value',
        'control': 'bad\u0001value',
        'tooLarge': 'x' * 4097,
      },
    );
    expect(metadataSafe.metadata['nested'], {'label': 'safe'});
    expect(metadataSafe.metadata.containsKey('bad\nkey'), isFalse);
    expect(metadataSafe.metadata.containsKey('control'), isFalse);
    expect(metadataSafe.metadata.containsKey('tooLarge'), isFalse);
    expect(
      () => (metadataSafe.metadata['nested'] as Map)['label'] = 'changed',
      throwsUnsupportedError,
    );

    expect(
      () => item.copyWith(
        metadata: {
          for (var index = 0; index < 100; index++) 'large-$index': 'x' * 4096,
        },
      ),
      throwsArgumentError,
    );
  });
}
