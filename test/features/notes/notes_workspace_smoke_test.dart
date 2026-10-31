import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/presentation/notes_workspace_screen.dart';
import 'package:varian/features/notes/state/notes_offline_provider.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<SupabaseClient> _authenticatedClient(_NotesApiMock api) async {
  const accountId = 'notes-smoke-account';
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
      'refresh_token': 'test-refresh-token',
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

class _NotesApiMock {
  final Map<String, Map<String, dynamic>> rows = {};

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/workspace_notes')) {
      if (request.method == 'GET') {
        final idFilter = request.url.queryParameters['id'];
        if (idFilter == null) {
          return _jsonResponse(rows.values.toList(growable: false), request);
        }
        final id = idFilter.startsWith('eq.') ? idFilter.substring(3) : '';
        final row = rows[id];
        if (row == null) return http.Response('', 406, request: request);
        return _jsonResponse(row, request);
      }
      if (request.method == 'POST') {
        final incoming = Map<String, dynamic>.from(
          jsonDecode(request.body) as Map,
        );
        rows[incoming['id'] as String] = incoming;
        return _jsonResponse(incoming, request, statusCode: 201);
      }
    }
    return http.Response(
      jsonEncode({
        'message':
            'Unexpected mock request: ${request.method} ${request.url.path}',
      }),
      500,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }

  http.Response _jsonResponse(
    Object body,
    http.Request request, {
    int statusCode = 200,
  }) => http.Response(
    jsonEncode(body),
    statusCode,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

class _SmokeNotesNotifier extends WorkspaceNotesNotifier {
  _SmokeNotesNotifier(
    SupabaseClient super.client,
    WorkspaceNoteRepository super.repository,
  );

  @override
  Future<void> load() async {}
}

class _TestTabController extends ActiveDocumentTabController {
  _TestTabController(super.ref) : _ref = ref;

  final Ref _ref;

  @override
  Future<void> select(OpenDocumentTab tab) async {
    _ref.read(activeDocumentTabProvider.notifier).state = tab;
  }
}

GoRouter _router() => GoRouter(
  initialLocation: '/notes',
  routes: [
    GoRoute(path: '/notes', builder: (_, _) => const NotesWorkspaceScreen()),
    GoRoute(
      path: '/notes/:noteId',
      builder: (_, state) =>
          NotesWorkspaceScreen(selectedNoteId: state.pathParameters['noteId']),
    ),
  ],
);

Future<void> _settleSmoke(WidgetTester tester) async {
  for (var frame = 0; frame < 50; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) return;
  }
  fail('Notes workspace did not settle within five seconds.');
}

void main() {
  testWidgets('opens Notes with the synthetic account session', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _NotesApiMock();
    final client = await _authenticatedClient(api);
    expect(client.auth.currentUser?.id, 'notes-smoke-account');
    final router = _router();
    addTearDown(router.dispose);
    final repository = WorkspaceNoteRepository(client);
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWith((ref) => client),
        notesOfflineServiceProvider.overrideWith((ref) => null),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
        workspaceNotesProvider.overrideWith(
          (ref) => _SmokeNotesNotifier(client, repository),
        ),
        workspaceScopedNoteFoldersProvider.overrideWith(
          (ref, scope) async => const [],
        ),
        workspacePinnedNotesProvider.overrideWith(
          (ref, accountId) async => const [],
        ),
        activeDocumentTabControllerProvider.overrideWith(
          (ref) => _TestTabController(ref),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _settleSmoke(tester);
    expect(find.text('Notes'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notes-workspace-search')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('New note'));
    await _settleSmoke(tester);
    expect(find.byKey(const ValueKey('note-title-field')), findsOneWidget);
    expect(api.rows, hasLength(1));
    final created = WorkspaceNote.fromJson(api.rows.values.single);
    expect(created.ownerUserId, 'notes-smoke-account');
    expect(created.projectId, isNull);
    expect(find.text('Private'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
