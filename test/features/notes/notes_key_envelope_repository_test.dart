import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_key_envelope_repository.dart';
import 'package:varian/features/notes/data/notes_key_manager.dart';

void main() {
  test('encodes Postgres bytea as hex and round-trips it', () {
    final bytes = Uint8List.fromList([0, 1, 15, 16, 127, 255]);
    final encoded = NotesKeyEnvelopeRepository.encodeBytea(bytes);

    expect(encoded, r'\x00010f107fff');
    expect(NotesKeyEnvelopeRepository.decodeBytea(encoded), bytes);
  });

  test('rejects malformed or non-hex bytea values', () {
    for (final value in [null, '0000', r'\x0', r'\x00xz']) {
      expect(
        () => NotesKeyEnvelopeRepository.decodeBytea(value),
        throwsA(isA<NotesKeyException>()),
      );
    }
  });
}
