import 'package:flutter/material.dart';
import 'package:varian/features/notes/domain/note_markdown_metadata.dart';
import 'package:varian/features/notes/domain/note_markdown_properties.dart';

class NotesPropertiesPanel extends StatefulWidget {
  const NotesPropertiesPanel({
    required this.markdown,
    required this.onMarkdownChanged,
    super.key,
  });

  final String markdown;
  final ValueChanged<String> onMarkdownChanged;

  @override
  State<NotesPropertiesPanel> createState() => _NotesPropertiesPanelState();
}

class _NotesPropertiesPanelState extends State<NotesPropertiesPanel> {
  late String _markdown = widget.markdown;
  String? _message;

  @override
  void didUpdateWidget(covariant NotesPropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) _markdown = widget.markdown;
  }

  @override
  Widget build(BuildContext context) {
    final metadata = parseNoteMarkdownMetadata(_markdown);
    final properties = metadata.yaml is Map ? metadata.yaml as Map : const {};
    final malformed = metadata.parseError != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Properties',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!malformed)
              IconButton(
                key: const ValueKey('notes-property-add'),
                tooltip: 'Add property',
                onPressed: _addProperty,
                icon: const Icon(Icons.add),
              ),
          ],
        ),
        if (malformed)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Malformed YAML frontmatter. Fix it in Markdown source before editing Properties.',
              key: ValueKey('notes-properties-malformed'),
            ),
          )
        else if (properties.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No Properties yet.'),
          )
        else
          Expanded(
            child: ListView(
              children: [
                for (final entry in properties.entries)
                  ListTile(
                    key: ValueKey('notes-property-${entry.key}'),
                    dense: true,
                    title: Text('${entry.key}'),
                    subtitle: Text(_displayValue(entry.value)),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          key: ValueKey('notes-property-edit-${entry.key}'),
                          tooltip: 'Edit ${entry.key}',
                          onPressed: () => _editProperty(
                            key: '${entry.key}',
                            value: entry.value,
                          ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          key: ValueKey('notes-property-remove-${entry.key}'),
                          tooltip: 'Remove ${entry.key}',
                          onPressed: () => _removeProperty('${entry.key}'),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Future<void> _addProperty() => _editProperty();

  Future<void> _editProperty({String? key, Object? value}) async {
    final metadata = parseNoteMarkdownMetadata(_markdown);
    if (metadata.parseError != null) return;
    final properties = metadata.yaml is Map ? metadata.yaml as Map : const {};
    final draft = await showDialog<_PropertyDraft>(
      context: context,
      builder: (context) => _PropertyEditorDialog(
        keyName: key,
        value: value,
        existingKeys: properties.keys.map((item) => '$item').toSet(),
      ),
    );
    if (draft == null || !mounted) return;
    try {
      final updated = setNoteMarkdownProperty(
        _markdown,
        key: draft.key,
        type: draft.type,
        value: draft.value,
      );
      setState(() {
        _markdown = updated;
        _message = null;
      });
      widget.onMarkdownChanged(updated);
    } on Object catch (error) {
      setState(() => _message = _errorMessage(error));
    }
  }

  void _removeProperty(String key) {
    try {
      final updated = removeNoteMarkdownProperty(_markdown, key: key);
      setState(() {
        _markdown = updated;
        _message = null;
      });
      widget.onMarkdownChanged(updated);
    } on Object catch (error) {
      setState(() => _message = _errorMessage(error));
    }
  }

  String _errorMessage(Object error) => error is FormatException
      ? error.message
      : error is ArgumentError
      ? error.message?.toString() ?? 'Property could not be saved.'
      : 'Property could not be saved.';
}

class _PropertyDraft {
  const _PropertyDraft({
    required this.key,
    required this.type,
    required this.value,
  });

  final String key;
  final NotePropertyType type;
  final Object value;
}

class _PropertyEditorDialog extends StatefulWidget {
  const _PropertyEditorDialog({
    required this.keyName,
    required this.value,
    required this.existingKeys,
  });

  final String? keyName;
  final Object? value;
  final Set<String> existingKeys;

  @override
  State<_PropertyEditorDialog> createState() => _PropertyEditorDialogState();
}

class _PropertyEditorDialogState extends State<_PropertyEditorDialog> {
  late final _keyController = TextEditingController(text: widget.keyName ?? '');
  late final _valueController = TextEditingController(
    text: _initialValue(widget.value),
  );
  late NotePropertyType _type = _propertyType(widget.keyName, widget.value);
  late bool _checkboxValue = widget.value == true;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.keyName == null ? 'Add property' : 'Edit property'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('note-property-key-input'),
            controller: _keyController,
            enabled: widget.keyName == null,
            autofocus: widget.keyName == null,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<NotePropertyType>(
            key: const ValueKey('note-property-type-input'),
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final type in NotePropertyType.values)
                DropdownMenuItem(value: type, child: Text(_typeLabel(type))),
            ],
            onChanged: (type) {
              if (type != null) setState(() => _type = type);
            },
          ),
          if (_type == NotePropertyType.checkbox)
            SwitchListTile(
              key: const ValueKey('note-property-checkbox-input'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Value'),
              value: _checkboxValue,
              onChanged: (value) => setState(() => _checkboxValue = value),
            )
          else
            TextField(
              key: const ValueKey('note-property-value-input'),
              controller: _valueController,
              keyboardType: _type == NotePropertyType.number
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : TextInputType.multiline,
              minLines:
                  _type == NotePropertyType.list ||
                      _type == NotePropertyType.tags ||
                      _type == NotePropertyType.aliases
                  ? 3
                  : 1,
              maxLines:
                  _type == NotePropertyType.list ||
                      _type == NotePropertyType.tags ||
                      _type == NotePropertyType.aliases
                  ? 6
                  : 3,
              decoration: InputDecoration(
                labelText: _type == NotePropertyType.dateTime
                    ? 'ISO date-time'
                    : _type == NotePropertyType.list ||
                          _type == NotePropertyType.tags ||
                          _type == NotePropertyType.aliases
                    ? 'One value per line'
                    : 'Value',
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('note-property-save'),
        onPressed: _save,
        child: const Text('Save'),
      ),
    ],
  );

  void _save() {
    final key = _keyController.text;
    if (widget.keyName == null && widget.existingKeys.contains(key)) {
      setState(() => _error = 'A property with this name already exists.');
      return;
    }
    final Object? value;
    switch (_type) {
      case NotePropertyType.text:
        value = _valueController.text;
      case NotePropertyType.list:
      case NotePropertyType.tags:
      case NotePropertyType.aliases:
        value = _valueController.text
            .split('\n')
            .where((line) => line.isNotEmpty)
            .toList();
      case NotePropertyType.number:
        value = num.tryParse(_valueController.text.trim());
        if (value == null || (value is double && !value.isFinite)) {
          setState(() => _error = 'Enter a valid finite number.');
          return;
        }
      case NotePropertyType.checkbox:
        value = _checkboxValue;
      case NotePropertyType.dateTime:
        value = DateTime.tryParse(_valueController.text.trim());
        if (value == null) {
          setState(() => _error = 'Enter a valid ISO date-time.');
          return;
        }
    }
    try {
      _validatePropertyDraft(key, _type, value);
    } on Object catch (error) {
      setState(
        () => _error = error is ArgumentError
            ? error.message?.toString() ?? 'Check the property value.'
            : 'Check the property value.',
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(_PropertyDraft(key: key, type: _type, value: value));
  }

  void _validatePropertyDraft(String key, NotePropertyType type, Object value) {
    setNoteMarkdownProperty('---\n---\n', key: key, type: type, value: value);
  }
}

NotePropertyType _propertyType(String? key, Object? value) {
  if (key == 'tags') return NotePropertyType.tags;
  if (key == 'aliases') return NotePropertyType.aliases;
  if (value is DateTime) return NotePropertyType.dateTime;
  if (value is bool) return NotePropertyType.checkbox;
  if (value is num) return NotePropertyType.number;
  if (value is List && value.every((item) => item is String)) {
    return NotePropertyType.list;
  }
  return NotePropertyType.text;
}

String _initialValue(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is List && value.every((item) => item is String)) {
    return value.join('\n');
  }
  return value?.toString() ?? '';
}

String _displayValue(Object? value) {
  if (value is Iterable && value is! String) {
    return value.map(_displayValue).join(', ');
  }
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}: ${_displayValue(entry.value)}')
        .join(', ');
  }
  return value?.toString() ?? 'null';
}

String _typeLabel(NotePropertyType type) => switch (type) {
  NotePropertyType.text => 'Text',
  NotePropertyType.list => 'List',
  NotePropertyType.number => 'Number',
  NotePropertyType.checkbox => 'Checkbox',
  NotePropertyType.dateTime => 'Date-time',
  NotePropertyType.tags => 'Tags',
  NotePropertyType.aliases => 'Aliases',
};
