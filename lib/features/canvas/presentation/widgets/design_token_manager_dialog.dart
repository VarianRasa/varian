import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/responsive.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../../../domain/models/design_tokens.dart';
import '../../state/design_token_provider.dart';

class DesignTokenManagerDialog extends ConsumerStatefulWidget {
  final bool readOnly;

  const DesignTokenManagerDialog({this.readOnly = false, super.key});

  @override
  ConsumerState<DesignTokenManagerDialog> createState() =>
      _DesignTokenManagerDialogState();
}

class _DesignTokenManagerDialogState
    extends ConsumerState<DesignTokenManagerDialog> {
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _valueController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _modesController = TextEditingController(text: 'base');
  final _modeValuesController = TextEditingController();
  DesignTokenType _type = DesignTokenType.string;
  String? _editingId;
  String _previewMode = 'base';
  String _query = '';

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _valueController.dispose();
    _descriptionController.dispose();
    _modesController.dispose();
    _modeValuesController.dispose();
    super.dispose();
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _idController.clear();
      _nameController.clear();
      _valueController.clear();
      _descriptionController.clear();
      _modesController.text = ref.read(designTokenSetProvider).modes.join(', ');
      _modeValuesController.clear();
      _type = DesignTokenType.string;
    });
  }

  void _edit(DesignToken token) {
    final set = ref.read(designTokenSetProvider);
    final modeValues = token.modeValues.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    setState(() {
      _editingId = token.id;
      _idController.text = token.id;
      _nameController.text = token.name;
      _valueController.text = token.value.toString();
      _descriptionController.text = token.description ?? '';
      _modesController.text = set.modes.join(', ');
      _modeValuesController.text = modeValues;
      _type = token.type;
    });
  }

  Object? _parseValue(String raw) {
    final value = raw.trim();
    switch (_type) {
      case DesignTokenType.number:
        return double.tryParse(value);
      case DesignTokenType.boolean:
        if (value.toLowerCase() == 'true') return true;
        if (value.toLowerCase() == 'false') return false;
        return null;
      case DesignTokenType.color:
      case DesignTokenType.string:
        return value.isEmpty ? null : value;
    }
  }

  Object? _parseModeValue(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    switch (_type) {
      case DesignTokenType.number:
        return double.tryParse(value);
      case DesignTokenType.boolean:
        if (value.toLowerCase() == 'true') return true;
        if (value.toLowerCase() == 'false') return false;
        return null;
      case DesignTokenType.color:
      case DesignTokenType.string:
        return value;
    }
  }

  void _save() {
    if (widget.readOnly) return;
    final id = _idController.text.trim();
    final name = _nameController.text.trim();
    final value = _parseValue(_valueController.text);
    if (id.isEmpty || name.isEmpty || value == null) return;

    final modes = _modesController.text
        .split(',')
        .map((mode) => mode.trim())
        .where((mode) => mode.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (modes.isEmpty) modes.add('base');
    final modeValues = <String, Object>{};
    for (final part in _modeValuesController.text.split(',')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final mode = part.substring(0, separator).trim();
      final parsed = _parseModeValue(part.substring(separator + 1));
      if (mode.isNotEmpty && parsed != null) modeValues[mode] = parsed;
    }
    final current = ref.read(designTokenSetProvider);
    final token = DesignToken(
      id: id,
      name: name,
      type: _type,
      value: value,
      modeValues: modeValues,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    ref
        .read(designTokenSetProvider.notifier)
        .setSet(
          DesignTokenSet(
            version: current.version + 1,
            modes: modes,
            entries: {...current.entries, token.id: token},
          ),
        );
    _previewMode = modes.contains(_previewMode) ? _previewMode : modes.first;
    _resetForm();
  }

  void _delete(DesignToken token) {
    if (widget.readOnly) return;
    final current = ref.read(designTokenSetProvider);
    ref
        .read(designTokenSetProvider.notifier)
        .setSet(
          DesignTokenSet(
            version: current.version + 1,
            modes: current.modes,
            entries: {...current.entries}..remove(token.id),
          ),
        );
    if (_editingId == token.id) _resetForm();
  }

  @override
  Widget build(BuildContext context) {
    final tokenSet = ref.watch(designTokenSetProvider);
    final normalizedQuery = _query.trim().toLowerCase();
    final tokens = tokenSet.entries.values.where((token) {
      if (normalizedQuery.isEmpty) return true;
      return '${token.id} ${token.name} ${token.description ?? ''}'
          .toLowerCase()
          .contains(normalizedQuery);
    }).toList()..sort((left, right) => left.id.compareTo(right.id));
    if (!tokenSet.modes.contains(_previewMode) && tokenSet.modes.isNotEmpty) {
      _previewMode = tokenSet.modes.first;
    }

    final compact = AppResponsive.isNarrow(context);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 640);
    final width = AppResponsive.dialogWidth(context, preferred: 860);
    return UiDialog(
      key: const ValueKey('design-token-manager-dialog'),
      semanticsLabel: 'Design tokens',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: width,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Design Tokens', style: style.titleTextStyle),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close design tokens',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: compact
                    ? SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 220,
                              child: _buildTokenList(tokens, tokenSet),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _buildTokenEditor(),
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 300,
                            child: _buildTokenList(tokens, tokenSet),
                          ),
                          const VerticalDivider(width: AppSpacing.xl),
                          Expanded(child: _buildTokenEditor()),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  variant: UiButtonVariant.ghost,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenList(List<DesignToken> tokens, DesignTokenSet tokenSet) {
    final appTokens = context.appTokens;
    final previewMode = tokenSet.modes.contains(_previewMode)
        ? _previewMode
        : tokenSet.modes.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiTextField(
          key: const ValueKey('token-search'),
          label: 'Search tokens',
          hint: 'ID, name, or description',
          prefix: const Icon(Icons.search),
          clearable: true,
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: AppSpacing.md - AppSpacing.xxs),
        UiSelect<String>(
          label: 'Preview mode',
          items: {for (final mode in tokenSet.modes) mode: mode},
          value: previewMode,
          enabled: tokenSet.modes.isNotEmpty,
          onChanged: (value) {
            if (value != null) setState(() => _previewMode = value);
          },
        ),
        const SizedBox(height: AppSpacing.md - AppSpacing.xxs),
        Expanded(
          child: tokens.isEmpty
              ? Center(
                  child: Text(
                    'No tokens yet',
                    style: TextStyle(color: appTokens.textMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: tokens.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final token = tokens[index];
                    final selected = token.id == _editingId;
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: 'Edit token ${token.name}',
                      child: UiSurface(
                        key: ValueKey('token-row-${token.id}'),
                        color: selected ? appTokens.accentSoft : null,
                        padding: const EdgeInsets.all(
                          AppSpacing.md - AppSpacing.xxs,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _edit(token),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      token.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xxs + 1),
                                    Text(
                                      '${token.id} / ${token.resolve(previewMode ?? 'base')}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall!
                                          .copyWith(color: appTokens.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (!widget.readOnly)
                              UiIconButton(
                                icon: Icons.delete_outline,
                                tooltip: 'Delete token ${token.name}',
                                onPressed: () => _delete(token),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTokenEditor() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _editingId == null ? 'Create token' : 'Edit token',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.md - AppSpacing.xxs),
        UiTextField(
          key: const ValueKey('token-id'),
          controller: _idController,
          enabled: !widget.readOnly,
          label: 'ID',
          hint: 'color.brand.primary',
        ),
        UiTextField(
          key: const ValueKey('token-name'),
          controller: _nameController,
          enabled: !widget.readOnly,
          label: 'Name',
        ),
        UiSelect<DesignTokenType>(
          label: 'Type',
          items: {for (final type in DesignTokenType.values) type.name: type},
          value: _type,
          enabled: !widget.readOnly,
          onChanged: (value) {
            if (value != null) setState(() => _type = value);
          },
        ),
        UiTextField(
          key: const ValueKey('token-value'),
          controller: _valueController,
          enabled: !widget.readOnly,
          label: 'Base value',
        ),
        UiTextField(
          key: const ValueKey('token-modes'),
          controller: _modesController,
          enabled: !widget.readOnly,
          label: 'Modes',
          hint: 'base, dark, compact',
        ),
        UiTextField(
          key: const ValueKey('token-mode-values'),
          controller: _modeValuesController,
          enabled: !widget.readOnly,
          label: 'Mode values',
          hint: 'dark=#ffffff, compact=#ff0000',
        ),
        UiTextField(
          key: const ValueKey('token-description'),
          controller: _descriptionController,
          enabled: !widget.readOnly,
          label: 'Description',
          minLines: 2,
          maxLines: 3,
        ),
        if (!widget.readOnly) ...[
          const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              UiButton(
                variant: UiButtonVariant.ghost,
                onPressed: _resetForm,
                child: const Text('Clear'),
              ),
              UiButton(
                key: const ValueKey('save-token'),
                onPressed: _save,
                prefix: const Icon(Icons.save_outlined, size: 16),
                child: Text(_editingId == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
