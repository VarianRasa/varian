import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:characters/characters.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/collaboration/domain/crdt_text_sequence.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';

class NotesCanvasDocument {
  NotesCanvasDocument._({
    required this.boardId,
    required this._baseCards,
    required this._edges,
    required this._textSequences,
    required this._versionVector,
  });

  static const snapshotSchemaVersion = 2;
  static const maxSnapshotBytes = 20 * 1024 * 1024;

  final String boardId;
  final Map<String, NotesCanvasCard> _baseCards;
  final Map<String, NotesCanvasEdge> _edges;
  final Map<String, CrdtTextSequence> _textSequences;
  final Map<String, List<_CanvasMoveDelta>> _moveDeltas = {};
  final Map<String, NotesCanvasOperation> _pendingById = {};
  final Map<String, String> _pendingDots = {};
  CrdtVersionVector _versionVector;

  factory NotesCanvasDocument.fromState(
    String boardId,
    NotesCanvasBoardState state,
  ) {
    if (!_isUuid(boardId)) {
      throw const FormatException('Notes Canvas board ID must be a UUID.');
    }
    state.validate();
    final cards = {for (final card in state.cards) card.id: card};
    final sequences = <String, CrdtTextSequence>{};
    for (final card in state.cards) {
      if (card case final NotesCanvasTextCard textCard) {
        sequences[card.id] = CrdtTextSequence.seed(
          textCard.markdown,
          actorId: _seedActor(card.id),
        );
      }
    }
    return NotesCanvasDocument._(
      boardId: boardId,
      baseCards: cards,
      edges: {for (final edge in state.edges) edge.id: edge},
      textSequences: sequences,
      versionVector: CrdtVersionVector(),
    );
  }

  factory NotesCanvasDocument.fromSnapshot(Map<String, dynamic> snapshot) {
    if (snapshot['schema_version'] != snapshotSchemaVersion ||
        snapshot['board_id'] is! String ||
        snapshot['base_state'] is! Map ||
        snapshot['materialized_state'] is! Map) {
      throw const FormatException('Malformed Notes Canvas CRDT snapshot.');
    }
    try {
      final boardId = snapshot['board_id'] as String;
      final baseState = NotesCanvasBoardState.fromJson(
        Map<String, dynamic>.from(snapshot['base_state'] as Map),
      );
      final document = NotesCanvasDocument.fromState(boardId, baseState);
      document._versionVector = _readVersionVector(snapshot['version_vector']);

      final rawMoves = snapshot['move_deltas'];
      if (rawMoves is! Map) {
        throw const FormatException('Canvas movement snapshot is malformed.');
      }
      for (final entry in rawMoves.entries) {
        if (entry.key is! String || entry.value is! List) {
          throw const FormatException('Canvas movement snapshot is malformed.');
        }
        final cardId = entry.key as String;
        if (!document._baseCards.containsKey(cardId)) {
          throw const FormatException(
            'Canvas movement references a missing card.',
          );
        }
        final deltas = <_CanvasMoveDelta>[];
        for (final rawDelta in entry.value as List) {
          if (rawDelta is! Map) {
            throw const FormatException('Canvas movement delta is malformed.');
          }
          final delta = Map<String, dynamic>.from(rawDelta);
          final opId = _requiredString(delta, 'op_id');
          final dx = _requiredNumber(delta, 'dx');
          final dy = _requiredNumber(delta, 'dy');
          if (!_isUuid(opId) || !_validDelta(dx) || !_validDelta(dy)) {
            throw const FormatException('Canvas movement delta is invalid.');
          }
          deltas.add(_CanvasMoveDelta(opId: opId, dx: dx, dy: dy));
        }
        document._moveDeltas[cardId] = deltas;
      }

      final rawSequences = snapshot['text_sequences'];
      if (rawSequences is! Map) {
        throw const FormatException('Canvas text snapshot is malformed.');
      }
      for (final entry in rawSequences.entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException('Canvas text snapshot is malformed.');
        }
        final cardId = entry.key as String;
        if (document._baseCards[cardId] is! NotesCanvasTextCard) {
          throw const FormatException(
            'Canvas text snapshot references a non-text card.',
          );
        }
        _validateTextSequenceSnapshot(entry.value);
        document._textSequences[cardId] = CrdtTextSequence.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
      if (document._textSequences.length !=
          document._baseCards.values.whereType<NotesCanvasTextCard>().length) {
        throw const FormatException('Canvas text snapshot is incomplete.');
      }

      final rawPending = snapshot['pending_operations'];
      if (rawPending is! List) {
        throw const FormatException('Canvas pending operations are malformed.');
      }
      for (final rawOperation in rawPending) {
        final operation = NotesCanvasOperation.fromJson(
          _asStringMap(rawOperation),
        );
        if (operation.boardId != boardId ||
            operation.replicaCounter <=
                document._versionVector[operation.replicaId] ||
            operation.dependencies[operation.replicaId] !=
                operation.replicaCounter - 1) {
          throw const FormatException(
            'Canvas pending operation is inconsistent.',
          );
        }
        document._registerPending(operation);
      }
      final claimedState = NotesCanvasBoardState.fromJson(
        _asStringMap(snapshot['materialized_state']),
      );
      if (document.boardState != claimedState) {
        throw const FormatException(
          'Canvas CRDT snapshot does not match its materialized state.',
        );
      }
      if (utf8.encode(jsonEncode(snapshot)).length > maxSnapshotBytes) {
        throw const FormatException(
          'Canvas CRDT snapshot exceeds its size limit.',
        );
      }
      document.boardState.validate();
      return document;
    } on TypeError catch (error) {
      throw FormatException('Malformed Notes Canvas CRDT snapshot: $error');
    }
  }

