import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class NotesKeyException implements Exception {
  const NotesKeyException();
}

class NotesKeyEnvelope {
  const NotesKeyEnvelope({
    required this.version,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
  });
  final int version, iterations;
  final Uint8List salt, nonce, ciphertext;
  NotesKeyEnvelope copyWith({Uint8List? ciphertext}) => NotesKeyEnvelope(
    version: version,
    iterations: iterations,
    salt: salt,
    nonce: nonce,
    ciphertext: ciphertext ?? this.ciphertext,
  );
}

class NotesAccountKey {
  const NotesAccountKey({required this.envelope, required this.key});
  final NotesKeyEnvelope envelope;
  final Uint8List key;
}

class NotesKeyManager {
  static const int defaultIterations = 210000;
  static const int minIterations = 100000, maxIterations = 1000000;
  final Random _random;
  NotesKeyManager({Random? random}) : _random = random ?? Random.secure();

  Future<NotesKeyEnvelope> createEnvelope({
    required String accountId,
    required String passphrase,
    int iterations = defaultIterations,
  }) async => (await createAccountKey(
    accountId: accountId,
    passphrase: passphrase,
    iterations: iterations,
  )).envelope;

  Future<NotesAccountKey> createAccountKey({
    required String accountId,
    required String passphrase,
    int iterations = defaultIterations,
  }) async {
    _validate(accountId, passphrase, iterations);
    final dek = _bytes(32), salt = _bytes(16), nonce = _bytes(12);
    final envelope = NotesKeyEnvelope(
      version: 1,
      iterations: iterations,
      salt: salt,
      nonce: nonce,
      ciphertext: _crypt(
        true,
        dek,
        accountId,
        passphrase,
        iterations,
        salt,
        nonce,
      ),
    );
    return NotesAccountKey(envelope: envelope, key: dek);
  }

  Future<Uint8List> unlockEnvelope({
    required String accountId,
    required String passphrase,
    required NotesKeyEnvelope envelope,
  }) async {
    try {
      _validate(accountId, passphrase, envelope.iterations);
      if (envelope.version != 1 ||
          envelope.salt.length != 16 ||
          envelope.nonce.length != 12 ||
          envelope.ciphertext.length != 48) {
        throw const NotesKeyException();
      }
      final dek = _crypt(
        false,
        envelope.ciphertext,
        accountId,
        passphrase,
        envelope.iterations,
        envelope.salt,
        envelope.nonce,
      );
      if (dek.length != 32) throw const NotesKeyException();
      return dek;
    } catch (_) {
      throw const NotesKeyException();
    }
  }

  Future<NotesKeyEnvelope> rotateEnvelope({
    required String accountId,
    required String oldPassphrase,
    required String newPassphrase,
    required NotesKeyEnvelope envelope,
  }) async {
    final dek = await unlockEnvelope(
      accountId: accountId,
      passphrase: oldPassphrase,
      envelope: envelope,
    );
    _validate(accountId, newPassphrase, defaultIterations);
    final salt = _bytes(16), nonce = _bytes(12);
    return NotesKeyEnvelope(
      version: 1,
      iterations: defaultIterations,
      salt: salt,
      nonce: nonce,
      ciphertext: _crypt(
        true,
        dek,
        accountId,
        newPassphrase,
        defaultIterations,
        salt,
        nonce,
      ),
    );
  }

  Uint8List _crypt(
    bool encrypt,
    Uint8List input,
    String account,
    String password,
    int iterations,
    Uint8List salt,
    Uint8List nonce,
  ) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    final key = Uint8List(32)..fillRange(0, 32, 0);
    kdf.deriveKey(Uint8List.fromList(utf8.encode(password)), 0, key, 0);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(utf8.encode('varian-notes-envelope:v1:$account')),
        ),
      );
    return cipher.process(input);
  }

  Uint8List _bytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );
  void _validate(String account, String passphrase, int iterations) {
    if (account.isEmpty ||
        account.length > 256 ||
        passphrase.length < 12 ||
        utf8.encode(passphrase).length > 1024 ||
        iterations < minIterations ||
        iterations > maxIterations) {
      throw const NotesKeyException();
    }
  }
}
