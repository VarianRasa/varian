import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/features/settings/state/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/route_error_screen.dart';

import 'package:varian/app/supabase_bootstrap.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/canvas/presentation/secure_share_screen.dart';
import 'package:varian/features/canvas/presentation/canvas_screen.dart';
import 'package:varian/features/home/presentation/home_screen.dart';

void main() {
  testWidgets('unmatched route has a safe compact error and home recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/missing/private-path',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Text('PROJECT LIBRARY'),
        ),
      ],
      errorBuilder: buildRouteErrorScreen,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        supportedLocales: CreativeStudioLocalizations.supportedLocales,
        localizationsDelegates: const [
          CreativeStudioLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: AppThemeScope(
            data: AppTheme.lightTheme,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This page is unavailable'), findsOneWidget);
    expect(find.textContaining('/missing/private-path'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.bySemanticsLabel('This page is unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final recoveryAction = find.text('Back to project library');
    await tester.ensureVisible(recoveryAction);
    await tester.pumpAndSettle();
    final actionRect = tester.getRect(recoveryAction);
    expect(actionRect.top, greaterThanOrEqualTo(0));
    expect(actionRect.bottom, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);

    await tester.tap(recoveryAction);
    await tester.pumpAndSettle();

    expect(find.text('PROJECT LIBRARY'), findsOneWidget);
    expect(find.text('This page is unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route error screen localizes its recovery action', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/missing',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SizedBox()),
      ],
      errorBuilder: buildRouteErrorScreen,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('id'),
        theme: AppTheme.darkTheme,
        supportedLocales: CreativeStudioLocalizations.supportedLocales,
        localizationsDelegates: const [
          CreativeStudioLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        routerConfig: router,
        builder: (context, child) => AppThemeScope(
          data: AppTheme.darkTheme,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Halaman ini tidak tersedia'), findsOneWidget);
    expect(find.text('Kembali ke pustaka proyek'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'production router keeps exactly one Windows frame across routes',
    (tester) async {
      defaultSupabaseBootstrap.markUnavailable();
      var shareReads = 0;
      String? sharedProjectId;
      String? sharedToken;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({});
        final settingsPreferences = await SharedPreferences.getInstance();
        final settingsRepository = SettingsRepository(
          preferences: settingsPreferences,
        );
        void expectOneWindowFrame() {
          expect(
            find.byKey(const ValueKey('desktop-window-title-bar')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('desktop-window-resize-area')),
            findsOneWidget,
          );
        }

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(settingsRepository),
              sharedCanvasReaderProvider.overrideWithValue(({
                required projectId,
                required token,
                String? passwordDigest,
              }) async {
                shareReads++;
                sharedProjectId = projectId;
                sharedToken = token;
                return SharedCanvasData(
                  document: CanvasDocument(
                    projectId: projectId,
                    updatedAt: DateTime.utc(2026, 10, 3),
                  ),
                  watermarkEnabled: true,
                );
              }),
            ],
            child: const CreativeCanvasApp(),
          ),
        );
        await tester.pump();
        expectOneWindowFrame();

        final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
        router.go('/settings');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(router.routeInformationProvider.value.uri.path, '/settings');
        expect(find.text('Settings'), findsOneWidget);
        expectOneWindowFrame();
        expect(tester.takeException(), isNull);

        router.go('/settings/appearance');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expectOneWindowFrame();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/settings/appearance',
        );
        expect(find.text('Appearance'), findsWidgets);
        expectOneWindowFrame();
        expect(tester.takeException(), isNull);

        router.go('/');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        router.go('/missing/private-path');
        await tester.pump();
        expectOneWindowFrame();
        await tester.pumpAndSettle();

        expect(find.byType(RouteErrorScreen), findsOneWidget);
        expect(find.textContaining('/missing/private-path'), findsNothing);
        expectOneWindowFrame();
        expect(tester.takeException(), isNull);

        final copy = CreativeStudioLocalizations.of(
          tester.element(find.byType(RouteErrorScreen)),
        );
        await tester.tap(find.text(copy.routeErrorHomeAction));
        await tester.pump();
        expectOneWindowFrame();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(RouteErrorScreen), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/');
        expect(tester.takeException(), isNull);
        router.go('/auth/callback-error');
        await tester.pumpAndSettle();

        expect(find.byType(RouteErrorScreen), findsNothing);
        expect(find.text(copy.authCallbackTitle), findsOneWidget);
        expect(
          find.byKey(const ValueKey('auth-callback-request-link')),
          findsOneWidget,
        );
        expectOneWindowFrame();
        expect(tester.takeException(), isNull);
        router.go('/auth');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expectOneWindowFrame();
        expect(router.routeInformationProvider.value.uri.path, '/auth');
        expect(find.text(copy.authSignInTitle), findsOneWidget);
        expectOneWindowFrame();
        expect(tester.takeException(), isNull);

        router.go('/auth/update-password');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          router.routeInformationProvider.value.uri.path,
          '/auth/update-password',
        );
        expect(
          find.byKey(const ValueKey('update-password-submit')),
          findsOneWidget,
        );
        expectOneWindowFrame();
        expect(tester.takeException(), isNull);
        router.go('/join?roomId=123456');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(router.routeInformationProvider.value.uri.path, '/auth');
        expect(
          router.routeInformationProvider.value.uri.queryParameters['returnTo'],
          '/join?roomId=123456',
        );
        expect(find.text(copy.authSignInTitle), findsOneWidget);
        expectOneWindowFrame();
        expect(tester.takeException(), isNull);

        const meetingId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
        router.go('/meeting/$meetingId/stage?projectId=local-meeting');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(router.routeInformationProvider.value.uri.path, '/auth');
        expect(
          router.routeInformationProvider.value.uri.queryParameters['returnTo'],
          '/meeting/$meetingId/stage?projectId=local-meeting',
        );
        expect(tester.takeException(), isNull);
        expectOneWindowFrame();

        router.go('/meeting/$meetingId?projectId=local-meeting');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(router.routeInformationProvider.value.uri.path, '/auth');
        expect(
          router.routeInformationProvider.value.uri.queryParameters['returnTo'],
          '/meeting/$meetingId?projectId=local-meeting',
        );
        expect(tester.takeException(), isNull);
        expectOneWindowFrame();

        router.go('/project/local-role-fixture?role=editor');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(router.routeInformationProvider.value.uri.path, '/auth');
        expect(
          router.routeInformationProvider.value.uri.queryParameters['returnTo'],
          '/project/local-role-fixture?role=editor',
        );
        expect(find.text(copy.authSignInTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectOneWindowFrame();

        router.go('/share/local-share?token=fixture-token&embed=1');
        await tester.pump();
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/share/local-share',
        );
        expect(
          router.routeInformationProvider.value.uri.queryParameters['embed'],
          '1',
        );
        expect(shareReads, 1);
        expect(sharedProjectId, 'local-share');
        expect(sharedToken, 'fixture-token');
        expect(
          find.text('Embedding is disabled for this published snapshot.'),
          findsOneWidget,
        );
        expect(find.byType(CanvasScreen), findsNothing);
        expectOneWindowFrame();
        expect(tester.takeException(), isNull);

        router.go('/share/local-share?token=fixture-token');
        await tester.pump();
        await tester.pumpAndSettle();
        expect(shareReads, 1);
        expect(sharedProjectId, 'local-share');
        expect(sharedToken, 'fixture-token');
        expect(find.byType(CanvasScreen), findsOneWidget);
        expectOneWindowFrame();
        final watermark = find.text('PUBLISHED PREVIEW');
        expect(watermark, findsOneWidget);
        final watermarkSurface = find
            .ancestor(of: watermark, matching: find.byType(DecoratedBox))
            .first;
        final watermarkDecoration =
            tester.widget<DecoratedBox>(watermarkSurface).decoration
                as BoxDecoration;
        expect(
          watermarkDecoration.borderRadius,
          BorderRadius.circular(AppRadius.dialog),
        );
        expect(tester.takeException(), isNull);

        router.go('/project/local-route-fixture-missing');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/project/local-route-fixture-missing',
        );
        expect(
          find.byKey(const ValueKey('project-route-not-found')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        expectOneWindowFrame();

        router.go('/');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.byType(RouteErrorScreen), findsNothing);
        expect(find.byType(CanvasScreen), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/');
        expect(tester.takeException(), isNull);
        expectOneWindowFrame();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