  CrdtVersionVector get versionVector => _versionVector;
  int get pendingOperationCount => _pendingById.length;

  NotesCanvasBoardState get boardState {
    final cards = _baseCards.values.map((card) {
      final deltas = List<_CanvasMoveDelta>.of(_moveDeltas[card.id] ?? const [])
        ..sort((a, b) => a.opId.compareTo(b.opId));
      var x = card.x;
      var y = card.y;
      for (final delta in deltas) {
        x += delta.dx;
        y += delta.dy;
      }
      x = x
          .clamp(-NotesCanvasCard.maxCoordinate, NotesCanvasCard.maxCoordinate)
          .toDouble();
      y = y
          .clamp(-NotesCanvasCard.maxCoordinate, NotesCanvasCard.maxCoordinate)
          .toDouble();
      return switch (card) {
        NotesCanvasNoteCard() => NotesCanvasNoteCard(
          id: card.id,
          noteId: card.noteId,
          x: x,
          y: y,
          width: card.width,
          height: card.height,
          tombstoned: card.tombstoned,
        ),
        NotesCanvasTextCard() => NotesCanvasTextCard(
          id: card.id,
          markdown: _textSequences[card.id]!.visibleText,
          x: x,
          y: y,
          width: card.width,
          height: card.height,
          tombstoned: card.tombstoned,
        ),
      };
    });
    return NotesCanvasBoardState(cards: cards, edges: _edges.values);
  }

  List<NotesCanvasCard> get visibleCards => boardState.cards
      .where((card) => !card.tombstoned)
      .toList(growable: false);

