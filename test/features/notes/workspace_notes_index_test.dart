import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_links.dart';
import 'package:varian/features/notes/domain/workspace_notes_index.dart';

void main() {
  final now = DateTime.utc(2026);

  WorkspaceNote note(
    String id,
    String title, {
    String ownerId = 'owner',
    String? projectId,
    String markdown = '',
    DateTime? deletedAt,
  }) => WorkspaceNote(
    id: id,
    ownerUserId: ownerId,
    projectId: projectId,
    title: title,
    markdownContent: markdown,
    createdAt: now,
    updatedAt: now,
    deletedAt: deletedAt,
  );

  test('searches active notes across title, Markdown, YAML and tags', () {
    final indexed = note(
      'a',
      'Planning',
      markdown: '---\nsummary: searchable-value\ntags: [project]\n---\n#weekly',
    );
    final deleted = note(
      'gone',
      'Planning archive',
      markdown: 'needle #archive',
      deletedAt: now,
    );
    final index = WorkspaceNotesIndex([indexed, deleted]);

    expect(index.search('PLAN'), [indexed]);
    expect(index.search('searchable-value'), [indexed]);
    expect(index.search('weekly'), [indexed]);
    expect(index.search('project'), [indexed]);
    expect(index.search('  '), [indexed]);
    expect(index.tags, ['project', 'weekly']);
  });

  test('backlinks resolve stable IDs and unique titles only once per source', () {
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    final target = note(targetId, 'Target');
    final marked = note(
      'marked',
      'Marked',
      markdown:
          '[[Old label]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000--> [[Target]]',
    );
    final legacy = note('legacy', 'Legacy', markdown: '[[tArGeT|T]]');
    final stale = note(
      'stale',
      'Stale',
      markdown:
          '[[Target]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174999-->',
    );
    final trashed = note(
      'trash',
      'Trash',
      markdown: '[[Target]]',
      deletedAt: now,
    );
    final index = WorkspaceNotesIndex([target, marked, legacy, stale, trashed]);

    expect(index.backlinksFor(targetId), [marked, legacy]);
  });

  test('resolves note aliases and indexes linked mentions', () {
    final target = note(
      'target',
      'Current title',
      markdown: '---\naliases: [Old title]\n---\nTarget body',
    );
    final linked = note('linked', 'Linked', markdown: '[[Old title]]');
    final mentioned = note(
      'mentioned',
      'Mentioned',
      markdown: 'The Old title appears here.',
    );
    final codeOnly = note(
      'code',
      'Code',
      markdown:
          '---\nsummary: Old title\n---\n`Old title`\n[link](https://example.test/Old%20title)',
    );
    final index = WorkspaceNotesIndex([target, linked, mentioned, codeOnly]);

    expect(index.backlinksFor('target'), [linked, mentioned]);
    expect(
      renderWorkspaceMarkdown(linked.markdownContent, [target], source: linked),
      contains('varian-note://target'),
    );
  });

  test('ambiguous aliases do not produce guessed backlinks or mentions', () {
    final first = note(
      'first',
      'First',
      markdown: '---\naliases: [Shared name]\n---\n',
    );
    final second = note(
      'second',
      'Second',
      markdown: '---\naliases: [Shared name]\n---\n',
    );
    final source = note('source', 'Source', markdown: 'Shared name appears.');
    final index = WorkspaceNotesIndex([first, second, source]);

    expect(index.backlinksFor('first'), isEmpty);
    expect(index.backlinksFor('second'), isEmpty);
  });

  test(
    'does not create linked mentions from frontmatter, code or destinations',
    () {
      final target = note(
        'target',
        'Target',
        markdown: '---\naliases: [Old title]\n---\nBody',
      );
      final source = note(
        'source',
        'Source',
        markdown:
            '---\nsummary: Old title\n---\n`Old title`\n[link](https://example.test/Old%20title)',
      );

      expect(
        WorkspaceNotesIndex([target, source]).backlinksFor('target'),
        isEmpty,
      );
    },
  );

  test('ambiguous title links do not produce guessed backlinks', () {
    const firstId = '123e4567-e89b-12d3-a456-426614174000';
    final first = note(firstId, 'Duplicate');
    final second = note('second', 'Duplicate');
    final source = note('source', 'Source', markdown: '[[Duplicate]]');
    final marked = note(
      'marked',
      'Marked',
      markdown:
          '[[Duplicate]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000-->',
    );
    final index = WorkspaceNotesIndex([first, second, source, marked]);

    expect(index.backlinksFor(firstId), [marked]);
    expect(index.backlinksFor('second'), isEmpty);
  });

  test(
    'graph preserves directed unique edges and includes optional isolates',
    () {
      final a = note('a', 'Alpha', markdown: '[[Beta]] [[Beta]] [[Alpha]]');
      final b = note('b', 'Beta', markdown: '[[Alpha]]');
      final isolated = note('c', 'Charlie');
      final deleted = note(
        'd',
        'Deleted',
        markdown: '[[Alpha]]',
        deletedAt: now,
      );
      final index = WorkspaceNotesIndex([a, b, isolated, deleted]);

      final linked = index.graph();
      expect(linked.nodes.map((node) => node.id), ['a', 'b']);
      expect(linked.edges.map((edge) => '${edge.sourceId}->${edge.targetId}'), [
        'a->a',
        'a->b',
        'b->a',
      ]);

      final all = index.graph(includeUnlinked: true);
      expect(all.nodes.map((node) => node.id), ['a', 'b', 'c']);
      expect(all.totalNodeCount, 3);
    },
  );

  test('graph applies AND tag filters and one-hop focus', () {
    final a = note(
      'a',
      'Alpha',
      markdown: '---\ntags: [one, two]\n---\n[[Beta]]',
    );
    final b = note('b', 'Beta', markdown: '---\ntags: [one]\n---\n[[Gamma]]');
    final c = note('c', 'Gamma', markdown: '---\ntags: [one, two]\n---');
    final d = note('d', 'Delta', markdown: '---\ntags: [two]\n---');
    final index = WorkspaceNotesIndex([a, b, c, d]);

    expect(
      index
          .graph(selectedTags: {'one', 'two'}, includeUnlinked: true)
          .nodes
          .map((node) => node.id),
      ['a', 'c'],
    );
    expect(
      index
          .graph(focusNoteId: 'b', includeUnlinked: true)
          .nodes
          .map((node) => node.id),
      ['b', 'a', 'c'],
    );
  });

  test('graph caps rendered nodes while reporting filtered total', () {
    final notes = List.generate(502, (i) => note('id-$i', 'Note $i'));
    final graph = WorkspaceNotesIndex(notes).graph(includeUnlinked: true);

    expect(graph.nodes, hasLength(500));
    expect(graph.totalNodeCount, 502);
    expect(graph.isCapped, isTrue);
    expect(
      graph.nodes.map((item) => item.title).toList(),
      [...graph.nodes.map((item) => item.title)].toList()..sort(),
    );
    expect(
      WorkspaceNotesIndex(notes).graph(limit: 0, includeUnlinked: true).nodes,
      isEmpty,
    );
    expect(
      WorkspaceNotesIndex(
        notes,
      ).graph(limit: 0, includeUnlinked: true).totalNodeCount,
      502,
    );
    expect(
      WorkspaceNotesIndex(notes).graph(limit: 600, includeUnlinked: true).nodes,
      hasLength(500),
    );
  });

  test('rename rewrites marked and uniquely resolved links only', () {
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    final target = note(targetId, 'Target');
    final marked = note(
      'marked',
      'Marked',
      markdown:
          'prefix [[stale label|alias]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000--> suffix `[[Target]]`',
    );
    final legacy = note(
      'legacy',
      'Legacy',
      markdown: '[[ Target ]] and [[Target|T]]',
    );
    final unrelated = note('unrelated', 'Unrelated', markdown: 'no links');
    final plan = planWorkspaceNoteRename(
      activeNotes: [target, marked, legacy, unrelated],
      targetId: targetId,
      requestedTitle: '  Renamed  ',
    );

    expect(plan.markdownReplacements, {
      'marked':
          'prefix [[Renamed|alias]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000--> suffix `[[Target]]`',
      'legacy': '[[ Renamed ]] and [[Renamed|T]]',
    });
    expect(plan.ambiguousSourceIds, isEmpty);
    expect(target.title, 'Target');
  });

  test('rename reports ambiguous legacy sources but rewrites marked links', () {
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    final target = note(targetId, 'Duplicate');
    final other = note('other', 'Duplicate');
    final source = note(
      'source',
      'Source',
      markdown:
          '[[Duplicate]] [[old|alias]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000-->',
    );
    final plan = planWorkspaceNoteRename(
      activeNotes: [target, other, source],
      targetId: targetId,
      requestedTitle: 'New name',
    );

    expect(plan.ambiguousSourceIds, {'source'});
    expect(plan.markdownReplacements, {
      'source':
          '[[Duplicate]] [[New name|alias]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000-->',
    });
  });

  test('rename de-duplicates self-links and omits unchanged bodies', () {
    final target = note(
      'target',
      'Target',
      markdown:
          '[[Target]] [[Other]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174111-->',
    );
    final plan = planWorkspaceNoteRename(
      activeNotes: [target],
      targetId: 'target',
      requestedTitle: 'Next',
    );

    expect(plan.markdownReplacements, {
      'target':
          '[[Next]] [[Other]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174111-->',
    });
  });

  test('rename rejects missing targets and blank titles', () {
    expect(
      () => planWorkspaceNoteRename(
        activeNotes: [],
        targetId: 'missing',
        requestedTitle: 'Title',
      ),
      throwsArgumentError,
    );
    expect(
      () => planWorkspaceNoteRename(
        activeNotes: [note('target', 'Target')],
        targetId: 'target',
        requestedTitle: '  ',
      ),
      throwsArgumentError,
    );
  });

  test('links, backlinks, graph and rename stay within note scope', () {
    const targetId = '123e4567-e89b-12d3-a456-426614174000';
    final target = note(targetId, 'Target', projectId: 'project-a');
    final sameProject = note(
      'same-project',
      'Same project source',
      projectId: 'project-a',
      markdown: '[[Target]]',
    );
    final otherProject = note(
      'other-project',
      'Other project source',
      projectId: 'project-b',
      markdown:
          '[[Target]]<!--varian-note-id:123e4567-e89b-12d3-a456-426614174000-->',
    );
    final privateNote = note(
      'private',
      'Private source',
      ownerId: 'another-owner',
      markdown: '[[Target]]',
    );
    final notes = [target, sameProject, otherProject, privateNote];
    final index = WorkspaceNotesIndex(notes);

    expect(index.backlinksFor(targetId), [sameProject]);
    expect(
      index.graph().edges.map((edge) => '${edge.sourceId}->${edge.targetId}'),
      ['same-project->$targetId'],
    );
    final rename = planWorkspaceNoteRename(
      activeNotes: notes,
      targetId: targetId,
      requestedTitle: 'Renamed',
    );
    expect(rename.markdownReplacements.keys, {'same-project'});
  });
}
