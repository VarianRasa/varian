import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';

void main() {
  const boardId = '10000000-0000-4000-8000-000000000001';
  const operationId = '10000000-0000-4000-8000-000000000002';
  const cardId = '10000000-0000-4000-8000-000000000003';

  test('round trips typed card create and additive movement operations', () {
    final create = NotesCanvasCardCreateOperation(
      boardId: boardId,
      opId: operationId,
      replicaId: 'replica-a',
      replicaCounter: 1,
      dependencies: CrdtVersionVector(),
      card: const NotesCanvasTextCard(
        id: cardId,
        markdown: '',
        x: 0,
        y: 0,
        width: 300,
        height: 180,
      ),
    );
    final move = NotesCanvasCardMoveOperation(
      boardId: boardId,
      opId: '10000000-0000-4000-8000-000000000004',
      replicaId: 'replica-a',
      replicaCounter: 2,
      dependencies: CrdtVersionVector({'replica-a': 1}),
      cardId: cardId,
      dx: 15.5,
      dy: -8,
    );

    final decodedCreate = NotesCanvasOperation.fromJson(
      jsonDecode(create.encode()) as Map<String, dynamic>,
    );
    final decodedMove = NotesCanvasOperation.fromJson(
      jsonDecode(move.encode()) as Map<String, dynamic>,
    );

    expect(decodedCreate.toJson(), create.toJson());
    expect(decodedMove.toJson(), move.toJson());
    expect(decodedMove.dot.key, 'replica-a:2');
  });

  test('creates text cards empty before CRDT text operations', () {
    final operation = NotesCanvasCardCreateOperation(
      boardId: boardId,
      opId: operationId,
      replicaId: 'replica-a',
      replicaCounter: 1,
      dependencies: CrdtVersionVector(),
      card: const NotesCanvasTextCard(
        id: cardId,
        markdown: 'seed text',
        x: 0,
        y: 0,
        width: 300,
        height: 180,
      ),
    );

    expect(() => operation.validate(), throwsFormatException);
  });

  test('rejects counters beyond the JavaScript safe integer limit', () {
    const maxSafeInteger = 9007199254740991;
    const beyondSafeInteger = 9007199254740992;
    NotesCanvasCardTombstoneOperation(
      boardId: boardId,
      opId: operationId,
      replicaId: 'replica-a',
      replicaCounter: maxSafeInteger,
      dependencies: CrdtVersionVector(),
      cardId: cardId,
    ).validate();
    expect(
      () => NotesCanvasCardTombstoneOperation(
        boardId: boardId,
        opId: operationId,
        replicaId: 'replica-a',
        replicaCounter: beyondSafeInteger,
        dependencies: CrdtVersionVector(),
        cardId: cardId,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => NotesCanvasCardTombstoneOperation(
        boardId: boardId,
        opId: operationId,
        replicaId: 'replica-a',
        replicaCounter: 1,
        dependencies: CrdtVersionVector({'replica-b': beyondSafeInteger}),
        cardId: cardId,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => NotesCanvasTextInsertOperation(
        boardId: boardId,
        opId: operationId,
        replicaId: 'replica-a',
        replicaCounter: 1,
        dependencies: CrdtVersionVector(),
        cardId: cardId,
        after: const CrdtDot(actorId: 'replica-b', counter: beyondSafeInteger),
        text: 'a',
      ).validate(),
      throwsFormatException,
    );
  });

  test(
    'rejects invalid UUIDs, counters, movement, and multi-grapheme inserts',
    () {
      expect(
        () => NotesCanvasCardTombstoneOperation(
          boardId: boardId,
          opId: 'bad-id',
          replicaId: 'replica-a',
          replicaCounter: 1,
          dependencies: CrdtVersionVector(),
          cardId: cardId,
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => NotesCanvasCardMoveOperation(
          boardId: boardId,
          opId: operationId,
          replicaId: 'replica-a',
          replicaCounter: 0,
          dependencies: CrdtVersionVector(),
          cardId: cardId,
          dx: double.infinity,
          dy: 0,
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => NotesCanvasTextInsertOperation(
          boardId: boardId,
          opId: operationId,
          replicaId: 'replica-a',
          replicaCounter: 1,
          dependencies: CrdtVersionVector(),
          cardId: cardId,
          after: null,
          text: 'ab',
        ).validate(),
        throwsFormatException,
      );
    },
  );
}