  Map<String, dynamic> snapshotState() {
    final baseState = NotesCanvasBoardState(
      cards: _baseCards.values,
      edges: _edges.values,
    );
    final snapshot = <String, dynamic>{
      'schema_version': snapshotSchemaVersion,
      'board_id': boardId,
      'base_state': baseState.toJson(),
      'materialized_state': boardState.toJson(),
      'version_vector': _versionVector.toJson(),
      'move_deltas': {
        for (final entry in _moveDeltas.entries)
          entry.key:
              (List<_CanvasMoveDelta>.of(entry.value)
                    ..sort((a, b) => a.opId.compareTo(b.opId)))
                  .map((delta) => delta.toJson())
                  .toList(growable: false),
      },
      'text_sequences': {
        for (final entry in _textSequences.entries)
          entry.key: entry.value.toJson(),
      },
      'pending_operations': _pendingById.values
          .map((operation) => operation.toJson())
          .toList(growable: false),
    };
    if (utf8.encode(jsonEncode(snapshot)).length > maxSnapshotBytes) {
      throw const FormatException(
        'Canvas CRDT snapshot exceeds its size limit.',
      );
    }
    return snapshot;
  }

  NotesCanvasOperation createCard({
    required String replicaId,
    required NotesCanvasCard card,
  }) => _applyLocal(
    replicaId,
    (opId, counter, dependencies) => NotesCanvasCardCreateOperation(
      boardId: boardId,
      opId: opId,
      replicaId: replicaId,
      replicaCounter: counter,
      dependencies: dependencies,
      card: card,
    ),
  );

  List<NotesCanvasOperation> createTextCard({
    required String replicaId,
    required NotesCanvasTextCard card,
  }) {
    card.validate();
    final create = createCard(
      replicaId: replicaId,
      card: NotesCanvasTextCard(
        id: card.id,
        markdown: '',
        x: card.x,
        y: card.y,
        width: card.width,
        height: card.height,
        tombstoned: card.tombstoned,
      ),
    );
    return List.unmodifiable([
      create,
      ...insertText(
        replicaId: replicaId,
        cardId: card.id,
        offset: 0,
        text: card.markdown,
      ),
    ]);
  }

  NotesCanvasOperation tombstoneCard({
    required String replicaId,
    required String cardId,
  }) => _applyLocal(
    replicaId,
    (opId, counter, dependencies) => NotesCanvasCardTombstoneOperation(
      boardId: boardId,
      opId: opId,
      replicaId: replicaId,
      replicaCounter: counter,
      dependencies: dependencies,
      cardId: cardId,
    ),
  );

  NotesCanvasOperation moveCard({
    required String replicaId,
    required String cardId,
    required double dx,
    required double dy,
  }) => _applyLocal(
    replicaId,
    (opId, counter, dependencies) => NotesCanvasCardMoveOperation(
      boardId: boardId,
      opId: opId,
      replicaId: replicaId,
      replicaCounter: counter,
      dependencies: dependencies,
      cardId: cardId,
      dx: dx,
      dy: dy,
    ),
  );

  List<NotesCanvasOperation> insertText({
    required String replicaId,
    required String cardId,
    required int offset,
    required String text,
  }) {
    final sequence = _requireTextSequence(cardId);
    if (offset < 0 || offset > sequence.visibleIds().length) {
      throw RangeError.range(offset, 0, sequence.visibleIds().length, 'offset');
    }
    final operations = <NotesCanvasOperation>[];
    var insertionOffset = offset;
    for (final grapheme in text.characters) {
      final anchor = sequence.visibleIdBefore(insertionOffset);
      final operation = _applyLocal(
        replicaId,
        (opId, counter, dependencies) => NotesCanvasTextInsertOperation(
          boardId: boardId,
          opId: opId,
          replicaId: replicaId,
          replicaCounter: counter,
          dependencies: dependencies,
          cardId: cardId,
          after: anchor,
          text: grapheme,
        ),
      );
      operations.add(operation);
      insertionOffset++;
    }
    return List.unmodifiable(operations);
  }

  List<NotesCanvasOperation> deleteText({
    required String replicaId,
    required String cardId,
    required int start,
    required int end,
  }) {
    final sequence = _requireTextSequence(cardId);
    if (start < 0 || end < start || end > sequence.visibleIds().length) {
      throw RangeError('Invalid Notes Canvas text range.');
    }
    final targets = sequence
        .atomsForRange(start, end)
        .map((atom) => atom.id)
        .toList(growable: false);
    return List.unmodifiable(
      targets.map(
        (target) => _applyLocal(
          replicaId,
          (opId, counter, dependencies) => NotesCanvasTextDeleteOperation(
            boardId: boardId,
            opId: opId,
            replicaId: replicaId,
            replicaCounter: counter,
            dependencies: dependencies,
            cardId: cardId,
            target: target,
          ),
        ),
      ),
    );
  }

