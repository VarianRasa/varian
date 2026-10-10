import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/assets/data/asset_library_service.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/data/providers/asset_provider_contract.dart';
import 'package:varian/features/assets/domain/asset_library.dart';

class _FakeProvider implements AssetCatalogProvider {
  AssetLibraryQuery? lastQuery;
  final AssetLibraryPage page;
  final Object? error;

  _FakeProvider(this.page, {this.error});

  @override
  String get id => 'fake';

  @override
  Future<AssetLibraryPage> search(AssetLibraryQuery query) async {
    lastQuery = query;
    if (error != null) throw error!;
    return page;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'does not persist bundled assets through the remote-capable save API',
    () async {
      final service = AssetLibraryService(
        scopeId: 'project-1',
        localStorage: LocalStorageService(),
      );
      final bundled = AssetLibraryService.builtInItems('project-1').first;

      await expectLater(service.save(bundled), throwsArgumentError);
    },
  );

  test('requires a path-safe project scope for Storage-backed assets', () {
    expect(
      () => AssetLibraryService(
        scopeId: 'project/1',
        localStorage: LocalStorageService(),
      ),
      throwsArgumentError,
    );
  });

  test('requires a license before saving external catalog assets', () async {
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );
    final item = AssetLibraryItem(
      id: 'remote-without-license',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.openverse,
      name: 'Unlicensed result',
      sourceUrl: 'https://example.org/unlicensed.jpg',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    await expectLater(service.saveProviderItem(item), throwsArgumentError);
  });

  test('rejects Storage paths owned by other asset namespaces', () async {
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );
    final item = AssetLibraryItem(
      id: 'collaboration-reference',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Collaboration object',
      storagePath: 'project-1/collaboration/object.png',
      sizeBytes: 1,
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    await expectLater(service.save(item), throwsArgumentError);
  });

