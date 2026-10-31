// ignore: depend_on_referenced_packages
import 'package:characters/characters.dart';

import 'crdt_primitives.dart';

class CrdtTextAtom {
  final CrdtDot id;
  final CrdtDot? after;
  final String value;
  final bool deleted;
  final CrdtDot? deleteDot;
  final Map<String, CrdtRegisterValue> formats;

  const CrdtTextAtom({
    required this.id,
    required this.after,
    required this.value,
    this.deleted = false,
    this.deleteDot,
    this.formats = const {},
  });

  CrdtTextAtom copyWith({
    bool? deleted,
    CrdtDot? deleteDot,
    Map<String, CrdtRegisterValue>? formats,
  }) => CrdtTextAtom(
    id: id,
    after: after,
    value: value,
    deleted: deleted ?? this.deleted,
    deleteDot: deleteDot ?? this.deleteDot,
    formats: formats ?? this.formats,
  );

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'after': after?.toJson(),
    'value': value,
    'deleted': deleted,
    'deleteDot': deleteDot?.toJson(),
    'formats': formats.map((key, register) => MapEntry(key, register.toJson())),
  };

  factory CrdtTextAtom.fromJson(Map<String, dynamic> json) => CrdtTextAtom(
    id: CrdtDot.fromJson(Map<String, dynamic>.from(json['id'] as Map)),
    after: json['after'] is Map
        ? CrdtDot.fromJson(Map<String, dynamic>.from(json['after'] as Map))
        : null,
    value: json['value'] as String,
    deleted: json['deleted'] as bool? ?? false,
    deleteDot: json['deleteDot'] is Map
        ? CrdtDot.fromJson(Map<String, dynamic>.from(json['deleteDot'] as Map))
        : null,
    formats:
        (json['formats'] as Map?)?.map(
          (key, value) => MapEntry(
            key as String,
            CrdtRegisterValue.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        ) ??
        const {},
  );
}

class CrdtRegisterValue {
  final CrdtDot dot;
  final Object? value;

  const CrdtRegisterValue({required this.dot, required this.value});

  Map<String, dynamic> toJson() => {'dot': dot.toJson(), 'value': value};

  factory CrdtRegisterValue.fromJson(Map<String, dynamic> json) =>
      CrdtRegisterValue(
        dot: CrdtDot.fromJson(Map<String, dynamic>.from(json['dot'] as Map)),
        value: json['value'],
      );
}

/// RGA-like sequence for text and other ordered atoms.
///
/// The sequence is intentionally small and JSON agnostic. It keeps tombstones
/// until the server confirms that every active checkpoint has observed them.
class CrdtTextSequence {
  final Map<String, CrdtTextAtom> _atoms = {};

  CrdtTextSequence.seed(String value, {String actorId = 'snapshot'}) {
    CrdtDot? previous;
    var counter = 1;
    for (final character in value.characters) {
      final dot = CrdtDot(actorId: actorId, counter: counter++);
      _atoms[dot.key] = CrdtTextAtom(
        id: dot,
        after: previous,
        value: character,
      );
      previous = dot;
    }
  }

  CrdtTextSequence.empty();

  factory CrdtTextSequence.fromJson(Map<String, dynamic> json) {
    final sequence = CrdtTextSequence.empty();
    final rawAtoms = json['atoms'];
    if (rawAtoms is List) {
      for (final rawAtom in rawAtoms) {
        if (rawAtom is Map) {
          final atom = CrdtTextAtom.fromJson(
            Map<String, dynamic>.from(rawAtom),
          );
          sequence._atoms[atom.id.key] = atom;
        }
      }
    }
    return sequence;
  }

  Map<String, dynamic> toJson() => {
    'atoms': _atoms.values.map((atom) => atom.toJson()).toList(),
  };

  Iterable<CrdtTextAtom> get atoms => _orderedAtoms();

  String get visibleText => _orderedAtoms()
      .where((atom) => !atom.deleted)
      .map((atom) => atom.value)
      .join();

  void insert({
    required CrdtDot id,
    required CrdtDot? after,
    required String value,
  }) {
    if (value.isEmpty || _atoms.containsKey(id.key)) return;
    _atoms[id.key] = CrdtTextAtom(id: id, after: after, value: value);
  }

  void delete(CrdtDot target, CrdtDot deleteDot) {
    final atom = _atoms[target.key];
    if (atom == null) return;
    if (atom.deleted &&
        atom.deleteDot != null &&
        atom.deleteDot!.compareTimestampTo(deleteDot) >= 0) {
      return;
    }
    _atoms[target.key] = atom.copyWith(deleted: true, deleteDot: deleteDot);
  }

  void format({
    required CrdtDot target,
    required CrdtDot dot,
    required String key,
    required Object? value,
  }) {
    final atom = _atoms[target.key];
    if (atom == null) return;
    final current = atom.formats[key];
    if (current != null && current.dot.compareTimestampTo(dot) >= 0) return;
    _atoms[target.key] = atom.copyWith(
      formats: {
        ...atom.formats,
        key: CrdtRegisterValue(dot: dot, value: value),
      },
    );
  }

  List<String> visibleIds() => _orderedAtoms()
      .where((atom) => !atom.deleted)
      .map((atom) => atom.id.key)
      .toList(growable: false);

  CrdtDot? visibleIdBefore(int offset) {
    final visible = _orderedAtoms().where((atom) => !atom.deleted).toList();
    if (offset <= 0 || visible.isEmpty) return null;
    final index = (offset - 1).clamp(0, visible.length - 1);
    return visible[index].id;
  }

  CrdtDot? visibleIdAt(int offset) {
    final visible = _orderedAtoms().where((atom) => !atom.deleted).toList();
    if (offset < 0 || offset >= visible.length) return null;
    return visible[offset].id;
  }

  List<CrdtTextAtom> atomsForRange(int start, int end) {
    final visible = _orderedAtoms().where((atom) => !atom.deleted).toList();
    final safeStart = start.clamp(0, visible.length);
    final safeEnd = end.clamp(safeStart, visible.length);
    return visible.sublist(safeStart, safeEnd);
  }

  List<CrdtTextAtom> _orderedAtoms() {
    final children = <String?, List<CrdtTextAtom>>{};
    for (final atom in _atoms.values) {
      children.putIfAbsent(atom.after?.key, () => []).add(atom);
    }
    for (final values in children.values) {
      values.sort((a, b) => a.id.compareTo(b.id));
    }

    final ordered = <CrdtTextAtom>[];
    final pending = <CrdtTextAtom>[];
    for (final root in (children[null] ?? const <CrdtTextAtom>[]).reversed) {
      pending.add(root);
    }
    while (pending.isNotEmpty) {
      final atom = pending.removeLast();
      ordered.add(atom);
      for (final child
          in (children[atom.id.key] ?? const <CrdtTextAtom>[]).reversed) {
        pending.add(child);
      }
    }
    return ordered;
  }
}
