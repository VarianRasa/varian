import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:characters/characters.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';

sealed class NotesCanvasOperation {
  const NotesCanvasOperation({
    required this.boardId,
    required this.opId,
    required this.replicaId,
    required this.replicaCounter,
    required this.dependencies,
  });

  static const maxEncodedBytes = 256 * 1024;
  static const _maxCounter = 9007199254740991;

  final String boardId;
  final String opId;
  final String replicaId;
  final int replicaCounter;
  final CrdtVersionVector dependencies;

  CrdtDot get dot => CrdtDot(actorId: replicaId, counter: replicaCounter);
  String get type;

  Map<String, Object?> get payload;

  Map<String, Object?> toJson() => {
    'board_id': boardId,
    'op_id': opId,
    'replica_id': replicaId,
    'replica_counter': replicaCounter,
    'dependencies': dependencies.toJson(),
    'type': type,
    ...payload,
  };

  String encode() {
    validate();
    return jsonEncode(toJson());
  }

  void validate() {
    if (!_isUuid(boardId) || !_isUuid(opId)) {
      throw const FormatException(
        'Canvas board and operation IDs must be UUIDs.',
      );
    }
    if (replicaId.trim().isEmpty || replicaId.length > 128) {
      throw const FormatException('Canvas replica ID is invalid.');
    }
    if (replicaCounter < 1 || replicaCounter > _maxCounter) {
      throw const FormatException('Canvas replica counter is invalid.');
    }
    for (final entry in dependencies.values.entries) {
      if (entry.key.trim().isEmpty ||
          entry.key.length > 128 ||
          entry.value < 0 ||
          entry.value > _maxCounter) {
        throw const FormatException('Canvas dependencies are invalid.');
      }
    }
    validatePayload();
    if (utf8.encode(jsonEncode(toJson())).length > maxEncodedBytes) {
      throw const FormatException('Canvas operation exceeds 256 KiB.');
    }
  }

  void validatePayload();

  static NotesCanvasOperation fromJson(Map<String, dynamic> json) {
    try {
      final boardId = _requiredString(json, 'board_id');
      final opId = _requiredString(json, 'op_id');
      final replicaId = _requiredString(json, 'replica_id');
      final replicaCounter = _requiredInt(json, 'replica_counter');
      final dependencies = _readVersionVector(json['dependencies']);
      final operation = switch (json['type']) {
        'card_create' => NotesCanvasCardCreateOperation(
          boardId: boardId,
          opId: opId,
          replicaId: replicaId,
          replicaCounter: replicaCounter,
          dependencies: dependencies,
          card: NotesCanvasCard.fromJson(_asStringMap(json['card'])),
        ),
        'card_tombstone' => NotesCanvasCardTombstoneOperation(
          boardId: boardId,
          opId: opId,
          replicaId: replicaId,
          replicaCounter: replicaCounter,
          dependencies: dependencies,
          cardId: _requiredString(json, 'card_id'),
        ),
        'card_move' => NotesCanvasCardMoveOperation(
          boardId: boardId,
          opId: opId,
          replicaId: replicaId,
          replicaCounter: replicaCounter,
          dependencies: dependencies,
          cardId: _requiredString(json, 'card_id'),
          dx: _requiredNumber(json, 'dx'),
          dy: _requiredNumber(json, 'dy'),
        ),
        'text_insert' => NotesCanvasTextInsertOperation(
          boardId: boardId,
          opId: opId,
          replicaId: replicaId,
          replicaCounter: replicaCounter,
          dependencies: dependencies,
          cardId: _requiredString(json, 'card_id'),
          after: json['after'] == null
              ? null
              : CrdtDot.fromJson(_asStringMap(json['after'])),
          text: _requiredString(json, 'text'),
        ),
        'text_delete' => NotesCanvasTextDeleteOperation(
          boardId: boardId,
          opId: opId,
          replicaId: replicaId,
          replicaCounter: replicaCounter,
          dependencies: dependencies,
          cardId: _requiredString(json, 'card_id'),
          target: CrdtDot.fromJson(_asStringMap(json['target'])),
        ),
        'edge_create' => NotesCanvasEdgeCreateOperation(
          boardId: boardId,
          opId: opId,
          replicaId: replicaId,
          replicaCounter: replicaCounter,
          dependencies: dependencies,
          edge: NotesCanvasEdge.fromJson(_asStringMap(json['edge'])),
        ),
        'edge_tombstone' => NotesCanvasEdgeTombstoneOperation(
          boardId: boardId,
          opId: opId,
          replicaId: replicaId,
          replicaCounter: replicaCounter,
          dependencies: dependencies,
          edgeId: _requiredString(json, 'edge_id'),
        ),
        _ => throw const FormatException('Unknown Notes Canvas operation.'),
      };
      operation.validate();
      return operation;
    } on TypeError catch (error) {
      throw FormatException('Malformed Notes Canvas operation: $error');
    }
  }
}

final class NotesCanvasCardCreateOperation extends NotesCanvasOperation {
  const NotesCanvasCardCreateOperation({
    required super.boardId,
    required super.opId,
    required super.replicaId,
    required super.replicaCounter,
    required super.dependencies,
    required this.card,
  });

  final NotesCanvasCard card;

  @override
  String get type => 'card_create';

  @override
  Map<String, Object?> get payload => {'card': card.toJson()};

