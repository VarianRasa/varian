import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/responsive.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../state/onboarding_provider.dart';

Future<void> showOnboardingDialog(BuildContext context) async {
  await showUiDialog<void>(
    context: context,
    builder: (_) => const OnboardingDialog(),
  );
}

class OnboardingDialog extends ConsumerWidget {
  const OnboardingDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = CreativeStudioLocalizations.of(context);
    final steps = [
      (
        title: copy.onboardingLocalTitle,
        body: copy.onboardingLocalBody,
        icon: Icons.offline_bolt_outlined,
      ),
      (
        title: copy.onboardingCreateTitle,
        body: copy.onboardingCreateBody,
        icon: Icons.add_box_outlined,
      ),
      (
        title: copy.onboardingToolsTitle,
        body: copy.onboardingToolsBody,
        icon: Icons.dashboard_customize_outlined,
      ),
    ];
    final state = ref.watch(onboardingProvider);
    final step = state.step.clamp(0, steps.length - 1);
    final current = steps[step];
    final tokens = context.appTokens;
    return UiDialog(
      key: const ValueKey('onboarding-dialog'),
      semanticsLabel: copy.onboardingSemanticsLabel,
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 520,
        maxHeight: 560,
      ),
      builder: (context, style) => Padding(
        padding: AppResponsive.dialogPadding(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiSurface(
                padding: const EdgeInsets.all(AppSpacing.md),
                color: tokens.panelElevated,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(current.icon, color: tokens.accent, size: 22),
                        const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                        Expanded(
                          child: Text(
                            current.title,
                            style: style.titleTextStyle,
                          ),
                        ),
                        UiBadge(
                          '${step + 1}/${steps.length}',
                          variant: UiBadgeVariant.info,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        for (var index = 0; index < steps.length; index++) ...[
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              child: UiLinearProgressIndicator(
                                height: 3,
                                value: index <= step ? 1 : 0,
                              ),
                            ),
                          ),
                          if (index < steps.length - 1)
                            const SizedBox(
                              width: AppSpacing.xs + AppSpacing.xxs,
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              Text(
                current.body,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: tokens.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.xl - AppSpacing.xxs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      copy.onboardingLocalNote,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl - AppSpacing.xxs),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    key: const ValueKey('onboarding-skip'),
                    onPressed: () async {
                      await ref.read(onboardingProvider.notifier).skip();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    variant: UiButtonVariant.ghost,
                    child: Text(copy.onboardingSkip),
                  ),
                  UiButton(
                    key: const ValueKey('onboarding-next'),
                    onPressed: () {
                      if (step < steps.length - 1) {
                        ref.read(onboardingProvider.notifier).setStep(step + 1);
                      } else {
                        ref.read(onboardingProvider.notifier).skip();
                        Navigator.of(context).pop();
                      }
                    },
                    prefix: Icon(
                      step < steps.length - 1
                          ? Icons.arrow_forward
                          : Icons.check,
                    ),
                    child: Text(
                      step < steps.length - 1
                          ? copy.onboardingNext
                          : copy.onboardingStart,
                    ),
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
