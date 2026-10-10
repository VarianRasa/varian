import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/features/templates/data/diagram_templates.dart';
import 'package:varian/features/templates/presentation/template_picker_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('renders starter templates without material or overflow errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: testApp(const _DialogLauncher())),
    );
    await tester.tap(find.text('Open template picker'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('STARTER TEMPLATES'), findsOneWidget);
    expect(find.text('Flowchart'), findsOneWidget);
    final cards = tester.widgetList<Ink>(
      find.byKey(const ValueKey('template-picker-card-surface')),
    );
    expect(cards, isNotEmpty);
    for (final card in cards) {
      final cardBorder = (card.decoration! as BoxDecoration).border! as Border;
      expect(cardBorder.top.width, AppBorder.thin);
      expect(cardBorder.top.color, AppTokens.dark.panelBorder);
    }

    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(390));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(844));
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 1);
    final firstCard = tester.getRect(
      find.byKey(const ValueKey('template-picker-card-surface')).first,
    );
    expect(firstCard.left, greaterThanOrEqualTo(dialogRect.left));
    expect(firstCard.right, lessThanOrEqualTo(dialogRect.right));
    expect(firstCard.top, greaterThanOrEqualTo(dialogRect.top));
    expect(firstCard.bottom, lessThanOrEqualTo(dialogRect.bottom));
  });
  testWidgets('template cards follow the two-column grid at wide width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: testApp(const _DialogLauncher())),
    );
    await tester.tap(find.text('Open template picker'));
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(find.byType(Dialog));
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    final cardFinder = find.byKey(
      const ValueKey('template-picker-card-surface'),
    );
    final cardRects = List.generate(
      4,
      (index) => tester.getRect(cardFinder.at(index)),
    );
    for (final rect in cardRects) {
      expect(rect.left, greaterThanOrEqualTo(dialogRect.left));
      expect(rect.right, lessThanOrEqualTo(dialogRect.right));
      expect(rect.top, greaterThanOrEqualTo(dialogRect.top));
      expect(rect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    }
    expect(cardRects[1].top, cardRects[0].top);
    expect(cardRects[1].left - cardRects[0].right, AppSpacing.md);
    expect(cardRects[3].top, greaterThan(cardRects[1].top));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'selecting a template returns its metadata and closes the dialog',
    (tester) async {
      DiagramTemplateMetadata? selected;
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            _DialogLauncher(
              onSelected: (template) => selected = template,
              onOpenWizard: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open template picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flowchart'));
      await tester.pumpAndSettle();

      expect(selected?.id, 'flowchart');
      expect(selected?.name, 'Flowchart');
      expect(find.text('STARTER TEMPLATES'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('advanced wizard closes the picker and calls its callback', (
    tester,
  ) async {
    var wizardCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            onSelected: (_) {},
            onOpenWizard: () => wizardCalls++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open template picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced wizard'));
    await tester.pumpAndSettle();

    expect(wizardCalls, 1);
    expect(find.text('STARTER TEMPLATES'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _DialogLauncher extends StatelessWidget {
  const _DialogLauncher({this.onSelected = _ignoreTemplate, this.onOpenWizard});

  final ValueChanged<DiagramTemplateMetadata> onSelected;
  final VoidCallback? onOpenWizard;

  static void _ignoreTemplate(DiagramTemplateMetadata template) {}

  @override
  Widget build(BuildContext context) => UiButton(
    onPressed: () => showUiDialog<void>(
      context: context,
      builder: (_) => TemplatePickerDialog(
        onSelected: onSelected,
        onOpenWizard: onOpenWizard,
      ),
    ),
    child: const Text('Open template picker'),
  );
}
