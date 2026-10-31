import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/app/workspace_timestamp.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/presentation/notes_library_screen.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

class _FakeNotes extends WorkspaceNotesNotifier {
  _FakeNotes(WorkspaceNotesState initial) : super(null, null) {
    state = initial;
  }
  void replace(WorkspaceNotesState next) => state = next;
  int retryCount = 0;
  @override
  Future<void> load() async => retryCount++;
  @override
  Future<WorkspaceNote?> openNote(String noteId) async =>
      state.notes.where((note) => note.id == noteId).firstOrNull;
}

class _FakeTabController extends ActiveDocumentTabController {
  // Keep a readable reference for the test fake's state update.
  // ignore: use_super_parameters
  _FakeTabController(Ref ref) : _ref = ref, super(ref);

  final Ref _ref;

  @override
  Future<void> select(OpenDocumentTab tab) async {
    _ref.read(activeDocumentTabProvider.notifier).state = tab;
  }
}

WorkspaceNote _note(
  String id,
  String title,
  String body,
  int day, {
  String owner = 'u',
}) => WorkspaceNote(
  id: id,
  ownerUserId: owner,
  title: title,
  markdownContent: body,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026, 1, day),
);

Widget _standalone(WorkspaceNotesState state) => ProviderScope(
  key: UniqueKey(),
  overrides: [workspaceNotesProvider.overrideWith((ref) => _FakeNotes(state))],
  child: const MaterialApp(home: NotesLibraryScreen()),
);

void main() {
  testWidgets(
    'searches title/body case-insensitively, orders newest, and shows bounded plain excerpt',
    (tester) async {
      final notes = [
        _note('old', 'Old title', 'simple', 2),
        _note('new', 'Newest title', '# BODY-match\n**${'x' * 190}**', 3),
      ];
      await tester.pumpWidget(
        _standalone(WorkspaceNotesState(accountId: 'u', notes: notes)),
      );
      expect(
        tester.getTopLeft(find.text('Newest title')).dy,
        lessThan(tester.getTopLeft(find.text('Old title')).dy),
      );
      final excerpt = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey('note-new')),
              matching: find.byType(Text),
            )
            .last,
      );
      expect(excerpt.data!.length, lessThanOrEqualTo(160));
      expect(excerpt.data, isNot(contains('#')));
      expect(excerpt.data, isNot(contains('**')));
      expect(
        find.text('Modified ${formatWorkspaceTimestamp(notes[1].updatedAt)}'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Search notes'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('notes-library-search')),
        'newest TITLE',
      );
      await tester.pump();
      expect(find.text('Newest title'), findsOneWidget);
      expect(find.text('Old title'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('notes-library-search')),
        'body-MATCH',
      );
      await tester.pump();
      expect(find.text('Newest title'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('notes-library-search')),
        'no-such-note',
      );
      await tester.pump();
      expect(find.text('No Notes match your search.'), findsOneWidget);
    },
  );

  testWidgets('organization panel stays usable at responsive widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      _standalone(
        WorkspaceNotesState(
          accountId: 'u',
          notes: [_note('n1', 'A note', 'body', 1, owner: 'u')],
        ),
      ),
    );
    for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notes-bookmarks')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('shows loading, first-use empty, error/retry', (tester) async {
    await tester.pumpWidget(
      _standalone(const WorkspaceNotesState(loading: true)),
    );
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await tester.pumpWidget(
      _standalone(const WorkspaceNotesState(accountId: 'u')),
    );
    expect(find.textContaining('No Notes yet'), findsOneWidget);
    final failed = _FakeNotes(
      const WorkspaceNotesState(accountId: 'u', error: 'failed'),
    );
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [workspaceNotesProvider.overrideWith((ref) => failed)],
        child: const MaterialApp(home: NotesLibraryScreen()),
      ),
    );
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(failed.retryCount, 1);
  });

  testWidgets('opens note route and selects its OpenDocumentTab', (
    tester,
  ) async {
    final saved = _note('n1', 'A note', 'body', 1);
    final notifier = _FakeNotes(
      WorkspaceNotesState(accountId: 'u', notes: [saved]),
    );
    final router = GoRouter(
      initialLocation: '/notes',
      routes: [
        GoRoute(path: '/notes', builder: (_, _) => const NotesLibraryScreen()),
        GoRoute(
          path: '/notes/:noteId',
          builder: (_, state) =>
              Text('Opened ${state.pathParameters['noteId']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceNotesProvider.overrideWith((ref) => notifier),
          activeDocumentTabControllerProvider.overrideWith(
            (ref) => _FakeTabController(ref),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('A note'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/notes/n1');
    expect(find.text('Opened n1'), findsOneWidget);
    expect(
      ProviderScope.containerOf(
        tester.element(find.text('Opened n1')),
      ).read(activeDocumentTabProvider),
      OpenDocumentTab.note(saved),
    );
    router.dispose();
  });

  testWidgets('account switch clears prior titles and active search matches', (
    tester,
  ) async {
    final notifier = _FakeNotes(
      WorkspaceNotesState(
        accountId: 'u1',
        notes: [_note('old', 'Secret old title', 'needle', 2, owner: 'u1')],
      ),
    );
    final container = ProviderContainer(
      overrides: [workspaceNotesProvider.overrideWith((ref) => notifier)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NotesLibraryScreen()),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('notes-library-search')),
      'needle',
    );
    await tester.pump();
    expect(find.text('Secret old title'), findsOneWidget);
    notifier.replace(const WorkspaceNotesState(accountId: 'u2', loading: true));
    await tester.pump();
    expect(find.text('Secret old title'), findsNothing);
    expect(find.text('No Notes match your search.'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('notes-library-search')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
