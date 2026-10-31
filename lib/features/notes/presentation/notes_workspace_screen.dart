import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/export/data/export_file_saver.dart';
import 'package:varian/features/notes/data/notes_export_service.dart';
import 'package:varian/features/notes/data/notes_import_service.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/data/notes_key_envelope_repository.dart';
import 'package:varian/features/notes/data/notes_key_manager.dart';
import 'package:varian/features/notes/domain/note_markdown_metadata.dart';
import 'package:varian/features/notes/presentation/notes_import_dialog.dart';
import 'package:varian/features/notes/presentation/notes_recovery_dialog.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_folder.dart';
import 'package:varian/features/notes/domain/workspace_notes_index.dart';
import 'package:varian/features/notes/presentation/notes_context_panel.dart';
import 'package:varian/features/notes/presentation/notes_canvas_screen.dart';
import 'package:varian/features/notes/presentation/notes_organization_panel.dart';
import 'package:varian/features/notes/presentation/notes_editor.dart';
import 'package:varian/features/notes/presentation/workspace_note_scope_change_dialog.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';
import 'package:varian/features/notes/state/notes_offline_provider.dart';
import 'package:varian/data/remote/supabase_service.dart';

class NotesWorkspaceScreen extends ConsumerStatefulWidget {
  const NotesWorkspaceScreen({
    this.selectedNoteId,
    this.selectedAnchorFragment,
    super.key,
  });

  final String? selectedNoteId;
  final String? selectedAnchorFragment;
  @override
  ConsumerState<NotesWorkspaceScreen> createState() =>
      _NotesWorkspaceScreenState();
}

class _NotesWorkspaceScreenState extends ConsumerState<NotesWorkspaceScreen> {
  String query = '';
  String? selectedId;
  String? selectedTag;
  String? selectedProjectId;
  String? selectedFolderId;
  bool showContext = true;

  @override
  void initState() {
    super.initState();
    selectedId = widget.selectedNoteId;
  }

