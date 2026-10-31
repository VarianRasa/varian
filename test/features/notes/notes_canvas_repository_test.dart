import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/notes/data/notes_canvas_repository.dart';
import 'package:varian/features/notes/domain/notes_canvas_board.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _authenticate(SupabaseClient client) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final token =
      '${_encodePart({'alg': 'HS256'})}.${_encodePart({'sub': 'account-a', 'exp': expiration})}.signature';
  client.auth.stopAutoRefresh();
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': {
        'id': 'account-a',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-01T00:00:00Z',
      },
    }),
  );
}

http.Response _response(Object body, http.Request request) => http.Response(
  jsonEncode(body),
  200,
  request: request,
  headers: {'content-type': 'application/json', 'content-range': '0-0/1'},
);

Map<String, dynamic> _boardRow(String id) {
  final document = NotesCanvasDocument.fromState(
    id,
    NotesCanvasBoardState.empty(),
  );
  return {
    'id': id,
    'owner_user_id': 'account-a',
    'created_by': 'account-a',
    'project_id': null,
    'title': 'Board',
    'state_json': document.boardState.toJson(),
    'crdt_snapshot_json': document.snapshotState(),
    'version_vector': document.versionVector.toJson(),
    'revision': 1,
    'snapshot_server_sequence': 0,
    'created_at': '2026-10-21T00:00:00Z',
    'updated_at': '2026-10-21T00:00:00Z',
  };
}

void main() {
  const boardId = '50000000-0000-4000-8000-000000000001';
  const cardId = '50000000-0000-4000-8000-000000000002';

  test('creates private board through scoped atomic RPC', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith(
          '/rpc/create_workspace_note_canvas_board',
        )) {
          return _response(_boardRow(boardId), request);
        }
        return _response([], request);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final document = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );

    final board = await NotesCanvasRepository(client).createBoard(
      boardId: boardId,
      title: 'Board',
      projectId: null,
      document: document,
      expectedAccountId: 'account-a',
    );

    expect(board.id, boardId);
    expect(board.projectId, isNull);
    final request = requests.singleWhere(
      (item) =>
          item.url.path.endsWith('/rpc/create_workspace_note_canvas_board'),
    );
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['p_board_id'], boardId);
    expect(body['p_project_id'], isNull);
    expect(body['p_state_json'], document.boardState.toJson());
    expect(body['p_crdt_snapshot_json'], document.snapshotState());
  });

  test(
    'append rechecks owner scope and sends a board-specific operation',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/workspace_note_canvas_boards')) {
            return _response([_boardRow(boardId)], request);
          }
          if (request.url.path.endsWith(
            '/rpc/append_workspace_note_canvas_operation',
          )) {
            return _response(7, request);
          }
          return _response([], request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final operation = NotesCanvasCardMoveOperation(
        boardId: boardId,
        opId: '50000000-0000-4000-8000-000000000003',
        replicaId: 'replica-a',
        replicaCounter: 1,
        dependencies: CrdtVersionVector(),
        cardId: cardId,
        dx: 5,
        dy: 3,
      );

      final sequence = await NotesCanvasRepository(client).appendOperation(
        boardId: boardId,
        operation: operation,
        expectedAccountId: 'account-a',
      );

      expect(sequence, 7);
      final request = requests.singleWhere(
        (item) => item.url.path.endsWith(
          '/rpc/append_workspace_note_canvas_operation',
        ),
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['p_board_id'], boardId);
      expect(body['p_operation'], operation.toJson());
    },
  );

  test(
    'refuses operations aimed at another board before network writes',
    () async {
      var writes = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          if (request.method == 'POST') writes++;
          if (request.url.path.endsWith('/workspace_note_canvas_boards')) {
            return _response([_boardRow(boardId)], request);
          }
          return _response(1, request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final operation = NotesCanvasCardMoveOperation(
        boardId: '50000000-0000-4000-8000-000000000004',
        opId: '50000000-0000-4000-8000-000000000005',
        replicaId: 'replica-a',
        replicaCounter: 1,
        dependencies: CrdtVersionVector(),
        cardId: cardId,
        dx: 1,
        dy: 1,
      );

      await expectLater(
        NotesCanvasRepository(client).appendOperation(
          boardId: boardId,
          operation: operation,
          expectedAccountId: 'account-a',
        ),
        throwsFormatException,
      );
      expect(writes, 0);
    },
  );
}
