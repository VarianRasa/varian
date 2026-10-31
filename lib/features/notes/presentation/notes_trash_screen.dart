import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/workspace_timestamp.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

class NotesTrashScreen extends ConsumerStatefulWidget {
  const NotesTrashScreen({super.key});

  @override
  ConsumerState<NotesTrashScreen> createState() => _NotesTrashScreenState();
}

class _NotesTrashScreenState extends ConsumerState<NotesTrashScreen> {
  String? _loadedAccount;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceNotesProvider);
    final accountId = state.accountId;
    if (_loadedAccount != accountId) {
      _loadedAccount = accountId;
      if (accountId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              ref.read(workspaceNotesProvider).accountId == accountId) {
            ref.read(workspaceNotesProvider.notifier).loadTrash();
          }
        });
      }
    }
    return UiPageScaffold(
      title: const Text('Notes Trash'),
      actions: [
        TextButton(
          onPressed: () => context.go('/notes'),
          child: const Text('Notes Library'),
        ),
      ],
      child: state.trashLoading && state.trashNotes.isEmpty
          ? const Center(child: UiLoadingState())
          : state.trashError != null && state.trashNotes.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load Trash.'),
                  TextButton(
                    onPressed: () =>
                        ref.read(workspaceNotesProvider.notifier).loadTrash(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : state.trashNotes.isEmpty
          ? const Center(child: Text('Trash is empty.'))
          : ListView.builder(
              itemCount: state.trashNotes.length,
              itemBuilder: (context, index) {
                final note = state.trashNotes[index];
                return ListTile(
                  key: ValueKey('trashed-note-${note.id}'),
                  title: Text(note.title),
                  subtitle: Text(
                    'Deleted ${formatWorkspaceTimestamp(note.deletedAt ?? note.updatedAt)}',
                  ),
                  trailing: TextButton(
                    key: ValueKey('restore-note-${note.id}'),
                    onPressed: () async {
                      final accountId = state.accountId;
                      if (accountId == null || note.ownerUserId != accountId) {
                        return;
                      }
                      final restored = await ref
                          .read(workspaceNotesProvider.notifier)
                          .restoreNote(note);
                      if (!mounted ||
                          !restored ||
                          ref.read(workspaceNotesProvider).accountId !=
                              accountId) {
                        return;
                      }
                      if (!context.mounted) return;
                      context.go('/notes');
                    },
                    child: const Text('Restore'),
                  ),
                );
              },
            ),
    );
  }
}