  NotesCanvasOperation createEdge({
    required String replicaId,
    required NotesCanvasEdge edge,
  }) => _applyLocal(
    replicaId,
    (opId, counter, dependencies) => NotesCanvasEdgeCreateOperation(
      boardId: boardId,
      opId: opId,
      replicaId: replicaId,
      replicaCounter: counter,
      dependencies: dependencies,
      edge: edge,
    ),
  );

  NotesCanvasOperation tombstoneEdge({
    required String replicaId,
    required String edgeId,
  }) => _applyLocal(
    replicaId,
    (opId, counter, dependencies) => NotesCanvasEdgeTombstoneOperation(
      boardId: boardId,
      opId: opId,
      replicaId: replicaId,
      replicaCounter: counter,
      dependencies: dependencies,
      edgeId: edgeId,
    ),
  );

  CrdtApplyStatus applyRemoteOperation(NotesCanvasOperation operation) {
    try {
      operation.validate();
    } on FormatException {
      return CrdtApplyStatus.rejected;
    }
    if (operation.boardId != boardId ||
        operation.dependencies[operation.replicaId] !=
            operation.replicaCounter - 1) {
      return CrdtApplyStatus.rejected;
    }

    final pending = _pendingById[operation.opId];
    if (pending != null) {
      return pending.encode() == operation.encode()
          ? CrdtApplyStatus.duplicate
          : CrdtApplyStatus.rejected;
    }
    final counter = _versionVector[operation.replicaId];
    if (operation.replicaCounter <= counter) return CrdtApplyStatus.duplicate;
    final pendingAtCounter = _pendingDots[_dotKey(operation)];
    if (pendingAtCounter != null) {
      return pendingAtCounter == operation.opId
          ? CrdtApplyStatus.duplicate
          : CrdtApplyStatus.rejected;
    }

    if (!_versionVector.satisfies(operation.dependencies) ||
        operation.replicaCounter != counter + 1) {
      _registerPending(operation);
      return CrdtApplyStatus.buffered;
    }
    if (!_apply(operation)) return CrdtApplyStatus.rejected;
    _drainPending();
    return CrdtApplyStatus.applied;
  }

  NotesCanvasOperation _applyLocal(
    String replicaId,
    NotesCanvasOperation Function(
      String opId,
      int counter,
      CrdtVersionVector dependencies,
    )
    build,
  ) {
    final operation = build(
      const Uuid().v4(),
      _versionVector[replicaId] + 1,
      _versionVector,
    );
    final status = applyRemoteOperation(operation);
    if (status != CrdtApplyStatus.applied) {
      throw StateError('The Notes Canvas operation could not be applied.');
    }
    return operation;
  }

  CrdtTextSequence _requireTextSequence(String cardId) {
    final sequence = _textSequences[cardId];
    if (sequence == null) {
      throw StateError('The Canvas text card is unavailable.');
    }
    return sequence;
  }

