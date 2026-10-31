import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
sealed class NotesCanvasCard {
  const NotesCanvasCard({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.tombstoned = false,
  });

  static const maxCoordinate = 1000000.0;
  static const maxDimension = 10000.0;
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool tombstoned;

  String get type;
  Map<String, Object?> toJson();

  void validateGeometry() {
    if (!_uuidPattern.hasMatch(id)) {
      throw const FormatException('Canvas card ID must be a UUID.');
    }
    if (!_isBounded(x) || !_isBounded(y)) {
      throw const FormatException('Canvas card position is out of bounds.');
    }
    if (!_isDimension(width) || !_isDimension(height)) {
      throw const FormatException('Canvas card size is out of bounds.');
    }
  }

  static bool _isBounded(double value) =>
      value.isFinite && value.abs() <= maxCoordinate;

  static bool _isDimension(double value) =>
      value.isFinite && value > 0 && value <= maxDimension;

  static NotesCanvasCard fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final x = _requiredNumber(json, 'x');
    final y = _requiredNumber(json, 'y');
    final width = _requiredNumber(json, 'width');
    final height = _requiredNumber(json, 'height');
    final tombstoned = json['tombstoned'] ?? false;
    if (tombstoned is! bool) {
      throw const FormatException('Canvas card tombstone must be boolean.');
    }
    return switch (json['type']) {
      'note' => NotesCanvasNoteCard(
        id: id,
        noteId: _requiredString(json, 'note_id'),
        x: x,
        y: y,
        width: width,
        height: height,
        tombstoned: tombstoned,
      ),
      'text' => NotesCanvasTextCard(
        id: id,
        markdown: _requiredString(json, 'markdown'),
        x: x,
        y: y,
        width: width,
        height: height,
        tombstoned: tombstoned,
      ),
      _ => throw const FormatException('Unknown Notes Canvas card type.'),
    };
  }
}

@immutable
final class NotesCanvasNoteCard extends NotesCanvasCard {
  const NotesCanvasNoteCard({
    required super.id,
    required this.noteId,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    super.tombstoned,
  });

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  final String noteId;

