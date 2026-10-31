import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _authenticate(SupabaseClient client, String accountId) async {
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

http.Response _zeroRows(http.Request request) => http.Response(
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

Map<String, dynamic> _note(String id, String ownerId) => {
  'id': id,
  'owner_user_id': ownerId,
  'title': 'A Note',
  'markdown_content': '# Private',
  'created_at': '2026-10-11T00:00:00Z',
  'updated_at': '2026-10-11T00:00:00Z',
};

Map<String, dynamic> _databaseNote({
  required String id,
  required String ownerId,
  required String title,
  required String markdown,
  required int revision,
}) => {
  'id': id,
  'owner_user_id': ownerId,
  'title': title,
  'markdown_content': markdown,
  'created_at': '2026-10-11T00:00:00Z',
  'updated_at': '2026-10-11T00:00:00Z',
  'revision': revision,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tracks auth recovery, list/create, and account changes', () async {
    final requests = <http.Request>[];
    late final SupabaseClient client;
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          final inserted = jsonDecode(request.body) as Map<String, dynamic>;
          return _response(inserted, request);
        }
        final ownerId =
            request.url.queryParameters['owner_user_id']?.substring(3) ??
            client.auth.currentUser!.id;
        if (request.method == 'PATCH' ||
            request.url.queryParameters.containsKey('title')) {
          return _response([], request);
        }
        return http.Response(
          jsonEncode([_note('note-$ownerId', ownerId)]),
          200,
          request: request,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-0/1',
          },
        );
      }),
    );
    addTearDown(client.dispose);
    SupabaseClient? activeClient;
    final authEvents = StreamController<User?>.broadcast();
    authEvents.add(null);
    addTearDown(authEvents.close);
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWith((ref) => activeClient),
        authUserProvider.overrideWith((ref) => authEvents.stream),
      ],
    );
    addTearDown(container.dispose);

    // Supply the cloud client after the Notes provider has been initialized.
    final notes = container.read(workspaceNotesProvider);
    expect(notes.accountId, isNull);
    await _authenticate(client, 'owner-a');
    activeClient = client;
    container.invalidate(supabaseClientProvider);
    await Future<void>.delayed(Duration.zero);
    authEvents.add(client.auth.currentSession?.user);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(workspaceNotesProvider).accountId, 'owner-a');
    await container.read(workspaceNotesProvider.notifier).load();
    expect(
      container.read(workspaceNotesProvider).notes,
      isNotEmpty,
      reason:
          'error: ${container.read(workspaceNotesProvider).error}; requests: ${requests.map((request) => request.url).toList()}',
    );
    expect(
      container.read(workspaceNotesProvider).notes.single.ownerUserId,
      'owner-a',
    );
    expect(
      requests.first.url.queryParameters.containsKey('owner_user_id'),
      isFalse,
    );

    final created = await container
        .read(workspaceNotesProvider.notifier)
        .createNote();
    expect(created?.ownerUserId, 'owner-a');
    expect(requests.any((request) => request.method == 'POST'), isTrue);

    await _authenticate(client, 'owner-b');
    authEvents.add(client.auth.currentSession?.user);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(workspaceNotesProvider).accountId, 'owner-b');
    expect(
      container.read(workspaceNotesProvider).notes,
      everyElement(
        predicate(
          (Object? note) =>
              note is WorkspaceNote && note.ownerUserId == 'owner-b',
        ),
      ),
    );
    expect(
      container.read(workspaceNotesProvider).notes,
      isNot(
        contains(
          predicate(
            (Object? note) =>
                note is WorkspaceNote && note.ownerUserId == 'owner-a',
          ),
        ),
      ),
    );
    container.dispose();
  });

  test('stores a returned daily note in the current account state', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith(
          '/rpc/get_or_create_workspace_daily_note',
        )) {
          return _response({
            'id': 'daily-note-id',
            'owner_user_id': 'owner-a',
            'created_by': 'owner-a',
            'title': '2026-10-21',
            'markdown_content': '',
            'created_at': '2026-10-21T00:00:00Z',
            'updated_at': '2026-10-21T00:00:00Z',
            'revision': 1,
            'project_id': 'project-1',
            'daily_note_date': '2026-10-21',
            'deleted_at': null,
          }, request);
        }
        return _response([], request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client, 'owner-a');
    final notifier = WorkspaceNotesNotifier(
      client,
      WorkspaceNoteRepository(client),
    );
    addTearDown(notifier.dispose);
    await notifier.load();

    final note = await notifier.getOrCreateDailyNote(
      localDate: DateTime(2026, 10, 21, 23, 45),
      projectId: 'project-1',
    );

    expect(note?.id, 'daily-note-id');
    expect(notifier.state.notes, contains(note));
    expect(
      requests.any(
        (request) => request.url.path.endsWith(
          '/rpc/get_or_create_workspace_daily_note',
        ),
      ),
      isTrue,
    );
  });

  test('ignores a daily note response after the account changes', () async {
    final pendingResponse = Completer<http.Response>();
    late http.Request dailyRequest;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith(
          '/rpc/get_or_create_workspace_daily_note',
        )) {
          dailyRequest = request;
          return pendingResponse.future;
        }
        return _response([], request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client, 'owner-a');
    final notifier = WorkspaceNotesNotifier(
      client,
      WorkspaceNoteRepository(client),
    );
    addTearDown(notifier.dispose);
    await notifier.load();

    final request = notifier.getOrCreateDailyNote(
      localDate: DateTime(2026, 10, 21),
      projectId: 'project-1',
    );
    await Future<void>.delayed(Duration.zero);
    await _authenticate(client, 'owner-b');
    notifier.refreshAccount();
    pendingResponse.complete(
      _response({
        'id': 'account-a-daily-note',
        'owner_user_id': 'owner-a',
        'created_by': 'owner-a',
        'title': '2026-10-21',
        'markdown_content': 'private body',
        'created_at': '2026-10-21T00:00:00Z',
        'updated_at': '2026-10-21T00:00:00Z',
        'revision': 1,
        'project_id': null,
        'daily_note_date': '2026-10-21',
        'deleted_at': null,
      }, dailyRequest),
    );

    expect(await request, isNull);
    expect(notifier.state.accountId, 'owner-b');
    expect(notifier.state.notes, isEmpty);
  });

  test(
    'allows an authorized project editor to save another member note',
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
          if (request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return _response({
              ..._databaseNote(
                id: 'shared-note',
                ownerId: 'owner-b',
                title: body['title'] as String,
                markdown: body['markdown_content'] as String,
                revision: body['revision'] as int,
              ),
              'project_id': 'project-1',
            }, request);
          }
          return _response([], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, 'editor-a');
      final notifier = WorkspaceNotesNotifier(
        client,
        WorkspaceNoteRepository(client),
      );
      addTearDown(notifier.dispose);

      final result = await notifier.saveNote(
        WorkspaceNote(
          id: 'shared-note',
          ownerUserId: 'owner-b',
          projectId: 'project-1',
          title: 'Shared',
          markdownContent: 'updated body',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          revision: 2,
        ),
      );

      expect(result, isA<WorkspaceNoteSaveSuccess>());
      expect((result as WorkspaceNoteSaveSuccess).note.ownerUserId, 'owner-b');
      expect(notifier.state.error, isNull);
      expect(requests.any((request) => request.method == 'PATCH'), isTrue);
    },
  );

  test('preserves a typed conflict without exposing backend details', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH') return _zeroRows(request);
        if (request.url.queryParameters.containsKey('id')) {
          return _response({
            ..._note('note-1', 'owner-a'),
            'revision': 5,
          }, request);
        }
        return _response([], request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client, 'owner-a');
    final notifier = WorkspaceNotesNotifier(
      client,
      WorkspaceNoteRepository(client),
    );
    addTearDown(notifier.dispose);
    final outcome = await notifier.saveNote(
      WorkspaceNote(
        id: 'note-1',
        ownerUserId: 'owner-a',
        title: 'Draft',
        markdownContent: 'local body',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        revision: 2,
      ),
    );
    expect(outcome, isA<WorkspaceNoteSaveConflict>());
    expect(notifier.state.conflicts['note-1']?.remoteNote.revision, 5);
    expect(notifier.state.error, isA<WorkspaceNoteConflictError>());
    expect(
      workspaceNotesFailureMessage(notifier.state.error, accountId: 'owner-a'),
      isNot(contains('PGRST')),
    );
  });

  test('maps known backend errors without exposing response details', () {
    final missingTable = PostgrestException(
      message: 'sensitive database response',
      code: '42P01',
      details: 'sensitive detail',
    );
    final denied = PostgrestException(
      message: 'sensitive database response',
      code: '42501',
    );
    expect(
      workspaceNotesFailureMessage(missingTable, accountId: 'owner'),
      contains('migration'),
    );
    expect(
      workspaceNotesFailureMessage(denied, accountId: 'owner'),
      contains('denied'),
    );
    expect(
      workspaceNotesFailureMessage(missingTable, accountId: 'owner'),
      isNot(contains('sensitive')),
    );
    expect(
      workspaceNotesFailureMessage(null, accountId: null),
      contains('Sign in'),
    );
    expect(
      workspaceNotesFailureMessage(
        StateError('Encrypted Notes storage is unavailable.'),
        accountId: 'owner',
      ),
      contains('device storage'),
    );
    expect(
      workspaceNotesFailureMessage(
        AuthRetryableFetchException(message: 'Network unavailable.'),
        accountId: 'owner',
      ),
      contains('connection'),
    );
  });

  test(
    'keeps deletion and restoration state owner-scoped and revision-safe',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return _response({
              ..._note('note-1', 'owner-a'),
              'revision': body['revision'],
              'deleted_at': body['deleted_at'],
              'updated_at': body['updated_at'],
            }, request);
          }
          return _response([], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, 'owner-a');
      final notifier = WorkspaceNotesNotifier(
        client,
        WorkspaceNoteRepository(client),
      );
      addTearDown(notifier.dispose);
      final note = WorkspaceNote(
        id: 'note-1',
        ownerUserId: 'owner-a',
        title: 'A Note',
        markdownContent: 'private',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        revision: 2,
      );
      expect(await notifier.deleteNote(note.copyWith()), isTrue);
      expect(notifier.state.notes, isEmpty);
      expect(notifier.state.trashNotes.single.deletedAt, isNotNull);
      final deleted = notifier.state.trashNotes.single;
      expect(
        await notifier.deleteNote(
          WorkspaceNote(
            id: note.id,
            ownerUserId: 'owner-b',
            title: note.title,
            markdownContent: note.markdownContent,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            revision: note.revision,
          ),
        ),
        isFalse,
      );
      expect(await notifier.restoreNote(deleted), isTrue);
      expect(notifier.state.trashNotes, isEmpty);
      expect(notifier.state.notes.single.revision, 4);
      expect(
        requests
            .where((request) => request.method == 'PATCH')
            .map((request) => request.url.queryParameters['revision']),
        ['eq.2', 'eq.3'],
      );
      expect(
        requests
            .where((request) => request.method == 'PATCH')
            .every(
              (request) =>
                  !request.url.queryParameters.containsKey('owner_user_id'),
            ),
        isTrue,
      );
    },
  );

  test(
    'rename applies returned rows together and refreshes the active list',
    () async {
      final requests = <http.Request>[];
      const ownerId = 'owner-a';
      const targetId = '123e4567-e89b-12d3-a456-426614174000';
      const sourceId = '123e4567-e89b-12d3-a456-426614174001';
      const otherId = '123e4567-e89b-12d3-a456-426614174002';
      final initialRows = [
        _databaseNote(
          id: targetId,
          ownerId: ownerId,
          title: 'Target',
          markdown: '',
          revision: 1,
        ),
        _databaseNote(
          id: sourceId,
          ownerId: ownerId,
          title: 'Source',
          markdown: '[[Target]]',
          revision: 2,
        ),
        _databaseNote(
          id: otherId,
          ownerId: ownerId,
          title: 'Other',
          markdown: '',
          revision: 1,
        ),
      ];
      final updatedRows = [
        _databaseNote(
          id: targetId,
          ownerId: ownerId,
          title: 'Renamed',
          markdown: '',
          revision: 2,
        ),
        _databaseNote(
          id: sourceId,
          ownerId: ownerId,
          title: 'Source',
          markdown: '[[Renamed]]',
          revision: 3,
        ),
      ];
      var renamed = false;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith(
            '/rpc/rename_workspace_notes_with_links',
          )) {
            renamed = true;
            return _response(updatedRows, request);
          }
          if (request.url.queryParameters.containsKey('title')) {
            return _response([], request);
          }
          return _response(
            renamed ? [...updatedRows, initialRows.last] : initialRows,
            request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, ownerId);
      final notifier = WorkspaceNotesNotifier(
        client,
        WorkspaceNoteRepository(client),
      );
      addTearDown(notifier.dispose);
      await notifier.load();

      final result = await notifier.renameNoteWithLinks(
        noteId: targetId,
        title: 'Renamed',
      );

      expect(result, isA<WorkspaceNoteRenameSuccess>());
      expect(notifier.state.notes.map((note) => note.id), [
        targetId,
        sourceId,
        otherId,
      ]);
      expect(notifier.state.notes.first.title, 'Renamed');
      expect(notifier.state.notes[1].markdownContent, '[[Renamed]]');
      expect(notifier.state.renamingNoteIds, isEmpty);
      expect(
        requests.where(
          (request) => request.url.path.endsWith(
            '/rpc/rename_workspace_notes_with_links',
          ),
        ),
        hasLength(1),
      );
      expect(
        requests.where((request) => request.method == 'GET').length,
        greaterThan(1),
      );
    },
  );

  test('pre-rename load cannot overwrite a committed rename', () async {
    const ownerId = 'owner-a';
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    const sourceId = '123e4567-e89b-12d3-a456-426614174001';
    final initialRows = [
      _databaseNote(
        id: targetId,
        ownerId: ownerId,
        title: 'Target',
        markdown: '',
        revision: 1,
      ),
      _databaseNote(
        id: sourceId,
        ownerId: ownerId,
        title: 'Source',
        markdown: '[[Target]]',
        revision: 2,
      ),
    ];
    final updatedRows = [
      _databaseNote(
        id: targetId,
        ownerId: ownerId,
        title: 'Renamed',
        markdown: '',
        revision: 2,
      ),
      _databaseNote(
        id: sourceId,
        ownerId: ownerId,
        title: 'Source',
        markdown: '[[Renamed]]',
        revision: 3,
      ),
    ];
    final renameResponse = Completer<http.Response>();
    final renameStarted = Completer<void>();
    final staleListResponse = Completer<http.Response>();
    final staleListStarted = Completer<void>();
    var listReads = 0;
    var renamed = false;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith(
          '/rpc/rename_workspace_notes_with_links',
        )) {
          renameStarted.complete();
          return renameResponse.future.then((response) {
            renamed = true;
            return response;
          });
        }
        if (request.url.queryParameters.containsKey('title')) {
          return _response([], request);
        }
        listReads++;
        if (listReads == 3) {
          staleListStarted.complete();
          return staleListResponse.future;
        }
        return _response(renamed ? updatedRows : initialRows, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client, ownerId);
    final notifier = WorkspaceNotesNotifier(
      client,
      WorkspaceNoteRepository(client),
    );
    addTearDown(notifier.dispose);
    await notifier.load();

    final pendingRename = notifier.renameNoteWithLinks(
      noteId: targetId,
      title: 'Renamed',
    );
    await renameStarted.future;
    final staleLoad = notifier.load();
    await staleListStarted.future;
    renameResponse.complete(
      _response(
        updatedRows,
        http.Request(
          'POST',
          Uri.parse(
            'https://example.supabase.co/rest/v1/rpc/rename_workspace_notes_with_links',
          ),
        ),
      ),
    );
    final result = await pendingRename;
    staleListResponse.complete(
      _response(
        initialRows,
        http.Request(
          'GET',
          Uri.parse('https://example.supabase.co/rest/v1/workspace_notes'),
        ),
      ),
    );
    await staleLoad;

    expect(result, isA<WorkspaceNoteRenameSuccess>());
    expect(notifier.state.notes.first.title, 'Renamed');
    expect(notifier.state.notes.last.markdownContent, '[[Renamed]]');
  });

  test(
    'current load clears its indicator when authentication invalidates it',
    () async {
      const targetId = '123e4567-e89b-12d3-a456-426614174000';
      final pendingList = Completer<http.Response>();
      final listStarted = Completer<void>();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          if (request.url.queryParameters.containsKey('title')) {
            return _response([], request);
          }
          listStarted.complete();
          return pendingList.future;
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, 'owner-a');
      final notifier = WorkspaceNotesNotifier(null, null);
      addTearDown(notifier.dispose);
      final loadingCleared = Completer<void>();
      notifier.updateClient(client);
      notifier.addListener((state) {
        if (!state.loading && !loadingCleared.isCompleted) {
          loadingCleared.complete();
        }
      });
      await listStarted.future;
      expect(notifier.state.loading, isTrue);

      await _authenticate(client, 'owner-b');
      pendingList.complete(
        _response(
          [
            _databaseNote(
              id: targetId,
              ownerId: 'owner-a',
              title: 'Target',
              markdown: '',
              revision: 1,
            ),
          ],
          http.Request(
            'GET',
            Uri.parse('https://example.supabase.co/rest/v1/workspace_notes'),
          ),
        ),
      );
      await loadingCleared.future;

      expect(notifier.state.loading, isFalse);
    },
  );

  test('ambiguous legacy links block rename before RPC', () async {
    final requests = <http.Request>[];
    const ownerId = 'owner-a';
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    final rows = [
      _databaseNote(
        id: targetId,
        ownerId: ownerId,
        title: 'Duplicate',
        markdown: '',
        revision: 1,
      ),
      _databaseNote(
        id: '123e4567-e89b-12d3-a456-426614174001',
        ownerId: ownerId,
        title: 'Duplicate',
        markdown: '',
        revision: 1,
      ),
      _databaseNote(
        id: '123e4567-e89b-12d3-a456-426614174002',
        ownerId: ownerId,
        title: 'Source',
        markdown: '[[Duplicate]]',
        revision: 1,
      ),
    ];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.queryParameters.containsKey('title')) {
          return _response([], request);
        }
        return _response(rows, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client, ownerId);
    final notifier = WorkspaceNotesNotifier(
      client,
      WorkspaceNoteRepository(client),
    );
    addTearDown(notifier.dispose);
    await notifier.load();
    final before = [...notifier.state.notes];

    final result = await notifier.renameNoteWithLinks(
      noteId: targetId,
      title: 'New',
    );

    expect(result, isA<WorkspaceNoteRenameBlocked>());
    expect((result! as WorkspaceNoteRenameBlocked).ambiguousSourceIds, {
      '123e4567-e89b-12d3-a456-426614174002',
    });
    expect(notifier.state.notes, before);
    expect(
      requests.any(
        (request) =>
            request.url.path.endsWith('/rpc/rename_workspace_notes_with_links'),
      ),
      isFalse,
    );
  });

  test(
    'conflict and unavailable rename outcomes preserve the notes list',
    () async {
      const targetId = '123e4567-e89b-12d3-a456-426614174000';
      const ownerId = 'owner-a';
      final rows = [
        _databaseNote(
          id: targetId,
          ownerId: ownerId,
          title: 'Target',
          markdown: '',
          revision: 1,
        ),
      ];
      final cases = <(String, Type, Type)>[
        (
          'workspace_notes_conflict',
          WorkspaceNoteRenameConflict,
          WorkspaceNoteConflictError,
        ),
        (
          'workspace_notes_unavailable',
          WorkspaceNoteRenameUnavailable,
          WorkspaceNoteUnavailableError,
        ),
      ];
      for (final item in cases) {
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-publishable-key',
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith(
              '/rpc/rename_workspace_notes_with_links',
            )) {
              return http.Response(
                jsonEncode({
                  'code': 'P0001',
                  'message': item.$1,
                  'details': null,
                  'hint': null,
                }),
                400,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.queryParameters.containsKey('title')) {
              return _response([], request);
            }
            return _response(rows, request);
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client, ownerId);
        final notifier = WorkspaceNotesNotifier(
          client,
          WorkspaceNoteRepository(client),
        );
        addTearDown(notifier.dispose);
        await notifier.load();
        final before = [...notifier.state.notes];

        final result = await notifier.renameNoteWithLinks(
          noteId: targetId,
          title: 'New',
        );

        expect(result.runtimeType, item.$2);
        expect(notifier.state.notes, before);
        expect(notifier.state.error.runtimeType, item.$3);
        expect(notifier.state.renamingNoteIds, isEmpty);
      }
    },
  );

  test('network failure preserves notes and remains retryable', () async {
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    const ownerId = 'owner-a';
    final rows = [
      _databaseNote(
        id: targetId,
        ownerId: ownerId,
        title: 'Target',
        markdown: '',
        revision: 1,
      ),
    ];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith(
          '/rpc/rename_workspace_notes_with_links',
        )) {
          throw http.ClientException('temporary network failure');
        }
        if (request.url.queryParameters.containsKey('title')) {
          return _response([], request);
        }
        return _response(rows, request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client, ownerId);
    final notifier = WorkspaceNotesNotifier(
      client,
      WorkspaceNoteRepository(client),
    );
    addTearDown(notifier.dispose);
    await notifier.load();
    final before = [...notifier.state.notes];

    final result = await notifier.renameNoteWithLinks(
      noteId: targetId,
      title: 'New',
    );

    expect(result, isA<WorkspaceNoteRenameFailure>());
    expect(notifier.state.notes, before);
    expect(notifier.state.error, isA<http.ClientException>());
    expect(notifier.state.renamingNoteIds, isEmpty);
  });

  test(
    'folder and pin providers reject delayed data after account switch',
    () async {
      final folderResponse = Completer<http.Response>();
      final pinResponse = Completer<http.Response>();
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final isOwnerA =
              request.url.queryParameters['owner_user_id'] == 'eq.owner-a' ||
              request.url.queryParameters['user_id'] == 'eq.owner-a';
          if (request.url.path.endsWith('/workspace_note_folders') &&
              isOwnerA) {
            return folderResponse.future;
          }
          if (request.url.path.endsWith('/workspace_note_preferences') &&
              isOwnerA) {
            return pinResponse.future;
          }
          return _response([], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, 'owner-a');
      final authEvents = StreamController<User?>.broadcast();
      addTearDown(authEvents.close);
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWith((ref) => client),
          authUserProvider.overrideWith((ref) => authEvents.stream),
        ],
      );
      addTearDown(container.dispose);
      final folderSubscription = container.listen(
        workspaceNoteFoldersProvider('owner-a'),
        (_, _) {},
      );
      final pinSubscription = container.listen(
        workspacePinnedNotesProvider('owner-a'),
        (_, _) {},
      );
      authEvents.add(client.auth.currentUser);

      for (var attempt = 0; attempt < 10 && requests.length < 2; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(requests, hasLength(2));
      expect(
        container.read(workspaceNoteFoldersProvider('owner-a')).isLoading,
        isTrue,
      );
      expect(
        container.read(workspacePinnedNotesProvider('owner-a')).isLoading,
        isTrue,
      );

      await _authenticate(client, 'owner-b');
      authEvents.add(client.auth.currentUser);
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        container.read(workspaceNoteFoldersProvider('owner-a')).hasError,
        isTrue,
      );
      expect(
        container.read(workspacePinnedNotesProvider('owner-a')).hasError,
        isTrue,
      );

      final oldFolderRequest = requests.singleWhere(
        (request) => request.url.path.endsWith('/workspace_note_folders'),
      );
      final oldPinRequest = requests.singleWhere(
        (request) => request.url.path.endsWith('/workspace_note_preferences'),
      );
      folderResponse.complete(_response([], oldFolderRequest));
      pinResponse.complete(_response([], oldPinRequest));
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        await container.read(workspaceNoteFoldersProvider('owner-b').future),
        isEmpty,
      );
      expect(
        await container.read(workspacePinnedNotesProvider('owner-b').future),
        isEmpty,
      );
      expect(
        container.read(workspaceNoteFoldersProvider('owner-a')).hasError,
        isTrue,
      );
      expect(
        container.read(workspacePinnedNotesProvider('owner-a')).hasError,
        isTrue,
      );
      folderSubscription.close();
      pinSubscription.close();
    },
  );

  test('account changes invalidate a pending rename response', () async {
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    final response = Completer<http.Response>();
    late final SupabaseClient client;
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith(
          '/rpc/rename_workspace_notes_with_links',
        )) {
          return response.future;
        }
        if (request.url.queryParameters.containsKey('title')) {
          return _response([], request);
        }
        final owner =
            request.url.queryParameters['owner_user_id']?.substring(3) ??
            client.auth.currentUser!.id;
        return _response([
          _databaseNote(
            id: targetId,
            ownerId: owner,
            title: 'Target',
            markdown: '',
            revision: 1,
          ),
        ], request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client, 'owner-a');
    final notifier = WorkspaceNotesNotifier(
      client,
      WorkspaceNoteRepository(client),
    );
    addTearDown(notifier.dispose);
    await notifier.load();
    final pending = notifier.renameNoteWithLinks(
      noteId: targetId,
      title: 'New',
    );
    await Future<void>.delayed(Duration.zero);
    await _authenticate(client, 'owner-b');
    notifier.refreshAccount();
    await notifier.load();
    response.complete(
      _response(
        [
          _databaseNote(
            id: targetId,
            ownerId: 'owner-a',
            title: 'New',
            markdown: '',
            revision: 2,
          ),
        ],
        http.Request(
          'POST',
          Uri.parse(
            'https://example.supabase.co/rest/v1/rpc/rename_workspace_notes_with_links',
          ),
        ),
      ),
    );

    expect(await pending, isNull);
    expect(notifier.state.accountId, 'owner-b');
    expect(
      notifier.state.notes,
      everyElement(
        predicate(
          (Object? note) =>
              note is WorkspaceNote && note.ownerUserId == 'owner-b',
        ),
      ),
    );
    expect(notifier.state.renamingNoteIds, isEmpty);
  });
}
