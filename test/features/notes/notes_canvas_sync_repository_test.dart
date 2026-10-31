import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_canvas_repository.dart';
import 'package:varian/features/notes/data/notes_canvas_sync_repository.dart';
import 'package:varian/features/notes/data/notes_canvas_sync_transport.dart';
import 'package:varian/features/notes/data/notes_local_database.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';
import 'package:varian/features/notes/domain/notes_canvas_board.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';

void main() {
  const accountId = 'account-sync-a';
  const boardId = '60000000-0000-4000-8000-000000000001';
  const cardId = '60000000-0000-4000-8000-000000000002';
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index));

  late NotesLocalDatabase database;
  late NotesLocalStore store;

  setUp(() {
    database = NotesLocalDatabase(NativeDatabase.memory());
    store = NotesLocalStore(
      database: database,
      storageAvailability: () async => true,
    );
  });

  tearDown(() => database.close());

  (NotesCanvasDocument, NotesCanvasOperation) localDocument() {
    final document = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );
    final operation = document.createCard(
      replicaId: 'replica-a',
      card: const NotesCanvasTextCard(
        id: cardId,
        markdown: '',
        x: 10,
        y: 20,
        width: 300,
        height: 180,
      ),
    );
    return (document, operation);
  }

  test(
    'replays queued operations and removes ciphertext only after snapshot',
    () async {
      final (document, operation) = localDocument();
      final transport = _FakeCanvasTransport(boardId);
      final sync = NotesCanvasSyncRepository(
        store: store,
        transport: transport,
        keyForAccount: (_) async => key,
        currentAccountId: () async => accountId,
      );
      await sync.queueOperation(
        accountId: accountId,
        boardId: boardId,
        document: document,
        operation: operation,
      );

      final board = await sync.synchronizeBoard(
        accountId: accountId,
        boardId: boardId,
      );

      expect(board.state.cards.single.id, cardId);
      expect(board.snapshotServerSequence, 1);
      expect(transport.materializedRevisions, 1);
      expect(
        await store.pendingCanvasOutboxOperationIds(
          accountId: accountId,
          boardId: boardId,
        ),
        isEmpty,
      );
      expect(
        await sync.readCachedDocument(accountId: accountId, boardId: boardId),
        isNotNull,
      );
    },
  );

  test('keeps encrypted queued edits when snapshot CAS conflicts', () async {
    final (document, operation) = localDocument();
    final transport = _FakeCanvasTransport(boardId)
      ..conflictOnMaterialize = true;
    final sync = NotesCanvasSyncRepository(
      store: store,
      transport: transport,
      keyForAccount: (_) async => key,
      currentAccountId: () async => accountId,
    );
    await sync.queueOperation(
      accountId: accountId,
      boardId: boardId,
      document: document,
      operation: operation,
    );

    await expectLater(
      sync.synchronizeBoard(accountId: accountId, boardId: boardId),
      throwsA(isA<NotesCanvasRevisionConflictException>()),
    );

    expect(
      await store.pendingCanvasOutboxOperationIds(
        accountId: accountId,
        boardId: boardId,
      ),
      [operation.opId],
    );
    expect(
      await store.readCanvasOutbox(
        accountId: accountId,
        boardId: boardId,
        key: key,
      ),
      [operation.encode()],
    );
  });
}

class _FakeCanvasTransport implements NotesCanvasSyncTransport {
  _FakeCanvasTransport(this.boardId) {
    final document = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );
    board = NotesCanvasBoard(
      id: boardId,
      ownerUserId: 'account-sync-a',
      createdBy: 'account-sync-a',
      title: 'Board',
      state: document.boardState,
      crdtSnapshot: document.snapshotState(),
      versionVector: document.versionVector,
      revision: 1,
      snapshotServerSequence: 0,
      createdAt: DateTime.utc(2026, 10, 21),
      updatedAt: DateTime.utc(2026, 10, 21),
    );
  }

  final String boardId;
  late NotesCanvasBoard board;
  final List<NotesCanvasOperationRecord> operations = [];
  bool conflictOnMaterialize = false;
  int materializedRevisions = 0;

  @override
  Future<NotesCanvasBoard> getBoard({
    required String boardId,
    required String expectedAccountId,
  }) async => board;

  @override
  Future<int> appendOperation({
    required String boardId,
    required NotesCanvasOperation operation,
    required String expectedAccountId,
  }) async {
    final existing = operations.where(
      (record) => record.operation.opId == operation.opId,
    );
    if (existing.isNotEmpty) return existing.single.serverSequence;
    final sequence = operations.length + 1;
    operations.add(
      NotesCanvasOperationRecord(
        serverSequence: sequence,
        operation: operation,
      ),
    );
    return sequence;
  }

  @override
  Future<List<NotesCanvasOperationRecord>> listOperations({
    required String boardId,
    required int afterSequence,
    required String expectedAccountId,
    int limit = 500,
  }) async => operations
      .where((record) => record.serverSequence > afterSequence)
      .take(limit)
      .toList(growable: false);

  @override
  Future<NotesCanvasBoard> materializeSnapshot({
    required String boardId,
    required int expectedRevision,
    required int throughServerSequence,
    required NotesCanvasDocument document,
    required String expectedAccountId,
  }) async {
    materializedRevisions++;
    if (conflictOnMaterialize) {
      throw const NotesCanvasRevisionConflictException();
    }
    board = NotesCanvasBoard(
      id: board.id,
      ownerUserId: board.ownerUserId,
      createdBy: board.createdBy,
      projectId: board.projectId,
      title: board.title,
      state: document.boardState,
      crdtSnapshot: document.snapshotState(),
      versionVector: document.versionVector,
      revision: board.revision + 1,
      snapshotServerSequence: throughServerSequence,
      createdAt: board.createdAt,
      updatedAt: DateTime.utc(2026, 10, 21, 1),
    );
    return board;
  }
}
