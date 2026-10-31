import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/workspace_timestamp.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_folder.dart';
import 'package:varian/features/notes/domain/workspace_note_project_scope.dart';
import 'package:varian/features/notes/domain/workspace_note_scope_change_job.dart';
import 'package:varian/features/notes/presentation/notes_graph_screen.dart';
import 'package:varian/features/notes/presentation/notes_workspace_screen.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

class _Notes extends WorkspaceNotesNotifier {
  _Notes(WorkspaceNotesState initial) : super(null, null) {
    state = initial;
  }

  int loadCount = 0;

  @override
  Future<void> load() async {
    loadCount++;
  }

  @override
  Future<WorkspaceNote?> openNote(String noteId) async {
    for (final note in state.notes) {
      if (note.id == noteId) return note;
    }
    return null;
  }
}

class _DailyNotes extends _Notes {
  _DailyNotes(super.initial);

  final List<(DateTime, String?)> requests = [];

  @override
  Future<WorkspaceNote?> getOrCreateDailyNote({
    required DateTime localDate,
    String? projectId,
  }) async {
    requests.add((localDate, projectId));
    final note = WorkspaceNote(
      id: 'daily-note',
      ownerUserId: state.accountId!,
      title: 'Daily note',
      markdownContent: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      projectId: projectId,
      dailyNoteDate: formatWorkspaceDateKey(localDate),
    );
    state = state.copyWith(notes: [note, ...state.notes]);
    return note;
  }
}

class _TabController extends ActiveDocumentTabController {
  _TabController(super.ref) : _ref = ref;

  @override
  Future<void> select(OpenDocumentTab tab) async {
    _ref.read(activeDocumentTabProvider.notifier).state = tab;
  }

  late final Ref _ref;
}

