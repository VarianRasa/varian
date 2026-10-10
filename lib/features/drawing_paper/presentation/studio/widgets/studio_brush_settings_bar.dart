import 'package:varian/app/responsive.dart';
import 'package:flutter/material.dart';
import 'package:mix/mix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/ruler_guide.dart';
import 'package:varian/features/drawing_paper/domain/models/selection_mask.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

class StudioBrushSettingsBar extends ConsumerWidget {
  final DrawingPaperPayload initialPayload;

  const StudioBrushSettingsBar({super.key, required this.initialPayload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawingStudioProviderFamily(initialPayload));
    final notifier = ref.read(
      drawingStudioProviderFamily(initialPayload).notifier,
    );
    final tokens = context.appTokens;
    final compact = AppResponsive.isCompact(context);

    return MixScope.inherit(
      colors: AppMixTokens.colors(tokens),
      child: SizedBox(
        height: 60,
        child: Box(
          style: BoxStyler()
              .color(AppMixTokens.panelElevated())
              .borderBottom(color: tokens.panelBorder, width: AppBorder.thin),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                SizedBox(
                  width: compact ? 150 : 180,
                  child: UiSelect<StudioBrushCategory>(
                    items: const {
                      'G-Pen (Manga)': StudioBrushCategory.gPen,
                      'Maru-Pen (Fine Line)': StudioBrushCategory.maruPen,
                      'Ink Pen': StudioBrushCategory.inkPen,
                      'Fude Brush': StudioBrushCategory.fudeBrush,
                      'Marker': StudioBrushCategory.marker,
                      'Soft Airbrush': StudioBrushCategory.airbrush,
                      'Rough Pencil': StudioBrushCategory.pencilRough,
                      'Oil Pastel': StudioBrushCategory.oilPastel,
                      'Watercolor Wash': StudioBrushCategory.watercolor,
                      'Screen Tone': StudioBrushCategory.screentoneBrush,
                      'Special Pen': StudioBrushCategory.specialPen,
                      'Hard Eraser': StudioBrushCategory.eraserHard,
                      'Soft Eraser': StudioBrushCategory.eraserSoft,
                      'Vector Eraser': StudioBrushCategory.eraserVector,
                      'Smudge Tool': StudioBrushCategory.smudge,
                      'Blur Tool': StudioBrushCategory.blurTool,
                      'Bucket Fill': StudioBrushCategory.bucketFill,
                      'Lasso Fill': StudioBrushCategory.lassoFill,
                    },
                    value: state.activeBrush,
                    onChanged: (brush) {
                      if (brush != null) notifier.setBrush(brush);
                    },
                  ),
                ),
                _StudioDivider(color: tokens.panelBorder),
                if (state.activeTool == StudioTool.shapes) ...[
                  SizedBox(
                    width: compact ? 128 : 150,
                    child: UiSelect<ShapeKind>(
                      items: const {
                        'Line': ShapeKind.line,
                        'Rectangle': ShapeKind.rectangle,
                        'Rounded Rectangle': ShapeKind.roundedRectangle,
                        'Ellipse': ShapeKind.ellipse,
                        'Polygon': ShapeKind.polygon,
                        'Star': ShapeKind.star,
                        'Arrow': ShapeKind.arrow,
                      },
                      value: state.activeShapeKind,
                      label: 'SHAPE',
                      onChanged: (kind) {
                        if (kind != null) notifier.setShapeKind(kind);
                      },
                    ),
                  ),
                  _StudioDivider(color: tokens.panelBorder),
                ],
                if (state.activeTool == StudioTool.selection) ...[
                  SizedBox(
                    width: compact ? 108 : 125,
                    child: UiSelect<SelectionToolType>(
                      items: const {
                        'Rectangle': SelectionToolType.rectangle,
                        'Ellipse': SelectionToolType.ellipse,
                        'Lasso': SelectionToolType.lasso,
                      },
                      value: state.activeSelectionTool,
                      label: 'SELECT',
                      onChanged: (tool) {
                        if (tool != null) notifier.setSelectionTool(tool);
                      },
                    ),
                  ),
                  SizedBox(
                    width: compact ? 96 : 110,
                    child: UiSelect<SelectionOperation>(
                      items: const {
                        'Replace': SelectionOperation.replace,
                        'Add': SelectionOperation.add,
                        'Subtract': SelectionOperation.subtract,
                        'Intersect': SelectionOperation.intersect,
                      },
                      value: state.activeSelectionOp,
                      label: 'MODE',
                      onChanged: (mode) {
                        if (mode != null) notifier.setSelectionOperation(mode);
                      },
                    ),
                  ),
                  _StudioDivider(color: tokens.panelBorder),
                ],
                if (state.activeTool == StudioTool.itemSelection) ...[
                  UiIconButton(
                    icon: Icons.select_all,
                    tooltip: 'Select all items',
                    onPressed: notifier.selectAllItems,
                  ),
                  UiIconButton(
                    icon: Icons.copy_outlined,
                    tooltip: 'Copy selected items',
                    onPressed: notifier.copySelectedItems,
                  ),
                  UiIconButton(
                    icon: Icons.content_cut_outlined,
                    tooltip: 'Cut selected items',
                    onPressed: notifier.cutSelectedItems,
                  ),
                  UiIconButton(
                    icon: Icons.control_point_duplicate_outlined,
                    tooltip: 'Duplicate selected items',
                    onPressed: notifier.duplicateSelectedItems,
                  ),
                  UiIconButton(
                    icon: Icons.content_paste_outlined,
                    tooltip: 'Paste items',
                    onPressed: state.itemClipboard.isEmpty
                        ? null
                        : notifier.pasteSelectedItems,
                  ),
                  UiIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete selected items',
                    onPressed: notifier.deleteSelectedItems,
                  ),
                  _StudioDivider(color: tokens.panelBorder),
                ],
                if (state.activeTool == StudioTool.ruler) ...[
                  SizedBox(
                    width: compact ? 128 : 150,
                    child: UiSelect<RulerType>(
                      items: const {
                        'Straight': RulerType.straight,
                        'Circular': RulerType.circular,
                        'Radial Focus': RulerType.radialFocus,
                        'Symmetry': RulerType.symmetryMirror,
                        '1-Point Perspective': RulerType.perspective1Point,
                        '2-Point Perspective': RulerType.perspective2Point,
                        '3-Point Perspective': RulerType.perspective3Point,
                      },
                      value: state.activeRulerType,
                      label: 'RULER',
                      onChanged: (type) {
                        if (type != null) notifier.setRulerType(type);
                      },
                    ),
                  ),
                  _StudioDivider(color: tokens.panelBorder),
                ],
                if (state.activeTool == StudioTool.speechBalloon) ...[
                  SizedBox(
                    width: compact ? 116 : 135,
                    child: UiSelect<SpeechBalloonType>(
                      items: const {
                        'Speech Oval': SpeechBalloonType.speechOval,
                        'Thought Cloud': SpeechBalloonType.thoughtCloud,
                        'Shout': SpeechBalloonType.shoutExplosion,
                        'Whisper': SpeechBalloonType.squareWhisper,
                      },
                      value: state.activeBalloonType,
                      label: 'BALLOON',
                      onChanged: (type) {
                        if (type != null) notifier.setBalloonType(type);
                      },
                    ),
                  ),
                  _StudioDivider(color: tokens.panelBorder),
                ],
                _StudioSlider(
                  label: 'Size',
                  valueLabel: '${state.brushSize.toInt()}px',
                  value: state.brushSize,
                  min: 1,
                  max: 120,
                  color: tokens.accent,
                  width: compact ? 84 : 100,
                  onChanged: notifier.setBrushSize,
                ),
                _StudioSlider(
                  label: 'Opacity',
                  valueLabel: '${(state.brushOpacity * 100).toInt()}%',
                  value: state.brushOpacity,
                  min: 0.05,
                  max: 1,
                  color: tokens.accent,
                  width: compact ? 68 : 80,
                  onChanged: notifier.setBrushOpacity,
                ),
                _StudioSlider(
                  label: 'Stabilizer',
                  valueLabel: '${(state.stabilizer * 100).toInt()}%',
                  value: state.stabilizer,
                  min: 0,
                  max: 1,
                  color: tokens.info,
                  width: compact ? 68 : 80,
                  onChanged: notifier.setStabilizer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudioDivider extends StatelessWidget {
  final Color color;

  const _StudioDivider({required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm + AppSpacing.xxs,
    ),
    child: SizedBox(
      height: AppSpacing.xl,
      child: VerticalDivider(color: color, thickness: AppBorder.thin),
    ),
  );
}

class _StudioSlider extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final Color color;
  final double width;
  final ValueChanged<double> onChanged;

  const _StudioSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.width,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label:',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
          ),
          SizedBox(
            width: width,
            child: UiSlider(
              label: label,
              semanticValueFormatterCallback: (_) => '$label $valueLabel',
              value: max == min
                  ? 0.0
                  : ((value.clamp(min, max) - min) / (max - min)),
              onChanged: (next) => onChanged(min + next * (max - min)),
            ),
          ),
          Text(
            valueLabel,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
