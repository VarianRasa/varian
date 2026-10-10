import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:varian/app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/features/auth/presentation/update_password_screen.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/auth/state/auth_recovery.dart';

void main() {
  testWidgets('expired callback stays usable with compact large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final coordinator = AuthCallbackCoordinator(() => null);
    final router = GoRouter(
      initialLocation: '/auth/callback-error',
      routes: [
        GoRoute(
          path: '/auth/callback-error',
          builder: (context, state) => const AuthCallbackErrorScreen(),
        ),
        GoRoute(
          path: '/auth',
          builder: (context, state) => const Scaffold(body: Text('AUTH FORM')),
        ),
      ],
    );
    coordinator.state = const AuthCallbackSnapshot(
      status: AuthCallbackStatus.error,
      kind: AuthCallbackKind.expired,
      message: 'token=do-not-display',
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authCallbackCoordinatorProvider.overrideWith((ref) => coordinator),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.darkTheme,
          supportedLocales: CreativeStudioLocalizations.supportedLocales,
          localizationsDelegates: const [
            CreativeStudioLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (context, child) {
            final theme = Theme.of(context);
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: AppThemeScope(
                data: theme,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Icon>(find.byIcon(Icons.link_off_outlined)).size,
      AppControlSize.compact,
    );
    expect(find.text('Authentication link unavailable'), findsOneWidget);
    expect(
      find.text('This recovery link is no longer valid. Request a new one.'),
      findsOneWidget,
    );
    expect(find.textContaining('token=do-not-display'), findsNothing);

    final requestLink = find.byKey(
      const ValueKey('auth-callback-request-link'),
    );
    await tester.ensureVisible(requestLink);
    await tester.pumpAndSettle();
    final actionRect = tester.getRect(requestLink);
    expect(actionRect.top, greaterThanOrEqualTo(0));
    expect(actionRect.bottom, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);

    await tester.tap(requestLink);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/auth');
    expect(find.text('AUTH FORM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
