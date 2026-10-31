import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/notes/data/notes_local_database.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';
import 'package:varian/features/notes/data/workspace_note_attachment_repository.dart';

const _accountId = '223e4567-e89b-12d3-a456-426614174001';
const _noteId = '323e4567-e89b-12d3-a456-426614174002';
const _attachmentId = '123e4567-e89b-12d3-a456-426614174000';
const _projectId = 'proj-1';
const _pngBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _authenticate(
  SupabaseClient client, {
  String accountId = _accountId,
}) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final token =
      '${_encodePart({'alg': 'HS256'})}.${_encodePart({'sub': accountId, 'exp': expiration})}.signature';
  client.auth.stopAutoRefresh();
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'fixture-refresh-token',
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

http.Response _json(http.Request request, Object body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );

NotesLocalDatabase _database() => NotesLocalDatabase(NativeDatabase.memory());

WorkspaceNoteAttachmentRepository _repository(
  SupabaseClient client,
  NotesLocalDatabase database,
) => WorkspaceNoteAttachmentRepository(
  client: client,
  localStore: NotesLocalStore(
    database: database,
    storageAvailability: () async => true,
  ),
  keyForAccount: (_) async => null,
);

Map<String, dynamic> _noteRow({String? projectId = _projectId}) => {
  'id': _noteId,
  'owner_user_id': _accountId,
  'project_id': projectId,
  'deleted_at': null,
};

void main() {
  test(
    'uploads only after checking the Note scope and verifies final metadata',
    () async {
      final requests = <http.Request>[];
      final path = 'project/70726f6a2d31/$_attachmentId';
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/workspace_notes')) {
            return _json(request, _noteRow());
          }
          if (request.url.path.endsWith(
            '/rpc/create_workspace_note_attachment',
          )) {
            return _json(request, [
              {'attachment_id': _attachmentId, 'storage_path': path},
            ]);
          }
          if (request.url.path.contains(
            '/storage/v1/object/workspace-note-assets/',
          )) {
            return _json(request, {'Key': path, 'Id': 'object-id'});
          }
          if (request.url.path.endsWith(
            '/functions/v1/notes-attachment-rehome',
          )) {
            return _json(request, {
              'attachmentId': _attachmentId,
              'mimeType': 'image/png',
              'sizeBytes': _pngBytes.length,
            });
          }
          if (request.url.path.endsWith('/workspace_note_attachments')) {
            return _json(request, {
              'id': _attachmentId,
              'note_id': _noteId,
              'owner_user_id': _accountId,
              'project_id': _projectId,
              'storage_path': path,
              'original_name': 'diagram.png',
              'mime_type': 'image/png',
              'size_bytes': _pngBytes.length,
              'sha256': 'a' * 64,
              'status': 'ready',
            });
          }
          return _json(request, {'message': 'unexpected request'}, status: 500);
        }),
      );
      final database = _database();
      addTearDown(client.dispose);
      addTearDown(database.close);
      await _authenticate(client);

      final attachment = await _repository(client, database).upload(
        accountId: _accountId,
        noteId: _noteId,
        expectedProjectId: _projectId,
        originalName: 'diagram.png',
        bytes: Uint8List.fromList(_pngBytes),
      );

      expect(attachment.id, _attachmentId);
      expect(attachment.projectId, _projectId);
      expect(
        requests.map((request) => request.url.path),
        contains('/storage/v1/object/workspace-note-assets/$path'),
      );
      expect(
        requests.map((request) => request.url.path),
        contains('/functions/v1/notes-attachment-rehome'),
      );
    },
  );

  test(
    'rejects an attachment when the selected scope differs from the Note',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return _json(request, _noteRow(projectId: 'different-project'));
        }),
      );
      final database = _database();
      addTearDown(client.dispose);
      addTearDown(database.close);
      await _authenticate(client);

      await expectLater(
        _repository(client, database).upload(
          accountId: _accountId,
          noteId: _noteId,
          expectedProjectId: _projectId,
          originalName: 'diagram.png',
          bytes: Uint8List.fromList(_pngBytes),
        ),
        throwsFormatException,
      );

      expect(requests, hasLength(1));
      expect(requests.single.url.path, endsWith('/workspace_notes'));
    },
  );

  test(
    'stops before upload when the authenticated account changes mid-read',
    () async {
      final requests = <http.Request>[];
      late SupabaseClient client;
      client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          await _authenticate(
            client,
            accountId: '423e4567-e89b-12d3-a456-426614174003',
          );
          return _json(request, _noteRow());
        }),
      );
      final database = _database();
      addTearDown(client.dispose);
      addTearDown(database.close);
      await _authenticate(client);

      await expectLater(
        _repository(client, database).upload(
          accountId: _accountId,
          noteId: _noteId,
          expectedProjectId: _projectId,
          originalName: 'diagram.png',
          bytes: Uint8List.fromList(_pngBytes),
        ),
        throwsFormatException,
      );

      expect(requests, hasLength(1));
      expect(requests.single.url.path, endsWith('/workspace_notes'));
    },
  );
}
