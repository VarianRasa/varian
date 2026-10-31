import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/color_picker_dialog.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import 'package:varian/features/charts/presentation/chart_palette.dart';
import 'package:varian/features/diagrams/presentation/diagram_shape_palette.dart';

class ToolItem {
  final CanvasTool tool;
  final IconData icon;
  final String label;

  const ToolItem(this.tool, this.icon, this.label);
}

class ToolCategory {
  final String id;
  final String title;
  final IconData defaultIcon;
  final List<ToolItem> items;

  const ToolCategory({
    required this.id,
    required this.title,
    required this.defaultIcon,
    required this.items,
  });
}

class _BrushWidthField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _BrushWidthField({required this.value, required this.onChanged});

  @override
  State<_BrushWidthField> createState() => _BrushWidthFieldState();
}

class _BrushWidthFieldState extends State<_BrushWidthField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _BrushWidthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  static String _format(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();

  void _syncController({bool force = false}) {
    if (_focusNode.hasFocus && !force) return;
    final text = _format(widget.value);
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite) {
      _syncController(force: true);
      return;
    }
    final next = parsed.clamp(minBrushWidth, maxBrushWidth).toDouble();
    widget.onChanged(next);
    final text = _format(next);
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 62,
    height: AppControlSize.minimumHitTarget,
    child: Semantics(
      textField: true,
      label: 'Custom brush width',
      hint: 'Enter a width from $minBrushWidth to $maxBrushWidth',
      child: UiTextField(
        key: const ValueKey('custom-brush-width'),
        controller: _controller,
        focusNode: _focusNode,
        label: 'Custom',
        hint: '1–100',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        textAlign: TextAlign.center,
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
      ),
    ),
  );
}

class CanvasToolbar extends ConsumerStatefulWidget {
  final bool aiActive;
  final VoidCallback? onAiPressed;
  final VoidCallback? onModel3dPressed;

  const CanvasToolbar({
    super.key,
    this.aiActive = false,
    this.onAiPressed,
    this.onModel3dPressed,
  });

  @override
  ConsumerState<CanvasToolbar> createState() => _CanvasToolbarState();
}

class _CanvasToolbarState extends ConsumerState<CanvasToolbar> {
  String? _expandedCategoryId;

