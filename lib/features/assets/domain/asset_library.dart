import 'dart:convert';

import '../../../domain/models/document_asset.dart';
import '../../../domain/models/durable_asset_reference.dart';

bool _hasAssetLibraryControlCharacter(String value) =>
    value.codeUnits.any((code) => code < 0x20 || code == 0x7f);

bool _isNonPersistableLocalReference(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return false;
  final isWindowsDrivePath = RegExp(r'^[a-z]:[\\/]').hasMatch(normalized);
  return normalized.startsWith('data:') ||
      normalized.startsWith('blob:') ||
      normalized.startsWith('http://') ||
      normalized.startsWith('https://') ||
      (!isWindowsDrivePath &&
          RegExp(r'^[a-z][a-z0-9+.-]*:').hasMatch(normalized));
}

bool _isHttpsUrl(String? value) =>
    value?.trim().toLowerCase().startsWith('https://') == true;

/// Kinds exposed by the reusable asset catalog.
enum AssetLibraryItemKind {
  image,
  graphic,
  icon,
  illustration,
  video,
  audio,
  model3d,
  file,
}

enum AssetLibrarySource { upload, openverse, wikimedia, bundled, remote }

enum AssetLibraryItemStatus { ready, syncing, missing, failed }

enum AssetLibrarySort { recent, name, mostUsed }

class AssetLibraryQuotaExceededException implements Exception {
  const AssetLibraryQuotaExceededException();

  @override
  String toString() => 'Workspace asset storage quota exceeded.';
}

