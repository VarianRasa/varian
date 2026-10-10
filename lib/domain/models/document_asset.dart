import 'durable_asset_reference.dart';

enum DocumentAssetKind {
  image,
  audio,
  video,
  model3d,
  document,
  drawing,
  font,
  other,
}

enum DocumentAssetStorage { local, remote, bundled, embedded, unknown }

class DocumentAsset {
  final String id;
  final DocumentAssetKind kind;
  final DocumentAssetStorage storage;
  final String name;
  final String mimeType;
  final int? sizeBytes;
  final String? checksum;
  final String? localPath;
  final String? remoteUrl;
  final String? durableReference;
  final String? license;
  final String? folderId;
  final List<String> tags;
  final int version;
  final String? thumbnailReference;
  final String? duplicateOf;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> metadata;

  const DocumentAsset({
    required this.id,
    required this.kind,
    required this.storage,
    required this.name,
    required this.mimeType,
    this.sizeBytes,
    this.checksum,
    this.localPath,
    this.remoteUrl,
    this.durableReference,
    this.license,
    this.folderId,
    this.tags = const [],
    this.version = 1,
    this.thumbnailReference,
    this.duplicateOf,
    required this.createdAt,
    required this.updatedAt,
    this.metadata = const {},
  });

  /// A bucket-relative Storage path or typed opaque artifact handle is durable
  /// metadata. Signed/public delivery URLs and native paths stay runtime-only.
  bool get hasDurableReference =>
      _validatedDurableReference(durableReference) != null ||
      _validatedDurableReference(remoteUrl) != null;

  String? _validatedDurableReference(String? value) =>
      _validatedDurableReferenceForKind(kind, value);

  static String? _validatedDurableReferenceForKind(
    DocumentAssetKind kind,
    String? value,
  ) {
    final stable = durableAssetReference(value);
    if (stable != null) return stable;
    return switch (kind) {
      DocumentAssetKind.image => validImageArtifactReference(value),
      DocumentAssetKind.video => validVideoArtifactReference(value),
      DocumentAssetKind.model3d => validModel3DArtifactReference(value),
      DocumentAssetKind.document => validFileArtifactReference(value),
      DocumentAssetKind.audio => validMediaArtifactReference(value),
      _ => null,
    };
  }

  String? _validatedThumbnailReference(String? value) =>
      durableAssetReference(value) ??
      validImageArtifactReference(value) ??
      validMediaArtifactReference(value);

