import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/features/auth/state/auth_recovery.dart';

void main() {
  group('AuthCallbackParser', () {
    test('parses callback values from a hash route', () {
      final uri = Uri.parse(
        'http://localhost:3000/#/auth?code=fixture-a&type=recovery',
      );

      final callback = AuthCallbackParser.parse(uri);

      expect(callback.kind, AuthCallbackKind.passwordRecovery);
      expect(callback.hasCode, isTrue);
      expect(callback.uri.fragment, isEmpty);
      expect(callback.uri.query, isEmpty);
    });

    test(
      'classifies password recovery without retaining callback credentials',
      () {
        final uri = Uri.parse(
          'http://localhost:3000/auth?code=fixture-b&type=recovery&returnTo=%2Fsettings%2Fsecurity',
        );

        final callback = AuthCallbackParser.parse(uri);

        expect(callback.kind, AuthCallbackKind.passwordRecovery);
        expect(callback.hasCode, isTrue);
        expect(callback.safeReturnPath, '/settings/security');
        expect(callback.toString(), isNot(contains('fixture-b')));
        expect(
          AuthCallbackParser.cleanedUri(uri).toString(),
          'http://localhost:3000/auth?returnTo=%2Fsettings%2Fsecurity',
        );
      },
    );

    test('maps expired and access denied callbacks to safe states', () {
      final expired = AuthCallbackParser.parse(
        Uri.parse(
          'http://localhost:3000/auth?error=access_denied&error_code=otp_expired&error_description=The+link+has+expired',
        ),
      );
      final denied = AuthCallbackParser.parse(
        Uri.parse(
          'http://localhost:3000/auth?error=access_denied&error_code=access_denied',
        ),
      );

      expect(expired.kind, AuthCallbackKind.expired);
      expect(denied.kind, AuthCallbackKind.accessDenied);
      expect(expired.message, isNot(contains('expired')));
      expect(expired.message, isNot(contains('otp_expired')));
      expect(AuthCallbackParser.cleanedUri(expired.uri).query, isEmpty);
    });

    test('provider errors take precedence over callback credentials', () {
      final expiredRecovery = AuthCallbackParser.parse(
        Uri.parse(
          'http://localhost:3000/auth?type=recovery&code=fixture-recovery&error=access_denied&error_code=otp_expired',
        ),
      );
      final deniedSignIn = AuthCallbackParser.parse(
        Uri.parse(
          'http://localhost:3000/auth?code=fixture-sign-in&error=access_denied',
        ),
      );

      expect(expiredRecovery.kind, AuthCallbackKind.expired);
      expect(deniedSignIn.kind, AuthCallbackKind.accessDenied);
      expect(
        AuthCallbackParser.exchangeUri(expiredRecovery.uri).query,
        isEmpty,
      );
    });

    test(
      'rejects unsafe return paths and preserves only safe navigation state',
      () {
        final uri = Uri.parse(
          'http://localhost:3000/auth?code=abc&next=https%3A%2F%2Fevil.example%2Fsteal&projectId=local-1',
        );

        final callback = AuthCallbackParser.parse(uri);

        expect(callback.safeReturnPath, isNull);
        expect(AuthCallbackParser.cleanedUri(uri).queryParameters, isEmpty);
      },
    );

    test('preserves safe join route parameters', () {
      expect(
        AuthCallbackParser.safeLocalPath('/join?roomId=482917'),
        '/join?roomId=482917',
      );
    });

    test('selects a safe fallback when the first return path is unsafe', () {
      final uri = Uri.parse(
        'http://localhost:3000/auth?returnTo=https%3A%2F%2Fevil.example&next=%2Fjoin%3FroomId%3D482917',
      );

      final callback = AuthCallbackParser.parse(uri);

      expect(callback.safeReturnPath, '/join?roomId=482917');
      expect(
        AuthCallbackParser.cleanedUri(uri).queryParameters['returnTo'],
        '/join?roomId=482917',
      );
    });

    test('classifies malformed credential fragments for cleanup', () {
      final uri = Uri.parse('http://localhost:3000/auth#access_token=%ZZ');

      final callback = AuthCallbackParser.parse(uri);

      expect(callback.kind, AuthCallbackKind.malformed);
      expect(AuthCallbackParser.cleanedUri(uri).fragment, isEmpty);
    });

    test('classifies malformed query encoding without throwing', () {
      final uri = Uri.parse('http://localhost:3000/auth?code=%ZZ');

      final callback = AuthCallbackParser.parse(uri);

      expect(callback.kind, AuthCallbackKind.malformed);
      expect(callback.hasCode, isFalse);
      expect(AuthCallbackParser.cleanedUri(uri).query, isEmpty);
    });

    test('rejects malformed UTF-8 query values for cleanup', () {
      final uri = Uri.parse(
        'http://localhost:3000/auth?code=%C3%28&type=recovery',
      );

      final callback = AuthCallbackParser.parse(uri);

      expect(callback.kind, AuthCallbackKind.malformed);
      expect(callback.hasCode, isFalse);
      expect(callback.uri.queryParameters, isEmpty);
      expect(callback.uri.fragment, isEmpty);
    });

    test('drops malformed UTF-8 in a return path without throwing', () {
      final uri = Uri.parse(
        'http://localhost:3000/auth?code=abc&returnTo=%2Fjoin%3FprojectId%3D%FF',
      );

      final callback = AuthCallbackParser.parse(uri);

      expect(callback.kind, AuthCallbackKind.malformed);
      expect(callback.safeReturnPath, isNull);
      expect(AuthCallbackParser.cleanedUri(uri).queryParameters, isEmpty);
    });

    test('stores only sanitized callback metadata', () {
      final callback = AuthCallbackParser.parse(
        Uri.parse(
          'http://fixture-user@localhost:3000/auth#access_token=fixture-c&type=recovery',
        ),
      );

      expect(callback.uri.queryParameters, isEmpty);
      expect(callback.uri.fragment, isEmpty);
      expect(callback.uri.userInfo, isEmpty);
      expect(callback.uri.toString(), isNot(contains('fixture-c')));
      expect(callback.uri.toString(), isNot(contains('fixture-user')));
    });
  });

  test(
    'callback coordinator renders unavailable cloud state without retaining URI data',
    () async {
      final coordinator = AuthCallbackCoordinator(() => null);
      await coordinator.handle(
        Uri.parse('http://localhost:3000/auth?code=fixture-d&type=recovery'),
      );

      expect(coordinator.state.status, AuthCallbackStatus.error);
      expect(
        coordinator.state.message,
        contains('Local projects remain available'),
      );
      expect(coordinator.state.toString(), isNot(contains('fixture-d')));
      coordinator.dispose();
    },
  );

  test('invalid callback states do not trigger a cloud request', () async {
    var ensureReadyCalls = 0;
    final coordinator = AuthCallbackCoordinator(
      () => null,
      ensureReady: () async => ensureReadyCalls++,
    );
    await coordinator.handle(
      Uri.parse('http://localhost:3000/auth?error=access_denied'),
    );

    expect(ensureReadyCalls, 0);
    expect(coordinator.state.status, AuthCallbackStatus.error);
    expect(coordinator.state.kind, AuthCallbackKind.accessDenied);

    await coordinator.handle(
      Uri.parse('http://localhost:3000/auth?error=access_denied'),
    );
    expect(coordinator.state.message, contains('already used'));
    coordinator.dispose();
  });

  test('password reset cooldown is bounded and deterministic', () {
    final cooldown = PasswordResetCooldown(
      duration: const Duration(seconds: 30),
    );
    final start = DateTime(2026, 9, 18, 12);

    expect(cooldown.tryStart(now: start), isTrue);
    expect(
      cooldown.tryStart(now: start.add(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      cooldown.remainingAt(start.add(const Duration(seconds: 10))),
      const Duration(seconds: 20),
    );
    expect(
      cooldown.remainingAt(start.add(const Duration(seconds: 30))),
      Duration.zero,
    );
    expect(
      cooldown.tryStart(now: start.add(const Duration(seconds: 31))),
      isTrue,
    );
  });

  test('caps provider cooldown hints to a bounded retry window', () {
    final cooldown = PasswordResetCooldown();
    final start = DateTime(2026, 9, 18, 12);

    expect(
      cooldown.tryStart(now: start, retryAfter: const Duration(minutes: 30)),
      isTrue,
    );
    expect(cooldown.remainingAt(start), const Duration(minutes: 5));
  });

  test('normalizes invalid cooldown durations to a safe bounded default', () {
    final cooldown = PasswordResetCooldown(duration: Duration.zero);
    final start = DateTime(2026, 9, 18, 12);

    expect(cooldown.tryStart(now: start), isTrue);
    expect(cooldown.remainingAt(start), const Duration(seconds: 30));
  });

  test('normalizes hash-router callbacks for the SDK exchange', () {
    final exchangeUri = AuthCallbackParser.exchangeUri(
      Uri.parse('http://localhost:3000/#/auth?code=fixture-e&type=recovery'),
    );

    expect(exchangeUri.fragment, isEmpty);
    expect(exchangeUri.queryParameters['code'], 'fixture-e');
    expect(exchangeUri.queryParameters['type'], 'recovery');
  });

  test('recognizes the SDK passwordRecovery redirect event', () {
    expect(
      AuthCallbackParser.isPasswordRecoveryRedirectType('passwordRecovery'),
      isTrue,
    );
    expect(
      AuthCallbackParser.isPasswordRecoveryRedirectType('recovery'),
      isTrue,
    );
    expect(
      AuthCallbackParser.isPasswordRecoveryRedirectType('signedIn'),
      isFalse,
    );
  });

  test('stores return path and owner in one envelope key', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthReturnPathStore.save(
      '/project/account-a',
      ownerAccountId: 'account-a',
    );

    final prefs = await SharedPreferences.getInstance();
    final envelope = jsonDecode(prefs.getString('auth_return_path')!);
    expect(envelope, {
      'version': 1,
      'path': '/project/account-a',
      'owner': 'account-a',
    });
    expect(prefs.getString('auth_return_path_owner'), isNull);
  });

  test('does not consume a return path owned by another account', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthReturnPathStore.save(
      '/project/account-a',
      ownerAccountId: 'account-a',
    );

    expect(await AuthReturnPathStore.consume(accountId: 'account-b'), isNull);
    expect(
      await AuthReturnPathStore.consume(accountId: 'account-a'),
      '/project/account-a',
    );
  });

  test('migrates legacy return path keys when consumed', () async {
    SharedPreferences.setMockInitialValues({
      'auth_return_path': '/project/legacy',
      'auth_return_path_owner': 'account-a',
    });

    expect(
      await AuthReturnPathStore.consume(accountId: 'account-a'),
      '/project/legacy',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_return_path'), isNull);
    expect(prefs.getString('auth_return_path_owner'), isNull);
  });

  test('clears malformed return path envelopes safely', () async {
    SharedPreferences.setMockInitialValues({
      'auth_return_path': '{"version":1,"owner":"account-a"}',
    });

    expect(await AuthReturnPathStore.consume(accountId: 'account-a'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_return_path'), isNull);
  });

  test('clears a matching explicit return path after authentication', () async {
    SharedPreferences.setMockInitialValues({
      'auth_return_path': '/project/current?projectId=current',
      'auth_return_path_owner': 'account-b',
    });

    await AuthReturnPathStore.clearIfMatches(
      '/project/current?projectId=current',
      expectedOwner: 'account-b',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_return_path'), isNull);
  });

  test(
    'preserves a different replacement return path when paths do not match',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_return_path': '/project/replacement',
      });

      await AuthReturnPathStore.clearIfMatches(
        '/project/current',
        expectedOwner: 'account-b',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_return_path'), '/project/replacement');
    },
  );

  test('consumes protected return paths once', () async {
    SharedPreferences.setMockInitialValues({
      'auth_return_path': '/project/local-1?projectId=local-1',
    });

    expect(
      await AuthReturnPathStore.consume(),
      '/project/local-1?projectId=local-1',
    );
    expect(await AuthReturnPathStore.consume(), isNull);
  });
}
