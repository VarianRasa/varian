import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/notes/data/notes_canvas_repository.dart';
import 'package:varian/features/notes/domain/notes_canvas_board.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';
import 'package:varian/features/notes/presentation/notes_canvas_screen.dart';
import 'package:varian/features/notes/state/notes_canvas_provider.dart';
import 'package:varian/features/notes/state/notes_offline_provider.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

class _WorkspaceNotes extends WorkspaceNotesNotifier {
  _WorkspaceNotes() : super(null, null);

  @override
  Future<void> load() async {}
}

class _CanvasRepository extends NotesCanvasRepository {
  factory _CanvasRepository(Map<String, NotesCanvasBoard> boards) {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    return _CanvasRepository._(boards, client);
  }

  _CanvasRepository._(this.boards, this.client) : super(client);

  final SupabaseClient client;
  final Map<String, NotesCanvasBoard> boards;
  final List<String> requestedAccounts = [];

  @override
  Future<NotesCanvasBoard> getBoard({
    required String boardId,
    required String expectedAccountId,
  }) async {
    requestedAccounts.add(expectedAccountId);
    return boards[expectedAccountId]!;
  }
}

NotesCanvasBoard _board({
  required String boardId,
  required String ownerId,
  required String title,
  String? projectId,
}) {
  final document = NotesCanvasDocument.fromState(
    boardId,
    NotesCanvasBoardState.empty(),
  );
  final now = DateTime.utc(2026, 10, 21);
  return NotesCanvasBoard(
    id: boardId,
    ownerUserId: ownerId,
    createdBy: ownerId,
    projectId: projectId,
    title: title,
    state: document.boardState,
    crdtSnapshot: document.snapshotState(),
    versionVector: document.versionVector,
    revision: 1,
    snapshotServerSequence: 0,
    createdAt: now,
    updatedAt: now,
  );
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
  isAnonymous: false,
);

void main() {
  const boardId = '70000000-0000-4000-8000-000000000001';

  testWidgets('reloads board data on account changes and gates locked edits', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final events = StreamController<User?>.broadcast();
    addTearDown(events.close);
    final repository = _CanvasRepository({
      'account-a': _board(
        boardId: boardId,
        ownerId: 'account-a',
        title: 'Account A board',
      ),
      'account-b': _board(
        boardId: boardId,
        ownerId: 'account-b',
        title: 'Account B board',
      ),
    });
    addTearDown(() => repository.client.auth.stopAutoRefresh());
    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => events.stream),
        notesCanvasRepositoryProvider.overrideWithValue(repository),
        notesCanvasSyncRepositoryProvider.overrideWithValue(null),
        notesOfflineServiceProvider.overrideWithValue(null),
        workspaceNotesProvider.overrideWith((ref) => _WorkspaceNotes()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: const NotesCanvasScreen(boardId: boardId)),
      ),
    );
    await tester.pump();
    events.add(_user('account-a'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Account A board'), findsOneWidget);
    expect(
      find.textContaining('Set up or unlock encrypted Notes storage'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('notes-canvas-add-text')),
          )
          .onPressed,
      isNull,
    );

    events.add(_user('account-b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(repository.requestedAccounts, ['account-a', 'account-b']);
    expect(find.text('Account A board'), findsNothing);
    expect(find.text('Account B board'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clears a board when the requested project scope changes', (
    tester,
  ) async {
    final events = StreamController<User?>.broadcast();
    addTearDown(events.close);
    final repository = _CanvasRepository({
      'account-a': _board(
        boardId: boardId,
        ownerId: 'account-a',
        title: 'Project A board',
        projectId: 'project-a',
      ),
    });
    addTearDown(() => repository.client.auth.stopAutoRefresh());
    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => events.stream),
        notesCanvasRepositoryProvider.overrideWithValue(repository),
        notesCanvasSyncRepositoryProvider.overrideWithValue(null),
        notesOfflineServiceProvider.overrideWithValue(null),
        workspaceNotesProvider.overrideWith((ref) => _WorkspaceNotes()),
      ],
    );
    addTearDown(container.dispose);
    var projectId = 'project-a';
    late StateSetter updateScope;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateScope = setState;
              return NotesCanvasScreen(boardId: boardId, projectId: projectId);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    events.add(_user('account-a'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Project A board'), findsOneWidget);

    updateScope(() => projectId = 'project-b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Project A board'), findsNothing);
    expect(
      find.text(
        'This board or one of its linked notes is unavailable in this scope.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
