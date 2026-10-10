import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/ai/domain/ai_governance.dart';
import 'package:varian/features/ai/presentation/ai_governance_policy_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('policy headings and empty state use Material body roles', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const _DialogLauncher())),
    );
    await tester.tap(find.text('Open AI governance policy'));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.text('Quota and rate limits')));
    final tokens = theme.extension<AppTokens>()!;
    for (final label in [
      'Quota and rate limits',
      'Provider allowlist',
      'Retention and provenance',
    ]) {
      expect(
        tester.widget<Text>(find.text(label)).style,
        theme.textTheme.bodyMedium!.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final emptyState = find.text('No explicit provider policies configured.');
    expect(
      tester.widget<Text>(emptyState).style,
      theme.textTheme.bodyMedium!.copyWith(color: tokens.textMuted),
    );
    expect(tester.takeException(), isNull);
    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers, hasLength(2));
    expect(dividers[1].height, AppSpacing.xl + AppSpacing.xs);
  });

  testWidgets('provider heading and validation error use Material body role', (
    tester,
  ) async {
    var saveCalled = false;
    final policy = const AIGovernancePolicy(
      quotaCredits: -1,
      providers: {
        'local-provider': AIProviderPolicy(provider: 'local-provider'),
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            policy: policy,
            onSave: (_) async {
              saveCalled = true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open AI governance policy'));
    await tester.pumpAndSettle();

    final provider = find.text('local-provider');
    final theme = Theme.of(tester.element(provider));
    final tokens = theme.extension<AppTokens>()!;
    expect(
      tester.widget<Text>(provider).style,
      theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700),
    );

    await tester.tap(find.byKey(const ValueKey('ai-governance-save-button')));
    await tester.pump();

    final error = find.text('AI quota must be a finite non-negative number.');
    expect(
      tester.widget<Text>(error).style,
      theme.textTheme.bodyMedium!.copyWith(color: tokens.danger),
    );
    expect(saveCalled, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('policy dialog stays in compact viewport with save reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: testApp(const _DialogLauncher())),
    );
    await tester.tap(find.text('Open AI governance policy'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    expect(dialog.constraints!.maxHeight, 456);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final save = tester.getRect(find.text('Save policy'));
    expect(save.left, greaterThanOrEqualTo(dialogRect.left));
    expect(save.right, lessThanOrEqualTo(dialogRect.right));
    expect(save.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(tester.takeException(), isNull);
  });
}

class _DialogLauncher extends StatelessWidget {
  const _DialogLauncher({
    this.policy = const AIGovernancePolicy(),
    this.onSave,
  });

  final AIGovernancePolicy policy;
  final Future<void> Function(AIGovernancePolicy policy)? onSave;

  @override
  Widget build(BuildContext context) => UiButton(
    onPressed: () => showUiDialog<void>(
      context: context,
      builder: (_) => AIGovernancePolicyDialog(
        initialPolicy: policy,
        onSave: onSave ?? (_) async {},
      ),
    ),
    child: const Text('Open AI governance policy'),
  );
}
