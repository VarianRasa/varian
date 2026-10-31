import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_import_service.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';

final class _MemoryPlatformFile extends PlatformFile {
  _MemoryPlatformFile(this.name, this._bytes);

  @override
  final String name;
  final Uint8List _bytes;

  @override
  Uri get uri => Uri.parse('memory:///$name');

  @override
  XFile get xFile => XFile.fromData(_bytes, name: name);

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

PlatformFile _file(String name, String contents) =>
    _MemoryPlatformFile(name, Uint8List.fromList(utf8.encode(contents)));

Uint8List _zip(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _replaceAscii(Uint8List bytes, String from, String to) {
  final result = Uint8List.fromList(bytes);
  final source = ascii.encode(from);
  final replacement = ascii.encode(to);
  if (source.length != replacement.length) {
    throw ArgumentError('Replacement names must have equal byte lengths.');
  }
  for (var i = 0; i <= result.length - source.length; i++) {
    var matches = true;
    for (var j = 0; j < source.length; j++) {
      if (result[i + j] != source[j]) {
        matches = false;
        break;
      }
    }
    if (!matches) continue;
    result.setRange(i, i + source.length, replacement);
    i += source.length - 1;
  }
  return result;
}

WorkspaceNote _existing(String title) => WorkspaceNote(
  id: 'existing-note',
  ownerUserId: 'owner-a',
  title: title,
  markdownContent: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test(
    'prepares Markdown files with fresh IDs and flags title collisions',
    () async {
      final preview = await NotesImportService().prepare(
        files: [_file('Meeting.md', '---\ntitle: Meeting\n---\nBody')],
        existingNotes: [_existing('Meeting')],
      );

      expect(preview.notes, hasLength(1));
      expect(preview.notes.single.title, 'Meeting');
      expect(preview.notes.single.markdown, '---\ntitle: Meeting\n---\nBody');
      expect(preview.notes.single.newId, isNotEmpty);
      expect(preview.notes.single.duplicateTitle, isTrue);
    },
  );

  test('remaps only manifest-known internal ID markers', () async {
    final sourceId = '123e4567-e89b-42d3-a456-426614174000';
    final secondSourceId = '123e4567-e89b-42d3-a456-426614174001';
    final unknownId = '123e4567-e89b-42d3-a456-426614174099';
    final manifest = jsonEncode({
      'format': 'varian-notes',
      'schemaVersion': 1,
      'notes': [
        {'id': sourceId, 'path': 'first.md', 'title': 'First'},
        {'id': secondSourceId, 'path': 'second.md', 'title': 'Second'},
      ],
    });
    final preview = await NotesImportService().prepare(
      files: [
        _file('manifest.json', manifest),
        _file('first.md', 'first note'),
        _file(
          'second.md',
          '[[First]]<!--varian-note-id:$sourceId-->\n'
              '[[Unknown]]<!--varian-note-id:$unknownId-->',
        ),
      ],
      existingNotes: const [],
    );

    final importedFirst = preview.notes.firstWhere(
      (note) => note.sourceId == sourceId,
    );
    final importedSecond = preview.notes.firstWhere(
      (note) => note.sourceId == secondSourceId,
    );
    expect(
      importedSecond.markdown,
      contains('<!--varian-note-id:${importedFirst.newId}-->'),
    );
    expect(
      importedSecond.markdown,
      contains('<!--varian-note-id:$unknownId-->'),
    );
    expect(importedFirst.newId, isNot(sourceId));
    expect(importedSecond.newId, isNot(secondSourceId));
  });

  test(
    'preserves standalone Markdown bytes and reports duplicate outcome',
    () async {
      const markdown = '\ufeff---\ncreated: 2024-01-01\n---\n\nExact  \n';
      final preview = await NotesImportService().prepare(
        files: [_file('exact.md', markdown)],
        existingNotes: [_existing('exact')],
      );

      expect(preview.notes.single.markdown, markdown);
      expect(preview.notes.single.duplicateTitle, isTrue);
    },
  );

  test(
    'rejects unsupported, empty, and oversized inputs before preview',
    () async {
      await expectLater(
        NotesImportService().prepare(
          files: [_file('unsupported.txt', 'text')],
          existingNotes: const [],
        ),
        throwsA(isA<NotesImportException>()),
      );
      await expectLater(
        NotesImportService().prepare(files: [], existingNotes: const []),
        throwsA(isA<NotesImportException>()),
      );
      await expectLater(
        NotesImportService().prepare(
          files: List.generate(101, (index) => _file('$index.md', 'body')),
          existingNotes: const [],
        ),
        throwsA(isA<NotesImportException>()),
      );
      final aggregateChunk = Uint8List(9 * 1024 * 1024);
      await expectLater(
        NotesImportService().prepare(
          files: List.generate(
            3,
            (index) => _MemoryPlatformFile('$index.md', aggregateChunk),
          ),
          existingNotes: const [],
        ),
        throwsA(isA<NotesImportException>()),
      );
      final oversized = Uint8List(10 * 1024 * 1024 + 1);
      await expectLater(
        NotesImportService().prepare(
          files: [_MemoryPlatformFile('large.md', oversized)],
          existingNotes: const [],
        ),
        throwsA(isA<NotesImportException>()),
      );
    },
  );

  test('ZIP preflight rejects traversal and absolute paths', () async {
    for (final path in ['../outside.md', '/absolute.md', r'C:\\outside.md']) {
      final bytes = _zip({path: utf8.encode('unsafe')});
      await expectLater(
        NotesImportService().decodeSelection(
          files: [_MemoryPlatformFile('bundle.zip', bytes)],
          existingNotes: const [],
        ),
        throwsA(isA<NotesImportException>()),
      );
    }
  });

  test(
    'ZIP preflight detects duplicate entries before decoding content',
    () async {
      final encoded = _zip({
        'first.md': utf8.encode('one'),
        'other.md': utf8.encode('two'),
      });
      final duplicate = _replaceAscii(encoded, 'other.md', 'first.md');

      await expectLater(
        NotesImportService().decodeSelection(
          files: [_MemoryPlatformFile('bundle.zip', duplicate)],
          existingNotes: const [],
        ),
        throwsA(isA<NotesImportException>()),
      );
    },
  );

  test(
    'duplicate title decisions rename or skip without overwriting',
    () async {
      final preview = await NotesImportService().prepare(
        files: [_file('A.md', 'first'), _file('folder/A.md', 'second')],
        existingNotes: const [],
      );
      final duplicate = preview.notes.singleWhere(
        (note) => note.duplicateTitle,
      );

      final renamed = preview.resolveDuplicateTitles(
        renamedTitles: {duplicate.newId: 'A copy'},
      );
      expect(renamed, hasLength(2));
      expect(renamed.last.title, 'A copy');
      expect(
        preview.resolveDuplicateTitles(skippedNoteIds: {duplicate.newId}),
        hasLength(1),
      );
      expect(
        () => preview.resolveDuplicateTitles(),
        throwsA(isA<NotesImportException>()),
      );
    },
  );

  test('ZIP preflight rejects malformed entries and Markdown bytes', () async {
    await expectLater(
      NotesImportService().decodeSelection(
        files: [
          _MemoryPlatformFile('broken.zip', Uint8List.fromList([1, 2, 3])),
        ],
        existingNotes: const [],
      ),
      throwsA(isA<NotesImportException>()),
    );
    await expectLater(
      NotesImportService().decodeSelection(
        files: [
          _MemoryPlatformFile(
            'bad-note.zip',
            _zip({
              'bad.md': [0xff],
            }),
          ),
        ],
        existingNotes: const [],
      ),
      throwsA(isA<NotesImportException>()),
    );
  });
}
