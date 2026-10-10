import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/features/auth/presentation/update_password_screen.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/app/theme.dart';

import '../../test_app.dart';

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(null);

  @override
  Future<void> updatePassword(String password) async {}
}

void main() {
  testWidgets('recovery route icon uses the compact control token', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const UpdatePasswordScreen())),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Icon>(find.byIcon(Icons.lock_reset_outlined)).size,
      AppControlSize.compact,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('marks both recovery fields as newly created passwords', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const UpdatePasswordScreen())),
    );
    await tester.pumpAndSettle();

    final password = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('update-password-field')),
        matching: find.byType(TextField),
      ),
    );
    final confirmation = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('update-password-confirmation')),
        matching: find.byType(TextField),
      ),
    );

    expect(password.autofillHints, contains(AutofillHints.newPassword));
    expect(confirmation.autofillHints, contains(AutofillHints.newPassword));
  });

  testWidgets('validates password confirmation locally', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const UpdatePasswordScreen())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('update-password-field')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('update-password-confirmation')),
      'different-password',
    );
    await tester.tap(find.byKey(const ValueKey('update-password-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('rejects weak passwords before cloud work', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const UpdatePasswordScreen())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('update-password-field')),
      'short',
    );
    await tester.enterText(
      find.byKey(const ValueKey('update-password-confirmation')),
      'short',
    );
    await tester.tap(find.byKey(const ValueKey('update-password-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('clears handled recovery return paths after update', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_return_path': '/project/recovery-target',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(_FakeAuthService())],
        child: testApp(const UpdatePasswordScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('update-password-field')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('update-password-confirmation')),
      'new-password-123',
    );
    await tester.tap(find.byKey(const ValueKey('update-password-submit')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_return_path'), '/project/recovery-target');
    expect(
      find.text('Password updated. Your workspace is ready.'),
      findsOneWidget,
    );
  });
}
