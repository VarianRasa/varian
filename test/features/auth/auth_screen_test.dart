import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/supabase_bootstrap.dart';
import 'package:varian/data/remote/supabase_app_config.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/auth/presentation/auth_screen.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/auth/state/auth_recovery.dart';

import '../../test_app.dart';

class _SuccessfulAuthService extends AuthService {
  _SuccessfulAuthService() : super(null);

  bool didSignIn = false;
  bool didSignUp = false;

  @override
  bool get canAttempt => true;

  @override
  Future<void> signIn({required String email, required String password}) async {
    didSignIn = true;
  }

  @override
  Future<bool> signUp({required String email, required String password}) async {
    didSignUp = true;
    return true;
  }
}

void main() {
  testWidgets('shows the canvas auth page without developer config fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: testApp(const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to your canvas'), findsOneWidget);
    expect(
      find.text('Configure a Supabase URL and publishable key'),
      findsNothing,
    );
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('auth-template-showcase')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('auth-template-moodboard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('auth-template-storyboard')),
      findsOneWidget,
    );
  });

  testWidgets('canvas showcase allows selecting a built-in template', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: testApp(const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final storyboard = find.byKey(const ValueKey('auth-template-storyboard'));
    expect(storyboard, findsOneWidget);
    await tester.ensureVisible(storyboard);
    await tester.pumpAndSettle();
    await tester.tap(storyboard);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: storyboard,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth canvas and card remain within compact and wide viewports', (
    tester,
  ) async {
    ProviderScope app() => ProviderScope(
      overrides: [supabaseClientProvider.overrideWithValue(null)],
      child: testApp(const AuthScreen()),
    );

    Future<void> pumpAtSize(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
    }

    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpAtSize(const Size(320, 480));

    final compactCanvas = find.byKey(const ValueKey('auth-template-showcase'));
    expect(compactCanvas, findsOneWidget);
    expect(tester.getSize(compactCanvas).height, 94);
    final compactCanvasRect = tester.getRect(compactCanvas);
    expect(compactCanvasRect.left, greaterThanOrEqualTo(0));
    expect(compactCanvasRect.right, lessThanOrEqualTo(320));

    final authCardTitle = find.text('Sign in to your canvas');
    final authCard = find.ancestor(
      of: authCardTitle,
      matching: find.byType(UiSurface),
    );
    final compactCardRect = tester.getRect(authCard.first);
    expect(compactCardRect.left, greaterThanOrEqualTo(0));
    expect(compactCardRect.right, lessThanOrEqualTo(320));
    await tester.ensureVisible(authCardTitle);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('SIGN IN'));
    await tester.pumpAndSettle();
    final compactSubmit = tester.getRect(find.text('SIGN IN'));
    expect(compactSubmit.left, greaterThanOrEqualTo(0));
    expect(compactSubmit.right, lessThanOrEqualTo(320));
    expect(compactSubmit.bottom, lessThanOrEqualTo(480));

    await pumpAtSize(const Size(1280, 900));
    final wideCanvas = find.byKey(const ValueKey('auth-template-showcase'));
    expect(wideCanvas, findsOneWidget);
    expect(tester.getSize(wideCanvas).height, 124);
    final wideCard = find.ancestor(
      of: find.text('Sign in to your canvas'),
      matching: find.byType(UiSurface),
    );
    final wideCardRect = tester.getRect(wideCard.first);
    expect(wideCardRect.left, greaterThanOrEqualTo(0));
    expect(wideCardRect.right, lessThanOrEqualTo(1280));
    expect(wideCardRect.top, greaterThanOrEqualTo(0));
    expect(wideCardRect.bottom, lessThanOrEqualTo(900));
    expect(tester.takeException(), isNull);
  });
  testWidgets('auth footer reflows at narrow width with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: testApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: const AuthScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final footer = find.byKey(const ValueKey('auth-footer'));
    expect(footer, findsOneWidget);
    await tester.ensureVisible(footer);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('New to Creative Workstation?'), findsOneWidget);
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);
  });
  testWidgets('password reset remains reachable at compact large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: testApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: const AuthScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final forgotPassword = find.text('Forgot password?');
    await tester.ensureVisible(forgotPassword);
    await tester.pumpAndSettle();
    await tester.tap(forgotPassword);
    await tester.pumpAndSettle();

    expect(find.text('Reset your password'), findsOneWidget);
    final resetAction = find.text('SEND RESET EMAIL');
    await tester.ensureVisible(resetAction);
    await tester.pumpAndSettle();
    expect(tester.getRect(resetAction).bottom, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('labels Google OAuth as signup in signup mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: testApp(const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final signupLink = find.text('CREATE ACCOUNT').last;
    await tester.ensureVisible(signupLink);
    await tester.tap(signupLink);
    await tester.pumpAndSettle();

    expect(find.text('Sign up with Google'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('password visibility can be toggled accessibly', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: testApp(const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    var passwordField = tester.widget<TextField>(find.byType(TextField).last);
    expect(passwordField.obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();

    passwordField = tester.widget<TextField>(find.byType(TextField).last);
    expect(passwordField.obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pumpAndSettle();

    passwordField = tester.widget<TextField>(find.byType(TextField).last);
    expect(passwordField.obscureText, isTrue);
  });

  testWidgets('auth page uses the 840px split breakpoint', (tester) async {
    tester.view.physicalSize = const Size(AppBreakpoints.medium, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pumpAtWidth(double width) async {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(null)],
          child: testApp(const AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAtWidth(AppBreakpoints.medium - 1);
    final narrowHeadline = tester.getTopLeft(
      find.text('Your ideas,\nconnected.'),
    );
    final narrowCardTitle = tester.getTopLeft(
      find.text('Sign in to your canvas'),
    );
    expect(narrowCardTitle.dy, lessThan(narrowHeadline.dy));

    await pumpAtWidth(AppBreakpoints.medium);
    final wideHeadline = tester.getTopLeft(
      find.text('Your ideas,\nconnected.'),
    );
    final wideCardTitle = tester.getTopLeft(
      find.text('Sign in to your canvas'),
    );
    expect(wideCardTitle.dx - wideHeadline.dx, greaterThan(100));
  });

  testWidgets('keeps local validation available when cloud bootstrap failed', (
    tester,
  ) async {
    final bootstrap = SupabaseBootstrapController(initialize: () async {})
      ..markUnavailable();
    final auth = AuthService(null, bootstrap: bootstrap);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          authServiceProvider.overrideWithValue(auth),
        ],
        child: testApp(const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.text('SIGN IN');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Authentication is unavailable right now.'), findsNothing);
    bootstrap.dispose();
  });

  test('maps backend auth errors to safe user-facing messages', () {
    expect(
      AuthService.friendlyError('Invalid login credentials'),
      'Incorrect email or password.',
    );
    expect(
      AuthService.friendlyError('Email not confirmed'),
      'Confirm your email address before signing in.',
    );
    expect(
      AuthService.friendlyError(
        'For security purposes, you can only request this after 60 seconds',
      ),
      'Too many attempts. Try again in a moment.',
    );
    expect(
      AuthService.friendlyError('Password reset rate limit exceeded (429)'),
      'Too many attempts. Try again in a moment.',
    );
    expect(
      AuthService.retryAfter(
        'For security purposes, you can only request this after 60 seconds',
      ),
      const Duration(seconds: 60),
    );
    expect(
      AuthService.friendlyError('The password recovery link has expired'),
      'This link is expired or invalid. Request a new one.',
    );
    expect(
      AuthService.friendlyError('Authentication is unavailable right now.'),
      'Authentication is unavailable right now. Local projects remain available.',
    );
  });

  test('checks Supabase initialization safely before client setup', () {
    expect(() => isSupabaseInitialized(), returnsNormally);
  });

  test('keeps reset cooldown state across AuthScreen instances', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final first = container.read(passwordResetCooldownProvider);
    final start = DateTime(2026, 9, 18, 12);

    expect(first.tryStart(now: start), isTrue);
    expect(container.read(passwordResetCooldownProvider), same(first));
    expect(first.remainingAt(start), const Duration(seconds: 30));
  });

  testWidgets('embedded auth reports successful sign-in and sign-up', (
    tester,
  ) async {
    final auth = _SuccessfulAuthService();
    var authenticated = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          authServiceProvider.overrideWithValue(auth),
        ],
        child: testApp(
          AuthScreen(embedded: true, onAuthenticated: () => authenticated++),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'password-123');
    await tester.tap(find.text('SIGN IN').first);
    await tester.pumpAndSettle();

    expect(auth.didSignIn, isTrue);
    expect(authenticated, 1);

    await tester.ensureVisible(find.text('CREATE ACCOUNT').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREATE ACCOUNT').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'password-123');
    await tester.tap(find.text('CREATE ACCOUNT').first);
    await tester.pumpAndSettle();

    expect(auth.didSignUp, isTrue);
    expect(authenticated, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded auth stays usable in narrow and short panels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final size in [const Size(264, 260), const Size(320, 320)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(null)],
          child: testApp(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: const AuthScreen(embedded: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth-embedded-background-grid')),
        findsOneWidget,
      );
      expect(find.byTooltip('Back to canvas'), findsNothing);
      expect(find.byType(UiSurface), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('CREATE ACCOUNT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CREATE ACCOUNT').last);
      await tester.pumpAndSettle();
      expect(find.text('Sign up with Google'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('SIGN IN').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SIGN IN').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
      expect(tester.takeException(), isNull);

      expect(find.byTooltip('Back to canvas'), findsNothing);
      expect(find.byType(UiSurface), findsNothing);
    }
  });

  test('uses the publisher Supabase defaults without build flags', () {
    expect(SupabaseAppConfig.url, 'https://jnpxpylzzskaukgwhuzg.supabase.co');
    expect(SupabaseAppConfig.publishableKey, startsWith('sb_publishable_'));
    expect(SupabaseAppConfig.publishableKey, isNot(contains('service_role')));
  });

  test('sign-out flushes local durable state before auth cleanup', () async {
    var flushed = false;
    final auth = AuthService(
      null,
      flushDurable: () async {
        flushed = true;
      },
    );

    await auth.signOut();

    expect(flushed, isTrue);
  });
}