  bool _apply(NotesCanvasOperation operation) {
    final dot = operation.dot;
    switch (operation) {
      case NotesCanvasCardCreateOperation():
        final card = operation.card;
        if (_baseCards.containsKey(card.id) ||
            _baseCards.length >= NotesCanvasBoardState.maxCards) {
          return false;
        }
        _baseCards[card.id] = card;
        if (card case final NotesCanvasTextCard textCard) {
          _textSequences[card.id] = CrdtTextSequence.seed(
            textCard.markdown,
            actorId: _seedActor(card.id),
          );
        }
      case NotesCanvasCardTombstoneOperation():
        final card = _baseCards[operation.cardId];
        if (card == null) return false;
        _baseCards[card.id] = _withCardTombstone(card, true);
      case NotesCanvasCardMoveOperation():
        if (!_baseCards.containsKey(operation.cardId)) return false;
        _moveDeltas
            .putIfAbsent(operation.cardId, () => [])
            .add(
              _CanvasMoveDelta(
                opId: operation.opId,
                dx: operation.dx,
                dy: operation.dy,
              ),
            );
      case NotesCanvasTextInsertOperation():
        final sequence = _textSequences[operation.cardId];
        if (sequence == null ||
            (operation.after != null &&
                !sequence.atoms.any((atom) => atom.id == operation.after))) {
          return false;
        }
        sequence.insert(id: dot, after: operation.after, value: operation.text);
      case NotesCanvasTextDeleteOperation():
        final sequence = _textSequences[operation.cardId];
        if (sequence == null ||
            !sequence.atoms.any((atom) => atom.id == operation.target)) {
          return false;
        }
        sequence.delete(operation.target, dot);
      case NotesCanvasEdgeCreateOperation():
        final edge = operation.edge;
        if (_edges.containsKey(edge.id) ||
            _edges.length >= NotesCanvasBoardState.maxEdges ||
            !_baseCards.containsKey(edge.fromCardId) ||
            !_baseCards.containsKey(edge.toCardId)) {
          return false;
        }
        _edges[edge.id] = edge;
      case NotesCanvasEdgeTombstoneOperation():
        final edge = _edges[operation.edgeId];
        if (edge == null) return false;
        _edges[edge.id] = NotesCanvasEdge(
          id: edge.id,
          fromCardId: edge.fromCardId,
          toCardId: edge.toCardId,
          tombstoned: true,
        );
    }
    _versionVector = _versionVector.advance(dot);
    return true;
  }

  void _drainPending() {
    var progressed = true;
    while (progressed) {
      progressed = false;
      final pending = _pendingById.values.toList()
        ..sort((a, b) {
          final counterOrder = a.replicaCounter.compareTo(b.replicaCounter);
          if (counterOrder != 0) return counterOrder;
          final replicaOrder = a.replicaId.compareTo(b.replicaId);
          return replicaOrder != 0 ? replicaOrder : a.opId.compareTo(b.opId);
        });
      for (final operation in pending) {
        if (!_versionVector.satisfies(operation.dependencies) ||
            operation.replicaCounter !=
                _versionVector[operation.replicaId] + 1) {
          continue;
        }
        if (_apply(operation)) {
          _removePending(operation);
          progressed = true;
        }
      }
    }
  }

  void _registerPending(NotesCanvasOperation operation) {
    final dotKey = _dotKey(operation);
    final existingId = _pendingDots[dotKey];
    if (existingId != null && existingId != operation.opId) {
      throw const FormatException('Canvas replica counter is duplicated.');
    }
    _pendingById[operation.opId] = operation;
    _pendingDots[dotKey] = operation.opId;
  }

  void _removePending(NotesCanvasOperation operation) {
    _pendingById.remove(operation.opId);
    _pendingDots.remove(_dotKey(operation));
  }
}

class _CanvasMoveDelta {
  const _CanvasMoveDelta({
    required this.opId,
    required this.dx,
    required this.dy,
  });

  final String opId;
  final double dx;
  final double dy;

  Map<String, Object?> toJson() => {'op_id': opId, 'dx': dx, 'dy': dy};
}

String _seedActor(String cardId) => 'zzzz_canvas_snapshot_$cardId';

String _dotKey(NotesCanvasOperation operation) =>
    '${operation.replicaId}:${operation.replicaCounter}';

