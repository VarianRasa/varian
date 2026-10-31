import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/notes/data/notes_local_database.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';
import 'package:varian/features/notes/data/notes_sync_repository.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/note_crdt_document.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/state/notes_offline_provider.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _authenticate(SupabaseClient client, String accountId) async {
  final expires =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final token =
      '${_encodePart({'alg': 'HS256'})}.${_encodePart({'sub': accountId, 'exp': expires})}.signature';
  client.auth.stopAutoRefresh();
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expires,
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': {
        'id': accountId,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-01T00:00:00Z',
      },
    }),
  );
}

class _BlockedOfflineTransport implements NotesSyncTransport {
  @override
  Future<bool> canReplay(
    String accountId,
    Map<String, dynamic> operation,
  ) async => false;

  @override
  Future<void> replay(String accountId, Map<String, dynamic> operation) async {}
}

class _OfflineTransport implements NotesSyncTransport {
  @override
  Future<bool> canReplay(
    String accountId,
    Map<String, dynamic> operation,
  ) async => true;

  @override
  Future<void> replay(String accountId, Map<String, dynamic> operation) async {}
}

void main() {
  test('queues private-note creation when cloud creation fails', () async {
    const accountId = 'account-create';
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '{"message":"offline"}',
          503,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await _authenticate(client, accountId);
    final database = NotesLocalDatabase(NativeDatabase.memory());
    final store = NotesLocalStore(
      database: database,
      storageAvailability: () async => true,
    );
    final sync = NotesSyncRepository(
      store: store,
      transport: _OfflineTransport(),
      keyForAccount: (_) async => key,
      currentAccountId: () async => accountId,
    );
    final notifier = WorkspaceNotesNotifier(
      client,
      WorkspaceNoteRepository(client),
      offlineService: NotesOfflineService(
        store: store,
        sync: sync,
        keyForAccount: (_) async => key,
      ),
    );
    addTearDown(notifier.dispose);
    addTearDown(client.dispose);
    addTearDown(database.close);

    final note = await notifier.createNote();

    expect(note, isNotNull);
    expect(notifier.state.notes, contains(note));
    expect(notifier.state.queuedNoteIds, contains(note!.id));
    expect(
      await store.readNote(accountId: accountId, noteId: note.id, key: key),
      '',
    );
    final entry =
        jsonDecode(
              (await store.readOutbox(accountId: accountId, key: key)).single,
            )
            as Map<String, dynamic>;
    expect(entry['kind'], 'note_mutation');
    expect(entry['action'], 'create');
    expect(entry['ownerUserId'], accountId);
  });

  test(
    'keeps a note unchanged when encrypted storage is unavailable',
    () async {
      const accountId = 'account-a';
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient(
          (request) async => http.Response(
            '{"message":"offline"}',
            503,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await _authenticate(client, accountId);
      final database = NotesLocalDatabase(NativeDatabase.memory());
      final store = NotesLocalStore(
        database: database,
        storageAvailability: () async => false,
      );
      final sync = NotesSyncRepository(
        store: store,
        transport: _OfflineTransport(),
        keyForAccount: (_) async => key,
        currentAccountId: () async => accountId,
      );
      final notifier = WorkspaceNotesNotifier(
        client,
        WorkspaceNoteRepository(client),
        offlineService: NotesOfflineService(
          store: store,
          sync: sync,
          keyForAccount: (_) async => key,
        ),
      );
      addTearDown(notifier.dispose);
      addTearDown(client.dispose);
      addTearDown(database.close);
      final note = WorkspaceNote(
        id: 'note-no-storage',
        ownerUserId: accountId,
        title: 'Keep this note',
        markdownContent: 'unsynced draft',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      notifier.state = notifier.state.copyWith(notes: [note]);

      expect(await notifier.deleteNote(note), isFalse);
      expect(store.isEnabled, isFalse);
      expect(notifier.state.notes, [note]);
      expect(notifier.state.trashNotes, isEmpty);
      expect(notifier.state.queuedNoteIds, isEmpty);
      expect(
        workspaceNotesFailureMessage(
          notifier.state.error,
          accountId: accountId,
        ),
        contains('device storage'),
      );
    },
  );

  test(
    'restores queued note indicators from encrypted outbox on startup',
    () async {
      const accountId = 'account-a';
      const noteId = 'note-pending';
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient(
          (request) async => http.Response(
            '[]',
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-0/0',
            },
          ),
        ),
      );
      await _authenticate(client, accountId);
      final database = NotesLocalDatabase(NativeDatabase.memory());
      final store = NotesLocalStore(
        database: database,
        storageAvailability: () async => true,
      );
      final sync = NotesSyncRepository(
        store: store,
        transport: _BlockedOfflineTransport(),
        keyForAccount: (_) async => key,
        currentAccountId: () async => accountId,
      );
      await sync.enqueue(
        accountId: accountId,
        key: key,
        operation: {
          'kind': 'note_mutation',
          'action': 'delete',
          'noteId': noteId,
          'opId': '$noteId:mutation:1:delete',
          'projectId': null,
          'expectedRevision': 1,
        },
      );
      final notifier = WorkspaceNotesNotifier(
        client,
        WorkspaceNoteRepository(client),
        offlineService: NotesOfflineService(
          store: store,
          sync: sync,
          keyForAccount: (_) async => key,
        ),
      );
      addTearDown(notifier.dispose);
      addTearDown(client.dispose);
      addTearDown(database.close);

      for (
        var attempt = 0;
        attempt < 20 && !notifier.state.queuedNoteIds.contains(noteId);
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(notifier.state.queuedNoteIds, contains(noteId));
    },
  );

  test(
    'queues private-note delete and restore across offline retries',
    () async {
      const accountId = 'account-a';
      const noteId = 'note-delete';
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/workspace_notes') &&
              request.method == 'PATCH') {
            return http.Response(
              '{"message":"offline"}',
              503,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-0/0',
            },
          );
        }),
      );
      await _authenticate(client, accountId);
      final database = NotesLocalDatabase(NativeDatabase.memory());
      final store = NotesLocalStore(
        database: database,
        storageAvailability: () async => true,
      );
      final sync = NotesSyncRepository(
        store: store,
        transport: _OfflineTransport(),
        keyForAccount: (_) async => key,
        currentAccountId: () async => accountId,
      );
      final notifier = WorkspaceNotesNotifier(
        client,
        WorkspaceNoteRepository(client),
        offlineService: NotesOfflineService(
          store: store,
          sync: sync,
          keyForAccount: (_) async => key,
        ),
      );
      addTearDown(notifier.dispose);
      addTearDown(client.dispose);
      addTearDown(database.close);

      final note = WorkspaceNote(
        id: noteId,
        ownerUserId: accountId,
        title: 'Offline note',
        markdownContent: 'private draft',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        revision: 1,
      );
      expect(await notifier.deleteNote(note), isTrue);
      expect(notifier.state.trashNotes.single.deletedAt, isNotNull);
      expect(notifier.state.queuedNoteIds, contains(noteId));

      final queuedDelete = (await store.readOutbox(
        accountId: accountId,
        key: key,
      )).single;
      final deleteEnvelope = jsonDecode(queuedDelete) as Map<String, dynamic>;
      expect(deleteEnvelope['action'], 'delete');
      expect(deleteEnvelope['expectedRevision'], 1);

      final deleted = notifier.state.trashNotes.single;
      expect(await notifier.restoreNote(deleted), isTrue);
      expect(notifier.state.notes.single.deletedAt, isNull);
      expect(notifier.state.queuedNoteIds, contains(noteId));
      final queued = await store.readOutbox(accountId: accountId, key: key);
      expect(queued, hasLength(2));
      expect(queued.map((payload) => (jsonDecode(payload) as Map)['action']), [
        'delete',
        'restore',
      ]);
    },
  );

  test('queues a CRDT edit locally after a cloud write fails', () async {
    const accountId = 'account-a';
    const noteId = 'note-a';
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith(
          '/rpc/append_workspace_note_crdt_operation',
        )) {
          return http.Response(
            '{"message":"offline"}',
            503,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-0/0',
          },
        );
      }),
    );
    await _authenticate(client, accountId);
    final database = NotesLocalDatabase(NativeDatabase.memory());
    final store = NotesLocalStore(
      database: database,
      storageAvailability: () async => true,
    );
    final sync = NotesSyncRepository(
      store: store,
      transport: _OfflineTransport(),
      keyForAccount: (_) async => key,
      currentAccountId: () async => accountId,
    );
    final notifier = WorkspaceNotesNotifier(
      client,
      WorkspaceNoteRepository(client),
      offlineService: NotesOfflineService(
        store: store,
        sync: sync,
        keyForAccount: (_) async => key,
      ),
    );
    addTearDown(notifier.dispose);
    addTearDown(client.dispose);
    addTearDown(database.close);

    final note = WorkspaceNote(
      id: noteId,
      ownerUserId: accountId,
      title: 'Offline note',
      markdownContent: 'old text',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      revision: 1,
    );
    final document = NoteCrdtDocument.fromMarkdown(noteId, 'old text');
    final operation = document.applyLocalEdit(
      replicaId: 'device-a',
      markdown: 'offline draft',
    );
    expect(operation, isNotNull);

    final saved = await notifier.syncCrdtEdit(
      note: note,
      document: document,
      operations: [operation!],
    );

    expect(saved?.markdownContent, 'offline draft');
    expect(notifier.state.queuedNoteIds, contains(noteId));
    expect(
      await store.readNote(accountId: accountId, noteId: noteId, key: key),
      'offline draft',
    );
    final queued = (await store.readOutbox(
      accountId: accountId,
      key: key,
    )).single;
    final envelope = jsonDecode(queued) as Map<String, dynamic>;
    expect(envelope['opId'], operation.opId);
    expect(envelope['projectId'], isNull);
    expect(envelope['operation'], isA<Map>());
  });
}
