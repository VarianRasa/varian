import 'note_markdown_metadata.dart';
import 'workspace_note.dart';
import 'workspace_note_links.dart';

class WorkspaceNotesGraphEdge {
  const WorkspaceNotesGraphEdge({
    required this.sourceId,
    required this.targetId,
  });

  final String sourceId;
  final String targetId;
}

class WorkspaceNotesGraph {
  WorkspaceNotesGraph({
    required Iterable<WorkspaceNote> nodes,
    required Iterable<WorkspaceNotesGraphEdge> edges,
    required this.totalNodeCount,
  }) : nodes = List.unmodifiable(nodes),
       edges = List.unmodifiable(edges);

  final List<WorkspaceNote> nodes;
  final List<WorkspaceNotesGraphEdge> edges;
  final int totalNodeCount;

  bool get isCapped => totalNodeCount > nodes.length;
}

class WorkspaceNoteRenamePlan {
  WorkspaceNoteRenamePlan({
    required Map<String, String> markdownReplacements,
    required Set<String> ambiguousSourceIds,
  }) : markdownReplacements = Map.unmodifiable(markdownReplacements),
       ambiguousSourceIds = Set.unmodifiable(ambiguousSourceIds);

  final Map<String, String> markdownReplacements;
  final Set<String> ambiguousSourceIds;
}

class WorkspaceNotesIndex {
  WorkspaceNotesIndex(List<WorkspaceNote> activeNotes)
    : _notes = List.unmodifiable(
        activeNotes.where((note) => note.deletedAt == null),
      ),
      _metadata = Map.unmodifiable({
        for (final note in activeNotes.where((note) => note.deletedAt == null))
          note.id: parseNoteMarkdownMetadata(note.markdownContent),
      });

  final List<WorkspaceNote> _notes;
  final Map<String, NoteMarkdownMetadata> _metadata;

  List<String> get tags {
    final values = <String>{};
    for (final metadata in _metadata.values) {
      values.addAll(metadata.tags);
    }
    return List.unmodifiable(values.toList()..sort(_compareText));
  }

  List<WorkspaceNote> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return _notes;
    return List.unmodifiable(
      _notes.where((note) {
        if (note.title.toLowerCase().contains(needle)) return true;
        final metadata = _metadata[note.id]!;
        return metadata.searchableValues.any(
          (value) => value.toLowerCase().contains(needle),
        );
      }),
    );
  }

  List<WorkspaceNote> backlinksFor(String noteId) {
    final target = _notes.where((note) => note.id == noteId).toList();
    if (target.length != 1) return const [];
    final backlinks = <WorkspaceNote>[];
    for (final source in _notes) {
      final links = parseWorkspaceWikiLinks(source.markdownContent);
      final sharesScope = notesShareLinkScope(source, target.single);
      final linked = links.any((link) => _resolve(link, source)?.id == noteId);
      final mentioned =
          sharesScope && _hasUnambiguousMention(source, target.single);
      if (sharesScope && (linked || mentioned)) backlinks.add(source);
    }
    return List.unmodifiable(backlinks);
  }

  WorkspaceNotesGraph graph({
    String? focusNoteId,
    Set<String> selectedTags = const {},
    bool includeUnlinked = false,
    int limit = 500,
  }) {
    var candidates = _notes.where((note) {
      final noteTags = _metadata[note.id]!.tags;
      return selectedTags.isEmpty || selectedTags.every(noteTags.contains);
    }).toList();
    final candidateIds = candidates.map((note) => note.id).toSet();
    final edgeKeys = <String>{};
    final edges = <WorkspaceNotesGraphEdge>[];
    for (final source in candidates) {
      for (final link in parseWorkspaceWikiLinks(source.markdownContent)) {
        final target = _resolve(link, source);
        if (target == null || !candidateIds.contains(target.id)) continue;
        final key = '${source.id}\u0000${target.id}';
        if (edgeKeys.add(key)) {
          edges.add(
            WorkspaceNotesGraphEdge(sourceId: source.id, targetId: target.id),
          );
        }
      }
    }

    if (focusNoteId != null) {
      if (!candidateIds.contains(focusNoteId)) {
        candidates = [];
        edges.clear();
      } else {
        final focusedIds = <String>{focusNoteId};
        for (final edge in edges) {
          if (edge.sourceId == focusNoteId || edge.targetId == focusNoteId) {
            focusedIds
              ..add(edge.sourceId)
              ..add(edge.targetId);
          }
        }
        candidates = candidates
            .where((note) => focusedIds.contains(note.id))
            .toList();
        edges.removeWhere(
          (edge) =>
              !focusedIds.contains(edge.sourceId) ||
              !focusedIds.contains(edge.targetId),
        );
      }
    }

    if (!includeUnlinked) {
      final connected = <String>{};
      for (final edge in edges) {
        connected
          ..add(edge.sourceId)
          ..add(edge.targetId);
      }
      candidates.removeWhere((note) => !connected.contains(note.id));
    }

    candidates.sort((a, b) {
      if (focusNoteId != null) {
        if (a.id == focusNoteId && b.id != focusNoteId) return -1;
        if (b.id == focusNoteId && a.id != focusNoteId) return 1;
      }
      final byTitle = _compareText(a.title, b.title);
      return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
    });
    final totalNodeCount = candidates.length;
    final visibleLimit = limit < 0 ? 0 : (limit > 500 ? 500 : limit);
    final renderedNodes = candidates.take(visibleLimit).toList();
    final renderedIds = renderedNodes.map((note) => note.id).toSet();
    edges.sort((a, b) {
      final sourceOrder = a.sourceId.compareTo(b.sourceId);
      return sourceOrder != 0 ? sourceOrder : a.targetId.compareTo(b.targetId);
    });
    final renderedEdges = edges
        .where(
          (edge) =>
              renderedIds.contains(edge.sourceId) &&
              renderedIds.contains(edge.targetId),
        )
        .toList();
    return WorkspaceNotesGraph(
      nodes: renderedNodes,
      edges: renderedEdges,
      totalNodeCount: totalNodeCount,
    );
  }

  bool _hasUnambiguousMention(WorkspaceNote source, WorkspaceNote target) {
    for (final name in workspaceNoteNames(target)) {
      final matches = _notes
          .where(
            (note) =>
                notesShareLinkScope(source, note) &&
                workspaceNoteMatchesName(note, name),
          )
          .take(2)
          .toList();
      if (matches.length == 1 &&
          matches.single.id == target.id &&
          containsWorkspaceLinkedMention(source.markdownContent, [name])) {
        return true;
      }
    }
    return false;
  }

  WorkspaceNote? _resolve(WorkspaceWikiLink link, WorkspaceNote source) {
    if (link.markerValid) {
      for (final note in _notes) {
        if (note.id == link.targetId && notesShareLinkScope(source, note)) {
          return note;
        }
      }
      return null;
    }
    final matches = _notes
        .where(
          (note) =>
              workspaceNoteMatchesName(note, link.title) &&
              notesShareLinkScope(source, note),
        )
        .take(2)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }
}