  @override
  void validatePayload() {
    if (card case final NotesCanvasNoteCard noteCard) {
      noteCard.validate();
    } else if (card case final NotesCanvasTextCard textCard) {
      textCard.validate();
      if (textCard.markdown.isNotEmpty) {
        throw const FormatException(
          'Canvas text cards must be created empty before inserting text.',
        );
      }
    }
    if (card.tombstoned) {
      throw const FormatException(
        'A created Canvas card cannot be tombstoned.',
      );
    }
  }
}

final class NotesCanvasCardTombstoneOperation extends NotesCanvasOperation {
  const NotesCanvasCardTombstoneOperation({
    required super.boardId,
    required super.opId,
    required super.replicaId,
    required super.replicaCounter,
    required super.dependencies,
    required this.cardId,
  });

  final String cardId;

  @override
  String get type => 'card_tombstone';

  @override
  Map<String, Object?> get payload => {'card_id': cardId};

  @override
  void validatePayload() => _requireUuid(cardId, 'Canvas card ID');
}

final class NotesCanvasCardMoveOperation extends NotesCanvasOperation {
  const NotesCanvasCardMoveOperation({
    required super.boardId,
    required super.opId,
    required super.replicaId,
    required super.replicaCounter,
    required super.dependencies,
    required this.cardId,
    required this.dx,
    required this.dy,
  });

  final String cardId;
  final double dx;
  final double dy;

  @override
  String get type => 'card_move';

  @override
  Map<String, Object?> get payload => {'card_id': cardId, 'dx': dx, 'dy': dy};

  @override
  void validatePayload() {
    _requireUuid(cardId, 'Canvas card ID');
    if (!_isBoundedDelta(dx) || !_isBoundedDelta(dy)) {
      throw const FormatException('Canvas movement delta is out of bounds.');
    }
  }
}

final class NotesCanvasTextInsertOperation extends NotesCanvasOperation {
  const NotesCanvasTextInsertOperation({
    required super.boardId,
    required super.opId,
    required super.replicaId,
    required super.replicaCounter,
    required super.dependencies,
    required this.cardId,
    required this.after,
    required this.text,
  });

  final String cardId;
  final CrdtDot? after;
  final String text;

  @override
  String get type => 'text_insert';

  @override
  Map<String, Object?> get payload => {
    'card_id': cardId,
    'after': after?.toJson(),
    'text': text,
  };

  @override
  void validatePayload() {
    _requireUuid(cardId, 'Canvas text card ID');
    if (text.isEmpty ||
        text.characters.length != 1 ||
        utf8.encode(text).length > NotesCanvasTextCard.maxMarkdownBytes) {
      throw const FormatException(
        'Canvas text insertion must be one grapheme.',
      );
    }
    if (after != null) _validateDot(after!);
  }
}

final class NotesCanvasTextDeleteOperation extends NotesCanvasOperation {
  const NotesCanvasTextDeleteOperation({
    required super.boardId,
    required super.opId,
    required super.replicaId,
    required super.replicaCounter,
    required super.dependencies,
    required this.cardId,
    required this.target,
  });

  final String cardId;
  final CrdtDot target;

  @override
  String get type => 'text_delete';

  @override
  Map<String, Object?> get payload => {
    'card_id': cardId,
    'target': target.toJson(),
  };

  @override
  void validatePayload() {
    _requireUuid(cardId, 'Canvas text card ID');
    _validateDot(target);
  }
}

final class NotesCanvasEdgeCreateOperation extends NotesCanvasOperation {
  const NotesCanvasEdgeCreateOperation({
    required super.boardId,
    required super.opId,
    required super.replicaId,
    required super.replicaCounter,
    required super.dependencies,
    required this.edge,
  });

  final NotesCanvasEdge edge;

  @override
  String get type => 'edge_create';

  @override
  Map<String, Object?> get payload => {'edge': edge.toJson()};

  @override
  void validatePayload() {
    edge.validate();
    if (edge.tombstoned) {
      throw const FormatException(
        'A created Canvas edge cannot be tombstoned.',
      );
    }
  }
}

final class NotesCanvasEdgeTombstoneOperation extends NotesCanvasOperation {
  const NotesCanvasEdgeTombstoneOperation({
    required super.boardId,
    required super.opId,
    required super.replicaId,
    required super.replicaCounter,
    required super.dependencies,
    required this.edgeId,
  });

  final String edgeId;

  @override
  String get type => 'edge_tombstone';

  @override
  Map<String, Object?> get payload => {'edge_id': edgeId};

  @override
  void validatePayload() => _requireUuid(edgeId, 'Canvas edge ID');
}

void _validateDot(CrdtDot dot) {
  if (dot.actorId.trim().isEmpty ||
      dot.actorId.length > 128 ||
      dot.counter < 1 ||
      dot.counter > NotesCanvasOperation._maxCounter) {
    throw const FormatException('Canvas text atom ID is invalid.');
  }
}

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

void _requireUuid(String value, String label) {
  if (!_isUuid(value)) throw FormatException('$label must be a UUID.');
}

bool _isBoundedDelta(double value) =>
    value.isFinite && value.abs() <= NotesCanvasCard.maxCoordinate * 2;

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Canvas field "$key" is invalid.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Canvas field "$key" is invalid.');
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
    throw const FormatException('Canvas dependencies must be an object.');
  }
  final values = <String, int>{};
  for (final entry in raw.entries) {
    if (entry.key is! String || entry.value is! int) {
      throw const FormatException('Canvas dependencies are malformed.');
    }
    values[entry.key as String] = entry.value as int;
  }
  return CrdtVersionVector(values);
}