class _OrganizationRepository implements WorkspaceNoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final List<WorkspaceNoteFolder> folders = [];
  final List<WorkspaceNote> notes = [];
  Completer<List<WorkspaceNoteFolder>>? pendingFolders;
  Object? foldersError;
  final Set<String> pinnedIds = {};
  List<WorkspaceNoteProjectScope> editableProjectScopes = const [];
  bool canManageScope = true;
  int scopeEligibilityChecks = 0;
  final Map<String, String?> movedNotes = {};
  final Map<String, String?> movedNoteScopes = {};
  final Set<String> deletedFolders = {};
  final Map<String, String> renamedFolders = {};
  final Map<String, String?> movedFolders = {};
  WorkspaceNoteScopeChangeJob? scopeChangeStatus;
  int scopeChangeRetries = 0;

  @override
  Future<List<WorkspaceNoteFolder>> listFolders({
    String? projectId,
    String? expectedAccountId,
  }) async {
    final error = foldersError;
    if (error != null) throw error;
    final pending = pendingFolders;
    if (pending != null) return pending.future;
    return folders
        .where((folder) => folder.projectId == projectId)
        .toList(growable: false);
  }

  @override
  Future<List<WorkspaceNote>> listPinnedNotes({
    String? expectedAccountId,
  }) async => notes
      .where((note) => pinnedIds.contains(note.id))
      .toList(growable: false);

  @override
  Future<WorkspaceNoteFolder> createFolder({
    required String name,
    String? projectId,
    String? parentFolderId,
    int sortOrder = 0,
    String? expectedAccountId,
  }) async {
    final now = DateTime.utc(2026);
    final folder = WorkspaceNoteFolder(
      id: 'folder-${folders.length}',
      ownerUserId: expectedAccountId ?? 'owner-a',
      projectId: projectId,
      parentFolderId: parentFolderId,
      name: name,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    folders.add(folder);
    return folder;
  }

  @override
  Future<void> renameFolder({
    required String folderId,
    required String name,
    String? expectedAccountId,
  }) async {
    renamedFolders[folderId] = name;
    final index = folders.indexWhere((folder) => folder.id == folderId);
    if (index >= 0) {
      final folder = folders[index];
      folders[index] = WorkspaceNoteFolder(
        id: folder.id,
        ownerUserId: folder.ownerUserId,
        projectId: folder.projectId,
        parentFolderId: folder.parentFolderId,
        name: name,
        sortOrder: folder.sortOrder,
        createdAt: folder.createdAt,
        updatedAt: folder.updatedAt,
      );
    }
  }

  @override
  Future<void> moveFolder({
    required String folderId,
    String? parentFolderId,
    String? expectedAccountId,
  }) async {
    movedFolders[folderId] = parentFolderId;
  }

  @override
  Future<void> deleteFolder({
    required String folderId,
    String? expectedAccountId,
  }) async {
    deletedFolders.add(folderId);
    final folder = folders.firstWhere((item) => item.id == folderId);
    for (var index = 0; index < notes.length; index++) {
      final note = notes[index];
      if (note.folderId == folderId) {
        notes[index] = _withFolder(note, folder.parentFolderId);
      }
    }
    folders.removeWhere((item) => item.id == folderId);
    for (var index = 0; index < folders.length; index++) {
      final child = folders[index];
      if (child.parentFolderId == folderId) {
        folders[index] = WorkspaceNoteFolder(
          id: child.id,
          ownerUserId: child.ownerUserId,
          projectId: child.projectId,
          parentFolderId: folder.parentFolderId,
          name: child.name,
          sortOrder: child.sortOrder,
          createdAt: child.createdAt,
          updatedAt: child.updatedAt,
        );
      }
    }
  }

  @override
  Future<void> moveNoteToFolder({
    required String noteId,
    String? folderId,
    String? expectedAccountId,
  }) async {
    movedNotes[noteId] = folderId;
    final index = notes.indexWhere((note) => note.id == noteId);
    if (index >= 0) notes[index] = _withFolder(notes[index], folderId);
  }

  @override
  Future<bool> canManageNoteScopeChange({
    required String noteId,
    String? expectedAccountId,
  }) async {
    scopeEligibilityChecks++;
    return canManageScope;
  }

  @override
  Future<List<WorkspaceNoteProjectScope>> listEditableNoteProjectScopes({
    String? expectedAccountId,
  }) async => editableProjectScopes;

  @override
  Future<String?> setNoteProject({
    required String noteId,
    required String? projectId,
    String? expectedAccountId,
  }) async {
    movedNoteScopes[noteId] = projectId;
    scopeChangeStatus = WorkspaceNoteScopeChangeJob(
      jobId: 'rehome-job-1',
      status: WorkspaceNoteScopeChangeStatus.pending,
    );
    return 'rehome-job-1';
  }

  @override
  Future<WorkspaceNoteScopeChangeJob?> getNoteScopeChangeStatus({
    required String noteId,
    String? expectedAccountId,
  }) async => scopeChangeStatus;

  @override
  Future<void> retryNoteScopeChange({
    required String jobId,
    String? expectedAccountId,
  }) async {
    scopeChangeRetries++;
    scopeChangeStatus = WorkspaceNoteScopeChangeJob(
      jobId: jobId,
      status: WorkspaceNoteScopeChangeStatus.copying,
    );
  }

  @override
  Future<void> setPinned({
    required String noteId,
    required bool pinned,
    String? expectedAccountId,
  }) async {
    if (pinned) {
      pinnedIds.add(noteId);
    } else {
      pinnedIds.remove(noteId);
    }
  }
}

