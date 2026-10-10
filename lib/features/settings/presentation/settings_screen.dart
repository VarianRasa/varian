import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';

import '../../../app/localization/app_localizations.dart';
import '../../governance/state/accessibility_settings_provider.dart';
import '../state/settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  final String? section;

  const SettingsScreen({this.section, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = CreativeStudioLocalizations.of(context);
    final selected = section?.trim().isEmpty == true ? null : section;
    final readiness = ref.watch(settingsReadinessProvider);
    final accessibilityReadiness = ref.watch(
      accessibilitySettingsReadyProvider,
    );
    return UiPageScaffold(
      title: Text(copy.settingsTitle),
      actions: [
        UiButton(
          onPressed: selected == null ? null : () => context.go('/settings'),
          variant: UiButtonVariant.ghost,
          child: Text(copy.close),
        ),
      ],
      child: readiness.when(
        loading: () => _SettingsReadinessState(
          icon: Icons.hourglass_top_outlined,
          title: copy.settingsLoading,
          message: copy.settingsReadinessDescription,
        ),
        error: (error, stackTrace) => _SettingsReadinessState(
          icon: Icons.settings_outlined,
          title: copy.settingsUnavailable,
          message: copy.settingsUnavailableDescription,
          action: UiButton(
            onPressed: () => ref.invalidate(settingsReadinessProvider),
            child: Text(copy.retry),
          ),
        ),
        data: (_) => accessibilityReadiness.when(
          loading: () => selected == 'accessibility'
              ? _SettingsReadinessState(
                  icon: Icons.hourglass_top_outlined,
                  title: copy.settingsLoading,
                  message: copy.settingsReadinessDescription,
                )
              : _settingsLayout(context, selected),
          error: (error, stackTrace) => selected == 'accessibility'
              ? _SettingsReadinessState(
                  icon: Icons.settings_outlined,
                  title: copy.settingsUnavailable,
                  message: copy.settingsUnavailableDescription,
                  action: UiButton(
                    onPressed: () =>
                        ref.invalidate(accessibilitySettingsReadyProvider),
                    child: Text(copy.retry),
                  ),
                )
              : _settingsLayout(context, selected),
          data: (_) => _settingsLayout(context, selected),
        ),
      ),
    );
  }

  Widget _settingsLayout(BuildContext context, String? selected) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < AppBreakpoints.medium;
          final navigation = _SettingsNavigation(
            selected: selected,
            onSelected: (value) {
              final route = value == null ? '/settings' : '/settings/$value';
              context.go(route);
            },
          );
          final content = _SettingsContent(section: selected);
          final padding = AppResponsive.pagePadding(context);
          if (compact) {
            return ListView(
              padding: padding.copyWith(bottom: AppSpacing.xl),
              children: [
                navigation,
                const SizedBox(height: AppSpacing.sm),
                content,
              ],
            );
          }
          return SingleChildScrollView(
            padding: padding.copyWith(bottom: AppSpacing.xl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppBreakpoints.wide,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 220, child: navigation),
                    const SizedBox(width: AppSpacing.md),
                    const VerticalDivider(
                      width: AppSpacing.lg,
                      thickness: AppBorder.thin,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: content),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _SettingsReadinessState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _SettingsReadinessState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: UiSurface(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: AppControlSize.regular),
                const SizedBox(height: AppSpacing.md),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(message, textAlign: TextAlign.center),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SettingsNavigation extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _SettingsNavigation({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final copy = CreativeStudioLocalizations.of(context);
    final sections = <(String?, String, IconData)>[
      (null, copy.settingsOverview, Icons.tune_outlined),
      ('appearance', copy.settingsAppearance, Icons.palette_outlined),
      ('accessibility', copy.settingsAccessibility, Icons.accessibility_new),
      ('integrations', copy.settingsIntegrations, Icons.hub_outlined),
    ];
    final tokens = context.appTokens;
    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Semantics(
                key: ValueKey('settings-section-${item.$1 ?? 'overview'}'),
                selected: item.$1 == selected,
                child: UiButton(
                  onPressed: () => onSelected(item.$1),
                  variant: item.$1 == selected
                      ? UiButtonVariant.secondary
                      : UiButtonVariant.ghost,
                  mainAxisSize: MainAxisSize.max,
                  semanticsLabel: item.$2,
                  prefix: Icon(
                    item.$3,
                    color: item.$1 == selected
                        ? tokens.accent
                        : tokens.textMuted,
                  ),
                  child: Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsContent extends ConsumerWidget {
  final String? section;

  const _SettingsContent({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = CreativeStudioLocalizations.of(context);
    if (section == 'accessibility') {
      return _AccessibilitySettingsPanel(copy: copy);
    }
    final title = switch (section) {
      'appearance' => copy.settingsAppearance,
      'integrations' => copy.settingsIntegrations,
      _ => copy.settingsOverview,
    };
    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(copy.settingsLocalFirstDescription),
          const SizedBox(height: AppSpacing.pageWide),
          Text(copy.settingsReadinessDescription),
        ],
      ),
    );
  }
}

class _AccessibilitySettingsPanel extends ConsumerWidget {
  final CreativeStudioLocalizations copy;

  const _AccessibilitySettingsPanel({required this.copy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accessibilitySettingsProvider);
    final notifier = ref.read(accessibilitySettingsProvider.notifier);
    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.settingsAccessibility,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.pageWide),
          UiSwitch(
            label: Text(copy.settingsReducedMotion),
            value: settings.reducedMotion,
            onChange: (value) =>
                notifier.update(settings.copyWith(reducedMotion: value)),
          ),
          const SizedBox(height: AppSpacing.xs),
          UiSwitch(
            label: Text(copy.settingsHighContrast),
            value: settings.highContrast,
            onChange: (value) =>
                notifier.update(settings.copyWith(highContrast: value)),
          ),
          const SizedBox(height: AppSpacing.xs),
          UiSwitch(
            label: Text(copy.settingsForceRtl),
            value: settings.forceRtl,
            onChange: (value) =>
                notifier.update(settings.copyWith(forceRtl: value)),
          ),
          const SizedBox(height: AppSpacing.xs),
          UiSwitch(
            label: Text(copy.settingsLargerText),
            value: settings.largerText,
            onChange: (value) => notifier.update(
              settings.copyWith(
                largerText: value,
                textScaleFactor: value ? 1.2 : 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
