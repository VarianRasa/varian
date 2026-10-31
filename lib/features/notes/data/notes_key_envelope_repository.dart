import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'notes_key_manager.dart';

class NotesKeyEnvelopeRepository {
  const NotesKeyEnvelopeRepository(this.client);
  final SupabaseClient client;

  Future<NotesKeyEnvelope?> get(String accountId) async {
    _requireAccount(accountId);
    final row = await client
        .from('workspace_note_key_envelopes')
        .select('version,kdf_iterations,salt,nonce,wrapped_key')
        .eq('owner_user_id', accountId)
        .maybeSingle();
    _requireAccount(accountId);
    if (row == null) return null;
    return NotesKeyEnvelope(
      version: (row['version'] as num).toInt(),
      iterations: (row['kdf_iterations'] as num).toInt(),
      salt: decodeBytea(row['salt']),
      nonce: decodeBytea(row['nonce']),
      ciphertext: decodeBytea(row['wrapped_key']),
    );
  }

  Future<void> save(String accountId, NotesKeyEnvelope envelope) async {
    _requireAccount(accountId);
    if (envelope.version != 1 ||
        envelope.salt.length != 16 ||
        envelope.nonce.length != 12 ||
        envelope.ciphertext.length != 48 ||
        envelope.iterations < NotesKeyManager.minIterations ||
        envelope.iterations > NotesKeyManager.maxIterations) {
      throw const NotesKeyException();
    }
    await client.from('workspace_note_key_envelopes').upsert({
      'owner_user_id': accountId,
      'version': envelope.version,
      'kdf_iterations': envelope.iterations,
      'salt': encodeBytea(envelope.salt),
      'nonce': encodeBytea(envelope.nonce),
      'wrapped_key': encodeBytea(envelope.ciphertext),
    }, onConflict: 'owner_user_id');
    _requireAccount(accountId);
  }

  void _requireAccount(String accountId) {
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous || user.id != accountId) {
      throw StateError('Notes account changed during recovery.');
    }
  }

  static String encodeBytea(Uint8List bytes) =>
      '\\x${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';

  static Uint8List decodeBytea(Object? value) {
    if (value is! String || !value.startsWith(r'\x') || value.length % 2 != 0) {
      throw const NotesKeyException();
    }
    final hex = value.substring(2);
    if (hex.length.isOdd) throw const NotesKeyException();
    final bytes = <int>[];
    for (var offset = 0; offset < hex.length; offset += 2) {
      final byte = int.tryParse(hex.substring(offset, offset + 2), radix: 16);
      if (byte == null) throw const NotesKeyException();
      bytes.add(byte);
    }
    return Uint8List.fromList(bytes);
  }
}
