import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/ai/domain/ai_workflow_contract.dart';
import 'package:varian/features/ai/presentation/ai_workflow_dialogs.dart';

import '../../test_app.dart';

void main() {
  testWidgets(
    'AI output review fits a compact viewport and returns selection',
    (tester) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const initial = AIVariantSet(
        id: 'local-variants',
        variants: [
          AIOutputVariant(id: 'a', index: 0),
          AIOutputVariant(id: 'b', index: 1),
          AIOutputVariant(id: 'c', index: 2),
        ],
      );
      AIVariantSet? result;

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () => showUiDialog<AIVariantSet>(
                  context: context,
                  builder: (_) => AIWorkflowReviewDialog(
                    initialVariants: initial,
                    providerHealth: AIProviderHealth(
                      provider: 'local fixture',
                      status: AIProviderStatus.healthy,
                      checkedAt: DateTime.utc(2026, 10, 3),
                    ),
                    quota: const AIQuotaSnapshot(
                      scope: 'local',
                      used: 1,
                      limit: 4,
                      unit: 'credits',
                    ),
                    provenance: const AIProvenanceNotice(
                      provider: 'local fixture',
                      license: 'CC-BY',
                    ),
                  ),
                ).then((value) => result = value),
                child: const Text('Review local variants'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review local variants'));
      await tester.pumpAndSettle();

      expect(find.text('AI OUTPUT REVIEW'), findsOneWidget);
      expect(find.text('Output provenance'), findsOneWidget);
      expect(find.text('3 of 2 compare slots used'), findsNothing);
      expect(find.text('0 of 2 compare slots used'), findsOneWidget);
      expect(find.text('Use comparison'), findsOneWidget);
      expect(
        tester.getSize(find.byType(Dialog).last).height,
        lessThanOrEqualTo(480),
      );
      expect(tester.takeException(), isNull);
      final dialogSurface = find.descendant(
        of: find.byType(Dialog).last,
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.shape != null,
        ),
      );
      final dialogBounds = tester.getRect(dialogSurface);
      expect(dialogBounds.left, greaterThanOrEqualTo(0));
      expect(dialogBounds.top, greaterThanOrEqualTo(0));
      expect(dialogBounds.right, lessThanOrEqualTo(360));
      expect(dialogBounds.bottom, lessThanOrEqualTo(480));
      for (var index = 0; index < initial.variants.length; index++) {
        final title = find.text('Variant ${index + 1}');
        await tester.ensureVisible(title);
        await tester.pumpAndSettle();
        final cardFinder = find.ancestor(
          of: title,
          matching: find.byType(UiSurface),
        );
        final cardBounds = tester.getRect(cardFinder.first);
        expect(cardBounds.left, greaterThanOrEqualTo(dialogBounds.left));
        expect(cardBounds.right, lessThanOrEqualTo(dialogBounds.right));
        expect(cardBounds.top, greaterThanOrEqualTo(dialogBounds.top));
        expect(cardBounds.bottom, lessThanOrEqualTo(dialogBounds.bottom));
        final compareAction = find.descendant(
          of: cardFinder.first,
          matching: find.text('Compare'),
        );
        final compareBounds = tester.getRect(compareAction);
        expect(compareBounds.left, greaterThanOrEqualTo(cardBounds.left));
        expect(compareBounds.right, lessThanOrEqualTo(cardBounds.right));
        expect(compareBounds.top, greaterThanOrEqualTo(cardBounds.top));
        expect(compareBounds.bottom, lessThanOrEqualTo(cardBounds.bottom));
      }
      for (final action in [find.text('Close'), find.text('Use comparison')]) {
        final bounds = tester.getRect(action);
        expect(bounds.left, greaterThanOrEqualTo(dialogBounds.left));
        expect(bounds.right, lessThanOrEqualTo(dialogBounds.right));
        expect(bounds.bottom, lessThanOrEqualTo(dialogBounds.bottom));
      }

      final compareButtons = find.text('Compare');
      await tester.ensureVisible(compareButtons.first);
      await tester.tap(compareButtons.first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Compare').first);
      await tester.tap(find.text('Compare').first);
      await tester.pumpAndSettle();

      expect(find.text('2 of 2 compare slots used'), findsOneWidget);
      await tester.ensureVisible(find.text('Use comparison'));
      await tester.tap(find.text('Use comparison'));
      await tester.pumpAndSettle();

      expect(result?.compareSelection.map((variant) => variant.id), ['a', 'b']);
      expect(tester.takeException(), isNull);
    },
  );
}
