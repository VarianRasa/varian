import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/features/onboarding/state/onboarding_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/features/onboarding/presentation/onboarding_dialog.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';

import '../../test_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'onboarding can be skipped and resumed without blocking local state',
    () async {
      final first = OnboardingNotifier();
      await first.load();
      expect(first.state.shouldShow, isTrue);

      await first.skip();
      expect(first.state.shouldShow, isFalse);

      final restored = OnboardingNotifier();
      await restored.load();
      expect(restored.state.shouldShow, isFalse);

      await restored.resume();
      expect(restored.state.shouldShow, isTrue);
      expect(restored.state.step, 0);

      first.dispose();
      restored.dispose();
    },
  );
  testWidgets('onboarding body scrolls in a short viewport', (tester) async {
    tester.view.physicalSize = const Size(800, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(onboardingProvider.notifier);
    await notifier.load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showOnboardingDialog(context),
              child: const Text('Open onboarding'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open onboarding'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('onboarding-dialog')), findsOneWidget);
    expect(find.text('Work locally first'), findsOneWidget);
    expect(
      find.text(
        'Your local workspace stays available while you decide when to connect the cloud.',
      ),
      findsOneWidget,
    );
    final scrollableFinder = find.descendant(
      of: find.byKey(const ValueKey('onboarding-dialog')),
      matching: find.byType(SingleChildScrollView),
    );
    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    final dialogContext = tester.element(find.byType(UiDialog));
    expect(
      dialog.constraints!.maxWidth,
      AppResponsive.dialogWidth(dialogContext, preferred: 520),
    );
    expect(
      dialog.constraints!.maxHeight,
      AppResponsive.dialogHeight(dialogContext, preferred: 560),
    );
    final dialogBounds = tester.getRect(find.byType(Dialog));
    expect(dialogBounds.left, greaterThanOrEqualTo(0));
    expect(dialogBounds.top, greaterThanOrEqualTo(0));
    expect(dialogBounds.right, lessThanOrEqualTo(800));
    expect(dialogBounds.bottom, lessThanOrEqualTo(240));
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('onboarding-dialog')),
      matching: find.byType(SingleChildScrollView),
    );
    final contentPadding = tester.widget<Padding>(
      find.ancestor(of: scrollable, matching: find.byType(Padding)).first,
    );
    expect(contentPadding.padding, const EdgeInsets.all(AppSpacing.page));
    expect(scrollableFinder, findsOneWidget);
    await tester.drag(scrollableFinder, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('NEXT'), findsOneWidget);
    expect(tester.getBottomRight(find.text('NEXT')).dy, lessThanOrEqualTo(240));
  });
  testWidgets('onboarding dialog stays within compact viewport bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(onboardingProvider.notifier).load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showOnboardingDialog(context),
              child: const Text('Open onboarding'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open onboarding'));
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final nextButton = find.byKey(const ValueKey('onboarding-next'));
    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    expect(dialog.constraints!.maxHeight, 456);
    final compactContentPadding = tester.widget<Padding>(
      find
          .ancestor(
            of: find.descendant(
              of: find.byKey(const ValueKey('onboarding-dialog')),
              matching: find.byType(SingleChildScrollView),
            ),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(compactContentPadding.padding, const EdgeInsets.all(AppSpacing.md));
    final card = tester.widget<UiSurface>(find.byType(UiSurface));
    expect(card.padding, const EdgeInsets.all(AppSpacing.md));
    final tokens = Theme.of(
      tester.element(find.byType(UiSurface)),
    ).extension<AppTokens>()!;
    expect(card.color, tokens.panelElevated);
    final progressIndicators = tester.widgetList<UiLinearProgressIndicator>(
      find.byType(UiLinearProgressIndicator),
    );
    expect(progressIndicators.map((indicator) => indicator.height), [3, 3, 3]);
    expect(progressIndicators.map((indicator) => indicator.value), [1, 0, 0]);
    await tester.tap(nextButton);
    await tester.pumpAndSettle();
    expect(find.text('Create your next canvas'), findsOneWidget);
    final secondProgressValues = tester.widgetList<UiLinearProgressIndicator>(
      find.byType(UiLinearProgressIndicator),
    );
    expect(secondProgressValues.map((indicator) => indicator.value), [1, 1, 0]);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(nextButton);
    expect(tester.getRect(nextButton).bottom, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });
}
