import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/prototype_interaction.dart';

class PrototypeInteractionEditorResult {
  final List<PrototypeInteraction> interactions;
  final String? stateId;

  const PrototypeInteractionEditorResult({
    required this.interactions,
    required this.stateId,
  });
}

class PrototypeInteractionEditorDialog extends StatefulWidget {
  final String sourceNodeId;
  final String sourceNodeLabel;
  final List<PrototypeInteraction> initialInteractions;
  final String? initialStateId;
  final List<CanvasNode> nodes;

  const PrototypeInteractionEditorDialog({
    required this.sourceNodeId,
    required this.sourceNodeLabel,
    required this.initialInteractions,
    required this.initialStateId,
    required this.nodes,
    super.key,
  });

  static Future<PrototypeInteractionEditorResult?> show(
    BuildContext context, {
    required String sourceNodeId,
    required String sourceNodeLabel,
    required List<PrototypeInteraction> initialInteractions,
    required String? initialStateId,
    required List<CanvasNode> nodes,
  }) => showUiDialog<PrototypeInteractionEditorResult>(
    context: context,
    builder: (_) => PrototypeInteractionEditorDialog(
      sourceNodeId: sourceNodeId,
      sourceNodeLabel: sourceNodeLabel,
      initialInteractions: initialInteractions,
      initialStateId: initialStateId,
      nodes: nodes,
    ),
  );

  @override
  State<PrototypeInteractionEditorDialog> createState() =>
      _PrototypeInteractionEditorDialogState();
}

