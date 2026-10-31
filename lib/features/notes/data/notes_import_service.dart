import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/features/notes/domain/note_archive_manifest.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';

class _SelectedImportFile {
  const _SelectedImportFile({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;
}

class NotesImportService {
  static const maxFiles = 100;
  static const maxCompressedBytes = 25 * 1024 * 1024;
  static const maxExpandedBytes = 100 * 1024 * 1024;
  static const maxMarkdownBytes = 10 * 1024 * 1024;
  static const maxManifestBytes = 1024 * 1024;

  final Uuid _uuid;

  NotesImportService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  Future<NotesImportPreview> decodeSelection({
    required List<PlatformFile> files,
    required List<WorkspaceNote> existingNotes,
  }) async {
    if (files.length == 1 && files.single.name.toLowerCase().endsWith('.zip')) {
      final zipFile = files.single;
      final compressedSize = await zipFile.length();
      if (compressedSize > maxCompressedBytes) {
        throw const NotesImportException(
          NotesImportFailure.inputTooLarge,
          'ZIP input exceeds the 25 MiB compressed size limit.',
        );
      }
      final zipBytes = await _readBytes(zipFile);
      if (zipBytes.length > maxCompressedBytes) {
        throw const NotesImportException(
          NotesImportFailure.inputTooLarge,
          'ZIP input exceeds the 25 MiB compressed size limit.',
        );
      }
      return _decodeZip(zipBytes, existingNotes);
    }
    if (files.any((file) => file.name.toLowerCase().endsWith('.zip'))) {
      throw const NotesImportException(
        NotesImportFailure.unsupportedFile,
        'Choose one ZIP archive or a set of Markdown files, not both.',
      );
    }
    return prepare(files: files, existingNotes: existingNotes);
  }

  Future<NotesImportPreview> prepare({
    required List<PlatformFile> files,
    required List<WorkspaceNote> existingNotes,
  }) async {
    if (files.isEmpty) {
      throw const NotesImportException(
        NotesImportFailure.emptySelection,
        'Select at least one Markdown file.',
      );
    }

    if (files.length > maxFiles + 1) {
      throw const NotesImportException(
        NotesImportFailure.fileCount,
        'Select at most 100 Markdown files and one manifest.',
      );
    }

    final contentFiles = <({PlatformFile file, String path})>[];
    PlatformFile? manifestFile;
    final names = <String>{};
    var totalInputBytes = 0;
    for (final file in files) {
      final path = _normalizeSelectionPath(file.name);
      if (path == null) {
        throw const NotesImportException(
          NotesImportFailure.invalidPath,
          'A selected file has an unsafe path.',
        );
      }
      if (!names.add(path.toLowerCase())) {
        throw const NotesImportException(
          NotesImportFailure.duplicatePath,
          'Selected file paths must be unique.',
        );
      }
      final isManifest = path.toLowerCase() == 'manifest.json';
      final isMarkdown = path.toLowerCase().endsWith('.md');
      if (!isManifest && !isMarkdown) {
        throw const NotesImportException(
          NotesImportFailure.unsupportedFile,
          'Only Markdown files and one manifest.json are supported.',
        );
      }
      if (isManifest) {
        if (manifestFile != null) {
          throw const NotesImportException(
            NotesImportFailure.duplicateManifest,
            'Only one manifest.json is allowed.',
          );
        }
        manifestFile = file;
      } else {
        contentFiles.add((file: file, path: path));
      }
      final int size;
      try {
        size = await file.length();
      } catch (_) {
        throw NotesImportException(
          NotesImportFailure.unreadableFile,
          'Could not inspect selected file: ${file.name}',
        );
      }
      final maxSize = isManifest ? maxManifestBytes : maxMarkdownBytes;
      if (size > maxSize) {
        throw NotesImportException(
          NotesImportFailure.fileTooLarge,
          'Selected file exceeds its size limit: ${file.name}',
        );
      }
      totalInputBytes += size;
      if (totalInputBytes > maxCompressedBytes) {
        throw const NotesImportException(
          NotesImportFailure.inputTooLarge,
          'Selected files exceed the 25 MiB input limit.',
        );
      }
    }
    if (contentFiles.isEmpty || contentFiles.length > maxFiles) {
      throw const NotesImportException(
        NotesImportFailure.fileCount,
        'Select between 1 and 100 Markdown files.',
      );
    }

    final contentPayloads = <_SelectedImportFile>[];
    for (final selected in contentFiles) {
      final bytes = await _readBytes(selected.file);
      if (bytes.length > maxMarkdownBytes) {
        throw NotesImportException(
          NotesImportFailure.fileTooLarge,
          'Selected file exceeds the 10 MiB Markdown limit: ${selected.file.name}',
        );
      }
      contentPayloads.add(
        _SelectedImportFile(path: selected.path, bytes: bytes),
      );
    }
    final manifestBytes = manifestFile == null
        ? null
        : await _readBytes(manifestFile);
    return _preparePayloads(
      contentFiles: contentPayloads,
      manifestBytes: manifestBytes,
      existingNotes: existingNotes,
    );
  }

  Future<Uint8List> _readBytes(PlatformFile file) async {
    try {
      return await file.readAsBytes();
    } catch (_) {
      throw NotesImportException(
        NotesImportFailure.unreadableFile,
        'Could not read selected file: ${file.name}',
      );
    }
  }

  NotesImportPreview _decodeZip(
    Uint8List bytes,
    List<WorkspaceNote> existingNotes,
  ) {
    final decoder = ZipDecoder();
    final Archive archive;
    try {
      archive = decoder.decodeBytes(bytes);
    } catch (_) {
      throw const NotesImportException(
        NotesImportFailure.invalidArchive,
        'The ZIP archive is malformed or unsupported.',
      );
    }

    final paths = <String>{};
    final markdownPaths = <String>{};
    var totalExpandedBytes = 0;
    for (final header in decoder.directory.fileHeaders) {
      final directory = header.filename.endsWith('/');
      final rawPath = directory
          ? header.filename.substring(0, header.filename.length - 1)
          : header.filename;
      final path = _normalizeSelectionPath(rawPath);
      if (path == null) {
        throw const NotesImportException(
          NotesImportFailure.invalidPath,
          'ZIP archive contains an unsafe path.',
        );
      }
      if (!paths.add(path.toLowerCase())) {
        throw const NotesImportException(
          NotesImportFailure.duplicateArchiveEntry,
          'ZIP archive paths must be unique.',
        );
      }
      final mode = (header.externalFileAttributes >> 16) & 0xf000;
      if ((header.versionMadeBy >> 8) == 3 && mode == 0xa000) {
        throw const NotesImportException(
          NotesImportFailure.unsupportedArchiveEntry,
          'ZIP symbolic links are not supported.',
        );
      }
      if (directory) continue;
      final normalized = path.toLowerCase();
      if (normalized == 'manifest.json') {
        if (header.uncompressedSize > maxManifestBytes) {
          throw const NotesImportException(
            NotesImportFailure.fileTooLarge,
            'Archive manifest exceeds the 1 MiB limit.',
          );
        }
      } else if (normalized.endsWith('.md')) {
        if (header.uncompressedSize > maxMarkdownBytes) {
          throw const NotesImportException(
            NotesImportFailure.fileTooLarge,
            'A Markdown entry exceeds the 10 MiB limit.',
          );
        }
        markdownPaths.add(path);
        if (markdownPaths.length > maxFiles) {
          throw const NotesImportException(
            NotesImportFailure.fileCount,
            'ZIP archive contains more than 100 Markdown files.',
          );
        }
      } else {
        throw const NotesImportException(
          NotesImportFailure.unsupportedArchiveEntry,
          'ZIP archive contains an unsupported file type.',
        );
      }
      totalExpandedBytes += header.uncompressedSize;
      if (totalExpandedBytes > maxExpandedBytes) {
        throw const NotesImportException(
          NotesImportFailure.expandedTooLarge,
          'ZIP archive exceeds the 100 MiB expanded size limit.',
        );
      }
    }

    final filesByPath = {for (final file in archive.files) file.name: file};
    final payloads = <_SelectedImportFile>[];
    Uint8List? manifestBytes;
    for (final path in paths) {
      if (path.toLowerCase() == 'manifest.json') {
        final file = filesByPath.entries
            .where((entry) => entry.key.toLowerCase() == path.toLowerCase())
            .map((entry) => entry.value)
            .firstOrNull;
        if (file == null) {
          throw const NotesImportException(
            NotesImportFailure.invalidArchive,
            'ZIP archive manifest could not be read.',
          );
        }
        manifestBytes = file.readBytes();
        if (manifestBytes == null) {
          throw const NotesImportException(
            NotesImportFailure.invalidArchive,
            'ZIP archive manifest could not be read.',
          );
        }
      } else if (path.toLowerCase().endsWith('.md')) {
        final file = filesByPath.entries
            .where((entry) => entry.key.toLowerCase() == path.toLowerCase())
            .map((entry) => entry.value)
            .firstOrNull;
        final content = file?.readBytes();
        if (content == null) {
          throw const NotesImportException(
            NotesImportFailure.invalidArchive,
            'ZIP archive Markdown entry could not be read.',
          );
        }
        payloads.add(_SelectedImportFile(path: path, bytes: content));
      }
    }
    return _preparePayloads(
      contentFiles: payloads,
      manifestBytes: manifestBytes,
      existingNotes: existingNotes,
    );
  }

  NotesImportPreview _preparePayloads({
    required List<_SelectedImportFile> contentFiles,
    required Uint8List? manifestBytes,
    required List<WorkspaceNote> existingNotes,
  }) {
    if (contentFiles.isEmpty || contentFiles.length > maxFiles) {
      throw const NotesImportException(
        NotesImportFailure.fileCount,
        'Select between 1 and 100 Markdown files.',
      );
    }
    if (manifestBytes != null && manifestBytes.length > maxManifestBytes) {
      throw const NotesImportException(
        NotesImportFailure.fileTooLarge,
        'Manifest exceeds the 1 MiB limit.',
      );
    }
    final manifest = manifestBytes == null
        ? null
        : NoteArchiveManifest.parse(manifestBytes);
    final manifestByPath = <String, NoteArchiveManifestEntry>{};
    final generatedIds = <String, String>{};
    if (manifest != null) {
      for (final entry in manifest.notes) {
        manifestByPath[entry.path.toLowerCase()] = entry;
        generatedIds[entry.sourceId.toLowerCase()] = _uuid.v4();
      }
      if (manifestByPath.length != contentFiles.length ||
          contentFiles.any(
            (file) => !manifestByPath.containsKey(file.path.toLowerCase()),
          )) {
        throw const NotesImportException(
          NotesImportFailure.manifestMismatch,
          'The manifest must describe every Markdown file exactly once.',
        );
      }
    }

    final existingTitles = existingNotes
        .map((note) => note.title.trim().toLowerCase())
        .where((title) => title.isNotEmpty)
        .toSet();
    final seenTitles = <String>{};
    final prepared = <PreparedNoteImport>[];
    for (final selected in contentFiles) {
      if (selected.bytes.length > maxMarkdownBytes) {
        throw const NotesImportException(
          NotesImportFailure.fileTooLarge,
          'A Markdown file exceeds the 10 MiB limit.',
        );
      }
      final String markdown;
      try {
        final bytes = selected.bytes;
        final hasUtf8Bom =
            bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf;
        final decoded = utf8.decode(
          hasUtf8Bom ? bytes.sublist(3) : bytes,
          allowMalformed: false,
        );
        markdown = hasUtf8Bom ? '\ufeff$decoded' : decoded;
      } on FormatException {
        throw NotesImportException(
          NotesImportFailure.invalidMarkdown,
          'Markdown file is not valid UTF-8: ${selected.path}',
        );
      }
      final manifestEntry = manifestByPath[selected.path.toLowerCase()];
      final title = manifestEntry?.title ?? _titleFromPath(selected.path);
      if (title.trim().isEmpty) {
        throw NotesImportException(
          NotesImportFailure.invalidTitle,
          'Selected file has no usable title: ${selected.path}',
        );
      }
      final remappedMarkdown = manifest == null
          ? markdown
          : _remapInternalLinks(markdown, generatedIds);
      final normalizedTitle = title.trim().toLowerCase();
      final duplicateTitle =
          existingTitles.contains(normalizedTitle) ||
          !seenTitles.add(normalizedTitle);
      final newId = manifestEntry == null
          ? _uuid.v4()
          : generatedIds[manifestEntry.sourceId.toLowerCase()]!;
      prepared.add(
        PreparedNoteImport(
          newId: newId,
          sourceId: manifestEntry?.sourceId,
          sourcePath: selected.path,
          title: title,
          markdown: remappedMarkdown,
          folderPath: manifestEntry?.folderPath,
          duplicateTitle: duplicateTitle,
        ),
      );
    }
    return NotesImportPreview(notes: prepared, existingTitles: existingTitles);
  }
}

String? _normalizeSelectionPath(String rawPath) {
  if (rawPath.isEmpty ||
      rawPath.startsWith('/') ||
      rawPath.startsWith('\\') ||
      rawPath.contains(':') ||
      rawPath.contains('\\') ||
      rawPath.contains('\u0000')) {
    return null;
  }
  final segments = rawPath.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    return null;
  }
  return segments.join('/');
}

String _titleFromPath(String path) {
  final name = path.split('/').last;
  return name.substring(0, name.length - 3).trim();
}

String _remapInternalLinks(String markdown, Map<String, String> generatedIds) {
  final markerPattern = RegExp(r'<!--varian-note-id:([0-9a-fA-F-]{36})-->');
  return markdown.replaceAllMapped(markerPattern, (match) {
    final replacement = generatedIds[match.group(1)!.toLowerCase()];
    return replacement == null
        ? match.group(0)!
        : '<!--varian-note-id:$replacement-->';
  });
}

class NotesImportPreview {
  NotesImportPreview({
    required List<PreparedNoteImport> notes,
    Set<String> existingTitles = const {},
  }) : notes = List.unmodifiable(notes),
       _existingTitles = Set.unmodifiable(existingTitles);

