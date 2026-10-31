import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/app/workspace_timestamp.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_template.dart';
import 'package:varian/features/notes/domain/workspace_note_version.dart';
import 'package:varian/features/notes/data/notes_import_service.dart';

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _authenticate(
  SupabaseClient client, {
  String accountId = 'owner-a',
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

http.Response _noRows(http.Request request) => http.Response(
  jsonEncode({
    'code': 'PGRST116',
    'details': 'Results contain 0 rows',
    'hint': null,
    'message': 'JSON object requested, multiple (or no) rows returned',
  }),
  406,
  request: request,
  headers: {'content-type': 'application/json'},
);

http.Response _response(Object body, http.Request request) => http.Response(
  jsonEncode(body),
  200,
  request: request,
  headers: {'content-type': 'application/json', 'content-range': '0-0/1'},
);

void main() {
  test(
    'imports prepared notes through the destination-scoped atomic RPC',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/rpc/can_edit_project')) {
            return _response(true, request);
          }
          return _response([
            {
              'id': 'new-note-id',
              'owner_user_id': 'owner-a',
              'project_id': 'project-1',
              'created_by': 'owner-a',
              'folder_id': 'folder-id',
              'title': 'Imported',
              'markdown_content': 'exact Markdown',
              'created_at': '2026-10-11T00:00:00Z',
              'updated_at': '2026-10-11T00:00:00Z',
              'revision': 1,
            },
          ], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final imported = await WorkspaceNoteRepository(client).importNotes(
        notes: const [
          PreparedNoteImport(
            newId: 'new-note-id',
            sourcePath: 'Journal/imported.md',
            title: 'Imported',
            markdown: 'exact Markdown',
            folderPath: 'Journal',
            duplicateTitle: false,
          ),
        ],
        projectId: 'project-1',
        expectedAccountId: 'owner-a',
      );

      expect(imported.single.id, 'new-note-id');
      expect(imported.single.markdownContent, 'exact Markdown');
      final request = requests.singleWhere(
        (item) => item.url.path.endsWith('/rpc/import_workspace_notes_batch'),
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['p_project_id'], 'project-1');
      expect(body['p_folders'], ['Journal']);
      expect(body['p_notes'], [
        {
          'id': 'new-note-id',
          'title': 'Imported',
          'markdown_content': 'exact Markdown',
          'folder_path': 'Journal',
        },
      ]);
      expect(body.containsKey('p_owner_user_id'), isFalse);
    },
  );
  test(
    'history snapshots preserve exact Markdown and normalize timestamps',
    () {
      final version = WorkspaceNoteVersion.fromJson({
        'id': 'version-1',
        'note_id': 'note-1',
        'revision': 3,
        'title': 'History',
        'markdown_content': '  # Exact\n\n- list  ',
        'actor_id': null,
        'created_at': '2026-10-11T01:00:00-04:00',
      });

      expect(version.markdownContent, '  # Exact\n\n- list  ');
      expect(version.createdAt, DateTime.utc(2026, 10, 11, 5));
      expect(version.actorId, isNull);
    },
  );

  test('lists history newest revision first', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return _response([
          {
            'id': 'v3',
            'note_id': 'note-1',
            'revision': 3,
            'title': 'Third',
            'markdown_content': 'body',
            'actor_id': 'owner-a',
            'created_at': '2026-10-11T03:00:00Z',
          },
          {
            'id': 'v2',
            'note_id': 'note-1',
            'revision': 2,
            'title': 'Second',
            'markdown_content': 'older',
            'actor_id': 'owner-a',
            'created_at': '2026-10-11T02:00:00Z',
          },
        ], request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    final versions = await WorkspaceNoteRepository(
      client,
    ).listNoteVersions('note-1');

    expect(versions.map((version) => version.revision), [3, 2]);
    expect(requests.single.url.path, endsWith('/workspace_note_versions'));
    expect(
      requests.single.url.queryParameters['order'],
      'revision.desc.nullslast',
    );
    expect(requests.single.url.queryParameters['note_id'], 'eq.note-1');
  });

  test('restores exact historical Markdown as a new revision', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path.endsWith('/workspace_notes')) {
          return _response({
            'id': 'note-1',
            'owner_user_id': 'owner-a',
            'title': 'Current',
            'markdown_content': 'now',
            'created_at': '2026-10-11T00:00:00Z',
            'updated_at': '2026-10-11T03:00:00Z',
            'revision': 4,
          }, request);
        }
        if (request.url.path.endsWith('/workspace_note_versions')) {
          return _response({
            'id': 'version-2',
            'note_id': 'note-1',
            'revision': 2,
            'title': 'Old title',
            'markdown_content': '  # Old\n\nexact  ',
            'actor_id': 'owner-a',
            'created_at': '2026-10-11T02:00:00Z',
          }, request);
        }
        if (request.method == 'PATCH') {
          return _response({
            'id': 'note-1',
            'owner_user_id': 'owner-a',
            'title': 'Old title',
            'markdown_content': '  # Old\n\nexact  ',
            'created_at': '2026-10-11T00:00:00Z',
            'updated_at': '2026-10-11T04:00:00Z',
            'revision': 5,
          }, request);
        }
        return _noRows(request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    final restored = await WorkspaceNoteRepository(client).restoreNoteVersion(
      noteId: 'note-1',
      versionId: 'version-2',
      expectedRevision: 4,
      expectedAccountId: 'owner-a',
    );

    expect(restored.revision, 5);
    expect(restored.markdownContent, '  # Old\n\nexact  ');
    final update = requests.singleWhere((request) => request.method == 'PATCH');
    expect(update.url.queryParameters['revision'], 'eq.4');
    final updateBody = jsonDecode(update.body) as Map<String, dynamic>;
    expect(updateBody['title'], 'Old title');
    expect(updateBody['markdown_content'], '  # Old\n\nexact  ');
    expect(updateBody['revision'], 5);
    expect(updateBody['updated_at'], isA<String>());
  });

  test('stale history restore fails its revision compare-and-set', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'PATCH') return _noRows(request);
        if (request.url.path.endsWith('/workspace_note_versions')) {
          return _response({
            'id': 'version-2',
            'note_id': 'note-1',
            'revision': 2,
            'title': 'Old',
            'markdown_content': 'older',
            'actor_id': 'owner-a',
            'created_at': '2026-10-11T02:00:00Z',
          }, request);
        }
        return _response({
          'id': 'note-1',
          'owner_user_id': 'owner-a',
          'title': 'Current',
          'markdown_content': 'newest',
          'created_at': '2026-10-11T00:00:00Z',
          'updated_at': '2026-10-11T03:00:00Z',
          'revision': 5,
        }, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    await expectLater(
      WorkspaceNoteRepository(client).restoreNoteVersion(
        noteId: 'note-1',
        versionId: 'version-2',
        expectedRevision: 4,
        expectedAccountId: 'owner-a',
      ),
      throwsStateError,
    );
    final update = requests.singleWhere((request) => request.method == 'PATCH');
    expect(update.url.queryParameters['revision'], 'eq.4');
  });

  test('project viewers cannot restore a historical version', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/rpc/can_edit_project')) {
          return _response(false, request);
        }
        return _response({
          'id': 'project-note',
          'owner_user_id': 'owner-b',
          'title': 'Current',
          'markdown_content': 'body',
          'created_at': '2026-10-11T00:00:00Z',
          'updated_at': '2026-10-11T03:00:00Z',
          'revision': 4,
          'project_id': 'project-1',
        }, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    await expectLater(
      WorkspaceNoteRepository(client).restoreNoteVersion(
        noteId: 'project-note',
        versionId: 'version-2',
        expectedRevision: 4,
        expectedAccountId: 'owner-a',
      ),
      throwsStateError,
    );
    expect(
      requests.any(
        (request) => request.url.path.endsWith('/workspace_note_versions'),
      ),
      isFalse,
    );
    expect(requests.any((request) => request.method == 'PATCH'), isFalse);
  });

  test('legacy note JSON defaults createdBy to owner and parses scope', () {
    final note = WorkspaceNote.fromJson({
      'id': 'note-a',
      'owner_user_id': 'owner-a',
      'title': 'A',
      'markdown_content': '',
      'created_at': '2026-10-01T00:00:00Z',
      'updated_at': '2026-10-01T00:00:00Z',
    });
    expect(note.createdBy, 'owner-a');
    expect(note.projectId, isNull);
    expect(note.folderId, isNull);
  });
  test(
    'save advances revision only when the loaded revision matches',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return _response({
            'id': 'note-1',
            'owner_user_id': 'owner-a',
            'title': 'Updated',
            'markdown_content': 'draft',
            'created_at': '2026-10-11T00:00:00Z',
            'updated_at': '2026-10-11T01:00:00Z',
            'revision': 3,
          }, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final repository = WorkspaceNoteRepository(client);
      final note = WorkspaceNote.fromJson({
        'id': 'note-1',
        'owner_user_id': 'owner-a',
        'title': 'Updated',
        'markdown_content': 'draft',
        'created_at': '2026-10-11T00:00:00Z',
        'updated_at': '2026-10-11T00:00:00Z',
        'revision': 2,
      });

      final outcome = await repository.save(note, expectedAccountId: 'owner-a');

      expect((outcome as WorkspaceNoteSaveSuccess).note.revision, 3);
      expect(requests.single.url.queryParameters['revision'], 'eq.2');
      expect((jsonDecode(requests.single.body) as Map)['revision'], 3);
    },
  );

  test('classifies a live changed row as conflict after CAS misses', () async {
    var reads = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH') return _noRows(request);
        reads++;
        return _response({
          'id': 'note-1',
          'owner_user_id': 'owner-a',
          'title': 'Remote',
          'markdown_content': 'remote body',
          'created_at': '2026-10-11T00:00:00Z',
          'updated_at': '2026-10-11T01:00:00Z',
          'revision': 4,
        }, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final note = WorkspaceNote.fromJson({
      'id': 'note-1',
      'owner_user_id': 'owner-a',
      'title': 'Local',
      'markdown_content': 'draft',
      'created_at': '2026-10-11T00:00:00Z',
      'updated_at': '2026-10-11T00:00:00Z',
      'revision': 2,
    });
    final outcome = await WorkspaceNoteRepository(
      client,
    ).save(note, expectedAccountId: 'owner-a');
    expect(outcome, isA<WorkspaceNoteSaveConflict>());
    expect((outcome as WorkspaceNoteSaveConflict).remoteNote.revision, 4);
    expect(reads, 1);
  });

  test('classifies a missing row after CAS miss as unavailable', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return _noRows(request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final note = WorkspaceNote.fromJson({
      'id': 'note-1',
      'owner_user_id': 'owner-a',
      'title': 'Local',
      'markdown_content': 'draft',
      'created_at': '2026-10-11T00:00:00Z',
      'updated_at': '2026-10-11T00:00:00Z',
      'revision': 2,
    });
    final outcome = await WorkspaceNoteRepository(
      client,
    ).save(note, expectedAccountId: 'owner-a');
    expect(outcome, isA<WorkspaceNoteSaveUnavailable>());
    expect(
      requests.last.url.queryParameters.containsKey('owner_user_id'),
      isFalse,
    );
    expect(requests.last.url.queryParameters['id'], 'eq.note-1');
  });

  test(
    'classifies changed project notes as conflicts under RLS visibility',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/rpc/can_edit_project')) {
            return _response(true, request);
          }
          if (request.method == 'PATCH') return _noRows(request);
          if (request.url.queryParameters.containsKey('owner_user_id')) {
            return _noRows(request);
          }
          return _response({
            'id': 'project-note',
            'owner_user_id': 'owner-b',
            'project_id': 'project-1',
            'created_by': 'owner-b',
            'title': 'Shared note',
            'markdown_content': 'remote content',
            'created_at': '2026-10-11T00:00:00Z',
            'updated_at': '2026-10-11T01:00:00Z',
            'revision': 5,
          }, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final note = WorkspaceNote(
        id: 'project-note',
        ownerUserId: 'owner-b',
        projectId: 'project-1',
        createdBy: 'owner-b',
        title: 'Shared note',
        markdownContent: 'local content',
        createdAt: DateTime.utc(2026, 10, 11),
        updatedAt: DateTime.utc(2026, 10, 11),
        revision: 2,
      );

      final result = await WorkspaceNoteRepository(
        client,
      ).save(note, expectedAccountId: 'owner-a');

      expect(result, isA<WorkspaceNoteSaveConflict>());
      expect((result as WorkspaceNoteSaveConflict).remoteNote.revision, 5);
      final conflictRead = requests.last;
      expect(conflictRead.method, 'GET');
      expect(conflictRead.url.queryParameters['id'], 'eq.project-note');
      expect(
        conflictRead.url.queryParameters.containsKey('owner_user_id'),
        isFalse,
      );
    },
  );

  test(
    'rejects a note owned by a different account before sending a request',
    () async {
      var requestCount = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requestCount++;
          return _response({}, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final note = WorkspaceNote(
        id: 'note-1',
        ownerUserId: 'owner-b',
        title: 'Private',
        markdownContent: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        revision: 2,
      );
      await expectLater(
        WorkspaceNoteRepository(
          client,
        ).save(note, expectedAccountId: 'owner-a'),
        throwsA(isA<StateError>()),
      );
      expect(requestCount, 0);
    },
  );

  test(
    'legacy title rename advances revision and invalidates stale saves',
    () async {
      final requests = <http.Request>[];
      final createdAt = DateTime.utc(2026, 10, 11, 6, 5);
      final updatedAt = DateTime.utc(2026, 10, 11, 7, 30);
      final original = <String, dynamic>{
        'id': 'legacy-note',
        'owner_user_id': 'owner-a',
        'title': 'Untitled Note',
        'markdown_content': '# Preserve content',
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'revision': 2,
      };
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET' &&
              request.url.queryParameters.containsKey('title')) {
            return _response([original], request);
          }
          if (request.method == 'PATCH' &&
              request.url.queryParameters.containsKey('title')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return _response({
              ...original,
              ...body,
              'title': formatWorkspaceTimestamp(createdAt),
              'revision': 3,
            }, request);
          }
          if (request.method == 'PATCH') return _noRows(request);
          return _response({
            ...original,
            'title': formatWorkspaceTimestamp(createdAt),
            'revision': 3,
          }, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final repository = WorkspaceNoteRepository(client);

      final renamed = await repository.renameLegacyUntitledNotes(
        expectedAccountId: 'owner-a',
      );
      final renameRequest = requests.firstWhere(
        (request) => request.method == 'PATCH',
      );
      final renameBody = jsonDecode(renameRequest.body) as Map<String, dynamic>;
      expect(renameRequest.url.queryParameters['revision'], 'eq.2');
      expect(renameBody['revision'], 3);
      expect(renameBody.containsKey('updated_at'), isFalse);
      expect(renamed.single.revision, 3);
      expect(renamed.single.updatedAt, updatedAt);

      final staleSave = await repository.save(
        WorkspaceNote.fromJson(original),
        expectedAccountId: 'owner-a',
      );
      expect(staleSave, isA<WorkspaceNoteSaveConflict>());
      expect((staleSave as WorkspaceNoteSaveConflict).remoteNote.revision, 3);
    },
  );

  test('does not accept a malformed remote revision as a conflict', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH') return _noRows(request);
        return _response({
          'id': 'note-1',
          'owner_user_id': 'owner-a',
          'title': 'Remote',
          'markdown_content': 'remote',
          'created_at': '2026-10-11T00:00:00Z',
          'updated_at': '2026-10-11T01:00:00Z',
          'revision': 'bad',
        }, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final note = WorkspaceNote(
      id: 'note-1',
      ownerUserId: 'owner-a',
      title: 'Local',
      markdownContent: 'draft',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      revision: 2,
    );
    await expectLater(
      WorkspaceNoteRepository(client).save(note, expectedAccountId: 'owner-a'),
      throwsA(isA<TypeError>()),
    );
  });

  test(
    'daily note lookup sends its device-local date and selected scope',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return _response({
            'id': 'daily-note-id',
            'owner_user_id': 'owner-a',
            'created_by': 'owner-a',
            'project_id': 'project-1',
            'daily_note_date': '2026-10-21',
            'title': '2026-10-21',
            'markdown_content': 'existing body',
            'created_at': '2026-10-21T00:00:00Z',
            'updated_at': '2026-10-21T00:00:00Z',
            'revision': 1,
            'deleted_at': null,
          }, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final note = await WorkspaceNoteRepository(client).getOrCreateDailyNote(
        localDate: DateTime(2026, 10, 21, 23, 45),
        projectId: 'project-1',
        expectedAccountId: 'owner-a',
      );

      expect(note.id, 'daily-note-id');
      expect(note.dailyNoteDate, '2026-10-21');
      expect(note.markdownContent, 'existing body');
      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        endsWith('/rpc/get_or_create_workspace_daily_note'),
      );
      expect(jsonDecode(requests.single.body), {
        'p_daily_note_date': '2026-10-21',
        'p_project_id': 'project-1',
      });
    },
  );

  test(
    'lists and creates Notes templates in the selected project scope',
    () async {
      final requests = <http.Request>[];
      final templateRow = {
        'id': 'template-1',
        'owner_user_id': 'owner-b',
        'created_by': 'owner-b',
        'project_id': 'project-1',
        'title': 'Shared template',
        'markdown_content': '# {{title}}',
        'revision': 1,
        'created_at': '2026-10-21T00:00:00Z',
        'updated_at': '2026-10-21T00:00:00Z',
      };
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/rpc/can_edit_project')) {
            return _response(true, request);
          }
          if (request.method == 'GET') {
            return _response([templateRow], request);
          }
          final inserted = jsonDecode(request.body) as Map<String, dynamic>;
          return _response({
            ...inserted,
            'id': 'created-template',
            'created_at': inserted['created_at'],
            'updated_at': inserted['updated_at'],
          }, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final repository = WorkspaceNoteRepository(client);

      final templates = await repository.listTemplates(
        projectId: 'project-1',
        expectedAccountId: 'owner-a',
      );
      final created = await repository.createTemplate(
        title: '  Meeting  ',
        markdownContent: '# {{title}}',
        projectId: 'project-1',
        expectedAccountId: 'owner-a',
      );

      expect(templates.single.title, 'Shared template');
      expect(templates.single.projectId, 'project-1');
      expect(created.title, 'Meeting');
      expect(created.projectId, 'project-1');
      expect(created.createdBy, 'owner-a');
      final listRequest = requests.firstWhere(
        (request) => request.method == 'GET',
      );
      expect(listRequest.url.queryParameters['project_id'], 'eq.project-1');
      final insertRequest = requests.singleWhere(
        (request) =>
            request.method == 'POST' &&
            request.url.path.endsWith('/workspace_note_templates'),
      );
      final inserted = jsonDecode(insertRequest.body) as Map<String, dynamic>;
      expect(inserted['owner_user_id'], 'owner-a');
      expect(inserted['created_by'], 'owner-a');
      expect(inserted['project_id'], 'project-1');
      expect(inserted['revision'], 1);
    },
  );

  test('template updates use revision CAS and report stale edits', () async {
    final requests = <http.Request>[];
    final currentRow = {
      'id': 'template-1',
      'owner_user_id': 'owner-a',
      'created_by': 'owner-a',
      'project_id': 'project-1',
      'title': 'Remote title',
      'markdown_content': 'remote body',
      'revision': 2,
      'created_at': '2026-10-21T00:00:00Z',
      'updated_at': '2026-10-22T00:00:00Z',
    };
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/rpc/can_edit_project')) {
          return _response(true, request);
        }
        if (request.method == 'PATCH') return _noRows(request);
        return _response(currentRow, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    final template = WorkspaceNoteTemplate(
      id: 'template-1',
      ownerUserId: 'owner-a',
      projectId: 'project-1',
      title: 'Original title',
      markdownContent: 'original body',
      createdAt: DateTime.utc(2026, 10, 21),
      updatedAt: DateTime.utc(2026, 10, 21),
    );
    await expectLater(
      WorkspaceNoteRepository(client).updateTemplate(
        template,
        title: 'Local title',
        markdownContent: 'local body',
        expectedAccountId: 'owner-a',
      ),
      throwsA(isA<WorkspaceNoteTemplateConflictException>()),
    );

    final patch = requests.singleWhere((request) => request.method == 'PATCH');
    expect(patch.url.queryParameters['revision'], 'eq.1');
    expect(patch.url.queryParameters['project_id'], 'eq.project-1');
    expect(patch.url.queryParameters['owner_user_id'], 'eq.owner-a');
    expect(patch.url.queryParameters['created_by'], 'eq.owner-a');
    final body = jsonDecode(patch.body) as Map<String, dynamic>;
    expect(body['revision'], 2);
    expect(body['title'], 'Local title');
    expect(body['markdown_content'], 'local body');
  });

  test('project template creation requires edit permission', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return _response(false, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    await expectLater(
      WorkspaceNoteRepository(client).createTemplate(
        title: 'No access',
        markdownContent: 'Body',
        projectId: 'project-1',
        expectedAccountId: 'owner-a',
      ),
      throwsA(isA<StateError>()),
    );

    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('/rpc/can_edit_project'));
  });

  test('template delete uses revision CAS and reports a stale row', () async {
    final requests = <http.Request>[];
    final currentRow = {
      'id': 'template-1',
      'owner_user_id': 'owner-a',
      'created_by': 'owner-a',
      'project_id': 'project-1',
      'title': 'Remote title',
      'markdown_content': 'remote body',
      'revision': 2,
      'created_at': '2026-10-21T00:00:00Z',
      'updated_at': '2026-10-22T00:00:00Z',
    };
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/rpc/can_edit_project')) {
          return _response(true, request);
        }
        if (request.method == 'DELETE') return _noRows(request);
        return _response(currentRow, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final template = WorkspaceNoteTemplate(
      id: 'template-1',
      ownerUserId: 'owner-a',
      projectId: 'project-1',
      title: 'Original title',
      markdownContent: 'original body',
      createdAt: DateTime.utc(2026, 10, 21),
      updatedAt: DateTime.utc(2026, 10, 21),
    );

    await expectLater(
      WorkspaceNoteRepository(
        client,
      ).deleteTemplate(template: template, expectedAccountId: 'owner-a'),
      throwsA(isA<WorkspaceNoteTemplateConflictException>()),
    );

    final delete = requests.singleWhere(
      (request) => request.method == 'DELETE',
    );
    expect(delete.url.queryParameters['revision'], 'eq.1');
    expect(delete.url.queryParameters['project_id'], 'eq.project-1');
    expect(delete.url.queryParameters['owner_user_id'], 'eq.owner-a');
    expect(delete.url.queryParameters['created_by'], 'eq.owner-a');
  });

  test(
    'private template update and delete succeed with exact scope CAS',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'PATCH') {
            return _response({
              'id': 'template-1',
              'owner_user_id': 'owner-a',
              'created_by': 'owner-a',
              'project_id': null,
              'title': 'Updated',
              'markdown_content': 'new content',
              'revision': 2,
              'created_at': '2026-10-21T00:00:00Z',
              'updated_at': '2026-10-22T00:00:00Z',
            }, request);
          }
          if (request.method == 'DELETE') {
            return _response({'id': 'template-1'}, request);
          }
          return _noRows(request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final repository = WorkspaceNoteRepository(client);
      final template = WorkspaceNoteTemplate(
        id: 'template-1',
        ownerUserId: 'owner-a',
        title: 'Original',
        markdownContent: 'old content',
        createdAt: DateTime.utc(2026, 10, 21),
        updatedAt: DateTime.utc(2026, 10, 21),
      );

      final updated = await repository.updateTemplate(
        template,
        title: 'Updated',
        markdownContent: 'new content',
        expectedAccountId: 'owner-a',
      );
      await repository.deleteTemplate(
        template: updated,
        expectedAccountId: 'owner-a',
      );

      expect(updated.revision, 2);
      expect(updated.markdownContent, 'new content');
      for (final request in requests) {
        expect(request.url.queryParameters['project_id'], 'is.null');
        expect(request.url.queryParameters['owner_user_id'], 'eq.owner-a');
        expect(request.url.queryParameters['created_by'], 'eq.owner-a');
      }
      expect(requests.map((request) => request.method), ['PATCH', 'DELETE']);
    },
  );

  test('private template query and response stay owner-scoped', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return _response([
          {
            'id': 'template-1',
            'owner_user_id': 'owner-b',
            'created_by': 'owner-b',
            'project_id': null,
            'title': 'Wrong owner',
            'markdown_content': 'private',
            'revision': 1,
            'created_at': '2026-10-21T00:00:00Z',
            'updated_at': '2026-10-21T00:00:00Z',
          },
        ], request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    await expectLater(
      WorkspaceNoteRepository(
        client,
      ).listTemplates(expectedAccountId: 'owner-a'),
      throwsA(isA<StateError>()),
    );
    expect(requests.single.url.queryParameters['owner_user_id'], 'eq.owner-a');
    expect(requests.single.url.queryParameters['project_id'], 'is.null');
  });

  test('new blank note stores a local-time title and creation time', () async {
    late Map<String, dynamic> inserted;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        inserted = jsonDecode(request.body) as Map<String, dynamic>;
        return _response({
          ...inserted,
          'created_at': inserted['created_at'],
          'updated_at': inserted['updated_at'],
        }, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    final note = await WorkspaceNoteRepository(
      client,
    ).create(title: 'Untitled Note', expectedAccountId: 'owner-a');

    final createdAt = DateTime.parse(inserted['created_at'] as String);
    expect(note.title, formatWorkspaceTimestamp(createdAt));
    expect(inserted['title'], note.title);
    expect(note.ownerUserId, 'owner-a');
    expect(note.markdownContent, isEmpty);
  });

  test('creates unresolved notes in the source project scope', () async {
    late Map<String, dynamic> inserted;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/rpc/can_edit_project')) {
          return _response(true, request);
        }
        inserted = jsonDecode(request.body) as Map<String, dynamic>;
        return _response({
          ...inserted,
          'created_at': inserted['created_at'],
          'updated_at': inserted['updated_at'],
          'revision': 1,
          'deleted_at': null,
        }, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    final note = await WorkspaceNoteRepository(client).create(
      title: 'Missing note',
      projectId: 'project-1',
      expectedAccountId: 'owner-a',
    );

    expect(inserted['owner_user_id'], 'owner-a');
    expect(inserted['created_by'], 'owner-a');
    expect(inserted['project_id'], 'project-1');
    expect(note.projectId, 'project-1');
    expect(note.title, 'Missing note');
  });

  test(
    'renames only exact legacy note titles within the current owner',
    () async {
      final createdAt = DateTime.utc(2026, 10, 11, 6, 5);
      final updatedAt = DateTime.utc(2026, 10, 11, 7, 30);
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final note = {
            'id': 'legacy-note',
            'owner_user_id': 'owner-a',
            'title': 'Untitled Note',
            'markdown_content': '# Preserve content',
            'created_at': createdAt.toIso8601String(),
            'updated_at': updatedAt.toIso8601String(),
          };
          if (request.method == 'GET') {
            return _response([note], request);
          }
          final updated = {
            ...note,
            'title': formatWorkspaceTimestamp(createdAt),
          };
          return _response(updated, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final renamed = await WorkspaceNoteRepository(
        client,
      ).renameLegacyUntitledNotes(expectedAccountId: 'owner-a');

      expect(renamed, hasLength(1));
      expect(renamed.single.title, formatWorkspaceTimestamp(createdAt));
      expect(renamed.single.id, 'legacy-note');
      expect(renamed.single.ownerUserId, 'owner-a');
      expect(renamed.single.markdownContent, '# Preserve content');
      expect(renamed.single.createdAt, createdAt);
      expect(renamed.single.updatedAt, updatedAt);
      expect(requests.last.url.queryParameters['owner_user_id'], 'eq.owner-a');
      expect(requests.last.url.queryParameters['title'], 'eq.Untitled Note');
    },
  );

  test(
    'active listing relies on RLS while Trash remains owner-scoped',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return _response([], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final repository = WorkspaceNoteRepository(client);
      await repository.list(expectedAccountId: 'owner-a');
      await repository.listTrash(expectedAccountId: 'owner-a');
      expect(
        requests[0].url.queryParameters.containsKey('owner_user_id'),
        isFalse,
      );
      expect(requests[0].url.queryParameters['deleted_at'], 'is.null');
      expect(
        requests[1].url.queryParameters.containsKey('owner_user_id'),
        isFalse,
      );
      expect(requests[1].url.queryParameters['deleted_at'], 'not.is.null');
    },
  );

  test(
    'deleted row is unavailable to open and stale save after delete is unavailable',
    () async {
      final requests = <http.Request>[];
      final deletedRow = {
        'id': 'note-1',
        'owner_user_id': 'owner-a',
        'title': 'Deleted',
        'markdown_content': 'private markdown',
        'created_at': '2026-10-11T00:00:00Z',
        'updated_at': '2026-10-11T01:00:00Z',
        'revision': 3,
        'deleted_at': '2026-10-11T01:00:00Z',
      };
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'PATCH') return _noRows(request);
          if (request.url.queryParameters.containsKey('id')) {
            if (request.url.queryParameters['deleted_at'] == 'is.null') {
              return _noRows(request);
            }
            return _response(deletedRow, request);
          }
          return _response([], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final repository = WorkspaceNoteRepository(client);
      final stale = WorkspaceNote.fromJson({
        ...deletedRow,
        'deleted_at': null,
        'revision': 2,
      });
      expect(
        await repository.save(stale, expectedAccountId: 'owner-a'),
        isA<WorkspaceNoteSaveUnavailable>(),
      );
      await expectLater(
        repository.get('note-1', expectedAccountId: 'owner-a'),
        throwsA(isA<StateError>()),
      );
      expect(requests.first.url.queryParameters['revision'], 'eq.2');
    },
  );

  test(
    'delete and restore use owner/revision CAS and advance metadata',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _response({
            'id': 'note-1',
            'owner_user_id': 'owner-a',
            'title': 'Title',
            'markdown_content': 'body',
            'created_at': '2026-10-11T00:00:00Z',
            'updated_at': body['updated_at'],
            'revision': body['revision'],
            'deleted_at': body['deleted_at'],
          }, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final repository = WorkspaceNoteRepository(client);
      final live = WorkspaceNote(
        id: 'note-1',
        ownerUserId: 'owner-a',
        title: 'Title',
        markdownContent: 'body',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        revision: 2,
      );
      final deleted = await repository.delete(
        live,
        expectedAccountId: 'owner-a',
      );
      expect(deleted.deletedAt, isNotNull);
      expect(deleted.revision, 3);
      expect(
        requests.first.url.queryParameters.containsKey('owner_user_id'),
        isFalse,
      );
      expect(requests.first.url.queryParameters['revision'], 'eq.2');
      expect(requests.first.url.queryParameters['deleted_at'], 'is.null');
      final restored = await repository.restore(
        deleted,
        expectedAccountId: 'owner-a',
      );
      expect(restored.deletedAt, isNull);
      expect(restored.revision, 4);
      expect(requests.last.url.queryParameters['revision'], 'eq.3');
      expect(requests.last.url.queryParameters['deleted_at'], 'not.is.null');
    },
  );

  test(
    'rename RPC sends the complete revision snapshot and planned rewrites',
    () async {
      final requests = <http.Request>[];
      final now = DateTime.utc(2026);
      final targetId = '123e4567-e89b-12d3-a456-426614174000';
      final sourceId = '123e4567-e89b-12d3-a456-426614174001';
      final otherId = '123e4567-e89b-12d3-a456-426614174002';
      WorkspaceNote makeNote(
        String id,
        String title,
        int revision, {
        String markdown = '',
      }) => WorkspaceNote(
        id: id,
        ownerUserId: 'owner-a',
        title: title,
        markdownContent: markdown,
        createdAt: now,
        updatedAt: now,
        revision: revision,
      );
      final target = makeNote(targetId, 'Target', 3);
      final source = makeNote(sourceId, 'Source', 2, markdown: '[[Target]]');
      final other = makeNote(otherId, 'Other', 1);
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return _response([
            {
              'id': targetId,
              'owner_user_id': 'owner-a',
              'title': 'Renamed',
              'markdown_content': '',
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
              'revision': 4,
            },
            {
              'id': sourceId,
              'owner_user_id': 'owner-a',
              'title': 'Source',
              'markdown_content': '[[Renamed]]',
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
              'revision': 3,
            },
          ], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final updated = await WorkspaceNoteRepository(client).renameWithLinks(
        target: target,
        title: ' Renamed ',
        snapshot: [target, source, other],
        markdownReplacements: {sourceId: '[[Renamed]]'},
        expectedAccountId: 'owner-a',
      );

      expect(updated.map((note) => note.id), [targetId, sourceId]);
      expect(updated.first.revision, 4);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/rename_workspace_notes_with_links',
      );
      final payload = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(payload['p_target_id'], targetId);
      expect(payload['p_expected_revision'], 3);
      expect(payload['p_title'], 'Renamed');
      expect(payload.containsKey('p_owner_user_id'), isFalse);
      expect(payload['p_snapshot'], [
        {'id': targetId, 'revision': 3},
        {'id': sourceId, 'revision': 2},
        {'id': otherId, 'revision': 1},
      ]);
      expect(payload['p_source_updates'], [
        {'id': sourceId, 'revision': 2, 'markdown_content': '[[Renamed]]'},
      ]);
    },
  );

  test(
    'project editor may rename notes owned by another project member',
    () async {
      const targetId = '123e4567-e89b-12d3-a456-426614174000';
      const sourceId = '223e4567-e89b-12d3-a456-426614174000';
      final now = DateTime.utc(2026);
      final target = WorkspaceNote(
        id: targetId,
        ownerUserId: 'owner-b',
        createdBy: 'owner-b',
        projectId: 'project-1',
        title: 'Target',
        markdownContent: '',
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );
      final source = WorkspaceNote(
        id: sourceId,
        ownerUserId: 'owner-b',
        createdBy: 'owner-b',
        projectId: 'project-1',
        title: 'Source',
        markdownContent: '[[Target]]',
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/rpc/can_edit_project')) {
            return _response(true, request);
          }
          return _response([
            {
              'id': targetId,
              'owner_user_id': 'owner-b',
              'created_by': 'owner-b',
              'project_id': 'project-1',
              'title': 'Renamed',
              'markdown_content': '',
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
              'revision': 2,
            },
            {
              'id': sourceId,
              'owner_user_id': 'owner-b',
              'created_by': 'owner-b',
              'project_id': 'project-1',
              'title': 'Source',
              'markdown_content': '[[Renamed]]',
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
              'revision': 2,
            },
          ], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final updated = await WorkspaceNoteRepository(client).renameWithLinks(
        target: target,
        title: 'Renamed',
        snapshot: [target, source],
        markdownReplacements: {sourceId: '[[Renamed]]'},
        expectedAccountId: 'owner-a',
      );

      expect(updated.map((note) => note.id), [targetId, sourceId]);
      expect(updated.every((note) => note.ownerUserId == 'owner-b'), isTrue);
      expect(updated.every((note) => note.projectId == 'project-1'), isTrue);
    },
  );

  test('rename validates account and replacement IDs before RPC', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return _response([], request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final now = DateTime.utc(2026);
    final target = WorkspaceNote(
      id: '123e4567-e89b-12d3-a456-426614174000',
      ownerUserId: 'owner-a',
      title: 'Target',
      markdownContent: '',
      createdAt: now,
      updatedAt: now,
    );
    final repository = WorkspaceNoteRepository(client);

    await expectLater(
      repository.renameWithLinks(
        target: target,
        title: 'Next',
        snapshot: [target],
        markdownReplacements: {},
        expectedAccountId: 'another-account',
      ),
      throwsStateError,
    );
    await expectLater(
      repository.renameWithLinks(
        target: target,
        title: 'Next',
        snapshot: [target],
        markdownReplacements: {'unknown-id': 'body'},
        expectedAccountId: 'owner-a',
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.renameWithLinks(
        target: target,
        title: 'Next',
        snapshot: [target],
        markdownReplacements: {target.id: 'arbitrary content'},
        expectedAccountId: 'owner-a',
      ),
      throwsArgumentError,
    );
    expect(requests, isEmpty);
  });

  test(
    'rename rejects snapshots that cross project and private scope',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/rpc/can_edit_project')) {
            return _response(true, request);
          }
          return _response([], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final now = DateTime.utc(2026);
      final target = WorkspaceNote(
        id: '123e4567-e89b-12d3-a456-426614174000',
        ownerUserId: 'owner-a',
        projectId: 'project-a',
        title: 'Target',
        markdownContent: '',
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );
      final privateSource = WorkspaceNote(
        id: 'private-source',
        ownerUserId: 'owner-a',
        title: 'Source',
        markdownContent: '[[Target]]',
        createdAt: now,
        updatedAt: now,
        revision: 1,
      );

      await expectLater(
        WorkspaceNoteRepository(client).renameWithLinks(
          target: target,
          title: 'Next',
          snapshot: [target, privateSource],
          markdownReplacements: {},
          expectedAccountId: 'owner-a',
        ),
        throwsArgumentError,
      );
      expect(
        requests.any(
          (request) => request.url.path.endsWith(
            '/rpc/rename_workspace_notes_with_links',
          ),
        ),
        isFalse,
      );
    },
  );

  test('rename maps stale and unavailable RPC outcomes', () async {
    final now = DateTime.utc(2026);
    final target = WorkspaceNote(
      id: '123e4567-e89b-12d3-a456-426614174000',
      ownerUserId: 'owner-a',
      title: 'Target',
      markdownContent: '',
      createdAt: now,
      updatedAt: now,
      revision: 3,
    );
    final errorCases = <(String, Type)>[
      ('workspace_notes_conflict', WorkspaceNoteRenameConflictException),
      ('workspace_notes_unavailable', WorkspaceNoteRenameUnavailableException),
    ];
    for (final error in errorCases) {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': 'P0001',
              'message': error.$1,
              'details': null,
              'hint': null,
            }),
            400,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      await expectLater(
        WorkspaceNoteRepository(client).renameWithLinks(
          target: target,
          title: 'Next',
          snapshot: [target],
          markdownReplacements: {},
          expectedAccountId: 'owner-a',
        ),
        throwsA(predicate((actual) => actual.runtimeType == error.$2)),
      );
    }
  });

  test('pin writes and reads stay isolated to the signed-in account', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return _response([], request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final repository = WorkspaceNoteRepository(client);

    await repository.setPinned(
      noteId: 'note-1',
      pinned: true,
      expectedAccountId: 'owner-a',
    );
    await repository.listPinnedNotes(expectedAccountId: 'owner-a');
    expect(jsonDecode(requests.first.body), {
      'user_id': 'owner-a',
      'note_id': 'note-1',
    });
    expect(requests[1].url.queryParameters['user_id'], 'eq.owner-a');

    await _authenticate(client, accountId: 'owner-b');
    await expectLater(
      repository.setPinned(
        noteId: 'note-1',
        pinned: true,
        expectedAccountId: 'owner-a',
      ),
      throwsStateError,
    );
    expect(requests, hasLength(2));
  });

  test('project note writes require editor capability', () async {
    final now = DateTime.utc(2026);
    final note = WorkspaceNote(
      id: 'note-1',
      ownerUserId: 'owner-a',
      projectId: 'project-1',
      title: 'Project note',
      markdownContent: 'content',
      createdAt: now,
      updatedAt: now,
      revision: 2,
    );
    for (final allowed in [false, true]) {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/rpc/can_edit_project')) {
            return _response(allowed, request);
          }
          return _response({
            'id': 'note-1',
            'owner_user_id': 'owner-a',
            'project_id': 'project-1',
            'created_by': 'owner-a',
            'title': 'Project note',
            'markdown_content': 'content',
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'revision': 3,
          }, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final repository = WorkspaceNoteRepository(client);

      if (!allowed) {
        await expectLater(
          repository.save(note, expectedAccountId: 'owner-a'),
          throwsStateError,
        );
        expect(requests.any((request) => request.method == 'PATCH'), isFalse);
      } else {
        final result = await repository.save(
          note,
          expectedAccountId: 'owner-a',
        );
        expect((result as WorkspaceNoteSaveSuccess).note.revision, 3);
        expect(requests.any((request) => request.method == 'PATCH'), isTrue);
      }
    }
  });

  test('project folder writes require edit membership', () async {
    for (final allowed in [false, true]) {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/rpc/can_edit_project')) {
            return _response(allowed, request);
          }
          return _response({
            'id': 'folder-1',
            'owner_user_id': 'owner-a',
            'project_id': 'project-1',
            'name': 'Research',
            'sort_order': 0,
            'created_at': '2026-10-01T00:00:00Z',
            'updated_at': '2026-10-01T00:00:00Z',
          }, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final repository = WorkspaceNoteRepository(client);

      if (!allowed) {
        await expectLater(
          repository.createFolder(
            name: 'Research',
            projectId: 'project-1',
            expectedAccountId: 'owner-a',
          ),
          throwsStateError,
        );
        expect(
          requests.any(
            (request) => request.url.path.endsWith('/workspace_note_folders'),
          ),
          isFalse,
        );
      } else {
        final folder = await repository.createFolder(
          name: 'Research',
          projectId: 'project-1',
          expectedAccountId: 'owner-a',
        );
        expect(folder.projectId, 'project-1');
        expect(
          requests.any(
            (request) => request.url.path.endsWith('/workspace_note_folders'),
          ),
          isTrue,
        );
      }
      final permissionRequest = requests.singleWhere(
        (request) => request.url.path.endsWith('/rpc/can_edit_project'),
      );
      expect(jsonDecode(permissionRequest.body), {'p_project_id': 'project-1'});
    }
  });

  test(
    'renames a project folder through the editor membership check',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/rpc/can_edit_project')) {
            return _response(true, request);
          }
          if (request.method == 'GET') {
            return _response({
              'id': 'folder-1',
              'owner_user_id': 'owner-b',
              'project_id': 'project-1',
            }, request);
          }
          return _response({'id': 'folder-1'}, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      await WorkspaceNoteRepository(client).renameFolder(
        folderId: 'folder-1',
        name: '  Research  ',
        expectedAccountId: 'owner-a',
      );

      final renameRequest = requests.singleWhere(
        (request) => request.method == 'PATCH',
      );
      expect(jsonDecode(renameRequest.body), {'name': 'Research'});
      expect(
        requests
            .singleWhere(
              (request) => request.url.path.endsWith('/rpc/can_edit_project'),
            )
            .body,
        jsonEncode({'p_project_id': 'project-1'}),
      );
    },
  );

  test('moving a project note rejects a folder in another scope', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/rpc/can_edit_project')) {
          return _response(true, request);
        }
        if (request.url.path.endsWith('/workspace_notes')) {
          return _response({
            'id': 'note-1',
            'owner_user_id': 'owner-a',
            'project_id': 'project-1',
          }, request);
        }
        return _response({
          'id': 'folder-2',
          'owner_user_id': 'owner-a',
          'project_id': 'project-2',
        }, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    await expectLater(
      WorkspaceNoteRepository(client).moveNoteToFolder(
        noteId: 'note-1',
        folderId: 'folder-2',
        expectedAccountId: 'owner-a',
      ),
      throwsStateError,
    );
    expect(requests.any((request) => request.method == 'PATCH'), isFalse);
  });

  test('moving a folder beneath its descendant is rejected', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/rpc/can_edit_project')) {
          return _response(true, request);
        }
        if (request.url.path.endsWith('/workspace_note_folders') &&
            request.url.queryParameters['id'] == 'eq.folder-a') {
          return _response({
            'id': 'folder-a',
            'owner_user_id': 'owner-a',
            'project_id': 'project-1',
            'parent_folder_id': null,
          }, request);
        }
        if (request.url.path.endsWith('/workspace_note_folders')) {
          return _response({
            'id': 'folder-b',
            'owner_user_id': 'owner-a',
            'project_id': 'project-1',
            'parent_folder_id': 'folder-a',
          }, request);
        }
        return _response({'id': 'folder-a'}, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    await expectLater(
      WorkspaceNoteRepository(client).moveFolder(
        folderId: 'folder-a',
        parentFolderId: 'folder-b',
        expectedAccountId: 'owner-a',
      ),
      throwsStateError,
    );
    expect(requests.any((request) => request.method == 'PATCH'), isFalse);
  });

  test('private folders reject parents owned by another account', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return _response({
          'id': 'foreign-folder',
          'owner_user_id': 'owner-b',
          'project_id': null,
        }, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    await expectLater(
      WorkspaceNoteRepository(client).createFolder(
        name: 'Child',
        parentFolderId: 'foreign-folder',
        expectedAccountId: 'owner-a',
      ),
      throwsStateError,
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
  });

  test(
    'unlinking a project note requests scope rehome and returns its job ID',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return _response({
              'id': 'note-1',
              'owner_user_id': 'previous-owner',
              'project_id': 'project-1',
            }, request);
          }
          if (request.url.path.endsWith('/rpc/is_project_owner')) {
            return _response(true, request);
          }
          if (request.url.path.endsWith(
            '/rpc/request_workspace_note_attachment_scope_change',
          )) {
            return _response('rehome-job-1', request);
          }
          return _response([], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final jobId = await WorkspaceNoteRepository(client).setNoteProject(
        noteId: 'note-1',
        projectId: null,
        expectedAccountId: 'owner-a',
      );

      expect(jobId, 'rehome-job-1');
      final request = requests.singleWhere(
        (item) => item.url.path.endsWith(
          '/rpc/request_workspace_note_attachment_scope_change',
        ),
      );
      expect(jsonDecode(request.body), {
        'p_note_id': 'note-1',
        'p_target_project_id': null,
      });
      expect(requests.any((item) => item.method == 'PATCH'), isFalse);
      expect(
        requests
            .singleWhere(
              (item) => item.url.path.endsWith('/rpc/is_project_owner'),
            )
            .body,
        jsonEncode({'p_project_id': 'project-1'}),
      );
    },
  );

  test('loads and retries a failed Note scope rehome job', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith(
          '/workspace_note_attachment_rehome_jobs',
        )) {
          return _response({
            'id': 'rehome-job-9',
            'requested_by': 'owner-a',
            'status': 'failed',
            'attempt_count': 8,
            'last_error_code': 'COPY_FAILED',
          }, request);
        }
        if (request.url.path.endsWith(
          '/rpc/retry_workspace_note_attachment_rehome',
        )) {
          return _response(true, request);
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final repository = WorkspaceNoteRepository(client);

    final job = await repository.getNoteScopeChangeStatus(
      noteId: 'note-1',
      expectedAccountId: 'owner-a',
    );
    await repository.retryNoteScopeChange(
      jobId: job!.jobId,
      expectedAccountId: 'owner-a',
    );

    expect(job.status.name, 'failed');
    expect(job.attemptCount, 8);
    expect(job.lastErrorCode, 'COPY_FAILED');
    final statusRequest = requests.singleWhere(
      (request) =>
          request.url.path.endsWith('/workspace_note_attachment_rehome_jobs'),
    );
    expect(
      statusRequest.url.queryParameters['job_kind'],
      'eq.note_scope_change',
    );
    expect(statusRequest.url.queryParameters['note_id'], 'eq.note-1');
    expect(statusRequest.url.queryParameters['requested_by'], 'eq.owner-a');
    final retryRequest = requests.singleWhere(
      (request) => request.url.path.endsWith(
        '/rpc/retry_workspace_note_attachment_rehome',
      ),
    );
    expect(jsonDecode(retryRequest.body), {'p_job_id': 'rehome-job-9'});
  });

  test(
    'project note scope controls require current project ownership',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith(
            '/workspace_note_attachment_rehome_jobs',
          )) {
            return _response([], request);
          }
          if (request.url.path.endsWith('/workspace_notes')) {
            return _response({
              'owner_user_id': 'owner-b',
              'project_id': 'project-1',
              'deleted_at': null,
            }, request);
          }
          if (request.url.path.endsWith('/rpc/is_project_owner')) {
            return _response(false, request);
          }
          throw StateError('Unexpected request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final allowed = await WorkspaceNoteRepository(client)
          .canManageNoteScopeChange(
            noteId: 'note-1',
            expectedAccountId: 'owner-a',
          );

      expect(allowed, isFalse);
      expect(
        requests
            .singleWhere(
              (request) => request.url.path.endsWith('/rpc/is_project_owner'),
            )
            .body,
        jsonEncode({'p_project_id': 'project-1'}),
      );
    },
  );

  test(
    'scope manager can recover a pending job after project ownership changes',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith(
            '/workspace_note_attachment_rehome_jobs',
          )) {
            return _response({
              'id': 'rehome-job-10',
              'requested_by': 'owner-a',
              'status': 'pending',
              'attempt_count': 1,
            }, request);
          }
          throw StateError('Unexpected request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final allowed = await WorkspaceNoteRepository(client)
          .canManageNoteScopeChange(
            noteId: 'note-1',
            expectedAccountId: 'owner-a',
          );

      expect(allowed, isTrue);
    },
  );

  test(
    'lists owned and editable projects, including empty destinations',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/projects')) {
            return _response([
              {'id': 'owned', 'name': 'Owned project', 'owner_id': 'owner-a'},
              {
                'id': 'editable-empty',
                'name': 'Empty destination',
                'owner_id': 'owner-b',
              },
              {'id': 'read-only', 'name': 'Read only', 'owner_id': 'owner-c'},
            ], request);
          }
          if (request.url.path.endsWith('/workspace_members')) {
            return _response([
              {'project_id': 'editable-empty', 'role': 'editor'},
              {'project_id': 'read-only', 'role': 'viewer'},
            ], request);
          }
          throw StateError('Unexpected request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final projects = await WorkspaceNoteRepository(
        client,
      ).listEditableNoteProjectScopes(expectedAccountId: 'owner-a');

      expect(projects.map((project) => project.id), [
        'owned',
        'editable-empty',
      ]);
      expect(projects.last.name, 'Empty destination');
      final membershipRequest = requests.singleWhere(
        (request) => request.url.path.endsWith('/workspace_members'),
      );
      expect(membershipRequest.url.queryParameters['user_id'], 'eq.owner-a');
      expect(requests, hasLength(2));
    },
  );
}
