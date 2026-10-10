import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

class StudioCanvasControlsDialog extends ConsumerWidget {
  final DrawingPaperPayload initialPayload;

  const StudioCanvasControlsDialog({super.key, required this.initialPayload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawingStudioProviderFamily(initialPayload));
    final notifier = ref.read(
      drawingStudioProviderFamily(initialPayload).notifier,
    );
    final tokens = context.appTokens;

    final maxHeight = AppResponsive.dialogHeight(context, preferred: 520);
    return UiDialog(
      semanticsLabel: 'Canvas and view controls',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 560,
        maxHeight: maxHeight,
      ),
      builder: (context, style) => SizedBox(
        width: AppResponsive.dialogWidth(context, preferred: 560),
        height: maxHeight,
        child: SingleChildScrollView(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, color: tokens.accent, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Canvas & View Controls',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close canvas controls',
                    size: UiButtonSize.sm,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Divider(color: tokens.panelBorder, thickness: AppBorder.thin),
              UiSwitch(
                label: const Text('Show Grid (50px)'),
                semanticsLabel: 'Show grid',
                value: state.payload.showGrid,
                onChange: (_) => notifier.toggleGrid(),
              ),
              UiSwitch(
                label: const Text('Pixel Grid (Zoom In)'),
                semanticsLabel: 'Show pixel grid',
                value: state.payload.showPixelGrid,
                onChange: (_) => notifier.togglePixelGrid(),
              ),
              UiSwitch(
                label: const Text('Manga Safe Bleed Margin'),
                semanticsLabel: 'Show manga safe bleed margin',
                value: state.payload.showMangaBleed,
                onChange: (_) => notifier.toggleMangaBleed(),
              ),
              UiSwitch(
                label: const Text('Reference Window (PiP)'),
                semanticsLabel: 'Show reference window',
                value: state.payload.referenceConfig.visible,
                onChange: (value) => notifier.updateReferenceConfig(
                  state.payload.referenceConfig.copyWith(visible: value),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Canvas Rotation',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                  ),
                  Text(
                    '${(state.viewRotation * 180 / 3.14159265).toInt()}°',
                    style: TextStyle(
                      color: tokens.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              UiSlider(
                value: ((state.viewRotation + 3.14159265) / (2 * 3.14159265))
                    .clamp(0.0, 1.0),
                onChanged: (value) => notifier.setViewRotation(
                  -3.14159265 + value * (2 * 3.14159265),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
