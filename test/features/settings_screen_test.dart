import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/settings/presentation/settings_screen.dart';
import 'package:varian/features/settings/state/settings_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('canonical settings sections navigate without replacing routes', (
    tester,
  ) async {
    final repository = SettingsRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    late GoRouter router;
    router = _router(repository, initialLocation: '/settings');

    await tester.pumpWidget(_app(router, repository));
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsWidgets);
    expect(router.routeInformationProvider.value.uri.path, '/settings');

    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/settings/appearance',
    );
    expect(find.text('Appearance'), findsWidgets);

    await tester.tap(find.text('Accessibility').first);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/settings/accessibility',
    );
    expect(find.text('Reduced motion'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(UiSwitch), findsNWidgets(4));

    await tester.tap(find.text('Reduced motion'));
    await tester.pumpAndSettle();
    expect(tester.widget<UiSwitch>(find.byType(UiSwitch).first).value, isTrue);

    await tester.tap(find.text('Integrations').first);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/settings/integrations',
    );
    expect(find.text('Integrations'), findsWidgets);

    await tester.tap(find.text('Close').first);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
  });

  testWidgets('settings navigation exposes the active section as selected', (
    tester,
  ) async {
    final repository = SettingsRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    final router = _router(repository, initialLocation: '/settings/appearance');

    await tester.pumpWidget(_app(router, repository));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('settings-section-appearance')),
          )
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('settings-section-integrations')),
          )
          .flagsCollection
          .isSelected,
      ui.Tristate.isFalse,
    );
  });
  testWidgets('settings uses a stacked layout at compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = SettingsRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    final router = _router(repository, initialLocation: '/settings');

    await tester.pumpWidget(_app(router, repository));
    await tester.pumpAndSettle();

    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.text('Overview'), findsWidgets);
  });

  testWidgets('settings uses navigation rail layout at expanded width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = SettingsRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    final router = _router(repository, initialLocation: '/settings');

    await tester.pumpWidget(_app(router, repository));
    await tester.pumpAndSettle();

    expect(find.byType(VerticalDivider), findsOneWidget);
    final navigation = find.ancestor(
      of: find.byKey(const ValueKey('settings-section-overview')),
      matching: find.byType(UiSurface),
    );
    final navigationRect = tester.getRect(navigation.first);
    expect(navigationRect.width, 220);
    expect(navigationRect.left, greaterThanOrEqualTo(0));
    expect(navigationRect.right, lessThanOrEqualTo(1000));
    expect(navigationRect.top, greaterThanOrEqualTo(0));
    expect(navigationRect.bottom, lessThanOrEqualTo(800));
    expect(find.text('Overview'), findsWidgets);
  });
  testWidgets('settings navigation works at both widths with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = SettingsRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    final router = _router(repository, initialLocation: '/settings');

    await tester.pumpWidget(_app(router, repository, largeText: true));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(VerticalDivider), findsNothing);

    final accessibility = find.byKey(
      const ValueKey('settings-section-accessibility'),
    );
    await tester.ensureVisible(accessibility);
    await tester.tap(accessibility);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/settings/accessibility',
    );
    expect(find.text('Reduced motion'), findsOneWidget);
    for (final label in [
      'Reduced motion',
      'High contrast',
      'Force right-to-left layout',
      'Larger text',
    ]) {
      final switchLabel = find.text(label);
      await tester.ensureVisible(switchLabel);
      await tester.pumpAndSettle();
      expect(switchLabel, findsOneWidget);
    }
    expect(
      tester.getRect(find.text('Larger text')).bottom,
      lessThanOrEqualTo(568),
    );

    await tester.binding.setSurfaceSize(const Size(1000, 800));
    await tester.pumpAndSettle();
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('settings-section-accessibility')),
          )
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings shows a visible retry state when readiness fails', (
    tester,
  ) async {
    final repository = SettingsRepository(
      preferences: await SharedPreferences.getInstance(),
    );

    final router = _router(repository, initialLocation: '/settings');

    await tester.pumpWidget(
      _app(
        router,
        repository,
        readinessOverride: settingsReadinessProvider.overrideWith(
          (ref) async => throw StateError('settings fixture failure'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('settings fixture failure'), findsNothing);
  });
  testWidgets('settings readiness icon keeps the regular control size', (
    tester,
  ) async {
    final repository = SettingsRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    final router = _router(repository, initialLocation: '/settings');

    await tester.pumpWidget(
      _app(
        router,
        repository,
        readinessOverride: settingsReadinessProvider.overrideWith(
          (ref) async => throw StateError('settings fixture failure'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(Icons.settings_outlined));
    expect(icon.size, AppControlSize.regular);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'settings readiness state scrolls with large text in a compact viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = SettingsRepository(
        preferences: await SharedPreferences.getInstance(),
      );
      final router = _router(repository, initialLocation: '/settings');
      final readiness = Completer<void>();

      await tester.pumpWidget(
        _app(
          router,
          repository,
          largeText: true,
          readinessOverride: settingsReadinessProvider.overrideWith(
            (ref) => readiness.future,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final loadingMessage = find.text(
        'Saved values are retained while storage or cloud services are not ready.',
      );
      expect(find.text('Loading settings'), findsOneWidget);
      expect(loadingMessage, findsOneWidget);
      await tester.ensureVisible(loadingMessage);
      await tester.pumpAndSettle();

      expect(tester.getRect(loadingMessage).bottom, lessThanOrEqualTo(568));
      expect(tester.takeException(), isNull);
    },
  );
}

GoRouter _router(
  SettingsRepository repository, {
  required String initialLocation,
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/:section',
      builder: (context, state) =>
          SettingsScreen(section: state.pathParameters['section']),
    ),
  ],
);

Widget _app(
  GoRouter router,
  SettingsRepository repository, {
  Override? readinessOverride,
  bool largeText = false,
}) => ProviderScope(
  overrides: [
    settingsRepositoryProvider.overrideWithValue(repository),
    ?readinessOverride,
  ],
  child: MaterialApp.router(
    routerConfig: router,
    theme: AppTheme.darkTheme,
    localizationsDelegates: const [
      CreativeStudioLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: CreativeStudioLocalizations.supportedLocales,
    builder: (context, child) {
      final app = AppThemeScope(
        data: AppTheme.darkTheme,
        child: SizedBox(child: child ?? const SizedBox.shrink()),
      );
      return largeText
          ? MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: app,
            )
          : app;
    },
  ),
);
