import 'package:flutter/material.dart';
import 'package:varian/features/notes/data/notes_import_service.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';

class NotesImportDialog extends StatefulWidget {
  const NotesImportDialog({
    required this.preview,
    required this.projectId,
    required this.onImport,
    required this.onImported,
    super.key,
  });

  final NotesImportPreview preview;
  final String? projectId;
  final Future<List<WorkspaceNote>?> Function(List<PreparedNoteImport>, String?)
  onImport;
  final Future<void> Function(List<WorkspaceNote>) onImported;

  @override
  State<NotesImportDialog> createState() => _NotesImportDialogState();
}

class _NotesImportDialogState extends State<NotesImportDialog> {
  final _titles = <String, TextEditingController>{};
  final _skipped = <String>{};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _titles.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    List<PreparedNoteImport> resolved;
    try {
      resolved = widget.preview.resolveDuplicateTitles(
        renamedTitles: {
          for (final entry in _titles.entries)
            if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text,
        },
        skippedNoteIds: _skipped,
      );
    } on NotesImportException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    if (resolved.isEmpty) {
      setState(() => _error = 'Select at least one note to import.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final imported = await widget.onImport(resolved, widget.projectId);
      if (!mounted) return;
      if (imported == null) {
        setState(() {
          _saving = false;
          _error = 'Import failed. Review the workspace error and retry.';
        });
        return;
      }
      Navigator.of(context).pop();
      await widget.onImported(imported);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Import failed. Review the workspace error and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import notes'),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Destination: ${widget.projectId == null ? 'Private notes' : 'Selected project'}',
            ),
            const SizedBox(height: 8),
            for (final note in widget.preview.notes)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(note.sourcePath),
                      if (note.folderPath != null)
                        Text('Folder: ${note.folderPath}'),
                      if (note.duplicateTitle) ...[
                        Text(
                          'Title “${note.title}” already exists. Rename or skip.',
                        ),
                        if (_skipped.contains(note.newId))
                          const Text('Will skip this note.')
                        else
                          TextField(
                            key: ValueKey('import-rename-${note.newId}'),
                            controller: _titles.putIfAbsent(
                              note.newId,
                              TextEditingController.new,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'New title',
                            ),
                          ),
                        TextButton(
                          onPressed: () => setState(() {
                            if (!_skipped.add(note.newId)) {
                              _skipped.remove(note.newId);
                            }
                          }),
                          child: Text(
                            _skipped.contains(note.newId)
                                ? 'Choose rename instead'
                                : 'Skip',
                          ),
                        ),
                      ] else
                        Text(note.title),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: Text(_saving ? 'Importing…' : 'Import'),
        ),
      ],
    );
  }
}
