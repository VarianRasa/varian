import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:varian/features/notes/domain/note_archive_manifest.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_folder.dart';

class NotesExportService {
  Uint8List exportZip(
    List<WorkspaceNote> notes,
    List<WorkspaceNoteFolder> folders,
  ) {
    if (notes.isEmpty || notes.length > NoteArchiveManifest.maxNotes) {
      throw ArgumentError.value(
        notes.length,
        'notes',
        'Must contain 1–100 notes.',
      );
    }
    final foldersById = {for (final folder in folders) folder.id: folder};
    final usedPaths = <String>{'manifest.json'};
    final manifestNotes = <Map<String, String?>>[];
    final archive = Archive();
    final seenIds = <String>{};

    for (final note in notes) {
      if (!seenIds.add(note.id.toLowerCase())) {
        throw ArgumentError.value(note.id, 'notes', 'Note IDs must be unique.');
      }
      final folderPath = _folderPath(note.folderId, foldersById);
      final safeTitle = _safeSegment(note.title);
      final stem = safeTitle.replaceFirst(
        RegExp(r'\.md$', caseSensitive: false),
        '',
      );
      final basePath = [
        if (folderPath.isNotEmpty) folderPath,
        '$stem.md',
      ].join('/');
      final path = _uniquePath(basePath, usedPaths);
      usedPaths.add(path.toLowerCase());

      archive.addFile(
        ArchiveFile(
          path,
          utf8.encode(note.markdownContent).length,
          Uint8List.fromList(utf8.encode(note.markdownContent)),
        ),
      );
      manifestNotes.add({
        'id': note.id,
        'path': path,
        'title': note.title,
        'folder': folderPath.isEmpty ? null : folderPath,
      });
    }

    final manifest = <String, Object?>{
      'format': NoteArchiveManifest.supportedFormat,
      'schemaVersion': NoteArchiveManifest.supportedSchemaVersion,
      'notes': manifestNotes,
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  String _folderPath(
    String? folderId,
    Map<String, WorkspaceNoteFolder> foldersById,
  ) {
    if (folderId == null) return '';
    final names = <String>[];
    final visited = <String>{};
    String? currentId = folderId;
    while (currentId != null) {
      if (!visited.add(currentId)) {
        throw ArgumentError.value(
          folderId,
          'folderId',
          'Folder hierarchy contains a cycle.',
        );
      }
      final folder = foldersById[currentId];
      if (folder == null) {
        throw ArgumentError.value(
          folderId,
          'folderId',
          'Folder hierarchy is incomplete.',
        );
      }
      names.add(_safeSegment(folder.name));
      currentId = folder.parentFolderId;
    }
    return names.reversed.join('/');
  }

  String _safeSegment(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(RegExp(r'^[. ]+'), '')
        .replaceFirst(RegExp(r'[. ]+$'), '');
    if (sanitized.isEmpty) return 'Untitled';
    final windowsDeviceNames = {
      'CON',
      'PRN',
      'AUX',
      'NUL',
      for (var index = 1; index <= 9; index++) 'COM$index',
      for (var index = 1; index <= 9; index++) 'LPT$index',
    };
    final deviceName = sanitized.split('.').first.toUpperCase();
    return windowsDeviceNames.contains(deviceName) ? '_$sanitized' : sanitized;
  }

  String _uniquePath(String path, Set<String> usedPaths) {
    if (!usedPaths.contains(path.toLowerCase())) return path;
    final slash = path.lastIndexOf('/');
    final directory = slash < 0 ? '' : path.substring(0, slash + 1);
    final filename = slash < 0 ? path : path.substring(slash + 1);
    final dot = filename.lastIndexOf('.');
    final stem = dot <= 0 ? filename : filename.substring(0, dot);
    final extension = dot <= 0 ? '' : filename.substring(dot);
    var suffix = 2;
    while (usedPaths.contains(
      '$directory${stem}_$suffix$extension'.toLowerCase(),
    )) {
      suffix++;
    }
    return '$directory${stem}_$suffix$extension';
  }
}