  DocumentAsset copyWith({
    String? id,
    DocumentAssetKind? kind,
    DocumentAssetStorage? storage,
    String? name,
    String? mimeType,
    Object? sizeBytes = _sentinel,
    Object? checksum = _sentinel,
    Object? localPath = _sentinel,
    Object? remoteUrl = _sentinel,
    Object? durableReference = _sentinel,
    Object? license = _sentinel,
    Object? folderId = _sentinel,
    List<String>? tags,
    int? version,
    Object? thumbnailReference = _sentinel,
    Object? duplicateOf = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return DocumentAsset(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      storage: storage ?? this.storage,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes == _sentinel ? this.sizeBytes : sizeBytes as int?,
      checksum: checksum == _sentinel ? this.checksum : checksum as String?,
      localPath: localPath == _sentinel ? this.localPath : localPath as String?,
      remoteUrl: remoteUrl == _sentinel ? this.remoteUrl : remoteUrl as String?,
      durableReference: durableReference == _sentinel
          ? this.durableReference
          : durableReference as String?,
      license: license == _sentinel ? this.license : license as String?,
      folderId: folderId == _sentinel ? this.folderId : folderId as String?,
      tags: tags ?? this.tags,
      version: version ?? this.version,
      thumbnailReference: thumbnailReference == _sentinel
          ? this.thumbnailReference
          : thumbnailReference as String?,
      duplicateOf: duplicateOf == _sentinel
          ? this.duplicateOf
          : duplicateOf as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'storage': storage.name,
    'name': name,
    'mimeType': mimeType,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    if (checksum != null) 'checksum': checksum,
    'remoteUrl': ?_validatedDurableReference(remoteUrl),
    'durableReference': ?_validatedDurableReference(durableReference),
    if (license != null) 'license': license,
    if (folderId != null) 'folderId': folderId,
    if (tags.isNotEmpty) 'tags': tags,
    'version': version,
    'thumbnailReference': ?_validatedThumbnailReference(thumbnailReference),
    if (duplicateOf != null) 'duplicateOf': duplicateOf,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (metadata.isNotEmpty) 'metadata': _durablePersistenceMetadata(metadata),
  };

  /// Durable asset metadata. Local paths and runtime delivery URLs are
  /// intentionally excluded; only stable references and descriptive metadata
  /// cross the persistence boundary.
  Map<String, dynamic> toPersistenceJson() => {
    'id': id,
    'kind': kind.name,
    'storage': storage.name,
    'name': name,
    'mimeType': mimeType,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    if (checksum != null) 'checksum': checksum,
    if (_validatedDurableReference(durableReference) case final value?)
      'durableReference': value
    else
      'durableReference': ?_validatedDurableReference(remoteUrl),
    if (license != null) 'license': license,
    if (folderId != null) 'folderId': folderId,
    if (tags.isNotEmpty) 'tags': tags,
    'version': version,
    'thumbnailReference': ?_validatedThumbnailReference(thumbnailReference),
    if (duplicateOf != null) 'duplicateOf': duplicateOf,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (metadata.isNotEmpty) 'metadata': _durablePersistenceMetadata(metadata),
  };

  static Map<String, dynamic> _durablePersistenceMetadata(
    Map<String, dynamic> values,
  ) {
    final result = <String, dynamic>{};
    for (final entry in values.entries) {
      final key = entry.key;
      if (result.length >= 100 ||
          key.isEmpty ||
          key.length > 120 ||
          key.codeUnits.any((code) => code < 0x20 || code == 0x7f)) {
        continue;
      }
      final value = _durablePersistenceMetadataValue(entry.value, depth: 0);
      if (value != null) result[key] = value;
    }
    return result;
  }

  static dynamic _durablePersistenceMetadataValue(
    dynamic value, {
    required int depth,
  }) {
    if (depth > 5) return null;
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : null;
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty ||
          normalized.length > 4096 ||
          normalized.codeUnits.any((code) => code < 0x20 || code == 0x7f)) {
        return null;
      }
      final ownedReference =
          validImageArtifactReference(normalized) ??
          validVideoArtifactReference(normalized) ??
          validModel3DArtifactReference(normalized) ??
          validFileArtifactReference(normalized) ??
          validMediaArtifactReference(normalized);
      if (ownedReference != null) return ownedReference;
      if (durableAssetReference(normalized) != null) return normalized;
      final uri = Uri.tryParse(normalized);
      if (uri?.scheme.isNotEmpty == true ||
          normalized.startsWith('/') ||
          normalized.startsWith('\\\\') ||
          RegExp(r'^[a-z]:[\\/]').hasMatch(normalized)) {
        return null;
      }
      return normalized;
    }
    if (value is List) {
      final result = <dynamic>[];
      for (final child in value) {
        if (result.length >= 100) break;
        final sanitized = _durablePersistenceMetadataValue(
          child,
          depth: depth + 1,
        );
        if (sanitized != null) result.add(sanitized);
      }
      return result;
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        if (result.length >= 100 ||
            entry.key is! String ||
            (entry.key as String).isEmpty ||
            (entry.key as String).length > 120 ||
            (entry.key as String).codeUnits.any(
              (code) => code < 0x20 || code == 0x7f,
            )) {
          continue;
        }
        final sanitized = _durablePersistenceMetadataValue(
          entry.value,
          depth: depth + 1,
        );
        if (sanitized != null) result[entry.key as String] = sanitized;
      }
      return result;
    }
    return null;
  }

  factory DocumentAsset.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final rawMetadata = json['metadata'];
    return DocumentAsset(
      id: _requiredString(json['id'], 'id'),
      kind: _enumFromName(
        DocumentAssetKind.values,
        json['kind'] as String?,
        DocumentAssetKind.other,
      ),
      storage: _enumFromName(
        DocumentAssetStorage.values,
        json['storage'] as String?,
        DocumentAssetStorage.unknown,
      ),
      name: json['name'] as String? ?? 'Untitled asset',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      checksum: json['checksum'] as String?,
      // Local filesystem paths are runtime-only and must not be rehydrated
      // into a durable asset model.
      localPath: null,
      remoteUrl: _validatedDurableReferenceForKind(
        _enumFromName(
          DocumentAssetKind.values,
          json['kind'] as String?,
          DocumentAssetKind.other,
        ),
        json['remoteUrl'] as String?,
      ),
      durableReference: _validatedDurableReferenceForKind(
        _enumFromName(
          DocumentAssetKind.values,
          json['kind'] as String?,
          DocumentAssetKind.other,
        ),
        json['durableReference'] as String?,
      ),
      license: json['license'] as String?,
      folderId: json['folderId'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.whereType<String>().toList() ??
          const [],
      version: (json['version'] as num?)?.toInt() ?? 1,
      thumbnailReference:
          durableAssetReference(json['thumbnailReference'] as String?) ??
          validImageArtifactReference(json['thumbnailReference'] as String?) ??
          validMediaArtifactReference(json['thumbnailReference'] as String?),
      duplicateOf: json['duplicateOf'] as String?,
      createdAt: createdAt?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          updatedAt?.toUtc() ??
          createdAt?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      metadata: rawMetadata is Map
          ? _durablePersistenceMetadata(Map<String, dynamic>.from(rawMetadata))
          : const {},
    );
  }

  static T _enumFromName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static String _requiredString(Object? value, String field) {
    final result = value is String ? value.trim() : '';
    if (result.isEmpty) {
      throw FormatException('Document asset $field is required.');
    }
    return result;
  }

  static const Object _sentinel = Object();
}

