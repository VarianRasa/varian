import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../domain/project_template.dart';

class ProjectTemplateWizardDialog extends StatefulWidget {
  final ProjectTemplateCatalog catalog;
  final String initialProjectName;

  const ProjectTemplateWizardDialog({
    super.key,
    required this.catalog,
    this.initialProjectName = 'Untitled project',
  });

  @override
  State<ProjectTemplateWizardDialog> createState() =>
      _ProjectTemplateWizardDialogState();
}

class _ProjectTemplateWizardDialogState
    extends State<ProjectTemplateWizardDialog> {
  late final TextEditingController _nameController;
  late String? _templateId;
  bool _includeSampleAssets = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialProjectName);
    _templateId = widget.catalog.templates
        .where((template) => template.diagramTemplateId != null)
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final templates = widget.catalog.templates
        .where((template) => template.diagramTemplateId != null)
        .toList(growable: false);
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 520);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 560);
    return UiDialog(
      semanticsLabel: 'Starter project wizard',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('STARTER PROJECT WIZARD', style: style.titleTextStyle),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Start from a built-in, personal, or team template without ID collisions.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                UiTextField(
                  controller: _nameController,
                  autofocus: true,
                  label: 'Project name',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),
                UiSelect<String>(
                  label: 'Template',
                  hint: 'Choose a starter template',
                  value: _templateId,
                  items: {
                    for (final template in templates)
                      '${template.name} (${template.scope.name})': template.id,
                  },
                  onChanged: (value) => setState(() => _templateId = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                UiSwitch(
                  label: const Text('Include sample assets'),
                  description: const Text(
                    'Keep the project lightweight by default.',
                  ),
                  semanticsLabel: 'Include sample assets',
                  value: _includeSampleAssets,
                  onChange: (value) =>
                      setState(() => _includeSampleAssets = value),
                ),
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
                      onPressed: _nameController.text.trim().isEmpty
                          ? null
                          : () => Navigator.of(dialogContext).pop(
                              StarterProjectRequest(
                                projectName: _nameController.text.trim(),
                                templateId: _templateId,
                                includeSampleAssets: _includeSampleAssets,
                              ),
                            ),
                      prefix: const Icon(
                        Icons.rocket_launch_outlined,
                        size: 16,
                      ),
                      child: const Text('Create project'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
