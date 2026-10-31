import 'dart:convert';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'note_markdown_metadata.dart';

enum NotePropertyType { text, list, number, checkbox, dateTime, tags, aliases }

/// Updates one top-level property without reserializing unrelated YAML or body text.
String setNoteMarkdownProperty(
  String markdown, {
  required String key,
  required NotePropertyType type,
  required Object value,
}) {
  _validateKey(key);
  final normalizedValue = _yamlValue(type, value);
  final yamlValue = type == NotePropertyType.dateTime
      ? wrapAsYamlNode(
          normalizedValue as String,
          scalarStyle: ScalarStyle.PLAIN,
        )
      : normalizedValue;
  final metadata = parseNoteMarkdownMetadata(markdown);
  if (metadata.parseError != null) {
    throw const FormatException(
      'Fix invalid YAML frontmatter before editing Properties.',
    );
  }

  final frontmatter = _frontmatterSource(markdown);
  if (frontmatter == null) {
    final lineEnding = _lineEnding(markdown);
    final propertyLine = '${_yamlKey(key)}: ${_serializeValue(type, value)}';
    return '---$lineEnding$propertyLine$lineEnding---$lineEnding$markdown';
  }

  final root = metadata.yaml as Map;
  final raw = frontmatter.raw;
  if (!root.containsKey(key)) {
    final lineEnding = _lineEnding(raw);
    final separator = raw.isEmpty || raw.endsWith('\n') ? '' : lineEnding;
    final propertyLine = '${_yamlKey(key)}: ${_serializeValue(type, value)}';
    return _replaceFrontmatter(
      markdown,
      frontmatter,
      '$raw$separator$propertyLine',
    );
  }

  try {
    final editor = YamlEditor(raw)..update([key], yamlValue);
    return _replaceFrontmatter(markdown, frontmatter, editor.toString());
  } catch (_) {
    throw const FormatException(
      'The selected YAML property could not be edited safely.',
    );
  }
}

/// Removes one top-level property and preserves the rest of the note source.
String removeNoteMarkdownProperty(String markdown, {required String key}) {
  _validateKey(key);
  final metadata = parseNoteMarkdownMetadata(markdown);
  if (metadata.parseError != null) {
    throw const FormatException(
      'Fix invalid YAML frontmatter before editing Properties.',
    );
  }
  final frontmatter = _frontmatterSource(markdown);
  if (frontmatter == null || !(metadata.yaml as Map).containsKey(key)) {
    return markdown;
  }

  try {
    final editor = YamlEditor(frontmatter.raw)..remove([key]);
    final updatedRaw = editor.toString();
    if (updatedRaw.trim().isEmpty) return metadata.body;
    return _replaceFrontmatter(markdown, frontmatter, updatedRaw);
  } catch (_) {
    throw const FormatException(
      'The selected YAML property could not be removed safely.',
    );
  }
}

Object _yamlValue(NotePropertyType type, Object value) {
  switch (type) {
    case NotePropertyType.text:
      if (value is String) return value;
      break;
    case NotePropertyType.list:
    case NotePropertyType.tags:
    case NotePropertyType.aliases:
      if (value is List && value.every((item) => item is String)) {
        return value.cast<String>();
      }
      break;
    case NotePropertyType.number:
      if (value is num && (value is! double || value.isFinite)) return value;
      break;
    case NotePropertyType.checkbox:
      if (value is bool) return value;
      break;
    case NotePropertyType.dateTime:
      if (value is DateTime) return value.toUtc().toIso8601String();
      break;
  }
  throw ArgumentError('Property value does not match ${type.name}.');
}

String _serializeValue(NotePropertyType type, Object value) {
  final normalized = _yamlValue(type, value);
  return switch (type) {
    NotePropertyType.text => jsonEncode(normalized),
    NotePropertyType.list ||
    NotePropertyType.tags ||
    NotePropertyType.aliases => jsonEncode(normalized),
    NotePropertyType.number ||
    NotePropertyType.checkbox => normalized.toString(),
    NotePropertyType.dateTime => (value as DateTime).toUtc().toIso8601String(),
  };
}

void _validateKey(String key) {
  if (key.trim().isEmpty ||
      RegExp(r'[\r\n\u0000-\u001f\u007f]').hasMatch(key)) {
    throw ArgumentError('Property name must be non-empty and single-line.');
  }
}

String _yamlKey(String key) => jsonEncode(key);

String _lineEnding(String source) => source.contains('\r\n') ? '\r\n' : '\n';

String _replaceFrontmatter(
  String markdown,
  _FrontmatterSource frontmatter,
  String updatedRaw,
) {
  final suffixHasLineBreak =
      frontmatter.suffix.startsWith('\r\n') ||
      frontmatter.suffix.startsWith('\n');
  final separator = updatedRaw.isNotEmpty && !suffixHasLineBreak
      ? _lineEnding(markdown)
      : '';
  return '${frontmatter.prefix}$updatedRaw$separator${frontmatter.suffix}';
}

_FrontmatterSource? _frontmatterSource(String markdown) {
  final delimiters = RegExp(
    r'^---\r?$',
    multiLine: true,
  ).allMatches(markdown).toList();
  if (delimiters.isEmpty ||
      delimiters.first.start != 0 ||
      delimiters.length < 2) {
    return null;
  }
  final opening = delimiters.first;
  final closing = delimiters[1];
  final openingEnd =
      opening.end < markdown.length && markdown[opening.end] == '\n'
      ? opening.end + 1
      : opening.end;
  var rawEnd = closing.start;
  if (rawEnd > openingEnd && markdown.substring(rawEnd - 2, rawEnd) == '\r\n') {
    rawEnd -= 2;
  } else if (rawEnd > openingEnd && markdown[rawEnd - 1] == '\n') {
    rawEnd--;
  }
  return _FrontmatterSource(
    prefix: markdown.substring(0, openingEnd),
    raw: markdown.substring(openingEnd, rawEnd),
    suffix: markdown.substring(rawEnd),
  );
}

class _FrontmatterSource {
  const _FrontmatterSource({
    required this.prefix,
    required this.raw,
    required this.suffix,
  });

  final String prefix;
  final String raw;
  final String suffix;
}
