import 'note_markdown_metadata.dart';
import 'workspace_note.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _marker = RegExp(r'<!--varian-note-id:([^>]+)-->');

class WorkspaceWikiLink {
  const WorkspaceWikiLink({
    required this.start,
    required this.end,
    required this.title,
    required this.alias,
    required this.headingSlug,
    required this.blockId,
    required this.targetId,
    required this.markerValid,
  });
  final int start;
  final int end;
  final String title;
  final String? alias;
  final String? headingSlug;
  final String? blockId;
  final String? targetId;
  final bool markerValid;
}

enum WorkspaceNoteAnchorKind { heading, block }

class WorkspaceNoteAnchor {
  const WorkspaceNoteAnchor({
    required this.id,
    required this.kind,
    required this.line,
  });

  final String id;
  final WorkspaceNoteAnchorKind kind;
  final int line;
}

List<bool> _codeContextMask(String source) {
  final mask = List<bool>.filled(source.length, false);
  var offset = 0;
  String? fenceChar;
  var fenceLength = 0;
  for (final line in source.split('\n')) {
    final delimiter = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
    if (fenceChar == null && delimiter != null) {
      final run = delimiter.group(1)!;
      fenceChar = run[0];
      fenceLength = run.length;
      for (var i = offset; i < offset + line.length; i++) {
        mask[i] = true;
      }
    } else if (fenceChar != null) {
      final close = RegExp(
        '^ {0,3}${RegExp.escape(fenceChar)}{$fenceLength,}\\s*\$',
      ).hasMatch(line);
      for (var i = offset; i < offset + line.length; i++) {
        mask[i] = true;
      }
      if (close) {
        fenceChar = null;
        fenceLength = 0;
      }
    } else {
      final runs = RegExp(r'`+').allMatches(line).toList();
      for (var i = 0; i < runs.length; i++) {
        final opening = runs[i];
        final paired = runs
            .skip(i + 1)
            .firstWhere(
              (run) => run.group(0)!.length == opening.group(0)!.length,
              orElse: () => opening,
            );
        if (identical(paired, opening)) continue;
        final start = offset + opening.start;
        final end = offset + paired.end;
        for (var j = start; j < end; j++) {
          mask[j] = true;
        }
        i = runs.indexOf(paired);
      }
    }
    offset += line.length + 1;
  }
  var cursor = 0;
  while (cursor < source.length) {
    if (mask[cursor] || source[cursor] != '`') {
      cursor++;
      continue;
    }
    final start = cursor;
    while (cursor < source.length && source[cursor] == '`' && !mask[cursor]) {
      cursor++;
    }
    final runLength = cursor - start;
    var search = cursor;
    var closingEnd = -1;
    while (search < source.length && !mask[search]) {
      if (source[search] != '`') {
        search++;
        continue;
      }
      final candidateStart = search;
      while (search < source.length && source[search] == '`' && !mask[search]) {
        search++;
      }
      if (search - candidateStart == runLength) {
        closingEnd = search;
        break;
      }
    }
    if (closingEnd >= 0) {
      for (var i = start; i < closingEnd; i++) {
        mask[i] = true;
      }
      cursor = closingEnd;
    }
  }
  return mask;
}

List<bool> workspaceMarkdownCodeContextMask(String markdown) =>
    _codeContextMask(markdown);

