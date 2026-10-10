import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/component_payload.dart';
import '../../domain/canvas_selection.dart';
import '../../state/canvas_selection_provider.dart';
import '../../state/document_nodes_provider.dart';
import '../../state/selection_provider.dart';
import '../../state/viewport_provider.dart';

class _LayerRenameDialog extends StatefulWidget {
  final String title;
  final String fieldLabel;
  final String initialValue;
  final String? hint;
  final String? description;

  const _LayerRenameDialog({
    required this.title,
    required this.fieldLabel,
    required this.initialValue,
    this.hint,
    this.description,
    super.key,
  });

  @override
  State<_LayerRenameDialog> createState() => _LayerRenameDialogState();
}

class _LayerRenameDialogState extends State<_LayerRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiDialog(
    semanticsLabel: widget.title,
    constraints: AppResponsive.dialogConstraints(
      context,
      maxWidth: 460,
      maxHeight: 300,
    ),
    builder: (dialogContext, style) => Padding(
      padding: AppResponsive.dialogPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: style.titleTextStyle),
          const SizedBox(height: AppSpacing.md),
          UiTextField(
            key: widget.description == null
                ? const ValueKey('rename-layer-field')
                : const ValueKey('bulk-rename-pattern'),
            controller: _controller,
            autofocus: true,
            label: widget.fieldLabel,
            hint: widget.hint,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          if (widget.description != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(widget.description!, style: style.bodyTextStyle),
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
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_controller.text),
                child: Text(widget.description == null ? 'Save' : 'Apply'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class LayersPanel extends ConsumerStatefulWidget {
  final bool readOnly;
  final double width;
  final String projectId;

  const LayersPanel({
    super.key,
    this.readOnly = false,
    this.width = 250,
    this.projectId = 'default',
  });

  @override
  ConsumerState<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends ConsumerState<LayersPanel> {
  final Set<String> _collapsedIds = {};
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _clearFilter() {
    _filterController.clear();
    setState(() => _filterQuery = '');
  }

  Set<String> _visibleNodeIds(
    List<CanvasNode> nodes,
    Map<String, CanvasNode> byId,
  ) {
    final query = _filterQuery.trim().toLowerCase();
    if (query.isEmpty) return byId.keys.toSet();

    final childrenById = <String, List<CanvasNode>>{};
    for (final node in nodes) {
      final parentId = node.parentId;
      if (parentId != null && byId.containsKey(parentId)) {
        childrenById.putIfAbsent(parentId, () => []).add(node);
      }
    }

    final visible = <String>{};
    bool includeNode(CanvasNode node, Set<String> path) {
      if (!path.add(node.id)) return false;
      final matches = _nodeSearchText(node).contains(query);
      final descendantMatches = (childrenById[node.id] ?? const <CanvasNode>[])
          .any((child) => includeNode(child, path));
      path.remove(node.id);
      if (matches || descendantMatches) visible.add(node.id);
      return matches || descendantMatches;
    }

    for (final node in nodes) {
      includeNode(node, <String>{});
    }
    return visible;
  }

  void _selectNode(CanvasNode node) {
    ref.read(selectionProvider.notifier).select(node.id);
  }

  void _focusNode(CanvasNode node) {
    _selectNode(node);
    final viewportSize = MediaQuery.sizeOf(context);
    final canvasSize = Size(
      (viewportSize.width - 250).clamp(1.0, viewportSize.width),
      viewportSize.height,
    );
    ref
        .read(viewportProvider.notifier)
        .panToNodeCenter(node.bounds, canvasSize);
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(documentNodesProvider);
    final selectedIds = ref.watch(selectionProvider);
    final selectionPreferences = ref.watch(
      canvasSelectionPreferencesProvider(widget.projectId),
    );
    final tokens = context.appTokens;

    final displayNodes = nodes
        .where(
          (node) =>
              (selectionPreferences.showHidden ||
                  node.visible ||
                  selectedIds.contains(node.id)) &&
              (selectionPreferences.showLocked ||
                  !node.locked ||
                  selectedIds.contains(node.id)),
        )
        .toList(growable: false);
    final byId = {for (final n in displayNodes) n.id: n};
    final visibleNodeIds = _visibleNodeIds(displayNodes, byId);
    final childrenById = <String, List<CanvasNode>>{};
    for (final n in displayNodes) {
      if (!visibleNodeIds.contains(n.id)) continue;
      final p = n.parentId;
      if (p == null || !visibleNodeIds.contains(p)) continue;
      childrenById.putIfAbsent(p, () => []).add(n);
    }
    for (final list in childrenById.values) {
      list.sort((a, b) => b.zIndex.compareTo(a.zIndex));
    }

    final allRoots =
        displayNodes
            .where((n) => n.parentId == null || !byId.containsKey(n.parentId))
            .toList()
          ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    final roots = allRoots.where((n) => visibleNodeIds.contains(n.id)).toList();

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          right: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, color: tokens.accent, size: 16),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(child: UiSectionHeader(title: 'OBJECT TREE')),
                UiMenuButton<String>(
                  key: const Key('layers-selection-mode-menu'),
                  tooltip: 'Selection mode',
                  icon: Icons.select_all_outlined,
                  items: [
                    for (final mode in CanvasSelectionMode.values)
                      UiMenuAction<String>(
                        value: 'mode:${mode.name}',
                        icon: mode == CanvasSelectionMode.selectThrough
                            ? Icons.layers_outlined
                            : mode == CanvasSelectionMode.deep
                            ? Icons.account_tree_outlined
                            : Icons.touch_app_outlined,
                        label: '${_selectionModeLabel(mode)} selection',
                        selected: mode == selectionPreferences.mode,
                      ),
                    UiMenuAction<String>(
                      value: 'toggle_locked',
                      icon: Icons.lock_outline,
                      label: selectionPreferences.showLocked
                          ? 'Hide locked layers'
                          : 'Show locked layers',
                      selected: selectionPreferences.showLocked,
                    ),
                    UiMenuAction<String>(
                      value: 'toggle_hidden',
                      icon: Icons.visibility_off_outlined,
                      label: selectionPreferences.showHidden
                          ? 'Hide hidden layers'
                          : 'Show hidden layers',
                      selected: selectionPreferences.showHidden,
                    ),
                    if (selectionPreferences.isolateNodeId != null)
                      const UiMenuAction<String>(
                        value: 'clear_isolate',
                        icon: Icons.filter_none_outlined,
                        label: 'Exit isolate mode',
                      ),
                  ],
                  onSelected: (value) {
                    final notifier = ref.read(
                      canvasSelectionPreferencesProvider(
                        widget.projectId,
                      ).notifier,
                    );
                    if (value.startsWith('mode:')) {
                      final modeName = value.substring(5);
                      final mode = CanvasSelectionMode.values.firstWhere(
                        (candidate) => candidate.name == modeName,
                      );
                      notifier.setMode(mode);
                    } else if (value == 'toggle_locked') {
                      notifier.setShowLocked(!selectionPreferences.showLocked);
                    } else if (value == 'toggle_hidden') {
                      notifier.setShowHidden(!selectionPreferences.showHidden);
                    } else if (value == 'clear_isolate') {
                      notifier.clearIsolate();
                    }
                  },
                ),
                if (!widget.readOnly && selectedIds.length > 1)
                  UiMenuButton<String>(
                    key: const Key('layers-bulk-actions-menu'),
                    tooltip: 'Selection actions',
                    icon: Icons.checklist_outlined,
                    items: [
                      const UiMenuAction<String>(
                        value: 'rename',
                        icon: Icons.drive_file_rename_outline,
                        label: 'Rename selected',
                      ),
                      UiMenuAction<String>(
                        value: 'lock',
                        icon: Icons.lock_outline,
                        label:
                            displayNodes
                                .where((node) => selectedIds.contains(node.id))
                                .every((node) => node.locked)
                            ? 'Unlock selected'
                            : 'Lock selected',
                      ),
                      UiMenuAction<String>(
                        value: 'visibility',
                        icon: Icons.visibility_outlined,
                        label:
                            displayNodes
                                .where((node) => selectedIds.contains(node.id))
                                .every((node) => node.visible)
                            ? 'Hide selected'
                            : 'Show selected',
                      ),
                      for (final color in CanvasSelectionMath.layerColorPalette)
                        UiMenuAction<String>(
                          value: 'color:$color',
                          icon: Icons.palette_outlined,
                          label: 'Color ${_colorLabel(color)}',
                        ),
                      const UiMenuAction<String>(
                        value: 'color:none',
                        icon: Icons.format_color_reset_outlined,
                        label: 'Clear selected colors',
                      ),
                      const UiMenuAction<String>(
                        value: 'delete',
                        icon: Icons.delete_outline,
                        label: 'Delete selected',
                        destructive: true,
                      ),
                    ],
                    onSelected: (action) =>
                        _performBulkAction(action, selectedIds, displayNodes),
                  ),
                if (selectionPreferences.isolateNodeId != null)
                  UiIconButton(
                    icon: Icons.filter_none,
                    tooltip: 'Exit isolate mode',
                    size: UiButtonSize.sm,
                    onPressed: ref
                        .read(
                          canvasSelectionPreferencesProvider(
                            widget.projectId,
                          ).notifier,
                        )
                        .clearIsolate,
                  ),
              ],
            ),
          ),
          Divider(height: AppBorder.thin, color: tokens.panelBorder),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: UiTextField(
                    key: const Key('layers-filter-field'),
                    controller: _filterController,
                    hint: 'Filter layers...',
                    onChanged: (value) => setState(() => _filterQuery = value),
                  ),
                ),
                if (_filterQuery.trim().isNotEmpty)
                  UiIconButton(
                    icon: Icons.clear,
                    tooltip: 'Clear layer filter',
                    onPressed: _clearFilter,
                  ),
              ],
            ),
          ),
          Divider(height: AppBorder.thin, color: tokens.panelBorder),
          Expanded(
            child: roots.isEmpty
                ? Center(
                    child: Text(
                      _filterQuery.trim().isEmpty
                          ? 'No elements on canvas'
                          : 'No matching elements',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                    ),
                  )
                : (widget.readOnly || _filterQuery.trim().isNotEmpty
                      ? ListView.builder(
                          itemCount: roots.length,
                          itemBuilder: (context, index) => _rootItem(
                            roots[index],
                            childrenById,
                            selectedIds,
                            index: index,
                            rootIndex: null,
                            rootCount: 0,
                          ),
                        )
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: roots.length,
                          onReorderItem: (oldIndex, newIndex) {
                            ref
                                .read(documentNodesProvider.notifier)
                                .reorderRootNodes(oldIndex, newIndex);
                          },
                          itemBuilder: (context, index) => _rootItem(
                            roots[index],
                            childrenById,
                            selectedIds,
                            index: index,
                            rootIndex: index,
                            rootCount: roots.length,
                          ),
                        )),
          ),
        ],
      ),
    );
  }

  Widget _rootItem(
    CanvasNode node,
    Map<String, List<CanvasNode>> childrenById,
    Set<String> selectedIds, {
    required int index,
    required int? rootIndex,
    required int rootCount,
  }) {
    return KeyedSubtree(
      key: ValueKey(node.id),
      child: _buildNodeRow(
        node,
        childrenById,
        selectedIds,
        0,
        index: index,
        reorderIndex: rootIndex,
        reorderCount: rootCount,
      ),
    );
  }

  Widget _buildNodeRow(
    CanvasNode node,
    Map<String, List<CanvasNode>> childrenById,
    Set<String> selectedIds,
    int depth, {
    int index = 0,
    int? reorderIndex,
    int reorderCount = 0,
  }) {
    final tokens = context.appTokens;
    final children = childrenById[node.id] ?? const <CanvasNode>[];
    final hasChildren = children.isNotEmpty;
    final isCollapsed = _collapsedIds.contains(node.id);
    final showChildren =
        hasChildren && (!isCollapsed || _filterQuery.trim().isNotEmpty);
    final isSelected = selectedIds.contains(node.id);
    final pinCount = node.pins.isNotEmpty
        ? node.pins.length
        : (node.type == NodeType.annotatedImage
              ? (node.payload as AnnotatedImagePayload).pins.length
              : 0);
    final leadingControls = <Widget>[
      if (reorderIndex != null)
        ReorderableDragStartListener(
          index: reorderIndex,
          child: Padding(
            padding: const EdgeInsets.only(
              right: AppSpacing.xs + AppSpacing.xxs,
            ),
            child: Icon(Icons.drag_handle, size: 14, color: tokens.textMuted),
          ),
        ),
      if (hasChildren)
        UiIconButton(
          icon: isCollapsed ? Icons.chevron_right : Icons.expand_more,
          tooltip: isCollapsed ? 'Expand layer' : 'Collapse layer',
          size: UiButtonSize.sm,
          onPressed: () => setState(() {
            if (isCollapsed) {
              _collapsedIds.remove(node.id);
            } else {
              _collapsedIds.add(node.id);
            }
          }),
        )
      else
        Icon(
          _getNodeIcon(node.type.name),
          size: 15,
          color: isSelected ? tokens.accent : tokens.textMuted,
        ),
      if (node.layerColor != null) ...[
        const SizedBox(width: AppSpacing.xs),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Color(node.layerColor!),
            shape: BoxShape.circle,
          ),
        ),
      ],
    ];
    final selectionLabel = Expanded(
      child: Focus(
        key: ValueKey('layer-focus-${node.id}'),
        onKeyEvent: (focusNode, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            _selectNode(node);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MergeSemantics(
          child: Semantics(
            button: true,
            selected: isSelected,
            focusable: true,
            child: InkWell(
              key: ValueKey('layer-selection-${node.id}'),
              onTap: () => _selectNode(node),
              onDoubleTap: () => _focusNode(node),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _nodeLabel(node),
                      semanticsLabel:
                          '${_nodeLabel(node)} (${_typeLabel(node.type)})',
                      style: TextStyle(
                        color: isSelected ? tokens.text : tokens.textMuted,
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        letterSpacing: 0.8,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (pinCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Text(
                        '📌 $pinCount',
                        style: TextStyle(
                          color: tokens.warning,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final actionControls = <Widget>[
      UiIconButton(
        icon: Icons.center_focus_strong,
        tooltip: 'Focus on canvas',
        size: UiButtonSize.xs,
        onPressed: () => _focusNode(node),
      ),
      if (reorderIndex != null) ...[
        UiIconButton(
          icon: Icons.keyboard_arrow_up,
          tooltip: 'Move Up (Bring Forward)',
          size: UiButtonSize.xs,
          onPressed: reorderIndex > 0
              ? () => ref
                    .read(documentNodesProvider.notifier)
                    .reorderRootNodes(reorderIndex, reorderIndex - 1)
              : null,
        ),
        UiIconButton(
          icon: Icons.keyboard_arrow_down,
          tooltip: 'Move Down (Send Backward)',
          size: UiButtonSize.xs,
          onPressed: reorderIndex < reorderCount - 1
              ? () => ref
                    .read(documentNodesProvider.notifier)
                    .reorderRootNodes(reorderIndex, reorderIndex + 1)
              : null,
        ),
      ],
      if (!widget.readOnly)
        UiMenuButton<String>(
          tooltip: 'Object actions',
          icon: Icons.more_horiz,
          items: [
            UiMenuAction(
              value: 'visibility',
              icon: node.visible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              label: node.visible ? 'Hide' : 'Show',
              selected: node.visible,
            ),
            UiMenuAction(
              value: 'lock',
              icon: node.locked ? Icons.lock : Icons.lock_open_outlined,
              label: node.locked ? 'Unlock' : 'Lock',
              selected: node.locked,
            ),
            UiMenuAction(
              value: 'isolate',
              icon: Icons.filter_none_outlined,
              label: 'Isolate this layer',
              selected:
                  ref
                      .read(
                        canvasSelectionPreferencesProvider(widget.projectId),
                      )
                      .isolateNodeId ==
                  node.id,
            ),
            const UiMenuAction(
              value: 'rename',
              icon: Icons.drive_file_rename_outline,
              label: 'Rename',
            ),
            for (final color in CanvasSelectionMath.layerColorPalette)
              UiMenuAction(
                value: 'color:$color',
                icon: Icons.circle,
                label: 'Layer color',
                suffix: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                  ),
                ),
                selected: node.layerColor == color,
              ),
            if (node.layerColor != null)
              const UiMenuAction(
                value: 'color:none',
                icon: Icons.format_color_reset_outlined,
                label: 'Clear layer color',
              ),
            const UiMenuAction(
              value: 'delete',
              icon: Icons.delete_outline,
              label: 'Delete',
              destructive: true,
            ),
          ],
          onSelected: (action) => _performAction(action, node, selectedIds),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: depth * 14.0,
            right: AppSpacing.xs,
            top: 1,
            bottom: 1,
          ),
          child: UiSurface(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs + AppSpacing.xxs,
              vertical: AppSpacing.xs + AppSpacing.xxs / 2,
            ),
            color: isSelected ? tokens.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.control),
            bordered: isSelected,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < AppBreakpoints.compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [...leadingControls, selectionLabel]),
                      if (actionControls.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: AppSpacing.xxs,
                            children: actionControls,
                          ),
                        ),
                    ],
                  );
                }
                return Row(
                  children: [
                    ...leadingControls,
                    selectionLabel,
                    ...actionControls,
                  ],
                );
              },
            ),
          ),
        ),
        if (showChildren)
          ...children.map(
            (child) =>
                _buildNodeRow(child, childrenById, selectedIds, depth + 1),
          ),
      ],
    );
  }

  void _performAction(String action, CanvasNode node, Set<String> selectedIds) {
    if (widget.readOnly) return;
    final notifier = ref.read(documentNodesProvider.notifier);
    if (action == 'visibility') {
      notifier.updateNode(node.copyWith(visible: !node.visible));
    } else if (action == 'lock') {
      notifier.updateNode(node.copyWith(locked: !node.locked));
    } else if (action == 'isolate') {
      final preferences = ref.read(
        canvasSelectionPreferencesProvider(widget.projectId),
      );
      final selectionNotifier = ref.read(
        canvasSelectionPreferencesProvider(widget.projectId).notifier,
      );
      if (preferences.isolateNodeId == node.id) {
        selectionNotifier.clearIsolate();
      } else {
        selectionNotifier.setIsolateNode(node.id);
      }
    } else if (action == 'rename') {
      _renameNode(node);
    } else if (action.startsWith('color:')) {
      final value = action.substring(6);
      notifier.setLayerColor([
        node.id,
      ], value == 'none' ? null : int.tryParse(value));
    } else if (action == 'delete') {
      notifier.deleteNodes([node.id]);
      if (selectedIds.contains(node.id)) {
        ref.read(selectionProvider.notifier).toggle(node.id);
      }
    }
  }

  void _performBulkAction(
    String action,
    Set<String> selectedIds,
    List<CanvasNode> availableNodes,
  ) {
    if (widget.readOnly) return;
    final ids = selectedIds.toList(growable: false);
    final targets = availableNodes
        .where((node) => selectedIds.contains(node.id))
        .toList(growable: false);
    if (targets.length < 2) return;
    final notifier = ref.read(documentNodesProvider.notifier);

    if (action == 'rename') {
      unawaited(_renameSelectedNodes(targets));
      return;
    }
    if (action == 'lock') {
      notifier.setLocked(ids, targets.any((node) => !node.locked));
      return;
    }
    if (action == 'visibility') {
      notifier.setVisible(ids, targets.any((node) => !node.visible));
      return;
    }
    if (action.startsWith('color:')) {
      final raw = action.substring(6);
      notifier.setLayerColor(ids, raw == 'none' ? null : int.tryParse(raw));
      return;
    }
    if (action == 'delete') {
      unawaited(_deleteSelectedNodes(ids));
    }
  }

  Future<void> _renameSelectedNodes(List<CanvasNode> nodes) async {
    final value = await showUiDialog<String>(
      context: context,
      builder: (_) => const _LayerRenameDialog(
        key: ValueKey('bulk-rename-dialog'),
        title: 'Rename selected layers',
        fieldLabel: 'Name pattern',
        initialValue: 'Layer {index:02}',
        hint: 'Layer {index:02}',
        description: '{index}, {index:02}, {name}, or # are supported.',
      ),
    );
    final resultPattern = value?.trim();
    if (!mounted || resultPattern == null || resultPattern.isEmpty) return;
    final ordered = List<CanvasNode>.from(nodes)
      ..sort((left, right) {
        final z = right.zIndex.compareTo(left.zIndex);
        return z == 0 ? left.id.compareTo(right.id) : z;
      });
    ref
        .read(documentNodesProvider.notifier)
        .renameNodes(CanvasSelectionMath.batchRename(ordered, resultPattern));
  }

  Future<void> _deleteSelectedNodes(List<String> ids) async {
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Delete selected layers',
        constraints: AppResponsive.dialogConstraints(
          dialogContext,
          maxWidth: 420,
          maxHeight: 240,
        ),
        builder: (context, style) => Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Delete selected layers?', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              Text('${ids.length} layers will be removed.'),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    variant: UiButtonVariant.destructive,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    ref.read(documentNodesProvider.notifier).deleteNodes(ids);
    final remaining = ref
        .read(documentNodesProvider)
        .where((node) => ids.contains(node.id))
        .map((node) => node.id)
        .toList(growable: false);
    ref.read(selectionProvider.notifier).selectAll(remaining);
  }

  String _colorLabel(int color) =>
      '#${color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  Future<void> _renameNode(CanvasNode node) async {
    final value = await showUiDialog<String>(
      context: context,
      builder: (_) => _LayerRenameDialog(
        title: 'Rename layer',
        fieldLabel: 'Layer name',
        initialValue: _nodeLabel(node),
      ),
    );
    final name = value?.trim();
    if (!mounted || name == null || name.isEmpty) return;
    ref.read(documentNodesProvider.notifier).renameNodes({node.id: name});
  }

  String _selectionModeLabel(CanvasSelectionMode mode) => switch (mode) {
    CanvasSelectionMode.direct => 'Direct',
    CanvasSelectionMode.deep => 'Deep',
    CanvasSelectionMode.selectThrough => 'Select-through',
  };

  String _nodeLabel(CanvasNode node) {
    final explicit = node.name?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final payload = node.payload;
    String? value;
    if (payload is TextPayload) {
      value = payload.text;
    } else if (payload is StickyNotePayload) {
      value = payload.text;
    } else if (payload is ShapePayload) {
      value = payload.label;
    } else if (payload is FramePayload) {
      value = payload.name;
    } else if (payload is GroupPayload) {
      value = payload.name;
    } else if (payload is ComponentPayload) {
      value = payload.componentName;
    } else if (payload is FilePayload) {
      value = payload.fileName;
    } else if (payload is Model3DPayload) {
      value = payload.displayName;
    } else if (payload is DocumentPayload) {
      value = payload.title;
    } else if (payload is EmbedPayload) {
      value = payload.title?.trim().isNotEmpty == true
          ? payload.title
          : payload.provider;
    } else if (payload is LinkPayload) {
      value = payload.title;
    } else if (payload is VideoPayload) {
      value = payload.title;
    } else if (payload is AudioPayload) {
      value = payload.trackName;
    } else if (payload is MapPayload) {
      value = payload.locationTitle;
    } else if (payload is ColumnPayload) {
      value = payload.headerTitle;
    } else if (payload is NestedBoardPayload) {
      value = payload.boardName;
    } else if (payload is TablePayload) {
      value = payload.name;
    } else if (payload is TodoListPayload) {
      value = payload.title;
    } else if (payload is DrawingPaperPayload) {
      value = payload.presetName;
    }
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty
        ? _typeLabel(node.type)
        : trimmed.split('\n').first;
  }

  String _nodeSearchText(CanvasNode node) =>
      '${_nodeLabel(node)} ${_typeLabel(node.type)}'.toLowerCase();

  String _typeLabel(NodeType type) {
    if (type == NodeType.model3d) return '3D Model';
    final spaced = type.name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    return spaced
        .split(' ')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  IconData _getNodeIcon(String type) {
    switch (type) {
      case 'rectangle':
        return Icons.crop_square;
      case 'ellipse':
        return Icons.circle_outlined;
      case 'diamond':
        return Icons.change_history;
      case 'cylinder':
        return Icons.storage_outlined;
      case 'parallelogram':
        return Icons.view_sidebar_outlined;
      case 'line':
        return Icons.horizontal_rule;
      case 'arrow':
        return Icons.arrow_right_alt;
      case 'stickyNote':
        return Icons.sticky_note_2_outlined;
      case 'text':
        return Icons.title;
      case 'frame':
        return Icons.crop_free;
      case 'image':
        return Icons.image_outlined;
      case 'vectorPath':
        return Icons.colorize;
      case 'component':
        return Icons.widgets_outlined;
      case 'group':
        return Icons.folder_outlined;
      case 'drawing':
        return Icons.draw_outlined;
      case 'drawingPaper':
        return Icons.description_outlined;
      case 'fileCard':
        return Icons.insert_drive_file_outlined;
      case 'model3d':
        return Icons.view_in_ar_outlined;
      case 'linkCard':
        return Icons.link;
      case 'videoCard':
        return Icons.video_library_outlined;
      case 'audioCard':
        return Icons.audiotrack_outlined;
      case 'mapCard':
        return Icons.map_outlined;
      case 'document':
        return Icons.article_outlined;
      case 'embed':
        return Icons.public;
      case 'sketchCard':
        return Icons.gesture;
      case 'annotatedImage':
        return Icons.image_search_outlined;
      case 'columnContainer':
        return Icons.view_column_outlined;
      case 'nestedBoard':
        return Icons.dashboard_outlined;
      case 'tableGrid':
        return Icons.table_chart_outlined;
      case 'todoList':
        return Icons.checklist;
      default:
        return Icons.layers;
    }
  }
}
