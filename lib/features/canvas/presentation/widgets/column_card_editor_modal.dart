import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import '../../../../domain/models/node.dart';
import '../../../../domain/models/node_payload.dart';

class ColumnCardEditorModal extends StatefulWidget {
  final CanvasNode node;
  final ValueChanged<CanvasNode> onUpdate;

  const ColumnCardEditorModal({
    super.key,
    required this.node,
    required this.onUpdate,
  });

  static Future<void> show(
    BuildContext context, {
    required CanvasNode node,
    required ValueChanged<CanvasNode> onUpdate,
  }) {
    return showUiDialog<void>(
      context: context,
      builder: (context) =>
          ColumnCardEditorModal(node: node, onUpdate: onUpdate),
    );
  }

  @override
  State<ColumnCardEditorModal> createState() => _ColumnCardEditorModalState();
}

class _ColumnCardEditorModalState extends State<ColumnCardEditorModal> {
  late TextEditingController _titleController;
  late TextEditingController _newCardTitleController;
  late List<ColumnCardItem> _cards;
  late ColumnPayload _payload;
  int _wipLimit = 0;
  String _filter = 'all'; // 'all', 'active', 'done'
  late TextEditingController _wipLimitController;
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _headerColorScrollController = ScrollController();

  static const List<(String, Color)> _palette = [
    ('Blue', Color(0xFF3B82F6)),
    ('Orange', Color(0xFFF97316)),
    ('Green', Color(0xFF10B981)),
    ('Red', Color(0xFFEF4444)),
    ('Purple', Color(0xFF8B5CF6)),
    ('Pink', Color(0xFFEC4899)),
    ('Cyan', Color(0xFF06B6D4)),
    ('Gray', Color(0xFF6B7280)),
  ];

