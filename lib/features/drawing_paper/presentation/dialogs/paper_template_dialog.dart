import 'package:flutter/material.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';

class PaperTemplateDialog extends StatefulWidget {
  final Function(DrawingPaperPayload payload) onSelected;

  const PaperTemplateDialog({super.key, required this.onSelected});

  @override
  State<PaperTemplateDialog> createState() => _PaperTemplateDialogState();
}

class _PaperTemplateDialogState extends State<PaperTemplateDialog> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final dialogWidth = AppResponsive.dialogWidth(context, preferred: 600);
    final dialogHeight = AppResponsive.dialogHeight(context, preferred: 460);

    return UiDialog(
      semanticsLabel: 'New drawing paper',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 600,
        maxHeight: 460,
      ),
      builder: (context, style) => SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.note_add_outlined, color: tokens.accent, size: 22),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      'New Drawing Paper',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close paper template dialog',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Choose a standard physical paper preset or digital art canvas resolution:',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: dialogWidth < 520 ? 420 : 280,
                    childAspectRatio: 2.0,
                    crossAxisSpacing: AppSpacing.sm + AppSpacing.xxs,
                    mainAxisSpacing: AppSpacing.sm + AppSpacing.xxs,
                  ),
                  itemCount: PaperPresetSpec.presets.length,
                  itemBuilder: (context, index) {
                    final preset = PaperPresetSpec.presets[index];
                    final isSelected = index == _selectedIndex;
                    return Semantics(
                      button: true,
                      selected: isSelected,
                      label: '${preset.name} paper preset',
                      child: UiButton(
                        onPressed: () => setState(() => _selectedIndex = index),
                        variant: isSelected
                            ? UiButtonVariant.primary
                            : UiButtonVariant.outline,
                        mainAxisSize: MainAxisSize.max,
                        child: Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.description_outlined,
                                    size: 16,
                                    color: isSelected
                                        ? tokens.accentForeground
                                        : tokens.textMuted,
                                  ),
                                  const SizedBox(
                                    width: AppSpacing.xs + AppSpacing.xxs,
                                  ),
                                  Flexible(
                                    child: Text(
                                      preset.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall!
                                          .copyWith(
                                            color: isSelected
                                                ? tokens.accentForeground
                                                : tokens.text,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: AppSpacing.xs + AppSpacing.xxs,
                              ),
                              Text(
                                '${preset.pixelWidth} × ${preset.pixelHeight} px • ${preset.defaultDpi.toInt()} DPI',
                                style: Theme.of(context).textTheme.labelSmall!
                                    .copyWith(
                                      color: isSelected
                                          ? tokens.accentForeground.withValues(
                                              alpha: 0.72,
                                            )
                                          : tokens.info,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                preset.description,
                                style: Theme.of(context).textTheme.bodySmall!
                                    .copyWith(
                                      color: isSelected
                                          ? tokens.accentForeground.withValues(
                                              alpha: 0.72,
                                            )
                                          : tokens.textMuted,
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
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
                      final spec = PaperPresetSpec.presets[_selectedIndex];
                      widget.onSelected(
                        DrawingPaperPayload(
                          presetName: spec.name,
                          dpi: spec.defaultDpi,
                          pixelWidth: spec.pixelWidth.toDouble(),
                          pixelHeight: spec.pixelHeight.toDouble(),
                          paperColor: Colors.white,
                        ),
                      );
                      Navigator.of(context).pop();
                    },
                    prefix: const Icon(Icons.add),
                    child: const Text('Create Paper on Canvas'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
