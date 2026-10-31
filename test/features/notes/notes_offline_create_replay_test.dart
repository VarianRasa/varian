import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/notes/data/notes_local_database.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';
import 'package:varian/features/notes/data/notes_supabase_sync_transport.dart';
import 'package:varian/features/notes/data/notes_sync_repository.dart';

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<SupabaseClient> _authenticatedClient(
  _NotesApiMock api,
  String accountId,
) async {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-publishable-key',
    httpClient: MockClient(api.handle),
  );
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
  return client;
}

void main() {
  const accountId = 'account-a';
  const noteId = 'note-offline-create';
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index));

  test(
    'replays and acknowledges a private offline create idempotently',
    () async {
      final database = NotesLocalDatabase(NativeDatabase.memory());
      final store = NotesLocalStore(
        database: database,
        storageAvailability: () async => true,
      );
      final api = _NotesApiMock();
      final client = await _authenticatedClient(api, accountId);
      addTearDown(client.dispose);
      addTearDown(database.close);

      final repository = NotesSyncRepository(
        store: store,
        transport: SupabaseNotesSyncTransport(client),
        keyForAccount: (requestedAccount) async =>
            requestedAccount == accountId ? key : null,
        currentAccountId: () async => accountId,
      );
      final operation = <String, dynamic>{
        'kind': 'note_mutation',
        'action': 'create',
        'noteId': noteId,
        'opId': '$noteId:mutation:1',
        'ownerUserId': accountId,
        'projectId': null,
        'folderId': null,
        'title': 'Untitled Note',
        'markdownContent': 'private offline draft',
      };

      await repository.enqueue(
        accountId: accountId,
        operation: operation,
        key: key,
      );
      final queuedCiphertext = await database
          .customSelect('SELECT ciphertext FROM notes_outbox')
          .get();
      expect(queuedCiphertext, hasLength(1));
      expect(
        utf8.decode(
          queuedCiphertext.single.data['ciphertext'] as Uint8List,
          allowMalformed: true,
        ),
        isNot(contains('private offline draft')),
      );

      expect(await repository.syncAccount(accountId), 1);
      expect(api.rows, hasLength(1));
      expect(api.rows[noteId], containsPair('owner_user_id', accountId));
      expect(api.rows[noteId], containsPair('title', 'Untitled Note'));
      expect(
        api.rows[noteId],
        containsPair('markdown_content', 'private offline draft'),
      );
      expect(await store.readOutbox(accountId: accountId, key: key), isEmpty);
      expect(
        await database.customSelect('SELECT * FROM notes_outbox').get(),
        isEmpty,
      );

      await repository.enqueue(
        accountId: accountId,
        operation: operation,
        key: key,
      );
      expect(await repository.syncAccount(accountId), 1);
      expect(api.upsertRequests, 2);
      expect(api.rows, hasLength(1));
      expect(
        api.rows[noteId],
        containsPair('markdown_content', 'private offline draft'),
      );
      expect(await store.readOutbox(accountId: accountId, key: key), isEmpty);
    },
  );

  test(
    'keeps an encrypted create queued when its owner does not match',
    () async {
      final database = NotesLocalDatabase(NativeDatabase.memory());
      final store = NotesLocalStore(
        database: database,
        storageAvailability: () async => true,
      );
      final api = _NotesApiMock();
      final client = await _authenticatedClient(api, accountId);
      addTearDown(client.dispose);
      addTearDown(database.close);

      final repository = NotesSyncRepository(
        store: store,
        transport: SupabaseNotesSyncTransport(client),
        keyForAccount: (_) async => key,
        currentAccountId: () async => accountId,
      );
      final operation = <String, dynamic>{
        'kind': 'note_mutation',
        'action': 'create',
        'noteId': 'note-wrong-owner',
        'opId': 'note-wrong-owner:mutation:1',
        'ownerUserId': 'account-b',
        'projectId': null,
        'folderId': null,
        'title': 'Untitled Note',
        'markdownContent': 'private offline draft',
      };

      await repository.enqueue(
        accountId: accountId,
        operation: operation,
        key: key,
      );

      expect(await repository.syncAccount(accountId), 0);
      expect(api.requestCount, 0);
      expect(
        (await store.readOutbox(accountId: accountId, key: key)).single,
        jsonEncode(operation),
      );
    },
  );
}

class _NotesApiMock {
  final Map<String, Map<String, dynamic>> rows = {};
  var requestCount = 0;
  var upsertRequests = 0;

  Future<http.Response> handle(http.Request request) async {
    requestCount++;
    if (request.url.path.endsWith('/workspace_notes') &&
        request.method == 'POST') {
      upsertRequests++;
      final incoming = Map<String, dynamic>.from(
        jsonDecode(request.body) as Map,
      );
      rows.putIfAbsent(incoming['id'] as String, () => incoming);
      return http.Response('', 201, request: request);
    }
    if (request.url.path.endsWith('/workspace_notes') &&
        request.method == 'GET') {
      final idFilter = request.url.queryParameters['id'];
      final noteId = idFilter?.startsWith('eq.') == true
          ? idFilter!.substring(3)
          : null;
      final row = noteId == null ? null : rows[noteId];
      if (row != null) {
        return http.Response(
          jsonEncode(row),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
    }
    return http.Response('unexpected request', 500, request: request);
  }
}
