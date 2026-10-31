import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/presentation/notes_route_screen.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';
import '../../test_app.dart';

class _FakeTabController extends ActiveDocumentTabController {
  // ignore: use_super_parameters
  _FakeTabController(Ref ref) : _ref = ref, super(ref);

  final Ref _ref;

  @override
  Future<void> select(OpenDocumentTab tab) async {
    final accountId = _ref.read(workspaceNotesProvider).accountId;
    _ref.read(activeDocumentTabProvider.notifier).state = OpenDocumentTab(
      documentId: tab.documentId,
      name: tab.name,
      type: OpenDocumentTabType.note,
      ownerAccountId: accountId,
      noteProjectId: tab.noteProjectId,
    );
  }
}

class _NotesNotifier extends WorkspaceNotesNotifier {
  _NotesNotifier({this.note}) : super(null, null) {
    state = WorkspaceNotesState(
      accountId: 'account-1',
      notes: note == null ? const [] : [note!],
    );
  }

  final WorkspaceNote? note;
  int openCalls = 0;

  @override
  Future<WorkspaceNote?> openNote(String noteId) async {
    openCalls++;
    return note?.id == noteId ? note : null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final note = WorkspaceNote(
    id: 'note-1',
    ownerUserId: 'account-1',
    title: 'Private title',
    markdownContent: 'Private content',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  Future<({ProviderContainer container, _NotesNotifier notes, GoRouter router})>
  pumpRoute(
    WidgetTester tester, {
    WorkspaceNote? routeNote,
    Stream<User?>? authStream,
    Stream<User?> Function()? authStreamFactory,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notes = _NotesNotifier(note: routeNote);
    final container = ProviderContainer(
      overrides: [
        workspaceNotesProvider.overrideWith((ref) => notes),
        activeDocumentTabControllerProvider.overrideWith(
          (ref) => _FakeTabController(ref),
        ),
        authUserProvider.overrideWith(
          (ref) =>
              authStreamFactory?.call() ??
              authStream ??
              Stream.value(
                User(
                  id: 'account-1',
                  appMetadata: const {},
                  userMetadata: const {},
                  aud: 'authenticated',
                  createdAt: '2026-01-01T00:00:00Z',
                  isAnonymous: false,
                ),
              ),
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/notes/note-1',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('Canvas home')),
        ),
        GoRoute(
          path: '/notes/:noteId',
          builder: (context, state) =>
              NotesRouteScreen(noteId: state.pathParameters['noteId']!),
        ),
      ],
    );
    addTearDown(() {
      router.dispose();
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(MaterialApp.router(routerConfig: router)),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return (container: container, notes: notes, router: router);
  }

  testWidgets('waits for auth state before resolving the note', (tester) async {
    final authController = StreamController<User?>();
    addTearDown(authController.close);
    await pumpRoute(
      tester,
      routeNote: note,
      authStream: authController.stream,
      settle: false,
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Private content'), findsNothing);

    authController.add(
      User(
        id: 'account-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
        isAnonymous: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-markdown-editor')), findsOneWidget);
    expect(find.text('Private content'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries when auth reload settles with the same user', (
    tester,
  ) async {
    final authController = StreamController<User?>();
    addTearDown(authController.close);
    User user() => User(
      id: 'account-1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
      isAnonymous: false,
    );

    final result = await pumpRoute(
      tester,
      routeNote: note,
      authStreamFactory: () async* {
        yield user();
        await authController.stream.first;
        yield user();
      },
      settle: false,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('note-markdown-editor')), findsOneWidget);
    final callsBeforeReload = result.notes.openCalls;

    result.container.invalidate(authUserProvider);
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    authController.add(user());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('note-markdown-editor')), findsOneWidget);
    expect(result.notes.openCalls, greaterThan(callsBeforeReload));
    expect(find.text('Private content'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('directly opened Note returns to Canvas when Back is pressed', (
    tester,
  ) async {
    await pumpRoute(tester, routeNote: note);

    await tester.tap(find.byTooltip('Back to Canvas'));
    await tester.pumpAndSettle();

    expect(find.text('Canvas home'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-markdown-editor')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the standalone private note without Canvas controls', (
    tester,
  ) async {
    final result = await pumpRoute(tester, routeNote: note);

    expect(find.text('Private Note'), findsOneWidget);
    expect(find.byTooltip('Back to Canvas'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-markdown-editor')), findsOneWidget);
    expect(find.text('Private content'), findsNWidgets(2));
    expect(find.text('Workspace'), findsNothing);
    expect(find.byKey(const ValueKey('canvas-undo')), findsNothing);
    expect(result.notes.openCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not expose content for unavailable note IDs', (
    tester,
  ) async {
    await pumpRoute(tester);

    expect(
      find.text('This Note is unavailable for this account.'),
      findsOneWidget,
    );
    expect(find.text('Private title'), findsNothing);
    expect(find.text('Private content'), findsNothing);
  });

  testWidgets('opens a project note owned by another member', (tester) async {
    final sharedNote = WorkspaceNote(
      id: note.id,
      ownerUserId: 'other-account',
      title: 'Shared project title',
      markdownContent: 'Shared project content',
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      projectId: 'project-1',
    );
    final result = await pumpRoute(tester, routeNote: sharedNote);

    expect(find.byKey(const ValueKey('note-markdown-editor')), findsOneWidget);
    expect(find.text('Shared project title'), findsOneWidget);
    expect(find.text('Shared project content'), findsNWidgets(2));
    expect(
      result.container.read(activeDocumentTabProvider)?.ownerAccountId,
      'account-1',
    );
    expect(
      result.container.read(activeDocumentTabProvider)?.noteProjectId,
      'project-1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects a note owned by a different account', (tester) async {
    await pumpRoute(
      tester,
      routeNote: WorkspaceNote(
        id: note.id,
        ownerUserId: 'other-account',
        title: note.title,
        markdownContent: note.markdownContent,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
      ),
    );

    expect(
      find.text('This Note is unavailable for this account.'),
      findsOneWidget,
    );
    expect(find.text('Private title'), findsNothing);
    expect(find.text('Private content'), findsNothing);
    expect(find.byKey(const ValueKey('note-markdown-editor')), findsNothing);
  });
}
