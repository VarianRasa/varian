import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import '../../../../domain/models/node.dart';
import '../../../../domain/models/node_payload.dart';

class TodoListEditorModal extends StatefulWidget {
  final CanvasNode node;
  final ValueChanged<CanvasNode> onUpdate;

  const TodoListEditorModal({
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
      builder: (context) => TodoListEditorModal(node: node, onUpdate: onUpdate),
    );
  }

  @override
  State<TodoListEditorModal> createState() => _TodoListEditorModalState();
}

class _TodoListEditorModalState extends State<TodoListEditorModal> {
  late TextEditingController _titleController;
  late TextEditingController _newItemController;
  late List<TodoItem> _items;
  late TodoListPayload _payload;
  String _activeTab = 'all'; // 'all', 'active', 'completed'
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _payload = widget.node.payload is TodoListPayload
        ? widget.node.payload as TodoListPayload
        : TodoListPayload();
    _titleController = TextEditingController(text: _payload.title);
    _newItemController = TextEditingController();
    _items = List<TodoItem>.from(_payload.items);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _newItemController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _syncChanges() {
    final updatedPayload = _payload.copyWith(
      title: _titleController.text.trim().isEmpty
          ? 'To-do List'
          : _titleController.text.trim(),
      items: _items,
    );
    widget.onUpdate(widget.node.copyWith(payload: updatedPayload));
  }

  void _addNewTask([String? textOverride]) {
    final text = textOverride ?? _newItemController.text.trim();
    if (text.isEmpty) return;

    final newId = const Uuid().v4();
    setState(() {
      _items.add(TodoItem(id: newId, text: text, isDone: false));
      if (textOverride == null) {
        _newItemController.clear();
      }
    });
    _syncChanges();
    _inputFocus.requestFocus();
  }

