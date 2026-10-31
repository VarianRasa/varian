import 'package:yaml/yaml.dart';

class NoteMarkdownMetadata {
  const NoteMarkdownMetadata({
    required this.frontmatterRaw,
    required this.body,
    required this.yaml,
    required this.parseError,
    required this.searchableValues,
    required this.tags,
  });

  final String? frontmatterRaw;
  final String body;
  final Object? yaml;
  final Object? parseError;
  final List<String> searchableValues;
  final Set<String> tags;
}

List<bool> _markdownCodeMask(String source) {
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
        for (var j = offset + opening.start; j < offset + paired.end; j++) {
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

Object? _normalizeYamlNode(YamlNode node) {
  if (node is YamlMap) {
    return {
      for (final entry in node.nodes.entries)
        entry.key.value: _normalizeYamlNode(entry.value),
    };
  }
  if (node is YamlList) {
    return node.nodes.map(_normalizeYamlNode).toList(growable: false);
  }
  if (node is YamlScalar) {
    final value = node.value;
    if (value is String &&
        node.style == ScalarStyle.PLAIN &&
        RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
          caseSensitive: false,
        ).hasMatch(value)) {
      return DateTime.parse(value).toUtc();
    }
    return value;
  }
  return node.value;
}

NoteMarkdownMetadata parseNoteMarkdownMetadata(String markdown) {
  String? raw;
  var body = markdown;
  Object? parsed;
  Object? error;
  final lines = RegExp(
    r'^---\r?$',
    multiLine: true,
  ).allMatches(markdown).toList();
  if (lines.isNotEmpty && lines.first.start == 0) {
    final opening = lines.first;
    final openingEnd =
        opening.end + (markdown.startsWith('\r\n', opening.end) ? 2 : 1);
    final closing = lines.length > 1 ? lines[1] : null;
    if (closing != null) {
      var rawEnd = closing.start;
      if (rawEnd > openingEnd &&
          markdown.substring(rawEnd - 2, rawEnd) == '\r\n') {
        rawEnd -= 2;
      } else if (rawEnd > openingEnd && markdown[rawEnd - 1] == '\n') {
        rawEnd--;
      }
      raw = markdown.substring(openingEnd, rawEnd);
      final afterClosing = closing.end;
      final bodyStart = markdown.startsWith('\r\n', afterClosing)
          ? afterClosing + 2
          : afterClosing < markdown.length && markdown[afterClosing] == '\n'
          ? afterClosing + 1
          : afterClosing;
      body = markdown.substring(bodyStart);
      try {
        final frontmatterLines = raw.split(RegExp(r'\r?\n'));
        final isCommentOnly = frontmatterLines.every((line) {
          final trimmed = line.trimLeft();
          return trimmed.isEmpty || trimmed.startsWith('#');
        });
        parsed = isCommentOnly
            ? YamlMap()
            : _normalizeYamlNode(loadYamlNode(raw));
        if (parsed is! YamlMap && parsed is! Map) {
          throw const FormatException('Frontmatter root must be a mapping.');
        }
      } catch (e) {
        error = e;
      }
    } else {
      final openingNewline = markdown.indexOf('\n');
      raw = openingNewline < 0 ? '' : markdown.substring(openingNewline + 1);
      body = markdown;
      error = const FormatException('Unclosed YAML frontmatter.');
    }
  }
  final searchable = <String>[];
  void flatten(Object? value) {
    if (value is YamlMap || value is Map) {
      for (final entry in (value as Map).entries) {
        flatten(entry.key);
        flatten(entry.value);
      }
    } else if (value is YamlList || value is List) {
      for (final item in value as Iterable) {
        flatten(item);
      }
    } else if (value != null) {
      searchable.add(value.toString());
    }
  }

  flatten(parsed);
  if (raw != null && (error != null || parsed == null)) searchable.add(raw);
  final tags = <String>{};
  final yamlTags = parsed is Map ? parsed['tags'] : null;
  final candidates = yamlTags is Iterable && yamlTags is! String
      ? yamlTags
      : [?yamlTags];
  for (final item in candidates) {
    tags.add(item.toString().replaceFirst(RegExp(r'^#'), ''));
  }
  searchable.addAll(tags);
  final codeMask = _markdownCodeMask(body);
  var bodyOffset = 0;
  for (final line in body.split('\n')) {
    final clean = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      if (!codeMask[bodyOffset + i]) clean.write(line[i]);
    }
    for (final match in RegExp(
      r'(?<!\w)#([\p{L}\p{N}_/-]+)',
      unicode: true,
    ).allMatches(clean.toString())) {
      tags.add(match.group(1)!);
    }
    bodyOffset += line.length + 1;
  }
  return NoteMarkdownMetadata(
    frontmatterRaw: raw,
    body: body,
    yaml: parsed,
    parseError: error,
    searchableValues: List.unmodifiable([...searchable, body]),
    tags: Set.unmodifiable(tags),
  );
}
