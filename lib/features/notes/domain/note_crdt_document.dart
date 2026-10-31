// ignore: depend_on_referenced_packages
import 'package:characters/characters.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/collaboration/domain/crdt_text_sequence.dart';
import 'package:varian/features/notes/domain/note_crdt_operation.dart';

class NoteCrdtDocument {
  NoteCrdtDocument._(this.noteId, this._sequence, this._versionVector);

  final String noteId;
  final CrdtTextSequence _sequence;
  CrdtVersionVector _versionVector;
  final Set<String> _appliedOperationIds = {};
  final List<NoteCrdtOperation> _pending = [];

  factory NoteCrdtDocument.fromMarkdown(String noteId, String markdown) =>
      NoteCrdtDocument._(
        noteId,
        CrdtTextSequence.seed(markdown, actorId: 'zzzz_snapshot'),
        CrdtVersionVector({'zzzz_snapshot': markdown.characters.length}),
      );

  factory NoteCrdtDocument.fromSnapshot(Map<String, dynamic> snapshot) {
    final document = NoteCrdtDocument._(
      snapshot['noteId'] as String,
      CrdtTextSequence.fromJson(
        Map<String, dynamic>.from(snapshot['sequence'] as Map),
      ),
      CrdtVersionVector.fromJson(snapshot['versionVector']),
    );
    final ids = snapshot['appliedOperationIds'];
    if (ids is List) {
      document._appliedOperationIds.addAll(ids.whereType<String>());
    }
    final pending = snapshot['pendingOperations'];
    if (pending is List) {
      document._pending.addAll(
        pending.whereType<Map>().map(
          (item) => NoteCrdtOperation.fromJson(Map<String, dynamic>.from(item)),
        ),
      );
    }
    return document;
  }

  String get visibleMarkdown => _sequence.visibleText;
  CrdtVersionVector get versionVector => _versionVector;

  Map<String, dynamic> snapshotState() => {
    'noteId': noteId,
    'sequence': _sequence.toJson(),
    'versionVector': _versionVector.toJson(),
    'appliedOperationIds': _appliedOperationIds.toList()..sort(),
    'pendingOperations': _pending
        .map((operation) => operation.toJson())
        .toList(),
  };

  NoteCrdtOperation? applyLocalEdit({
    required String replicaId,
    required String markdown,
  }) {
    final before = visibleMarkdown.characters.toList(growable: false);
    final after = markdown.characters.toList(growable: false);
    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before[prefix] == after[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before[before.length - 1 - suffix] ==
            after[after.length - 1 - suffix]) {
      suffix++;
    }
    if (prefix == before.length && prefix == after.length) return null;

    final dependencies = _versionVector;
    final deletedAtoms = _sequence.atomsForRange(
      prefix,
      before.length - suffix,
    );
    final deletions = deletedAtoms
        .map((atom) => atom.id)
        .toList(growable: false);
    final inserted = after.sublist(prefix, after.length - suffix);
    var counter = _versionVector[replicaId];
    CrdtDot? anchor = _sequence.visibleIdBefore(prefix);
    final insertions = <NoteCrdtInsertion>[];
    for (final character in inserted) {
      counter++;
      final id = CrdtDot(actorId: replicaId, counter: counter);
      insertions.add(
        NoteCrdtInsertion(id: id, after: anchor, value: character),
      );
      anchor = id;
    }
    counter++;
    final operation = NoteCrdtOperation(
      noteId: noteId,
      replicaId: replicaId,
      dot: CrdtDot(actorId: replicaId, counter: counter),
      dependencies: dependencies,
      insertions: insertions,
      deletions: deletions,
    );
    _apply(operation);
    _drainPending();
    return operation;
  }

  CrdtApplyStatus applyRemoteOperation(NoteCrdtOperation operation) {
    if (operation.noteId != noteId ||
        operation.dot.actorId != operation.replicaId) {
      return CrdtApplyStatus.rejected;
    }
    if (_appliedOperationIds.contains(operation.opId)) {
      return CrdtApplyStatus.duplicate;
    }
    if (!_versionVector.satisfies(operation.dependencies)) {
      if (!_pending.any((pending) => pending.opId == operation.opId)) {
        _pending.add(operation);
      }
      return CrdtApplyStatus.buffered;
    }
    if (operation.dot.counter <= _versionVector[operation.replicaId]) {
      return CrdtApplyStatus.duplicate;
    }
    if (!_isWellFormed(operation)) return CrdtApplyStatus.rejected;
    _apply(operation);
    _drainPending();
    return CrdtApplyStatus.applied;
  }

  bool _isWellFormed(NoteCrdtOperation operation) {
    final knownAtoms = _sequence.atoms.map((atom) => atom.id.key).toSet();
    var expectedCounter = _versionVector[operation.replicaId] + 1;
    for (final insertion in operation.insertions) {
      if (insertion.id.actorId != operation.replicaId ||
          insertion.id.counter != expectedCounter ||
          insertion.value.characters.length != 1 ||
          (insertion.after != null &&
              !knownAtoms.contains(insertion.after!.key))) {
        return false;
      }
      knownAtoms.add(insertion.id.key);
      expectedCounter++;
    }
    if (operation.dot.counter != expectedCounter ||
        operation.dot.counter !=
            _versionVector[operation.replicaId] +
                operation.insertions.length +
                1) {
      return false;
    }
    return operation.deletions.every(knownAtoms.contains);
  }

  void _apply(NoteCrdtOperation operation) {
    for (final insertion in operation.insertions) {
      _sequence.insert(
        id: insertion.id,
        after: insertion.after,
        value: insertion.value,
      );
    }
    for (final deletion in operation.deletions) {
      _sequence.delete(deletion, operation.dot);
    }
    _versionVector = _versionVector.advance(operation.dot);
    _appliedOperationIds.add(operation.opId);
  }

  void _drainPending() {
    var progressed = true;
    while (progressed) {
      progressed = false;
      for (final operation in List<NoteCrdtOperation>.of(_pending)) {
        if (_versionVector.satisfies(operation.dependencies)) {
          _pending.remove(operation);
          if (operation.dot.counter > _versionVector[operation.replicaId]) {
            _apply(operation);
          }
          progressed = true;
        }
      }
    }
  }
}