  @override
  void didUpdateWidget(covariant NotesWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedNoteId != widget.selectedNoteId) {
      selectedId = widget.selectedNoteId;
    }
  }

  Future<void> _openNote(String noteId) async {
    final before = ref.read(workspaceNotesProvider);
    final accountId = before.accountId;
    if (accountId == null) return;
    final note =
        before.notes.where((item) => item.id == noteId).firstOrNull ??
        await ref.read(workspaceNotesProvider.notifier).openNote(noteId);
    if (!mounted ||
        note == null ||
        (note.projectId == null && note.ownerUserId != accountId)) {
      return;
    }
    final current = ref.read(workspaceNotesProvider);
    if (current.accountId != accountId) return;
    await ref
        .read(activeDocumentTabControllerProvider)
        .select(OpenDocumentTab.note(note));
    if (!mounted || ref.read(workspaceNotesProvider).accountId != accountId) {
      return;
    }
    setState(() => selectedId = note.id);
    context.go('/notes/${Uri.encodeComponent(note.id)}');
  }

  Future<void> _moveSelectedNoteScope(
    WorkspaceNote note,
    String accountId,
  ) async {
    if (ref.read(workspaceNotesProvider).accountId != accountId) return;
    final moved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => WorkspaceNoteScopeChangeDialog(
        note: note,
        accountId: accountId,
        repository: ref.read(workspaceNoteRepositoryProvider),
        onScopeChanged: () async {
          if (ref.read(workspaceNotesProvider).accountId != accountId) return;
          ref.invalidate(workspaceScopedNoteFoldersProvider);
          await ref.read(workspaceNotesProvider.notifier).load();
        },
      ),
    );
    if (!mounted || moved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          CreativeStudioLocalizations.of(context).notesScopeChangeDone,
        ),
      ),
    );
  }

  Future<void> _openDailyNote({
    required DateTime localDate,
    required String? projectId,
    required String accountId,
  }) async {
    final before = ref.read(workspaceNotesProvider);
    if (before.accountId != accountId ||
        before.loading ||
        selectedProjectId != projectId) {
      return;
    }
    final note = await ref
        .read(workspaceNotesProvider.notifier)
        .getOrCreateDailyNote(localDate: localDate, projectId: projectId);
    if (!mounted) return;
    final current = ref.read(workspaceNotesProvider);
    if (current.accountId != accountId || selectedProjectId != projectId) {
      return;
    }
    if (note == null) {
      final error = current.error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              workspaceNotesFailureMessage(error, accountId: accountId),
            ),
          ),
        );
      }
      return;
    }
    if (note.projectId != projectId ||
        (projectId == null && note.ownerUserId != accountId)) {
      return;
    }
    await _openNote(note.id);
  }

  void _openTemplates(String? projectId) {
    final route = projectId == null
        ? '/notes/templates'
        : Uri(
            path: '/notes/templates',
            queryParameters: {'projectId': projectId},
          ).toString();
    context.go(route);
  }

  Future<void> _recoverNotesKey() async {
    final accountId = ref.read(workspaceNotesProvider).accountId;
    final offline = ref.read(notesOfflineServiceProvider);
    final client = ref.read(supabaseClientProvider);
    if (accountId == null || offline == null || client == null) return;
    try {
      final envelope = await NotesKeyEnvelopeRepository(client).get(accountId);
      if (!mounted || ref.read(workspaceNotesProvider).accountId != accountId) {
        return;
      }
      final result = await showDialog<bool>(
        context: context,
        builder: (_) => NotesRecoveryDialog(
          accountId: accountId,
          manager: NotesKeyManager(),
          envelope: envelope,
          persistEnvelope: (value) =>
              NotesKeyEnvelopeRepository(client).save(accountId, value),
          persistKey: (key) async {
            await offline.store.storeDeviceKey(accountId: accountId, key: key);
            if (!offline.store.isEnabled) {
              throw StateError('Secure storage is unavailable.');
            }
          },
        ),
      );
      if (!mounted || result != true) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encrypted Notes recovery is ready.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notes recovery is unavailable. Try again.'),
        ),
      );
    }
  }

  Future<void> _exportNotes(
    List<WorkspaceNote> notes,
    List<WorkspaceNoteFolder> folders,
  ) async {
    if (notes.isEmpty) return;
    try {
      final bytes = NotesExportService().exportZip(notes, folders);
      final outcome = await ExportFileSaver().save(
        fileName: 'notes-export.zip',
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: 'Export notes',
      );
      if (!mounted || outcome == ExportSaveOutcome.saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note export was canceled.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export notes. Try again.')),
      );
    }
  }

  Future<void> _importNotes(WorkspaceNotesState state) async {
    final selection = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['md', 'zip', 'json'],
    );
    if (!mounted || selection.isEmpty) return;
    final NotesImportPreview preview;
    try {
      preview = await NotesImportService().decodeSelection(
        files: selection,
        existingNotes: state.notes
            .where((note) => note.projectId == selectedProjectId)
            .toList(),
      );
    } on NotesImportException catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import could not be prepared'),
          content: Text(error.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => NotesImportDialog(
        preview: preview,
        projectId: selectedProjectId,
        onImport: (notes, projectId) => ref
            .read(workspaceNotesProvider.notifier)
            .importNotes(notes: notes, projectId: projectId),
        onImported: (notes) async {
          ref.invalidate(workspaceScopedNoteFoldersProvider);
          await ref.read(workspaceNotesProvider.notifier).load();
          if (notes.isNotEmpty && mounted) await _openNote(notes.first.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceNotesProvider, (previous, next) {
      if (previous?.accountId != next.accountId) {
        setState(() {
          selectedId = widget.selectedNoteId;
          selectedTag = null;
          selectedProjectId = null;
          selectedFolderId = null;
          query = '';
        });
      }
    });
    final state = ref.watch(workspaceNotesProvider);
    final activeNotes = state.notes
        .where((note) => note.deletedAt == null)
        .toList(growable: false);
    final projectIds =
        activeNotes
            .map((note) => note.projectId)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final selectedScopeProjectId = projectIds.contains(selectedProjectId)
        ? selectedProjectId
        : null;
    final scopedNotes = activeNotes
        .where((note) {
          if (note.projectId != selectedScopeProjectId) return false;
          return selectedScopeProjectId != null ||
              note.ownerUserId == state.accountId;
        })
        .toList(growable: false);
    final folders = state.accountId == null
        ? const AsyncData<List<WorkspaceNoteFolder>>([])
        : ref.watch(
            workspaceScopedNoteFoldersProvider((
              state.accountId!,
              selectedScopeProjectId,
            )),
          );
    final pins = state.accountId == null
        ? const AsyncData<List<WorkspaceNote>>([])
        : ref.watch(workspacePinnedNotesProvider(state.accountId!));
    final pinnedNotes = pins.valueOrNull ?? const <WorkspaceNote>[];
    final pinnedIds = pinnedNotes.map((note) => note.id).toSet();
    final index = WorkspaceNotesIndex(scopedNotes);
    final activeTab = ref.watch(activeDocumentTabProvider);
    final activeTabId =
        activeTab?.isNote == true &&
            activeTab!.ownerAccountId == state.accountId
        ? activeTab.documentId
        : null;
    final effectiveSelectedId =
        widget.selectedNoteId ?? selectedId ?? activeTabId;
    final resolveIds = GoRouterState.of(context)
        .uri
        .queryParameters['resolveLinks']
        ?.split(',')
        .where((id) => id.isNotEmpty)
        .toSet();
    final isBookmarks = selectedFolderId == notesBookmarksFilterId;
    final notes =
        index
            .search(query)
            .where((note) => !isBookmarks || pinnedIds.contains(note.id))
            .where(
              (note) =>
                  selectedFolderId == null ||
                  isBookmarks ||
                  note.folderId == selectedFolderId,
            )
            .where(
              (note) =>
                  selectedTag == null ||
                  parseNoteMarkdownMetadata(
                    note.markdownContent,
                  ).tags.contains(selectedTag),
            )
            .where((note) => resolveIds == null || resolveIds.contains(note.id))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recentNotes =
        selectedFolderId == null &&
            query.trim().isEmpty &&
            selectedTag == null &&
            resolveIds == null
        ? notes.take(5).toList(growable: false)
        : const <WorkspaceNote>[];
    final allNotes = recentNotes.isEmpty
        ? notes
        : notes.skip(recentNotes.length).toList(growable: false);
    final selected = activeNotes
        .where((n) => n.id == effectiveSelectedId)
        .firstOrNull;
    final scopeChangeAccess = selected == null || state.accountId == null
        ? const AsyncData<bool>(false)
        : ref.watch(
            workspaceNoteScopeChangeEligibilityProvider((
              state.accountId!,
              selected.id,
            )),
          );
    final canManageScopeChange = scopeChangeAccess.valueOrNull == true;
    final narrow = AppResponsive.isNarrow(context);
    final compact = MediaQuery.sizeOf(context).width < 1200;
    Widget noteTile(WorkspaceNote note) => ListTile(
      key: ValueKey('workspace-note-${note.id}'),
      selected: effectiveSelectedId == note.id,
      title: Text(note.title),
      subtitle: Text(note.projectId == null ? 'Private' : 'Shared project'),
      trailing: state.accountId == null
          ? null
          : NotesNoteActions(
              noteId: note.id,
              accountId: state.accountId!,
              isPinned: pinnedIds.contains(note.id),
              folders:
                  folders.valueOrNull
                      ?.where((folder) => folder.projectId == note.projectId)
                      .toList(growable: false) ??
                  const [],
            ),
      onTap: () => _openNote(note.id),
    );
    final library = Column(
      children: [
        if (state.accountId != null)
          SizedBox(
            height: 240,
            child: NotesOrganizationPanel(
              accountId: state.accountId!,
              projectIds: projectIds,
              selectedProjectId: selectedScopeProjectId,
              onProjectSelected: (projectId) => setState(() {
                selectedProjectId = projectId;
                selectedFolderId = null;
              }),
              selectedFolderId: selectedFolderId,
              onFolderSelected: (folderId) =>
                  setState(() => selectedFolderId = folderId),
            ),
          ),
        TextField(
          key: const ValueKey('notes-workspace-search'),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search notes, tags, properties',
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        Expanded(
          child: ListView(
            children: [
              if (index.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in index.tags)
                        FilterChip(
                          label: Text('#$tag'),
                          selected: selectedTag == tag,
                          onSelected: (selected) => setState(
                            () => selectedTag = selected ? tag : null,
                          ),
                        ),
                    ],
                  ),
                ),
              if (recentNotes.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Text('Recent'),
                ),
                for (final note in recentNotes) noteTile(note),
              ],
              if (allNotes.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Text(
                    resolveIds != null
                        ? 'Resolve links'
                        : query.trim().isNotEmpty || selectedTag != null
                        ? 'Search results'
                        : 'All notes',
                  ),
                ),
                for (final note in allNotes) noteTile(note),
              ],
              if (isBookmarks && pins.isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Loading bookmarks…'),
                ),
              if (isBookmarks && pins.hasError)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Could not load bookmarks.'),
                ),
              if (notes.isEmpty &&
                  !(isBookmarks && (pins.isLoading || pins.hasError)))
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    isBookmarks
                        ? 'No bookmarked notes in this scope.'
                        : selectedFolderId == null
                        ? 'No notes match these filters.'
                        : 'No notes in this folder.',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    final editor = selected == null
        ? const Center(child: Text('Select a note to open it'))
        : NotesEditor(
            key: ValueKey('workspace-editor-${selected.id}'),
            noteId: selected.id,
            anchorFragment: widget.selectedAnchorFragment,
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.selectedNoteId == null
              ? 'Notes'
              : selected?.projectId == null
              ? 'Private Note'
              : 'Shared project note',
        ),
        leading: widget.selectedNoteId == null
            ? null
            : IconButton(
                tooltip: 'Back to Canvas',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/');
                  }
                },
                icon: const Icon(Icons.arrow_back),
              ),
        actions: [
          if (state.accountId != null && !narrow)
            IconButton(
              tooltip: 'Set up or unlock offline Notes',
              icon: const Icon(Icons.key_outlined),
              onPressed: _recoverNotesKey,
            ),
          if (state.accountId != null &&
              selected != null &&
              canManageScopeChange &&
              !compact)
            IconButton(
              key: const ValueKey('notes-move-scope-action'),
              tooltip: CreativeStudioLocalizations.of(
                context,
              ).notesMoveScopeAction,
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: state.loading
                  ? null
                  : () => _moveSelectedNoteScope(selected, state.accountId!),
            ),
          if (!narrow || selected == null)
            IconButton(
              tooltip: 'Import Markdown notes',
              icon: const Icon(Icons.file_upload_outlined),
              onPressed: () => _importNotes(state),
            ),
          if (state.accountId != null && !compact)
            IconButton(
              key: const ValueKey('notes-canvas-action'),
              tooltip: 'Notes Canvas',
              icon: const Icon(Icons.dashboard_customize_outlined),
              onPressed: () => context.go(
                notesCanvasRoute(projectId: selectedScopeProjectId),
              ),
            ),
          if (state.accountId != null && !compact)
            IconButton(
              key: const ValueKey('notes-templates-action'),
              tooltip: 'Manage templates',
              icon: const Icon(Icons.description_outlined),
              onPressed: () => _openTemplates(selectedScopeProjectId),
            ),
          if (state.accountId != null && (!narrow || selected == null))
            IconButton(
              key: const ValueKey('notes-daily-note-action'),
              tooltip: 'Open Daily Note',
              icon: const Icon(Icons.today_outlined),
              onPressed: state.loading
                  ? null
                  : () => _openDailyNote(
                      localDate: DateTime.now(),
                      projectId: selectedScopeProjectId,
                      accountId: state.accountId!,
                    ),
            ),
          if (!narrow || selected == null)
            IconButton(
              tooltip: 'Export notes',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: scopedNotes.isEmpty
                  ? null
                  : () => _exportNotes(
                      scopedNotes,
                      folders.valueOrNull ?? const <WorkspaceNoteFolder>[],
                    ),
            ),
          if (!narrow || selected == null)
            IconButton(
              tooltip: 'New note',
              icon: const Icon(Icons.add),
              onPressed: () async {
                final note = await ref
                    .read(workspaceNotesProvider.notifier)
                    .createNote();
                if (note != null && mounted) await _openNote(note.id);
              },
            ),
          if (narrow && selected != null)
            IconButton(
              tooltip: 'All notes',
              icon: const Icon(Icons.list),
              onPressed: () => context.go('/notes'),
            ),
          if (compact)
            PopupMenuButton<String>(
              tooltip: 'More Notes actions',
              onSelected: (action) async {
                if (action == 'moveScope' &&
                    selected != null &&
                    state.accountId != null &&
                    canManageScopeChange) {
                  await _moveSelectedNoteScope(selected, state.accountId!);
                } else if (action == 'templates') {
                  _openTemplates(selectedScopeProjectId);
                } else if (action == 'daily') {
                  final accountId = state.accountId;
                  if (accountId != null) {
                    await _openDailyNote(
                      localDate: DateTime.now(),
                      projectId: selectedScopeProjectId,
                      accountId: accountId,
                    );
                  }
                } else if (action == 'recovery') {
                  await _recoverNotesKey();
                } else if (action == 'canvas') {
                  context.go(
                    notesCanvasRoute(projectId: selectedScopeProjectId),
                  );
                } else if (action == 'graph') {
                  context.go('/notes/graph');
                } else if (action == 'trash') {
                  context.go('/notes/trash');
                }
              },
              itemBuilder: (context) => [
                if (state.accountId != null &&
                    selected != null &&
                    canManageScopeChange)
                  PopupMenuItem(
                    value: 'moveScope',
                    child: Text(
                      CreativeStudioLocalizations.of(
                        context,
                      ).notesMoveScopeAction,
                    ),
                  ),
                if (state.accountId != null)
                  const PopupMenuItem(
                    value: 'templates',
                    child: Text('Manage templates'),
                  ),
                if (state.accountId != null && selected != null)
                  PopupMenuItem(
                    value: 'daily',
                    enabled: !state.loading,
                    child: Text('Daily note'),
                  ),
                if (state.accountId != null)
                  const PopupMenuItem(
                    value: 'recovery',
                    child: Text('Offline recovery'),
                  ),
                if (state.accountId != null)
                  const PopupMenuItem(
                    value: 'canvas',
                    child: Text('Notes Canvas'),
                  ),
                const PopupMenuItem(
                  value: 'graph',
                  child: Text('Knowledge graph'),
                ),
                const PopupMenuItem(value: 'trash', child: Text('Trash')),
              ],
            )
          else ...[
            IconButton(
              tooltip: 'Knowledge graph',
              icon: const Icon(Icons.hub_outlined),
              onPressed: () => context.go('/notes/graph'),
            ),
            IconButton(
              tooltip: 'Trash',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => context.go('/notes/trash'),
            ),
          ],
          if (narrow)
            IconButton(
              tooltip: 'Context panel',
              icon: const Icon(Icons.info_outline),
              onPressed: () => setState(() => showContext = !showContext),
            ),
        ],
      ),
      body: narrow
          ? selected == null
                ? Padding(
                    padding: AppResponsive.pagePadding(context),
                    child: library,
                  )
                : Column(
                    children: [
                      Expanded(child: editor),
                      if (showContext)
                        SizedBox(
                          height: 220,
                          child: NotesContextPanel(
                            note: selected,
                            index: index,
                            onOpen: (n) => _openNote(n.id),
                          ),
                        ),
                    ],
                  )
          : Row(
              children: [
                SizedBox(
                  width: 264,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: library,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selected == null
                      ? const Center(child: Text('Select a note to open it'))
                      : editor,
                ),
                if (showContext && selected != null)
                  SizedBox(
                    width: 320,
                    child: NotesContextPanel(
                      note: selected,
                      index: index,
                      onOpen: (n) => _openNote(n.id),
                    ),
                  ),
              ],
            ),
    );
  }
}
