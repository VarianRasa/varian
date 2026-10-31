import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/app/workspace_timestamp.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/export/data/export_file_saver.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/data/workspace_note_attachment_repository.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_attachments.dart';
import 'package:varian/features/notes/domain/workspace_note_version.dart';
import 'package:varian/features/notes/domain/workspace_note_template.dart';
import 'package:varian/features/notes/presentation/notes_editor.dart';
import 'package:varian/features/notes/presentation/notes_markdown_syntax.dart';
import 'package:varian/features/notes/presentation/notes_workspace_screen.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

import '../../test_app.dart';

class _FakeWorkspaceNotesNotifier extends WorkspaceNotesNotifier {
  _FakeWorkspaceNotesNotifier(String? accountId) : super(null, null) {
    state = WorkspaceNotesState(accountId: accountId);
  }

  final Map<String, List<Completer<WorkspaceNote?>>> pendingOpens = {};
  final List<WorkspaceNote> saved = [];
  final List<WorkspaceNoteSaveOutcome?> outcomes = [];
  final List<(String, String)> renamed = [];
  final List<(String, String?)> createRequests = [];
  final List<WorkspaceNoteRenameOutcome?> renameOutcomes = [];
  Future<WorkspaceNote?> Function(String title, String? projectId)?
  createHandler;
  List<WorkspaceNoteVersion> history = const [];
  int openCalls = 0;
  int retryCalls = 0;
  Object? saveError;
  Future<WorkspaceNoteSaveOutcome?> Function(WorkspaceNote note)? saveHandler;
  Future<WorkspaceNoteRenameOutcome?> Function(String noteId, String title)?
  renameHandler;
  Future<void> Function()? loadHandler;

  @override
  Future<void> load() async {
    final handler = loadHandler;
    if (handler != null) {
      await handler();
      return;
    }
    await super.load();
  }

  @override
  Future<void> retryOfflineSync() async {
    retryCalls++;
  }

  @override
  Future<WorkspaceNote?> openNote(String noteId) {
    openCalls++;
    final completer = Completer<WorkspaceNote?>();
    pendingOpens.putIfAbsent(noteId, () => []).add(completer);
    return completer.future;
  }

  @override
  Future<WorkspaceNote?> createNote({
    String title = 'Untitled Note',
    String? projectId,
  }) async {
    createRequests.add((title, projectId));
    final handler = createHandler;
    if (handler != null) return handler(title, projectId);
    return super.createNote(title: title, projectId: projectId);
  }

  @override
  Future<WorkspaceNoteSaveOutcome?> saveNote(WorkspaceNote note) async {
    saved.add(note);
    state = state.copyWith(
      savingNoteIds: {...state.savingNoteIds, note.id},
      clearError: true,
    );
    final outcome = saveHandler == null
        ? _defaultSave(note)
        : await saveHandler!(note);
    if (outcome == null) {
      state = state.copyWith(
        savingNoteIds: {...state.savingNoteIds}..remove(note.id),
        error: saveError,
      );
      return null;
    }
    outcomes.add(outcome);
    switch (outcome) {
      case WorkspaceNoteSaveSuccess(:final note):
        state = state.copyWith(
          notes: [note, ...state.notes.where((item) => item.id != note.id)],
          savingNoteIds: {...state.savingNoteIds}..remove(note.id),
          clearError: true,
        );
      case WorkspaceNoteSaveConflict():
        state = state.copyWith(
          conflicts: {...state.conflicts, note.id: outcome},
          savingNoteIds: {...state.savingNoteIds}..remove(note.id),
          error: const WorkspaceNoteConflictError(),
        );
      case WorkspaceNoteSaveUnavailable():
        state = state.copyWith(
          savingNoteIds: {...state.savingNoteIds}..remove(note.id),
          error: const WorkspaceNoteUnavailableError(),
        );
    }
    return outcome;
  }

  @override
  Future<List<WorkspaceNoteVersion>> listNoteVersions(String noteId) async =>
      history;

  @override
  Future<bool> restoreNoteVersion({
    required String noteId,
    required String versionId,
    required int expectedRevision,
  }) async {
    final version = history.firstWhere((item) => item.id == versionId);
    final current = state.notes.firstWhere((item) => item.id == noteId);
    final updated = _withRevision(
      current.copyWith(
        title: version.title,
        markdownContent: version.markdownContent,
      ),
      expectedRevision + 1,
    );
    state = state.copyWith(
      notes: [updated, ...state.notes.where((item) => item.id != noteId)],
    );
    return true;
  }

  WorkspaceNoteSaveOutcome? _defaultSave(WorkspaceNote note) {
    if (saveError != null) return null;
    return WorkspaceNoteSaveSuccess(_withRevision(note, note.revision + 1));
  }

  @override
  Future<WorkspaceNoteRenameOutcome?> renameNoteWithLinks({
    required String noteId,
    required String title,
  }) async {
    renamed.add((noteId, title));
    final custom = renameHandler;
    if (custom != null) {
      final accountId = state.accountId;
      final outcome = await custom(noteId, title);
      if (state.accountId != accountId) return null;
      if (outcome != null) renameOutcomes.add(outcome);
      if (outcome case WorkspaceNoteRenameSuccess(:final notes)) {
        state = state.copyWith(
          notes: [
            ...notes,
            ...state.notes.where(
              (note) => !notes.any((updated) => updated.id == note.id),
            ),
          ],
        );
      }
      return outcome;
    }
    final target = state.notes.where((note) => note.id == noteId).firstOrNull;
    if (target == null) return const WorkspaceNoteRenameUnavailable();
    final result = WorkspaceNoteRenameSuccess([
      _withRevision(target.copyWith(title: title), target.revision + 1),
    ]);
    renameOutcomes.add(result);
    state = state.copyWith(
      notes: [
        result.notes.single,
        ...state.notes.where((note) => note.id != noteId),
      ],
    );
    return result;
  }
}

