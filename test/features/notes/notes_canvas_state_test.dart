import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';

void main() {
  const noteId = '00000000-0000-4000-8000-000000000001';
  const textCardId = '00000000-0000-4000-8000-000000000002';
  const edgeId = '00000000-0000-4000-8000-000000000003';

  test('round trips version-one note and text cards with stable edges', () {
    final state = NotesCanvasBoardState(
      cards: const [
        NotesCanvasNoteCard(
          id: noteId,
          noteId: '00000000-0000-4000-8000-000000000004',
          x: -120,
          y: 40,
          width: 300,
          height: 220,
        ),
        NotesCanvasTextCard(
          id: textCardId,
          markdown: '# Sketch',
          x: 220,
          y: 80,
          width: 400,
          height: 240,
        ),
      ],
      edges: const [
        NotesCanvasEdge(id: edgeId, fromCardId: noteId, toCardId: textCardId),
      ],
    );

    final decoded = NotesCanvasBoardState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.schemaVersion, 1);
    expect(decoded.cards, state.cards);
    expect(decoded.edges, state.edges);
  });

  test('rejects unsupported schema versions and unknown card types', () {
    expect(
      () => NotesCanvasBoardState.fromJson({'schema_version': 2}),
      throwsFormatException,
    );
    expect(
      () => NotesCanvasBoardState.fromJson({
        'schema_version': 1,
        'cards': [
          {
            'id': noteId,
            'type': 'image',
            'x': 0,
            'y': 0,
            'width': 1,
            'height': 1,
          },
        ],
        'edges': [],
      }),
      throwsFormatException,
    );
  });

  test('rejects non-finite or out-of-range geometry and malformed IDs', () {
    expect(
      () => NotesCanvasTextCard(
        id: textCardId,
        markdown: 'text',
        x: double.nan,
        y: 0,
        width: 100,
        height: 100,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => NotesCanvasTextCard(
        id: 'not-a-uuid',
        markdown: 'text',
        x: 0,
        y: 0,
        width: 100,
        height: 100,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => NotesCanvasTextCard(
        id: textCardId,
        markdown: 'text',
        x: 0,
        y: 0,
        width: 0,
        height: 100,
      ).validate(),
      throwsFormatException,
    );
  });

  test('enforces unique card and edge IDs and existing edge endpoints', () {
    const card = NotesCanvasTextCard(
      id: textCardId,
      markdown: 'text',
      x: 0,
      y: 0,
      width: 100,
      height: 100,
    );
    expect(
      () => NotesCanvasBoardState(cards: [card, card]).validate(),
      throwsFormatException,
    );
    expect(
      () => NotesCanvasBoardState(
        cards: const [card],
        edges: const [
          NotesCanvasEdge(id: edgeId, fromCardId: textCardId, toCardId: noteId),
        ],
      ).validate(),
      throwsFormatException,
    );
  });

  test('enforces text-card and serialized board byte limits', () {
    expect(
      () => NotesCanvasTextCard(
        id: textCardId,
        markdown: List.filled(
          NotesCanvasBoardState.maxTextCardBytes + 1,
          'a',
        ).join(),
        x: 0,
        y: 0,
        width: 100,
        height: 100,
      ).validate(),
      throwsFormatException,
    );
  });
}