class AssetLibraryFolder {
  final String id;
  final String scopeId;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AssetLibraryFolder({
    required String id,
    required String scopeId,
    required String name,
    String? parentId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    final normalizedId = id.trim();
    final normalizedScopeId = scopeId.trim();
    final normalizedName = name.trim();
    if (normalizedId.isEmpty ||
        normalizedId.length > 256 ||
        id != normalizedId ||
        _hasAssetLibraryControlCharacter(id) ||
        _hasAssetLibraryControlCharacter(normalizedId)) {
      throw ArgumentError.value(
        id,
        'id',
        'Folder ID must contain 1 to 256 safe characters.',
      );
    }
    if (normalizedScopeId.isEmpty ||
        normalizedScopeId.length > 256 ||
        scopeId != normalizedScopeId ||
        _hasAssetLibraryControlCharacter(scopeId) ||
        _hasAssetLibraryControlCharacter(normalizedScopeId) ||
        normalizedScopeId == 'drawing-paper') {
      throw ArgumentError.value(
        scopeId,
        'scopeId',
        'Folder scope is invalid or reserved.',
      );
    }
    if (normalizedName.isEmpty ||
        normalizedName.length > 120 ||
        name != normalizedName ||
        _hasAssetLibraryControlCharacter(name) ||
        _hasAssetLibraryControlCharacter(normalizedName)) {
      throw ArgumentError.value(
        name,
        'name',
        'Folder name must contain 1 to 120 safe characters.',
      );
    }
    final normalizedParentId = parentId?.trim();
    if (normalizedParentId != null &&
        (parentId != normalizedParentId ||
            _hasAssetLibraryControlCharacter(parentId!) ||
            normalizedParentId.length > 256 ||
            _hasAssetLibraryControlCharacter(normalizedParentId))) {
      throw ArgumentError.value(
        parentId,
        'parentId',
        'Parent folder IDs must contain at most 256 safe characters.',
      );
    }
    if (normalizedParentId == normalizedId) {
      throw ArgumentError.value(
        parentId,
        'parentId',
        'A folder cannot contain itself.',
      );
    }
    return AssetLibraryFolder._(
      id: normalizedId,
      scopeId: normalizedScopeId,
      name: normalizedName,
      parentId: normalizedParentId?.isEmpty == true ? null : normalizedParentId,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  const AssetLibraryFolder._({
    required this.id,
    required this.scopeId,
    required this.name,
    required this.parentId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'scopeId': scopeId,
    'name': name,
    'parentId': parentId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory AssetLibraryFolder.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(
      AssetLibraryItem._requiredJsonString(json, 'createdAt'),
    );
    final updatedAt = DateTime.tryParse(
      AssetLibraryItem._requiredJsonString(json, 'updatedAt'),
    );
    if (createdAt == null || updatedAt == null) {
      throw const FormatException(
        'Asset library folder timestamps are required.',
      );
    }
    return AssetLibraryFolder(
      id: AssetLibraryItem._requiredJsonString(json, 'id'),
      scopeId: AssetLibraryItem._requiredJsonString(json, 'scopeId'),
      name: AssetLibraryItem._requiredJsonString(json, 'name'),
      parentId: AssetLibraryItem._optionalJsonString(json, 'parentId'),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class AssetLibraryItem {
  final String id;
  final String scopeId;
  final AssetLibraryItemKind kind;
  final AssetLibrarySource source;
  final AssetLibraryItemStatus status;
  final String name;
  final String? description;
  final String? creator;
  final String? creatorUrl;
  final String? sourceUrl;
  final String? previewUrl;
  final String? downloadUrl;
  final String? localPath;
  final String? storagePath;
  final String mimeType;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? checksum;
  final String? providerAssetId;
  final String? license;
  final String? licenseUrl;
  final String? attribution;
  final String? folderId;
  final List<String> tags;
  final bool favorite;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final Map<String, dynamic> metadata;

  factory AssetLibraryItem({
    required String id,
    required String scopeId,
    required AssetLibraryItemKind kind,
    required AssetLibrarySource source,
    AssetLibraryItemStatus status = AssetLibraryItemStatus.ready,
    required String name,
    String? description,
    String? creator,
    String? creatorUrl,
    String? sourceUrl,
    String? previewUrl,
    String? thumbnailUrl,
    String? downloadUrl,
    String? localPath,
    String? storagePath,
    String mimeType = 'application/octet-stream',
    int? sizeBytes,
    int? width,
    int? height,
    int? durationMs,
    String? checksum,
    String? providerAssetId,
    String? license,
    String? licenseUrl,
    String? attribution,
    String? folderId,
    List<String> tags = const [],
    bool favorite = false,
    int usageCount = 0,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? lastUsedAt,
    Map<String, dynamic> metadata = const {},
  }) {
    final normalizedId = id.trim();
    final normalizedScopeId = scopeId.trim();
    final normalizedName = name.trim();
    if (normalizedId.isEmpty ||
        normalizedId.length > 256 ||
        id != normalizedId ||
        _hasAssetLibraryControlCharacter(id) ||
        _hasAssetLibraryControlCharacter(normalizedId)) {
      throw ArgumentError.value(
        id,
        'id',
        'Asset library ID must contain 1 to 256 safe characters.',
      );
    }
    if (normalizedScopeId.isEmpty ||
        normalizedScopeId.length > 256 ||
        scopeId != normalizedScopeId ||
        _hasAssetLibraryControlCharacter(scopeId) ||
        _hasAssetLibraryControlCharacter(normalizedScopeId) ||
        normalizedScopeId == 'drawing-paper') {
      throw ArgumentError.value(
        scopeId,
        'scopeId',
        'Asset library scope is invalid or reserved.',
      );
    }
    if (normalizedName.isEmpty ||
        normalizedName.length > 240 ||
        name != normalizedName ||
        _hasAssetLibraryControlCharacter(name) ||
        _hasAssetLibraryControlCharacter(normalizedName)) {
      throw ArgumentError.value(
        name,
        'name',
        'Asset library name must contain 1 to 240 safe characters.',
      );
    }
    _validateTextLength(
      description,
      'description',
      4096,
      allowLineBreaks: true,
    );
    _validateTextLength(creator, 'creator', 240);
    _validateTextLength(license, 'license', 120);
    if (license != null && license != license.trim()) {
      throw ArgumentError.value(
        license,
        'license',
        'Asset license cannot contain surrounding whitespace',
      );
    }
    _validateTextLength(attribution, 'attribution', 4096);
    if (sizeBytes != null && (sizeBytes < 0 || sizeBytes > 512 * 1024 * 1024)) {
      throw ArgumentError.value(
        sizeBytes,
        'sizeBytes',
        'Size must be between 0 and 512 MB.',
      );
    }
    if (usageCount < 0) {
      throw ArgumentError.value(
        usageCount,
        'usageCount',
        'Usage count cannot be negative.',
      );
    }
    if (width != null && width <= 0) {
      throw ArgumentError.value(width, 'width', 'Width must be positive.');
    }
    if (height != null && height <= 0) {
      throw ArgumentError.value(height, 'height', 'Height must be positive.');
    }
    if (durationMs != null && durationMs < 0) {
      throw ArgumentError.value(
        durationMs,
        'durationMs',
        'Duration cannot be negative.',
      );
    }
    final normalizedMimeType = mimeType.trim().toLowerCase().isEmpty
        ? 'application/octet-stream'
        : mimeType.trim().toLowerCase();
    if (normalizedMimeType.length > 120 ||
        _hasAssetLibraryControlCharacter(normalizedMimeType) ||
        !RegExp(
          r'^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$',
        ).hasMatch(normalizedMimeType)) {
      throw ArgumentError.value(
        mimeType,
        'mimeType',
        'MIME types must use a bounded type/subtype format.',
      );
    }
    final normalizedPreviewUrl = _trimToNull(previewUrl ?? thumbnailUrl);
    if (localPath != null && _hasAssetLibraryControlCharacter(localPath)) {
      throw ArgumentError.value(
        localPath,
        'localPath',
        'Local paths cannot contain control characters.',
      );
    }
    if (localPath != null &&
        localPath.isNotEmpty &&
        localPath != localPath.trim()) {
      throw ArgumentError.value(
        localPath,
        'localPath',
        'Local paths cannot contain leading or trailing whitespace.',
      );
    }
    final normalizedLocalPath = _trimToNull(localPath);
    final normalizedStoragePath = _trimToNull(storagePath);
    _validateUrl(sourceUrl, 'sourceUrl');
    _validateUrl(previewUrl ?? thumbnailUrl, 'previewUrl');
    _validateUrl(downloadUrl, 'downloadUrl');
    _validateUrl(creatorUrl, 'creatorUrl');
    _validateUrl(licenseUrl, 'licenseUrl');
    _validateStoragePath(storagePath);
    _validateStoragePath(normalizedStoragePath);
    if (folderId != null &&
        folderId.isNotEmpty &&
        folderId != folderId.trim()) {
      throw ArgumentError.value(
        folderId,
        'folderId',
        'Folder IDs cannot contain leading or trailing whitespace.',
      );
    }
    if (folderId != null && _hasAssetLibraryControlCharacter(folderId)) {
      throw ArgumentError.value(
        folderId,
        'folderId',
        'Folder IDs cannot contain control characters.',
      );
    }
    final normalizedFolderId = _trimToNull(folderId);
    if (normalizedFolderId != null &&
        (normalizedFolderId.length > 256 ||
            _hasAssetLibraryControlCharacter(normalizedFolderId))) {
      throw ArgumentError.value(
        folderId,
        'folderId',
        'Folder IDs must contain at most 256 safe characters.',
      );
    }
    _validateChecksum(checksum);
    final normalizedChecksum = _trimToNull(checksum)?.toLowerCase();
    if (providerAssetId != null &&
        providerAssetId.isNotEmpty &&
        providerAssetId != providerAssetId.trim()) {
      throw ArgumentError.value(
        providerAssetId,
        'providerAssetId',
        'Provider asset IDs cannot contain leading or trailing whitespace.',
      );
    }
    if (providerAssetId != null &&
        _hasAssetLibraryControlCharacter(providerAssetId)) {
      throw ArgumentError.value(
        providerAssetId,
        'providerAssetId',
        'Provider asset IDs cannot contain control characters.',
      );
    }
    final normalizedProviderAssetId = _trimToNull(providerAssetId);
    if (normalizedProviderAssetId != null &&
        (normalizedProviderAssetId.length > 256 ||
            _hasAssetLibraryControlCharacter(normalizedProviderAssetId))) {
      throw ArgumentError.value(
        providerAssetId,
        'providerAssetId',
        'Provider asset IDs must contain at most 256 safe characters.',
      );
    }
    if (tags.any((tag) => tag.isNotEmpty && tag != tag.trim())) {
      throw ArgumentError.value(
        tags,
        'tags',
        'Tag values cannot contain leading or trailing whitespace.',
      );
    }
    final sanitizedMetadata = _sanitizeMetadata(metadata);
    if (utf8.encode(jsonEncode(sanitizedMetadata)).length > 256 * 1024) {
      throw ArgumentError.value(
        metadata,
        'metadata',
        'Asset metadata cannot exceed 256 KB.',
      );
    }

    return AssetLibraryItem._(
      id: normalizedId,
      scopeId: normalizedScopeId,
      kind: kind,
      source: source,
      status: status,
      name: normalizedName,
      description: _trimToNull(description),
      creator: _trimToNull(creator),
      creatorUrl: _trimToNull(creatorUrl),
      sourceUrl: _trimToNull(sourceUrl),
      previewUrl: normalizedPreviewUrl,
      downloadUrl: _trimToNull(downloadUrl),
      localPath: _isNonPersistableLocalReference(normalizedLocalPath)
          ? null
          : normalizedLocalPath,
      storagePath: normalizedStoragePath,
      mimeType: normalizedMimeType,
      sizeBytes: sizeBytes,
      width: width,
      height: height,
      durationMs: durationMs,
      checksum: normalizedChecksum,
      providerAssetId: normalizedProviderAssetId,
      license: _trimToNull(license),
      licenseUrl: _trimToNull(licenseUrl),
      attribution: _trimToNull(attribution),
      folderId: normalizedFolderId,
      tags: _normalizeTags(tags),
      favorite: favorite,
      usageCount: usageCount,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      lastUsedAt: lastUsedAt?.toUtc(),
      metadata: Map<String, dynamic>.unmodifiable(sanitizedMetadata),
    );
  }

  const AssetLibraryItem._({
    required this.id,
    required this.scopeId,
    required this.kind,
    required this.source,
    required this.status,
    required this.name,
    required this.description,
    required this.creator,
    required this.creatorUrl,
    required this.sourceUrl,
    required this.previewUrl,
    required this.downloadUrl,
    required this.localPath,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.checksum,
    required this.providerAssetId,
    required this.license,
    required this.licenseUrl,
    required this.attribution,
    required this.folderId,
    required this.tags,
    required this.favorite,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
    required this.lastUsedAt,
    required this.metadata,
  });

  bool get isPersisted =>
      source == AssetLibrarySource.upload ||
      source == AssetLibrarySource.bundled ||
      storagePath != null;

  /// Whether the catalog item already has a durable source.
  ///
  /// Provider URLs and native paths are compatibility inputs only. The canvas
  /// materializes those inputs into an owned artifact before creating an image
  /// node, so they must not make a catalog item appear durably linked.
  bool get hasDurableReference =>
      source == AssetLibrarySource.bundled || storagePath != null;

  /// Whether the item has an input that can be hydrated at runtime.
  ///
  /// Images still pass through [ImageArtifactStore] before insertion. This
  /// predicate only controls whether the catalog should offer the action; it
  /// does not authorize a URL or local path to enter a canvas payload.
  bool get isRuntimeReady =>
      source == AssetLibrarySource.bundled ||
      storagePath != null ||
      _hasOwnedArtifactReference ||
      _isHttpsUrl(downloadUrl) ||
      _isHttpsUrl(sourceUrl) ||
      _isHttpsUrl(previewUrl) ||
      (localPath?.trim().isNotEmpty ?? false);

  bool get _hasOwnedArtifactReference {
    final value = metadata[_artifactReferenceMetadataKey(kind)]?.toString();
    return switch (kind) {
      AssetLibraryItemKind.image ||
      AssetLibraryItemKind.graphic ||
      AssetLibraryItemKind.icon ||
      AssetLibraryItemKind.illustration =>
        validImageArtifactReference(value) != null,
      AssetLibraryItemKind.file => validFileArtifactReference(value) != null,
      AssetLibraryItemKind.audio => validMediaArtifactReference(value) != null,
      AssetLibraryItemKind.video => validVideoArtifactReference(value) != null,
      AssetLibraryItemKind.model3d =>
        validModel3DArtifactReference(value) != null,
    };
  }

  String _artifactReferenceMetadataKey(AssetLibraryItemKind value) =>
      switch (value) {
        AssetLibraryItemKind.image ||
        AssetLibraryItemKind.graphic ||
        AssetLibraryItemKind.icon ||
        AssetLibraryItemKind.illustration => 'imageArtifactReference',
        AssetLibraryItemKind.file => 'fileArtifactReference',
        AssetLibraryItemKind.audio => 'audioArtifactReference',
        AssetLibraryItemKind.video => 'videoArtifactReference',
        AssetLibraryItemKind.model3d => 'model3dArtifactReference',
      };

  String? get runtimeUrl => _isHttpsUrl(downloadUrl)
      ? downloadUrl
      : _isHttpsUrl(sourceUrl)
      ? sourceUrl
      : _isHttpsUrl(previewUrl)
      ? previewUrl
      : null;

  String? get durableSourcePath => storagePath;

  bool get isInsertable =>
      status == AssetLibraryItemStatus.ready && isRuntimeReady;

  String? get thumbnailUrl => previewUrl;

  bool get hasPreview =>
      (previewUrl?.trim().isNotEmpty ?? false) ||
      (localPath?.trim().isNotEmpty ?? false);

  String get typeLabel => switch (kind) {
    AssetLibraryItemKind.image => 'Image',
    AssetLibraryItemKind.graphic => 'Graphic',
    AssetLibraryItemKind.icon => 'Icon',
    AssetLibraryItemKind.illustration => 'Illustration',
    AssetLibraryItemKind.video => 'Video',
    AssetLibraryItemKind.audio => 'Audio',
    AssetLibraryItemKind.model3d => '3D Model',
    AssetLibraryItemKind.file => 'File',
  };

  AssetLibraryItem copyWith({
    String? id,
    String? scopeId,
    AssetLibraryItemKind? kind,
    AssetLibrarySource? source,
    AssetLibraryItemStatus? status,
    String? name,
    Object? description = _sentinel,
    Object? creator = _sentinel,
    Object? creatorUrl = _sentinel,
    Object? sourceUrl = _sentinel,
    Object? previewUrl = _sentinel,
    Object? downloadUrl = _sentinel,
    Object? localPath = _sentinel,
    Object? storagePath = _sentinel,
    String? mimeType,
    Object? sizeBytes = _sentinel,
    Object? width = _sentinel,
    Object? height = _sentinel,
    Object? durationMs = _sentinel,
    Object? checksum = _sentinel,
    Object? providerAssetId = _sentinel,
    Object? license = _sentinel,
    Object? licenseUrl = _sentinel,
    Object? attribution = _sentinel,
    Object? folderId = _sentinel,
    List<String>? tags,
    bool? favorite,
    int? usageCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? lastUsedAt = _sentinel,
    Map<String, dynamic>? metadata,
  }) {
    return AssetLibraryItem(
      id: id ?? this.id,
      scopeId: scopeId ?? this.scopeId,
      kind: kind ?? this.kind,
      source: source ?? this.source,
      status: status ?? this.status,
      name: name ?? this.name,
      description: description == _sentinel
          ? this.description
          : description as String?,
      creator: creator == _sentinel ? this.creator : creator as String?,
      creatorUrl: creatorUrl == _sentinel
          ? this.creatorUrl
          : creatorUrl as String?,
      sourceUrl: sourceUrl == _sentinel ? this.sourceUrl : sourceUrl as String?,
      previewUrl: previewUrl == _sentinel
          ? this.previewUrl
          : previewUrl as String?,
      downloadUrl: downloadUrl == _sentinel
          ? this.downloadUrl
          : downloadUrl as String?,
      localPath: localPath == _sentinel ? this.localPath : localPath as String?,
      storagePath: storagePath == _sentinel
          ? this.storagePath
          : storagePath as String?,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes == _sentinel ? this.sizeBytes : sizeBytes as int?,
      width: width == _sentinel ? this.width : width as int?,
      height: height == _sentinel ? this.height : height as int?,
      durationMs: durationMs == _sentinel
          ? this.durationMs
          : durationMs as int?,
      checksum: checksum == _sentinel ? this.checksum : checksum as String?,
      providerAssetId: providerAssetId == _sentinel
          ? this.providerAssetId
          : providerAssetId as String?,
      license: license == _sentinel ? this.license : license as String?,
      licenseUrl: licenseUrl == _sentinel
          ? this.licenseUrl
          : licenseUrl as String?,
      attribution: attribution == _sentinel
          ? this.attribution
          : attribution as String?,
      folderId: folderId == _sentinel ? this.folderId : folderId as String?,
      tags: tags ?? this.tags,
      favorite: favorite ?? this.favorite,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt == _sentinel
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
      metadata: metadata ?? this.metadata,
    );
  }

  DocumentAsset toDocumentAsset({
    String? assetId,
    String? imageArtifactReference,
  }) {
    // Native paths and provider URLs are catalog/runtime compatibility values.
    // Durable document metadata keeps only scoped Storage or owned references.
    final ownedReference = switch (_documentAssetKind) {
      DocumentAssetKind.image => validImageArtifactReference(
        imageArtifactReference ??
            metadata['imageArtifactReference']?.toString(),
      ),
      DocumentAssetKind.video => validVideoArtifactReference(
        metadata['videoArtifactReference']?.toString(),
      ),
      DocumentAssetKind.model3d => validModel3DArtifactReference(
        metadata['model3dArtifactReference']?.toString(),
      ),
      DocumentAssetKind.document => validFileArtifactReference(
        metadata['fileArtifactReference']?.toString(),
      ),
      DocumentAssetKind.audio => validMediaArtifactReference(
        metadata['audioArtifactReference']?.toString(),
      ),
      _ => null,
    };
    final storageReference = durableAssetReference(storagePath);
    const String? persistedPreviewUrl = null;
    final durableReference = storageReference ?? ownedReference;
    final durableMetadata = _durableMetadata(metadata);
    final mergedMetadata = <String, dynamic>{
      'storagePath': ?storageReference,
      ...durableMetadata,
      'libraryItemId': id,
      if (assetId != null && assetId.trim().isNotEmpty) 'assetId': assetId,
      'scopeId': scopeId,
      'source': source.name,
      if (providerAssetId != null) 'providerAssetId': providerAssetId,
      if (creator != null) 'creator': creator,
      if (attribution != null) 'attribution': attribution,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'durationMs': durationMs,
    };
    return DocumentAsset(
      id: assetId?.trim().isNotEmpty == true ? assetId!.trim() : id,
      kind: _documentAssetKind,
      storage: storageReference != null
          ? DocumentAssetStorage.remote
          : ownedReference != null
          ? DocumentAssetStorage.local
          : source == AssetLibrarySource.bundled
          ? DocumentAssetStorage.bundled
          : DocumentAssetStorage.unknown,
      name: name,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      checksum: checksum,
      localPath: null,
      remoteUrl: null,
      durableReference: durableReference,
      license: license,
      folderId: folderId,
      tags: tags,
      thumbnailReference: persistedPreviewUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
      metadata: mergedMetadata,
    );
  }

  DocumentAssetKind get _documentAssetKind => switch (kind) {
    AssetLibraryItemKind.image ||
    AssetLibraryItemKind.graphic ||
    AssetLibraryItemKind.icon ||
    AssetLibraryItemKind.illustration => DocumentAssetKind.image,
    AssetLibraryItemKind.video => DocumentAssetKind.video,
    AssetLibraryItemKind.audio => DocumentAssetKind.audio,
    AssetLibraryItemKind.model3d => DocumentAssetKind.model3d,
    AssetLibraryItemKind.file => DocumentAssetKind.document,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'scopeId': scopeId,
    'kind': kind.name,
    'source': source.name,
    'status': status.name,
    'name': name,
    'description': description,
    'creator': creator,
    'creatorUrl': creatorUrl,
    'sourceUrl': sourceUrl,
    // Data URIs are transient previews and must not duplicate binary bytes in
    // local catalog persistence or document metadata.
    'previewUrl': _isPersistablePreviewUrl(previewUrl) ? previewUrl : null,
    'downloadUrl': downloadUrl,
    'localPath': _isNonPersistableLocalReference(localPath) ? null : localPath,
    'storagePath': storagePath,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'width': width,
    'height': height,
    'durationMs': durationMs,
    'checksum': checksum,
    'providerAssetId': providerAssetId,
    'license': license,
    'licenseUrl': licenseUrl,
    'attribution': attribution,
    'folderId': folderId,
    'tags': tags,
    'favorite': favorite,
    'usageCount': usageCount,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastUsedAt': lastUsedAt?.toIso8601String(),
    'metadata': metadata,
  };

  factory AssetLibraryItem.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(_requiredJsonString(json, 'createdAt'));
    final updatedAt = DateTime.tryParse(_requiredJsonString(json, 'updatedAt'));
    if (createdAt == null || updatedAt == null) {
      throw const FormatException('Asset library timestamps are required.');
    }
    final kindName = _requiredJsonString(json, 'kind');
    final sourceName = _requiredJsonString(json, 'source');
    final statusName = _requiredJsonString(json, 'status');
    _validateEnumName(kindName, AssetLibraryItemKind.values, 'kind');
    _validateEnumName(sourceName, AssetLibrarySource.values, 'source');
    _validateEnumName(statusName, AssetLibraryItemStatus.values, 'status');
    return AssetLibraryItem(
      id: _requiredJsonString(json, 'id'),
      scopeId: _requiredJsonString(json, 'scopeId'),
      kind: _enumFromName(
        AssetLibraryItemKind.values,
        kindName,
        AssetLibraryItemKind.file,
      ),
      source: _enumFromName(
        AssetLibrarySource.values,
        sourceName,
        AssetLibrarySource.remote,
      ),
      status: _enumFromName(
        AssetLibraryItemStatus.values,
        statusName,
        AssetLibraryItemStatus.ready,
      ),
      name: _requiredJsonString(json, 'name'),
      description: _optionalJsonString(json, 'description'),
      creator: _optionalJsonString(json, 'creator'),
      creatorUrl: _optionalJsonString(json, 'creatorUrl'),
      sourceUrl: _optionalJsonString(json, 'sourceUrl'),
      previewUrl:
          _optionalJsonString(json, 'previewUrl') ??
          _optionalJsonString(json, 'thumbnailUrl'),
      downloadUrl: _optionalJsonString(json, 'downloadUrl'),
      localPath: _optionalJsonString(json, 'localPath'),
      storagePath: _optionalJsonString(json, 'storagePath'),
      mimeType:
          _optionalJsonString(json, 'mimeType') ?? 'application/octet-stream',
      sizeBytes: _jsonInt(json, 'sizeBytes'),
      width: _jsonInt(json, 'width'),
      height: _jsonInt(json, 'height'),
      durationMs: _jsonInt(json, 'durationMs'),
      checksum: _optionalJsonString(json, 'checksum'),
      providerAssetId: _optionalJsonString(json, 'providerAssetId'),
      license: _optionalJsonString(json, 'license'),
      licenseUrl: _optionalJsonString(json, 'licenseUrl'),
      attribution: _optionalJsonString(json, 'attribution'),
      folderId: _optionalJsonString(json, 'folderId'),
      tags: _jsonTags(json['tags']),
      favorite: _jsonBool(json, 'favorite') ?? false,
      usageCount: _jsonInt(json, 'usageCount') ?? 0,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastUsedAt: _jsonDateTime(json, 'lastUsedAt'),
      metadata: _jsonMetadata(json['metadata']),
    );
  }

  static String _requiredJsonString(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value is! String) {
      throw FormatException('Asset library $field must be a string.');
    }
    if (value != value.trim()) {
      throw FormatException(
        'Asset library $field contains leading or trailing whitespace.',
      );
    }
    if (_hasAssetLibraryControlCharacter(value)) {
      throw FormatException(
        'Asset library $field contains control characters.',
      );
    }
    return value;
  }

  static String? _optionalJsonString(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('Asset library $field must be a string.');
  }

  static int? _jsonInt(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value == null) return null;
    if (value is! num || !value.isFinite || value != value.truncate()) {
      throw FormatException('Asset library $field must be an integer.');
    }
    return value.toInt();
  }

  static bool? _jsonBool(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value == null) return null;
    if (value is bool) return value;
    throw FormatException('Asset library $field must be a boolean.');
  }

  static DateTime? _jsonDateTime(Map<String, dynamic> json, String field) {
    final raw = _optionalJsonString(json, field);
    if (raw != null && raw.isNotEmpty && raw != raw.trim()) {
      throw FormatException(
        'Asset library $field contains leading or trailing whitespace.',
      );
    }
    if (raw != null && _hasAssetLibraryControlCharacter(raw)) {
      throw FormatException(
        'Asset library $field contains control characters.',
      );
    }
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('Asset library $field must be a timestamp.');
    }
    return parsed;
  }

  static List<String> _jsonTags(Object? value) {
    if (value == null) return const [];
    if (value is! List ||
        value.length > 50 ||
        value.any(
          (tag) =>
              tag is! String ||
              tag.length > 80 ||
              tag != tag.trim() ||
              _hasAssetLibraryControlCharacter(tag),
        )) {
      throw const FormatException('Asset library tags are invalid.');
    }
    return value.cast<String>();
  }

  static Map<String, dynamic> _jsonMetadata(Object? value) {
    if (value == null) return const {};
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Asset library metadata must be an object.');
    }
    return Map<String, dynamic>.from(value);
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

  static void _validateEnumName<T extends Enum>(
    Object? raw,
    List<T> values,
    String field,
  ) {
    if (raw == null) return;
    final name = raw.toString();
    if (!values.any((value) => value.name == name)) {
      throw FormatException('Asset library $field is invalid.');
    }
  }

  static String? _trimToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static bool _isDataUri(String? value) =>
      value?.trim().toLowerCase().startsWith('data:') == true;

  static bool _isPersistablePreviewUrl(String? value) =>
      value?.trim().toLowerCase().startsWith('https://') == true;

  static Map<String, dynamic> _durableMetadata(Map<String, dynamic> values) {
    final result = <String, dynamic>{};
    for (final entry in values.entries) {
      if (result.length >= 100 || entry.key.startsWith('_assetLibrary')) {
        continue;
      }
      final value = _durableMetadataValue(entry.value, depth: 0);
      if (value != null) result[entry.key] = value;
    }
    return result;
  }

  static dynamic _durableMetadataValue(dynamic value, {required int depth}) {
    if (depth > 5) return null;
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : null;
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty ||
          normalized.length > 4096 ||
          _hasAssetLibraryControlCharacter(normalized)) {
        return null;
      }
      final ownedReference =
          validImageArtifactReference(normalized) ??
          validVideoArtifactReference(normalized) ??
          validModel3DArtifactReference(normalized) ??
          validFileArtifactReference(normalized) ??
          validMediaArtifactReference(normalized);
      if (ownedReference != null) return ownedReference;
      if (durableAssetReference(normalized) != null) {
        return normalized;
      }
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
      for (final entry in value) {
        if (result.length >= 100) break;
        final child = _durableMetadataValue(entry, depth: depth + 1);
        if (child != null) result.add(child);
      }
      return List<dynamic>.unmodifiable(result);
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        if (result.length >= 100 ||
            entry.key is! String ||
            _hasAssetLibraryControlCharacter(entry.key as String)) {
          continue;
        }
        final child = _durableMetadataValue(entry.value, depth: depth + 1);
        if (child != null) result[entry.key as String] = child;
      }
      return Map<String, dynamic>.unmodifiable(result);
    }
    return null;
  }

  static Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> values) {
    final result = <String, dynamic>{};
    for (final entry in values.entries) {
      if (result.length >= 100) break;
      if (entry.key.length > 120 ||
          _hasAssetLibraryControlCharacter(entry.key)) {
        continue;
      }
      final sanitized = _sanitizeMetadataValue(entry.value, depth: 0);
      if (sanitized != null) result[entry.key] = sanitized;
    }
    return result;
  }

  static dynamic _sanitizeMetadataValue(dynamic value, {required int depth}) {
    if (depth > 5) return null;
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : null;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      final isOwnedArtifactReference =
          validImageArtifactReference(value) != null ||
          validVideoArtifactReference(value) != null ||
          validModel3DArtifactReference(value) != null ||
          validFileArtifactReference(value) != null ||
          validMediaArtifactReference(value) != null;
      if ((!isOwnedArtifactReference && _isDataUri(value)) ||
          value.length > 4096 ||
          _hasAssetLibraryControlCharacter(value) ||
          normalized.startsWith('file:') ||
          (!isOwnedArtifactReference &&
              RegExp(r'^[a-z][a-z0-9+.-]*://').hasMatch(normalized) &&
              (Uri.tryParse(value)?.scheme.toLowerCase() != 'https' ||
                  Uri.tryParse(value)?.userInfo.isNotEmpty == true ||
                  value.length > 2048)) ||
          normalized.startsWith('blob:') ||
          normalized.startsWith('content:') ||
          normalized.startsWith('/') ||
          normalized.startsWith('\\\\') ||
          RegExp(r'^[a-z]:[\\/]').hasMatch(normalized)) {
        return null;
      }
      return value;
    }
    if (value is List) {
      final sanitized = <dynamic>[];
      for (final entry in value) {
        if (sanitized.length >= 100) break;
        final child = _sanitizeMetadataValue(entry, depth: depth + 1);
        if (child != null) sanitized.add(child);
      }
      return List<dynamic>.unmodifiable(sanitized);
    }
    if (value is Map) {
      final sanitized = <String, dynamic>{};
      for (final entry in value.entries) {
        if (entry.key is! String ||
            (entry.key as String).length > 120 ||
            _hasAssetLibraryControlCharacter(entry.key as String) ||
            sanitized.length >= 100) {
          continue;
        }
        final child = _sanitizeMetadataValue(entry.value, depth: depth + 1);
        if (child != null) sanitized[entry.key as String] = child;
      }
      return Map<String, dynamic>.unmodifiable(sanitized);
    }
    return null;
  }

  static List<String> _normalizeTags(Iterable<String> values) {
    final tags = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value.trim();
      final key = normalized.toLowerCase();
      if (key.isEmpty ||
          _hasAssetLibraryControlCharacter(value) ||
          normalized.length > 80 ||
          _hasAssetLibraryControlCharacter(normalized) ||
          !seen.add(key)) {
        continue;
      }
      tags.add(normalized);
      if (tags.length == 50) break;
    }
    return List.unmodifiable(tags);
  }

  static void _validateStoragePath(String? raw) {
    if (raw == null) return;
    if (raw.isNotEmpty && raw != raw.trim()) {
      throw ArgumentError.value(
        raw,
        'storagePath',
        'Storage paths cannot contain leading or trailing whitespace.',
      );
    }
    if (raw.length > 512 ||
        raw.startsWith('/') ||
        raw.contains('\\') ||
        raw
            .split('/')
            .any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            ) ||
        _hasAssetLibraryControlCharacter(raw)) {
      throw ArgumentError.value(
        raw,
        'storagePath',
        'Storage paths must be relative, normalized, and traversal-safe.',
      );
    }
  }

  static void _validateTextLength(
    String? raw,
    String field,
    int maxLength, {
    bool allowLineBreaks = false,
  }) {
    if (raw == null || raw.length > maxLength) {
      if (raw == null) return;
      throw ArgumentError.value(
        raw,
        field,
        '$field cannot exceed $maxLength characters.',
      );
    }
    final hasUnsupportedControlCharacter = raw.codeUnits.any((code) {
      if (code >= 0x20 && code != 0x7f) return false;
      if (!allowLineBreaks) return true;
      return code != 0x09 && code != 0x0a && code != 0x0d;
    });
    if (hasUnsupportedControlCharacter) {
      throw ArgumentError.value(
        raw,
        field,
        '$field contains unsupported control characters.',
      );
    }
  }

  static void _validateChecksum(String? raw) {
    if (raw != null && raw.isNotEmpty && raw != raw.trim()) {
      throw ArgumentError.value(
        raw,
        'checksum',
        'Checksums cannot contain leading or trailing whitespace.',
      );
    }
    if (raw != null && _hasAssetLibraryControlCharacter(raw)) {
      throw ArgumentError.value(
        raw,
        'checksum',
        'Checksums cannot contain control characters.',
      );
    }
    final value = raw?.trim();
    if (value == null || value.isEmpty) return;
    if (!RegExp(r'^(?:sha256:)?[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw ArgumentError.value(
        raw,
        'checksum',
        'Checksums must be SHA-256 hex values.',
      );
    }
  }

  static void _validateUrl(String? raw, String field) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return;
    if (raw != null && _hasAssetLibraryControlCharacter(raw)) {
      throw ArgumentError.value(
        raw,
        field,
        'URL references cannot contain control characters.',
      );
    }
    final uri = Uri.tryParse(value);
    final scheme = uri?.scheme.toLowerCase();
    final allowedSchemes = field == 'previewUrl'
        ? const {'https', 'data', 'file'}
        : const {'https'};
    final needsHost = scheme == 'http' || scheme == 'https';
    final maxLength = scheme == 'data'
        ? 1024 * 1024
        : scheme == 'file'
        ? 4096
        : 2048;
    if (uri == null ||
        value.length > maxLength ||
        !allowedSchemes.contains(scheme) ||
        (needsHost && uri.host.isEmpty) ||
        uri.userInfo.isNotEmpty ||
        (scheme == 'https' &&
            raw != null &&
            raw.codeUnits.any((code) => code <= 0x20 || code == 0x7f))) {
      throw ArgumentError.value(
        raw,
        field,
        field == 'previewUrl'
            ? 'Only HTTPS, data, or file preview references are supported.'
            : 'Only HTTPS references are supported.',
      );
    }
  }

  static const Object _sentinel = Object();
}

