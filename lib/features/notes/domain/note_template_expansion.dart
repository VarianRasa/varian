import 'dart:convert';

import 'package:varian/app/workspace_timestamp.dart';
import 'package:varian/features/notes/domain/note_markdown_metadata.dart';

String expandWorkspaceNoteTemplate({
  required String template,
  required DateTime localDate,
  required String title,
  required List<String> aliases,
}) {
  final date = formatWorkspaceDateKey(localDate);
  final offsets = _frontmatterOffsets(template);
  if (offsets == null) {
    return _expandTokens(template, {
      'date': date,
      'title': _escapeMarkdownLiteral(title),
      'aliases': aliases.map(_escapeMarkdownLiteral).join(', '),
    });
  }

  final frontmatter = template.substring(0, offsets.frontmatterEnd);
  final body = template.substring(offsets.bodyStart);
  return '${_expandTokens(frontmatter, {'date': date, 'title': jsonEncode(title), 'aliases': jsonEncode(aliases)})}${_expandTokens(body, {'date': date, 'title': _escapeMarkdownLiteral(title), 'aliases': aliases.map(_escapeMarkdownLiteral).join(', ')})}';
}

List<String> workspaceNoteTemplateAliases(String markdown) {
  final yaml = parseNoteMarkdownMetadata(markdown).yaml;
  if (yaml is! Map) return const [];
  final aliases = yaml['aliases'] ?? yaml['alias'];
  if (aliases is String) {
    final alias = aliases.trim();
    return alias.isEmpty ? const [] : [alias];
  }
  if (aliases is Iterable) {
    return [
      for (final value in aliases)
        if (value is String && value.trim().isNotEmpty) value.trim(),
    ];
  }
  return const [];
}

({int frontmatterEnd, int bodyStart})? _frontmatterOffsets(String source) {
  final firstLineEnd = source.indexOf('\n');
  if (firstLineEnd < 0) return null;
  final openingLine = source
      .substring(0, firstLineEnd)
      .replaceFirst(RegExp(r'\r$'), '');
  if (!RegExp(r'^---[ \t]*$').hasMatch(openingLine)) return null;

  var lineStart = firstLineEnd + 1;
  while (lineStart <= source.length) {
    final newline = source.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? source.length : newline;
    final line = source
        .substring(lineStart, lineEnd)
        .replaceFirst(RegExp(r'\r$'), '');
    if (RegExp(r'^---[ \t]*$').hasMatch(line)) {
      return (
        frontmatterEnd: newline < 0 ? lineEnd : newline + 1,
        bodyStart: newline < 0 ? lineEnd : newline + 1,
      );
    }
    if (newline < 0) break;
    lineStart = newline + 1;
  }
  return null;
}

String _expandTokens(String source, Map<String, String> values) =>
    source.replaceAllMapped(
      RegExp(r'\{\{(date|title|aliases)\}\}'),
      (match) => values[match[1]]!,
    );

String _escapeMarkdownLiteral(String value) {
  final singleLine = value
      .replaceAll('\r\n', ' ')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');
  return singleLine.replaceAllMapped(
    RegExp(r'([\\`*_{}\[\]()#+\-.!|<>~])'),
    (match) => '\\${match[0]}',
  );
}
