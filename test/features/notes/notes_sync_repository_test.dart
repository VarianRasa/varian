import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_local_database.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';
import 'package:varian/features/notes/data/notes_sync_repository.dart';

class _Transport implements NotesSyncTransport {
  final List<String> replayed = [];
  bool permitted = true;
  bool failPermissionCheck = false;
  bool failReplay = false;
  String? replayError;
  Future<void> Function()? onReplay;

  @override
  Future<bool> canReplay(
    String accountId,
    Map<String, dynamic> operation,
  ) async {
    if (failPermissionCheck) throw StateError('401 Unauthorized');
    return permitted;
  }

  @override
  Future<void> replay(String accountId, Map<String, dynamic> operation) async {
    replayed.add(operation['opId'] as String);
    await onReplay?.call();
    if (failReplay) throw StateError('revision conflict');
    if (replayError != null) throw StateError(replayError!);
  }
}

void main() {
  late NotesLocalDatabase database;
  late NotesLocalStore store;
  late _Transport transport;
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  var currentAccount = 'account-a';
  var keyAvailable = true;

  setUp(() {
    database = NotesLocalDatabase(NativeDatabase.memory());
    store = NotesLocalStore(
      database: database,
      storageAvailability: () async => true,
    );
    transport = _Transport();
    currentAccount = 'account-a';
    keyAvailable = true;
  });

  tearDown(() => database.close());

  NotesSyncRepository createRepository() => NotesSyncRepository(
    store: store,
    transport: transport,
    keyForAccount: (accountId) async =>
        accountId == currentAccount && keyAvailable ? key : null,
    currentAccountId: () async => currentAccount,
    maxOperationsPerRun: 20,
  );

  test(
    'replays authorized encrypted operations and removes acknowledged IDs',
    () async {
      final repository = createRepository();
      final operation = {
        'noteId': 'note-1',
        'opId': 'note-1:replica:1',
        'dot': {'actorId': 'replica', 'counter': 1},
      };
      await repository.enqueue(
        accountId: 'account-a',
        operation: operation,
        key: key,
      );

      expect(await repository.syncAccount('account-a'), 1);
      expect(transport.replayed, ['note-1:replica:1']);
      expect(await store.readOutbox(accountId: 'account-a', key: key), isEmpty);
    },
  );

  test(
    'retains encrypted draft when replay hits a revision conflict',
    () async {
      final repository = createRepository();
      const operationId = 'note-conflict:mutation:4:update';
      await repository.enqueue(
        accountId: 'account-a',
        operation: {
          'kind': 'note_mutation',
          'action': 'update',
          'noteId': 'note-conflict',
          'opId': operationId,
          'title': 'local draft',
          'markdownContent': 'private conflict draft',
        },
        key: key,
      );
      transport.failReplay = true;

      expect(await repository.syncAccount('account-a'), 0);

      final retained = await store.readOutbox(accountId: 'account-a', key: key);
      expect(retained, hasLength(1));
      expect(
        jsonDecode(retained.single)['markdownContent'],
        'private conflict draft',
      );
      final ciphertext =
          (await database
                      .customSelect('SELECT ciphertext FROM notes_outbox')
                      .get())
                  .single
                  .data['ciphertext']
              as Uint8List;
      expect(
        utf8.decode(ciphertext, allowMalformed: true),
        isNot(contains('private conflict draft')),
      );
    },
  );

  test(
    'retains entries when permission is denied and pauses revoked project',
    () async {
      final repository = createRepository();
      final operation = {
        'noteId': 'note-1',
        'opId': 'note-1:replica:2',
        'projectId': 'project-1',
      };
      await repository.enqueue(
        accountId: 'account-a',
        operation: operation,
        key: key,
      );
      transport.permitted = false;

      expect(await repository.syncAccount('account-a'), 0);
      expect(
        await store.readOutbox(accountId: 'account-a', key: key),
        hasLength(1),
      );
      expect(await repository.pausedNoteIds('account-a'), {'note-1'});
      transport.permitted = true;
      expect(await repository.syncAccount('account-a'), 0);
      expect(transport.replayed, isEmpty);
    },
  );

  test('persists encrypted account-scoped vector checkpoints', () async {
    final repository = createRepository();
    final vector = {'replica-a': 5, 'replica-b': 2};
    await repository.saveVectorCheckpoint(
      accountId: 'account-a',
      noteId: 'note-1',
      versionVector: vector,
      key: key,
    );

    expect(
      await repository.loadVectorCheckpoint(
        accountId: 'account-a',
        noteId: 'note-1',
        key: key,
      ),
      vector,
    );
    expect(
      await repository.loadVectorCheckpoint(
        accountId: 'account-b',
        noteId: 'note-1',
        key: key,
      ),
      isNull,
    );
  });

  test('does not replay another account queue', () async {
    final repository = createRepository();
    final operation = {'noteId': 'note-1', 'opId': 'note-1:replica:3'};
    await repository.enqueue(
      accountId: 'account-a',
      operation: operation,
      key: key,
    );
    currentAccount = 'account-b';

    expect(await repository.syncAccount('account-a'), 0);
    expect(transport.replayed, isEmpty);
    expect(
      utf8.decode(
        (await database
                    .customSelect('SELECT ciphertext FROM notes_outbox')
                    .get())
                .single
                .data['ciphertext']
            as Uint8List,
        allowMalformed: true,
      ),
      isNot(contains('note-1:replica:3')),
    );
  });

  test('keeps encrypted drafts queued while the local key is locked', () async {
    final repository = createRepository();
    await repository.enqueue(
      accountId: 'account-a',
      operation: {
        'noteId': 'note-locked',
        'opId': 'note-locked:mutation:1',
        'markdownContent': 'locked private draft',
      },
      key: key,
    );
    keyAvailable = false;

    expect(await repository.syncAccount('account-a'), 0);
    expect(transport.replayed, isEmpty);
    expect(await repository.pendingNoteIds('account-a'), {'note-locked'});
    final ciphertext =
        (await database
                    .customSelect('SELECT ciphertext FROM notes_outbox')
                    .get())
                .single
                .data['ciphertext']
            as Uint8List;
    expect(
      utf8.decode(ciphertext, allowMalformed: true),
      isNot(contains('locked private draft')),
    );
  });

  test('keeps encrypted drafts queued when authentication expires', () async {
    final repository = createRepository();
    await repository.enqueue(
      accountId: 'account-a',
      operation: {'noteId': 'note-expired', 'opId': 'note-expired:mutation:1'},
      key: key,
    );
    transport.failPermissionCheck = true;

    expect(await repository.syncAccount('account-a'), 0);
    expect(transport.replayed, isEmpty);
    expect(await repository.pendingNoteIds('account-a'), {'note-expired'});
  });

  test('keeps encrypted drafts queued after server storage failure', () async {
    final repository = createRepository();
    await repository.enqueue(
      accountId: 'account-a',
      operation: {
        'noteId': 'note-storage',
        'opId': 'note-storage:mutation:1',
        'markdownContent': 'draft after server storage failure',
      },
      key: key,
    );
    transport.replayError = '503 server storage unavailable';

    expect(await repository.syncAccount('account-a'), 0);
    expect(await repository.pendingNoteIds('account-a'), {'note-storage'});
    expect(
      jsonDecode(
        (await store.readOutbox(accountId: 'account-a', key: key)).single,
      )['markdownContent'],
      'draft after server storage failure',
    );
  });

  test(
    'does not acknowledge a replay after the account changes mid-flight',
    () async {
      final repository = createRepository();
      final replayStarted = Completer<void>();
      final finishReplay = Completer<void>();
      transport.onReplay = () async {
        if (!replayStarted.isCompleted) replayStarted.complete();
        await finishReplay.future;
      };
      await repository.enqueue(
        accountId: 'account-a',
        operation: {'noteId': 'note-switch', 'opId': 'note-switch:mutation:1'},
        key: key,
      );

      final syncing = repository.syncAccount('account-a');
      await replayStarted.future;
      repository.accountChanged();
      currentAccount = 'account-b';
      finishReplay.complete();

      expect(await syncing, 0);
      expect(await repository.pendingNoteIds('account-a'), {'note-switch'});
    },
  );
}
