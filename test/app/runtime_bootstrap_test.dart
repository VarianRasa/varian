import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/runtime_bootstrap.dart';
import 'package:varian/app/supabase_bootstrap.dart';
import 'package:varian/app/widgets/ui_primitives.dart';

Widget _appWithBootstrap({
  required Widget child,
  required Future<void> initialization,
  SupabaseBootstrapController? bootstrap,
}) => MaterialApp(
  supportedLocales: CreativeStudioLocalizations.supportedLocales,
  localizationsDelegates: const [
    CreativeStudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  builder: (context, appChild) => RuntimeBootstrap(
    initialization: initialization,
    bootstrap: bootstrap,
    child: appChild ?? const SizedBox.shrink(),
  ),
  home: child,
);
void main() {
  test('manual bootstrap diagnostics are redacted to safe text', () {
    final bootstrap = SupabaseBootstrapController();

    bootstrap.markUnavailable(
      diagnostic: 'https://example.invalid/callback?access_token=secret',
    );

    expect(
      bootstrap.state.diagnostic,
      'Cloud services are unavailable right now.',
    );
    expect(bootstrap.state.diagnostic, isNot(contains('secret')));
    bootstrap.dispose();
  });

  testWidgets('fatal bootstrap surface renders safe recovery copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: BootstrapFatalErrorSurface()),
    );

    final title = tester.getRect(
      find.text('Creative Canvas Studio could not load.'),
    );
    final recovery = tester.getRect(
      find.text('Reload the app to try again. Your local work is preserved.'),
    );
    for (final rect in [title, recovery]) {
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(480));
    }
    expect(tester.takeException(), isNull);

    final details = FlutterErrorDetails(
      exception: StateError('callback credential=redacted-fixture'),
    );
    expect(
      BootstrapFatalErrorSurface.messageFor(details),
      isNot(contains('redacted-fixture')),
    );
  });

  testWidgets('fatal bootstrap surface localizes recovery copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('id'),
        supportedLocales: CreativeStudioLocalizations.supportedLocales,
        localizationsDelegates: [
          CreativeStudioLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: BootstrapFatalErrorSurface(),
      ),
    );

    expect(
      find.text('Creative Canvas Studio tidak dapat dimuat.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Muat ulang aplikasi untuk mencoba lagi. Pekerjaan lokal Anda tetap tersimpan.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'renders a visible degraded state when optional bootstrap fails',
    (tester) async {
      final initialization = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          child: _appWithBootstrap(
            initialization: initialization.future,
            child: const Text('LOCAL LIBRARY'),
          ),
        ),
      );
      initialization.completeError(StateError('hidden detail'));
      await tester.pump();

      expect(find.text('LOCAL LIBRARY'), findsOneWidget);
      expect(
        find.text(
          'Cloud services unavailable. Local projects remain available.',
        ),
        findsOneWidget,
      );
      final status = find.text(
        'Cloud services unavailable. Local projects remain available.',
      );
      final theme = Theme.of(tester.element(status));
      final tokens = theme.appTokens;
      expect(
        tester.widget<Text>(status).style,
        theme.textTheme.bodyMedium!.copyWith(color: tokens.text),
      );
      expect(find.text('hidden detail'), findsNothing);
    },
  );

  testWidgets(
    'shows initialization failure even when bootstrap state is still deferred',
    (tester) async {
      final initialization = Completer<void>();
      final bootstrap = SupabaseBootstrapController();

      await tester.pumpWidget(
        ProviderScope(
          child: _appWithBootstrap(
            initialization: initialization.future,
            bootstrap: bootstrap,
            child: const Text('LOCAL LIBRARY'),
          ),
        ),
      );
      initialization.completeError(StateError('provider detail'));
      await tester.pump();

      expect(find.text('LOCAL LIBRARY'), findsOneWidget);
      expect(
        find.text(
          'Cloud services unavailable. Local projects remain available.',
        ),
        findsOneWidget,
      );
      expect(find.text('provider detail'), findsNothing);
      bootstrap.dispose();
    },
  );

  testWidgets('keeps local UI visible while runtime services initialize', (
    tester,
  ) async {
    final initialization = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        child: _appWithBootstrap(
          initialization: initialization.future,
          child: const Text('LOCAL LIBRARY'),
        ),
      ),
    );

    expect(find.text('LOCAL LIBRARY'), findsOneWidget);

    initialization.complete();
    await tester.pump();

    expect(find.text('LOCAL LIBRARY'), findsOneWidget);
  });

  test('prefers saved runtime Supabase configuration when enabled', () {
    final resolved = SupabaseBootstrapController.resolveConfiguration(
      compiledUrl: 'https://compiled.example',
      compiledPublishableKey: 'compiled-key-fixture',
      savedUrl: 'https://saved.example',
      savedPublishableKey: 'saved-key-fixture',
      useSavedConfiguration: true,
    );

    expect(resolved.url, 'https://saved.example');
    expect(resolved.publishableKey, 'saved-key-fixture');
  });

  testWidgets(
    'keeps cloud bootstrap deferred until an explicit readiness request',
    (tester) async {
      var attempts = 0;
      final bootstrap = SupabaseBootstrapController(
        initialize: () async {
          attempts++;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          child: _appWithBootstrap(
            initialization: Future<void>.value(),
            bootstrap: bootstrap,
            child: const Text('LOCAL LIBRARY'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LOCAL LIBRARY'), findsOneWidget);
      expect(attempts, 0);
      expect(bootstrap.state.status, SupabaseBootstrapStatus.deferred);
      expect(
        find.text('Local workspace ready. Cloud services connect when needed.'),
        findsNothing,
      );

      await bootstrap.ensureReady(explicit: true);
      await bootstrap.ensureReady(explicit: true);
      await tester.pump();

      expect(attempts, 1);
      expect(bootstrap.state.status, SupabaseBootstrapStatus.ready);
      bootstrap.dispose();
    },
  );

  testWidgets('allows dismissing cloud bootstrap status', (tester) async {
    final bootstrap = SupabaseBootstrapController();
    bootstrap.markUnavailable();

    await tester.pumpWidget(
      ProviderScope(
        child: _appWithBootstrap(
          initialization: Future<void>.value(),
          bootstrap: bootstrap,
          child: const Text('LOCAL LIBRARY'),
        ),
      ),
    );
    await tester.pump();

    final status = find.text(
      'Cloud services unavailable. Local projects remain available.',
    );
    expect(status, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dismiss-bootstrap-status')));
    await tester.pump();

    expect(status, findsNothing);
    expect(find.text('LOCAL LIBRARY'), findsOneWidget);
    bootstrap.dispose();
  });
  testWidgets('bootstrap status banner fits a compact viewport', (
    tester,
  ) async {
    final bootstrap = SupabaseBootstrapController()..markUnavailable();
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: _appWithBootstrap(
          initialization: Future<void>.value(),
          bootstrap: bootstrap,
          child: const Text('LOCAL LIBRARY'),
        ),
      ),
    );
    await tester.pump();

    final banner = find.ancestor(
      of: find.text(
        'Cloud services unavailable. Local projects remain available.',
      ),
      matching: find.byType(UiSurface),
    );
    final bannerRect = tester.getRect(banner.first);
    expect(bannerRect.left, greaterThanOrEqualTo(0));
    expect(bannerRect.right, lessThanOrEqualTo(320));
    expect(bannerRect.top, greaterThanOrEqualTo(0));
    expect(bannerRect.bottom, lessThanOrEqualTo(480));
    for (final action in [
      find.text('Retry'),
      find.byKey(const ValueKey('dismiss-bootstrap-status')),
    ]) {
      final rect = tester.getRect(action);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(480));
    }
    expect(tester.takeException(), isNull);
    bootstrap.dispose();
  });

  testWidgets('bootstrap banner inherits RTL direction from app builder', (
    tester,
  ) async {
    final bootstrap = SupabaseBootstrapController();
    bootstrap.markUnavailable();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          supportedLocales: CreativeStudioLocalizations.supportedLocales,
          localizationsDelegates: const [
            CreativeStudioLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RuntimeBootstrap(
              initialization: Future<void>.value(),
              bootstrap: bootstrap,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: const Text('LOCAL LIBRARY'),
        ),
      ),
    );
    await tester.pump();

    final statusRect = tester.getRect(
      find.text('Cloud services unavailable. Local projects remain available.'),
    );
    final retryRect = tester.getRect(find.text('Retry'));
    expect(retryRect.left, lessThan(statusRect.left));
    expect(tester.takeException(), isNull);
    bootstrap.dispose();
  });

  testWidgets(
    'cancels deferred startup before explicit retry initializes once',
    (tester) async {
      var attempts = 0;
      final bootstrap = SupabaseBootstrapController(
        initialize: () async {
          attempts++;
        },
      );

      final deferred = bootstrap.beginAfterFirstFrame(
        quietPeriod: Duration.zero,
      );
      await bootstrap.retry();
      await tester.pump();
      await deferred;

      expect(attempts, 1);
      expect(bootstrap.state.status, SupabaseBootstrapStatus.ready);
      bootstrap.dispose();
    },
  );
}
