import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/note_markdown_metadata.dart';
import 'package:varian/features/notes/presentation/notes_properties_panel.dart';

void main() {
  testWidgets('adds a property without changing other source', (tester) async {
    const source = '---\nunknown: keep\n---\nBody stays exact\n';
    var updated = source;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 560,
            child: NotesPropertiesPanel(
              markdown: source,
              onMarkdownChanged: (value) => updated = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('notes-property-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('note-property-key-input')),
      'status',
    );
    await tester.enterText(
      find.byKey(const ValueKey('note-property-value-input')),
      'Draft',
    );
    await tester.tap(find.byKey(const ValueKey('note-property-save')));
    await tester.pumpAndSettle();

    final metadata = parseNoteMarkdownMetadata(updated);
    expect((metadata.yaml as Map)['status'], 'Draft');
    expect((metadata.yaml as Map)['unknown'], 'keep');
    expect(metadata.body, 'Body stays exact\n');
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits and removes a typed property', (tester) async {
    const source = '---\ndone: false\nkeep: true\n---\nBody';
    var updated = source;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 560,
            child: NotesPropertiesPanel(
              markdown: source,
              onMarkdownChanged: (value) => updated = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('notes-property-edit-done')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('note-property-checkbox-input')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('note-property-checkbox-input')),
    );
    await tester.tap(find.byKey(const ValueKey('note-property-save')));
    await tester.pumpAndSettle();

    expect((parseNoteMarkdownMetadata(updated).yaml as Map)['done'], isTrue);
    expect((parseNoteMarkdownMetadata(updated).yaml as Map)['keep'], isTrue);
    await tester.tap(find.byKey(const ValueKey('notes-property-remove-done')));
    await tester.pumpAndSettle();
    expect(
      (parseNoteMarkdownMetadata(updated).yaml as Map).containsKey('done'),
      isFalse,
    );
    expect((parseNoteMarkdownMetadata(updated).yaml as Map)['keep'], isTrue);
  });

  testWidgets('does not offer destructive edits for invalid frontmatter', (
    tester,
  ) async {
    const source = '---\ntags: [broken\n---\nBody';
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 560,
            child: NotesPropertiesPanel(
              markdown: source,
              onMarkdownChanged: (_) => changed = true,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Malformed YAML frontmatter'), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-property-add')), findsNothing);
    expect(changed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