class AssetLibraryQuery {
  final String scopeId;
  final AssetLibraryItemKind? kind;
  final String query;
  final String? folderId;
  final List<String> tags;
  final bool favoritesOnly;
  final AssetLibrarySort sort;
  final int pageSize;
  final String? cursor;
  final bool includeRemote;

  const AssetLibraryQuery({
    required this.scopeId,
    this.kind,
    this.query = '',
    this.folderId,
    this.tags = const [],
    this.favoritesOnly = false,
    this.sort = AssetLibrarySort.recent,
    this.pageSize = 24,
    this.cursor,
    this.includeRemote = false,
  }) : assert(pageSize > 0 && pageSize <= 100);
}

class AssetLibraryPage {
  final List<AssetLibraryItem> items;
  final String? nextCursor;
  final bool fromCache;
  final bool isOffline;

  const AssetLibraryPage({
    this.items = const [],
    this.nextCursor,
    this.fromCache = false,
    this.isOffline = false,
  });

  bool get hasMore => nextCursor?.isNotEmpty == true;
}

class AssetLibraryProviderCache {
  final List<AssetLibraryItem> items;
  final String? nextCursor;
  final DateTime fetchedAt;

  const AssetLibraryProviderCache({
    required this.items,
    required this.fetchedAt,
    this.nextCursor,
  });