class DocumentAssetManifest {
  final int version;
  final Map<String, DocumentAsset> entries;

  const DocumentAssetManifest({this.version = 1, this.entries = const {}});

  /// Ensures every map key is the unique durable identity of its asset.
  ///
  /// The constructor stays permissive so package diagnostics can inspect and
  /// repair malformed imported data. Production boundaries call this before
  /// consuming or persisting manifest entries.
  void validateIdentity() {
    final assetIds = <String>{};
    for (final entry in entries.entries) {
      final key = entry.key;
      final id = entry.value.id;
      if (key.isEmpty || key.trim() != key || key != id) {
        throw FormatException(
          'Document asset manifest key "$key" does not match asset ID "$id".',
        );
      }
      if (!assetIds.add(id)) {
        throw FormatException('Duplicate document asset ID: $id');
      }
    }
  }

  List<DocumentAsset> get items => entries.values.toList(growable: false);

  void _validateAssetId(String id) {
    if (id.isEmpty || id.trim() != id) {
      throw FormatException('Document asset ID is invalid: "$id".');
    }
  }

  void _validateEntries(Map<String, DocumentAsset> values) {
    DocumentAssetManifest(entries: values).validateIdentity();
  }

  DocumentAsset? operator [](String id) => entries[id];

  DocumentAssetManifest upsert(DocumentAsset asset) {
    validateIdentity();
    _validateAssetId(asset.id);
    final next = {...entries, asset.id: asset};
    _validateEntries(next);
    return DocumentAssetManifest(version: version, entries: next);
  }

  DocumentAssetManifest remove(String id) {
    validateIdentity();
    _validateAssetId(id);
    if (!entries.containsKey(id)) return this;
    final next = Map<String, DocumentAsset>.from(entries)..remove(id);
    return DocumentAssetManifest(version: version, entries: next);
  }

  DocumentAssetManifest merge(DocumentAssetManifest other) {
    validateIdentity();
    other.validateIdentity();
    if (other.entries.isEmpty) return this;
    final merged = Map<String, DocumentAsset>.from(entries);
    for (final entry in other.entries.entries) {
      // A manifest ID is the durable identity. Keep the receiver's asset on
      // collision; callers that intentionally replace an asset must use
      // [replace] or [upsert] explicitly.
      merged.putIfAbsent(entry.key, () => entry.value);
    }
    _validateEntries(merged);
    return DocumentAssetManifest(
      version: version >= other.version ? version : other.version,
      entries: merged,
    );
  }

