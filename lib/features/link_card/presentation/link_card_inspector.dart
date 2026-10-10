import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../domain/link_url_policy.dart';

class LinkCardInspector extends StatefulWidget {
  final CanvasNode node;
  final ValueChanged<String> onSubmitUrl;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onDescriptionChanged;
  final VoidCallback onRefresh;
  final VoidCallback onOpenInApp;
  final VoidCallback onOpenExternal;

  const LinkCardInspector({
    super.key,
    required this.node,
    required this.onSubmitUrl,
    required this.onTitleChanged,
    required this.onDescriptionChanged,
    required this.onRefresh,
    required this.onOpenInApp,
    required this.onOpenExternal,
  });

  @override
  State<LinkCardInspector> createState() => _LinkCardInspectorState();
}

class _LinkCardInspectorState extends State<LinkCardInspector> {
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late final TextEditingController _descriptionController;
  bool _syncingControllers = false;
  String? _error;

  LinkPayload get _payload => widget.node.payload as LinkPayload;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: _payload.title);
    _urlController = TextEditingController(text: _payload.url);
    _descriptionController = TextEditingController(
      text: _payload.description ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant LinkCardInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncingControllers = true;
    try {
      if (_urlController.text != _payload.url &&
          !_urlController.selection.isValid) {
        _urlController.text = _payload.url;
      }
      if (_titleController.text != _payload.title) {
        _titleController.text = _payload.title;
      }
      final description = _payload.description ?? '';
      if (_descriptionController.text != description) {
        _descriptionController.text = description;
      }
    } finally {
      _syncingControllers = false;
    }
  }

  void _onTitleChanged(String value) {
    if (!_syncingControllers) widget.onTitleChanged(value);
  }

  void _onDescriptionChanged(String value) {
    if (!_syncingControllers) widget.onDescriptionChanged(value);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submitUrl() {
    try {
      final normalized = normalizeLinkUrl(_urlController.text).toString();
      setState(() => _error = null);
      widget.onSubmitUrl(normalized);
    } on LinkUrlValidationException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final hostname = Uri.tryParse(_payload.url)?.host ?? '';
    final statusError = _payload.previewStatus == LinkPreviewStatus.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UiSectionHeader(title: 'LINK CARD'),
        const SizedBox(height: AppSpacing.sm),
        UiTextField(
          controller: _titleController,
          label: 'Title',
          hint: 'Link title',
          onChanged: _onTitleChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        UiTextField(
          key: const Key('link-inspector-url'),
          controller: _urlController,
          label: 'Target URL',
          hint: 'https://example.com',
          onSubmitted: (_) => _submitUrl(),
          description: _error,
        ),
        const SizedBox(height: AppSpacing.sm),
        UiTextField(
          controller: _descriptionController,
          label: 'Description',
          hint: 'Optional description',
          minLines: 2,
          maxLines: 3,
          onChanged: _onDescriptionChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        UiSurface(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hostname.isEmpty ? 'No URL' : hostname,
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                statusError
                    ? _payload.previewError ?? 'Preview error'
                    : _payload.previewStatus.name,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: statusError ? tokens.danger : tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xs + AppSpacing.xxs,
          runSpacing: AppSpacing.xs + AppSpacing.xxs,
          children: [
            UiButton(
              onPressed: _payload.url.isEmpty ? null : widget.onRefresh,
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.refresh),
              child: const Text('Refresh'),
            ),
            UiButton(
              onPressed: _payload.url.isEmpty ? null : widget.onOpenInApp,
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.visibility),
              child: const Text('Open'),
            ),
            UiIconButton(
              icon: Icons.open_in_new,
              tooltip: 'Open in browser',
              onPressed: _payload.url.isEmpty ? null : widget.onOpenExternal,
            ),
          ],
        ),
      ],
    );
  }
}
