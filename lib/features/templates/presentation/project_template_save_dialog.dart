import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../domain/project_template.dart';

class ProjectTemplateSaveRequest {
  final String name;
  final String description;
  final List<String> tags;
  final ProjectTemplateScope scope;

  const ProjectTemplateSaveRequest({
    required this.name,
    required this.description,
    required this.tags,
    required this.scope,
  });
}

class ProjectTemplateSaveDialog extends StatefulWidget {
  const ProjectTemplateSaveDialog({super.key});

  @override
  State<ProjectTemplateSaveDialog> createState() =>
      _ProjectTemplateSaveDialogState();
}

class _ProjectTemplateSaveDialogState extends State<ProjectTemplateSaveDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;
  ProjectTemplateScope _scope = ProjectTemplateScope.personal;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _tagsController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _save(BuildContext dialogContext) {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(dialogContext).pop(
      ProjectTemplateSaveRequest(
        name: name,
        description: _descriptionController.text.trim(),
        tags: _tagsController.text
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList(growable: false),
        scope: _scope,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return UiDialog(
      semanticsLabel: 'Save selection as template',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 500,
        maxHeight: 640,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('SAVE SELECTION AS TEMPLATE', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Selection, hierarchy, and connector relationships are stored with fresh IDs on insertion.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              UiTextField(
                controller: _nameController,
                label: 'Template name',
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              UiTextField(
                controller: _descriptionController,
                label: 'Description',
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              UiTextField(
                controller: _tagsController,
                label: 'Tags',
                hint: 'dashboard, onboarding, brand',
              ),
              const SizedBox(height: AppSpacing.md),
              UiSelect<ProjectTemplateScope>(
                items: const {
                  'Personal': ProjectTemplateScope.personal,
                  'Team workspace': ProjectTemplateScope.team,
                },
                value: _scope,
                label: 'Visibility',
                onChanged: (value) {
                  if (value != null) setState(() => _scope = value);
                },
              ),
              const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
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
                        : () => _save(dialogContext),
                    prefix: const Icon(Icons.save_outlined, size: 16),
                    child: const Text('Save template'),
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

class SavedProjectTemplatePickerDialog extends StatelessWidget {
  final ProjectTemplateCatalog catalog;

  const SavedProjectTemplatePickerDialog({required this.catalog, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final templates = catalog.templates
        .where((template) => !template.isBuiltIn)
        .toList(growable: false);
    return UiDialog(
      semanticsLabel: 'Insert saved template',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 620,
        maxHeight: 620,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('INSERT SAVED TEMPLATE', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Personal and team templates are inserted as a new, collision-free selection.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg - AppSpacing.xxs),
              if (templates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xl + AppSpacing.xs,
                  ),
                  child: Text(
                    'No saved templates yet. Select canvas nodes and use Save Selection as Template.',
                    textAlign: TextAlign.center,
                    style: style.bodyTextStyle.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: templates.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, index) {
                      final template = templates[index];
                      return UiButton(
                        mainAxisSize: MainAxisSize.max,
                        variant: UiButtonVariant.outline,
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(template),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.dashboard_customize_outlined,
                              size: 18,
                            ),
                            const SizedBox(
                              width: AppSpacing.sm + AppSpacing.xxs,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(template.name),
                                  Text(
                                    '${template.scope.name} · ${template.selectionNodes.length} nodes · ${template.tags.join(', ')}',
                                    style: Theme.of(dialogContext)
                                        .textTheme
                                        .labelSmall!
                                        .copyWith(color: tokens.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: AppSpacing.lg - AppSpacing.xxs),
              UiButton(
                variant: UiButtonVariant.ghost,
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
