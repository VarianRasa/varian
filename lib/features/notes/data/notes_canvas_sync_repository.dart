import 'dart:convert';
import 'dart:typed_data';

import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/notes/data/notes_canvas_repository.dart';
import 'package:varian/features/notes/data/notes_canvas_sync_transport.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';
import 'package:varian/features/notes/domain/notes_canvas_board.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';

class NotesCanvasSyncRepository {
  NotesCanvasSyncRepository({
    required NotesLocalStore store,
    required NotesCanvasSyncTransport transport,
    required Future<Uint8List?> Function(String accountId) keyForAccount,
    required Future<String?> Function() currentAccountId,
    this.maxOperationsPerRun = 500,
  }) : _store = store,
       _transport = transport,
       _keyForAccount = keyForAccount,
       _currentAccountId = currentAccountId;

  final NotesLocalStore _store;
  final NotesCanvasSyncTransport _transport;
  final Future<Uint8List?> Function(String accountId) _keyForAccount;
  final Future<String?> Function() _currentAccountId;
  final int maxOperationsPerRun;
  final Map<(String, String), Future<NotesCanvasBoard>> _running = {};
  int _generation = 0;

  void accountChanged() {
    _generation++;
  }

  Future<void> queueOperation({
    required String accountId,
    required String boardId,
    required NotesCanvasDocument document,
    required NotesCanvasOperation operation,
  }) async {
    final generation = _generation;
    if (operation.boardId != boardId || document.boardId != boardId) {
      throw const FormatException('Canvas operation targets another board.');
    }
    operation.validate();
    final key = await _keyForAccount(accountId);
    if (key == null ||
        key.length != 32 ||
        !(await _isCurrent(accountId, generation))) {
      throw StateError('Encrypted Notes storage is unavailable.');
    }
    await _store.enqueueCanvasOperation(
      accountId: accountId,
      boardId: boardId,
      operationId: operation.opId,
      payload: operation.encode(),
      key: key,
    );
    if (!_store.isEnabled || !(await _isCurrent(accountId, generation))) {
      throw StateError('Encrypted Notes storage is unavailable.');
    }
    await _store.saveCanvasSnapshot(
      accountId: accountId,
      boardId: boardId,
      snapshot: jsonEncode(document.snapshotState()),
      key: key,
    );
    if (!_store.isEnabled || !(await _isCurrent(accountId, generation))) {
      throw StateError('Encrypted Notes storage is unavailable.');
    }
  }

  Future<NotesCanvasDocument?> readCachedDocument({
    required String accountId,
    required String boardId,
  }) async {
    final generation = _generation;
    final key = await _keyForAccount(accountId);
    if (key == null ||
        key.length != 32 ||
        !(await _isCurrent(accountId, generation))) {
      return null;
    }
    final encoded = await _store.readCanvasSnapshot(
      accountId: accountId,
      boardId: boardId,
      key: key,
    );
    if (encoded == null || !(await _isCurrent(accountId, generation))) {
      return null;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      final document = NotesCanvasDocument.fromSnapshot(
        Map<String, dynamic>.from(decoded),
      );
      return document.boardId == boardId ? document : null;
    } catch (_) {
      return null;
    }
  }

  Future<NotesCanvasBoard> synchronizeBoard({
    required String accountId,
    required String boardId,
  }) {
    final key = (accountId, boardId);
    final existing = _running[key];
    if (existing != null) return existing;
    final generation = _generation;
    final run = _synchronizeBoard(accountId, boardId, generation);
    _running[key] = run;
    return run.whenComplete(() {
      if (identical(_running[key], run)) _running.remove(key);
    });
  }

