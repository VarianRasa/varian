import 'package:varian/features/collaboration/domain/crdt_primitives.dart';

class NoteCrdtInsertion {
  const NoteCrdtInsertion({
    required this.id,
    required this.after,
    required this.value,
  });

  final CrdtDot id;
  final CrdtDot? after;
  final String value;

  Map<String, Object?> toJson() => {
    'id': id.toJson(),
    'after': after?.toJson(),
    'value': value,
  };

  factory NoteCrdtInsertion.fromJson(Map<String, dynamic> json) =>
      NoteCrdtInsertion(
        id: CrdtDot.fromJson(Map<String, dynamic>.from(json['id'] as Map)),
        after: json['after'] is Map
            ? CrdtDot.fromJson(Map<String, dynamic>.from(json['after'] as Map))
            : null,
        value: json['value'] as String,
      );
}

class NoteCrdtOperation {
  const NoteCrdtOperation({
    required this.noteId,
    required this.replicaId,
    required this.dot,
    required this.dependencies,
    this.insertions = const [],
    this.deletions = const [],
  });

  final String noteId;
  final String replicaId;
  final CrdtDot dot;
  final CrdtVersionVector dependencies;
  final List<NoteCrdtInsertion> insertions;
  final List<CrdtDot> deletions;

  String get opId => '$noteId:${dot.actorId}:${dot.counter}';

  Map<String, Object?> toJson() => {
    'noteId': noteId,
    'opId': opId,
    'replicaId': replicaId,
    'dot': dot.toJson(),
    'dependencies': dependencies.toJson(),
    'insertions': insertions.map((item) => item.toJson()).toList(),
    'deletions': deletions.map((item) => item.toJson()).toList(),
  };

  factory NoteCrdtOperation.fromJson(
    Map<String, dynamic> json,
  ) => NoteCrdtOperation(
    noteId: json['noteId'] as String,
    replicaId: json['replicaId'] as String,
    dot: CrdtDot.fromJson(Map<String, dynamic>.from(json['dot'] as Map)),
    dependencies: CrdtVersionVector.fromJson(json['dependencies']),
    insertions: (json['insertions'] as List? ?? const [])
        .map(
          (item) => NoteCrdtInsertion.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
    deletions: (json['deletions'] as List? ?? const [])
        .map((item) => CrdtDot.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false),
  );
}