  @override
  String get type => 'note';

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'note_id': noteId,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'tombstoned': tombstoned,
  };

  void validate() {
    validateGeometry();
    if (!_uuidPattern.hasMatch(noteId)) {
      throw const FormatException('Canvas note reference must be a UUID.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NotesCanvasNoteCard &&
      id == other.id &&
      noteId == other.noteId &&
      x == other.x &&
      y == other.y &&
      width == other.width &&
      height == other.height &&
      tombstoned == other.tombstoned;

  @override
  int get hashCode => Object.hash(id, noteId, x, y, width, height, tombstoned);
}

@immutable
final class NotesCanvasTextCard extends NotesCanvasCard {
  const NotesCanvasTextCard({
    required super.id,
    required this.markdown,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    super.tombstoned,
  });

  static const maxMarkdownBytes = 100 * 1024;

  final String markdown;

  @override
  String get type => 'text';

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'markdown': markdown,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'tombstoned': tombstoned,
  };

  void validate() {
    validateGeometry();
    if (utf8.encode(markdown).length > maxMarkdownBytes) {
      throw const FormatException('Canvas text card exceeds 100 KiB.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NotesCanvasTextCard &&
      id == other.id &&
      markdown == other.markdown &&
      x == other.x &&
      y == other.y &&
      width == other.width &&
      height == other.height &&
      tombstoned == other.tombstoned;

  @override
  int get hashCode =>
      Object.hash(id, markdown, x, y, width, height, tombstoned);
}

@immutable
final class NotesCanvasEdge {
  const NotesCanvasEdge({
    required this.id,
    required this.fromCardId,
    required this.toCardId,
    this.tombstoned = false,
  });

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  final String id;
  final String fromCardId;
  final String toCardId;
  final bool tombstoned;

  Map<String, Object?> toJson() => {
    'id': id,
    'from_card_id': fromCardId,
    'to_card_id': toCardId,
    'tombstoned': tombstoned,
  };

  void validate() {
    if (!_uuidPattern.hasMatch(id) ||
        !_uuidPattern.hasMatch(fromCardId) ||
        !_uuidPattern.hasMatch(toCardId)) {
      throw const FormatException('Canvas edge IDs must be UUIDs.');
    }
  }

  factory NotesCanvasEdge.fromJson(Map<String, dynamic> json) {
    final tombstoned = json['tombstoned'] ?? false;
    if (tombstoned is! bool) {
      throw const FormatException('Canvas edge tombstone must be boolean.');
    }
    return NotesCanvasEdge(
      id: _requiredString(json, 'id'),
      fromCardId: _requiredString(json, 'from_card_id'),
      toCardId: _requiredString(json, 'to_card_id'),
      tombstoned: tombstoned,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotesCanvasEdge &&
      id == other.id &&
      fromCardId == other.fromCardId &&
      toCardId == other.toCardId &&
      tombstoned == other.tombstoned;

  @override
  int get hashCode => Object.hash(id, fromCardId, toCardId, tombstoned);
}

@immutable
final class NotesCanvasBoardState {
  NotesCanvasBoardState({
    required Iterable<NotesCanvasCard> cards,
    Iterable<NotesCanvasEdge> edges = const [],
  }) : cards = List.unmodifiable(cards),
       edges = List.unmodifiable(edges) {
    validate();
  }

  static const supportedSchemaVersion = 1;
  static const maxCards = 500;
  static const maxEdges = 2000;
  static const maxTextCardBytes = NotesCanvasTextCard.maxMarkdownBytes;
  static const maxSerializedBytes = 5 * 1024 * 1024;

  final List<NotesCanvasCard> cards;
  final List<NotesCanvasEdge> edges;
  int get schemaVersion => NotesCanvasBoardState.supportedSchemaVersion;

  factory NotesCanvasBoardState.empty() =>
      NotesCanvasBoardState(cards: const []);

  factory NotesCanvasBoardState.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != supportedSchemaVersion ||
        json['cards'] is! List ||
        json['edges'] is! List) {
      throw const FormatException(
        'Unsupported or malformed Notes Canvas state.',
      );
    }
    try {
      return NotesCanvasBoardState(
        cards: (json['cards'] as List)
            .map((item) => NotesCanvasCard.fromJson(_asStringMap(item)))
            .toList(growable: false),
        edges: (json['edges'] as List)
            .map((item) => NotesCanvasEdge.fromJson(_asStringMap(item)))
            .toList(growable: false),
      );
    } on TypeError catch (error) {
      throw FormatException('Malformed Notes Canvas state: $error');
    }
  }

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'cards': cards.map((card) => card.toJson()).toList(growable: false),
    'edges': edges.map((edge) => edge.toJson()).toList(growable: false),
  };

  void validate() {
    if (cards.length > maxCards || edges.length > maxEdges) {
      throw const FormatException('Notes Canvas state exceeds entity limits.');
    }
    final cardIds = <String>{};
    for (final card in cards) {
      switch (card) {
        case NotesCanvasNoteCard():
          card.validate();
        case NotesCanvasTextCard():
          card.validate();
      }
      if (!cardIds.add(card.id)) {
        throw const FormatException('Notes Canvas card IDs must be unique.');
      }
    }
    final edgeIds = <String>{};
    for (final edge in edges) {
      edge.validate();
      if (!edgeIds.add(edge.id)) {
        throw const FormatException('Notes Canvas edge IDs must be unique.');
      }
      if (!cardIds.contains(edge.fromCardId) ||
          !cardIds.contains(edge.toCardId)) {
        throw const FormatException('Notes Canvas edge endpoint is missing.');
      }
    }
    if (utf8.encode(jsonEncode(toJson())).length > maxSerializedBytes) {
      throw const FormatException('Notes Canvas state exceeds 5 MiB.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NotesCanvasBoardState &&
      listEquals(cards, other.cards) &&
      listEquals(edges, other.edges);

  @override
  int get hashCode => Object.hash(Object.hashAll(cards), Object.hashAll(edges));
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected a JSON object.');
  return Map<String, dynamic>.from(value);
}

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