  test('validates usage identifiers before recording telemetry', () async {
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );

    await expectLater(service.recordUsage('asset\n'), throwsArgumentError);
    await expectLater(service.recordUsage(' asset '), throwsArgumentError);
    await expectLater(
      service.recordUsage('asset', nodeId: 'node\n'),
      throwsArgumentError,
    );
    await expectLater(
      service.recordUsage('asset', nodeId: ' node '),
      throwsArgumentError,
    );
  });

  test('rejects malformed combined-pagination cursors', () async {
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );

    await expectLater(
      service.search(
        const AssetLibraryQuery(
          scopeId: 'project-1',
          cursor: 'local:not-a-number',
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      service.search(
        const AssetLibraryQuery(scopeId: 'project-1', cursor: 'not-a-cursor'),
      ),
      throwsArgumentError,
    );
    await expectLater(
      service.search(
        const AssetLibraryQuery(scopeId: 'project-1', cursor: 'remote:'),
      ),
      throwsArgumentError,
    );
    await expectLater(
      service.search(
        const AssetLibraryQuery(scopeId: 'project-1', tags: [' image ']),
      ),
      throwsArgumentError,
    );
  });

  test('persists bounded deletion tombstones locally', () async {
    final storage = LocalStorageService();
    await storage.saveAssetLibraryDeletionTombstones('project-1', {
      'asset-1': 'project-1/library/asset-1.png',
      'asset-2': null,
    });

    expect(await storage.loadAssetLibraryDeletionTombstones('project-1'), {
      'asset-1': 'project-1/library/asset-1.png',
      'asset-2': null,
    });
  });

  test('local persistence never crosses project scopes', () async {
    final storage = LocalStorageService();
    final otherItem = AssetLibraryItem(
      id: 'other-item',
      scopeId: 'project-2',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Other project asset',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );
    final otherFolder = AssetLibraryFolder(
      id: 'other-folder',
      scopeId: 'project-2',
      name: 'Other project folder',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );
    await storage.saveAssetLibrary('project-1', [otherItem]);
    await storage.saveAssetLibraryFolders('project-1', [otherFolder]);

    expect(await storage.loadAssetLibrary('project-1'), isEmpty);
    expect(await storage.loadAssetLibraryFolders('project-1'), isEmpty);
  });

  test('persists uploaded and favorite catalog items locally', () async {
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );
    await service.load();
    final saved = await service.save(
      AssetLibraryItem(
        id: 'upload-1',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.upload,
        name: 'Brand hero',
        localPath: 'C:/assets/hero.png',
        mimeType: 'image/png',
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
    );
    await service.setFavorite(saved.id, true);

    final restored = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );
    final page = await restored.search(
      const AssetLibraryQuery(scopeId: 'project-1', favoritesOnly: true),
    );

    expect(page.items.map((item) => item.id), ['upload-1']);
    expect(page.items.single.favorite, isTrue);
  });

  test(
    'keeps offline deletes as tombstones instead of resurrecting assets',
    () async {
      final storage = LocalStorageService();
      final service = AssetLibraryService(
        scopeId: 'project-1',
        localStorage: storage,
      );
      final item = await service.save(
        AssetLibraryItem(
          id: 'offline-delete',
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          source: AssetLibrarySource.upload,
          name: 'Offline asset',
          storagePath: 'project-1/library/offline.png',
          createdAt: DateTime.utc(2026, 9, 15),
          updatedAt: DateTime.utc(2026, 9, 15),
        ),
      );

      await service.delete(item.id);
      final restored = AssetLibraryService(
        scopeId: 'project-1',
        localStorage: storage,
      );
      await restored.load();

      expect(restored.items.where((asset) => asset.id == item.id), isEmpty);
      expect(await storage.loadAssetLibraryDeletionTombstones('project-1'), {
        'offline-delete': 'project-1/library/offline.png',
      });
    },
  );

  test(
    'bounds orphan cleanup and is a no-op without a remote client',
    () async {
      final service = AssetLibraryService(
        scopeId: 'project-1',
        localStorage: LocalStorageService(),
      );

      expect(await service.cleanupOrphanedStorage(maxObjects: 1), 0);
      await expectLater(
        service.cleanupOrphanedStorage(minimumAge: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      await expectLater(
        service.cleanupOrphanedStorage(maxObjects: 5001),
        throwsArgumentError,
      );
    },
  );

  test(
    'persists folders and only unassigns assets in a deleted folder',
    () async {
      final service = AssetLibraryService(
        scopeId: 'project-1',
        localStorage: LocalStorageService(),
      );
      final folder = await service.createFolder('Brand');
      expect(
        await service.localStorage.loadAssetLibraryFolderUpsertQueue(
          'project-1',
        ),
        contains(folder.id),
      );
      await service.save(
        AssetLibraryItem(
          id: 'folder-item',
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          source: AssetLibrarySource.upload,
          name: 'Logo',
          folderId: folder.id,
          createdAt: DateTime.utc(2026, 9, 15),
          updatedAt: DateTime.utc(2026, 9, 15),
        ),
      );
      await service.save(
        AssetLibraryItem(
          id: 'legacy-folder-item',
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          source: AssetLibrarySource.upload,
          name: 'Legacy',
          folderId: 'legacy-folder',
          createdAt: DateTime.utc(2026, 9, 15),
          updatedAt: DateTime.utc(2026, 9, 15),
        ),
      );

      await service.deleteFolder(folder.id);

      expect(service.folders, isEmpty);
      expect(
        service.items.firstWhere((item) => item.id == 'folder-item').folderId,
        isNull,
      );
      expect(
        service.items
            .firstWhere((item) => item.id == 'legacy-folder-item')
            .folderId,
        'legacy-folder',
      );
      final restored = AssetLibraryService(
        scopeId: 'project-1',
        localStorage: service.localStorage,
      );
      await restored.load();
      expect(restored.folders, isEmpty);
      expect(
        await service.localStorage.loadAssetLibraryFolderDeletionTombstones(
          'project-1',
        ),
        contains(folder.id),
      );
      expect(
        await service.localStorage.loadAssetLibraryFolderUpsertQueue(
          'project-1',
        ),
        isNot(contains(folder.id)),
      );
    },
  );

  test(
    'keeps machine-local uploads out of remote preview validation',
    () async {
      final service = AssetLibraryService(
        scopeId: 'project-1',
        localStorage: LocalStorageService(),
      );
      final item = await service.saveUpload(
        AssetPickerResult(
          name: 'logo.png',
          path: r'C:\\assets\\logo.png',
          storagePath: 'project-1/library/logo.png',
          bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          size: 8,
        ),
      );

      expect(item.localPath, r'C:\\assets\\logo.png');
      expect(item.previewUrl, isNull);
      expect(item.storagePath, 'project-1/library/logo.png');
      expect(item.status, AssetLibraryItemStatus.ready);
    },
  );

  test(
    'keeps Storage-backed catalog uploads pending when remote sync is unavailable',
    () async {
      final service = AssetLibraryService(
        scopeId: 'project-1',
        localStorage: LocalStorageService(),
      );
      final item = await service.save(
        AssetLibraryItem(
          id: 'storage-with-local-fallback',
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          source: AssetLibrarySource.upload,
          name: 'Cloud logo',
          localPath: r'C:\\assets\\cloud-logo.png',
          storagePath: 'project-1/library/cloud-logo.png',
          mimeType: 'image/png',
          createdAt: DateTime.utc(2026, 9, 15),
          updatedAt: DateTime.utc(2026, 9, 15),
        ),
      );

      expect(item.status, AssetLibraryItemStatus.syncing);
      expect(service.isOffline, isTrue);
    },
  );

  test('rejects binary and remote URLs passed as local upload paths', () async {
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );

    expect(
      () => service.saveUpload(
        AssetPickerResult(
          name: 'preview.png',
          path: 'data:image/png;base64,AA==',
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => service.saveUpload(
        AssetPickerResult(
          name: 'remote.png',
          path: 'ftp://example.org/remote.png',
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => service.saveUpload(
        AssetPickerResult(
          name: 'remote.png',
          path: 'https://example.org/remote.png',
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rejects a file whose bytes do not match its MIME type', () async {
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );

    expect(
      () => service.saveUpload(
        AssetPickerResult(
          name: 'not-a-png.png',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          size: 4,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rejects uploads larger than the hard limit', () async {
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );

    expect(
      () => service.saveUpload(
        AssetPickerResult(name: 'large.bin', size: 512 * 1024 * 1024 + 1),
      ),
      throwsArgumentError,
    );
  });

  test(
    'deduplicates uploads by checksum before saving a second record',
    () async {
      final service = AssetLibraryService(
        scopeId: 'project-1',
        localStorage: LocalStorageService(),
      );
      final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final first = await service.saveUpload(
        AssetPickerResult(name: 'first.png', bytes: bytes, size: bytes.length),
      );
      final second = await service.saveUpload(
        AssetPickerResult(name: 'second.png', bytes: bytes, size: bytes.length),
      );

      expect(second.id, first.id);
      expect(
        service.items.where((item) => item.checksum == first.checksum),
        hasLength(1),
      );
    },
  );

  test('combines local and provider results with a remote cursor', () async {
    final provider = _FakeProvider(
      AssetLibraryPage(
        items: [
          AssetLibraryItem(
            id: 'fake:one',
            scopeId: 'project-1',
            kind: AssetLibraryItemKind.image,
            source: AssetLibrarySource.remote,
            name: 'Remote image',
            sourceUrl: 'https://example.org/remote.jpg',
            createdAt: DateTime.utc(2026, 9, 15),
            updatedAt: DateTime.utc(2026, 9, 15),
          ),
        ],
        nextCursor: '2',
      ),
    );
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
      providers: [provider],
    );

    final page = await service.search(
      const AssetLibraryQuery(
        scopeId: 'project-1',
        query: 'remote',
        includeRemote: true,
      ),
    );

    expect(page.items.single.id, 'fake:one');
    expect(page.nextCursor, 'remote:2');
    expect(provider.lastQuery?.query, 'remote');
  });

  test('does not expose unsafe provider cursors to the next page', () async {
    final provider = _FakeProvider(
      AssetLibraryPage(
        items: [
          AssetLibraryItem(
            id: 'fake:cursor',
            scopeId: 'project-1',
            kind: AssetLibraryItemKind.image,
            source: AssetLibrarySource.remote,
            name: 'Remote image',
            sourceUrl: 'https://example.org/remote.jpg',
            createdAt: DateTime.utc(2026, 9, 15),
            updatedAt: DateTime.utc(2026, 9, 15),
          ),
        ],
        nextCursor: '2\n',
      ),
    );
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
      providers: [provider],
    );

    final page = await service.search(
      const AssetLibraryQuery(
        scopeId: 'project-1',
        query: 'remote',
        includeRemote: true,
      ),
    );

    expect(page.items, hasLength(1));
    expect(page.nextCursor, isNull);
  });

  test('paginates local catalog items before provider pages', () async {
    final localItems = [
      for (var index = 0; index < 25; index++)
        AssetLibraryItem(
          id: 'local:$index',
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          source: AssetLibrarySource.upload,
          name: 'Local $index',
          localPath: 'C:/assets/$index.png',
          createdAt: DateTime.utc(2026, 9, 15),
          updatedAt: DateTime.utc(
            2026,
            9,
            15,
          ).subtract(Duration(seconds: index)),
        ),
    ];
    final storage = LocalStorageService();
    await storage.saveAssetLibrary('project-1', localItems);
    final provider = _FakeProvider(
      AssetLibraryPage(
        items: [
          AssetLibraryItem(
            id: 'fake:remote',
            scopeId: 'project-1',
            kind: AssetLibraryItemKind.image,
            source: AssetLibrarySource.remote,
            name: 'Local remote result',
            sourceUrl: 'https://example.org/remote.jpg',
            createdAt: DateTime.utc(2026, 9, 15),
            updatedAt: DateTime.utc(
              2026,
              9,
              15,
            ).subtract(const Duration(seconds: 100)),
          ),
        ],
        nextCursor: '2',
      ),
    );
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: storage,
      providers: [provider],
    );

    final first = await service.search(
      const AssetLibraryQuery(
        scopeId: 'project-1',
        query: 'local',
        pageSize: 10,
        includeRemote: true,
      ),
    );
    final second = await service.search(
      AssetLibraryQuery(
        scopeId: 'project-1',
        query: 'local',
        pageSize: 10,
        cursor: first.nextCursor,
        includeRemote: true,
      ),
    );
    final third = await service.search(
      AssetLibraryQuery(
        scopeId: 'project-1',
        query: 'local',
        pageSize: 10,
        cursor: second.nextCursor,
        includeRemote: true,
      ),
    );

    expect(first.items.map((item) => item.id), [
      for (var index = 0; index < 10; index++) 'local:$index',
    ]);
    expect(first.nextCursor, 'local:10');
    expect(second.items.map((item) => item.id), [
      for (var index = 10; index < 20; index++) 'local:$index',
    ]);
    expect(second.nextCursor, 'local:20');
    expect(third.items.map((item) => item.id), [
      for (var index = 20; index < 25; index++) 'local:$index',
      'fake:remote',
    ]);
    expect(third.nextCursor, 'remote:2');

    expect(provider.lastQuery?.cursor, isNull);
    expect(provider.lastQuery?.pageSize, 5);
  });

  test('uses a bounded provider cache when the provider is offline', () async {
    final remoteItem = AssetLibraryItem(
      id: 'fake:cached',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.remote,
      name: 'Cached image',
      sourceUrl: 'https://example.org/cached.jpg',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );
    final storage = LocalStorageService();
    final online = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: storage,
      providers: [
        _FakeProvider(AssetLibraryPage(items: [remoteItem], nextCursor: '2')),
      ],
    );
    await online.search(
      const AssetLibraryQuery(scopeId: 'project-1', includeRemote: true),
    );

    final offline = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: storage,
      providers: [
        _FakeProvider(
          const AssetLibraryPage(),
          error: const AssetProviderException('fake', 'offline'),
        ),
      ],
    );
    final page = await offline.search(
      const AssetLibraryQuery(scopeId: 'project-1', includeRemote: true),
    );

    expect(
      page.items.where((item) => item.name == 'Cached image'),
      hasLength(1),
    );
    expect(page.nextCursor, 'remote:2');
    expect(page.fromCache, isTrue);
    expect(page.isOffline, isTrue);
  });

  test('does not duplicate a provider item when saved twice', () async {
    final service = AssetLibraryService(
      scopeId: 'project-1',
      localStorage: LocalStorageService(),
    );
    await service.load();
    final item = AssetLibraryItem(
      id: 'openverse:one',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.openverse,
      providerAssetId: 'one',
      name: 'One',
      sourceUrl: 'https://example.org/one.jpg',
      license: 'CC0',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    final saved = await service.saveProviderItem(item);
    expect(saved.status, AssetLibraryItemStatus.syncing);
    await service.saveProviderItem(item.copyWith(name: 'One renamed'));

    final page = await service.search(
      const AssetLibraryQuery(scopeId: 'project-1'),
    );
    expect(
      page.items.where((candidate) => candidate.id == item.id),
      hasLength(1),
    );
    expect(
      page.items.firstWhere((candidate) => candidate.id == item.id).name,
      'One renamed',
    );
  });
}
