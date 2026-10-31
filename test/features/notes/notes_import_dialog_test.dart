import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_import_service.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/presentation/notes_import_dialog.dart';

void main() {
  testWidgets('cancel does not call the import operation', (tester) async {
    var importCalls = 0;
    final preview = NotesImportPreview(
      notes: [
        const PreparedNoteImport(
          newId: 'new-note',
          sourcePath: 'folder/note.md',
          title: 'Imported note',
          markdown: '# Exact content\n',
          duplicateTitle: false,
          folderPath: 'folder',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => NotesImportDialog(
                preview: preview,
                projectId: null,
                onImport: (_, _) async {
                  importCalls++;
                  return <WorkspaceNote>[];
                },
                onImported: (_) async {},
              ),
            ),
            child: const Text('Open import'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(importCalls, 0);
    expect(find.byType(NotesImportDialog), findsNothing);
  });

  testWidgets('requires collision choice before calling import', (
    tester,
  ) async {
    var importCalls = 0;
    final preview = NotesImportPreview(
      notes: [
        const PreparedNoteImport(
          newId: 'duplicate-note',
          sourcePath: 'note.md',
          title: 'Existing title',
          markdown: 'content',
          duplicateTitle: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => NotesImportDialog(
                preview: preview,
                projectId: null,
                onImport: (_, _) async {
                  importCalls++;
                  return <WorkspaceNote>[];
                },
                onImported: (_) async {},
              ),
            ),
            child: const Text('Open import'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(importCalls, 0);
    expect(
      find.text('Choose a new title or skip every duplicate-title note.'),
      findsOneWidget,
    );
  });
}
