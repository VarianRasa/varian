import 'package:flutter/material.dart';
import 'package:varian/features/notes/domain/workspace_note_version.dart';

class NotesHistoryPanel extends StatefulWidget {
  const NotesHistoryPanel({
    required this.versions,
    required this.loading,
    required this.onRestore,
    super.key,
  });

  final List<WorkspaceNoteVersion> versions;
  final bool loading;
  final Future<bool> Function(WorkspaceNoteVersion version) onRestore;

  @override
  State<NotesHistoryPanel> createState() => _NotesHistoryPanelState();
}

class _NotesHistoryPanelState extends State<NotesHistoryPanel> {
  String? _restoringVersionId;

  Future<void> _confirmRestore(WorkspaceNoteVersion version) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this version?'),
        content: const Text(
          'The current title and Markdown will be replaced. This creates a new history version; existing versions are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore version'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _restoringVersionId = version.id);
    await widget.onRestore(version);
    if (mounted) setState(() => _restoringVersionId = null);
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 224,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text(
            'History is retained indefinitely. Storage use can grow over time.',
          ),
        ),
        Expanded(
          child: widget.loading
              ? const Center(child: CircularProgressIndicator())
              : widget.versions.isEmpty
              ? const Center(child: Text('No history available.'))
              : ListView.builder(
                  itemCount: widget.versions.length,
                  itemBuilder: (context, index) {
                    final version = widget.versions[index];
                    final restoring = _restoringVersionId == version.id;
                    return ListTile(
                      dense: true,
                      title: Text(
                        'Revision ${version.revision}: ${version.title}',
                      ),
                      subtitle: Text(version.createdAt.toLocal().toString()),
                      trailing: TextButton(
                        onPressed: _restoringVersionId != null
                            ? null
                            : () => _confirmRestore(version),
                        child: restoring
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Restore'),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
