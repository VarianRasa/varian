import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/app/supabase_bootstrap.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_surface.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_panel_controller.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/app/workspace_timestamp.dart';
import 'package:varian/features/home/state/home_provider.dart';
import '../../test_app.dart';

class _FakeWorkspaceNotesNotifier extends WorkspaceNotesNotifier {
  _FakeWorkspaceNotesNotifier(
    String? accountId, {
    bool listError = false,
    this._createError = false,
  }) : super(null, null) {
    state = WorkspaceNotesState(
      accountId: accountId,
      error: listError ? StateError('private backend detail') : null,
    );
  }

  final bool _createError;
  int createCalls = 0;
  final WorkspaceNote createdNote = WorkspaceNote(
    id: 'workspace-created-note',
    ownerUserId: 'workspace-test-account',
    title: 'New Workspace Note',
    markdownContent: '',
    createdAt: DateTime.utc(2026, 10, 11),
    updatedAt: DateTime.utc(2026, 10, 11),
  );

  @override
  Future<WorkspaceNote?> createNote({
    String title = 'Untitled Note',
    String? projectId,
  }) async {
    createCalls++;
    if (_createError || state.accountId == null) {
      state = state.copyWith(error: StateError('private backend detail'));
      return null;
    }
    state = state.copyWith(
      notes: [createdNote, ...state.notes],
      clearError: true,
    );
    return createdNote;
  }

  @override
  Future<WorkspaceNote?> openNote(String noteId) async =>
      noteId == createdNote.id ? createdNote : null;
}

class _FakeOpenNoteTabsNotifier extends OpenNoteTabsNotifier {
  _FakeOpenNoteTabsNotifier() : super(null);

