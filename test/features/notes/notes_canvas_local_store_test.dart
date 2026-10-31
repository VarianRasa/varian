import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_local_database.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';

void main() {
  late NotesLocalDatabase database;
  late NotesLocalStore store;
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
  const accountId = 'account-canvas-a';
  const boardId = '30000000-0000-4000-8000-000000000001';
  const operationId = '30000000-0000-4000-8000-000000000002';

  setUp(() {
    database = NotesLocalDatabase(NativeDatabase.memory());
    store = NotesLocalStore(
      database: database,
      storageAvailability: () async => true,
    );
  });

  tearDown(() => database.close());

  test('encrypts board snapshots and outbox with account-board AAD', () async {
    const snapshot = '{"schema_version":1,"cards":[]}';
    const operation = '{"type":"card_move","dx":5}';
    await store.saveCanvasSnapshot(
      accountId: accountId,
      boardId: boardId,
      snapshot: snapshot,
      key: key,
    );
    await store.enqueueCanvasOperation(
      accountId: accountId,
      boardId: boardId,
      operationId: operationId,
      payload: operation,
      key: key,
    );

    expect(
      await store.readCanvasSnapshot(
        accountId: accountId,
        boardId: boardId,
        key: key,
      ),
      snapshot,
    );
    expect(
      await store.readCanvasSnapshot(
        accountId: 'account-canvas-b',
        boardId: boardId,
        key: key,
      ),
      isNull,
    );
    expect(
      await store.readCanvasOutbox(
        accountId: accountId,
        boardId: boardId,
        key: key,
      ),
      [operation],
    );
    expect(
      await store.pendingCanvasOutboxOperationIds(
        accountId: accountId,
        boardId: boardId,
      ),
      [operationId],
    );

    final snapshotRows = await database
        .customSelect('SELECT ciphertext FROM notes_canvas_cache')
        .get();
    final outboxRows = await database
        .customSelect('SELECT ciphertext FROM notes_canvas_outbox')
        .get();
    expect(
      utf8.decode(
        snapshotRows.single.data['ciphertext'] as Uint8List,
        allowMalformed: true,
      ),
      isNot(contains(snapshot)),
    );
    expect(
      utf8.decode(
        outboxRows.single.data['ciphertext'] as Uint8List,
        allowMalformed: true,
      ),
      isNot(contains(operation)),
    );

    await store.removeCanvasOutboxOperation(
      accountId: accountId,
      boardId: boardId,
      operationId: operationId,
    );
    expect(
      await store.pendingCanvasOutboxOperationIds(
        accountId: accountId,
        boardId: boardId,
      ),
      isEmpty,
    );
  });

  test('replays queued operations in insertion order', () async {
    const operationIds = [
      '30000000-0000-4000-8000-000000000013',
      '30000000-0000-4000-8000-000000000012',
      '30000000-0000-4000-8000-000000000011',
    ];
    for (final operationId in operationIds) {
      await store.enqueueCanvasOperation(
        accountId: accountId,
        boardId: boardId,
        operationId: operationId,
        payload: operationId,
        key: key,
      );
    }
    await database.customStatement(
      'UPDATE notes_canvas_outbox SET created_at=1',
    );

    expect(
      await store.pendingCanvasOutboxOperationIds(
        accountId: accountId,
        boardId: boardId,
      ),
      operationIds,
    );
    expect(
      await store.readCanvasOutbox(
        accountId: accountId,
        boardId: boardId,
        key: key,
      ),
      operationIds,
    );
  });

  test('keeps one persistent replica ID per account', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final replicaId = await store.loadOrCreateCanvasReplicaId(
      accountId: accountId,
    );
    final reopenedStore = NotesLocalStore(database: database);

    expect(replicaId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(
      await reopenedStore.loadOrCreateCanvasReplicaId(accountId: accountId),
      replicaId,
    );
    expect(
      await reopenedStore.loadOrCreateCanvasReplicaId(
        accountId: 'account-canvas-b',
      ),
      isNot(replicaId),
    );
  });

  test(
    'does not persist board data when secure storage is unavailable',
    () async {
      final unavailable = NotesLocalStore(
        database: database,
        storageAvailability: () async => false,
      );

      await unavailable.saveCanvasSnapshot(
        accountId: accountId,
        boardId: boardId,
        snapshot: 'must not persist',
        key: key,
      );

      expect(unavailable.isEnabled, isFalse);
      expect(
        await database.customSelect('SELECT * FROM notes_canvas_cache').get(),
        isEmpty,
      );
    },
  );
}
