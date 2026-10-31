import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/state/notes_collaboration_provider.dart';
import 'package:varian/features/notes/data/notes_collaboration_transport.dart';

void main() {
  test('initial state has no cursors and is disconnected', () {
    expect(
      const NotesCollaborationState().connection,
      NotesConnectionState.disconnected,
    );
    expect(const NotesCollaborationState().cursors, isEmpty);
  });

  test(
    'connection states include membership denial and reconnect-capable error',
    () {
      expect(
        NotesConnectionState.values,
        contains(NotesConnectionState.denied),
      );
      expect(NotesConnectionState.values, contains(NotesConnectionState.error));
    },
  );

  test('anchor parser accepts only CRDT anchor shape', () {
    final decoded = NotesCursorAnchor.fromJson({
      'atomId': null,
      'bias': 'before',
    });
    expect(decoded?.atomId, isNull);
    expect(decoded?.bias, 'before');
  });
}