NotesCanvasCard _withCardTombstone(NotesCanvasCard card, bool tombstoned) =>
    switch (card) {
      NotesCanvasNoteCard() => NotesCanvasNoteCard(
        id: card.id,
        noteId: card.noteId,
        x: card.x,
        y: card.y,
        width: card.width,
        height: card.height,
        tombstoned: tombstoned,
      ),
      NotesCanvasTextCard() => NotesCanvasTextCard(
        id: card.id,
        markdown: card.markdown,
        x: card.x,
        y: card.y,
        width: card.width,
        height: card.height,
        tombstoned: tombstoned,
      ),
    };

void _validateTextSequenceSnapshot(Object? rawSequence) {
  if (rawSequence is! Map || rawSequence['atoms'] is! List) {
    throw const FormatException('Canvas text sequence is malformed.');
  }
  final atoms = rawSequence['atoms'] as List;
  final parents = <String, String?>{};
  for (final rawAtom in atoms) {
    if (rawAtom is! Map) {
      throw const FormatException('Canvas text atom is malformed.');
    }
    final id = _snapshotDotKey(rawAtom['id']);
    if (parents.containsKey(id)) {
      throw const FormatException('Canvas text atom ID is duplicated.');
    }
    final after = rawAtom['after'] == null
        ? null
        : _snapshotDotKey(rawAtom['after']);
    final value = rawAtom['value'];
    final deleted = rawAtom['deleted'] ?? false;
    if (value is! String || value.characters.length != 1 || deleted is! bool) {
      throw const FormatException('Canvas text atom is malformed.');
    }
    final deleteDot = rawAtom['deleteDot'] == null
        ? null
        : _snapshotDotKey(rawAtom['deleteDot']);
    if (deleted != (deleteDot != null)) {
      throw const FormatException('Canvas text tombstone is malformed.');
    }
    final formats = rawAtom['formats'];
    if (formats != null) {
      if (formats is! Map) {
        throw const FormatException('Canvas text formatting is malformed.');
      }
      for (final entry in formats.entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException('Canvas text formatting is malformed.');
        }
        final register = entry.value as Map;
        if (!register.containsKey('value')) {
          throw const FormatException('Canvas text formatting is malformed.');
        }
        _snapshotDotKey(register['dot']);
      }
    }
    parents[id] = after;
  }
  for (final parent in parents.values) {
    if (parent != null && !parents.containsKey(parent)) {
      throw const FormatException('Canvas text atom anchor is missing.');
    }
  }

  final completed = <String>{};
  for (final start in parents.keys) {
    final path = <String>[];
    final visiting = <String>{};
    String? current = start;
    while (current != null && !completed.contains(current)) {
      if (!visiting.add(current)) {
        throw const FormatException('Canvas text atoms contain a cycle.');
      }
      path.add(current);
      current = parents[current];
    }
    completed.addAll(path);
  }
}

String _snapshotDotKey(Object? rawDot) {
  if (rawDot is! Map) {
    throw const FormatException('Canvas text atom dot is malformed.');
  }
  final actor = rawDot['actorId'];
  final counter = rawDot['counter'];
  if (actor is! String ||
      actor.isEmpty ||
      actor.length > 128 ||
      counter is! int ||
      counter < 1) {
    throw const FormatException('Canvas text atom dot is malformed.');
  }
  return '$actor:$counter';
}

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

bool _validDelta(double value) =>
    value.isFinite && value.abs() <= NotesCanvasCard.maxCoordinate * 2;

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Canvas field "$key" is invalid.');
  }
  return value;
}

double _requiredNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('Canvas field "$key" is invalid.');
  return value.toDouble();
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected a JSON object.');
  return Map<String, dynamic>.from(value);
}

CrdtVersionVector _readVersionVector(Object? raw) {
  if (raw is! Map) {
    throw const FormatException('Canvas version vector is malformed.');
  }
  final values = <String, int>{};
  for (final entry in raw.entries) {
    final value = entry.value;
    if (entry.key is! String || value is! int || value < 0) {
      throw const FormatException('Canvas version vector is malformed.');
    }
    values[entry.key as String] = value;
  }
  return CrdtVersionVector(values);
}
