import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';

void main() {
  const boardId = '20000000-0000-4000-8000-000000000001';
  const cardId = '20000000-0000-4000-8000-000000000002';

  NotesCanvasBoardState initialState({String markdown = 'text'}) =>
      NotesCanvasBoardState(
        cards: [
          NotesCanvasTextCard(
            id: cardId,
            markdown: markdown,
            x: 10,
            y: 20,
            width: 300,
            height: 180,
          ),
        ],
      );

  test('concurrent additive moves converge in either delivery order', () {
    final origin = NotesCanvasDocument.fromState(boardId, initialState());
    final left = NotesCanvasDocument.fromSnapshot(origin.snapshotState());
    final right = NotesCanvasDocument.fromSnapshot(origin.snapshotState());
    final leftMove = left.moveCard(
      replicaId: 'replica-left',
      cardId: cardId,
      dx: 15,
      dy: -2,
    );
    final rightMove = right.moveCard(
      replicaId: 'replica-right',
      cardId: cardId,
      dx: -4,
      dy: 9,
    );

    left.applyRemoteOperation(rightMove);
    right.applyRemoteOperation(leftMove);

    expect(left.boardState.cards.single.x, 21);
    expect(left.boardState.cards.single.y, 27);
    expect(right.boardState, left.boardState);
  });

  test('buffers dependent operations and drains them without losing edits', () {
    final source = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );
    final create = source.createCard(
      replicaId: 'replica-a',
      card: const NotesCanvasTextCard(
        id: cardId,
        markdown: '',
        x: 0,
        y: 0,
        width: 200,
        height: 120,
      ),
    );
    final move = source.moveCard(
      replicaId: 'replica-a',
      cardId: cardId,
      dx: 20,
      dy: 5,
    );
    final receiver = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );

    expect(receiver.applyRemoteOperation(move), CrdtApplyStatus.buffered);
    expect(receiver.applyRemoteOperation(create), CrdtApplyStatus.applied);
    expect(receiver.boardState.cards.single.x, 20);
    expect(receiver.boardState.cards.single.y, 5);
  });

  test('retains a causally buffered operation when its target is invalid', () {
    const unknownCardId = '20000000-0000-4000-8000-000000000006';
    const createdCardId = '20000000-0000-4000-8000-000000000007';
    const waitingOperationId = '20000000-0000-4000-8000-000000000008';
    final source = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );
    final prerequisite = source.createCard(
      replicaId: 'replica-b',
      card: const NotesCanvasTextCard(
        id: createdCardId,
        markdown: '',
        x: 0,
        y: 0,
        width: 200,
        height: 120,
      ),
    );
    final waiting = NotesCanvasCardMoveOperation(
      boardId: boardId,
      opId: waitingOperationId,
      replicaId: 'replica-a',
      replicaCounter: 1,
      dependencies: CrdtVersionVector({'replica-a': 0, 'replica-b': 1}),
      cardId: unknownCardId,
      dx: 1,
      dy: 1,
    );
    final receiver = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );

    expect(receiver.applyRemoteOperation(waiting), CrdtApplyStatus.buffered);
    expect(
      receiver.applyRemoteOperation(prerequisite),
      CrdtApplyStatus.applied,
    );
    expect(receiver.pendingOperationCount, 1);
    expect(receiver.versionVector['replica-a'], 0);
  });

  test('rejects cyclic text atoms in a persisted snapshot', () {
    final document = NotesCanvasDocument.fromState(
      boardId,
      initialState(markdown: 'ab'),
    );
    final snapshot = document.snapshotState();
    final textSequences = snapshot['text_sequences'] as Map<String, dynamic>;
    final atoms = textSequences[cardId]!['atoms'] as List<dynamic>;
    final atom = Map<String, dynamic>.from(atoms.first as Map);
    atom['after'] = atom['id'];
    atoms[0] = atom;

    expect(
      () => NotesCanvasDocument.fromSnapshot(snapshot),
      throwsA(isA<FormatException>()),
    );
  });

  test('creates non-empty text cards through CRDT insert operations', () {
    const markdown = '# New note\n\nFirst paragraph';
    final document = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );
    const card = NotesCanvasTextCard(
      id: cardId,
      markdown: markdown,
      x: 10,
      y: 20,
      width: 300,
      height: 180,
    );

    final operations = document.createTextCard(
      replicaId: 'replica-a',
      card: card,
    );

    expect(operations, hasLength(markdown.length + 1));
    expect(operations.first, isA<NotesCanvasCardCreateOperation>());
    expect(
      operations.skip(1),
      everyElement(isA<NotesCanvasTextInsertOperation>()),
    );
    expect(
      (document.boardState.cards.single as NotesCanvasTextCard).markdown,
      markdown,
    );

    final replayed = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );
    for (final operation in operations) {
      expect(replayed.applyRemoteOperation(operation), CrdtApplyStatus.applied);
    }
    expect(replayed.boardState, document.boardState);
  });

  test(
    'text-card insertions converge and duplicate delivery is idempotent',
    () {
      final source = NotesCanvasDocument.fromState(boardId, initialState());
      final left = NotesCanvasDocument.fromSnapshot(source.snapshotState());
      final right = NotesCanvasDocument.fromSnapshot(source.snapshotState());
      final leftInsert = left
          .insertText(
            replicaId: 'replica-a',
            cardId: cardId,
            offset: 1,
            text: 'X',
          )
          .single;
      final rightInsert = right
          .insertText(
            replicaId: 'replica-b',
            cardId: cardId,
            offset: 1,
            text: 'Y',
          )
          .single;

      left.applyRemoteOperation(rightInsert);
      right.applyRemoteOperation(leftInsert);

      expect(left.boardState.cards.single, isA<NotesCanvasTextCard>());
      expect(
        (left.boardState.cards.single as NotesCanvasTextCard).markdown,
        'tXYext',
      );
      expect(right.boardState, left.boardState);
      expect(left.applyRemoteOperation(rightInsert), CrdtApplyStatus.duplicate);
    },
  );

  test(
    'tombstones hide cards without deleting their notes or inbound edges',
    () {
      const noteCardId = '20000000-0000-4000-8000-000000000003';
      const edgeId = '20000000-0000-4000-8000-000000000004';
      final document = NotesCanvasDocument.fromState(
        boardId,
        NotesCanvasBoardState(
          cards: const [
            NotesCanvasNoteCard(
              id: noteCardId,
              noteId: '20000000-0000-4000-8000-000000000005',
              x: 0,
              y: 0,
              width: 200,
              height: 120,
            ),
            NotesCanvasTextCard(
              id: cardId,
              markdown: 'text',
              x: 300,
              y: 0,
              width: 200,
              height: 120,
            ),
          ],
          edges: const [
            NotesCanvasEdge(
              id: edgeId,
              fromCardId: noteCardId,
              toCardId: cardId,
            ),
          ],
        ),
      );

      document.tombstoneCard(replicaId: 'replica-a', cardId: noteCardId);

      expect(document.visibleCards.map((card) => card.id), [cardId]);
      expect(document.boardState.edges.single.tombstoned, isFalse);
      expect(
        document.boardState.cards
            .singleWhere((card) => card.id == noteCardId)
            .tombstoned,
        isTrue,
      );
    },
  );

  test('renders long text cards without recursive traversal', () {
    final text = List.filled(20000, 'x').join();
    final document = NotesCanvasDocument.fromState(
      boardId,
      initialState(markdown: text),
    );

    expect(
      (document.boardState.cards.single as NotesCanvasTextCard).markdown,
      text,
    );
  });

  test(
    'snapshot round trips movement, text CRDT, and operation deduplication',
    () {
      final document = NotesCanvasDocument.fromState(boardId, initialState());
      document.moveCard(replicaId: 'replica-a', cardId: cardId, dx: 7, dy: 8);
      final insert = document
          .insertText(
            replicaId: 'replica-a',
            cardId: cardId,
            offset: 4,
            text: '!',
          )
          .single;
      final restored = NotesCanvasDocument.fromSnapshot(
        document.snapshotState(),
      );

      expect(restored.boardState, document.boardState);
      expect(restored.applyRemoteOperation(insert), CrdtApplyStatus.duplicate);
    },
  );
}
