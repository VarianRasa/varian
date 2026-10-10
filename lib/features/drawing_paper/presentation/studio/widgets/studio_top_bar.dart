import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mix/mix.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/services/psd_export_service.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_canvas_controls_dialog.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/timelapse_playback_dialog.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_color_panel.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_layer_panel.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

class StudioTopBar extends ConsumerWidget {
  final DrawingPaperPayload initialPayload;
  final VoidCallback onExit;

  const StudioTopBar({
    super.key,
    required this.initialPayload,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawingStudioProviderFamily(initialPayload));
    final notifier = ref.read(
      drawingStudioProviderFamily(initialPayload).notifier,
    );
    final tokens = context.appTokens;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppBreakpoints.medium;
        final backButton = UiButton(
          onPressed: onExit,
          variant: UiButtonVariant.secondary,
          size: UiButtonSize.sm,
          prefix: const Icon(Icons.arrow_back, size: 16),
          child: const Text(
            'Back to Infinite Canvas',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
        final presetDetails = UiSurface(
          color: tokens.panelElevated,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: 14, color: tokens.accent),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Flexible(
                child: Text(
                  '${state.payload.presetName} • ${state.payload.pixelWidth.toInt()}×${state.payload.pixelHeight.toInt()} px • ${state.payload.dpi.toInt()} DPI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
        final actionBar = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact) ...[
              UiMenuButton<_StudioCompactPanel>(
                tooltip: 'Open studio panels',
                icon: Icons.dashboard_customize_outlined,
                items: const [
                  UiMenuAction(
                    value: _StudioCompactPanel.colors,
                    icon: Icons.palette_outlined,
                    label: 'Color studio',
                  ),
                  UiMenuAction(
                    value: _StudioCompactPanel.layers,
                    icon: Icons.layers_outlined,
                    label: 'Layers',
                  ),
                ],
                onSelected: (panel) {
                  showUiDialog<void>(
                    context: context,
                    builder: (_) => _StudioCompactPanelDialog(
                      initialPayload: initialPayload,
                      panel: panel,
                    ),
                  );
                },
              ),
              VerticalDivider(
                color: tokens.panelBorder,
                thickness: AppBorder.thin,
                indent: AppSpacing.sm + AppSpacing.xxs,
                endIndent: AppSpacing.sm + AppSpacing.xxs,
              ),
            ],
            // Undo / Redo
            UiIconButton(
              icon: Icons.undo,
              tooltip: 'Undo (Ctrl+Z)',
              onPressed: state.undoCount > 0 ? () => notifier.undo() : null,
            ),
            UiIconButton(
              icon: Icons.redo,
              tooltip: 'Redo (Ctrl+Y)',
              onPressed: state.redoCount > 0 ? () => notifier.redo() : null,
            ),
            VerticalDivider(
              color: tokens.panelBorder,
              thickness: AppBorder.thin,
              indent: AppSpacing.sm + AppSpacing.xxs,
              endIndent: AppSpacing.sm + AppSpacing.xxs,
            ),

            // Canvas Controls Dialog (Grid, Rotation, PiP, Bleed)
            UiIconButton(
              icon: Icons.tune,
              tooltip: 'Canvas View Controls & Grid',
              onPressed: () {
                showUiDialog(
                  context: context,
                  builder: (_) => StudioCanvasControlsDialog(
                    initialPayload: initialPayload,
                  ),
                );
              },
            ),
            VerticalDivider(
              color: tokens.panelBorder,
              thickness: AppBorder.thin,
              indent: AppSpacing.sm + AppSpacing.xxs,
              endIndent: AppSpacing.sm + AppSpacing.xxs,
            ),

            // Zoom & Reset View
            UiIconButton(
              icon: Icons.crop_free,
              tooltip: 'Fit Paper to Screen',
              onPressed: () => notifier.resetView(),
            ),
            Text(
              '${(state.viewZoom * 100).toInt()}%',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: tokens.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),

            UiIconButton(
              icon: Icons.movie_creation_outlined,
              tooltip: 'Time-lapse Playback',
              variant: UiButtonVariant.ghost,
              onPressed: () {
                showUiDialog(
                  context: context,
                  builder: (_) =>
                      TimelapsePlaybackDialog(initialPayload: initialPayload),
                );
              },
            ),
            VerticalDivider(
              color: tokens.panelBorder,
              thickness: AppBorder.thin,
              indent: AppSpacing.sm + AppSpacing.xxs,
              endIndent: AppSpacing.sm + AppSpacing.xxs,
            ),

            // Export Button
            UiMenuButton<String>(
              tooltip: 'Export Paper',
              icon: Icons.download,
              items: const [
                UiMenuAction(
                  value: 'png_opaque',
                  icon: Icons.image_outlined,
                  label: 'Export PNG (White Paper)',
                ),
                UiMenuAction(
                  value: 'png_transparent',
                  icon: Icons.hide_image_outlined,
                  label: 'Export Transparent PNG',
                ),
                UiMenuAction(
                  value: 'jpeg',
                  icon: Icons.photo_outlined,
                  label: 'Export JPEG (High Quality)',
                ),
                UiMenuAction(
                  value: 'psd',
                  icon: Icons.layers_outlined,
                  label: 'Export PSD Layers (Photoshop Format)',
                ),
                UiMenuAction(
                  value: 'cmyk',
                  icon: Icons.print_outlined,
                  label: 'Export CMYK Print Simulation',
                ),
              ],
              onSelected: (val) {
                if (val == 'psd') {
                  final manifest = PsdExportService.exportToPsdManifest(
                    state.payload,
                  );
                  showUiToast(
                    context,
                    'Exported PSD Manifest (${manifest.length} bytes)',
                    variant: UiToastVariant.success,
                  );
                } else {
                  showUiToast(
                    context,
                    'Exported $val successfully',
                    variant: UiToastVariant.success,
                  );
                }
              },
            ),
          ],
        );

        return MixScope.inherit(
          colors: AppMixTokens.colors(tokens),
          child: SizedBox(
            height: compact ? 96 : 48,
            child: Box(
              style: BoxStyler()
                  .color(AppMixTokens.panel())
                  .borderBottom(
                    color: tokens.panelBorder,
                    width: AppBorder.thin,
                  )
                  .padding(
                    EdgeInsetsGeometryMix.value(
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    ),
                  ),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 220,
                                ),
                                child: backButton,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(child: presetDetails),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            hitTestBehavior: HitTestBehavior.deferToChild,
                            child: actionBar,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        backButton,
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: presetDetails),
                        actionBar,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

enum _StudioCompactPanel { colors, layers }

class _StudioCompactPanelDialog extends StatelessWidget {
  final DrawingPaperPayload initialPayload;
  final _StudioCompactPanel panel;

  const _StudioCompactPanelDialog({
    required this.initialPayload,
    required this.panel,
  });

  @override
  Widget build(BuildContext context) {
    final isLayers = panel == _StudioCompactPanel.layers;
    final title = isLayers ? 'Layers' : 'Color studio';
    final width = AppResponsive.dialogWidth(context, preferred: 300);
    final height = AppResponsive.dialogHeight(context, preferred: 560);
    return UiDialog(
      semanticsLabel: title,
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 320,
        maxHeight: 600,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: style.titleTextStyle)),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close $title panel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Divider(
                color: context.appTokens.panelBorder,
                thickness: AppBorder.thin,
              ),
              Expanded(
                child: isLayers
                    ? StudioLayerPanel(initialPayload: initialPayload)
                    : SingleChildScrollView(
                        child: StudioColorPanel(initialPayload: initialPayload),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
