import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';

class DiagramShapePalette extends ConsumerStatefulWidget {
  final VoidCallback? onClose;

  const DiagramShapePalette({this.onClose, super.key});

  @override
  ConsumerState<DiagramShapePalette> createState() =>
      _DiagramShapePaletteState();
}

class _DiagramShapePaletteState extends ConsumerState<DiagramShapePalette> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  DiagramShapeCategory? _category;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paletteWidth =
        (MediaQuery.sizeOf(context).width -
                AppResponsive.pagePadding(context).horizontal -
                72)
            .clamp(0.0, 330.0)
            .toDouble();
    final preferredHeight = AppResponsive.dialogHeight(context, preferred: 470);
    final tokens = context.appTokens;
    final selected = ref.watch(activeDiagramShapeProvider);
    final entries = DiagramShapeCatalog.entries
        .where((entry) {
          final categoryMatches =
              _category == null || entry.category == _category;
          final query = _query.trim().toLowerCase();
          final queryMatches =
              query.isEmpty ||
              entry.name.toLowerCase().contains(query) ||
              entry.id.toLowerCase().contains(query);
          return categoryMatches && queryMatches;
        })
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final paletteHeight = constraints.hasBoundedHeight
            ? math.min(constraints.maxHeight, preferredHeight)
            : preferredHeight;
        return SizedBox(
          width: paletteWidth,
          height: paletteHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiSectionHeader(
                title: 'DIAGRAM SHAPES',
                trailing: UiIconButton(
                  tooltip: 'Close diagram shapes',
                  icon: Icons.close,
                  onPressed: widget.onClose,
                  variant: UiButtonVariant.ghost,
                  size: UiButtonSize.sm,
                ),
              ),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              UiTextField(
                controller: _searchController,
                label: 'Search shapes',
                hint: 'Search by name or shape ID',
                prefix: const Icon(Icons.search, size: 16),
                clearable: true,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _CategoryChip(
                      label: 'All',
                      selected: _category == null,
                      onPressed: () => setState(() => _category = null),
                    ),
                    for (final category in DiagramShapeCategory.values)
                      _CategoryChip(
                        label: _categoryLabel(category),
                        selected: _category == category,
                        onPressed: () => setState(() => _category = category),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.pageWide),
                          child: Text(
                            'No diagram shapes found.',
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(color: tokens.textMuted),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: AppSpacing.xs + AppSpacing.xxs,
                          runSpacing: AppSpacing.xs + AppSpacing.xxs,
                          children: [
                            for (final entry in entries)
                              _ShapeButton(
                                entry: entry,
                                selected: selected.id == entry.id,
                                onPressed: () {
                                  ref
                                          .read(
                                            activeDiagramShapeProvider.notifier,
                                          )
                                          .state =
                                      entry;
                                  ref
                                      .read(activeToolProvider.notifier)
                                      .setTool(CanvasTool.diagramShape);
                                  widget.onClose?.call();
                                },
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _categoryLabel(DiagramShapeCategory category) => switch (category) {
    DiagramShapeCategory.basic => 'Basic',
    DiagramShapeCategory.flowchart => 'Flowchart',
    DiagramShapeCategory.uml => 'UML',
    DiagramShapeCategory.bpmn => 'BPMN',
    DiagramShapeCategory.network => 'Network',
    DiagramShapeCategory.database => 'Data',
    DiagramShapeCategory.people => 'People',
    DiagramShapeCategory.container => 'Containers',
    DiagramShapeCategory.notes => 'Notes',
    DiagramShapeCategory.arrows => 'Arrows',
  };
}

class _ShapeButton extends StatelessWidget {
  final DiagramShapeDefinition entry;
  final bool selected;
  final VoidCallback onPressed;

  const _ShapeButton({
    required this.entry,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final button = Tooltip(
      message: entry.name,
      child: Semantics(
        selected: selected,
        child: SizedBox(
          width: 76,
          height: 60,
          child: UiButton(
            onPressed: onPressed,
            semanticsLabel: entry.name,
            selected: selected,
            size: UiButtonSize.md,
            mainAxisSize: MainAxisSize.max,
            variant: selected
                ? UiButtonVariant.primary
                : UiButtonVariant.outline,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomPaint(
                  size: const Size(42, 24),
                  painter: _ShapePreviewPainter(entry, tokens),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? tokens.accentForeground
                        : tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Draggable<DiagramShapeDefinition>(
      data: entry,
      maxSimultaneousDrags: 1,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 76,
          height: 60,
          child: Center(
            child: CustomPaint(
              size: const Size(42, 24),
              painter: _ShapePreviewPainter(entry, tokens),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: button),
      child: button,
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: UiButton(
        onPressed: onPressed,
        semanticsLabel: label,
        size: UiButtonSize.sm,
        variant: selected ? UiButtonVariant.primary : UiButtonVariant.outline,
        child: Text(label),
      ),
    );
  }
}

class _ShapePreviewPainter extends CustomPainter {
  final DiagramShapeDefinition entry;
  final AppTokens tokens;

  const _ShapePreviewPainter(this.entry, this.tokens);

  @override
  void paint(Canvas canvas, Size size) {
    final path = entry.buildPath(size);
    final fill = Paint()
      ..color = tokens.accentSoft
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = tokens.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ShapePreviewPainter oldDelegate) =>
      oldDelegate.entry.id != entry.id ||
      oldDelegate.tokens.accentSoft != tokens.accentSoft ||
      oldDelegate.tokens.textMuted != tokens.textMuted;
}