List<WorkspaceWikiLink> parseWorkspaceWikiLinks(String markdown) {
  final excluded = _codeContextMask(markdown);
  final result = <WorkspaceWikiLink>[];
  final linkPattern = RegExp(r'\[\[([^\]\n|]+)(?:\|([^\]\n]*))?\]\]');
  for (final match in linkPattern.allMatches(markdown)) {
    if (excluded
        .skip(match.start)
        .take(match.end - match.start)
        .any((v) => v)) {
      continue;
    }
    final after = markdown.substring(match.end);
    final markerMatches = _marker.allMatches(after).take(2).toList();
    final adjacent = markerMatches.isNotEmpty && markerMatches.first.start == 0;
    final valid =
        adjacent &&
        markerMatches.length == 1 &&
        _uuid.hasMatch(markerMatches.first.group(1)!);
    final rawTarget = match.group(1)!.trim();
    final separator = rawTarget.indexOf('#');
    final title = separator < 0
        ? rawTarget
        : rawTarget.substring(0, separator).trim();
    final fragment = separator < 0
        ? null
        : rawTarget.substring(separator + 1).trim();
    final blockId = fragment?.startsWith('^') == true
        ? fragment!.substring(1)
        : null;
    result.add(
      WorkspaceWikiLink(
        start: match.start,
        end: match.end,
        title: title,
        alias: match.group(2)?.trim(),
        headingSlug: fragment == null || fragment.startsWith('^')
            ? null
            : workspaceHeadingSlug(fragment),
        blockId: blockId,
        targetId: valid ? markerMatches.first.group(1) : null,
        markerValid: valid,
      ),
    );
  }
  return List.unmodifiable(result);
}

String workspaceHeadingSlug(String heading) => heading
    .toLowerCase()
    .replaceAll(RegExp(r'[\p{P}\p{S}]', unicode: true), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '-');

List<WorkspaceNoteAnchor> parseWorkspaceNoteAnchors(String markdown) {
  final body = parseNoteMarkdownMetadata(markdown).body;
  final codeMask = _codeContextMask(body);
  final anchors = <WorkspaceNoteAnchor>[];
  final headingCounts = <String, int>{};
  var offset = 0;
  final lines = body.split('\n');
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final rawLine = lines[lineIndex];
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    final heading = RegExp(r'^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$').firstMatch(line);
    if (heading != null && !codeMask[offset + heading.start]) {
      final slug = workspaceHeadingSlug(heading.group(1)!);
      if (slug.isNotEmpty) {
        final occurrence = headingCounts.update(
          slug,
          (count) => count + 1,
          ifAbsent: () => 0,
        );
        anchors.add(
          WorkspaceNoteAnchor(
            id: occurrence == 0 ? slug : '$slug-$occurrence',
            kind: WorkspaceNoteAnchorKind.heading,
            line: lineIndex,
          ),
        );
      }
    }
    final block = RegExp(r'(?:^|\s)\^([A-Za-z0-9_-]+)\s*$').firstMatch(line);
    if (block != null && !codeMask[offset + block.start]) {
      anchors.add(
        WorkspaceNoteAnchor(
          id: block.group(1)!,
          kind: WorkspaceNoteAnchorKind.block,
          line: lineIndex,
        ),
      );
    }
    offset += rawLine.length + 1;
  }
  return List.unmodifiable(anchors);
}

