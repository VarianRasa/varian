import 'package:varian/features/notes/domain/notes_canvas_board.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';

abstract interface class NotesCanvasSyncTransport {
  Future<NotesCanvasBoard> getBoard({
    required String boardId,
    required String expectedAccountId,
  });

  Future<int> appendOperation({
    required String boardId,
    required NotesCanvasOperation operation,
    required String expectedAccountId,
  });

  Future<List<NotesCanvasOperationRecord>> listOperations({
    required String boardId,
    required int afterSequence,
    required String expectedAccountId,
    int limit = 500,
  });

  Future<NotesCanvasBoard> materializeSnapshot({
    required String boardId,
    required int expectedRevision,
    required int throughServerSequence,
    required NotesCanvasDocument document,
    required String expectedAccountId,
  });
}
