import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/notes_canvas_board.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';

void main() {
  const boardId = '40000000-0000-4000-8000-000000000001';
  const accountId = '40000000-0000-4000-8000-000000000002';

  test('parses a private board with an aligned state and CRDT snapshot', () {
    final document = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );
    final board = NotesCanvasBoard.fromJson({
      'id': boardId,
      'owner_user_id': accountId,
      'created_by': accountId,
      'project_id': null,
      'title': 'Research',
      'state_json': document.boardState.toJson(),
      'crdt_snapshot_json': document.snapshotState(),
      'version_vector': document.versionVector.toJson(),
      'revision': 1,
      'snapshot_server_sequence': 0,
      'created_at': '2026-10-21T00:00:00Z',
      'updated_at': '2026-10-21T00:00:00Z',
    });

    expect(board.id, boardId);
    expect(board.ownerUserId, accountId);
    expect(board.projectId, isNull);
    expect(board.title, 'Research');
    expect(board.state, NotesCanvasBoardState.empty());
    expect(board.revision, 1);
    expect(board.snapshotServerSequence, 0);
  });

  test('rejects mismatched state, snapshot, and scope row data', () {
    final document = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );
    final row = {
      'id': boardId,
      'owner_user_id': accountId,
      'created_by': accountId,
      'project_id': null,
      'title': 'Research',
      'state_json': {'schema_version': 1, 'cards': [], 'edges': []},
      'crdt_snapshot_json': document.snapshotState(),
      'version_vector': {'replica-a': 1},
      'revision': 1,
      'snapshot_server_sequence': 0,
      'created_at': '2026-10-21T00:00:00Z',
      'updated_at': '2026-10-21T00:00:00Z',
    };

    expect(() => NotesCanvasBoard.fromJson(row), throwsFormatException);
    expect(
      () => NotesCanvasBoard.fromJson({...row, 'id': 'not-a-uuid'}),
      throwsFormatException,
    );
  });
}
