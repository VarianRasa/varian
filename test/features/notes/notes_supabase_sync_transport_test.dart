import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/notes/data/notes_supabase_sync_transport.dart';

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

void main() {
  const accountId = 'account-a';
  const noteId = 'note-a';

  for (final action in ['update', 'delete', 'restore']) {
    test('replays an idempotent private-note $action mutation', () async {
      var row = <String, dynamic>{
        'owner_user_id': accountId,
        'project_id': null,
        'title': 'Before',
        'markdown_content': 'before',
        'revision': 1,
        'deleted_at': action == 'restore' ? '2026-10-01T00:00:00Z' : null,
      };
      var writes = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/workspace_notes')) {
            if (request.method == 'GET') {
              return http.Response(
                jsonEncode(row),
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.method == 'PATCH') {
              writes++;
              final patch = jsonDecode(request.body) as Map<String, dynamic>;
              row = {...row, ...patch};
              return http.Response('', 204, request: request);
            }
          }
          return http.Response(
            'unexpected request',
            500,
            request: request,
            headers: {'content-type': 'text/plain'},
          );
        }),
      );
      await _authenticate(client, accountId);
      addTearDown(client.dispose);
      final transport = SupabaseNotesSyncTransport(client);
      final entry = <String, dynamic>{
        'kind': 'note_mutation',
        'action': action,
        'noteId': noteId,
        'opId': '$noteId:mutation:2',
        'projectId': null,
        'expectedRevision': 1,
        if (action == 'update') ...{
          'title': 'After',
          'markdownContent': 'after',
        },
      };

      await transport.replay(accountId, entry);
      await transport.replay(accountId, entry);

      expect(writes, 1);
      expect(row['revision'], 2);
      if (action == 'update') {
        expect(row['title'], 'After');
        expect(row['markdown_content'], 'after');
      } else if (action == 'delete') {
        expect(row['deleted_at'], isNotNull);
      } else {
        expect(row['deleted_at'], isNull);
      }
    });
  }

  test('replays private-note creation idempotently', () async {
    Map<String, dynamic>? row;
    var insertCount = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/workspace_notes') &&
            request.method == 'POST') {
          insertCount++;
          row ??= Map<String, dynamic>.from(
            jsonDecode(request.body) as Map<String, dynamic>,
          );
          row!['owner_user_id'] = accountId;
          return http.Response('', 201, request: request);
        }
        if (request.url.path.endsWith('/workspace_notes') &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode(row),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('unexpected request', 500, request: request);
      }),
    );
    await _authenticate(client, accountId);
    addTearDown(client.dispose);
    final entry = <String, dynamic>{
      'kind': 'note_mutation',
      'action': 'create',
      'noteId': noteId,
      'opId': '$noteId:mutation:1',
      'ownerUserId': accountId,
      'projectId': null,
      'folderId': null,
      'title': 'Created offline',
      'markdownContent': 'draft',
    };
    final transport = SupabaseNotesSyncTransport(client);

    await transport.replay(accountId, entry);
    await transport.replay(accountId, entry);

    expect(insertCount, 2);
    expect(row?['title'], 'Created offline');
    expect(row?['markdown_content'], 'draft');
  });

  test(
    'does not replay a project mutation after membership revocation',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/workspace_notes')) {
            return http.Response(
              jsonEncode({
                'owner_user_id': accountId,
                'project_id': 'project-1',
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/rpc/can_edit_project')) {
            return http.Response(
              'false',
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('unexpected request', 500, request: request);
        }),
      );
      await _authenticate(client, accountId);
      addTearDown(client.dispose);

      final allowed = await SupabaseNotesSyncTransport(client)
          .canReplay(accountId, {
            'kind': 'note_mutation',
            'action': 'delete',
            'noteId': noteId,
            'opId': '$noteId:mutation:2',
            'projectId': 'project-1',
          });

      expect(allowed, isFalse);
    },
  );

  test('does not replay a mutation belonging to another account', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient(
        (request) async =>
            http.Response('unexpected request', 500, request: request),
      ),
    );
    await _authenticate(client, accountId);
    addTearDown(client.dispose);

    final allowed = await SupabaseNotesSyncTransport(client)
        .canReplay('another-account', {
          'kind': 'note_mutation',
          'action': 'delete',
          'noteId': noteId,
          'opId': '$noteId:mutation:2',
        });

    expect(allowed, isFalse);
  });
}