  Iterable<DocumentAsset> search({
    String query = '',
    DocumentAssetKind? kind,
    String? folderId,
    Iterable<String> tags = const [],
  }) {
    validateIdentity();
    final normalizedQuery = query.trim().toLowerCase();
    final requiredTags = tags
        .map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final result = entries.values
        .where((asset) {
          if (kind != null && asset.kind != kind) return false;
          if (folderId != null && asset.folderId != folderId) return false;
          if (!requiredTags.every(
            (tag) =>
                asset.tags.any((candidate) => candidate.toLowerCase() == tag),
          )) {
            return false;
          }
          if (normalizedQuery.isEmpty) return true;
          return [
            asset.id,
            asset.name,
            asset.mimeType,
            asset.license ?? '',
            ...asset.tags,
          ].join(' ').toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);
    return result;
  }

  DocumentAsset? findDuplicate(DocumentAsset candidate) {
    validateIdentity();
    final checksum = candidate.checksum?.trim();
    if (checksum == null || checksum.isEmpty) return null;
    return entries.values
        .where(
          (asset) => asset.id != candidate.id && asset.checksum == checksum,
        )
        .firstOrNull;
  }

  DocumentAssetManifest relink(
    String assetId, {
    required String durableReference,
    DocumentAssetStorage? storage,
    String? remoteUrl,
    String? localPath,
  }) {
    validateIdentity();
    final asset = entries[assetId];
    if (asset == null) return this;
    final validatedReference = DocumentAsset._validatedDurableReferenceForKind(
      asset.kind,
      durableReference,
    );
    if (validatedReference == null) {
      throw ArgumentError.value(
        durableReference,
        'durableReference',
        'Reference is invalid for asset kind ${asset.kind.name}.',
      );
    }
    return upsert(
      asset.copyWith(
        storage: storage,
        durableReference: validatedReference,
        remoteUrl: remoteUrl,
        localPath: localPath,
        version: asset.version + 1,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  DocumentAssetManifest replace(String assetId, DocumentAsset replacement) {
    validateIdentity();
    _validateAssetId(assetId);
    final existing = entries[assetId];
    if (existing == null) return this;
    return upsert(
      replacement.copyWith(
        id: assetId,
        version: existing.version + 1,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  DocumentAssetManifest copyWith({
    int? version,
    Map<String, DocumentAsset>? entries,
  }) {
    final nextEntries = entries ?? this.entries;
    _validateEntries(nextEntries);
    return DocumentAssetManifest(
      version: version ?? this.version,
      entries: nextEntries,
    );
  }

  Map<String, dynamic> toJson() {
    validateIdentity();
    return {
      'version': version,
      'items': items.map((asset) => asset.toJson()).toList(growable: false),
    };
  }

  Map<String, dynamic> toPersistenceJson() {
    validateIdentity();
    return {
      'version': version,
      'items': items
          .map((asset) => asset.toPersistenceJson())
          .toList(growable: false),
    };
  }

  factory DocumentAssetManifest.fromJson(Object? raw) {
    if (raw == null) return const DocumentAssetManifest();
    if (raw is List) {
      return _fromItems(version: 1, rawItems: raw);
    }
    if (raw is! Map) {
      throw const FormatException('Document asset manifest must be an object.');
    }
    final version = (raw['version'] as num?)?.toInt() ?? 1;
    final rawItems = raw['items'];
    return _fromItems(version: version, rawItems: rawItems);
  }

  static DocumentAssetManifest _fromItems({
    required int version,
    required Object? rawItems,
  }) {
    if (rawItems == null) {
      return DocumentAssetManifest(version: version);
    }
    if (rawItems is! List) {
      throw const FormatException(
        'Document asset manifest items must be a list.',
      );
    }
    final entries = <String, DocumentAsset>{};
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        throw const FormatException('Document asset entries must be objects.');
      }
      final asset = DocumentAsset.fromJson(Map<String, dynamic>.from(rawItem));
      if (entries.containsKey(asset.id)) {
        throw FormatException('Duplicate document asset ID: ${asset.id}');
      }
      entries[asset.id] = asset;
    }
    return DocumentAssetManifest(version: version, entries: entries);
  }
}
