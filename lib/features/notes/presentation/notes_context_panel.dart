import 'package:flutter/material.dart';
import 'package:varian/features/notes/domain/note_markdown_metadata.dart';
import 'package:varian/features/notes/domain/workspace_notes_index.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';

class NotesContextPanel extends StatelessWidget {
  const NotesContextPanel({
    required this.note,
    required this.index,
    this.onOpen,
    super.key,
  });
  final WorkspaceNote note;
  final WorkspaceNotesIndex index;
  final ValueChanged<WorkspaceNote>? onOpen;

  String _propertyValue(Object? value) {
    if (value is Iterable && value is! String) {
      return value.map(_propertyValue).join(', ');
    }
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${_propertyValue(entry.value)}')
          .join(', ');
    }
    return value?.toString() ?? 'null';
  }

  @override
  Widget build(BuildContext context) {
    final metadata = parseNoteMarkdownMetadata(note.markdownContent);
    final links = index.backlinksFor(note.id);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Backlinks (${links.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ...links.map(
          (item) => ListTile(
            title: Text(item.title),
            onTap: () => onOpen?.call(item),
          ),
        ),
        const Divider(),
        Text('Tags', style: Theme.of(context).textTheme.titleMedium),
        Wrap(
          spacing: 6,
          children: metadata.tags.map((tag) => Chip(label: Text(tag))).toList(),
        ),
        const Divider(),
        Text('Properties', style: Theme.of(context).textTheme.titleMedium),
        if (metadata.parseError != null)
          const Text('Malformed YAML frontmatter'),
        if (metadata.yaml is Map)
          ...(metadata.yaml as Map).entries.map(
            (entry) => ListTile(
              dense: true,
              title: Text('${entry.key}'),
              subtitle: Text(_propertyValue(entry.value)),
            ),
          )
        else if (metadata.yaml != null)
          ListTile(
            dense: true,
            title: const Text('Frontmatter'),
            subtitle: Text(_propertyValue(metadata.yaml)),
          ),
        const Divider(),
        Text('Outline', style: Theme.of(context).textTheme.titleMedium),
        ...RegExp(r'^#{1,6}\s+(.+)$', multiLine: true)
            .allMatches(metadata.body)
            .map(
              (match) => ListTile(dense: true, title: Text(match.group(1)!)),
            ),
      ],
    );
  }
}