WorkspaceNoteRenamePlan planWorkspaceNoteRename({
  required List<WorkspaceNote> activeNotes,
  required String targetId,
  required String requestedTitle,
}) {
  final title = requestedTitle.trim();
  if (title.isEmpty) {
    throw ArgumentError.value(
      requestedTitle,
      'requestedTitle',
      'Must not be empty.',
    );
  }
  final notes = activeNotes.where((note) => note.deletedAt == null).toList();
  final targets = notes.where((note) => note.id == targetId).toList();
  if (targets.length != 1) {
    throw ArgumentError.value(
      targetId,
      'targetId',
      'Must identify one active note.',
    );
  }
  final target = targets.single;
  final scopedNotes = notes
      .where((note) => notesShareLinkScope(target, note))
      .toList();
  final replacements = <String, String>{};
  final ambiguous = <String>{};
  for (final source in scopedNotes) {
    final links = parseWorkspaceWikiLinks(source.markdownContent);
    final output = StringBuffer();
    var cursor = 0;
    for (final link in links) {
      output.write(source.markdownContent.substring(cursor, link.start));
      final shouldRewrite = _linkTargetsNote(link, target, scopedNotes);
      if (shouldRewrite) {
        output.write(_replaceLinkTitle(source.markdownContent, link, title));
      } else {
        output.write(source.markdownContent.substring(link.start, link.end));
        if (!link.markerValid &&
            _ambiguousTargetLink(link, target, scopedNotes)) {
          ambiguous.add(source.id);
        }
      }
      cursor = link.end;
    }
    output.write(source.markdownContent.substring(cursor));
    final rewritten = output.toString();
    if (rewritten != source.markdownContent) {
      replacements[source.id] = rewritten;
    }
  }
  return WorkspaceNoteRenamePlan(
    markdownReplacements: replacements,
    ambiguousSourceIds: ambiguous,
  );
}

bool _linkTargetsNote(
  WorkspaceWikiLink link,
  WorkspaceNote target,
  List<WorkspaceNote> notes,
) {
  if (link.markerValid) return link.targetId == target.id;
  final matches = notes
      .where((note) => note.title.toLowerCase() == link.title.toLowerCase())
      .take(2)
      .toList();
  return matches.length == 1 && matches.single.id == target.id;
}

bool _ambiguousTargetLink(
  WorkspaceWikiLink link,
  WorkspaceNote target,
  List<WorkspaceNote> notes,
) {
  if (link.markerValid ||
      target.title.toLowerCase() != link.title.toLowerCase()) {
    return false;
  }
  return notes
          .where((note) => note.title.toLowerCase() == link.title.toLowerCase())
          .length >
      1;
}

String _replaceLinkTitle(
  String source,
  WorkspaceWikiLink link,
  String requestedTitle,
) {
  final content = source.substring(link.start + 2, link.end - 2);
  final aliasStart = content.indexOf('|');
  final rawTitle = aliasStart < 0 ? content : content.substring(0, aliasStart);
  final leadingLength = rawTitle.length - rawTitle.trimLeft().length;
  final trailingStart = rawTitle.trimRight().length;
  final newRawTitle =
      '${rawTitle.substring(0, leadingLength)}$requestedTitle${rawTitle.substring(trailingStart)}';
  final suffix = aliasStart < 0 ? '' : content.substring(aliasStart);
  return '[[$newRawTitle$suffix]]';
}

int _compareText(String a, String b) {
  final folded = a.toLowerCase().compareTo(b.toLowerCase());
  return folded != 0 ? folded : a.compareTo(b);
}
