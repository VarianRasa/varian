import 'package:flutter/material.dart';

class NotesFolderDialog extends StatefulWidget {
  const NotesFolderDialog({super.key, this.initialName});

  final String? initialName;

  @override
  State<NotesFolderDialog> createState() => _NotesFolderDialogState();
}

class _NotesFolderDialogState extends State<NotesFolderDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initialName == null ? 'Create folder' : 'Rename folder'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'Folder name'),
      onSubmitted: (_) => _submit(context),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => _submit(context),
        child: const Text('Save'),
      ),
    ],
  );

  void _submit(BuildContext context) {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }
}