  Widget _buildPaletteSwatch({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final tokens = context.appTokens;
    return Semantics(
      label: label,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: AppControlSize.minimumHitTarget,
          height: AppControlSize.minimumHitTarget,
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: tokens.handle, width: AppBorder.focus)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoCardAccentSwatch({
    required bool selected,
    required VoidCallback onTap,
  }) {
    final tokens = context.appTokens;
    return Semantics(
      label: 'Card accent color: None',
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: AppControlSize.minimumHitTarget,
          height: AppControlSize.minimumHitTarget,
          child: Icon(
            Icons.block,
            color: selected ? tokens.accent : tokens.textMuted,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderColorSwatch((String, Color) entry) {
    final (name, color) = entry;
    return _buildPaletteSwatch(
      label: 'Column header color: $name',
      color: color,
      selected: _payload.headerColor.toARGB32() == color.toARGB32(),
      onTap: () {
        setState(() {
          _payload = _payload.copyWith(headerColor: color);
        });
        _syncChanges();
      },
    );
  }

  Widget _buildCardAccentField(
    AppTokens tokens,
    Color? selectedColor,
    ValueChanged<Color?> onSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CARD ACCENT COLOR',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          children: [
            _buildNoCardAccentSwatch(
              selected: selectedColor == null,
              onTap: () => onSelected(null),
            ),
            ..._palette.map((entry) {
              final (name, color) = entry;
              return _buildPaletteSwatch(
                label: 'Card accent color: $name',
                color: color,
                selected: selectedColor?.toARGB32() == color.toARGB32(),
                onTap: () => onSelected(color),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildPriorityField(
    AppTokens tokens,
    ColumnCardPriority priority,
    ValueChanged<ColumnCardPriority> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRIORITY',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        UiSelect<ColumnCardPriority>(
          items: const {
            '⚪ None': ColumnCardPriority.none,
            '🔵 Low': ColumnCardPriority.low,
            '🟡 Medium': ColumnCardPriority.medium,
            '🔴 High': ColumnCardPriority.high,
          },
          value: priority,
          label: 'PRIORITY',
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ],
    );
  }

  Widget _buildDueDateField(
    AppTokens tokens,
    BuildContext context,
    String? dueDate,
    ValueChanged<String> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DUE DATE',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        UiButton(
          onPressed: () async {
            final initial = dueDate == null
                ? DateTime.now()
                : DateTime.tryParse(dueDate) ?? DateTime.now();
            final picked = await showUiDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              onChanged(
                '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
              );
            }
          },
          variant: UiButtonVariant.outline,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(dueDate ?? 'Pick due date...'),
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _payload = widget.node.payload is ColumnPayload
        ? widget.node.payload as ColumnPayload
        : ColumnPayload();
    _titleController = TextEditingController(text: _payload.headerTitle);
    _newCardTitleController = TextEditingController();
    _cards = List<ColumnCardItem>.from(_payload.cards);
    _wipLimit = _payload.wipLimit;
    _wipLimitController = TextEditingController(text: _wipLimit.toString());
    _filter = _payload.filterMode;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _newCardTitleController.dispose();
    _wipLimitController.dispose();
    _inputFocus.dispose();
    _headerColorScrollController.dispose();
    super.dispose();
  }

  void _syncChanges() {
    final updatedPayload = _payload.copyWith(
      headerTitle: _titleController.text.trim().isEmpty
          ? 'Column'
          : _titleController.text.trim(),
      cards: _cards,
      wipLimit: _wipLimit,
      filterMode: _filter,
    );
    widget.onUpdate(widget.node.copyWith(payload: updatedPayload));
  }

  void _addNewCard([String? titleOverride]) {
    final title = titleOverride ?? _newCardTitleController.text.trim();
    if (title.isEmpty) return;

    final newId = const Uuid().v4();
    setState(() {
      _cards.add(
        ColumnCardItem(
          id: newId,
          title: title,
          isDone: false,
          priority: ColumnCardPriority.none,
        ),
      );
      if (titleOverride == null) {
        _newCardTitleController.clear();
      }
    });
    _syncChanges();
    _inputFocus.requestFocus();
  }

  void _toggleDone(int index) {
    setState(() {
      _cards[index] = _cards[index].copyWith(isDone: !_cards[index].isDone);
    });
    _syncChanges();
  }

  void _deleteCard(int index) {
    setState(() {
      _cards.removeAt(index);
    });
    _syncChanges();
  }

  void _showCardDetailDialog(int index) {
    final card = _cards[index];
    final titleCtrl = TextEditingController(text: card.title);
    final descCtrl = TextEditingController(text: card.description);
    final tagCtrl = TextEditingController();
    final assigneeCtrl = TextEditingController(text: card.assignee ?? '');
    ColumnCardPriority priority = card.priority;
    List<String> tags = List<String>.from(card.tags);
    String? dueDate = card.dueDate;
    Color? cardColor = card.cardColor;

    showUiDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = dialogContext.appTokens;
        void addTag(StateSetter setDialogState) {
          final trimmed = tagCtrl.text.trim();
          if (trimmed.isNotEmpty && !tags.contains(trimmed)) {
            setDialogState(() {
              tags.add(trimmed);
              tagCtrl.clear();
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setDialogState) => UiDialog(
            constraints: AppResponsive.dialogConstraints(
              context,
              maxWidth: 560,
              maxHeight: 640,
            ),
            builder: (context, style) => Padding(
              padding: AppResponsive.dialogPadding(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.dashboard_customize_outlined,
                        size: 20,
                        color: tokens.accent,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text('Card Properties', style: style.titleTextStyle),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Flexible(
                    child: SingleChildScrollView(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 480;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              UiTextField(
                                controller: titleCtrl,
                                label: 'Card Title *',
                              ),
                              const SizedBox(height: AppSpacing.md),
                              UiTextField(
                                controller: descCtrl,
                                label: 'Description / Notes',
                                minLines: 3,
                                maxLines: 3,
                              ),
                              const SizedBox(
                                height: AppSpacing.lg - AppSpacing.xxs,
                              ),
                              if (compact) ...[
                                _buildPriorityField(
                                  tokens,
                                  priority,
                                  (value) =>
                                      setDialogState(() => priority = value),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                UiTextField(
                                  controller: assigneeCtrl,
                                  label: 'ASSIGNEE',
                                  hint: '@username',
                                ),
                              ] else
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildPriorityField(
                                        tokens,
                                        priority,
                                        (value) => setDialogState(
                                          () => priority = value,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: UiTextField(
                                        controller: assigneeCtrl,
                                        label: 'ASSIGNEE',
                                        hint: '@username',
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(
                                height: AppSpacing.lg - AppSpacing.xxs,
                              ),
                              if (compact) ...[
                                _buildDueDateField(
                                  tokens,
                                  context,
                                  dueDate,
                                  (value) =>
                                      setDialogState(() => dueDate = value),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _buildCardAccentField(
                                  tokens,
                                  cardColor,
                                  (value) =>
                                      setDialogState(() => cardColor = value),
                                ),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _buildDueDateField(
                                        tokens,
                                        context,
                                        dueDate,
                                        (value) => setDialogState(
                                          () => dueDate = value,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: _buildCardAccentField(
                                        tokens,
                                        cardColor,
                                        (value) => setDialogState(
                                          () => cardColor = value,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(
                                height: AppSpacing.lg - AppSpacing.xxs,
                              ),
                              Text(
                                'TAGS & LABELS',
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(
                                height: AppSpacing.xs + AppSpacing.xxs,
                              ),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SizedBox(
                                    width: compact
                                        ? constraints.maxWidth
                                        : math.max(
                                            180.0,
                                            constraints.maxWidth - 120,
                                          ),
                                    child: UiTextField(
                                      controller: tagCtrl,
                                      hint: 'Add tag (e.g. Design, Bug, UI)...',
                                      onSubmitted: (_) =>
                                          addTag(setDialogState),
                                    ),
                                  ),
                                  UiButton(
                                    onPressed: () => addTag(setDialogState),
                                    variant: UiButtonVariant.outline,
                                    prefix: const Icon(Icons.add, size: 14),
                                    child: const Text('Add Tag'),
                                  ),
                                ],
                              ),
                              if (tags.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Wrap(
                                  spacing: AppSpacing.xs + AppSpacing.xxs,
                                  runSpacing: AppSpacing.xs,
                                  children: tags
                                      .map(
                                        (tag) => UiBadge(
                                          tag,
                                          variant: UiBadgeVariant.secondary,
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      UiButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        variant: UiButtonVariant.ghost,
                        child: const Text('Cancel'),
                      ),
                      UiButton(
                        onPressed: () {
                          final newTitle = titleCtrl.text.trim();
                          if (newTitle.isEmpty) return;
                          setState(() {
                            _cards[index] = _cards[index].copyWith(
                              title: newTitle,
                              description: descCtrl.text.trim(),
                              priority: priority,
                              assignee: assigneeCtrl.text.trim().isEmpty
                                  ? null
                                  : assigneeCtrl.text.trim(),
                              dueDate: dueDate,
                              cardColor: cardColor,
                              tags: tags,
                            );
                          });
                          _syncChanges();
                          Navigator.of(dialogContext).pop();
                        },
                        variant: UiButtonVariant.primary,
                        child: const Text('Save Card'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBatchImportDialog() {
    showUiDialog<void>(
      context: context,
      builder: (context) => _BatchAddCardsDialog(
        onAdd: (lines) {
          for (final line in lines) {
            _addNewCard(line);
          }
          if (lines.isNotEmpty) _syncChanges();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final shortCompactViewport =
        AppResponsive.isCompact(context) &&
        MediaQuery.sizeOf(context).height < 560;
    final filteredIndices = <int>[];
    for (int i = 0; i < _cards.length; i++) {
      if (_filter == 'active' && _cards[i].isDone) continue;
      if (_filter == 'done' && !_cards[i].isDone) continue;
      filteredIndices.add(i);
    }

    final totalCards = _cards.length;
    final doneCards = _cards.where((c) => c.isDone).length;
    final isWipExceeded = _wipLimit > 0 && totalCards > _wipLimit;

    return UiDialog(
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 720,
        maxHeight: 660,
      ),
      builder: (context, style) {
        final dialogWidth = AppResponsive.dialogWidth(context, preferred: 720);
        final dialogHeight = AppResponsive.dialogHeight(
          context,
          preferred: 660,
        );
        return SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header: Title, Color, WIP, Close
                Row(
                  children: [
                    Icon(
                      Icons.view_column_rounded,
                      color: _payload.headerColor,
                      size: 22,
                    ),
                    SizedBox(
                      width: shortCompactViewport
                          ? AppSpacing.xs + AppSpacing.xxs
                          : AppSpacing.md,
                    ),
                    Expanded(
                      child: UiTextField(
                        controller: _titleController,
                        hint: 'Column / Stage Title...',
                        onChanged: (_) => _syncChanges(),
                      ),
                    ),
                    UiIconButton(
                      icon: Icons.close,
                      tooltip: 'Close Modal',
                      size: UiButtonSize.sm,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                SizedBox(
                  height: shortCompactViewport ? AppSpacing.xs : AppSpacing.sm,
                ),
                if (AppResponsive.isCompact(context))
                  SizedBox(
                    height: AppControlSize.minimumHitTarget,
                    child: Scrollbar(
                      controller: _headerColorScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _headerColorScrollController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final entry in _palette) ...[
                              if (entry != _palette.first)
                                const SizedBox(width: AppSpacing.xxs),
                              _buildHeaderColorSwatch(entry),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: AppSpacing.xxs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      for (final entry in _palette)
                        _buildHeaderColorSwatch(entry),
                    ],
                  ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const SizedBox(
                  height: AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
                ),

                // WIP Limit & Progress Row
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: shortCompactViewport
                        ? AppSpacing.xs
                        : AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.panelElevated,
                    borderRadius: BorderRadius.circular(tokens.controlRadius),
                    border: Border.all(
                      color: isWipExceeded ? tokens.danger : tokens.panelBorder,
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final summary = Row(
                        children: [
                          Icon(
                            isWipExceeded
                                ? Icons.warning_amber_rounded
                                : Icons.checklist_rtl_rounded,
                            size: 16,
                            color: isWipExceeded
                                ? tokens.danger
                                : tokens.success,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Cards: $totalCards${_wipLimit > 0 ? ' / WIP Limit $_wipLimit' : ''} • Completed: $doneCards',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall!
                                  .copyWith(
                                    color: isWipExceeded
                                        ? tokens.danger
                                        : tokens.text,
                                    fontWeight: isWipExceeded
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                            ),
                          ),
                        ],
                      );
                      final limit = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'WIP Limit: ',
                            style: Theme.of(context).textTheme.labelSmall!
                                .copyWith(color: tokens.textMuted),
                          ),
                          SizedBox(
                            width: 60,
                            child: UiTextField(
                              controller: _wipLimitController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (val) {
                                final parsed = int.tryParse(val) ?? 0;
                                setState(
                                  () => _wipLimit = parsed.clamp(0, 999),
                                );
                                _syncChanges();
                              },
                            ),
                          ),
                        ],
                      );
                      if (shortCompactViewport) {
                        return Row(
                          children: [
                            Expanded(child: summary),
                            const SizedBox(
                              width: AppSpacing.xs + AppSpacing.xxs,
                            ),
                            limit,
                          ],
                        );
                      }
                      if (constraints.maxWidth < 520) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            summary,
                            const SizedBox(
                              height: AppSpacing.xs + AppSpacing.xxs,
                            ),
                            limit,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: summary),
                          const SizedBox(width: AppSpacing.sm),
                          limit,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Filter Tabs & Batch Add Action
                Wrap(
                  spacing: AppSpacing.xs + AppSpacing.xxs,
                  runSpacing: AppSpacing.xs + AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildFilterButton('all', 'All ($totalCards)'),
                    _buildFilterButton(
                      'active',
                      'Active (${totalCards - doneCards})',
                    ),
                    _buildFilterButton('done', 'Done ($doneCards)'),
                    UiButton(
                      onPressed: _showBatchImportDialog,
                      variant: UiButtonVariant.outline,
                      size: UiButtonSize.sm,
                      prefix: const Icon(Icons.playlist_add, size: 14),
                      child: const Text('Batch Add'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Add new card input bar
                UiSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  color: tokens.panelElevated,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final input = UiTextField(
                        controller: _newCardTitleController,
                        onSubmitted: (_) => _addNewCard(),
                        hint: 'Type card title and press Enter...',
                      );
                      final addButton = UiButton(
                        onPressed: _addNewCard,
                        variant: UiButtonVariant.primary,
                        size: UiButtonSize.sm,
                        child: const Text('Add Card'),
                      );
                      if (constraints.maxWidth < 420 && !shortCompactViewport) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.add_task_rounded,
                                  color: tokens.textMuted,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: input),
                              ],
                            ),
                            const SizedBox(
                              height: AppSpacing.xs + AppSpacing.xxs,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: addButton,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Icon(
                            Icons.add_task_rounded,
                            color: tokens.textMuted,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: input),
                          const SizedBox(width: AppSpacing.sm),
                          addButton,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Reorderable Card List
                Expanded(
                  child: filteredIndices.isEmpty
                      ? Center(
                          child: shortCompactViewport
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.inbox_outlined,
                                      size: AppControlSize.compact,
                                      color: tokens.textMuted.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Flexible(
                                      child: Text(
                                        'No cards found for current filter',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: tokens.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.inbox_outlined,
                                      size: 42,
                                      color: tokens.textMuted.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      'No cards found for current filter',
                                      style: TextStyle(
                                        color: tokens.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                        )
                      : ReorderableListView.builder(
                          itemCount: filteredIndices.length,
                          onReorderItem: (oldIndex, newIndex) {
                            setState(() {
                              final actualOld = filteredIndices[oldIndex];
                              final actualNew = filteredIndices[newIndex];
                              final moved = _cards.removeAt(actualOld);
                              _cards.insert(actualNew, moved);
                            });
                            _syncChanges();
                          },
                          itemBuilder: (context, index) {
                            final actualIndex = filteredIndices[index];
                            final card = _cards[actualIndex];

                            Color priorityColor = tokens.textMuted;
                            String priorityLabel = '';
                            switch (card.priority) {
                              case ColumnCardPriority.high:
                                priorityColor = const Color(0xFFEF4444);
                                priorityLabel = 'HIGH';
                                break;
                              case ColumnCardPriority.medium:
                                priorityColor = const Color(0xFFF59E0B);
                                priorityLabel = 'MED';
                                break;
                              case ColumnCardPriority.low:
                                priorityColor = const Color(0xFF3B82F6);
                                priorityLabel = 'LOW';
                                break;
                              case ColumnCardPriority.none:
                                break;
                            }

                            return Container(
                              key: ValueKey(card.id),
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              padding: const EdgeInsets.all(
                                AppSpacing.sm + AppSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    card.cardColor?.withValues(alpha: 0.15) ??
                                    tokens.panelElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.controlRadius,
                                ),
                                border: Border.all(
                                  color: card.cardColor ?? tokens.panelBorder,
                                  width: card.cardColor != null
                                      ? 1.4
                                      : AppBorder.thin,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.drag_indicator,
                                    color: tokens.textMuted,
                                    size: 18,
                                  ),
                                  const SizedBox(
                                    width: AppSpacing.xs + AppSpacing.xxs,
                                  ),
                                  // Checkbox
                                  UiCheckbox(
                                    value: card.isDone,
                                    semanticsLabel:
                                        'Mark ${card.title} as done',
                                    onChange: (_) => _toggleDone(actualIndex),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  // Card Content & Badges
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () =>
                                          _showCardDetailDialog(actualIndex),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              if (card.priority !=
                                                  ColumnCardPriority.none)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1.5,
                                                      ),
                                                  margin: const EdgeInsets.only(
                                                    right: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: priorityColor
                                                        .withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                    border: Border.all(
                                                      color: priorityColor,
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    priorityLabel,
                                                    style: TextStyle(
                                                      color: priorityColor,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  card.title,
                                                  style: TextStyle(
                                                    color: card.isDone
                                                        ? tokens.textMuted
                                                        : tokens.text,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    decoration: card.isDone
                                                        ? TextDecoration
                                                              .lineThrough
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (card.description.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              card.description,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: tokens.textMuted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                          if (card.tags.isNotEmpty ||
                                              card.dueDate != null ||
                                              card.assignee != null) ...[
                                            const SizedBox(
                                              height:
                                                  AppSpacing.xs +
                                                  AppSpacing.xxs,
                                            ),
                                            Wrap(
                                              spacing: AppSpacing.sm,
                                              runSpacing: AppSpacing.xs,
                                              children: [
                                                if (card.dueDate != null)
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons.schedule,
                                                        size: 11,
                                                        color: Color(
                                                          0xFFF59E0B,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        card.dueDate!,
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFFF59E0B,
                                                          ),
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                if (card.assignee != null)
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons.person_outline,
                                                        size: 11,
                                                        color: Color(
                                                          0xFF60A5FA,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 3),
                                                      ConstrainedBox(
                                                        constraints:
                                                            const BoxConstraints(
                                                              maxWidth: 140,
                                                            ),
                                                        child: Text(
                                                          card.assignee!,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                color: Color(
                                                                  0xFF60A5FA,
                                                                ),
                                                                fontSize: 10,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ...card.tags.map(
                                                  (t) => ConstrainedBox(
                                                    constraints:
                                                        const BoxConstraints(
                                                          maxWidth: 120,
                                                        ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                            vertical: 1,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFF282B34,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              3,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        t,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFFD1D5DB,
                                                          ),
                                                          fontSize: 9,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Edit & Delete
                                  UiIconButton(
                                    icon: Icons.edit_outlined,
                                    tooltip: 'Edit Card Detail',
                                    onPressed: () =>
                                        _showCardDetailDialog(actualIndex),
                                  ),
                                  UiIconButton(
                                    icon: Icons.delete_outline,
                                    tooltip: 'Delete Card',
                                    variant: UiButtonVariant.destructive,
                                    onPressed: () => _deleteCard(actualIndex),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterButton(String key, String label) {
    final isSelected = _filter == key;
    return UiButton(
      onPressed: () {
        setState(() => _filter = key);
        _syncChanges();
      },
      variant: isSelected ? UiButtonVariant.primary : UiButtonVariant.outline,
      size: UiButtonSize.sm,
      child: Text(label),
    );
  }
}

class _BatchAddCardsDialog extends StatefulWidget {
  const _BatchAddCardsDialog({required this.onAdd});

  final ValueChanged<List<String>> onAdd;

  @override
  State<_BatchAddCardsDialog> createState() => _BatchAddCardsDialogState();
}

class _BatchAddCardsDialogState extends State<_BatchAddCardsDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return UiDialog(
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 520,
        maxHeight: 560,
      ),
      builder: (context, style) => SizedBox(
        width: AppResponsive.dialogWidth(context, preferred: 520),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: AppResponsive.dialogHeight(context, preferred: 560),
          ),
          child: Padding(
            padding: AppResponsive.dialogPadding(context),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Batch Add Cards', style: style.titleTextStyle),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Paste multiple lines. Each line creates a new card in this column.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  UiTextField(
                    controller: _controller,
                    hint:
                        'Design Homepage Mockup\nIntegrate Auth APIs\nSetup Cloudflare Worker\nQA Regression Test',
                    minLines: AppResponsive.isCompact(context) ? 3 : 6,
                    maxLines: 8,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      UiButton(
                        onPressed: () => Navigator.of(context).pop(),
                        variant: UiButtonVariant.ghost,
                        child: const Text('Cancel'),
                      ),
                      UiButton(
                        onPressed: () {
                          widget.onAdd(
                            _controller.text
                                .split('\n')
                                .map((line) => line.trim())
                                .where((line) => line.isNotEmpty)
                                .toList(),
                          );
                          Navigator.of(context).pop();
                        },
                        variant: UiButtonVariant.primary,
                        child: const Text('Add All Cards'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