  void _toggleDone(int index) {
    setState(() {
      _items[index] = _items[index].copyWith(isDone: !_items[index].isDone);
    });
    _syncChanges();
  }

  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
    _syncChanges();
  }

  void _showBatchImportDialog() {
    final batchController = TextEditingController();
    showUiDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = dialogContext.appTokens;
        return UiDialog(
          constraints: AppResponsive.dialogConstraints(
            dialogContext,
            maxWidth: 520,
            maxHeight: 560,
          ),
          builder: (context, style) => SingleChildScrollView(
            child: Padding(
              padding: AppResponsive.dialogPadding(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Batch Paste Tasks', style: style.titleTextStyle),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Paste multiple lines of tasks. Each non-empty line becomes a new task item.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  UiTextField(
                    controller: batchController,
                    hint: 'Task 1\nTask 2\nTask 3',
                    minLines: 8,
                    maxLines: 8,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      UiButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        variant: UiButtonVariant.ghost,
                        child: const Text('Cancel'),
                      ),
                      UiButton(
                        onPressed: () {
                          final lines = batchController.text
                              .split('\n')
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty);
                          if (lines.isNotEmpty) {
                            setState(() {
                              for (final line in lines) {
                                _items.add(
                                  TodoItem(
                                    id: const Uuid().v4(),
                                    text: line,
                                    isDone: false,
                                  ),
                                );
                              }
                            });
                            _syncChanges();
                          }
                          Navigator.pop(dialogContext);
                        },
                        variant: UiButtonVariant.primary,
                        child: const Text('Add All Tasks'),
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

  Future<void> _pickDueDate(int index) async {
    final current = _items[index].dueDate;
    DateTime initial = DateTime.now();
    if (current != null) {
      final parsed = DateTime.tryParse(current);
      if (parsed != null) initial = parsed;
    }

    final picked = await showUiDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked != null) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        _items[index] = _items[index].copyWith(dueDate: formatted);
      });
      _syncChanges();
    }
  }

  void _markAll(bool done) {
    setState(() {
      _items = _items.map((e) => e.copyWith(isDone: done)).toList();
    });
    _syncChanges();
  }

  void _clearCompleted() {
    setState(() {
      _items.removeWhere((e) => e.isDone);
    });
    _syncChanges();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final compactHeight = MediaQuery.sizeOf(context).height < 560;
    final titleField = UiTextField(
      controller: _titleController,
      hint: 'Checklist Title...',
      onChanged: (_) => _syncChanges(),
    );
    final importButton = UiIconButton(
      icon: Icons.post_add_rounded,
      tooltip: 'Batch Paste Tasks',
      size: UiButtonSize.sm,
      onPressed: _showBatchImportDialog,
    );
    final closeButton = UiIconButton(
      icon: Icons.close,
      tooltip: 'Close',
      size: UiButtonSize.sm,
      onPressed: () => Navigator.pop(context),
    );
    final completedCount = _items.where((i) => i.isDone).length;
    final totalCount = _items.length;
    final progress = totalCount > 0 ? (completedCount / totalCount) : 0.0;

    return UiDialog(
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 580,
        maxHeight: 640,
      ),
      builder: (context, style) => SizedBox(
        width: AppResponsive.dialogWidth(context, preferred: 580),
        height: AppResponsive.dialogHeight(context, preferred: 640),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Bar
              LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Icon(
                      Icons.checklist_rounded,
                      color: tokens.success,
                      size: 20,
                    ),
                    SizedBox(
                      width: constraints.maxWidth < 380
                          ? AppSpacing.xs
                          : AppSpacing.sm,
                    ),
                    Expanded(child: titleField),
                    importButton,
                    closeButton,
                  ],
                ),
              ),

              SizedBox(height: compactHeight ? AppSpacing.sm : AppSpacing.md),

              // Progress Bar & Percentage Summary
              Container(
                key: const ValueKey('todo-editor-progress-frame'),
                padding: EdgeInsets.symmetric(
                  horizontal: compactHeight
                      ? AppSpacing.sm
                      : AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
                  vertical: compactHeight
                      ? AppSpacing.xs
                      : AppSpacing.sm + AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: tokens.panelElevated,
                  borderRadius: BorderRadius.circular(tokens.controlRadius),
                  border: Border.all(
                    color: tokens.panelBorder,
                    width: AppBorder.thin,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth < 340
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Progress: $completedCount of $totalCount completed',
                                  style: Theme.of(context).textTheme.bodySmall!
                                      .copyWith(
                                        color: tokens.text,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '${(progress * 100).toInt()}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall!
                                        .copyWith(
                                          color: tokens.success,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Progress: $completedCount of $totalCount completed',
                                  style: Theme.of(context).textTheme.bodySmall!
                                      .copyWith(
                                        color: tokens.text,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                Text(
                                  '${(progress * 100).toInt()}%',
                                  style: Theme.of(context).textTheme.bodySmall!
                                      .copyWith(
                                        color: tokens.success,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                    ),
                    SizedBox(
                      height: compactHeight ? AppSpacing.xs : AppSpacing.sm,
                    ),
                    UiLinearProgressIndicator(
                      value: progress,
                      semanticsLabel: 'Todo completion progress',
                    ),
                  ],
                ),
              ),

              SizedBox(
                height: compactHeight
                    ? AppSpacing.sm
                    : AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
              ),

              // Filter Tabs & Quick Actions
              Wrap(
                spacing: AppSpacing.xs + AppSpacing.xxs,
                runSpacing: AppSpacing.xs + AppSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildFilterChip('All ($totalCount)', 'all'),
                  _buildFilterChip(
                    'Active (${totalCount - completedCount})',
                    'active',
                  ),
                  _buildFilterChip('Done ($completedCount)', 'completed'),
                  UiIconButton(
                    icon: Icons.more_horiz,
                    tooltip: 'Task actions',
                    size: UiButtonSize.sm,
                    onPressed: () {
                      showUiDialog<void>(
                        context: context,
                        builder: (dialogContext) {
                          return UiDialog(
                            builder: (context, style) => Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Task actions',
                                  style: style.titleTextStyle,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                UiButton(
                                  onPressed: () {
                                    _markAll(true);
                                    Navigator.pop(dialogContext);
                                  },
                                  variant: UiButtonVariant.outline,
                                  child: const Text('Mark All Done'),
                                ),
                                const SizedBox(
                                  height: AppSpacing.xs + AppSpacing.xxs,
                                ),
                                UiButton(
                                  onPressed: () {
                                    _markAll(false);
                                    Navigator.pop(dialogContext);
                                  },
                                  variant: UiButtonVariant.outline,
                                  child: const Text('Uncheck All'),
                                ),
                                const SizedBox(
                                  height: AppSpacing.xs + AppSpacing.xxs,
                                ),
                                UiButton(
                                  onPressed: () {
                                    _clearCompleted();
                                    Navigator.pop(dialogContext);
                                  },
                                  variant: UiButtonVariant.destructive,
                                  child: const Text('Clear Completed'),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),

              SizedBox(
                height: compactHeight
                    ? AppSpacing.xs
                    : AppSpacing.sm + AppSpacing.xxs,
              ),

              // Add Task Input Box
              Container(
                key: const ValueKey('todo-editor-add-item-frame'),
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: compactHeight ? 0 : AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: tokens.panelElevated,
                  borderRadius: BorderRadius.circular(tokens.controlRadius),
                  border: Border.all(
                    color: tokens.panelBorder,
                    width: AppBorder.thin,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: tokens.success,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                    Expanded(
                      child: UiTextField(
                        controller: _newItemController,
                        hint: 'Add a new task and press Enter...',
                        onSubmitted: (_) => _addNewTask(),
                      ),
                    ),
                    UiIconButton(
                      icon: Icons.arrow_forward_rounded,
                      tooltip: 'Add task',
                      size: UiButtonSize.sm,
                      onPressed: _addNewTask,
                    ),
                  ],
                ),
              ),

              SizedBox(height: compactHeight ? AppSpacing.xs : AppSpacing.md),

              // Task List (Reorderable)
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.task_alt_rounded,
                              size: 36,
                              color: tokens.textMuted,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'No tasks yet. Add one above!',
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Material(
                        color: Colors.transparent,
                        child: Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(canvasColor: Colors.transparent),
                          child: ReorderableListView.builder(
                            itemCount: _items.length,
                            onReorderItem: (oldIndex, newIndex) {
                              setState(() {
                                final item = _items.removeAt(oldIndex);
                                _items.insert(newIndex, item);
                              });
                              _syncChanges();
                            },
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              if (_activeTab == 'active' && item.isDone) {
                                return Container(key: ValueKey(item.id));
                              }
                              if (_activeTab == 'completed' && !item.isDone) {
                                return Container(key: ValueKey(item.id));
                              }

                              return _buildTaskRow(item, index);
                            },
                          ),
                        ),
                      ),
              ),

              SizedBox(height: compactHeight ? AppSpacing.xs : AppSpacing.md),

              // Footer Actions
              LayoutBuilder(
                builder: (context, constraints) {
                  final reorderHint = Text(
                    '💡 Drag items to reorder',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                  );
                  final doneButton = UiButton(
                    onPressed: () => Navigator.pop(context),
                    variant: UiButtonVariant.primary,
                    prefix: const Icon(Icons.check, size: 16),
                    child: const Text('Done'),
                  );
                  return constraints.maxWidth < 380
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            reorderHint,
                            Align(
                              alignment: Alignment.centerRight,
                              child: doneButton,
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [reorderHint, doneButton],
                        );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String tabKey) {
    final isSelected = _activeTab == tabKey;
    return UiButton(
      onPressed: () => setState(() => _activeTab = tabKey),
      variant: isSelected ? UiButtonVariant.primary : UiButtonVariant.outline,
      size: UiButtonSize.sm,
      child: Text(label),
    );
  }

  Widget _buildTaskRow(TodoItem item, int index) {
    final tokens = context.appTokens;
    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.panelElevated,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Drag Handle
          Icon(Icons.drag_indicator, size: 16, color: tokens.textMuted),
          const SizedBox(width: 6),

          // Checkbox
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleDone(index),
            child: Semantics(
              button: true,
              checked: item.isDone,
              label: 'Mark ${item.text} as ${item.isDone ? 'active' : 'done'}',
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: item.isDone ? tokens.success : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: item.isDone ? tokens.success : tokens.textMuted,
                    width: 1.5,
                  ),
                ),
                child: item.isDone
                    ? Icon(Icons.check, size: 14, color: tokens.handle)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Text / Inline Edit and responsive task actions
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.text,
                  style: TextStyle(
                    color: item.isDone ? tokens.textMuted : tokens.text,
                    fontSize: 13,
                    decoration: item.isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (item.dueDate != null ||
                    item.assignee != null ||
                    item.priority != TodoPriority.none)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.priority != TodoPriority.none)
                          _buildPriorityBadge(item.priority),
                        if (item.dueDate != null)
                          _buildMetadataTag(
                            '📅 ${item.dueDate}',
                            key: ValueKey(
                              'todo-editor-metadata-${item.id}-due',
                            ),
                          ),
                        if (item.assignee != null)
                          _buildMetadataTag(
                            '👤 ${item.assignee}',
                            key: ValueKey(
                              'todo-editor-metadata-${item.id}-assignee',
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Due Date Picker Button
                    UiButton(
                      prefix: const Icon(
                        Icons.calendar_today_rounded,
                        size: 13,
                      ),
                      variant: UiButtonVariant.outline,
                      size: UiButtonSize.sm,
                      onPressed: () => _pickDueDate(index),
                      child: Text(
                        item.dueDate?.isNotEmpty == true
                            ? item.dueDate!
                            : 'Set Date',
                      ),
                    ),
                    // Priority selector
                    SizedBox(
                      width: 160,
                      child: UiSelect<TodoPriority>(
                        label: 'Priority',
                        value: item.priority,
                        items: {
                          for (final priority in TodoPriority.values)
                            priority.label: priority,
                        },
                        onChanged: (priority) {
                          if (priority == null) return;
                          setState(() {
                            _items[index] = item.copyWith(priority: priority);
                          });
                          _syncChanges();
                        },
                      ),
                    ),
                    // Delete Button
                    UiIconButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete task',
                      variant: UiButtonVariant.destructive,
                      size: UiButtonSize.sm,
                      onPressed: () => _deleteItem(index),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getPriorityColor(TodoPriority p) {
    final tokens = context.appTokens;
    switch (p) {
      case TodoPriority.high:
        return tokens.danger;
      case TodoPriority.medium:
        return tokens.warning;
      case TodoPriority.low:
        return tokens.info;
      case TodoPriority.none:
        return tokens.textMuted;
    }
  }

  Widget _buildPriorityBadge(TodoPriority p) {
    final color = _getPriorityColor(p);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        p.label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMetadataTag(String text, {required Key key}) {
    final tokens = context.appTokens;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: tokens.panelElevated,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
      ),
      child: Text(text, style: TextStyle(color: tokens.textMuted, fontSize: 9)),
    );
  }
}
