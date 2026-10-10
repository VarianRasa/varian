enum SemanticRecordKind { node, asset, comment, version, provenance }

class SemanticIndexRecord {
  final String id;
  final SemanticRecordKind kind;
  final String title;
  final String content;
  final List<String> tags;
  final List<String> references;
  final DateTime updatedAt;
  final Map<String, dynamic> metadata;

  const SemanticIndexRecord({
    required this.id,
    required this.kind,
    this.title = '',
    this.content = '',
    this.tags = const [],
    this.references = const [],
    required this.updatedAt,
    this.metadata = const {},
  });

  String get searchText => [
    id,
    title,
    content,
    ...tags,
    ...references,
    ..._flattenMetadata(metadata),
  ].join(' ');

  SemanticIndexRecord copyWith({
    String? id,
    SemanticRecordKind? kind,
    String? title,
    String? content,
    List<String>? tags,
    List<String>? references,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) => SemanticIndexRecord(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    content: content ?? this.content,
    tags: tags ?? this.tags,
    references: references ?? this.references,
    updatedAt: updatedAt ?? this.updatedAt,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'content': content,
    'tags': tags,
    'references': references,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'metadata': metadata,
  };

  factory SemanticIndexRecord.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind']?.toString();
    final kind = SemanticRecordKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => SemanticRecordKind.node,
    );
    return SemanticIndexRecord(
      id: json['id']?.toString() ?? '',
      kind: kind,
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      tags: _stringList(json['tags']),
      references: _stringList(json['references']),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return List.unmodifiable(
      value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty),
    );
  }

  static Iterable<String> _flattenMetadata(Object? value) sync* {
    if (value is Map) {
      for (final entry in value.entries) {
        yield entry.key.toString();
        yield* _flattenMetadata(entry.value);
      }
    } else if (value is Iterable) {
      for (final item in value) {
        yield* _flattenMetadata(item);
      }
    } else if (value != null) {
      yield value.toString();
    }
  }
}

class SemanticSearchHit {
  final SemanticIndexRecord record;
  final double score;
  final List<String> matchedTokens;

  const SemanticSearchHit({
    required this.record,
    required this.score,
    required this.matchedTokens,
  });
}

class SemanticIndex {
  static const int schemaVersion = 1;

  final String projectId;
  final DateTime updatedAt;
  final List<SemanticIndexRecord> records;

  const SemanticIndex({
    required this.projectId,
    required this.updatedAt,
    this.records = const [],
  });

  factory SemanticIndex.empty(String projectId) =>
      SemanticIndex(projectId: projectId, updatedAt: DateTime.now().toUtc());

  SemanticIndex upsert(SemanticIndexRecord record) {
    if (record.id.trim().isEmpty) return this;
    final next = [
      for (final current in records)
        if (current.id != record.id || current.kind != record.kind) current,
      record,
    ];
    return copyWith(
      records: _sortRecords(next),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  SemanticIndex upsertAll(Iterable<SemanticIndexRecord> values) {
    var result = this;
    for (final value in values) {
      result = result.upsert(value);
    }
    return result;
  }

  SemanticIndex remove({required String id, SemanticRecordKind? kind}) {
    final next = records
        .where(
          (record) => record.id != id || (kind != null && record.kind != kind),
        )
        .toList(growable: false);
    if (next.length == records.length) return this;
    return copyWith(records: next, updatedAt: DateTime.now().toUtc());
  }

  SemanticIndex replaceAll(Iterable<SemanticIndexRecord> values) {
    final unique = <String, SemanticIndexRecord>{};
    for (final value in values) {
      if (value.id.trim().isEmpty) continue;
      unique['${value.kind.name}:${value.id}'] = value;
    }
    return copyWith(
      records: _sortRecords(unique.values),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  List<SemanticSearchHit> search(
    String query, {
    SemanticRecordKind? kind,
    int limit = 20,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final queryTokens = _tokenize(normalizedQuery);
    if (queryTokens.isEmpty) return const [];

    final hits = <SemanticSearchHit>[];
    for (final record in records) {
      if (kind != null && record.kind != kind) continue;
      final title = record.title.toLowerCase();
      final content = record.content.toLowerCase();
      final tags = record.tags.map((tag) => tag.toLowerCase()).toSet();
      final idTokens = _tokenize(record.id);
      final allText = record.searchText.toLowerCase();
      final matched = <String>[];
      var score = 0.0;
      for (final token in queryTokens) {
        final inTitle = _tokenize(title).contains(token);
        final inContent = _tokenize(content).contains(token);
        final inTags = tags.any((tag) => _tokenize(tag).contains(token));
        final inId = idTokens.contains(token);
        final inAnyText = allText.contains(token);
        if (!inAnyText) continue;
        matched.add(token);
        if (inTitle) score += 12;
        if (inTags) score += 8;
        if (inContent) score += 4;
        if (inId) score += 3;
        if (!inTitle && !inTags && !inContent && !inId) score += 1;
      }
      if (matched.isEmpty) continue;
      if (title.contains(normalizedQuery)) score += 20;
      if (record.id.toLowerCase() == normalizedQuery) score += 30;
      score += matched.length / queryTokens.length;
      hits.add(
        SemanticSearchHit(
          record: record,
          score: score,
          matchedTokens: List.unmodifiable(matched),
        ),
      );
    }
    hits.sort((left, right) {
      final score = right.score.compareTo(left.score);
      if (score != 0) return score;
      final updated = right.record.updatedAt.compareTo(left.record.updatedAt);
      if (updated != 0) return updated;
      return left.record.id.compareTo(right.record.id);
    });
    return List.unmodifiable(hits.take(limit.clamp(0, hits.length)));
  }

  SemanticIndex copyWith({
    String? projectId,
    DateTime? updatedAt,
    List<SemanticIndexRecord>? records,
  }) => SemanticIndex(
    projectId: projectId ?? this.projectId,
    updatedAt: updatedAt ?? this.updatedAt,
    records: records ?? this.records,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'projectId': projectId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'records': records.map((record) => record.toJson()).toList(),
  };

  factory SemanticIndex.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['records'];
    final records = <SemanticIndexRecord>[];
    if (rawRecords is List) {
      for (final item in rawRecords) {
        if (item is Map) {
          records.add(
            SemanticIndexRecord.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final updatedAt =
        DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final unique = <String, SemanticIndexRecord>{};
    for (final record in records) {
      unique['${record.kind.name}:${record.id}'] = record;
    }
    return SemanticIndex(
      projectId: json['projectId']?.toString() ?? '',
      updatedAt: updatedAt,
      records: _sortRecords(unique.values),
    );
  }

  static List<SemanticIndexRecord> _sortRecords(
    Iterable<SemanticIndexRecord> values,
  ) {
    final result = List<SemanticIndexRecord>.from(values);
    result.sort((left, right) {
      final updated = right.updatedAt.compareTo(left.updatedAt);
      if (updated != 0) return updated;
      final kind = left.kind.name.compareTo(right.kind.name);
      if (kind != 0) return kind;
      return left.id.compareTo(right.id);
    });
    return List.unmodifiable(result);
  }

  static List<String> _tokenize(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}