class _PrototypeInteractionEditorDialogState
    extends State<PrototypeInteractionEditorDialog> {
  late List<PrototypeInteraction> _interactions;
  late final TextEditingController _stateController;
  int _selectedIndex = 0;
  String? _error;

  List<CanvasNode> get _frames => widget.nodes
      .where(
        (node) => node.type == NodeType.frame && node.id != widget.sourceNodeId,
      )
      .toList(growable: false);

  List<CanvasNode> get _overlayNodes => widget.nodes
      .where((node) => node.id != widget.sourceNodeId && node.visible)
      .toList(growable: false);

  PrototypeInteraction? get _selected =>
      _interactions.isEmpty ? null : _interactions[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _interactions = [
      for (final interaction in widget.initialInteractions)
        interaction.normalized(),
    ];
    _stateController = TextEditingController(text: widget.initialStateId ?? '');
    if (_interactions.isEmpty) {
      _interactions = [_newInteraction()];
    }
  }

  @override
  void dispose() {
    _stateController.dispose();
    super.dispose();
  }

  PrototypeInteraction _newInteraction() => PrototypeInteraction(
    id: 'interaction-${DateTime.now().microsecondsSinceEpoch}',
  );

  void _select(int index) {
    setState(() {
      _selectedIndex = index;
      _error = null;
    });
  }

  void _replaceSelected(PrototypeInteraction interaction) {
    if (_interactions.isEmpty) return;
    setState(() {
      _interactions[_selectedIndex] = interaction;
      _error = null;
    });
  }

  void _addInteraction() {
    setState(() {
      _interactions = [..._interactions, _newInteraction()];
      _selectedIndex = _interactions.length - 1;
      _error = null;
    });
  }

  void _removeSelected() {
    if (_interactions.isEmpty) return;
    setState(() {
      _interactions = [..._interactions]..removeAt(_selectedIndex);
      if (_interactions.isEmpty) {
        _interactions = [_newInteraction()];
        _selectedIndex = 0;
      } else {
        _selectedIndex = _selectedIndex
            .clamp(0, _interactions.length - 1)
            .toInt();
      }
      _error = null;
    });
  }

  void _save() {
    final normalized = [
      for (final interaction in _interactions) interaction.normalized(),
    ];
    final invalid = normalized
        .where((interaction) => !interaction.isValid)
        .firstOrNull;
    if (invalid != null) {
      setState(() {
        _error =
            'Lengkapi target untuk action ${_actionLabel(invalid.action)}.';
      });
      return;
    }
    Navigator.of(context).pop(
      PrototypeInteractionEditorResult(
        interactions: normalized,
        stateId: _clean(_stateController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = AppResponsive.isNarrow(context);
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 860);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 700);
    return UiDialog(
      semanticsLabel: 'Prototype interaction editor',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    color: context.appTokens.accent,
                  ),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      'Prototype: ${widget.sourceNodeLabel}',
                      style: style.titleTextStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close prototype editor',
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
                            UiTextField(
                              controller: _stateController,
                              label: 'Initial state ID',
                              hint: 'default',
                              prefix: const Icon(Icons.toggle_on_outlined),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            SizedBox(
                              height: 210,
                              child: _buildInteractionList(context),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _buildInteractionForm(theme),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          UiTextField(
                            controller: _stateController,
                            label: 'Initial state ID',
                            hint: 'default',
                            prefix: const Icon(Icons.toggle_on_outlined),
                          ),
                          const SizedBox(
                            height: AppSpacing.md + AppSpacing.xxs,
                          ),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: 235,
                                  child: _buildInteractionList(context),
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(child: _buildInteractionForm(theme)),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    onPressed: _save,
                    prefix: const Icon(Icons.save_outlined, size: 16),
                    child: const Text('Save prototype'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInteractionList(BuildContext context) {
    final tokens = context.appTokens;
    return UiSurface(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(tokens.controlRadius),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm + AppSpacing.xxs,
              AppSpacing.sm,
              AppSpacing.sm - AppSpacing.xxs,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Interactions',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                UiIconButton(
                  icon: Icons.add,
                  tooltip: 'Add interaction',
                  onPressed: _addInteraction,
                ),
              ],
            ),
          ),
          Divider(height: AppBorder.thin, color: tokens.panelBorder),
          Expanded(
            child: ListView.builder(
              itemCount: _interactions.length,
              itemBuilder: (context, index) {
                final interaction = _interactions[index];
                final selected = index == _selectedIndex;
                return Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: tokens.accentSoft,
                    selectedColor: tokens.text,
                    onTap: () => _select(index),
                    title: Text(
                      interaction.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_triggerLabel(interaction.trigger)} · ${_actionLabel(interaction.action)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.textMuted),
                    ),
                    trailing: interaction.enabled
                        ? null
                        : Icon(
                            Icons.pause_circle_outline,
                            size: 16,
                            color: tokens.textMuted,
                          ),
                  ),
                );
              },
            ),
          ),
          Divider(height: AppBorder.thin, color: tokens.panelBorder),
          UiButton(
            variant: UiButtonVariant.ghost,
            onPressed: _removeSelected,
            prefix: const Icon(Icons.delete_outline, size: 16),
            child: const Text('Remove selected'),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionForm(ThemeData theme) {
    final interaction = _selected;
    if (interaction == null) {
      return const Center(child: Text('Add an interaction to begin.'));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiTextField(
            key: ValueKey('id-${interaction.id}'),
            initialValue: interaction.id,
            label: 'Interaction ID',
            onChanged: (value) =>
                _replaceSelected(interaction.copyWith(id: value)),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
          UiSelect<PrototypeTrigger>(
            label: 'Trigger',
            value: interaction.trigger,
            items: {
              for (final value in PrototypeTrigger.values)
                _triggerLabel(value): value,
            },
            onChanged: (value) {
              if (value != null) {
                _replaceSelected(interaction.copyWith(trigger: value));
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
          UiSelect<PrototypeAction>(
            label: 'Action',
            value: interaction.action,
            items: {
              for (final value in PrototypeAction.values)
                _actionLabel(value): value,
            },
            onChanged: (value) {
              if (value != null) {
                _replaceSelected(
                  interaction.copyWith(
                    action: value,
                    targetFrameId: null,
                    targetNodeId: null,
                    stateId: null,
                    url: null,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
          _buildActionTarget(interaction),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
          UiSelect<PrototypeTransition>(
            label: 'Transition',
            value: interaction.transition,
            items: {
              for (final value in PrototypeTransition.values)
                _transitionLabel(value): value,
            },
            onChanged: (value) {
              if (value != null) {
                _replaceSelected(interaction.copyWith(transition: value));
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
          UiTextField(
            key: ValueKey('duration-${interaction.id}'),
            initialValue: '${interaction.durationMs}',
            keyboardType: TextInputType.number,
            label: 'Duration (ms)',
            hint: 'Milliseconds',
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null) {
                _replaceSelected(interaction.copyWith(durationMs: parsed));
              }
            },
          ),
          UiSwitch(
            label: const Text('Preserve scroll position'),
            semanticsLabel: 'Preserve scroll position',
            value: interaction.preserveScroll,
            onChange: (value) =>
                _replaceSelected(interaction.copyWith(preserveScroll: value)),
          ),
          UiSwitch(
            label: const Text('Enabled'),
            semanticsLabel: 'Interaction enabled',
            value: interaction.enabled,
            onChange: (value) =>
                _replaceSelected(interaction.copyWith(enabled: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTarget(PrototypeInteraction interaction) {
    switch (interaction.action) {
      case PrototypeAction.navigate:
        return _buildNodeDropdown(
          label: 'Target frame',
          value: interaction.targetFrameId,
          nodes: _frames,
          onChanged: (value) =>
              _replaceSelected(interaction.copyWith(targetFrameId: value)),
        );
      case PrototypeAction.overlay:
        return _buildNodeDropdown(
          label: 'Overlay node',
          value: interaction.targetNodeId,
          nodes: _overlayNodes,
          onChanged: (value) =>
              _replaceSelected(interaction.copyWith(targetNodeId: value)),
        );
      case PrototypeAction.setState:
        return UiTextField(
          key: ValueKey('state-${interaction.id}'),
          initialValue: interaction.stateId ?? '',
          label: 'Target state ID',
          hint: 'pressed',
          onChanged: (value) =>
              _replaceSelected(interaction.copyWith(stateId: value)),
        );
      case PrototypeAction.openUrl:
        return UiTextField(
          key: ValueKey('url-${interaction.id}'),
          initialValue: interaction.url ?? '',
          keyboardType: TextInputType.url,
          label: 'Deep link / URL',
          hint: 'https://example.com or myapp://screen',
          onChanged: (value) =>
              _replaceSelected(interaction.copyWith(url: value)),
        );
      case PrototypeAction.back:
        return const UiTextField(
          initialValue: 'Returns to the previous presentation frame.',
          label: 'Target',
          enabled: false,
          readOnly: true,
        );
    }
  }

  Widget _buildNodeDropdown({
    required String label,
    required String? value,
    required List<CanvasNode> nodes,
    required ValueChanged<String?> onChanged,
  }) {
    final availableIds = nodes.map((node) => node.id).toSet();
    final items = <String, String>{};
    for (final node in nodes) {
      final nodeLabel = _nodeLabel(node);
      final itemLabel = items.containsKey(nodeLabel)
          ? '$nodeLabel (${node.id})'
          : nodeLabel;
      items[itemLabel] = node.id;
    }
    return UiSelect<String>(
      label: label,
      hint: 'Select a node',
      value: availableIds.contains(value) ? value : null,
      items: items,
      onChanged: onChanged,
    );
  }

  String _nodeLabel(CanvasNode node) {
    if (node.name?.trim().isNotEmpty == true) return node.name!.trim();
    if (node.payload is FramePayload) {
      final name = (node.payload as FramePayload).name.trim();
      if (name.isNotEmpty) return name;
    }
    return node.id;
  }

  String? _clean(String value) {
    final result = value.trim();
    return result.isEmpty ? null : result;
  }

  String _triggerLabel(PrototypeTrigger value) => switch (value) {
    PrototypeTrigger.tap => 'Tap',
    PrototypeTrigger.hover => 'Hover',
    PrototypeTrigger.press => 'Press',
    PrototypeTrigger.drag => 'Drag',
  };

  String _actionLabel(PrototypeAction value) => switch (value) {
    PrototypeAction.navigate => 'Navigate',
    PrototypeAction.overlay => 'Open overlay',
    PrototypeAction.setState => 'Set state',
    PrototypeAction.openUrl => 'Open URL / deep link',
    PrototypeAction.back => 'Back',
  };

  String _transitionLabel(PrototypeTransition value) => switch (value) {
    PrototypeTransition.instant => 'Instant',
    PrototypeTransition.dissolve => 'Dissolve',
    PrototypeTransition.smartAnimate => 'Smart animate',
    PrototypeTransition.slideLeft => 'Slide left',
    PrototypeTransition.slideRight => 'Slide right',
    PrototypeTransition.slideUp => 'Slide up',
    PrototypeTransition.slideDown => 'Slide down',
    PrototypeTransition.push => 'Push',
  };
}