  bool isUsable({DateTime? now, Duration maxAge = const Duration(days: 7)}) {
    final age = (now ?? DateTime.now().toUtc()).difference(fetchedAt);
    final cursorIsSafe =
        nextCursor == null ||
        (nextCursor!.trim().isNotEmpty &&
            nextCursor == nextCursor!.trim() &&
            nextCursor!.length <= 120 &&
            !_hasAssetLibraryControlCharacter(nextCursor!));
    return age >= Duration.zero && age <= maxAge && cursorIsSafe;
  }

  Map<String, dynamic> toJson() => {
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'nextCursor': nextCursor,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory AssetLibraryProviderCache.fromJson(Map<String, dynamic> json) {
    final rawFetchedAt = json['fetchedAt'];
    final rawItems = json['items'];
    if (rawFetchedAt is! String ||
        _hasAssetLibraryControlCharacter(rawFetchedAt) ||
        rawItems is! List ||
        rawItems.any((value) => value is! Map)) {
      throw const FormatException('Asset provider cache is invalid.');
    }
    final fetchedAt = DateTime.tryParse(rawFetchedAt);
    if (fetchedAt == null) {
      throw const FormatException('Asset provider cache timestamp is invalid.');
    }
    final rawCursor = json['nextCursor'];
    if (rawCursor != null && rawCursor is! String) {
      throw const FormatException('Asset provider cache cursor is invalid.');
    }
    final cursor = rawCursor as String?;
    if (cursor != null &&
        (cursor.trim().isEmpty ||
            cursor != cursor.trim() ||
            cursor.length > 120 ||
            _hasAssetLibraryControlCharacter(cursor))) {
      throw const FormatException('Asset provider cache cursor is invalid.');
    }
    return AssetLibraryProviderCache(
      items: [
        for (final value in rawItems.take(100))
          AssetLibraryItem.fromJson(Map<String, dynamic>.from(value as Map)),
      ],
      nextCursor: cursor,
      fetchedAt: fetchedAt.toUtc(),
    );
  }
}

List<AssetLibraryItem> filterAssetLibraryItems(
  Iterable<AssetLibraryItem> source,
  AssetLibraryQuery query,
) {
  final normalizedQuery = query.query.trim().toLowerCase();
  final requiredTags = query.tags
      .map((tag) => tag.trim().toLowerCase())
      .where((tag) => tag.isNotEmpty)
      .toSet();
  final filtered = source.where((item) {
    if (item.scopeId != query.scopeId) return false;
    if (query.kind != null && item.kind != query.kind) return false;
    if (query.folderId != null && item.folderId != query.folderId) return false;
    if (query.favoritesOnly && !item.favorite) return false;
    if (!requiredTags.every(
      (tag) => item.tags.any((candidate) => candidate.toLowerCase() == tag),
    )) {
      return false;
    }
    if (normalizedQuery.isEmpty) return true;
    return [
      item.id,
      item.name,
      item.description ?? '',
      item.creator ?? '',
      item.license ?? '',
      ...item.tags,
    ].join(' ').toLowerCase().contains(normalizedQuery);
  }).toList();

  filtered.sort((left, right) {
    switch (query.sort) {
      case AssetLibrarySort.name:
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      case AssetLibrarySort.mostUsed:
        final usage = right.usageCount.compareTo(left.usageCount);
        return usage == 0 ? right.updatedAt.compareTo(left.updatedAt) : usage;
      case AssetLibrarySort.recent:
        return right.updatedAt.compareTo(left.updatedAt);
    }
  });
  return filtered;
}
