import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/notes/domain/notes_canvas_board.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';
import 'package:varian/features/notes/data/notes_canvas_sync_transport.dart';

final notesCanvasRepositoryProvider = Provider<NotesCanvasRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) throw StateError('Notes require a configured account.');
  return NotesCanvasRepository(client);
});

class NotesCanvasRevisionConflictException implements Exception {
  const NotesCanvasRevisionConflictException();
}

class NotesCanvasUnavailableException implements Exception {
  const NotesCanvasUnavailableException();
}

class NotesCanvasRepository implements NotesCanvasSyncTransport {
  NotesCanvasRepository(this._client);

  static const _boardColumns =
      'id, owner_user_id, created_by, project_id, title, state_json, crdt_snapshot_json, version_vector, revision, snapshot_server_sequence, created_at, updated_at';
  final SupabaseClient _client;

  String _requireAccount(String? expectedAccountId) {
    final auth = _client.auth;
    final user = auth.currentSession?.user ?? auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Sign in to access Notes Canvas.');
    }
    if (expectedAccountId != null && user.id != expectedAccountId) {
      throw StateError('The signed-in account changed during this action.');
    }
    return user.id;
  }

  Future<void> _requireProjectEdit(String? projectId, String accountId) async {
    if (projectId == null) return;
    final allowed = await _client.rpc(
      'can_edit_project',
      params: {'p_project_id': projectId},
    );
    _requireAccount(accountId);
    if (allowed != true) {
      throw StateError('Project edit membership required.');
    }
  }

  Future<List<NotesCanvasBoard>> listBoards({
    required String? projectId,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final rows = projectId == null
        ? await _client
              .from('workspace_note_canvas_boards')
              .select(_boardColumns)
              .isFilter('project_id', null)
              .eq('owner_user_id', accountId)
              .order('updated_at', ascending: false)
        : await _client
              .from('workspace_note_canvas_boards')
              .select(_boardColumns)
              .eq('project_id', projectId)
              .order('updated_at', ascending: false);
    _requireAccount(accountId);
    return rows
        .map((row) => NotesCanvasBoard.fromJson(row))
        .toList(growable: false);
  }

  Future<NotesCanvasBoard> getBoard({
    required String boardId,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final row = await _client
        .from('workspace_note_canvas_boards')
        .select(_boardColumns)
        .eq('id', boardId)
        .maybeSingle();
    _requireAccount(accountId);
    if (row == null) throw const NotesCanvasUnavailableException();
    return NotesCanvasBoard.fromJson(row);
  }

  Future<NotesCanvasBoard> createBoard({
    required String boardId,
    required String title,
    required String? projectId,
    required NotesCanvasDocument document,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (document.boardId != boardId ||
        title.trim().isEmpty ||
        title.trim().length > 120) {
      throw const FormatException('Notes Canvas board input is invalid.');
    }
    document.boardState.validate();
    await _requireProjectEdit(projectId, accountId);
    await _assertNoteReferences(
      document.boardState,
      ownerUserId: accountId,
      projectId: projectId,
      accountId: accountId,
    );
    final raw = await _client.rpc(
      'create_workspace_note_canvas_board',
      params: {
        'p_board_id': boardId,
        'p_title': title.trim(),
        'p_project_id': projectId,
        'p_state_json': document.boardState.toJson(),
        'p_crdt_snapshot_json': document.snapshotState(),
        'p_version_vector': document.versionVector.toJson(),
      },
    );
    _requireAccount(accountId);
    return NotesCanvasBoard.fromJson(_recordMap(raw));
  }

  Future<int> appendOperation({
    required String boardId,
    required NotesCanvasOperation operation,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    operation.validate();
    if (operation.boardId != boardId) {
      throw const FormatException('Canvas operation targets another board.');
    }
    final board = await getBoard(
      boardId: boardId,
      expectedAccountId: accountId,
    );
    await _requireProjectEdit(board.projectId, accountId);
    if (operation case final NotesCanvasCardCreateOperation create) {
      final state = NotesCanvasBoardState(cards: [create.card]);
      await _assertNoteReferences(
        state,
        ownerUserId: board.ownerUserId,
        projectId: board.projectId,
        accountId: accountId,
      );
    }
    final raw = await _client.rpc(
      'append_workspace_note_canvas_operation',
      params: {'p_board_id': boardId, 'p_operation': operation.toJson()},
    );
    _requireAccount(accountId);
    final sequence = raw is int ? raw : int.tryParse(raw.toString());
    if (sequence == null || sequence < 1) {
      throw const FormatException('Canvas server sequence is invalid.');
    }
    return sequence;
  }

  Future<List<NotesCanvasOperationRecord>> listOperations({
    required String boardId,
    required int afterSequence,
    required String expectedAccountId,
    int limit = 500,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (afterSequence < 0) {
      throw RangeError.value(afterSequence, 'afterSequence');
    }
    final raw = await _client.rpc(
      'get_workspace_note_canvas_delta',
      params: {
        'p_board_id': boardId,
        'p_after_sequence': afterSequence,
        'p_limit': limit.clamp(1, 1000),
      },
    );
    _requireAccount(accountId);
    if (raw is! List) {
      throw const FormatException('Canvas operation delta is malformed.');
    }
    final records = raw
        .map((item) => NotesCanvasOperationRecord.fromJson(_recordMap(item)))
        .toList(growable: false);
    var previousSequence = afterSequence;
    for (final record in records) {
      if (record.serverSequence <= previousSequence ||
          record.operation.boardId != boardId) {
        throw const FormatException('Canvas operation delta is out of order.');
      }
      previousSequence = record.serverSequence;
    }
    return records;
  }

  Future<NotesCanvasBoard> materializeSnapshot({
    required String boardId,
    required int expectedRevision,
    required int throughServerSequence,
    required NotesCanvasDocument document,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    if (document.boardId != boardId ||
        expectedRevision < 1 ||
        throughServerSequence < 0) {
      throw const FormatException('Canvas snapshot input is invalid.');
    }
    final board = await getBoard(
      boardId: boardId,
      expectedAccountId: accountId,
    );
    await _requireProjectEdit(board.projectId, accountId);
    document.boardState.validate();
    await _assertNoteReferences(
      document.boardState,
      ownerUserId: board.ownerUserId,
      projectId: board.projectId,
      accountId: accountId,
    );
    try {
      final raw = await _client.rpc(
        'materialize_workspace_note_canvas',
        params: {
          'p_board_id': boardId,
          'p_expected_revision': expectedRevision,
          'p_state_json': document.boardState.toJson(),
          'p_crdt_snapshot_json': document.snapshotState(),
          'p_version_vector': document.versionVector.toJson(),
          'p_snapshot_server_sequence': throughServerSequence,
        },
      );
      _requireAccount(accountId);
      return NotesCanvasBoard.fromJson(_recordMap(raw));
    } on PostgrestException catch (error) {
      _requireAccount(accountId);
      if (error.code == '40001' ||
          error.message.contains('workspace_note_canvas_revision_conflict')) {
        throw const NotesCanvasRevisionConflictException();
      }
      rethrow;
    }
  }

  Future<void> deleteBoard({
    required String boardId,
    required String expectedAccountId,
  }) async {
    final accountId = _requireAccount(expectedAccountId);
    final board = await getBoard(
      boardId: boardId,
      expectedAccountId: accountId,
    );
    await _requireProjectEdit(board.projectId, accountId);
    final deleted = await _client.rpc(
      'delete_workspace_note_canvas_board',
      params: {'p_board_id': boardId},
    );
    _requireAccount(accountId);
    if (deleted != true) throw const NotesCanvasUnavailableException();
  }

  Future<void> _assertNoteReferences(
    NotesCanvasBoardState state, {
    required String ownerUserId,
    required String? projectId,
    required String accountId,
  }) async {
    for (final card in state.cards.whereType<NotesCanvasNoteCard>()) {
      final row = await _client
          .from('workspace_notes')
          .select('id, owner_user_id, project_id, deleted_at')
          .eq('id', card.noteId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      _requireAccount(accountId);
      if (row == null ||
          row['project_id'] != projectId ||
          (projectId == null && row['owner_user_id'] != ownerUserId)) {
        throw const NotesCanvasUnavailableException();
      }
    }
  }
}

Map<String, dynamic> _recordMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is List && value.length == 1 && value.single is Map) {
    return Map<String, dynamic>.from(value.single as Map);
  }
  throw const FormatException('Canvas server returned an invalid board.');
}
