import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class NoteArchiveManifest {
  const NoteArchiveManifest({
    required this.format,
    required this.schemaVersion,
    required this.notes,
  });

  static const supportedFormat = 'varian-notes';
  static const supportedSchemaVersion = 1;
  static const maxNotes = 100;

  final String format;
  final int schemaVersion;
  final List<NoteArchiveManifestEntry> notes;

  factory NoteArchiveManifest.parse(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const NoteArchiveManifestException(
        'Manifest is not valid UTF-8 JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const NoteArchiveManifestException(
        'Manifest must be a JSON object.',
      );
    }
    if (decoded['format'] != supportedFormat) {
      throw const NoteArchiveManifestException('Unsupported archive format.');
    }
    if (decoded['schemaVersion'] is! int ||
        decoded['schemaVersion'] != supportedSchemaVersion) {
      throw const NoteArchiveManifestException(
        'Unsupported archive schema version.',
      );
    }
    final rawNotes = decoded['notes'];
    if (rawNotes is! List<dynamic> || rawNotes.length > maxNotes) {
      throw const NoteArchiveManifestException(
        'Manifest notes must be a list of at most 100 entries.',
      );
    }

    final noteEntries = <NoteArchiveManifestEntry>[];
    final ids = <String>{};
    final paths = <String>{};
    for (final rawEntry in rawNotes) {
      if (rawEntry is! Map<String, dynamic>) {
        throw const NoteArchiveManifestException(
          'Each manifest note must be an object.',
        );
      }
      final sourceId = rawEntry['id'];
      final path = rawEntry['path'];
      final title = rawEntry['title'];
      final folder = rawEntry['folder'];
      if (sourceId is! String || !_uuidPattern.hasMatch(sourceId)) {
        throw const NoteArchiveManifestException(
          'Manifest note ID must be a UUID.',
        );
      }
      if (path is! String || !_validRelativePath(path, requireMarkdown: true)) {
        throw const NoteArchiveManifestException(
          'Manifest note path must be a safe relative Markdown path.',
        );
      }
      if (title is! String || title.trim().isEmpty) {
        throw const NoteArchiveManifestException(
          'Manifest note title must not be empty.',
        );
      }
      if (folder != null &&
          (folder is! String || !_validRelativePath(folder))) {
        throw const NoteArchiveManifestException(
          'Manifest folder path must be safe and relative.',
        );
      }
      if (path.toLowerCase() == 'manifest.json') {
        throw const NoteArchiveManifestException(
          'A note cannot use the manifest path.',
        );
      }
      if (!ids.add(sourceId.toLowerCase())) {
        throw const NoteArchiveManifestException(
          'Manifest note IDs must be unique.',
        );
      }
      if (!paths.add(path.toLowerCase())) {
        throw const NoteArchiveManifestException(
          'Manifest note paths must be unique.',
        );
      }
      noteEntries.add(
        NoteArchiveManifestEntry(
          sourceId: sourceId,
          path: path,
          title: title.trim(),
          folderPath: folder as String?,
        ),
      );
    }

    return NoteArchiveManifest(
      format: supportedFormat,
      schemaVersion: supportedSchemaVersion,
      notes: List.unmodifiable(noteEntries),
    );
  }
}

@immutable
class NoteArchiveManifestEntry {
  const NoteArchiveManifestEntry({
    required this.sourceId,
    required this.path,
    required this.title,
    this.folderPath,
  });

  final String sourceId;
  final String path;
  final String title;
  final String? folderPath;
}

final class NoteArchiveManifestException implements Exception {
  const NoteArchiveManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _validRelativePath(String path, {bool requireMarkdown = false}) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith('\\') ||
      path.contains('\\') ||
      path.contains(':') ||
      path.contains('\u0000')) {
    return false;
  }
  final segments = path.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    return false;
  }
  if (requireMarkdown && !path.toLowerCase().endsWith('.md')) return false;
  return true;
}
