import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/workspace_note_folder.dart';
import 'package:varian/features/notes/presentation/notes_folder_dialog.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

const notesBookmarksFilterId = '__bookmarks__';

class NotesOrganizationPanel extends ConsumerWidget {
  const NotesOrganizationPanel({
    required this.accountId,
    required this.projectIds,
    required this.selectedProjectId,
    required this.onProjectSelected,
    required this.selectedFolderId,
    required this.onFolderSelected,
    super.key,
  });

  final String accountId;
  final List<String> projectIds;
  final String? selectedProjectId;
  final ValueChanged<String?> onProjectSelected;
  final String? selectedFolderId;
  final ValueChanged<String?> onFolderSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(
      workspaceScopedNoteFoldersProvider((accountId, selectedProjectId)),
    );
    final pins = ref.watch(workspacePinnedNotesProvider(accountId));

    Future<void> createFolder(String? parentId) async {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => const NotesFolderDialog(),
      );
      if (name == null || !context.mounted) return;
      await _runOrganizationAction(context, () async {
        await ref
            .read(workspaceNoteRepositoryProvider)
            .createFolder(
              name: name,
              projectId: selectedProjectId,
              parentFolderId: parentId,
              expectedAccountId: accountId,
            );
        ref.invalidate(
          workspaceScopedNoteFoldersProvider((accountId, selectedProjectId)),
        );
      });
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (projectIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: DropdownButtonFormField<String?>(
              key: const ValueKey('notes-scope-selector'),
              isExpanded: true,
              initialValue: selectedProjectId,
              decoration: const InputDecoration(
                labelText: 'Note scope',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Private notes'),
                ),
                for (final projectId in projectIds)
                  DropdownMenuItem<String?>(
                    value: projectId,
                    child: Text(
                      'Shared project · ${_shortProjectId(projectId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onProjectSelected,
            ),
          ),
        ListTile(
          key: const ValueKey('notes-bookmarks'),
          dense: true,
          leading: const Icon(Icons.push_pin_outlined),
          title: const Text('Bookmarks'),
          subtitle: pins.when(
            data: (items) => Text('${items.length} bookmarked notes'),
            loading: () => const Text('Loading bookmarks…'),
            error: (_, _) => const Text('Bookmarks unavailable.'),
          ),
          selected: selectedFolderId == notesBookmarksFilterId,
          onTap: () => onFolderSelected(notesBookmarksFilterId),
        ),
        ListTile(
          key: const ValueKey('notes-all-notes'),
          dense: true,
          leading: const Icon(Icons.notes_outlined),
          title: const Text('All notes'),
          selected: selectedFolderId == null,
          onTap: () => onFolderSelected(null),
        ),
        folders.when(
          data: (items) => Column(
            key: const ValueKey('notes-folder-tree'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No folders in this scope yet.'),
                ),
              for (final folder in items.where(
                (item) => item.parentFolderId == null,
              ))
                _FolderTreeItem(
                  folder: folder,
                  allFolders: items,
                  accountId: accountId,
                  projectId: selectedProjectId,
                  selectedFolderId: selectedFolderId,
                  onSelect: onFolderSelected,
                  onChanged: () => ref.invalidate(
                    workspaceScopedNoteFoldersProvider((
                      accountId,
                      selectedProjectId,
                    )),
                  ),
                  onCreate: createFolder,
                ),
              ListTile(
                key: const ValueKey('notes-new-folder'),
                dense: true,
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('New folder'),
                onTap: () => createFolder(null),
              ),
            ],
          ),
          loading: () => const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load folders.'),
                TextButton(
                  onPressed: () => ref.invalidate(
                    workspaceScopedNoteFoldersProvider((
                      accountId,
                      selectedProjectId,
                    )),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FolderTreeItem extends ConsumerWidget {
  const _FolderTreeItem({
    required this.folder,
    required this.allFolders,
    required this.accountId,
    required this.projectId,
    required this.selectedFolderId,
    required this.onSelect,
    required this.onChanged,
    required this.onCreate,
    this.depth = 0,
    this.ancestors = const {},
  });

  final WorkspaceNoteFolder folder;
  final List<WorkspaceNoteFolder> allFolders;
  final String accountId;
  final String? projectId;
  final String? selectedFolderId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onChanged;
  final Future<void> Function(String?) onCreate;
  final int depth;
  final Set<String> ancestors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ancestors.contains(folder.id)) return const SizedBox.shrink();
    final path = {...ancestors, folder.id};
    final children = allFolders
        .where((item) => item.parentFolderId == folder.id)
        .toList(growable: false);

    return Column(
      children: [
        ListTile(
          key: ValueKey('notes-folder-${folder.id}'),
          dense: true,
          contentPadding: EdgeInsetsDirectional.only(
            start: 12 + depth * 16,
            end: 4,
          ),
          leading: const Icon(Icons.folder_outlined),
          title: Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(projectId == null ? 'Private' : 'Shared project'),
          selected: selectedFolderId == folder.id,
          onTap: () => onSelect(folder.id),
          trailing: PopupMenuButton<String>(
            tooltip: 'Folder actions: ${folder.name}',
            onSelected: (action) => _handleAction(context, ref, action),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('New subfolder')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'move', child: Text('Move folder')),
              PopupMenuItem(value: 'delete', child: Text('Delete folder')),
            ],
          ),
        ),
        for (final child in children)
          _FolderTreeItem(
            folder: child,
            allFolders: allFolders,
            accountId: accountId,
            projectId: projectId,
            selectedFolderId: selectedFolderId,
            onSelect: onSelect,
            onChanged: onChanged,
            onCreate: onCreate,
            depth: depth + 1,
            ancestors: path,
          ),
      ],
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    if (action == 'new') {
      await onCreate(folder.id);
      return;
    }
    if (action == 'rename') {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => NotesFolderDialog(initialName: folder.name),
      );
      if (name == null || !context.mounted) return;
      await _runOrganizationAction(context, () async {
        await ref
            .read(workspaceNoteRepositoryProvider)
            .renameFolder(
              folderId: folder.id,
              name: name,
              expectedAccountId: accountId,
            );
        onChanged();
      });
      return;
    }
    if (action == 'move') {
      final parentId = await _chooseParent(context);
      if (parentId == null || !context.mounted) return;
      await _runOrganizationAction(context, () async {
        await ref
            .read(workspaceNoteRepositoryProvider)
            .moveFolder(
              folderId: folder.id,
              parentFolderId: parentId.isEmpty ? null : parentId,
              expectedAccountId: accountId,
            );
        onChanged();
      });
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete folder?'),
          content: const Text(
            'Notes and child folders will move to the parent. Note content will be kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await _runOrganizationAction(context, () async {
        await ref
            .read(workspaceNoteRepositoryProvider)
            .deleteFolder(folderId: folder.id, expectedAccountId: accountId);
        onChanged();
        if (selectedFolderId == folder.id) onSelect(null);
      });
    }
  }

