import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../data/diagram_templates.dart';

class TemplatePickerDialog extends StatelessWidget {
  final ValueChanged<DiagramTemplateMetadata> onSelected;
  final VoidCallback? onOpenWizard;

  const TemplatePickerDialog({
    required this.onSelected,
    this.onOpenWizard,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final dialogMaxHeight = AppResponsive.dialogHeight(context, preferred: 720);
    final templateGridMaxHeight = (dialogMaxHeight - 180).clamp(96.0, 460.0);
    final templates = DiagramTemplates.listTemplates()
        .where((template) => !template.isKit)
        .toList(growable: false);
    return UiDialog(
      semanticsLabel: 'Choose starter template',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 760,
        maxHeight: 720,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('STARTER TEMPLATES', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Choose a structured starting point. Every insertion receives fresh IDs.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: templateGridMaxHeight),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 480 ? 2 : 1;
                    return GridView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                      ),
                      itemCount: templates.length,
                      itemBuilder: (_, index) {
                        final template = templates[index];
                        return _TemplateCard(
                          template: template,
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            onSelected(template);
                          },
                        );
                      },
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
                  if (onOpenWizard != null)
                    UiButton(
                      variant: UiButtonVariant.ghost,
                      prefix: const Icon(Icons.tune_outlined, size: 16),
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        onOpenWizard!();
                      },
                      child: const Text('Advanced wizard'),
                    ),
                  if (onOpenWizard != null)
                    const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
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

class _TemplateCard extends StatelessWidget {
  final DiagramTemplateMetadata template;
  final VoidCallback onPressed;

  const _TemplateCard({required this.template, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final borderRadius = BorderRadius.circular(tokens.controlRadius);
    return Semantics(
      button: true,
      label: 'Use ${template.name} template',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius,
          child: Ink(
            key: const ValueKey('template-picker-card-surface'),
            padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xxs),
            decoration: BoxDecoration(
              color: tokens.panel,
              borderRadius: borderRadius,
              border: Border.all(
                color: tokens.panelBorder,
                width: AppBorder.thin,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.dashboard_customize_outlined, color: tokens.accent),
                const SizedBox(height: AppSpacing.md),
                Text(
                  template.name,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Text(
                  template.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
