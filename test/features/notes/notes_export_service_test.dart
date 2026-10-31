import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_export_service.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_folder.dart';

void main() {
  final note = WorkspaceNote(
    id: '10000000-0000-4000-8000-000000000001',
    ownerUserId: 'private-user-id',
    title: 'Plan: Q&A?',
    markdownContent:
        '\uFEFF---\ntags: [work]\n---\nExact body\n<!--varian-note-id:12345678-1234-1234-1234-123456789abc-->\n',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    folderId: 'folder-child',
  );
  final folders = [
    WorkspaceNoteFolder(
      id: 'folder-parent',
      ownerUserId: 'private-user-id',
      name: 'Work',
      sortOrder: 0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
    WorkspaceNoteFolder(
      id: 'folder-child',
      ownerUserId: 'private-user-id',
      parentFolderId: 'folder-parent',
      name: 'Research',
      sortOrder: 0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  ];

  test('exports exact Markdown with stable safe paths and v1 manifest', () {
    final bytes = NotesExportService().exportZip([note], folders);
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = archive.files.where((entry) => entry.isFile).toList();
    final entriesByPath = {for (final entry in files) entry.name: entry};

    expect(entriesByPath.keys, contains('Work/Research/Plan_ Q&A_.md'));
    expect(entriesByPath.keys, contains('manifest.json'));
    expect(
      entriesByPath['Work/Research/Plan_ Q&A_.md']!.content,
      utf8.encode(note.markdownContent),
    );
    final manifest =
        jsonDecode(
              utf8.decode(entriesByPath['manifest.json']!.content as List<int>),
            )
            as Map<String, dynamic>;
    expect(manifest['format'], 'varian-notes');
    expect(manifest['schemaVersion'], 1);
    expect(manifest['notes'], [
      {
        'id': note.id,
        'path': 'Work/Research/Plan_ Q&A_.md',
        'title': note.title,
        'folder': 'Work/Research',
      },
    ]);
    final archiveText = utf8.decode(
      files.expand((entry) => entry.content as List<int>).toList(),
      allowMalformed: true,
    );
    expect(archiveText, isNot(contains('private-user-id')));
    expect(archiveText, isNot(contains('revision')));
  });

  test('rejects empty note selections', () {
    expect(
      () => NotesExportService().exportZip([], folders),
      throwsArgumentError,
    );
  });
}
