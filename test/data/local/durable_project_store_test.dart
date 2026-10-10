import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/features/assets/domain/asset_library.dart';
import 'package:varian/features/history/snapshot_manager.dart';

void main() {
  late Directory tempDirectory;
  late String databasePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('varian-durable-');
    databasePath =
        '${tempDirectory.path}${Platform.pathSeparator}runtime.sqlite';
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<DurableProjectStore> openStore() async {
    final database = ProjectDurableDatabase(NativeDatabase(File(databasePath)));
    final store = DurableProjectStore(database: database);
    await store.ready;
    return store;
  }

  test(
    'document survives store recreation on the durable SQLite backend',
    () async {
      final first = await openStore();
      addTearDown(first.close);
      final document = jsonEncode({
        'schemaVersion': 7,
        'projectId': 'project-a',
        'nodes': [
          {'id': 'node-a', 'type': 'rectangle'},
        ],
      });

      await first.writeDocument(
        projectId: 'project-a',
        documentJson: document,
        schemaVersion: 7,
      );
      await first.close();

      final second = await openStore();
      addTearDown(second.close);

      expect(await second.readDocument('project-a'), document);
    },
  );

  test(
    'project records, queues, recovery, and history cannot cross project IDs',
    () async {
      final store = await openStore();
      addTearDown(store.close);

      await store.writeDocument(
        projectId: 'project-a',
        documentJson: jsonEncode({'projectId': 'project-a', 'node': 'a'}),
      );
      await store.writeDocument(
        projectId: 'project-b',
        documentJson: jsonEncode({'projectId': 'project-b', 'node': 'b'}),
      );
      await store.writeRecovery(
        projectId: 'project-a',
        recoveryJson: jsonEncode({'projectId': 'project-a', 'recovery': 'a'}),
      );
      await store.writeHistory(
        projectId: 'project-b',
        historyJson: jsonEncode({'projectId': 'project-b', 'history': 'b'}),
      );
      await store.writeCollaborationQueue(
        projectId: 'project-a',
        queueJson: jsonEncode([
          {'projectId': 'project-a', 'op': 'a'},
        ]),
      );

      expect(jsonDecode((await store.readDocument('project-a'))!), {
        'projectId': 'project-a',
        'node': 'a',
      });
      expect(jsonDecode((await store.readDocument('project-b'))!), {
        'projectId': 'project-b',
        'node': 'b',
      });
      expect(await store.readRecovery('project-b'), isNull);
      expect(await store.readHistory('project-a'), isNull);
      expect(jsonDecode((await store.readCollaborationQueue('project-a'))!), [
        {'projectId': 'project-a', 'op': 'a'},
      ]);
    },
  );

  test(
    'project snapshot writes document, recovery, viewport, and assets atomically',
    () async {
      final store = await openStore();
      addTearDown(store.close);

      await store.writeProjectSnapshot(
        projectId: 'project-snapshot',
        documentJson: jsonEncode({'kind': 'document'}),
        recoveryJson: jsonEncode({'kind': 'recovery'}),
        viewportJson: jsonEncode({'x': 12, 'y': 4, 'zoom': 1.5}),
        assetIndexJson: jsonEncode({
          'items': ['asset-a'],
        }),
      );

      expect(
        await store.readDocument('project-snapshot'),
        jsonEncode({'kind': 'document'}),
      );
      expect(
        await store.readRecovery('project-snapshot'),
        jsonEncode({'kind': 'recovery'}),
      );
      expect(
        await store.readViewport('project-snapshot'),
        jsonEncode({'x': 12, 'y': 4, 'zoom': 1.5}),
      );
      expect(
        await store.readAssetIndex('project-snapshot'),
        jsonEncode({
          'items': ['asset-a'],
        }),
      );

      await store.deleteRecord(
        projectId: 'project-snapshot',
        kind: DurableProjectRecordKind.viewport,
      );
      expect(await store.readViewport('project-snapshot'), isNull);
      expect(
        await store.readDocument('project-snapshot'),
        jsonEncode({'kind': 'document'}),
      );
    },
  );

  test('purges every durable record for one project only', () async {
    final store = await openStore();
    addTearDown(store.close);

    await store.writeProjectSnapshot(
      projectId: 'purge-me',
      documentJson: jsonEncode({'projectId': 'purge-me', 'kind': 'document'}),
      recoveryJson: jsonEncode({'projectId': 'purge-me', 'kind': 'recovery'}),
      viewportJson: jsonEncode({'projectId': 'purge-me'}),
      assetIndexJson: jsonEncode({'projectId': 'purge-me'}),
    );
    await store.writeHistory(
      projectId: 'purge-me',
      historyJson: jsonEncode([
        {'projectId': 'purge-me'},
      ]),
    );
    await store.writeAutoCheckpoint(
      projectId: 'purge-me',
      checkpointJson: jsonEncode([
        {'projectId': 'purge-me'},
      ]),
    );
    await store.saveAssetLibrary('purge-me', const []);
    await store.writeAssetQueue(
      projectId: 'purge-me',
      queueJson: jsonEncode({'projectId': 'purge-me'}),
    );
    await store.writeCollaborationQueue(
      projectId: 'purge-me',
      queueJson: jsonEncode({'projectId': 'purge-me', 'queue': 'default'}),
    );
    await store.writeCollaborationQueue(
      projectId: 'purge-me',
      accountId: 'account-a',
      generation: 2,
      queueJson: jsonEncode({'projectId': 'purge-me', 'queue': 'scoped'}),
    );
    await store.writeDocument(
      projectId: 'keep-me',
      documentJson: jsonEncode({'projectId': 'keep-me'}),
    );

    await store.purgeProject('purge-me');

    expect(await store.readDocument('purge-me'), isNull);
    expect(await store.readRecovery('purge-me'), isNull);
    expect(await store.readHistory('purge-me'), isNull);
    expect(await store.readAutoCheckpoint('purge-me'), isNull);
    expect(await store.readViewport('purge-me'), isNull);
    expect(await store.readAssetIndex('purge-me'), isNull);
    expect(await store.loadAssetLibrary('purge-me'), isEmpty);
    expect(await store.readAssetQueue('purge-me'), isNull);
    expect(await store.readCollaborationQueue('purge-me'), isNull);
    expect(
      await store.readCollaborationQueue(
        'purge-me',
        accountId: 'account-a',
        generation: 2,
      ),
      isNull,
    );
    expect(await store.readDocument('keep-me'), isNotNull);
  });

  test(
    'legacy migration keeps the legacy value and resumes after verification failure',
    () async {
      final store = await openStore();
      addTearDown(store.close);
      var legacy = jsonEncode({'projectId': 'project-a', 'version': 1});

      final blocked = await store.migrateLegacyRecord(
        migrationId: 'document-project-a-v1',
        projectId: 'project-a',
        kind: DurableProjectRecordKind.document,
        readLegacy: () async => legacy,
        verify: (_) => false,
      );

      expect(blocked, isFalse);
      expect(await store.readDocument('project-a'), isNull);
      expect(await store.getMigrationState('document-project-a-v1'), 'blocked');
      expect(legacy, jsonEncode({'projectId': 'project-a', 'version': 1}));

      final migrated = await store.migrateLegacyRecord(
        migrationId: 'document-project-a-v1',
        projectId: 'project-a',
        kind: DurableProjectRecordKind.document,
        readLegacy: () async => legacy,
      );

      expect(migrated, isTrue);
      expect(await store.readDocument('project-a'), legacy);
      expect(
        await store.getMigrationState('document-project-a-v1'),
        'complete',
      );
    },
  );

  test(
    'malformed durable payload remains readable for compatibility recovery',
    () async {
      final store = await openStore();
      addTearDown(store.close);

      await store.writeDocument(
        projectId: 'project-corrupt',
        documentJson: '{not-json',
      );

      final raw = await store.readDocument('project-corrupt');
      expect(raw, '{not-json');
      expect(() => jsonDecode(raw!), throwsFormatException);
    },
  );

  test(
    'CanvasDocument survives restart and falls back to its recovery record',
    () async {
      final first = await openStore();
      final document = CanvasDocument(
        projectId: 'project-document',
        nodes: const [],
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      await first.saveCanvasDocument(document);
      await first.close();

      final second = await openStore();
      addTearDown(second.close);
      expect(
        (await second.loadCanvasDocument('project-document'))?.projectId,
        'project-document',
      );

      await second.writeDocument(
        projectId: 'project-document',
        documentJson: '{corrupt',
      );
      expect(
        (await second.loadCanvasDocument('project-document'))?.projectId,
        'project-document',
      );
    },
  );

  test(
    'saveCanvasDocument keeps the prior validated document as recovery',
    () async {
      final store = await openStore();
      addTearDown(store.close);
      final first = CanvasDocument(
        projectId: 'project-recovery',
        metadata: const {'revision': 1},
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      final second = first.copyWith(
        metadata: const {'revision': 2},
        updatedAt: DateTime.utc(2026, 1, 3),
      );

      await store.saveCanvasDocument(first);
      await store.saveCanvasDocument(second);
      await store.writeDocument(
        projectId: 'project-recovery',
        documentJson: '{corrupt',
      );

      final recovered = await store.loadCanvasDocument('project-recovery');
      expect(recovered?.metadata['revision'], 1);
    },
  );

  test('rejects a document payload embedded for another project', () async {
    final store = await openStore();
    addTearDown(store.close);

    expect(
      () => store.writeDocument(
        projectId: 'project-a',
        documentJson: jsonEncode(
          CanvasDocument(
            projectId: 'project-b',
            updatedAt: DateTime.utc(2026, 1, 2),
          ).toJson(),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await store.readDocument('project-a'), isNull);
  });

  test('rejects history and checkpoint records for another project', () async {
    final store = await openStore();
    addTearDown(store.close);
    final record = DocumentSnapshotRecord(
      id: 'snapshot-b',
      description: 'wrong project',
      timestamp: DateTime.utc(2026, 1, 2),
      document: CanvasDocument(
        projectId: 'project-b',
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    );

    await expectLater(
      store.saveHistory('project-a', [record]),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      store.saveAutoCheckpoints('project-a', [record]),
      throwsA(isA<StateError>()),
    );
  });

  test('keeps asset catalog items scoped to their project', () async {
    final store = await openStore();
    addTearDown(store.close);
    final itemA = AssetLibraryItem(
      id: 'asset-a',
      scopeId: 'project-a',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Project A asset',
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    final itemB = AssetLibraryItem(
      id: 'asset-b',
      scopeId: 'project-b',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Project B asset',
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

    await store.saveAssetLibrary('project-a', [itemA, itemB]);

    expect((await store.loadAssetLibrary('project-a')).map((item) => item.id), [
      'asset-a',
    ]);
    expect(await store.loadAssetLibrary('project-b'), isEmpty);
  });

  test('rejects an asset catalog item with another project scope', () async {
    final store = await openStore();
    addTearDown(store.close);
    final item = AssetLibraryItem(
      id: 'asset-b',
      scopeId: 'project-b',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Project B asset',
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

    await store.saveAssetLibrary('project-a', [item]);
    expect(await store.loadAssetLibrary('project-a'), isEmpty);
  });

  test('asset library persistence keeps only matching typed items', () async {
    final store = await openStore();
    addTearDown(store.close);
    final itemA = AssetLibraryItem(
      id: 'asset-a',
      scopeId: 'project-a',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Project A asset',
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    final itemB = itemA.copyWith(id: 'asset-b', scopeId: 'project-b');

    await store.saveAssetLibrary('project-a', [itemA, itemB]);
    expect((await store.loadAssetLibrary('project-a')).map((item) => item.id), [
      'asset-a',
    ]);
  });

  test(
    'rejects a mismatched recovery payload before it is persisted',
    () async {
      final store = await openStore();
      addTearDown(store.close);

      expect(
        () => store.writeRecovery(
          projectId: 'project-a',
          recoveryJson: jsonEncode(
            CanvasDocument(
              projectId: 'project-b',
              updatedAt: DateTime.utc(2026, 1, 2),
            ).toJson(),
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'keeps collaboration queues isolated by account and lifecycle generation',
    () async {
      final store = await openStore();
      addTearDown(store.close);
      final accountAQueue = jsonEncode([
        {'projectId': 'project-a', 'op': 'account-a'},
      ]);
      final accountBQueue = jsonEncode([
        {'projectId': 'project-a', 'op': 'account-b'},
      ]);

      await store.writeCollaborationQueue(
        projectId: 'project-a',
        queueJson: accountAQueue,
        accountId: 'account-a',
        generation: 1,
      );
      await store.writeCollaborationQueue(
        projectId: 'project-a',
        queueJson: accountBQueue,
        accountId: 'account-b',
        generation: 1,
      );

      expect(
        await store.readCollaborationQueue(
          'project-a',
          accountId: 'account-a',
          generation: 1,
        ),
        accountAQueue,
      );
      expect(
        await store.readCollaborationQueue(
          'project-a',
          accountId: 'account-b',
          generation: 1,
        ),
        accountBQueue,
      );

      await store.clearCollaborationQueue(
        'project-a',
        accountId: 'account-a',
        generation: 1,
      );

      expect(
        await store.readCollaborationQueue(
          'project-a',
          accountId: 'account-a',
          generation: 1,
        ),
        isNull,
      );
      expect(
        await store.readCollaborationQueue(
          'project-a',
          accountId: 'account-b',
          generation: 1,
        ),
        accountBQueue,
      );
    },
  );

  test('an old lifecycle clear cannot erase a newer queue', () async {
    final store = await openStore();
    addTearDown(store.close);
    final oldQueue = jsonEncode([
      {'projectId': 'project-a', 'op': 'old'},
    ]);
    final currentQueue = jsonEncode([
      {'projectId': 'project-a', 'op': 'current'},
    ]);

    await store.writeCollaborationQueue(
      projectId: 'project-a',
      queueJson: oldQueue,
      accountId: 'account-a',
      generation: 1,
    );
    await store.writeCollaborationQueue(
      projectId: 'project-a',
      queueJson: currentQueue,
      accountId: 'account-a',
      generation: 2,
    );
    await store.clearCollaborationQueue(
      'project-a',
      accountId: 'account-a',
      generation: 1,
    );

    expect(
      await store.readCollaborationQueue(
        'project-a',
        accountId: 'account-a',
        generation: 2,
      ),
      currentQueue,
    );
  });
}