  Future<String?> _chooseParent(BuildContext context) => showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final candidates = allFolders.where((candidate) {
        if (candidate.id == folder.id) return false;
        var current = candidate.parentFolderId;
        final visited = <String>{candidate.id};
        while (current != null && visited.add(current)) {
          if (current == folder.id) return false;
          current = allFolders
              .where((item) => item.id == current)
              .firstOrNull
              ?.parentFolderId;
        }
        return true;
      });
      return SimpleDialog(
        title: const Text('Move folder'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Move to root'),
          ),
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, candidate.id),
              child: Text(candidate.name),
            ),
        ],
      );
    },
  );
}

class NotesNoteActions extends ConsumerWidget {
  const NotesNoteActions({
    required this.noteId,
    required this.accountId,
    required this.isPinned,
    required this.folders,
    super.key,
  });

  final String noteId;
  final String accountId;
  final bool isPinned;
  final List<WorkspaceNoteFolder> folders;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    key: ValueKey('notes-actions-$noteId'),
    tooltip: 'Note actions',
    onSelected: (action) async {
      await _runOrganizationAction(context, () async {
        final repository = ref.read(workspaceNoteRepositoryProvider);
        if (action == 'pin') {
          await repository.setPinned(
            noteId: noteId,
            pinned: !isPinned,
            expectedAccountId: accountId,
          );
          ref.invalidate(workspacePinnedNotesProvider(accountId));
        } else {
          await repository.moveNoteToFolder(
            noteId: noteId,
            folderId: action == 'root' ? null : action,
            expectedAccountId: accountId,
          );
          await ref.read(workspaceNotesProvider.notifier).load();
        }
      });
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'pin',
        child: Text(isPinned ? 'Remove from Bookmarks' : 'Add to Bookmarks'),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'root', child: Text('Move to top level')),
      for (final folder in folders)
        PopupMenuItem(value: folder.id, child: Text('Move to ${folder.name}')),
    ],
    icon: const Icon(Icons.more_vert),
  );
}

Future<void> _runOrganizationAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update note organization.')),
      );
    }
  }
}

String _shortProjectId(String projectId) => projectId.length <= 10
    ? projectId
    : '${projectId.substring(0, 6)}…${projectId.substring(projectId.length - 3)}';