  final List<PreparedNoteImport> notes;
  final Set<String> _existingTitles;

  List<PreparedNoteImport> resolveDuplicateTitles({
    Map<String, String> renamedTitles = const {},
    Set<String> skippedNoteIds = const {},
  }) {
    final notesById = {for (final note in notes) note.newId: note};
    if (renamedTitles.keys.any((id) => !notesById.containsKey(id)) ||
        skippedNoteIds.any((id) => !notesById.containsKey(id)) ||
        renamedTitles.keys.any(skippedNoteIds.contains)) {
      throw const NotesImportException(
        NotesImportFailure.invalidDuplicateResolution,
        'Duplicate decisions refer to an unavailable note.',
      );
    }

    final resolvedTitles = <String>{..._existingTitles};
    final accepted = <PreparedNoteImport>[];
    for (final note in notes) {
      if (skippedNoteIds.contains(note.newId)) {
        if (!note.duplicateTitle) {
          throw const NotesImportException(
            NotesImportFailure.invalidDuplicateResolution,
            'Only duplicate-title notes can be skipped.',
          );
        }
        continue;
      }
      final renamedTitle = renamedTitles[note.newId];
      if (note.duplicateTitle && renamedTitle == null) {
        throw const NotesImportException(
          NotesImportFailure.duplicateResolutionRequired,
          'Choose a new title or skip every duplicate-title note.',
        );
      }
      final title = (renamedTitle ?? note.title).trim();
      if (title.isEmpty) {
        throw const NotesImportException(
          NotesImportFailure.invalidTitle,
          'Imported note titles cannot be empty.',
        );
      }
      final normalized = title.toLowerCase();
      if (!resolvedTitles.add(normalized)) {
        throw const NotesImportException(
          NotesImportFailure.duplicateTitle,
          'Resolved import titles must be unique.',
        );
      }
      accepted.add(
        PreparedNoteImport(
          newId: note.newId,
          sourceId: note.sourceId,
          sourcePath: note.sourcePath,
          title: title,
          markdown: note.markdown,
          folderPath: note.folderPath,
          duplicateTitle: false,
        ),
      );
    }
    return List.unmodifiable(accepted);
  }
}

class PreparedNoteImport {
  const PreparedNoteImport({
    required this.newId,
    required this.sourcePath,
    required this.title,
    required this.markdown,
    required this.duplicateTitle,
    this.sourceId,
    this.folderPath,
  });

  final String newId;
  final String? sourceId;
  final String sourcePath;
  final String title;
  final String markdown;
  final String? folderPath;
  final bool duplicateTitle;
}

enum NotesImportFailure {
  emptySelection,
  invalidArchive,
  duplicateArchiveEntry,
  expandedTooLarge,
  unsupportedArchiveEntry,
  duplicateResolutionRequired,
  invalidDuplicateResolution,
  duplicateTitle,
  invalidPath,
  duplicatePath,
  unsupportedFile,
  duplicateManifest,
  fileTooLarge,
  inputTooLarge,
  fileCount,
  manifestMismatch,
  invalidTitle,
  invalidMarkdown,
  unreadableFile,
}

final class NotesImportException implements Exception {
  const NotesImportException(this.failure, this.message);

  final NotesImportFailure failure;
  final String message;

  @override
  String toString() => message;
}
