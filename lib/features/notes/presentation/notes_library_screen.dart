import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/workspace_timestamp.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_folder.dart';
import 'package:varian/features/notes/presentation/notes_organization_panel.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';

class NotesLibraryScreen extends ConsumerStatefulWidget {
  const NotesLibraryScreen({super.key});

  @override
  ConsumerState<NotesLibraryScreen> createState() => _NotesLibraryScreenState();
}

class _NotesLibraryScreenState extends ConsumerState<NotesLibraryScreen> {
  String _query = '';
  String? _selectedProjectId;
  String? _selectedFolderId;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openNote(String noteId) async {
    final before = ref.read(workspaceNotesProvider);
    final accountId = before.accountId;
    if (accountId == null) return;
    final note = await ref
        .read(workspaceNotesProvider.notifier)
        .openNote(noteId);
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
    if (!mounted) return;
    context.go('/notes/${Uri.encodeComponent(note.id)}');
  }

  String _excerpt(String markdown) {
    final plain = markdown
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'[#>*_~`-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return plain.length <= 160 ? plain : '${plain.substring(0, 157)}…';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceNotesProvider, (previous, next) {
      if (previous?.accountId != next.accountId) {
        _searchController.clear();
        setState(() {
          _query = '';
          _selectedProjectId = null;
          _selectedFolderId = null;
        });
      }
    });
    final state = ref.watch(workspaceNotesProvider);
    final projectIds =
        state.notes
            .map((note) => note.projectId)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final selectedScopeProjectId = projectIds.contains(_selectedProjectId)
        ? _selectedProjectId
        : null;
    final scopedNotes = state.notes
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
    final pinnedIds = (pins.valueOrNull ?? const <WorkspaceNote>[])
        .map((note) => note.id)
        .toSet();
    final isBookmarks = _selectedFolderId == notesBookmarksFilterId;
    final needle = _query.trim().toLowerCase();
    final notes =
        scopedNotes
            .where((note) => !isBookmarks || pinnedIds.contains(note.id))
            .where(
              (note) =>
                  _selectedFolderId == null ||
                  isBookmarks ||
                  note.folderId == _selectedFolderId,
            )
            .where(
              (note) =>
                  needle.isEmpty ||
                  note.title.toLowerCase().contains(needle) ||
                  note.markdownContent.toLowerCase().contains(needle),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return UiPageScaffold(
      title: const Text('Notes'),
      actions: [
        TextButton(
          onPressed: () => context.go('/notes/trash'),
          child: const Text('Trash'),
        ),
        IconButton(
          tooltip: 'Create Note',
          icon: const Icon(Icons.add),
          onPressed: () async {
            final note = await ref
                .read(workspaceNotesProvider.notifier)
                .createNote();
            if (note != null && context.mounted) {
              await _openNote(note.id);
            }
          },
        ),
      ],
      childPad: false,
      child: Padding(
        padding: AppResponsive.pagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.accountId != null)
              SizedBox(
                height: 240,
                child: NotesOrganizationPanel(
                  accountId: state.accountId!,
                  projectIds: projectIds,
                  selectedProjectId: selectedScopeProjectId,
                  onProjectSelected: (projectId) => setState(() {
                    _selectedProjectId = projectId;
                    _selectedFolderId = null;
                  }),
                  selectedFolderId: _selectedFolderId,
                  onFolderSelected: (folderId) =>
                      setState(() => _selectedFolderId = folderId),
                ),
              ),
            TextField(
              controller: _searchController,
              key: const ValueKey('notes-library-search'),
              decoration: const InputDecoration(
                labelText: 'Search notes',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: state.loading && state.notes.isEmpty
                  ? const Center(child: UiLoadingState())
                  : state.error != null && state.notes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Could not load Notes.'),
                          TextButton(
                            onPressed: () => ref
                                .read(workspaceNotesProvider.notifier)
                                .load(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : state.notes.isEmpty
                  ? const Center(
                      child: Text(
                        'No Notes yet. Create a Note to get started.',
                      ),
                    )
                  : notes.isEmpty
                  ? Center(
                      child: Text(
                        isBookmarks && pins.isLoading
                            ? 'Loading bookmarks…'
                            : isBookmarks && pins.hasError
                            ? 'Could not load bookmarks.'
                            : _selectedFolderId != null && !isBookmarks
                            ? 'No Notes in this folder.'
                            : 'No Notes match your search.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return ListTile(
                          key: ValueKey('note-${note.id}'),
                          title: Text(note.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _excerpt(note.markdownContent),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Modified ${formatWorkspaceTimestamp(note.updatedAt)}',
                              ),
                              Text(
                                note.projectId == null
                                    ? 'Private'
                                    : 'Shared project',
                              ),
                            ],
                          ),
                          trailing: state.accountId == null
                              ? null
                              : NotesNoteActions(
                                  noteId: note.id,
                                  accountId: state.accountId!,
                                  isPinned: pinnedIds.contains(note.id),
                                  folders:
                                      folders.valueOrNull
                                          ?.where(
                                            (folder) =>
                                                folder.projectId ==
                                                note.projectId,
                                          )
                                          .toList(growable: false) ??
                                      const [],
                                ),
                          onTap: () => _openNote(note.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
