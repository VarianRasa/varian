import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/note_markdown_metadata.dart';

void main() {
  test('parses full YAML and preserves frontmatter and body', () {
    const source =
        '---\ntags: [one, two]\nnested:\n  value: 42\n---\n# Heading\n#body';
    final metadata = parseNoteMarkdownMetadata(source);
    expect(metadata.frontmatterRaw, 'tags: [one, two]\nnested:\n  value: 42');
    expect(metadata.body, '# Heading\n#body');
    expect(metadata.yaml, {
      'tags': ['one', 'two'],
      'nested': {'value': 42},
    });
    expect(metadata.tags, containsAll(['one', 'two', 'body']));
    expect(metadata.searchableValues, contains('42'));
  });

  test('preserves LF and CRLF frontmatter and body bytes exactly', () {
    for (final newline in ['\n', '\r\n']) {
      final source = [
        '---',
        'title: Café',
        'tags: [one]',
        '---',
        'Body',
        'tail',
      ].join(newline);
      final parsed = parseNoteMarkdownMetadata(source);
      expect(
        parsed.frontmatterRaw,
        ['title: Café', 'tags: [one]'].join(newline),
      );
      expect(parsed.body, ['Body', 'tail'].join(newline));
      expect(
        source,
        '---$newline${parsed.frontmatterRaw}$newline---$newline${parsed.body}',
      );
    }
  });

  test('handles absent, open, invalid and non-map frontmatter intact', () {
    final absent = parseNoteMarkdownMetadata('plain #tag');
    expect(absent.frontmatterRaw, isNull);
    expect(absent.body, 'plain #tag');
    expect(absent.tags, contains('tag'));
    const invalidClosed = '---\ntags: [broken\n---\nbody';
    final invalid = parseNoteMarkdownMetadata(invalidClosed);
    expect(invalid.frontmatterRaw, 'tags: [broken');
    expect(invalid.body, 'body');
    expect(invalid.parseError, isNotNull);
    expect(invalid.searchableValues, contains(invalid.frontmatterRaw));

    const nonMap = '---\n- item\n---\nbody';
    final rootList = parseNoteMarkdownMetadata(nonMap);
    expect(rootList.body, 'body');
    expect(rootList.parseError, isNotNull);

    const unclosed = '---\ntags: [broken\nbody';
    final open = parseNoteMarkdownMetadata(unclosed);
    expect(open.frontmatterRaw, unclosed.substring(4));
    expect(open.body, unclosed);
    expect(open.parseError, isNotNull);
    expect(open.searchableValues, contains(unclosed));
  });

  test('matches inline backtick run lengths and fence delimiters', () {
    final parsed = parseNoteMarkdownMetadata(
      '`unmatched #visible\n``#hidden `` #visibleToo\n````\n#hiddenFence\n```\n#stillHidden\n````\n~~~\n#tildeHidden\n~~~',
    );
    expect(parsed.tags, containsAll(['visible', 'visibleToo']));
    expect(parsed.tags, isNot(contains('hidden')));
    expect(parsed.tags, isNot(contains('stillHidden')));
    expect(parsed.tags, isNot(contains('tildeHidden')));
  });

  test('ignores hashtags in inline and fenced code', () {
    final parsed = parseNoteMarkdownMetadata(
      'real #yes `#no`\n```\n#hidden\n```\n`#multiLineHidden\ncontinued #alsoHidden` #outside',
    );
    expect(parsed.tags, contains('yes'));
    expect(parsed.tags, isNot(contains('no')));
    expect(parsed.tags, isNot(contains('hidden')));
    expect(parsed.tags, isNot(contains('multiLineHidden')));
    expect(parsed.tags, isNot(contains('alsoHidden')));
    expect(parsed.tags, contains('outside'));
  });
}
