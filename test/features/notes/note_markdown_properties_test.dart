import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/note_markdown_metadata.dart';
import 'package:varian/features/notes/domain/note_markdown_properties.dart';

void main() {
  group('setNoteMarkdownProperty', () {
    test(
      'updates one property and preserves comments, other values, and body',
      () {
        const source =
            '---\r\n'
            '# keep header comment\r\n'
            'title: "Old" # keep title comment\r\n'
            'tags:\r\n'
            '  - old # keep list comment\r\n'
            'unknown: {nested: [1, 2]}\r\n'
            '---\r\n'
            'Body\r\n'
            'with exact CRLF';

        final updated = setNoteMarkdownProperty(
          source,
          key: 'tags',
          type: NotePropertyType.tags,
          value: ['new', 'two'],
        );
        final metadata = parseNoteMarkdownMetadata(updated);

        expect(metadata.parseError, isNull);
        expect((metadata.yaml as Map)['tags'], ['new', 'two']);
        expect((metadata.yaml as Map)['unknown'], {
          'nested': [1, 2],
        });
        expect(updated, contains('# keep header comment\r\n'));
        expect(updated, contains('# keep title comment'));
        expect(updated, contains('# keep list comment'));
        expect(updated, endsWith('---\r\nBody\r\nwith exact CRLF'));
      },
    );

    test('writes each approved property type without changing the body', () {
      const source = '---\n---\nBody stays exact\n';
      final timestamp = DateTime.parse('2026-10-21T14:30:00+02:00');
      var updated = setNoteMarkdownProperty(
        source,
        key: 'title',
        type: NotePropertyType.text,
        value: '2026-10-21',
      );
      expect(
        parseNoteMarkdownMetadata(updated).parseError,
        isNull,
        reason: updated,
      );
      updated = setNoteMarkdownProperty(
        updated,
        key: 'items',
        type: NotePropertyType.list,
        value: ['01', 'true', 'text'],
      );
      expect(
        parseNoteMarkdownMetadata(updated).parseError,
        isNull,
        reason: updated,
      );
      updated = setNoteMarkdownProperty(
        updated,
        key: 'rank',
        type: NotePropertyType.number,
        value: 3.5,
      );
      updated = setNoteMarkdownProperty(
        updated,
        key: 'done',
        type: NotePropertyType.checkbox,
        value: true,
      );
      updated = setNoteMarkdownProperty(
        updated,
        key: 'when',
        type: NotePropertyType.dateTime,
        value: timestamp,
      );
      updated = setNoteMarkdownProperty(
        updated,
        key: 'tags',
        type: NotePropertyType.tags,
        value: ['notes', 'design'],
      );
      updated = setNoteMarkdownProperty(
        updated,
        key: 'aliases',
        type: NotePropertyType.aliases,
        value: ['Draft', 'Project Notes'],
      );

      final metadata = parseNoteMarkdownMetadata(updated);
      final properties = metadata.yaml as Map;
      expect(metadata.parseError, isNull);
      expect(properties['title'], '2026-10-21');
      expect(properties['items'], ['01', 'true', 'text']);
      expect(properties['rank'], 3.5);
      expect(properties['done'], isTrue);
      expect(properties['when'], timestamp.toUtc());
      expect(properties['tags'], ['notes', 'design']);
      expect(properties['aliases'], ['Draft', 'Project Notes']);
      expect(metadata.body, 'Body stays exact\n');
    });

    test('keeps date-time properties distinguishable from text values', () {
      const source = '---\nwhen: "2024-01-01T00:00:00.000Z"\n---\nBody';
      final timestamp = DateTime.parse('2026-10-21T12:30:00.000Z');
      final updated = setNoteMarkdownProperty(
        source,
        key: 'when',
        type: NotePropertyType.dateTime,
        value: timestamp,
      );
      final metadata = parseNoteMarkdownMetadata(updated);

      expect(metadata.parseError, isNull);
      expect((metadata.yaml as Map)['when'], timestamp);
      expect(updated, contains('when: 2026-10-21T12:30:00.000Z'));
    });

    test('adds frontmatter to a note that has none', () {
      const source = 'Body\r\nwith exact CRLF';
      final updated = setNoteMarkdownProperty(
        source,
        key: 'title',
        type: NotePropertyType.text,
        value: 'A title',
      );
      final metadata = parseNoteMarkdownMetadata(updated);

      expect(metadata.parseError, isNull);
      expect((metadata.yaml as Map)['title'], 'A title');
      expect(metadata.body, source);
      expect(updated, contains('\r\n'));
    });

    test('refuses to edit invalid frontmatter', () {
      const source = '---\ntags: [broken\n---\nBody';

      expect(
        () => setNoteMarkdownProperty(
          source,
          key: 'title',
          type: NotePropertyType.text,
          value: 'A title',
        ),
        throwsFormatException,
      );
      expect(source, '---\ntags: [broken\n---\nBody');
    });

    test('rejects values that do not match the selected type', () {
      expect(
        () => setNoteMarkdownProperty(
          '---\ntitle: old\n---\nBody',
          key: 'done',
          type: NotePropertyType.checkbox,
          value: 'true',
        ),
        throwsArgumentError,
      );
      expect(
        () => setNoteMarkdownProperty(
          '---\ntitle: old\n---\nBody',
          key: 'rank',
          type: NotePropertyType.number,
          value: double.nan,
        ),
        throwsArgumentError,
      );
    });
  });

  group('removeNoteMarkdownProperty', () {
    test(
      'removes one key and keeps unrelated comments, properties, and body',
      () {
        const source =
            '---\n'
            '# header comment\n'
            'title: "A title"\n'
            'unknown: keep\n'
            '# trailing comment\n'
            '---\n'
            'Body';
        final updated = removeNoteMarkdownProperty(source, key: 'title');
        final metadata = parseNoteMarkdownMetadata(updated);

        expect(metadata.parseError, isNull);
        expect((metadata.yaml as Map).containsKey('title'), isFalse);
        expect((metadata.yaml as Map)['unknown'], 'keep');
        expect(updated, contains('# header comment'));
        expect(updated, contains('# trailing comment'));
        expect(metadata.body, 'Body');
      },
    );

    test('keeps comment-only frontmatter valid when removing its last key', () {
      const source = '---\nvalue: old\n# keep this comment\n---\nBody';
      final updated = removeNoteMarkdownProperty(source, key: 'value');
      final metadata = parseNoteMarkdownMetadata(updated);

      expect(metadata.parseError, isNull);
      expect(metadata.yaml, isA<Map>());
      expect(updated, contains('# keep this comment'));
      expect(metadata.body, 'Body');
    });
  });
}
