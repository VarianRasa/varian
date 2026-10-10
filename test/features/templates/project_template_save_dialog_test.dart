import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/templates/presentation/project_template_save_dialog.dart';
import 'package:varian/features/templates/domain/project_template.dart';
import 'package:varian/features/templates/presentation/project_template_wizard_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('enables save after entering a template name', (tester) async {
    ProjectTemplateSaveRequest? result;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Material(
            child: UiButton(
              onPressed: () async {
                result = await showUiDialog<ProjectTemplateSaveRequest>(
                  context: tester.element(find.byType(UiButton)),
                  builder: (_) => const ProjectTemplateSaveDialog(),
                );
              },
              child: const Text('Open template dialog'),
            ),
          ),
          data: AppTheme.darkTheme,
          materialTheme: AppTheme.darkTheme,
        ),
      ),
    );
    await tester.tap(find.text('Open template dialog'));
    await tester.pumpAndSettle();

    final nameField = find.byWidgetPredicate(
      (widget) => widget is UiTextField && widget.label == 'Template name',
    );
    await tester.enterText(nameField, 'Brand kit');
    await tester.pump();
    await tester.tap(find.text('Save template'));
    await tester.pumpAndSettle();

    expect(result?.name, 'Brand kit');
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets('save actions remain reachable in a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ProjectTemplateSaveRequest? result;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () async {
                result = await showUiDialog<ProjectTemplateSaveRequest>(
                  context: context,
                  builder: (_) => const ProjectTemplateSaveDialog(),
                );
              },
              child: const Text('Open template dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open template dialog'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    expect(dialog.constraints!.maxHeight, 456);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final nameField = find.byWidgetPredicate(
      (widget) => widget is UiTextField && widget.label == 'Template name',
    );
    await tester.enterText(nameField, 'Compact template');
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
    await tester.ensureVisible(find.text('Save template'));
    await tester.tap(find.text('Save template'));
    await tester.pumpAndSettle();

    expect(result?.name, 'Compact template');
    expect(tester.takeException(), isNull);
  });
  testWidgets('template helper copy follows the Material body-small role', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => const ProjectTemplateSaveDialog(),
              ),
              child: const Text('Open template dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open template dialog'));
    await tester.pumpAndSettle();

    final helper = find.text(
      'Selection, hierarchy, and connector relationships are stored with fresh IDs on insertion.',
    );
    final theme = Theme.of(tester.element(helper));
    final tokens = theme.extension<AppTokens>()!;

    expect(
      tester.widget<Text>(helper).style,
      theme.textTheme.bodySmall!.copyWith(color: tokens.textMuted),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('starter wizard helper copy follows the Material body-small role', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => ProjectTemplateWizardDialog(
                  catalog: ProjectTemplateCatalog.withBuiltIns(),
                ),
              ),
              child: const Text('Open template wizard'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open template wizard'));
    await tester.pumpAndSettle();

    final helper = find.text(
      'Start from a built-in, personal, or team template without ID collisions.',
    );
    final theme = Theme.of(tester.element(helper));
    final tokens = theme.extension<AppTokens>()!;

    expect(
      tester.widget<Text>(helper).style,
      theme.textTheme.bodySmall!.copyWith(color: tokens.textMuted),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'starter wizard stays within a compact viewport and returns its request',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      StarterProjectRequest? result;

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () async {
                  result = await showUiDialog<StarterProjectRequest>(
                    context: context,
                    builder: (_) => ProjectTemplateWizardDialog(
                      catalog: ProjectTemplateCatalog.withBuiltIns(),
                      initialProjectName: 'Compact local fixture',
                    ),
                  );
                },
                child: const Text('Open compact starter wizard'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open compact starter wizard'));
      await tester.pumpAndSettle();

      final dialog = tester.getRect(find.byType(Dialog));
      expect(dialog.left, greaterThanOrEqualTo(0));
      expect(dialog.top, greaterThanOrEqualTo(0));
      expect(dialog.right, lessThanOrEqualTo(320));
      expect(dialog.bottom, lessThanOrEqualTo(480));
      expect(find.text('STARTER PROJECT WIZARD'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Create project'));
      await tester.tap(find.text('Create project'));
      await tester.pumpAndSettle();
      expect(result?.projectName, 'Compact local fixture');
      expect(result?.templateId, isNotNull);
      expect(result?.includeSampleAssets, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('saved template metadata follows the Material label-small role', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.utc(2026, 10, 2);
    final catalog = ProjectTemplateCatalog(
      templates: [
        ProjectTemplate(
          id: 'team:brand',
          name: 'Brand kit',
          description: 'Reusable components',
          scope: ProjectTemplateScope.team,
          tags: const ['brand'],
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) =>
                    SavedProjectTemplatePickerDialog(catalog: catalog),
              ),
              child: const Text('Open saved templates'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open saved templates'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final savedTemplate = find.widgetWithText(UiButton, 'Brand kit');
    await tester.ensureVisible(savedTemplate);
    final rowRect = tester.getRect(savedTemplate);
    expect(rowRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(rowRect.right, lessThanOrEqualTo(dialogRect.right));

    final metadata = find.text('team · 0 nodes · brand');
    final theme = Theme.of(tester.element(metadata));
    final tokens = theme.extension<AppTokens>()!;

    expect(
      tester.widget<Text>(metadata).style,
      theme.textTheme.labelSmall!.copyWith(color: tokens.textMuted),
    );
    expect(tester.takeException(), isNull);
  });
}
