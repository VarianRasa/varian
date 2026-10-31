import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/workspace_note_template.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

class NotesTemplatesScreen extends ConsumerStatefulWidget {
  const NotesTemplatesScreen({this.projectId, super.key});

  final String? projectId;

  @override
  ConsumerState<NotesTemplatesScreen> createState() =>
      _NotesTemplatesScreenState();
}

class _NotesTemplatesScreenState extends ConsumerState<NotesTemplatesScreen> {
  String? _projectId;
  String? _accountId;
  List<WorkspaceNoteTemplate> _templates = const [];
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    _accountId = ref.read(workspaceNotesProvider).accountId;
    _load();
  }

  Future<void> _load() async {
    final accountId = ref.read(workspaceNotesProvider).accountId;
    if (accountId == null) return;
    final projectId = _projectId;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _accountId = accountId;
    });
    try {
      final templates = await ref
          .read(workspaceNoteRepositoryProvider)
          .listTemplates(projectId: projectId, expectedAccountId: accountId);
      if (!_isCurrent(generation, accountId, projectId)) return;
      setState(() {
        _templates = templates;
        _loading = false;
      });
    } catch (error) {
      if (!_isCurrent(generation, accountId, projectId)) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  bool _isCurrent(int generation, String accountId, String? projectId) =>
      mounted &&
      generation == _generation &&
      _projectId == projectId &&
      ref.read(workspaceNotesProvider).accountId == accountId;

  Future<void> _saveTemplate({WorkspaceNoteTemplate? template}) async {
    final accountId = ref.read(workspaceNotesProvider).accountId;
    if (accountId == null || accountId != _accountId) return;
    final projectId = _projectId;
    final result = await showDialog<({String title, String markdown})>(
      context: context,
      builder: (_) => _TemplateFormDialog(template: template),
    );
    if (result == null || !_isCurrent(_generation, accountId, projectId)) {
      return;
    }
    try {
      final repository = ref.read(workspaceNoteRepositoryProvider);
      final saved = template == null
          ? await repository.createTemplate(
              title: result.title,
              markdownContent: result.markdown,
              projectId: projectId,
              expectedAccountId: accountId,
            )
          : await repository.updateTemplate(
              template,
              title: result.title,
              markdownContent: result.markdown,
              expectedAccountId: accountId,
            );
      if (!_isCurrent(_generation, accountId, projectId)) return;
      setState(() {
        _templates = [
          saved,
          ..._templates.where((item) => item.id != saved.id),
        ];
      });
    } catch (error) {
      if (!_isCurrent(_generation, accountId, projectId)) return;
      _showError();
    }
  }

  Future<void> _deleteTemplate(WorkspaceNoteTemplate template) async {
    final accountId = ref.read(workspaceNotesProvider).accountId;
    if (accountId == null || accountId != _accountId) return;
    final projectId = _projectId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('“${template.title}” will be removed from this scope.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_isCurrent(_generation, accountId, projectId)) {
      return;
    }
    try {
      await ref
          .read(workspaceNoteRepositoryProvider)
          .deleteTemplate(template: template, expectedAccountId: accountId);
      if (!_isCurrent(_generation, accountId, projectId)) return;
      setState(() {
        _templates = _templates
            .where((item) => item.id != template.id)
            .toList(growable: false);
      });
    } catch (error) {
      if (!_isCurrent(_generation, accountId, projectId)) return;
      _showError();
    }
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Template action failed. Check access and retry.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountId = ref.watch(workspaceNotesProvider).accountId;
    if (accountId != _accountId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _generation++;
        _templates = const [];
        _loading = true;
        _error = null;
        _accountId = accountId;
        if (accountId != null) _load();
        setState(() {});
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes templates'),
        leading: IconButton(
          tooltip: 'Back to Notes',
          onPressed: () => context.go('/notes'),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: 'Create template',
            onPressed: _loading || accountId == null
                ? null
                : () => _saveTemplate(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DropdownButtonFormField<String>(
              key: ValueKey('template-scope-${widget.projectId}'),
              initialValue: _projectId == null ? 'private' : 'project',
              decoration: const InputDecoration(labelText: 'Template scope'),
              items: [
                const DropdownMenuItem(
                  value: 'private',
                  child: Text('Private'),
                ),
                if (widget.projectId != null)
                  DropdownMenuItem(
                    value: 'project',
                    child: Text('Shared project (${widget.projectId})'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _projectId = value == 'project' ? widget.projectId : null;
                });
                _load();
              },
            ),
          ),
          Expanded(
            child: accountId == null
                ? const Center(child: Text('Sign in to manage templates.'))
                : _buildTemplateList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Templates could not be loaded.'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_templates.isEmpty) {
      return const Center(
        child: Text('No templates in this scope. Create one to get started.'),
      );
    }
    return ListView.builder(
      itemCount: _templates.length,
      itemBuilder: (context, index) {
        final template = _templates[index];
        return ListTile(
          key: ValueKey('note-template-${template.id}'),
          title: Text(template.title),
          subtitle: Text(template.markdownContent.split('\n').first),
          trailing: Wrap(
            children: [
              IconButton(
                tooltip: 'Edit ${template.title}',
                onPressed: () => _saveTemplate(template: template),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete ${template.title}',
                onPressed: () => _deleteTemplate(template),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TemplateFormDialog extends StatefulWidget {
  const _TemplateFormDialog({this.template});

  final WorkspaceNoteTemplate? template;

  @override
  State<_TemplateFormDialog> createState() => _TemplateFormDialogState();
}

class _TemplateFormDialogState extends State<_TemplateFormDialog> {
  late final TextEditingController _title;
  String? _titleError;
  late final TextEditingController _markdown;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.template?.title ?? '');
    _markdown = TextEditingController(
      text: widget.template?.markdownContent ?? '',
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _markdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.template == null ? 'Create template' : 'Edit template'),
    content: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * 0.65,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              onChanged: (_) => setState(() => _titleError = null),
              decoration: InputDecoration(
                labelText: 'Title',
                errorText: _titleError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _markdown,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Markdown',
                helperText: 'Tokens: {{date}}, {{title}}, {{aliases}}',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_title.text.trim().isEmpty) {
            setState(() => _titleError = 'Enter a template title.');
            return;
          }
          Navigator.pop(context, (
            title: _title.text,
            markdown: _markdown.text,
          ));
        },
        child: const Text('Save'),
      ),
    ],
  );
}
