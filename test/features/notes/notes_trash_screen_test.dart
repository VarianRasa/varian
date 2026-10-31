import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/presentation/notes_trash_screen.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

class _TrashNotes extends WorkspaceNotesNotifier {
  _TrashNotes(WorkspaceNotesState initial) : super(null, null) {
    state = initial;
  }
  int loads = 0;
  bool restoreResult = true;
  @override
  Future<void> loadTrash() async {
    loads++;
  }

  @override
  Future<bool> restoreNote(WorkspaceNote note) async {
    if (!restoreResult) return false;
    state = state.copyWith(
      trashNotes: [],
      notes: [note.copyWith(clearDeletedAt: true)],
    );
    return true;
  }
}

WorkspaceNote _deleted() => WorkspaceNote(
  id: 'n1',
  ownerUserId: 'u1',
  title: 'Deleted note',
  markdownContent: 'private body',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  revision: 4,
  deletedAt: DateTime.utc(2026, 1, 2),
);

void main() {
  testWidgets('renders loading, empty, and error retry states', (tester) async {
    final loading = _TrashNotes(
      const WorkspaceNotesState(accountId: 'u1', trashLoading: true),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workspaceNotesProvider.overrideWith((ref) => loading)],
        child: const MaterialApp(home: NotesTrashScreen()),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    final empty = _TrashNotes(const WorkspaceNotesState(accountId: 'u1'));
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [workspaceNotesProvider.overrideWith((ref) => empty)],
        child: const MaterialApp(home: NotesTrashScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('Trash is empty.'), findsOneWidget);
    final failed = _TrashNotes(
      const WorkspaceNotesState(accountId: 'u1', trashError: 'failed'),
    );
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [workspaceNotesProvider.overrideWith((ref) => failed)],
        child: const MaterialApp(home: NotesTrashScreen()),
      ),
    );
    expect(find.text('Could not load Trash.'), findsOneWidget);
    final automaticLoadCount = failed.loads;
    await tester.tap(find.text('Retry'));
    expect(failed.loads, automaticLoadCount + 1);
  });

  testWidgets('restores a note and navigates back to active Library', (
    tester,
  ) async {
    final notifier = _TrashNotes(
      WorkspaceNotesState(accountId: 'u1', trashNotes: [_deleted()]),
    );
    final router = GoRouter(
      initialLocation: '/notes/trash',
      routes: [
        GoRoute(
          path: '/notes/trash',
          builder: (_, _) => const NotesTrashScreen(),
        ),
        GoRoute(
          path: '/notes',
          builder: (_, _) => const Text('Active Library'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workspaceNotesProvider.overrideWith((ref) => notifier)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Active Library'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/notes');
    router.dispose();
  });
}
