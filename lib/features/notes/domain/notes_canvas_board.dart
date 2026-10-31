import 'package:flutter/foundation.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';

@immutable
class NotesCanvasBoard {
  const NotesCanvasBoard({
    required this.id,
    required this.ownerUserId,
    required this.createdBy,
    required this.title,
    required this.state,
    required this.crdtSnapshot,
    required this.versionVector,
    required this.revision,
    required this.snapshotServerSequence,
    required this.createdAt,
    required this.updatedAt,
    this.projectId,
  });

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  final String id;
  final String ownerUserId;
  final String createdBy;
  final String? projectId;
  final String title;
  final NotesCanvasBoardState state;
  final Map<String, dynamic> crdtSnapshot;
  final CrdtVersionVector versionVector;
  final int revision;
  final int snapshotServerSequence;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPrivate => projectId == null;

  factory NotesCanvasBoard.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    if (!_uuidPattern.hasMatch(id)) {
      throw const FormatException('Notes Canvas board ID must be a UUID.');
    }
    final ownerUserId = _requiredString(json, 'owner_user_id');
    final createdBy = _requiredString(json, 'created_by');
    final title = _requiredString(json, 'title');
    final projectId = json['project_id'];
    if (projectId != null && projectId is! String) {
      throw const FormatException('Notes Canvas project scope is malformed.');
    }
    final revision = _requiredInteger(json, 'revision');
    final snapshotSequence = _requiredInteger(json, 'snapshot_server_sequence');
    if (revision < 1 || snapshotSequence < 0 || title.trim().isEmpty) {
      throw const FormatException('Notes Canvas board metadata is invalid.');
    }
    final state = NotesCanvasBoardState.fromJson(
      _asStringMap(json['state_json']),
    );
    final snapshot = _asStringMap(json['crdt_snapshot_json']);
    final vector = _readVersionVector(json['version_vector']);
    final document = NotesCanvasDocument.fromSnapshot(snapshot);
    if (document.boardId != id ||
        document.boardState != state ||
        document.versionVector != vector) {
      throw const FormatException(
        'Notes Canvas board snapshot is inconsistent.',
      );
    }
    return NotesCanvasBoard(
      id: id,
      ownerUserId: ownerUserId,
      createdBy: createdBy,
      projectId: projectId as String?,
      title: title,
      state: state,
      crdtSnapshot: Map.unmodifiable(snapshot),
      versionVector: vector,
      revision: revision,
      snapshotServerSequence: snapshotSequence,
      createdAt: DateTime.parse(_requiredString(json, 'created_at')).toUtc(),
      updatedAt: DateTime.parse(_requiredString(json, 'updated_at')).toUtc(),
    );
  }
}

@immutable
class NotesCanvasOperationRecord {
  const NotesCanvasOperationRecord({
    required this.serverSequence,
    required this.operation,
  });

  final int serverSequence;
  final NotesCanvasOperation operation;

  factory NotesCanvasOperationRecord.fromJson(Map<String, dynamic> json) {
    final sequence = _requiredInteger(json, 'server_sequence');
    if (sequence < 1) {
      throw const FormatException('Canvas server sequence is invalid.');
    }
    return NotesCanvasOperationRecord(
      serverSequence: sequence,
      operation: NotesCanvasOperation.fromJson(
        _asStringMap(json['operation_json']),
      ),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String)
    throw FormatException('Canvas field "$key" is invalid.');
  return value;
}

int _requiredInteger(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Canvas field "$key" is invalid.');
  return value;
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected a JSON object.');
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw const FormatException('Canvas field is not a string-keyed object.');
  }
}

CrdtVersionVector _readVersionVector(Object? raw) {
  final map = _asStringMap(raw);
  final values = <String, int>{};
  for (final entry in map.entries) {
    if (entry.key.isEmpty || entry.key.length > 128 || entry.value is! int) {
      throw const FormatException('Canvas version vector is malformed.');
    }
    final counter = entry.value as int;
    if (counter < 0) {
      throw const FormatException('Canvas version vector is malformed.');
    }
    values[entry.key] = counter;
  }
  return CrdtVersionVector(values);
}
