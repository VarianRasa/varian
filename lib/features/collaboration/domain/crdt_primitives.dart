import 'dart:convert';

/// A Lamport dot identifies one operation produced by one collaboration actor.
class CrdtDot implements Comparable<CrdtDot> {
  final String actorId;
  final int counter;

  const CrdtDot({required this.actorId, required this.counter})
    : assert(counter > 0);

  String get key => '$actorId:$counter';

  @override
  int compareTo(CrdtDot other) {
    final actorOrder = actorId.compareTo(other.actorId);
    if (actorOrder != 0) return actorOrder;
    return counter.compareTo(other.counter);
  }

  int compareTimestampTo(CrdtDot other) {
    final counterOrder = counter.compareTo(other.counter);
    if (counterOrder != 0) return counterOrder;
    return actorId.compareTo(other.actorId);
  }

  Map<String, dynamic> toJson() => {'actorId': actorId, 'counter': counter};

  factory CrdtDot.fromJson(Map<String, dynamic> json) => CrdtDot(
    actorId: json['actorId'] as String,
    counter: (json['counter'] as num).toInt(),
  );

  @override
  bool operator ==(Object other) =>
      other is CrdtDot && actorId == other.actorId && counter == other.counter;

  @override
  int get hashCode => Object.hash(actorId, counter);

  @override
  String toString() => key;
}

class CrdtVersionVector {
  final Map<String, int> values;

  CrdtVersionVector([Map<String, int> values = const {}])
    : values = Map.unmodifiable({...values});

  int operator [](String actorId) => values[actorId] ?? 0;

  int get nextCounter =>
      values.values.fold(
        0,
        (maximum, counter) => counter > maximum ? counter : maximum,
      ) +
      1;

  bool satisfies(CrdtVersionVector required) =>
      required.values.entries.every((entry) => this[entry.key] >= entry.value);

  CrdtVersionVector advance(CrdtDot dot) {
    final next = {...values};
    final current = next[dot.actorId] ?? 0;
    if (dot.counter > current) next[dot.actorId] = dot.counter;
    return CrdtVersionVector(next);
  }

  CrdtVersionVector merge(CrdtVersionVector other) {
    final next = {...values};
    for (final entry in other.values.entries) {
      if ((next[entry.key] ?? 0) < entry.value) {
        next[entry.key] = entry.value;
      }
    }
    return CrdtVersionVector(next);
  }

  Map<String, dynamic> toJson() =>
      values.map((key, value) => MapEntry(key, value));

  factory CrdtVersionVector.fromJson(Object? raw) {
    if (raw is! Map) return CrdtVersionVector();
    final parsed = <String, int>{};
    for (final entry in raw.entries) {
      if (entry.key is String && entry.value is num) {
        parsed[entry.key as String] = (entry.value as num).toInt();
      }
    }
    return CrdtVersionVector(parsed);
  }

  @override
  bool operator ==(Object other) =>
      other is CrdtVersionVector && _jsonEquals(values, other.values);

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  static bool _jsonEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

enum CrdtOperationKind {
  nodeUpsert,
  nodeDelete,
  edgeUpsert,
  edgeDelete,
  nodeFieldSet,
  textInsert,
  textDelete,
  textFormat,
  strokeUpsert,
  strokeDelete,
  rasterOperation,
  rasterReset,
  assetUpsert,
  assetDelete,
  tokenUpsert,
  tokenDelete,
  commentUpsert,
  commentDelete,
  commentReplyInsert,
  commentReplyUpsert,
  commentReplyDelete,
  commentReactionSet,
  commentResolveSet,
}

enum CrdtApplyStatus { applied, duplicate, buffered, rejected }

/// JSON-safe operation envelope shared by local queues, Realtime, and storage.
class CrdtOperation {
  static const maxEncodedBytes = 256 * 1024;

  final String projectId;
  final String opId;
  final CrdtDot dot;
  final CrdtVersionVector dependencies;
  final CrdtOperationKind kind;
  final String targetId;
  final String? field;
  final Map<String, dynamic> value;

  const CrdtOperation({
    required this.projectId,
    required this.opId,
    required this.dot,
    required this.dependencies,
    required this.kind,
    required this.targetId,
    this.field,
    this.value = const {},
  });

  factory CrdtOperation.create({
    required String projectId,
    required CrdtDot dot,
    required CrdtVersionVector dependencies,
    required CrdtOperationKind kind,
    required String targetId,
    String? field,
    Map<String, dynamic> value = const {},
  }) => CrdtOperation(
    projectId: projectId,
    opId: dot.key,
    dot: dot,
    dependencies: dependencies,
    kind: kind,
    targetId: targetId,
    field: field,
    value: value,
  );

  Map<String, dynamic> toJson() => {
    'v': 1,
    'projectId': projectId,
    'opId': opId,
    'dot': dot.toJson(),
    'dependencies': dependencies.toJson(),
    'kind': kind.name,
    'targetId': targetId,
    'field': field,
    'value': value,
  };

  Map<String, dynamic> toPersistenceJson() => {
    'v': 1,
    'projectId': projectId,
    'opId': opId,
    'dot': dot.toJson(),
    'dependencies': dependencies.toJson(),
    'kind': kind.name,
    'targetId': targetId,
    'field': field,
    'value': _persistenceValue(value),
  };

  static dynamic _persistenceValue(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.key is String)
            entry.key as String: _persistenceValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_persistenceValue).toList(growable: false);
    }
    return value;
  }

  CrdtOperation withDependencies(CrdtVersionVector nextDependencies) =>
      CrdtOperation(
        projectId: projectId,
        opId: opId,
        dot: dot,
        dependencies: nextDependencies,
        kind: kind,
        targetId: targetId,
        field: field,
        value: value,
      );

  String encode() => jsonEncode(toJson());

  factory CrdtOperation.fromJson(Map<String, dynamic> json) {
    final rawValue = json['value'];
    final value = rawValue is Map
        ? Map<String, dynamic>.from(rawValue)
        : const <String, dynamic>{};
    final dot = CrdtDot.fromJson(Map<String, dynamic>.from(json['dot'] as Map));
    final operation = CrdtOperation(
      projectId: json['projectId'] as String,
      opId: json['opId'] as String? ?? dot.key,
      dot: dot,
      dependencies: CrdtVersionVector.fromJson(json['dependencies']),
      kind: CrdtOperationKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => throw const FormatException('Unknown CRDT operation'),
      ),
      targetId: json['targetId'] as String,
      field: json['field'] as String?,
      value: value,
    );
    if (operation.opId != operation.dot.key) {
      throw const FormatException('CRDT operation ID does not match its dot');
    }
    if (operation.encode().length > maxEncodedBytes) {
      throw const FormatException('CRDT operation is too large');
    }
    return operation;
  }
}