WorkspaceNote _note({
  required String id,
  required String title,
  String markdown = '',
  String ownerId = 'owner-a',
  String? projectId,
  String? folderId,
}) => WorkspaceNote(
  id: id,
  ownerUserId: ownerId,
  projectId: projectId,
  folderId: folderId,
  title: title,
  markdownContent: markdown,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

WorkspaceNote _withFolder(WorkspaceNote note, String? folderId) =>
    WorkspaceNote(
      id: note.id,
      ownerUserId: note.ownerUserId,
      projectId: note.projectId,
      folderId: folderId,
      createdBy: note.createdBy,
      title: note.title,
      markdownContent: note.markdownContent,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      revision: note.revision,
      deletedAt: note.deletedAt,
    );

GoRouter _router({String initialLocation = '/notes'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/notes', builder: (_, _) => const NotesWorkspaceScreen()),
    GoRoute(path: '/notes/graph', builder: (_, _) => const NotesGraphScreen()),
    GoRoute(
      path: '/notes/canvas',
      builder: (_, state) =>
          Text('Canvas ${state.uri.queryParameters['projectId'] ?? 'private'}'),
    ),
    GoRoute(
      path: '/notes/canvas/:boardId',
      builder: (_, state) => Text('Board ${state.pathParameters['boardId']}'),
    ),
    GoRoute(
      path: '/notes/:noteId',
      builder: (_, state) =>
          NotesWorkspaceScreen(selectedNoteId: state.pathParameters['noteId']),
    ),
  ],
);

void main() {
  testWidgets('folder panel shows loading, empty, and error states', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _OrganizationRepository()
      ..pendingFolders = Completer<List<WorkspaceNoteFolder>>();
    final notifier = _Notes(const WorkspaceNotesState(accountId: 'owner-a'));
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceNotesProvider.overrideWith((ref) => notifier),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
        workspaceScopedNoteFoldersProvider.overrideWith(
          (ref, scope) => repository.listFolders(
            projectId: scope.$2,
            expectedAccountId: scope.$1,
          ),
        ),
        workspacePinnedNotesProvider.overrideWith(
          (ref, accountId) =>
              repository.listPinnedNotes(expectedAccountId: accountId),
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
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.pendingFolders!.complete(const []);
    repository.pendingFolders = null;
    await tester.pumpAndSettle();
    expect(find.text('No folders in this scope yet.'), findsOneWidget);

    repository.foldersError = StateError('simulated folder failure');
    container.invalidate(workspaceScopedNoteFoldersProvider(('owner-a', null)));
    await tester.pumpAndSettle();
    expect(find.text('Could not load folders.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Daily Notes opens in the selected project scope', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _OrganizationRepository();
    final projectNote = _note(
      id: 'shared-note',
      title: 'Shared research',
      ownerId: 'owner-b',
      projectId: 'project-1',
    );
    repository.notes.add(projectNote);
    final notifier = _DailyNotes(
      WorkspaceNotesState(accountId: 'owner-a', notes: [projectNote]),
    );
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceNotesProvider.overrideWith((ref) => notifier),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
        workspaceScopedNoteFoldersProvider.overrideWith(
          (ref, scope) => repository.listFolders(
            projectId: scope.$2,
            expectedAccountId: scope.$1,
          ),
        ),
        workspacePinnedNotesProvider.overrideWith(
          (ref, accountId) =>
              repository.listPinnedNotes(expectedAccountId: accountId),
        ),
        activeDocumentTabControllerProvider.overrideWith(
          (ref) => _TabController(ref),
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
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('notes-scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared project · project-1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-daily-note-action')));
    await tester.pumpAndSettle();

    expect(notifier.requests, hasLength(1));
    expect(notifier.requests.single.$1.isUtc, isFalse);
    expect(notifier.requests.single.$2, 'project-1');
    expect(router.routeInformationProvider.value.uri.path, '/notes/daily-note');
    expect(
      container.read(activeDocumentTabProvider),
      OpenDocumentTab.note(notifier.state.notes.first),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens scoped Notes Canvas on desktop and narrow layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _OrganizationRepository();
    final projectNote = _note(
      id: 'shared-note',
      title: 'Shared research',
      ownerId: 'owner-b',
      projectId: 'project-1',
    );
    repository.notes.add(projectNote);
    final notifier = _Notes(
      WorkspaceNotesState(
        accountId: 'owner-a',
        notes: [
          _note(id: 'private-note', title: 'Private'),
          projectNote,
        ],
      ),
    );
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceNotesProvider.overrideWith((ref) => notifier),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
        workspaceScopedNoteFoldersProvider.overrideWith(
          (ref, scope) => repository.listFolders(
            projectId: scope.$2,
            expectedAccountId: scope.$1,
          ),
        ),
        workspacePinnedNotesProvider.overrideWith(
          (ref, accountId) =>
              repository.listPinnedNotes(expectedAccountId: accountId),
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
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes-canvas-action')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notes-canvas-action')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/notes/canvas');
    expect(find.text('Canvas private'), findsOneWidget);

    Future<void> selectProjectScope() async {
      await tester.tap(find.byKey(const ValueKey('notes-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shared project · project-1').last);
      await tester.pumpAndSettle();
    }

    router.go('/notes');
    await tester.pumpAndSettle();
    await selectProjectScope();
    await tester.tap(find.byKey(const ValueKey('notes-canvas-action')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['projectId'],
      'project-1',
    );

    tester.view.physicalSize = const Size(390, 844);
    router.go('/notes');
    await tester.pumpAndSettle();
    await selectProjectScope();
    await tester.tap(find.byTooltip('More Notes actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes Canvas').last);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['projectId'],
      'project-1',
    );
    expect(find.text('Canvas project-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project member can browse and open another member note', (
    tester,
  ) async {
    final repository = _OrganizationRepository();
    final projectNote = _note(
      id: 'shared-note',
      title: 'Shared research',
      ownerId: 'owner-b',
      projectId: 'project-1',
    );
    repository.notes.add(projectNote);
    final notifier = _Notes(
      WorkspaceNotesState(accountId: 'owner-a', notes: [projectNote]),
    );
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceNotesProvider.overrideWith((ref) => notifier),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
        workspaceScopedNoteFoldersProvider.overrideWith(
          (ref, scope) => repository.listFolders(
            projectId: scope.$2,
            expectedAccountId: scope.$1,
          ),
        ),
        workspacePinnedNotesProvider.overrideWith(
          (ref, accountId) =>
              repository.listPinnedNotes(expectedAccountId: accountId),
        ),
        activeDocumentTabControllerProvider.overrideWith(
          (ref) => _TabController(ref),
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
    await tester.pumpAndSettle();

    expect(find.text('Shared research'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('notes-scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared project · project-1').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-note-shared-note')),
      findsOneWidget,
    );
    expect(find.text('Shared project'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workspace-note-shared-note')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/notes/shared-note',
    );
    expect(find.text('Shared project note'), findsOneWidget);
  });

  testWidgets('organizes folders, moves notes, and keeps bookmarks personal', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _OrganizationRepository();
    final now = DateTime.utc(2026);
    repository.folders.addAll([
      WorkspaceNoteFolder(
        id: 'research',
        ownerUserId: 'owner-a',
        name: 'Research',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
      WorkspaceNoteFolder(
        id: 'literature',
        ownerUserId: 'owner-a',
        parentFolderId: 'research',
        name: 'Literature',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final note = _note(
      id: 'note-1',
      title: 'Project notes',
      markdown: '# Keep this content',
      folderId: 'literature',
    );
    repository.notes.add(note);
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceNotesProvider.overrideWith(
          (ref) =>
              _Notes(WorkspaceNotesState(accountId: 'owner-a', notes: [note])),
        ),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
        workspaceScopedNoteFoldersProvider.overrideWith(
          (ref, scope) => repository.listFolders(
            projectId: scope.$2,
            expectedAccountId: scope.$1,
          ),
        ),
        workspacePinnedNotesProvider.overrideWith(
          (ref, accountId) =>
              repository.listPinnedNotes(expectedAccountId: accountId),
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
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('notes-folder-literature')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('notes-folder-literature')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-note-note-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notes-all-notes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-actions-note-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Research'));
    await tester.pumpAndSettle();
    expect(repository.movedNotes['note-1'], 'research');

    await tester.tap(find.byKey(const ValueKey('notes-actions-note-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Bookmarks'));
    await tester.pumpAndSettle();
    expect(repository.pinnedIds, {'note-1'});
    await tester.tap(find.byKey(const ValueKey('notes-bookmarks')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-note-note-1')), findsOneWidget);

    await tester.tap(find.byTooltip('Folder actions: Research'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Studies');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repository.renamedFolders['research'], 'Studies');

    await tester.tap(find.byTooltip('Folder actions: Literature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to root'));
    await tester.pumpAndSettle();
    expect(repository.movedFolders['literature'], isNull);

    await tester.drag(
      find.byKey(const ValueKey('notes-folder-tree')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-new-folder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Field notes');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      repository.folders.any((folder) => folder.name == 'Field notes'),
      isTrue,
    );
    await tester.drag(
      find.byKey(const ValueKey('notes-folder-tree')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Folder actions: Studies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete folder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Note content will be kept'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repository.deletedFolders, {'research'});
    expect(repository.notes.single.markdownContent, '# Keep this content');
    expect(repository.notes.single.folderId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace search includes YAML and tags responsively', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final note = _note(
      id: 'note-a',
      title: 'Planning note',
      markdown: '---\nproject: atlas-roadmap\ntags: [research]\n---\n# Ideas',
    );
    final otherNote = _note(
      id: 'note-b',
      title: 'Other note',
      markdown: '---\ntags: [personal]\n---',
    );
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceNotesProvider.overrideWith(
            (ref) => _Notes(
              WorkspaceNotesState(
                accountId: 'owner-a',
                notes: [note, otherNote],
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Planning note'), findsOneWidget);
    expect(find.text('#research'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('notes-workspace-search')),
      'atlas-roadmap',
    );
    await tester.pump();
    expect(find.text('Planning note'), findsOneWidget);
    expect(find.text('Other note'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('notes-workspace-search')),
      '',
    );
    await tester.pump();
    await tester.tap(find.text('#research'));
    await tester.pump();
    expect(find.text('Planning note'), findsOneWidget);
    expect(find.text('Other note'), findsNothing);

    tester.view.physicalSize = const Size(320, 844);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('library separates recent notes from the full list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notes = [
      for (var index = 0; index < 7; index++)
        _note(
          id: 'note-$index',
          title: 'Note $index',
        ).copyWith(updatedAt: DateTime.utc(2026, 10, 16, index)),
    ];
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceNotesProvider.overrideWith(
            (ref) =>
                _Notes(WorkspaceNotesState(accountId: 'owner-a', notes: notes)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);
    expect(find.byTooltip('Import Markdown notes'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notes-templates-action')),
      findsOneWidget,
    );
    expect(find.byTooltip('Export notes'), findsOneWidget);
    expect(find.text('All notes'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('workspace-note-note-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-note-note-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-note-note-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-note-note-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected workspace shows backlinks, properties, and outline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    const sourceId = '123e4567-e89b-12d3-a456-426614174001';
    final target = _note(
      id: targetId,
      title: 'Target note',
      markdown:
          '---\nstatus: active\ntags: [research]\n---\n# Main idea\n## Detail',
    );
    final source = _note(
      id: sourceId,
      title: 'Source note',
      markdown: '[[Target note]]<!--varian-note-id:$targetId-->',
    );
    final router = _router(initialLocation: '/notes/$targetId');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceNotesProvider.overrideWith(
            (ref) => _Notes(
              WorkspaceNotesState(
                accountId: 'owner-a',
                notes: [target, source],
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backlinks (1)'), findsOneWidget);
    expect(find.text('Source note'), findsWidgets);
    expect(find.text('Properties'), findsOneWidget);
    expect(find.text('status'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
    expect(find.text('research'), findsWidgets);
    expect(find.text('Outline'), findsOneWidget);
    expect(find.text('Main idea'), findsNWidgets(2));
    expect(find.text('Detail'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow selected note exposes an explicit library action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final note = _note(id: 'note-a', title: 'Planning note');
    final router = _router(initialLocation: '/notes/note-a');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceNotesProvider.overrideWith(
            (ref) => _Notes(
              WorkspaceNotesState(accountId: 'owner-a', notes: [note]),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('All notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final width in [390.0, 768.0, 1024.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    tester.view.physicalSize = const Size(320, 844);
    await tester.pump();
    await tester.tap(find.byTooltip('All notes'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/notes');
    expect(find.text('Planning note'), findsOneWidget);
    await tester.tap(find.byTooltip('More Notes actions'));
    await tester.pumpAndSettle();
    expect(find.text('Manage templates'), findsOneWidget);
    expect(find.text('Offline recovery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moves a selected note and displays pending rehome status', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _OrganizationRepository()
      ..editableProjectScopes = const [
        WorkspaceNoteProjectScope(id: 'project-1', name: 'Project One'),
      ];
    final privateNote = _note(
      id: 'private-note',
      title: 'Private note',
      ownerId: 'owner-a',
    );
    final projectNote = _note(
      id: 'project-note',
      title: 'Project note',
      ownerId: 'owner-b',
      projectId: 'project-1',
    );
    repository.notes.addAll([privateNote, projectNote]);
    final notifier = _Notes(
      WorkspaceNotesState(
        accountId: 'owner-a',
        notes: [privateNote, projectNote],
      ),
    );
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceNotesProvider.overrideWith((ref) => notifier),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
        workspaceScopedNoteFoldersProvider.overrideWith(
          (ref, scope) => repository.listFolders(
            projectId: scope.$2,
            expectedAccountId: scope.$1,
          ),
        ),
        workspacePinnedNotesProvider.overrideWith(
          (ref, accountId) =>
              repository.listPinnedNotes(expectedAccountId: accountId),
        ),
        activeDocumentTabControllerProvider.overrideWith(
          (ref) => _TabController(ref),
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
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('workspace-note-private-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-move-scope-action')));
    await tester.pumpAndSettle();
    expect(find.text('Move note to another scope'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('notes-scope-target-project-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('MOVE NOTE'));
    await tester.pumpAndSettle();

    expect(repository.movedNoteScopes['private-note'], 'project-1');
    expect(find.text('Move pending'), findsOneWidget);

    repository.scopeChangeStatus = const WorkspaceNoteScopeChangeJob(
      jobId: 'rehome-job-1',
      status: WorkspaceNoteScopeChangeStatus.complete,
    );
    await tester.tap(find.text('CHECK STATUS'));
    await tester.pumpAndSettle();

    expect(find.text('Move complete'), findsOneWidget);
    expect(notifier.loadCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides Note scope changes from project members', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _OrganizationRepository()..canManageScope = false;
    final note = _note(
      id: 'project-note',
      title: 'Project note',
      ownerId: 'owner-b',
      projectId: 'project-1',
    );
    final notifier = _Notes(
      WorkspaceNotesState(accountId: 'owner-a', notes: [note]),
    );
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceNotesProvider.overrideWith((ref) => notifier),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
        workspaceScopedNoteFoldersProvider.overrideWith(
          (ref, scope) => repository.listFolders(
            projectId: scope.$2,
            expectedAccountId: scope.$1,
          ),
        ),
        workspacePinnedNotesProvider.overrideWith(
          (ref, accountId) =>
              repository.listPinnedNotes(expectedAccountId: accountId),
        ),
        activeDocumentTabControllerProvider.overrideWith(
          (ref) => _TabController(ref),
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared project · project-1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-note-project-note')));
    await tester.pumpAndSettle();

    expect(repository.scopeEligibilityChecks, greaterThan(0));
    expect(find.byKey(const ValueKey('notes-move-scope-action')), findsNothing);
    expect(find.byTooltip('More Notes actions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries a failed Note scope rehome job', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _OrganizationRepository()
      ..scopeChangeStatus = const WorkspaceNoteScopeChangeJob(
        jobId: 'rehome-job-2',
        status: WorkspaceNoteScopeChangeStatus.failed,
        attemptCount: 8,
      );
    final note = _note(id: 'private-note', title: 'Private note');
    final notifier = _Notes(
      WorkspaceNotesState(accountId: 'owner-a', notes: [note]),
    );
    final router = _router();
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceNotesProvider.overrideWith((ref) => notifier),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
        workspaceScopedNoteFoldersProvider.overrideWith(
          (ref, scope) => repository.listFolders(
            projectId: scope.$2,
            expectedAccountId: scope.$1,
          ),
        ),
        workspacePinnedNotesProvider.overrideWith(
          (ref, accountId) =>
              repository.listPinnedNotes(expectedAccountId: accountId),
        ),
        activeDocumentTabControllerProvider.overrideWith(
          (ref) => _TabController(ref),
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
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('workspace-note-private-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-move-scope-action')));
    await tester.pumpAndSettle();
    expect(find.text('Move failed'), findsOneWidget);
    await tester.tap(find.text('RETRY MOVE'));
    await tester.pumpAndSettle();

    expect(repository.scopeChangeRetries, 1);
    expect(find.text('Copying attachments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('graph discloses its 500 rendered-node cap', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notes = [
      for (var index = 0; index < 501; index++)
        _note(id: 'note-$index', title: 'Note $index'),
    ];
    final router = _router();
    router.go('/notes/graph');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceNotesProvider.overrideWith(
            (ref) =>
                _Notes(WorkspaceNotesState(accountId: 'owner-a', notes: notes)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Showing 500 of 501 notes (500 node limit)'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('graph-node-note-99')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('graph count and include-unlinked filter reflect the active set', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const linkedId = '123e4567-e89b-12d3-a456-426614174000';
    const sourceId = '123e4567-e89b-12d3-a456-426614174001';
    final notes = [
      _note(
        id: sourceId,
        title: 'Source',
        markdown:
            '---\ntags: [shared]\n---\n[[Target]]<!--varian-note-id:$linkedId-->',
      ),
      _note(
        id: linkedId,
        title: 'Target',
        markdown: '---\ntags: [shared]\n---',
      ),
      _note(
        id: '123e4567-e89b-12d3-a456-426614174002',
        title: 'Isolated',
        markdown: '---\ntags: [other]\n---',
      ),
      _note(
        id: '123e4567-e89b-12d3-a456-426614174003',
        title: 'In Trash',
      ).copyWith(deletedAt: DateTime.utc(2026, 10, 16)),
    ];
    final router = _router();
    router.go('/notes/graph');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceNotesProvider.overrideWith(
            (ref) =>
                _Notes(WorkspaceNotesState(accountId: 'owner-a', notes: notes)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 3 of 3 notes'), findsOneWidget);
    await tester.tap(find.text('All notes').first);
    await tester.pumpAndSettle();
    expect(find.text('In Trash'), findsNothing);
    await tester.tap(find.text('All notes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Include unlinked'));
    await tester.pump();
    expect(find.text('Showing 2 of 2 notes'), findsOneWidget);
    expect(find.byKey(ValueKey('graph-node-$sourceId')), findsOneWidget);
    expect(find.byKey(ValueKey('graph-node-$linkedId')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('graph-node-123e4567-e89b-12d3-a456-426614174002'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Include unlinked'));
    await tester.pump();
    expect(find.text('Showing 3 of 3 notes'), findsOneWidget);

    await tester.tap(find.text('All tags').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('shared').last);
    await tester.pumpAndSettle();
    expect(find.text('Showing 2 of 2 notes'), findsOneWidget);
    expect(find.byKey(ValueKey('graph-node-$sourceId')), findsOneWidget);
    expect(find.byKey(ValueKey('graph-node-$linkedId')), findsOneWidget);

    await tester.tap(find.text('shared').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('other').last);
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 1 notes'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('graph-node-123e4567-e89b-12d3-a456-426614174002'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('other').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All tags').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All notes').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target').last);
    await tester.pumpAndSettle();
    expect(find.text('Showing 2 of 2 notes'), findsOneWidget);
    expect(find.byKey(ValueKey('graph-node-$linkedId')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('graph-node-123e4567-e89b-12d3-a456-426614174002'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