  Future<NotesCanvasBoard> _synchronizeBoard(
    String accountId,
    String boardId,
    int generation,
  ) async {
    if (accountId.isEmpty || accountId.length > 256) {
      throw ArgumentError.value(accountId, 'accountId');
    }
    final key = await _keyForAccount(accountId);
    if (key == null ||
        key.length != 32 ||
        !(await _isCurrent(accountId, generation))) {
      throw StateError('Encrypted Notes storage is unavailable.');
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      if (!(await _isCurrent(accountId, generation))) {
        throw StateError('The signed-in account changed during this action.');
      }
      final board = await _transport.getBoard(
        boardId: boardId,
        expectedAccountId: accountId,
      );
      final encodedQueue = await _store.readCanvasOutbox(
        accountId: accountId,
        boardId: boardId,
        key: key,
        limit: maxOperationsPerRun,
      );
      final acknowledged = <NotesCanvasOperation>[];
      for (final payload in encodedQueue) {
        if (!(await _isCurrent(accountId, generation))) break;
        final decoded = jsonDecode(payload);
        if (decoded is! Map) continue;
        final operation = NotesCanvasOperation.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (operation.boardId != boardId) {
          throw const FormatException(
            'Queued Canvas operation has the wrong board ID.',
          );
        }
        await _transport.appendOperation(
          boardId: boardId,
          operation: operation,
          expectedAccountId: accountId,
        );
        if (!(await _isCurrent(accountId, generation))) break;
        acknowledged.add(operation);
      }
      if (!(await _isCurrent(accountId, generation))) {
        throw StateError('The signed-in account changed during this action.');
      }

      final document = NotesCanvasDocument.fromSnapshot(board.crdtSnapshot);
      var throughSequence = board.snapshotServerSequence;
      while (true) {
        final records = await _transport.listOperations(
          boardId: boardId,
          afterSequence: throughSequence,
          expectedAccountId: accountId,
          limit: 1000,
        );
        if (!(await _isCurrent(accountId, generation))) {
          throw StateError('The signed-in account changed during this action.');
        }
        for (final record in records) {
          final status = document.applyRemoteOperation(record.operation);
          if (status == CrdtApplyStatus.rejected) {
            throw StateError('A Canvas operation could not be replayed.');
          }
          throughSequence = record.serverSequence;
        }
        if (records.length < 1000) break;
      }
      if (document.pendingOperationCount != 0) {
        throw StateError(
          'Canvas operations are waiting for causal dependencies.',
        );
      }

      final acknowledgedById = {
        for (final item in acknowledged) item.opId: item,
      };
      final allAcknowledgedInSnapshot = acknowledged.every(
        (operation) =>
            document.versionVector[operation.replicaId] >=
            operation.replicaCounter,
      );
      if (!allAcknowledgedInSnapshot) {
        throw StateError('A queued Canvas operation was not materialized.');
      }

      NotesCanvasBoard latest = board;
      if (throughSequence > board.snapshotServerSequence) {
        try {
          latest = await _transport.materializeSnapshot(
            boardId: boardId,
            expectedRevision: board.revision,
            throughServerSequence: throughSequence,
            document: document,
            expectedAccountId: accountId,
          );
        } on NotesCanvasRevisionConflictException {
          if (attempt == 2) rethrow;
          continue;
        }
      }
      if (!(await _isCurrent(accountId, generation))) {
        throw StateError('The signed-in account changed during this action.');
      }

      await _store.saveCanvasSnapshot(
        accountId: accountId,
        boardId: boardId,
        snapshot: jsonEncode(document.snapshotState()),
        key: key,
      );
      if (!_store.isEnabled) {
        throw StateError('Encrypted Notes storage is unavailable.');
      }
      for (final operation in acknowledgedById.values) {
        if (!(await _isCurrent(accountId, generation))) {
          throw StateError('The signed-in account changed during this action.');
        }
        await _store.removeCanvasOutboxOperation(
          accountId: accountId,
          boardId: boardId,
          operationId: operation.opId,
        );
      }
      return latest;
    }
    throw const NotesCanvasRevisionConflictException();
  }

  Future<bool> _isCurrent(String accountId, int generation) async =>
      generation == _generation && await _currentAccountId() == accountId;
}