class _FakeTabController extends ActiveDocumentTabController {
  // ignore: use_super_parameters
  _FakeTabController(Ref ref) : _ref = ref, super(ref);

  final Ref _ref;

  @override
  Future<void> select(OpenDocumentTab tab) async {
    _ref.read(activeDocumentTabProvider.notifier).state = tab;
  }
}

class _FakeTemplateRepository extends WorkspaceNoteRepository {
  _FakeTemplateRepository(super.client, this.templates);

  final List<WorkspaceNoteTemplate> templates;
  String? requestedProjectId;

  @override
  Future<List<WorkspaceNoteTemplate>> listTemplates({
    String? projectId,
    String? expectedAccountId,
  }) async {
    requestedProjectId = projectId;
    return templates;
  }
}

class _FakeAttachmentRepository implements WorkspaceNoteAttachmentRepository {
  _FakeAttachmentRepository(this.bytes, this.attachments);

  final Uint8List bytes;
  final List<WorkspaceNoteAttachment> attachments;
  int cachedReads = 0;
  int uploadCalls = 0;
  int deleteCalls = 0;

  @override
  Future<WorkspaceNoteAttachment> upload({
    required String accountId,
    required String noteId,
    required String? expectedProjectId,
    required String originalName,
    required Uint8List bytes,
  }) async {
    uploadCalls++;
    return attachments.single;
  }

  @override
  Future<void> delete({
    required String accountId,
    required String noteId,
    required String attachmentId,
    required String? expectedProjectId,
  }) async {
    deleteCalls++;
  }

  @override
  Future<List<WorkspaceNoteAttachment>> listForNote({
    required String accountId,
    required String noteId,
    required String? expectedProjectId,
  }) async => attachments;

  @override
  Future<Uint8List> readBytes({
    required String accountId,
    required String noteId,
    required String attachmentId,
    required String? expectedProjectId,
  }) async => throw StateError('Expected the encrypted cache to be used.');

  @override
  Future<Uint8List?> readCachedBytes({
    required String accountId,
    required String noteId,
    required String noteMarkdown,
    required String attachmentId,
    required String? projectId,
  }) async {
    cachedReads++;
    return bytes;
  }
}

WorkspaceNote _withRevision(WorkspaceNote note, int revision) => WorkspaceNote(
  id: note.id,
  ownerUserId: note.ownerUserId,
  title: note.title,
  markdownContent: note.markdownContent,
  createdAt: note.createdAt,
  updatedAt: note.updatedAt,
  revision: revision,
  projectId: note.projectId,
);

WorkspaceNoteAttachment _attachment({
  String id = '123e4567-e89b-12d3-a456-426614174000',
  String noteId = 'note-1',
  WorkspaceNoteAttachmentType type = WorkspaceNoteAttachmentType.png,
  String originalName = 'diagram.png',
}) => WorkspaceNoteAttachment(
  id: id,
  noteId: noteId,
  ownerUserId: 'account-a',
  projectId: null,
  storagePath: 'private/account-a/$id',
  originalName: originalName,
  type: type,
  sizeBytes: 8,
  sha256: 'a' * 64,
);

WorkspaceNote _note({
  String id = 'note-1',
  String owner = 'account-a',
  String title = 'A Note',
  String markdown = '',
  int revision = 1,
  String? projectId,
}) => WorkspaceNote(
  id: id,
  ownerUserId: owner,
  title: title,
  markdownContent: markdown,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  revision: revision,
  projectId: projectId,
);

