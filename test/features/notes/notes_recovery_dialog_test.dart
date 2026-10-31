import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_key_manager.dart';
import 'package:varian/features/notes/presentation/notes_recovery_dialog.dart';

void main() {
  testWidgets('sets up recovery envelope and persists the local key', (
    tester,
  ) async {
    final manager = NotesKeyManager();
    NotesKeyEnvelope? savedEnvelope;
    Uint8List? savedKey;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => NotesRecoveryDialog(
                accountId: 'account-a',
                manager: manager,
                persistEnvelope: (envelope) async => savedEnvelope = envelope,
                persistKey: (key) async => savedKey = key,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Recovery passphrase'),
      'correct horse battery',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm passphrase'),
      'correct horse battery',
    );
    await tester.tap(find.text('Set up'));
    await tester.pumpAndSettle();

    expect(savedEnvelope, isNotNull);
    expect(savedKey, hasLength(32));
    expect(find.text('Set up Notes recovery'), findsNothing);
  });

  testWidgets('rejects mismatched confirmation without persisting data', (
    tester,
  ) async {
    var persistCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => NotesRecoveryDialog(
                accountId: 'account-a',
                manager: NotesKeyManager(),
                persistEnvelope: (_) async => persistCalls++,
                persistKey: (_) async => persistCalls++,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Recovery passphrase'),
      'correct horse battery',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm passphrase'),
      'different phrase',
    );
    await tester.tap(find.text('Set up'));
    await tester.pump();

    expect(find.text('Passphrases do not match.'), findsOneWidget);
    expect(persistCalls, 0);
  });

  testWidgets('locked cache shows a retryable wrong-passphrase error', (
    tester,
  ) async {
    final manager = NotesKeyManager();
    final recovery = await manager.createAccountKey(
      accountId: 'account-a',
      passphrase: 'correct horse battery',
    );
    var persistedKeys = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => NotesRecoveryDialog(
                accountId: 'account-a',
                manager: manager,
                envelope: recovery.envelope,
                persistEnvelope: (_) async {},
                persistKey: (_) async => persistedKeys++,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Recovery passphrase'),
      'wrong passphrase',
    );
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Recovery passphrase is invalid.'), findsOneWidget);
    expect(find.text('Unlock Notes'), findsOneWidget);
    expect(persistedKeys, 0);
  });
}
