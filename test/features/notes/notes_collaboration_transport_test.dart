import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_collaboration_transport.dart';

void main() {
  group('NotesCursorAnchor', () {
    test('round trips CRDT atom anchors without positions or text', () {
      const anchor = NotesCursorAnchor(atomId: 'replica:4', bias: 'after');
      expect(NotesCursorAnchor.fromJson(anchor.toJson())?.atomId, 'replica:4');
      expect(anchor.toJson().keys, containsAll(['atomId', 'bias']));
      expect(anchor.toJson().containsKey('text'), isFalse);
    });

    test('rejects malformed anchors', () {
      expect(
        NotesCursorAnchor.fromJson({'atomId': 4, 'bias': 'after'}),
        isNull,
      );
      expect(
        NotesCursorAnchor.fromJson({'atomId': 'x', 'bias': 'middle'}),
        isNull,
      );
      expect(NotesCursorAnchor.fromJson('markdown'), isNull);
      expect(
        NotesCursorAnchor.fromJson({
          'atomId': 'x',
          'bias': 'after',
          'text': 'secret',
        }),
        isNull,
      );
    });
  });

  test('operation hints include only an ID scoped to this note', () {
    expect(
      parseNotesOperationHint({'operationId': 'note-a:replica:9'}, 'note-a'),
      'note-a:replica:9',
    );
    expect(
      parseNotesOperationHint({'operationId': 'note-b:replica:9'}, 'note-a'),
      isNull,
    );
    expect(
      parseNotesOperationHint({
        'operationId': 'note-a:replica:9',
        'markdown': 'secret',
      }, 'note-a'),
      isNull,
    );
  });

  test('cursor payload accepts only anchors and removes departed cursors', () {
    final cursor = parseNotesCursorPayload({
      'userId': 'peer',
      'anchor': {'atomId': 'replica:1', 'bias': 'after'},
    }, localUserId: 'local');
    expect(cursor?.userId, 'peer');
    expect(cursor?.anchor?.atomId, 'replica:1');
    expect(
      parseNotesCursorPayload({
        'userId': 'peer',
        'anchor': null,
      }, localUserId: 'local')?.anchor,
      isNull,
    );
    expect(
      parseNotesCursorPayload({
        'userId': 'peer',
        'anchor': null,
        'markdown': 'secret',
      }, localUserId: 'local'),
      isNull,
    );
  });
}