Future<void> _openEditor(
  WidgetTester tester,
  _FakeWorkspaceNotesNotifier notes, {
  String noteId = 'note-1',
  ExportFileSaver? exportFileSaver,
  bool wrapInScaffold = false,
  WorkspaceNoteRepository? repository,
  WorkspaceNoteAttachmentRepository? attachmentRepository,
  NotesAttachmentPicker? attachmentPicker,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceNotesProvider.overrideWith((ref) => notes),
        if (repository != null)
          workspaceNoteRepositoryProvider.overrideWithValue(repository),
        if (attachmentRepository != null)
          workspaceNoteAttachmentRepositoryProvider.overrideWithValue(
            attachmentRepository,
          ),
      ],
      child: testApp(
        wrapInScaffold
            ? Scaffold(
                body: NotesEditor(
                  noteId: noteId,
                  exportFileSaver: exportFileSaver,
                  attachmentPicker: attachmentPicker,
                ),
              )
            : NotesEditor(
                noteId: noteId,
                exportFileSaver: exportFileSaver,
                attachmentPicker: attachmentPicker,
              ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _completeOpen(
  WidgetTester tester,
  _FakeWorkspaceNotesNotifier notes,
  WorkspaceNote? note, {
  String noteId = 'note-1',
}) async {
  if (note != null) {
    notes.state = notes.state.copyWith(
      notes: [note, ...notes.state.notes.where((item) => item.id != note.id)],
    );
  }
  notes.pendingOpens[noteId]!.last.complete(note);
  await tester.pumpAndSettle();
}

late final SupabaseClient _templateTestClient;

void main() {
  setUpAll(() {
    _templateTestClient = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
    );
    _templateTestClient.auth.stopAutoRefresh();
  });
  tearDownAll(() => _templateTestClient.dispose());

  test('legacy default title is derived from its creation timestamp', () {
    final created = DateTime.utc(2026, 10, 11, 6, 5);
    final note = _note(title: 'Untitled Note');
    final legacy = WorkspaceNote(
      id: note.id,
      ownerUserId: note.ownerUserId,
      title: 'Untitled Note',
      markdownContent: '# Keep this content',
      createdAt: created,
      updatedAt: created,
    );
    final renamed = legacy.copyWith(
      title: formatWorkspaceTimestamp(legacy.createdAt),
    );
    expect(renamed.title, formatWorkspaceTimestamp(created));
    expect(renamed.id, legacy.id);
    expect(renamed.ownerUserId, legacy.ownerUserId);
    expect(renamed.markdownContent, legacy.markdownContent);
    expect(renamed.createdAt, legacy.createdAt);
    expect(renamed.updatedAt, legacy.updatedAt);
  });

  testWidgets('Properties edits save through the note Markdown path', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(
      tester,
      notes,
      _note(markdown: '---\nunknown: keep\n---\nBody stays exact'),
    );

    await tester.tap(find.byKey(const ValueKey('note-properties-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-property-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('note-property-key-input')),
      'status',
    );
    await tester.enterText(
      find.byKey(const ValueKey('note-property-value-input')),
      'Draft',
    );
    await tester.tap(find.byKey(const ValueKey('note-property-save')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(notes.saved, hasLength(1));
    final saved = notes.saved.single.markdownContent;
    expect(saved, contains('"status": "Draft"'));
    expect(saved, contains('unknown: keep'));
    expect(saved, endsWith('---\nBody stays exact'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('template action inserts at the editor selection in note scope', (
    tester,
  ) async {
    final template = WorkspaceNoteTemplate(
      id: 'template-1',
      ownerUserId: 'account-a',
      projectId: 'project-1',
      title: 'Daily entry',
      markdownContent: '\n{{title}} on {{date}}\n',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final repository = _FakeTemplateRepository(_templateTestClient, [template]);
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes, repository: repository);
    final note = _note(markdown: 'Keep this', projectId: 'project-1');
    notes.state = notes.state.copyWith(notes: [note]);
    notes.pendingOpens['note-1']!.single.complete(note);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final markdownField = tester.widget<TextField>(
      find.byKey(const ValueKey('note-markdown-editor')),
    );
    markdownField.controller!.selection = const TextSelection.collapsed(
      offset: 4,
    );

    await tester.tap(find.byKey(const ValueKey('note-template-insert-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('apply-template-template-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(repository.requestedProjectId, 'project-1');
    expect(
      markdownField.controller!.text,
      'Keep\nA Note on ${formatWorkspaceDateKey(DateTime.now())}\n this',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('template replacement requires explicit confirmation', (
    tester,
  ) async {
    final template = WorkspaceNoteTemplate(
      id: 'template-2',
      ownerUserId: 'account-a',
      title: 'Fresh note',
      markdownContent: 'Replacement body',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final repository = _FakeTemplateRepository(_templateTestClient, [template]);
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes, repository: repository);
    final note = _note(markdown: 'Existing body');
    notes.state = notes.state.copyWith(notes: [note]);
    notes.pendingOpens['note-1']!.single.complete(note);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final markdownField = tester.widget<TextField>(
      find.byKey(const ValueKey('note-markdown-editor')),
    );

    await tester.tap(find.byKey(const ValueKey('note-template-insert-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Replace note with Fresh note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(markdownField.controller!.text, 'Existing body');
    expect(find.text('Replace this Note?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Replace').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(markdownField.controller!.text, 'Replacement body');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Properties dialog closes on account change', (tester) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(
      tester,
      notes,
      _note(markdown: '---\nsecret: private content\n---\nBody'),
    );
    await tester.tap(find.byKey(const ValueKey('note-properties-action')));
    await tester.pumpAndSettle();
    expect(find.text('private content'), findsOneWidget);

    notes.state = notes.state.copyWith(accountId: 'account-b');
    await tester.pumpAndSettle();

    expect(find.text('private content'), findsNothing);
    expect(find.byKey(const ValueKey('notes-property-add')), findsNothing);
    expect(
      find.text('The signed-in account changed. Reopen this Note.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing note shows retry and does not auto-reload', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    expect(notes.openCalls, 1);
    await _completeOpen(tester, notes, null);
    expect(
      find.text('This Note is unavailable for this account.'),
      findsOneWidget,
    );
    expect(notes.openCalls, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(notes.openCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows queued sync status and retries explicitly', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    final note = _note(markdown: 'Queued draft');
    await _completeOpen(tester, notes, note);
    notes.state = notes.state.copyWith(queuedNoteIds: {note.id});
    await tester.pump();

    expect(
      find.text(
        'Encrypted changes are queued on this device and will retry when access is available.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry sync'));
    await tester.pump();
    expect(notes.retryCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows when project access pauses a queued draft', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    final note = _note(
      owner: 'account-b',
      projectId: 'project-1',
      markdown: 'Project draft',
    );
    await _completeOpen(tester, notes, note);
    notes.state = notes.state.copyWith(
      queuedNoteIds: {note.id},
      accessPausedNoteIds: {note.id},
    );
    await tester.pump();

    expect(
      find.textContaining('Project access could not be verified.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('will not sync until access is restored.'),
      findsOneWidget,
    );
    expect(find.text('Check access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows when encrypted device storage is unavailable', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note(markdown: 'Keep the draft'));
    notes.state = notes.state.copyWith(
      error: StateError('Encrypted Notes storage is unavailable.'),
    );
    await tester.pump();

    expect(
      find.textContaining('Encrypted Notes device storage is unavailable.'),
      findsOneWidget,
    );
    expect(find.textContaining('Enable secure storage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens and saves a shared project note', (tester) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    final sharedNote = _note(
      owner: 'account-b',
      projectId: 'project-1',
      markdown: 'Shared content',
    );
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, sharedNote);

    expect(find.byKey(const ValueKey('note-markdown-editor')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('note-markdown-editor')),
      'Updated shared content',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(notes.saved, hasLength(1));
    expect(notes.saved.single.projectId, 'project-1');
    expect(notes.saved.single.ownerUserId, 'account-b');
    expect(notes.saved.single.markdownContent, 'Updated shared content');
    expect(tester.takeException(), isNull);
  });

  testWidgets('history restore confirms and preserves exact Markdown', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    notes.history = [
      WorkspaceNoteVersion(
        id: 'version-1',
        noteId: 'note-1',
        revision: 1,
        title: 'Historical title',
        markdownContent: '  # exact\n\n- body  ',
        actorId: 'account-a',
        createdAt: DateTime.utc(2026),
      ),
    ];
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note(title: 'Current', revision: 2));

    await tester.tap(find.byKey(const ValueKey('note-history-action')));
    await tester.pumpAndSettle();
    expect(find.textContaining('retained indefinitely'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restore this version?'), findsOneWidget);
    await tester.tap(find.text('Restore version'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-title-field')))
          .controller!
          .text,
      'Historical title',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      '  # exact\n\n- body  ',
    );
    expect(notes.state.notes.single.revision, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account switch during note load never reveals the old note', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    notes.state = const WorkspaceNotesState(accountId: 'account-b');
    notes.pendingOpens['note-1']!.single.complete(
      _note(title: 'Private A', markdown: 'Secret content'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Private A'), findsNothing);
    expect(find.text('Secret content'), findsNothing);
    expect(
      find.text('The signed-in account changed. Reopen this Note.'),
      findsOneWidget,
    );
    expect(notes.openCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending edits save when the editor is disposed', (tester) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());
    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'After edit',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workspaceNotesProvider.overrideWith((ref) => notes)],
        child: testApp(const SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();
    expect(notes.saved, isEmpty);
    expect(notes.renamed, [('note-1', 'After edit')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest edit uses the revision returned by prior save', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    final firstRename = Completer<WorkspaceNoteRenameOutcome?>();
    var renameCount = 0;
    notes.renameHandler = (noteId, title) {
      renameCount++;
      if (renameCount == 1) return firstRename.future;
      final latest = notes.state.notes.single;
      return Future.value(
        WorkspaceNoteRenameSuccess([
          _withRevision(latest.copyWith(title: title), latest.revision + 1),
        ]),
      );
    };
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());
    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'Saved first',
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(notes.renamed, hasLength(1));
    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'Latest edit',
    );
    firstRename.complete(
      WorkspaceNoteRenameSuccess([_note(title: 'Saved first', revision: 2)]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(notes.renamed, hasLength(2));
    expect(notes.renamed.last.$2, 'Latest edit');
    expect(notes.renameOutcomes.last, isA<WorkspaceNoteRenameSuccess>());
    expect(
      notes.state.notes.singleWhere((note) => note.id == 'note-1').revision,
      3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('save failure is sanitized and retry stores returned revision', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a')
      ..saveError = PostgrestException(
        message: 'sensitive backend detail',
        code: '42P01',
      );
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());
    await tester.enterText(
      find.byKey(const ValueKey('note-markdown-editor')),
      'Draft content',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Notes cloud storage is not ready.'),
      findsOneWidget,
    );
    expect(find.textContaining('sensitive backend detail'), findsNothing);
    expect(notes.saved, hasLength(1));

    notes.saveError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(notes.saved, hasLength(2));
    expect(notes.saved.last.markdownContent, 'Draft content');

    await tester.enterText(
      find.byKey(const ValueKey('note-markdown-editor')),
      'Draft content plus',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(notes.saved.last.revision, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflict preserves draft and explicit reload uses remote text', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    notes.saveHandler = (note) async => WorkspaceNoteSaveConflict(
      _note(title: 'Remote title', markdown: 'Remote body', revision: 2),
    );
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());
    await tester.enterText(
      find.byKey(const ValueKey('note-markdown-editor')),
      'Local draft',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(
      find.text('This Note changed elsewhere. Your draft is preserved.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      'Local draft',
    );
    await tester.tap(find.text('Reload remote'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      'Remote body',
    );
    expect(notes.saved, hasLength(1));
  });

  testWidgets(
    'repeated conflicts retain draft and use latest remote revision',
    (tester) async {
      final notes = _FakeWorkspaceNotesNotifier('account-a');
      notes.outcomes.addAll([
        WorkspaceNoteSaveConflict(
          _note(title: 'Remote two', markdown: 'Remote body two', revision: 2),
        ),
        WorkspaceNoteSaveConflict(
          _note(
            title: 'Remote three',
            markdown: 'Remote body three',
            revision: 3,
          ),
        ),
        WorkspaceNoteSaveSuccess(
          _note(title: 'Local title', markdown: 'Local draft', revision: 4),
        ),
      ]);
      notes.saveHandler = (_) async => notes.outcomes.removeAt(0);
      await _openEditor(tester, notes);
      await _completeOpen(tester, notes, _note());
      await tester.enterText(
        find.byKey(const ValueKey('note-markdown-editor')),
        'Local draft',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my draft'));
      await tester.pumpAndSettle();
      expect(notes.saved[1].revision, 2);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('note-markdown-editor')),
            )
            .controller!
            .text,
        'Local draft',
      );
      expect(find.text('Latest remote revision: 3'), findsOneWidget);
      await tester.tap(find.text('Keep my draft'));
      await tester.pumpAndSettle();
      expect(notes.saved[2].revision, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending save completion after account switch stays isolated', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    final pendingRename = Completer<WorkspaceNoteRenameOutcome?>();
    notes.renameHandler = (_, _) => pendingRename.future;
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note(title: 'Private A'));
    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'Edit from A',
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(notes.renamed, hasLength(1));
    notes.state = const WorkspaceNotesState(accountId: 'account-b');
    await tester.pump();
    await tester.pump();
    expect(find.text('Private A'), findsNothing);
    pendingRename.complete(
      WorkspaceNoteRenameSuccess([_note(title: 'Edit from A', revision: 2)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit from A'), findsNothing);
    expect(notes.state.accountId, 'account-b');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uses a split editor on wide screens and a toggle on narrow screens',
    (tester) async {
      final notes = _FakeWorkspaceNotesNotifier('account-a');
      await _openEditor(tester, notes);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      expect(
        MediaQuery.sizeOf(tester.element(find.byType(NotesEditor))).width,
        greaterThanOrEqualTo(900),
      );
      await _completeOpen(tester, notes, _note(markdown: '# Test'));
      expect(
        find.byKey(const ValueKey('note-markdown-editor')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('note-markdown-preview')),
        findsOneWidget,
      );
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('note-markdown-preview')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('note-markdown-source')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('note-source-preview-toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('note-markdown-source')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('note-markdown-preview')), findsNothing);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('preview checklist links toggle and save Markdown tasks', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    const markdown = '- [ ] Review the source';
    await _completeOpen(tester, notes, _note(markdown: markdown));

    final preview = tester.widget<Markdown>(
      find.byKey(const ValueKey('note-markdown-preview')),
    );
    expect(preview.data, contains('[☐](varian-task://toggle/2)'));
    preview.onTapLink?.call('☐', 'varian-task://toggle/2', '');
    await tester.pump();

    final editor = tester.widget<TextField>(
      find.byKey(const ValueKey('note-markdown-editor')),
    );
    expect(editor.controller!.text, '- [x] Review the source');

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(notes.saved.last.markdownContent, '- [x] Review the source');
  });

  testWidgets('preview callout links fold and unfold without editing source', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    const markdown = '> [!note]- Details\n> Hidden body';
    final markerStart = markdown.indexOf('> [!note]');
    await _completeOpen(tester, notes, _note(markdown: markdown));

    var preview = tester.widget<Markdown>(
      find.byKey(const ValueKey('note-markdown-preview')),
    );
    expect(preview.data, contains('varian-callout://toggle/$markerStart/1'));
    expect(preview.data, isNot(contains('Hidden body')));
    preview.onTapLink?.call(
      'NOTE ▸',
      'varian-callout://toggle/$markerStart/1',
      '',
    );
    await tester.pump();

    preview = tester.widget<Markdown>(
      find.byKey(const ValueKey('note-markdown-preview')),
    );
    expect(preview.data, contains('varian-callout://toggle/$markerStart/0'));
    expect(preview.data, contains('Hidden body'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      markdown,
    );
    expect(notes.saved, isEmpty);
  });

  testWidgets('preview renders inline and block math but not code samples', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    const markdown = r'''Inline $x^2$ and `$literal$`.

$$
\frac{1}{2}
$$

```text
$x$
```''';
    await _completeOpen(tester, notes, _note(markdown: markdown));

    expect(find.byType(Math), findsNWidgets(2));
    final preview = tester.widget<Markdown>(
      find.byKey(const ValueKey('note-markdown-preview')),
    );
    expect(preview.data, markdown);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed math shows its original Markdown source', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    const markdown = r'Malformed $\invalidcommand$';
    await _completeOpen(tester, notes, _note(markdown: markdown));

    expect(find.byType(Math), findsOneWidget);
    expect(find.text(r'$\invalidcommand$'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      markdown,
    );
  });

  testWidgets('preview renders fenced Mermaid through the local renderer', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    const markdown = '```mermaid\nflowchart TD\n  A --> B\n```';
    await _completeOpen(tester, notes, _note(markdown: markdown));

    expect(find.byType(NotesMermaidBlockPreview), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      markdown,
    );
  });

  testWidgets('preview blocks remote and local image loading', (tester) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    const markdown =
        '![Remote](https://example.invalid/image.png)\n\n'
        '![Local](/private/notes.png)';
    await _completeOpen(tester, notes, _note(markdown: markdown));

    expect(find.byType(Image), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      markdown,
    );
  });

  testWidgets('renders image embeds only from the encrypted note cache', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    final attachmentId = '123e4567-e89b-12d3-a456-426614174000';
    final attachments = _FakeAttachmentRepository(
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      [_attachment(id: attachmentId)],
    );
    await _openEditor(tester, notes, attachmentRepository: attachments);
    await _completeOpen(
      tester,
      notes,
      _note(markdown: '![[attachment:$attachmentId]]'),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('note-attachment-$attachmentId')),
      findsOneWidget,
    );
    expect(attachments.cachedReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uploads and deletes scoped attachment embeds', (tester) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    const attachmentId = '123e4567-e89b-12d3-a456-426614174000';
    final attachments = _FakeAttachmentRepository(
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      [_attachment(id: attachmentId)],
    );
    await _openEditor(
      tester,
      notes,
      attachmentRepository: attachments,
      attachmentPicker: () async => (
        name: 'diagram.png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
    );
    await _completeOpen(tester, notes, _note());

    await tester.tap(
      find.byKey(const ValueKey('note-attachment-insert-action')),
    );
    await tester.pumpAndSettle();

    expect(attachments.uploadCalls, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      contains('![[attachment:$attachmentId]]'),
    );
    await tester.tap(find.byTooltip('Delete attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(attachments.deleteCalls, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      isNot(contains('![[attachment:$attachmentId]]')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('markdown toolbar wraps selection and preserves source on save', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());
    await tester.enterText(
      find.byKey(const ValueKey('note-markdown-editor')),
      'hello',
    );
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('note-markdown-editor')),
    );
    field.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('markdown-bold-action')));
    await tester.pump();
    expect(field.controller!.text, '**hello**');
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 9, extentOffset: 9),
    );
    await tester.tap(find.byKey(const ValueKey('markdown-undo-action')));
    await tester.pump();
    expect(field.controller!.text, 'hello');
    await tester.tap(find.byKey(const ValueKey('markdown-redo-action')));
    await tester.pump();
    expect(field.controller!.text, '**hello**');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(notes.saved.last.markdownContent, '**hello**');
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('keyboard shortcuts format and undo Markdown source', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());
    final editor = find.byKey(const ValueKey('note-markdown-editor'));
    final field = tester.widget<TextField>(editor);
    await tester.enterText(editor, 'word');
    field.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(field.controller!.text, '**word**');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(field.controller!.text, 'word');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(field.controller!.text, '**word**');
  });

  testWidgets('undo and redo cover typing and toolbar edits in order', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());
    final editor = find.byKey(const ValueKey('note-markdown-editor'));
    final field = tester.widget<TextField>(editor);

    await tester.enterText(editor, 'plain');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('markdown-undo-action')));
    await tester.pump();
    expect(field.controller!.text, '');

    await tester.tap(find.byKey(const ValueKey('markdown-redo-action')));
    await tester.pump();
    expect(field.controller!.text, 'plain');

    field.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('markdown-bold-action')));
    await tester.pump();
    expect(field.controller!.text, '**plain**');

    await tester.tap(find.byKey(const ValueKey('markdown-undo-action')));
    await tester.pump();
    expect(field.controller!.text, 'plain');
    await tester.tap(find.byKey(const ValueKey('markdown-undo-action')));
    await tester.pump();
    expect(field.controller!.text, '');
    await tester.tap(find.byKey(const ValueKey('markdown-redo-action')));
    await tester.pump();
    expect(field.controller!.text, 'plain');
    await tester.tap(find.byKey(const ValueKey('markdown-redo-action')));
    await tester.pump();
    expect(field.controller!.text, '**plain**');
  });

  testWidgets('italic and heading actions preserve source selection', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());
    final editor = find.byKey(const ValueKey('note-markdown-editor'));
    final field = tester.widget<TextField>(editor);

    await tester.enterText(editor, 'word');
    field.controller!.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 4,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('markdown-italic-action')));
    await tester.pump();
    expect(field.controller!.text, 'w*ord*');
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 6, extentOffset: 6),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(notes.saved.last.markdownContent, 'w*ord*');

    await tester.enterText(editor, 'Title');
    field.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('markdown-heading-action')));
    await tester.pump();
    expect(field.controller!.text, '## Title');
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 8, extentOffset: 8),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(notes.saved.last.markdownContent, '## Title');
  });

  testWidgets('exports the current Markdown snapshot without saving', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    String? savedFileName;
    String? savedMimeType;
    Uint8List? savedBytes;
    final saver = ExportFileSaver(
      isWeb: false,
      saveFile:
          ({
            required fileName,
            required bytes,
            required mimeType,
            dialogTitle,
          }) async {
            savedFileName = fileName;
            savedBytes = bytes;
            savedMimeType = mimeType;
            return Uri.file('saved.md');
          },
    );
    await _openEditor(
      tester,
      notes,
      exportFileSaver: saver,
      wrapInScaffold: true,
    );
    await _completeOpen(
      tester,
      notes,
      _note(title: 'Bad:?Title', markdown: '# Original'),
    );
    const exactMarkdown =
        '---\\nstatus: active\\n---\\n## Exact **Markdown**\\n'
        '[[Target]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000-->\\n';
    await tester.enterText(find.byType(TextField).first, 'Bad:?Changed title');
    await tester.enterText(
      find.byKey(const ValueKey('note-markdown-editor')),
      exactMarkdown,
    );
    await tester.tap(find.byKey(const ValueKey('note-export-action')));
    await tester.pump();
    expect(savedFileName, 'Bad__Changed title.md');
    expect(savedMimeType, 'text/markdown');
    expect(savedBytes, Uint8List.fromList(utf8.encode(exactMarkdown)));
    expect(notes.saved, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Bad:?Changed title',
    );
  });

  testWidgets('export cancellation is silent', (tester) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    final saver = ExportFileSaver(
      isWeb: false,
      saveFile:
          ({
            required fileName,
            required bytes,
            required mimeType,
            dialogTitle,
          }) async => null,
    );
    await _openEditor(
      tester,
      notes,
      exportFileSaver: saver,
      wrapInScaffold: true,
    );
    await _completeOpen(tester, notes, _note());
    await tester.tap(find.byKey(const ValueKey('note-export-action')));
    await tester.pumpAndSettle();
    expect(find.text('Could not export this Note. Try again.'), findsNothing);
    expect(notes.saved, isEmpty);
  });

  testWidgets('export failure shows safe retryable message', (tester) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    final saver = ExportFileSaver(
      isWeb: false,
      saveFile:
          ({
            required fileName,
            required bytes,
            required mimeType,
            dialogTitle,
          }) async => throw Exception('private note content'),
    );
    await _openEditor(
      tester,
      notes,
      exportFileSaver: saver,
      wrapInScaffold: true,
    );
    await _completeOpen(tester, notes, _note(markdown: 'private note content'));
    await tester.tap(find.byKey(const ValueKey('note-export-action')));
    await tester.pumpAndSettle();
    expect(find.text('Could not export this Note. Try again.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('private note content'),
      ),
      findsNothing,
    );
    expect(notes.saved, isEmpty);
  });

  testWidgets('wiki suggestions insert a stable note ID marker', (
    tester,
  ) async {
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    final source = _note();
    await _completeOpen(tester, notes, source);
    final target = _note(id: targetId, title: 'Systems thinking');
    notes.state = notes.state.copyWith(notes: [source, target]);

    await tester.enterText(
      find.byKey(const ValueKey('note-markdown-editor')),
      '[[Syst',
    );
    await tester.pump();
    final suggestion = find.byKey(ValueKey('wiki-suggestion-$targetId'));
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion);
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      '[[Systems thinking]]<!--varian-note-id:$targetId-->',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates unresolved links in the current project scope', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    final source = _note(projectId: 'project-1');
    await _completeOpen(tester, notes, source);
    notes.createHandler = (title, projectId) async {
      final created = _note(
        id: 'created-note',
        title: title,
        projectId: projectId,
      );
      notes.state = notes.state.copyWith(
        notes: [created, ...notes.state.notes],
      );
      return created;
    };

    await tester.enterText(
      find.byKey(const ValueKey('note-markdown-editor')),
      '[[New topic',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('wiki-create-target-action')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('wiki-create-target-action')));
    await tester.pump();

    expect(notes.createRequests, [('New topic', 'project-1')]);
    final markdownField = tester.widget<TextField>(
      find.byKey(const ValueKey('note-markdown-editor')),
    );
    expect(
      markdownField.controller!.text,
      '[[New topic]]<!--varian-note-id:created-note-->',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(notes.saved.last.markdownContent, markdownField.controller!.text);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ignores a created target when the query changes while waiting', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note(projectId: 'project-1'));
    final createResult = Completer<WorkspaceNote?>();
    notes.createHandler = (_, _) => createResult.future;

    final editor = find.byKey(const ValueKey('note-markdown-editor'));
    await tester.enterText(editor, '[[Old topic');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wiki-create-target-action')));
    await tester.pump();
    await tester.enterText(editor, '[[Different topic');

    createResult.complete(
      _note(id: 'created-note', title: 'Old topic', projectId: 'project-1'),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(editor).controller!.text,
      '[[Different topic',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview opens only resolved stable note targets', (
    tester,
  ) async {
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    final source = _note(
      markdown:
          '[[Systems thinking#Overview]]<!--varian-note-id:$targetId--> and [[Missing]]',
    );
    final target = _note(
      id: targetId,
      title: 'Systems thinking',
      markdown: '# Overview\nTarget body',
    );
    final notes = _FakeWorkspaceNotesNotifier('account-a')
      ..state = WorkspaceNotesState(
        accountId: 'account-a',
        notes: [source, target],
      );
    final router = GoRouter(
      initialLocation: '/notes/note-1',
      routes: [
        GoRoute(
          path: '/notes/:noteId',
          builder: (context, state) {
            final id = state.pathParameters['noteId'];
            return id == 'note-1'
                ? Scaffold(body: NotesEditor(noteId: 'note-1'))
                : Scaffold(
                    body: NotesEditor(
                      noteId: targetId,
                      anchorFragment: state.uri.queryParameters['anchor'],
                    ),
                  );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceNotesProvider.overrideWith((ref) => notes),
          activeDocumentTabControllerProvider.overrideWith(
            (ref) => _FakeTabController(ref),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await _completeOpen(tester, notes, source);
    final preview = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .where((field) => field.readOnly)
        .single;
    expect(preview.controller.text, 'Systems thinking and [[Missing]]');
    expect(preview.controller.text, isNot(contains('varian-note-id')));

    final previewRect = tester.getRect(find.byWidget(preview));
    await tester.tapAt(Offset(previewRect.left + 20, previewRect.top + 12));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(router.routeInformationProvider.value.uri.path, '/notes/$targetId');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['anchor'],
      'overview',
    );
    notes.pendingOpens[targetId]!.last.complete(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('note-markdown-source')), findsOneWidget);
    final sourceEditor = tester.widget<TextField>(
      find.byKey(const ValueKey('note-markdown-source')),
    );
    expect(sourceEditor.controller!.selection.extentOffset, 0);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(NotesEditor)),
      ).read(activeDocumentTabProvider),
      OpenDocumentTab.note(target),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename uses the linked-note workflow', (tester) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());

    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'Renamed note',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(notes.renamed, [('note-1', 'Renamed note')]);
    expect(notes.saved, isEmpty);
    expect(notes.state.notes.single.title, 'Renamed note');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambiguous rename lists source notes and preserves draft', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    notes.renameHandler = (_, _) async =>
        WorkspaceNoteRenameBlocked({'source-1'});
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());
    notes.state = notes.state.copyWith(
      notes: [
        ...notes.state.notes,
        _note(id: 'source-1', title: 'Related note', markdown: '[[A Note]]'),
      ],
    );

    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'Renamed note',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('Resolve ambiguous links first'), findsOneWidget);
    expect(find.text('Related note'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-title-field')))
          .controller!
          .text,
      'Renamed note',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Resolve links opens only the ambiguous source notes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    const sourceId = '123e4567-e89b-12d3-a456-426614174001';
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    notes.renameHandler = (_, _) async =>
        WorkspaceNoteRenameBlocked({sourceId});
    final router = GoRouter(
      initialLocation: '/notes/$targetId',
      routes: [
        GoRoute(
          path: '/notes',
          builder: (_, _) => const NotesWorkspaceScreen(),
        ),
        GoRoute(
          path: '/notes/:noteId',
          builder: (_, state) => Scaffold(
            body: NotesEditor(noteId: state.pathParameters['noteId']!),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workspaceNotesProvider.overrideWith((ref) => notes)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await _completeOpen(
      tester,
      notes,
      _note(id: targetId, title: 'Target note'),
      noteId: targetId,
    );
    notes.state = notes.state.copyWith(
      notes: [
        ...notes.state.notes,
        _note(
          id: sourceId,
          title: 'Related source',
          markdown: '[[Target note]]<!--varian-note-id:$targetId-->',
        ),
      ],
    );

    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'Renamed target',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolve links'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/notes');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['resolveLinks'],
      sourceId,
    );
    expect(find.text('Related source'), findsOneWidget);
    expect(find.text('Target note'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rename failure preserves the title draft with recovery actions',
    (tester) async {
      final notes = _FakeWorkspaceNotesNotifier('account-a');
      notes.renameHandler = (_, _) async =>
          WorkspaceNoteRenameFailure(StateError('private backend detail'));
      await _openEditor(tester, notes);
      await _completeOpen(tester, notes, _note());

      await tester.enterText(
        find.byKey(const ValueKey('note-title-field')),
        'Keep this rename draft',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not rename this Note and update its links.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Reload'), findsOneWidget);
      expect(find.text('private backend detail'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-title-field')))
            .controller!
            .text,
        'Keep this rename draft',
      );
    },
  );

  testWidgets('retry reruns a failed linked-note rename with its draft', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    var attempts = 0;
    notes.renameHandler = (_, title) async {
      attempts++;
      if (attempts == 1) {
        return WorkspaceNoteRenameFailure(StateError('temporary failure'));
      }
      final current = notes.state.notes.single;
      return WorkspaceNoteRenameSuccess([
        current.copyWith(title: title, revision: current.revision + 1),
      ]);
    };
    await _openEditor(tester, notes);
    await _completeOpen(tester, notes, _note());

    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'Retry this rename',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(notes.state.notes.single.title, 'Retry this rename');
    expect(
      find.text('Could not rename this Note and update its links.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reload discards a failed rename draft for the current note', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    notes.renameHandler = (_, _) async =>
        WorkspaceNoteRenameFailure(StateError('temporary failure'));
    notes.loadHandler = () async {
      notes.state = notes.state.copyWith(
        notes: [
          _note(title: 'Remote title', markdown: 'remote body', revision: 4),
        ],
      );
    };
    await _openEditor(tester, notes);
    await _completeOpen(
      tester,
      notes,
      _note(title: 'Original title', markdown: 'original body'),
    );

    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      'Unsent title',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Reload'), findsOneWidget);

    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-title-field')))
          .controller!
          .text,
      'Remote title',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-markdown-editor')))
          .controller!
          .text,
      'remote body',
    );
    expect(
      find.text('Could not rename this Note and update its links.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing out clears previous account note content', (
    tester,
  ) async {
    final notes = _FakeWorkspaceNotesNotifier('account-a');
    await _openEditor(tester, notes);
    await _completeOpen(
      tester,
      notes,
      _note(title: 'Private A', markdown: 'Secret content'),
    );
    expect(find.text('Private A'), findsOneWidget);
    notes.state = const WorkspaceNotesState();
    await tester.pumpAndSettle();
    expect(find.text('Private A'), findsNothing);
    expect(find.text('Secret content'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
