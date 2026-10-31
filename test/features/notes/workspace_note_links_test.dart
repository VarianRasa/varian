import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_links.dart';

void main() {
  final now = DateTime.utc(2026);
  WorkspaceNote note(
    String id,
    String title, {
    String ownerId = 'owner',
    String? projectId,
    String markdown = '',
  }) => WorkspaceNote(
    id: id,
    ownerUserId: ownerId,
    projectId: projectId,
    title: title,
    markdownContent: markdown,
    createdAt: now,
    updatedAt: now,
  );

  test('parses exact UTF-16 ranges, aliases and valid UUID markers', () {
    const source =
        'x [[Café|label]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000-->';
    final links = parseWorkspaceWikiLinks(source);
    expect(links, hasLength(1));
    expect(
      source.substring(links.single.start, links.single.end),
      '[[Café|label]]',
    );
    expect(links.single.title, 'Café');
    expect(links.single.alias, 'label');
    expect(links.single.targetId, '123e4567-e89b-12d3-a456-426614174000');
    expect(links.single.markerValid, isTrue);
  });

  test('parses heading and case-sensitive block link fragments', () {
    final links = parseWorkspaceWikiLinks(
      '[[Target#Some Heading!]] [[Target#^BlockA|jump]]',
    );

    expect(links, hasLength(2));
    expect(links[0].title, 'Target');
    expect(links[0].headingSlug, 'some-heading');
    expect(links[0].blockId, isNull);
    expect(links[1].title, 'Target');
    expect(links[1].headingSlug, isNull);
    expect(links[1].blockId, 'BlockA');
    expect(links[1].alias, 'jump');
  });

  test('renders note links with heading and block fragments', () {
    final target = note(
      'target',
      'Target',
      markdown: '# Some Heading\\nParagraph ^BlockA',
    );
    final rendered = renderWorkspaceMarkdown(
      '[[Target#Some Heading]] [[Target#^BlockA|block]]',
      [target],
    );

    expect(rendered, contains('varian-note://target#some-heading'));
    expect(rendered, contains('varian-note://target#%5EBlockA'));
  });

  test('extracts stable heading and explicit block anchors', () {
    const source =
        '---\nheading: ignored\n---\n'
        '# Café: Plan!\n'
        '# Café Plan\n'
        'paragraph ^BlockA\n'
        'paragraph ^BlockA\n'
        'paragraph ^Unique';
    final anchors = parseWorkspaceNoteAnchors(source);

    expect(anchors.map((anchor) => anchor.id), [
      'café-plan',
      'café-plan-1',
      'BlockA',
      'BlockA',
      'Unique',
    ]);
    expect(
      resolveWorkspaceNoteAnchor(source, 'café-plan-1')?.id,
      'café-plan-1',
    );
    expect(resolveWorkspaceNoteAnchor(source, '^BlockA'), isNull);
    expect(resolveWorkspaceNoteAnchor(source, '^Unique')?.id, 'Unique');
  });

  test('valid marker with absent active target does not title-fallback', () {
    const source =
        '[[Target]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000-->';
    final rendered = renderWorkspaceMarkdown(source, [
      note('other-id', 'Target'),
    ]);
    expect(rendered, '[[Target]]');
    expect(rendered, isNot(contains('varian-note://')));
  });

  test('matches inline backtick run lengths and fenced delimiter lengths', () {
    const source =
        '`unmatched [[Visible]]\n``[[Hidden]] `` [[VisibleToo]]\n````\n[[HiddenFence]]\n```\n[[StillHidden]]\n````\n~~~\n[[TildeHidden]]\n~~~';
    expect(parseWorkspaceWikiLinks(source).map((link) => link.title), [
      'Visible',
      'VisibleToo',
    ]);
  });

  test('ignores wiki links inside multiline inline code spans', () {
    const source = '`[[Hidden]]\ncontinued` [[Visible]]';
    expect(parseWorkspaceWikiLinks(source).map((link) => link.title), [
      'Visible',
    ]);
  });

  test('invalid, duplicate and separated markers do not bind', () {
    for (final source in [
      '[[A]] <!--varian-note-id:123e4567-e89b-12d3-a456-426614174000-->',
      '[[A]]<!--varian-note-id:123E4567-e89b-12d3-a456-426614174000-->',
      '[[A]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000--><!--varian-note-id:123e4567-e89b-12d3-a456-426614174000-->',
    ]) {
      final link = parseWorkspaceWikiLinks(source).single;
      expect(link.markerValid, isFalse);
      expect(link.targetId, isNull);
    }
  });

  test('ignores valid fenced and inline code, resolves titles', () {
    final notes = [note('1', 'Target'), note('2', 'Other'), note('3', 'Other')];
    const source =
        '`[[Target]]`\n```\n[[Other]]\n```\n[[tArGeT]] [[Other]] [[Missing]]';
    final links = parseWorkspaceWikiLinks(source);
    expect(links.map((link) => link.title), ['tArGeT', 'Other', 'Missing']);
    final rendered = renderWorkspaceMarkdown(source, notes);
    expect(rendered, contains('varian-note://1'));
    expect(rendered, contains('[[Other]]'));
    expect(rendered, contains('[[Missing]]'));
  });

  test('renders links only within the same private owner or project', () {
    final privateSource = note(
      'private-source',
      'Private source',
      ownerId: 'owner-a',
      markdown: '[[Private]]',
    );
    final privateRendered =
        renderWorkspaceMarkdown(privateSource.markdownContent, [
          note('private-same', 'Private', ownerId: 'owner-a'),
          note('private-other', 'Private', ownerId: 'owner-b'),
        ], source: privateSource);
    final projectSource = note(
      'project-source',
      'Project source',
      markdown: '[[Project]] [[Other project]]',
      projectId: 'p1',
    );
    final projectRendered =
        renderWorkspaceMarkdown(projectSource.markdownContent, [
          note('project-same', 'Project', ownerId: 'owner-b', projectId: 'p1'),
          note('project-other', 'Other project', projectId: 'p2'),
        ], source: projectSource);

    expect(privateRendered, contains('varian-note://private-same'));
    expect(privateRendered, isNot(contains('private-other')));
    expect(projectRendered, contains('varian-note://project-same'));
    expect(projectRendered, contains('[[Other project]]'));
  });
}