WorkspaceNoteAnchor? resolveWorkspaceNoteAnchor(
  String markdown,
  String fragment,
) {
  final normalizedFragment = fragment.startsWith('#')
      ? fragment.substring(1)
      : fragment;
  final anchors = parseWorkspaceNoteAnchors(markdown);
  if (normalizedFragment.startsWith('^')) {
    final blockId = normalizedFragment.substring(1);
    final matches = anchors
        .where(
          (anchor) =>
              anchor.kind == WorkspaceNoteAnchorKind.block &&
              anchor.id == blockId,
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }
  final exact = anchors
      .where(
        (anchor) =>
            anchor.kind == WorkspaceNoteAnchorKind.heading &&
            anchor.id == normalizedFragment,
      )
      .toList();
  if (exact.length == 1) return exact.single;
  final slug = workspaceHeadingSlug(normalizedFragment);
  final matches = anchors
      .where(
        (anchor) =>
            anchor.kind == WorkspaceNoteAnchorKind.heading && anchor.id == slug,
      )
      .toList();
  return matches.length == 1 ? matches.single : null;
}

bool containsWorkspaceLinkedMention(String markdown, Iterable<String> names) {
  final body = parseNoteMarkdownMetadata(markdown).body;
  final excluded = _codeContextMask(body);
  void excludeRange(int start, int end) {
    for (var index = start; index < end; index++) {
      excluded[index] = true;
    }
  }

  for (final link in parseWorkspaceWikiLinks(body)) {
    excludeRange(link.start, link.end);
  }
  for (final destination in RegExp(r'\]\([^)]*\)').allMatches(body)) {
    excludeRange(destination.start + 1, destination.end);
  }
  for (final name in names) {
    if (name.trim().isEmpty) continue;
    final pattern = RegExp(
      r'(?<![\p{L}\p{N}_])' + RegExp.escape(name) + r'(?![\p{L}\p{N}_])',
      caseSensitive: false,
      unicode: true,
    );
    for (final match in pattern.allMatches(body)) {
      if (!excluded
          .skip(match.start)
          .take(match.end - match.start)
          .any((v) => v)) {
        return true;
      }
    }
  }
  return false;
}

bool workspaceNoteMatchesName(WorkspaceNote note, String name) {
  final normalizedName = name.trim().toLowerCase();
  if (normalizedName.isEmpty) return false;
  if (note.title.trim().toLowerCase() == normalizedName) return true;
  final metadata = parseNoteMarkdownMetadata(note.markdownContent);
  final aliases = metadata.yaml is Map
      ? (metadata.yaml as Map)['aliases']
      : null;
  final values = aliases is Iterable && aliases is! String
      ? aliases.whereType<String>()
      : aliases is String
      ? [aliases]
      : const <String>[];
  return values.any((alias) => alias.trim().toLowerCase() == normalizedName);
}

Iterable<String> workspaceNoteNames(WorkspaceNote note) sync* {
  yield note.title;
  final metadata = parseNoteMarkdownMetadata(note.markdownContent);
  final aliases = metadata.yaml is Map
      ? (metadata.yaml as Map)['aliases']
      : null;
  if (aliases is Iterable && aliases is! String) {
    for (final alias in aliases.whereType<String>()) {
      yield alias;
    }
  } else if (aliases is String) {
    yield aliases;
  }
}

bool notesShareLinkScope(WorkspaceNote source, WorkspaceNote target) {
  if (source.projectId != null || target.projectId != null) {
    return source.projectId != null && source.projectId == target.projectId;
  }
  return source.ownerUserId == target.ownerUserId;
}

String renderWorkspaceMarkdown(
  String markdown,
  List<WorkspaceNote> notes, {
  WorkspaceNote? source,
}) {
  final links = parseWorkspaceWikiLinks(markdown);
  final output = StringBuffer();
  var cursor = 0;
  for (final link in links) {
    output.write(markdown.substring(cursor, link.start));
    final candidates = link.targetId != null
        ? notes
              .where(
                (note) =>
                    note.deletedAt == null &&
                    note.id == link.targetId &&
                    (source == null || notesShareLinkScope(source, note)),
              )
              .toList()
        : notes
              .where(
                (note) =>
                    note.deletedAt == null &&
                    workspaceNoteMatchesName(note, link.title) &&
                    (source == null || notesShareLinkScope(source, note)),
              )
              .toList();
    final safeLabel = _escapeLabel(link.alias ?? link.title);
    if (candidates.length == 1) {
      final fragment = link.blockId != null
          ? '^${link.blockId}'
          : link.headingSlug;
      final destination = Uri(
        scheme: 'varian-note',
        host: Uri.encodeComponent(candidates.single.id),
        fragment: fragment,
      );
      output.write('[$safeLabel]($destination)');
    } else {
      output.write(markdown.substring(link.start, link.end));
    }
    cursor = link.end;
    if (link.markerValid) {
      final marker = _marker.matchAsPrefix(markdown, cursor);
      if (marker != null) cursor = marker.end;
    }
  }
  output.write(markdown.substring(cursor));
  return output.toString();
}

String _escapeLabel(String label) => label
    .replaceAll('\\', '\\\\')
    .replaceAll('[', '\\[')
    .replaceAll(']', '\\]')
    .replaceAll('(', '\\(')
    .replaceAll(')', '\\)')
    .replaceAll('\n', ' ');
