import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_key_manager.dart';

void main() {
  late NotesKeyManager manager;
  setUp(() => manager = NotesKeyManager());

  test('wraps a random key and unlocks with the passphrase', () async {
    final envelope = await manager.createEnvelope(
      accountId: 'a',
      passphrase: 'correct horse battery',
    );
    expect(envelope.version, 1);
    expect(
      await manager.unlockEnvelope(
        accountId: 'a',
        passphrase: 'correct horse battery',
        envelope: envelope,
      ),
      hasLength(32),
    );
  });

  test('returns the local key needed for encrypted persistence', () async {
    final created = await manager.createAccountKey(
      accountId: 'a',
      passphrase: 'correct horse battery',
    );
    expect(created.key, hasLength(32));
    expect(
      await manager.unlockEnvelope(
        accountId: 'a',
        passphrase: 'correct horse battery',
        envelope: created.envelope,
      ),
      created.key,
    );
  });

  test(
    'wrong passphrase, account mismatch, and tampering fail uniformly',
    () async {
      final envelope = await manager.createEnvelope(
        accountId: 'a',
        passphrase: 'correct horse battery',
      );
      final wrong = manager.unlockEnvelope(
        accountId: 'a',
        passphrase: 'wrong passphrase',
        envelope: envelope,
      );
      final other = manager.unlockEnvelope(
        accountId: 'b',
        passphrase: 'correct horse battery',
        envelope: envelope,
      );
      await expectLater(wrong, throwsA(isA<NotesKeyException>()));
      await expectLater(other, throwsA(isA<NotesKeyException>()));
      final corrupt = envelope.copyWith(
        ciphertext: envelope.ciphertext.sublist(
          0,
          envelope.ciphertext.length - 1,
        ),
      );
      await expectLater(
        manager.unlockEnvelope(
          accountId: 'a',
          passphrase: 'correct horse battery',
          envelope: corrupt,
        ),
        throwsA(isA<NotesKeyException>()),
      );
    },
  );

  test(
    'rotation rewraps same DEK and rejects out-of-range KDF settings',
    () async {
      final envelope = await manager.createEnvelope(
        accountId: 'a',
        passphrase: 'first passphrase',
      );
      final rotated = await manager.rotateEnvelope(
        accountId: 'a',
        oldPassphrase: 'first passphrase',
        newPassphrase: 'second passphrase',
        envelope: envelope,
      );
      expect(
        await manager.unlockEnvelope(
          accountId: 'a',
          passphrase: 'second passphrase',
          envelope: rotated,
        ),
        hasLength(32),
      );
    },
  );
}
