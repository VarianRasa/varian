import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/note_archive_manifest.dart';

Uint8List _manifest(Map<String, Object?> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

Map<String, Object?> _validManifest({
  List<Map<String, Object?>>? notes,
  Object? schemaVersion = 1,
}) => {
  'format': 'varian-notes',
  'schemaVersion': schemaVersion,
  'notes':
      notes ??
      [
        {
          'id': '123e4567-e89b-42d3-a456-426614174000',
          'path': 'Journal/first-note.md',
          'title': 'First note',
          'folder': 'Journal',
        },
      ],
};

void main() {
  test('parses manifest v1 fields without owner identifiers', () {
    final manifest = NoteArchiveManifest.parse(_manifest(_validManifest()));
    final entry = manifest.notes.single;

    expect(manifest.format, 'varian-notes');
    expect(manifest.schemaVersion, 1);
    expect(entry.sourceId, '123e4567-e89b-42d3-a456-426614174000');
    expect(entry.path, 'Journal/first-note.md');
    expect(entry.title, 'First note');
    expect(entry.folderPath, 'Journal');
  });

  test('rejects unsupported versions and malformed JSON', () {
    expect(
      () => NoteArchiveManifest.parse(
        _manifest(_validManifest(schemaVersion: 2)),
      ),
      throwsA(isA<NoteArchiveManifestException>()),
    );
    expect(
      () => NoteArchiveManifest.parse(
        _manifest(_validManifest(schemaVersion: 1.0)),
      ),
      throwsA(isA<NoteArchiveManifestException>()),
    );
    expect(
      () => NoteArchiveManifest.parse(Uint8List.fromList([0xff, 0xfe])),
      throwsA(isA<NoteArchiveManifestException>()),
    );
  });

  test('rejects duplicate source IDs and duplicate paths', () {
    final first = _validManifest()['notes'] as List<Map<String, Object?>>;
    final entry = first.single;
    expect(
      () => NoteArchiveManifest.parse(
        _manifest(
          _validManifest(
            notes: [
              entry,
              {...entry, 'path': 'other.md'},
            ],
          ),
        ),
      ),
      throwsA(isA<NoteArchiveManifestException>()),
    );
    expect(
      () => NoteArchiveManifest.parse(
        _manifest(
          _validManifest(
            notes: [
              entry,
              {...entry, 'id': '123e4567-e89b-42d3-a456-426614174001'},
            ],
          ),
        ),
      ),
      throwsA(isA<NoteArchiveManifestException>()),
    );
  });

  test('rejects traversal, absolute paths and missing titles', () {
    final entry =
        (_validManifest()['notes'] as List<Map<String, Object?>>).single;
    for (final path in [
      '../outside.md',
      '/absolute.md',
      r'C:\outside.md',
      'a\\..\\b.md',
    ]) {
      expect(
        () => NoteArchiveManifest.parse(
          _manifest(
            _validManifest(
              notes: [
                {...entry, 'path': path},
              ],
            ),
          ),
        ),
        throwsA(isA<NoteArchiveManifestException>()),
      );
    }
    expect(
      () => NoteArchiveManifest.parse(
        _manifest(
          _validManifest(
            notes: [
              {...entry}..remove('title'),
            ],
          ),
        ),
      ),
      throwsA(isA<NoteArchiveManifestException>()),
    );
  });
}