  @override
  Future<void> openTab(OpenDocumentTab tab) async {
    state = [...state.where((item) => item.identity != tab.identity), tab];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    defaultSupabaseBootstrap.markUnavailable();
  });

  Future<
    ({
      DurableProjectStore store,
      ProviderContainer container,
      LocalStorageService storage,
      _FakeWorkspaceNotesNotifier notes,
    })
  >
  pumpWorkspace(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    bool signedIn = true,
    bool notesListError = false,
    bool notesCreateError = false,
    bool notesAccountUnavailable = false,
    String? notesAccountId,
  }) async {
    final store = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    final storage = LocalStorageService();
    final panelController = CanvasEditorPanelController(
      initialShowLayers: false,
      initialShowInspector: false,
      initialShowWorkspace: true,
    );
    final notes = _FakeWorkspaceNotesNotifier(
      notesAccountId ??
          (signedIn && !notesAccountUnavailable
              ? 'workspace-test-account'
              : null),
      listError: notesListError,
      createError: notesCreateError,
    );
    final container = ProviderContainer(
      overrides: [
        durableProjectStoreProvider.overrideWithValue(store),
        workspaceNotesProvider.overrideWith((ref) => notes),
        openNoteTabsProvider.overrideWith((ref) => _FakeOpenNoteTabsNotifier()),
        localStorageServiceProvider.overrideWithValue(storage),
        supabaseClientProvider.overrideWithValue(null),
        authUserProvider.overrideWith(
          (ref) => Stream.value(
            signedIn
                ? User(
                    id: 'workspace-test-account',
                    appMetadata: const {},
                    userMetadata: const {},
                    aud: 'authenticated',
                    createdAt: '2026-10-01T00:00:00Z',
                    isAnonymous: false,
                  )
                : null,
          ),
        ),
        autosaveControllerProvider.overrideWith(
          (ref) => AutosaveController(ref),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      panelController.dispose();
      await store.close();
    });
    final now = DateTime.now();
    await container
        .read(localStorageServiceProvider)
        .saveProjectMetadata(
          LocalProjectMetadata(
            id: 'workspace-panel-project',
            name: 'Panel Canvas',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await container
        .read(localStorageServiceProvider)
        .saveDocument(
          CanvasDocument(projectId: 'workspace-panel-project', updatedAt: now),
        );
    await container.read(homeProjectsProvider.notifier).loadProjects();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          MediaQuery(
            data: MediaQueryData(size: size),
            child: CanvasEditorSurface(
              projectId: 'workspace-panel-project',
              projectName: 'Panel Canvas',
              panelController: panelController,
              services: const CanvasEditorServices(
                showProjectHeader: true,
                showLayersByDefault: false,
                enableAutosave: false,
                enableCloudSync: false,
                enableCollaboration: false,
                enableAiStudio: false,
                trackVideoObjectUrls: false,
                enableExport: false,
              ),
              onCreateProject: (context) async {},
              onSelectDocument: (context, tab) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (store: store, container: container, storage: storage, notes: notes);
  }

  testWidgets('lists saved Canvas and opens the compact Workspace panel', (
    tester,
  ) async {
    await pumpWorkspace(tester);

    expect(find.text('Workspace'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-canvas-workspace-panel-project')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-canvas-create')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-notes-refresh')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-notes-create')),
      findsOneWidget,
    );
    expect(find.byTooltip('Create Note'), findsOneWidget);
    expect(find.text('Panel Canvas'), findsNWidgets(2));
    expect(find.text('Notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Workspace Notes create action opens the new private Note', (
    tester,
  ) async {
    final workspace = await pumpWorkspace(tester, notesListError: true);

    expect(find.text('Notes could not be loaded'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-notes-create')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('workspace-notes-create')));
    await tester.pumpAndSettle();

    expect(workspace.notes.createCalls, 1);
    expect(
      workspace.container.read(activeDocumentTabProvider),
      OpenDocumentTab.note(workspace.notes.createdNote),
    );
    expect(
      workspace.container.read(openNoteTabsProvider),
      contains(OpenDocumentTab.note(workspace.notes.createdNote)),
    );
    expect(
      find.byKey(const ValueKey('notes-editor-workspace-created-note')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('note-markdown-editor')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Workspace Notes create reports a safe failure', (tester) async {
    final workspace = await pumpWorkspace(tester, notesCreateError: true);

    await tester.tap(find.byKey(const ValueKey('workspace-notes-create')));
    await tester.pumpAndSettle();

    expect(workspace.notes.createCalls, 1);
    expect(
      workspace.container.read(workspaceNotesProvider).error,
      isA<StateError>(),
    );
    expect(
      find.text('Could not create Note. Check your sign-in and try again.'),
      findsNothing,
    );
    expect(find.text('private backend detail'), findsNothing);
    expect(workspace.container.read(activeDocumentTabProvider), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Workspace Notes create explains when the account is unavailable',
    (tester) async {
      final workspace = await pumpWorkspace(
        tester,
        notesAccountUnavailable: true,
      );

      await tester.tap(find.byKey(const ValueKey('workspace-notes-create')));
      await tester.pumpAndSettle();

      expect(workspace.notes.createCalls, 0);
      expect(find.text('Sign in to create private Notes.'), findsOneWidget);
      expect(workspace.container.read(activeDocumentTabProvider), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('embedded auth panel fits narrow and short Workspace layouts', (
    tester,
  ) async {
    for (final size in [const Size(264, 320), const Size(320, 480)]) {
      await pumpWorkspace(tester, size: size, signedIn: false);

      expect(find.text('Sign in to your canvas'), findsOneWidget);
      expect(find.byTooltip('Back to canvas'), findsNothing);
      expect(
        find.byKey(const ValueKey('workspace-panel-close')),
        findsOneWidget,
      );
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final signUp = find.text('CREATE ACCOUNT').last;
      await tester.ensureVisible(signUp);
      await tester.pumpAndSettle();
      await tester.tap(signUp);
      await tester.pumpAndSettle();
      expect(find.text('Sign up with Google'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final backToSignIn = find.text('SIGN IN').last;
      await tester.ensureVisible(backToSignIn);
      await tester.pumpAndSettle();
      await tester.tap(backToSignIn);
      await tester.pumpAndSettle();
      final forgotPassword = find.text('Forgot password?');
      await tester.ensureVisible(forgotPassword);
      await tester.pumpAndSettle();
      await tester.tap(forgotPassword);
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('new Workspace Canvas gets a timestamp title', (tester) async {
    final state = await pumpWorkspace(tester);

    await tester.tap(find.byKey(const ValueKey('workspace-canvas-create')));
    await tester.pumpAndSettle();

    final projects = await state.storage.getProjects();
    final created = projects.singleWhere(
      (project) => project.id != 'workspace-panel-project',
    );
    expect(created.name, formatWorkspaceTimestamp(created.createdAt));
    expect(created.name, isNot('Untitled Doc'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Workspace controls stay aligned in a narrow panel', (
    tester,
  ) async {
    await pumpWorkspace(tester, size: const Size(274, 900));

    final panel = find.byKey(const ValueKey('canvas-workspace-panel'));
    expect(panel, findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-canvas-create')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-canvas-template')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('workspace-canvas-sort')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-canvas-status-menu')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-notes-refresh')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final panelRect = tester.getRect(panel);
    for (final key in [
      const ValueKey('workspace-canvas-create'),
      const ValueKey('workspace-canvas-template'),
      const ValueKey('workspace-canvas-sort'),
      const ValueKey('workspace-canvas-bulk-trash'),
      const ValueKey('workspace-canvas-status-menu'),
    ]) {
      final rect = tester.getRect(find.byKey(key));
      expect(rect.left, greaterThanOrEqualTo(panelRect.left));
      expect(rect.right, lessThanOrEqualTo(panelRect.right));
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('filters Canvas by status and supports archive actions', (
    tester,
  ) async {
    final state = await pumpWorkspace(tester);

    await tester.tap(
      find.byKey(
        const ValueKey('workspace-canvas-actions-workspace-panel-project'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(
      state.container.read(homeProjectsProvider).asData!.value.single.status,
      ProjectStatus.archived,
    );

    await tester.tap(
      find.byKey(const ValueKey('workspace-canvas-status-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived').last);
    await tester.pumpAndSettle();
    expect(find.text('Panel Canvas'), findsNWidgets(2));

    await tester.tap(
      find.byKey(
        const ValueKey('workspace-canvas-actions-workspace-panel-project'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('workspace-canvas-restore-workspace-panel-project'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      state.container.read(homeProjectsProvider).asData!.value.single.status,
      ProjectStatus.active,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