  static const List<ToolCategory> _categories = [
    ToolCategory(
      id: 'pointer',
      title: 'Navigation',
      defaultIcon: Icons.near_me_outlined,
      items: [
        ToolItem(CanvasTool.select, Icons.near_me_outlined, 'Select (V)'),
        ToolItem(CanvasTool.hand, Icons.pan_tool_outlined, 'Hand / Pan (H)'),
      ],
    ),
    ToolCategory(
      id: 'shapes',
      title: 'Shapes & Links',
      defaultIcon: Icons.crop_square,
      items: [
        ToolItem(CanvasTool.frame, Icons.crop_free, 'Frame Container (F)'),
        ToolItem(CanvasTool.rectangle, Icons.crop_square, 'Rectangle (R)'),
        ToolItem(CanvasTool.ellipse, Icons.circle_outlined, 'Ellipse (O)'),
        ToolItem(
          CanvasTool.diamond,
          Icons.change_history,
          'Diamond (Decision)',
        ),
        ToolItem(
          CanvasTool.cylinder,
          Icons.storage_outlined,
          'Cylinder (Database)',
        ),
        ToolItem(
          CanvasTool.parallelogram,
          Icons.view_sidebar_outlined,
          'Data / IO',
        ),
        ToolItem(CanvasTool.line, Icons.horizontal_rule, 'Line (L)'),
        ToolItem(CanvasTool.arrow, Icons.arrow_right_alt, 'Arrow (A)'),
        ToolItem(
          CanvasTool.connector,
          Icons.hub_outlined,
          'Smart Connector (C)',
        ),
      ],
    ),
    ToolCategory(
      id: 'diagrams',
      title: 'Diagrams',
      defaultIcon: Icons.account_tree_outlined,
      items: [
        ToolItem(
          CanvasTool.diagramShape,
          Icons.category_outlined,
          'Native diagram shapes',
        ),
        ToolItem(
          CanvasTool.mermaid,
          Icons.account_tree_outlined,
          'Mermaid source',
        ),
      ],
    ),
    ToolCategory(
      id: 'charts',
      title: 'Charts',
      defaultIcon: Icons.bar_chart,
      items: [ToolItem(CanvasTool.chart, Icons.bar_chart, 'Chart types')],
    ),
    ToolCategory(
      id: 'creative',
      title: 'Draw & Vector',
      defaultIcon: Icons.draw_outlined,
      items: [
        ToolItem(
          CanvasTool.drawingPaper,
          Icons.note_add_outlined,
          'Drawing Paper Studio',
        ),
        ToolItem(CanvasTool.brush, Icons.draw_outlined, 'Brush / Freehand (B)'),
        ToolItem(CanvasTool.pen, Icons.colorize, 'Vector Pen Tool (P)'),
        ToolItem(CanvasTool.sketchCard, Icons.gesture_outlined, 'Sketch Card'),
        ToolItem(
          CanvasTool.annotate,
          Icons.push_pin_outlined,
          'Annotate Image',
        ),
      ],
    ),
    ToolCategory(
      id: 'ai',
      title: 'AI Creative',
      defaultIcon: Icons.auto_awesome_outlined,
      items: [
        ToolItem(CanvasTool.select, Icons.auto_awesome, 'Focus AI prompt'),
      ],
    ),
    ToolCategory(
      id: 'text',
      title: 'Text & Notes',
      defaultIcon: Icons.title,
      items: [
        ToolItem(CanvasTool.text, Icons.title, 'Text (T)'),
        ToolItem(
          CanvasTool.stickyNote,
          Icons.sticky_note_2_outlined,
          'Sticky Note (N)',
        ),
        ToolItem(CanvasTool.document, Icons.description_outlined, 'Document'),
        ToolItem(
          CanvasTool.colorSwatch,
          Icons.palette_outlined,
          'Color Swatch',
        ),
      ],
    ),
    ToolCategory(
      id: 'org',
      title: 'Structure',
      defaultIcon: Icons.table_chart_outlined,
      items: [
        ToolItem(
          CanvasTool.todoList,
          Icons.checklist_outlined,
          'To-do List (X)',
        ),
        ToolItem(
          CanvasTool.tableGrid,
          Icons.table_chart_outlined,
          'Table Matrix (G)',
        ),
        ToolItem(
          CanvasTool.columnContainer,
          Icons.view_column_outlined,
          'Column Card (U)',
        ),
        ToolItem(
          CanvasTool.nestedBoard,
          Icons.dashboard_customize_outlined,
          'Nested Board',
        ),
        ToolItem(CanvasTool.component, Icons.widgets_outlined, 'Component (K)'),
      ],
    ),
    ToolCategory(
      id: 'media',
      title: 'Media & Cards',
      defaultIcon: Icons.perm_media_outlined,
      items: [
        ToolItem(CanvasTool.image, Icons.image_outlined, 'Image Asset (I)'),
        ToolItem(
          CanvasTool.fileCard,
          Icons.insert_drive_file_outlined,
          'File Card',
        ),
        ToolItem(
          CanvasTool.model3d,
          Icons.view_in_ar_outlined,
          '3D Model (GLB)',
        ),
        ToolItem(CanvasTool.linkCard, Icons.link_outlined, 'Link Card'),
        ToolItem(CanvasTool.videoCard, Icons.videocam_outlined, 'Video Card'),
        ToolItem(CanvasTool.audioCard, Icons.audiotrack_outlined, 'Audio Card'),
        ToolItem(CanvasTool.mapCard, Icons.map_outlined, 'Map Location'),
        ToolItem(CanvasTool.embed, Icons.smart_display_outlined, 'Embed Media'),
      ],
    ),
    ToolCategory(
      id: 'collab',
      title: 'Feedback',
      defaultIcon: Icons.chat_bubble_outline,
      items: [
        ToolItem(CanvasTool.comment, Icons.chat_bubble_outline, 'Comment (M)'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final activeTool = ref.watch(activeToolProvider);
    final brushConfig = ref.watch(activeBrushConfigProvider);
    final tokens = context.appTokens;

    final expandedCategory = _categories
        .where((c) => c.id == _expandedCategoryId)
        .firstOrNull;

    final maxToolbarHeight = math.max(
      0.0,
      MediaQuery.sizeOf(context).height - AppSpacing.xl,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Compact Main Folder Sidebar (Only 7 slots)
        UiSurface(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xs + AppSpacing.xxs,
          ),
          color: tokens.panelElevated.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxToolbarHeight),
            child: SingleChildScrollView(
              key: const ValueKey('canvas-toolbar-sidebar-scroll'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _categories
                    .map((cat) {
                      final activeToolInCategory = cat.id == 'ai'
                          ? null
                          : cat.items
                                .where((it) => it.tool == activeTool)
                                .firstOrNull;
                      final isCategoryActive = cat.id == 'ai'
                          ? widget.aiActive
                          : activeToolInCategory != null;
                      final isExpanded = _expandedCategoryId == cat.id;

                      // Display active item icon if selected, otherwise category default icon
                      final displayIcon =
                          activeToolInCategory?.icon ?? cat.defaultIcon;

                      final categoryTooltip = cat.id == 'ai'
                          ? widget.aiActive
                                ? 'Hide AI prompt'
                                : 'Show AI prompt'
                          : '${cat.title} (Click to open)';

                      return Tooltip(
                        message: categoryTooltip,
                        preferBelow: false,
                        child: Semantics(
                          button: true,
                          label: cat.id == 'ai'
                              ? categoryTooltip
                              : '${cat.title} tools',
                          selected: isCategoryActive,
                          expanded: isExpanded,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                tokens.controlRadius,
                              ),
                              onTap: () {
                                if (cat.id == 'ai') {
                                  setState(() => _expandedCategoryId = null);
                                  widget.onAiPressed?.call();
                                  return;
                                }
                                setState(() {
                                  if (_expandedCategoryId == cat.id) {
                                    _expandedCategoryId = null;
                                  } else {
                                    _expandedCategoryId = cat.id;
                                    // Single-item palettes such as Charts open without
                                    // activating their creation tool.
                                    if (cat.items.length == 1 &&
                                        cat.id != 'charts') {
                                      ref
                                          .read(activeToolProvider.notifier)
                                          .setTool(cat.items.first.tool);
                                    }
                                  }
                                });
                              },
                              child: SizedBox(
                                key: ValueKey(
                                  'canvas-toolbar-category-target-${cat.id}',
                                ),
                                width: AppControlSize.minimumHitTarget,
                                height: AppControlSize.minimumHitTarget,
                                child: Center(
                                  child: Container(
                                    key: ValueKey(
                                      'canvas-toolbar-category-visual-${cat.id}',
                                    ),
                                    width: AppControlSize.regular,
                                    height: AppControlSize.regular,
                                    decoration: BoxDecoration(
                                      color: isCategoryActive
                                          ? tokens.accent
                                          : isExpanded
                                          ? tokens.accentSoft
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(
                                        tokens.controlRadius,
                                      ),
                                      border: isCategoryActive
                                          ? Border.all(
                                              color: tokens.accentForeground
                                                  .withValues(alpha: 0.2),
                                              width: AppBorder.thin,
                                            )
                                          : isExpanded
                                          ? Border.all(
                                              color: tokens.panelBorder,
                                              width: AppBorder.thin,
                                            )
                                          : null,
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Icon(
                                          displayIcon,
                                          size: 19,
                                          color: isCategoryActive
                                              ? tokens.accentForeground
                                              : tokens.textMuted,
                                        ),
                                        if (cat.items.length > 1 ||
                                            cat.id == 'charts')
                                          Positioned(
                                            right: 2,
                                            bottom: 2,
                                            child: Icon(
                                              Icons.arrow_right,
                                              size: 10,
                                              color: isCategoryActive
                                                  ? tokens.accentForeground
                                                        .withValues(alpha: 0.72)
                                                  : tokens.textMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ),
        ),

        // 2. Flyout Sub-menu Drawer Panel
        if (expandedCategory != null &&
            (expandedCategory.items.length > 1 ||
                expandedCategory.id == 'charts')) ...[
          const SizedBox(width: AppSpacing.sm),
          UiSurface(
            padding: const EdgeInsets.all(AppSpacing.xs + AppSpacing.xxs),
            color: tokens.panelElevated.withValues(alpha: 0.96),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxToolbarHeight),
              child: SingleChildScrollView(
                key: const ValueKey('canvas-toolbar-flyout-scroll'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs + AppSpacing.xxs,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            expandedCategory.title.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall!
                                .copyWith(
                                  color: tokens.textMuted,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          UiIconButton(
                            tooltip: 'Close ${expandedCategory.title} tools',
                            icon: Icons.close,
                            onPressed: () =>
                                setState(() => _expandedCategoryId = null),
                            variant: UiButtonVariant.ghost,
                            size: UiButtonSize.sm,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ...expandedCategory.items.map((item) {
                      final isItemActive = activeTool == item.tool;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Semantics(
                          button: true,
                          label: item.label,
                          selected: isItemActive,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                tokens.controlRadius,
                              ),
                              onTap: () {
                                ref
                                    .read(activeToolProvider.notifier)
                                    .setTool(item.tool);
                                if (item.tool == CanvasTool.diagramShape ||
                                    item.tool == CanvasTool.chart) {
                                  return;
                                }
                                setState(() {
                                  _expandedCategoryId = null;
                                });
                                if (item.tool == CanvasTool.model3d) {
                                  widget.onModel3dPressed?.call();
                                }
                              },
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: AppControlSize.minimumHitTarget,
                                ),
                                child: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.xs + AppSpacing.xxs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isItemActive
                                        ? tokens.accent.withValues(alpha: 0.2)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(
                                      tokens.controlRadius,
                                    ),
                                    border: isItemActive
                                        ? Border.all(
                                            color: tokens.accent.withValues(
                                              alpha: 0.5,
                                            ),
                                            width: AppBorder.thin,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        item.icon,
                                        size: 16,
                                        color: isItemActive
                                            ? tokens.accent
                                            : tokens.textMuted,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Text(
                                        item.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium!
                                            .copyWith(
                                              color: isItemActive
                                                  ? tokens.text
                                                  : tokens.textMuted,
                                              fontWeight: isItemActive
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    if (expandedCategory.id == 'diagrams') ...[
                      const SizedBox(height: AppSpacing.sm),
                      DiagramShapePalette(
                        onClose: () =>
                            setState(() => _expandedCategoryId = null),
                      ),
                    ],
                    if (expandedCategory.id == 'charts') ...[
                      const SizedBox(height: AppSpacing.sm),
                      ChartPalette(
                        onClose: () =>
                            setState(() => _expandedCategoryId = null),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],

        // 3. Contextual Brush Preset Panel
        if (activeTool == CanvasTool.brush) ...[
          const SizedBox(width: AppSpacing.sm),
          UiSurface(
            padding: const EdgeInsets.all(AppSpacing.sm),
            color: tokens.panelElevated.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(tokens.controlRadius),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxToolbarHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BRUSH PRESET',
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: tokens.textMuted,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: BrushType.values.map((b) {
                        final isSel = brushConfig.brushType == b;
                        final isEraser = b == BrushType.eraser;
                        return Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: Semantics(
                            button: true,
                            label: 'Brush type ${b.name}',
                            selected: isSel,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  tokens.controlRadius,
                                ),
                                onTap: () => ref
                                    .read(activeBrushConfigProvider.notifier)
                                    .setBrushType(b),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: AppControlSize.minimumHitTarget,
                                    minHeight: AppControlSize.minimumHitTarget,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal:
                                            AppSpacing.xs + AppSpacing.xxs,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? (isEraser
                                                  ? tokens.danger
                                                  : tokens.accent)
                                            : tokens.panelElevated,
                                        borderRadius: BorderRadius.circular(
                                          tokens.controlRadius,
                                        ),
                                        border: Border.all(
                                          color: isSel
                                              ? (isEraser
                                                    ? tokens.danger
                                                    : tokens.accent)
                                              : tokens.panelBorder,
                                          width: AppBorder.thin,
                                        ),
                                      ),
                                      child: Text(
                                        b.name.toUpperCase(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall!
                                            .copyWith(
                                              color: isSel
                                                  ? tokens.accentForeground
                                                  : tokens.textMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Color: ',
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(color: tokens.textMuted),
                        ),
                        UiButton(
                          semanticsLabel: 'Pick brush color',
                          onPressed: brushConfig.brushType == BrushType.eraser
                              ? null
                              : () {
                                  showUiDialog<void>(
                                    context: context,
                                    builder: (dialogContext) =>
                                        ColorPickerDialog(
                                          dialogContext: dialogContext,
                                          dialogLabel: 'Pick brush color',
                                          title: 'Brush Color',
                                          currentColor: brushConfig.color,
                                          onColorChanged: (color) => ref
                                              .read(
                                                activeBrushConfigProvider
                                                    .notifier,
                                              )
                                              .setColor(color),
                                        ),
                                  );
                                },
                          variant: UiButtonVariant.outline,
                          size: UiButtonSize.sm,
                          prefix: DecoratedBox(
                            decoration: BoxDecoration(
                              color: brushConfig.color,
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                              border: Border.all(
                                color: tokens.panelBorder,
                                width: AppBorder.thin,
                              ),
                            ),
                            child: const SizedBox(width: 16, height: 16),
                          ),
                          child: Text(
                            colorToHex(
                              brushConfig.color,
                              includeHashSign: true,
                              enableAlpha: true,
                            ),
                            style: Theme.of(context).textTheme.labelSmall!,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Width: ',
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(color: tokens.textMuted),
                        ),
                        ...[2.0, 4.0, 8.0, 16.0, 24.0].map((w) {
                          final isW = brushConfig.strokeWidth == w;
                          return Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.xs,
                            ),
                            child: Semantics(
                              button: true,
                              label: 'Brush width ${w.toInt()}',
                              selected: isW,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    tokens.controlRadius,
                                  ),
                                  onTap: () => ref
                                      .read(activeBrushConfigProvider.notifier)
                                      .setStrokeWidth(w),
                                  child: SizedBox(
                                    key: ValueKey(
                                      'canvas-brush-width-target-${w.toInt()}',
                                    ),
                                    width: AppControlSize.minimumHitTarget,
                                    height: AppControlSize.minimumHitTarget,
                                    child: Center(
                                      child: Container(
                                        width: 26,
                                        height: 20,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isW
                                              ? tokens.accent
                                              : tokens.panelElevated,
                                          borderRadius: BorderRadius.circular(
                                            tokens.controlRadius,
                                          ),
                                        ),
                                        child: Text(
                                          '${w.toInt()}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall!
                                              .copyWith(
                                                color: isW
                                                    ? tokens.accentForeground
                                                    : tokens.textMuted,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(width: AppSpacing.xs),
                        _BrushWidthField(
                          value: brushConfig.strokeWidth,
                          onChanged: (width) => ref
                              .read(activeBrushConfigProvider.notifier)
                              .setStrokeWidth(width),
                        ),
                        if (brushConfig.brushType == BrushType.eraser) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Semantics(
                            button: true,
                            label: 'Eraser mode',
                            value: brushConfig.eraserMode == EraserMode.stroke
                                ? 'Stroke'
                                : 'Partial',
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  tokens.controlRadius,
                                ),
                                onTap: () {
                                  final nextMode =
                                      brushConfig.eraserMode ==
                                          EraserMode.stroke
                                      ? EraserMode.segment
                                      : EraserMode.stroke;
                                  ref
                                      .read(activeBrushConfigProvider.notifier)
                                      .setEraserMode(nextMode);
                                },
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: AppControlSize.minimumHitTarget,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal:
                                            AppSpacing.xs + AppSpacing.xxs,
                                        vertical: AppSpacing.xxs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tokens.panel,
                                        borderRadius: BorderRadius.circular(
                                          tokens.controlRadius,
                                        ),
                                        border: Border.all(
                                          color: tokens.panelBorder,
                                          width: AppBorder.thin,
                                        ),
                                      ),
                                      child: Text(
                                        brushConfig.eraserMode ==
                                                EraserMode.stroke
                                            ? 'MODE: STROKE'
                                            : 'MODE: PARTIAL',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall!
                                            .copyWith(
                                              color: tokens.danger,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(width: AppSpacing.sm),
                          Semantics(
                            button: true,
                            label: 'Smooth curves',
                            toggled: brushConfig.smoothCurves,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  tokens.controlRadius,
                                ),
                                onTap: () => ref
                                    .read(activeBrushConfigProvider.notifier)
                                    .setSmoothCurves(!brushConfig.smoothCurves),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: AppControlSize.minimumHitTarget,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal:
                                            AppSpacing.xs + AppSpacing.xxs,
                                        vertical: AppSpacing.xxs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: brushConfig.smoothCurves
                                            ? tokens.accent.withValues(
                                                alpha: 0.2,
                                              )
                                            : tokens.panelElevated,
                                        borderRadius: BorderRadius.circular(
                                          tokens.controlRadius,
                                        ),
                                        border: Border.all(
                                          color: brushConfig.smoothCurves
                                              ? tokens.accent
                                              : tokens.panelBorder,
                                          width: AppBorder.thin,
                                        ),
                                      ),
                                      child: Text(
                                        brushConfig.smoothCurves
                                            ? 'SMOOTH: ON'
                                            : 'SMOOTH: OFF',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall!
                                            .copyWith(
                                              color: brushConfig.smoothCurves
                                                  ? tokens.accent
                                                  : tokens.textMuted,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
