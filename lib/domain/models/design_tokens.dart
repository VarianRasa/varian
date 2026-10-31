enum DesignTokenType { color, number, string, boolean }

class DesignToken {
  final String id;
  final String name;
  final DesignTokenType type;
  final Object value;
  final Map<String, Object> modeValues;
  final String? description;
  final DateTime updatedAt;

  const DesignToken({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    this.modeValues = const {},
    this.description,
    required this.updatedAt,
  });

  Object resolve([String? mode]) =>
      mode == null ? value : (modeValues[mode] ?? value);

  DesignToken copyWith({
    String? id,
    String? name,
    DesignTokenType? type,
    Object? value,
    Map<String, Object>? modeValues,
    Object? description = _sentinel,
    DateTime? updatedAt,
  }) => DesignToken(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    value: value ?? this.value,
    modeValues: modeValues ?? this.modeValues,
    description: description == _sentinel
        ? this.description
        : description as String?,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'value': value,
    if (modeValues.isNotEmpty) 'modeValues': modeValues,
    if (description != null) 'description': description,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory DesignToken.fromJson(Map<String, dynamic> json) {
    final id = _required(json['id'], 'id');
    final name = _required(json['name'], 'name');
    final rawValue = json['value'];
    if (rawValue is! String && rawValue is! num && rawValue is! bool) {
      throw FormatException('Design token $id has an invalid value.');
    }
    final type = DesignTokenType.values.firstWhere(
      (entry) => entry.name == json['type'],
      orElse: () => DesignTokenType.string,
    );
    final rawModes = json['modeValues'];
    final modes = <String, Object>{};
    if (rawModes is Map) {
      for (final entry in rawModes.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String ||
            (value is! String && value is! num && value is! bool)) {
          continue;
        }
        modes[key] = value as Object;
      }
    }
    return DesignToken(
      id: id,
      name: name,
      type: type,
      value: rawValue as Object,
      modeValues: modes,
      description: json['description'] as String?,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static String _required(Object? value, String field) {
    final text = value is String ? value.trim() : '';
    if (text.isEmpty) throw FormatException('Design token $field is required.');
    return text;
  }

  static const Object _sentinel = Object();
}

class DesignTokenSet {
  final int version;
  final List<String> modes;
  final Map<String, DesignToken> entries;

  const DesignTokenSet({
    this.version = 1,
    this.modes = const ['base'],
    this.entries = const {},
  });

  DesignToken? operator [](String id) => entries[id];

  DesignTokenSet upsert(DesignToken token) => DesignTokenSet(
    version: version,
    modes: modes,
    entries: {...entries, token.id: token},
  );

  DesignTokenSet remove(String id) {
    if (!entries.containsKey(id)) return this;
    final next = Map<String, DesignToken>.from(entries)..remove(id);
    return DesignTokenSet(version: version, modes: modes, entries: next);
  }

  Object? resolve(String id, [String? mode]) => entries[id]?.resolve(mode);

  Map<String, dynamic> toJson() => {
    'version': version,
    'modes': modes,
    'items': entries.values.map((token) => token.toJson()).toList(),
  };

  factory DesignTokenSet.fromJson(Object? raw) {
    if (raw == null) return const DesignTokenSet();
    if (raw is! Map) {
      throw const FormatException('Design tokens must be an object.');
    }
    final rawModes = raw['modes'];
    final modes = rawModes is List
        ? rawModes.whereType<String>().where((mode) => mode.isNotEmpty).toList()
        : <String>['base'];
    if (modes.isEmpty) modes.add('base');
    final entries = <String, DesignToken>{};
    final rawItems = raw['items'];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is! Map) continue;
        final token = DesignToken.fromJson(Map<String, dynamic>.from(item));
        entries[token.id] = token;
      }
    }
    return DesignTokenSet(
      version: (raw['version'] as num?)?.toInt() ?? 1,
      modes: List<String>.unmodifiable(modes),
      entries: entries,
    );
  }
}
