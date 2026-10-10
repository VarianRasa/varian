import 'dart:convert';
import 'dart:typed_data';

import '../../link_card/domain/link_url_policy.dart';

const _maxCaptureBytes = 50 * 1024 * 1024;
const _maxCaptureTextBytes = 256 * 1024;

enum CaptureKind { text, image, file, link, screenshot, audio }

enum CaptureStatus { ready, enriching, syncPending, synced, error, deleted }

enum CaptureSyncState { localOnly, pending, synced, error }

enum CaptureOrigin { inApp, clipboard, drop, share, hotkey, pwaShareTarget }

class CaptureFailure implements Exception {
  final String code;
  final String message;

  const CaptureFailure(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

class CaptureLinkMetadata {
  final String? title;
  final String? description;
  final String? siteName;
  final String? imageRef;
  final String? mediaType;

  CaptureLinkMetadata({
    String? title,
    String? description,
    String? siteName,
    String? imageRef,
    String? mediaType,
  }) : title = _validateBoundedText(title),
       description = _validateBoundedText(description),
       siteName = _validateBoundedText(siteName),
       imageRef = _validateBoundedText(imageRef),
       mediaType = _validateBoundedText(mediaType);

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'siteName': siteName,
    'imageRef': imageRef,
    'mediaType': mediaType,
  };

  factory CaptureLinkMetadata.fromJson(Map<String, dynamic> json) {
    try {
      return CaptureLinkMetadata(
        title: _storedOptionalString(json['title']),
        description: _storedOptionalString(json['description']),
        siteName: _storedOptionalString(json['siteName']),
        imageRef: _storedOptionalString(json['imageRef']),
        mediaType: _storedOptionalString(json['mediaType']),
      );
    } on CaptureFailure {
      rethrow;
    } catch (_) {
      throw const CaptureFailure(
        'CAPTURE_STORAGE_ERROR',
        'Stored capture metadata is invalid.',
      );
    }
  }
}

class CaptureItem {
  final String id;
  final CaptureKind kind;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? title;
  final String? text;
  final String? sourceUri;
  final String? assetId;
  final String? mimeType;
  final String? extension;
  final int? byteSize;
  final String? thumbnailRef;
  final String? extractedText;
  final CaptureLinkMetadata? linkMetadata;
  final CaptureStatus status;
  final CaptureSyncState syncState;
  final CaptureOrigin origin;
  final bool isRead;
  final bool isFavorite;
  final String? syncErrorCode;

  CaptureItem({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    String? title,
    String? text,
    String? sourceUri,
    this.assetId,
    this.mimeType,
    this.extension,
    int? byteSize,
    this.thumbnailRef,
    String? extractedText,
    this.linkMetadata,
    this.status = CaptureStatus.ready,
    this.syncState = CaptureSyncState.localOnly,
    this.origin = CaptureOrigin.inApp,
    this.isRead = false,
    this.isFavorite = false,
    this.syncErrorCode,
  }) : title = _validateBoundedText(title),
       text = _validateBoundedText(text),
       sourceUri = _normalizeSourceUri(sourceUri),
       byteSize = _validateByteSize(byteSize),
       extractedText = _validateBoundedText(extractedText);

  CaptureItem copyWith({
    String? id,
    CaptureKind? kind,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? title,
    String? text,
    String? sourceUri,
    String? assetId,
    String? mimeType,
    String? extension,
    int? byteSize,
    String? thumbnailRef,
    String? extractedText,
    CaptureLinkMetadata? linkMetadata,
    CaptureStatus? status,
    CaptureSyncState? syncState,
    CaptureOrigin? origin,
    bool? isRead,
    bool? isFavorite,
    String? syncErrorCode,
    bool clearTitle = false,
    bool clearText = false,
    bool clearSourceUri = false,
    bool clearAssetId = false,
    bool clearMimeType = false,
    bool clearExtension = false,
    bool clearByteSize = false,
    bool clearThumbnailRef = false,
    bool clearExtractedText = false,
    bool clearLinkMetadata = false,
    bool clearSyncErrorCode = false,
  }) {
    return CaptureItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      title: clearTitle ? null : title ?? this.title,
      text: clearText ? null : text ?? this.text,
      sourceUri: clearSourceUri ? null : sourceUri ?? this.sourceUri,
      assetId: clearAssetId ? null : assetId ?? this.assetId,
      mimeType: clearMimeType ? null : mimeType ?? this.mimeType,
      extension: clearExtension ? null : extension ?? this.extension,
      byteSize: clearByteSize ? null : byteSize ?? this.byteSize,
      thumbnailRef: clearThumbnailRef
          ? null
          : thumbnailRef ?? this.thumbnailRef,
      extractedText: clearExtractedText
          ? null
          : extractedText ?? this.extractedText,
      linkMetadata: clearLinkMetadata
          ? null
          : linkMetadata ?? this.linkMetadata,
      status: status ?? this.status,
      syncState: syncState ?? this.syncState,
      origin: origin ?? this.origin,
      isRead: isRead ?? this.isRead,
      isFavorite: isFavorite ?? this.isFavorite,
      syncErrorCode: clearSyncErrorCode
          ? null
          : syncErrorCode ?? this.syncErrorCode,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'title': title,
    'text': text,
    'sourceUri': sourceUri,
    'assetId': assetId,
    'mimeType': mimeType,
    'extension': extension,
    'byteSize': byteSize,
    'thumbnailRef': thumbnailRef,
    'extractedText': extractedText,
    'linkMetadata': linkMetadata?.toJson(),
    'status': status.name,
    'syncState': syncState.name,
    'origin': origin.name,
    'isRead': isRead,
    'isFavorite': isFavorite,
    'syncErrorCode': syncErrorCode,
  };

  factory CaptureItem.fromJson(Map<String, dynamic> json) {
    try {
      return CaptureItem(
        id: _storedRequiredString(json['id']),
        kind: _storedEnumValue(
          CaptureKind.values,
          _storedRequiredString(json['kind']),
          CaptureKind.text,
        ),
        createdAt: _storedDate(json['createdAt']),
        updatedAt: _storedDate(json['updatedAt']),
        title: _storedOptionalString(json['title']),
        text: _storedOptionalString(json['text']),
        sourceUri: _storedOptionalString(json['sourceUri']),
        assetId: _storedOptionalString(json['assetId']),
        mimeType: _storedOptionalString(json['mimeType']),
        extension: _storedOptionalString(json['extension']),
        byteSize: _storedByteSize(json['byteSize']),
        thumbnailRef: _storedOptionalString(json['thumbnailRef']),
        extractedText: _storedOptionalString(json['extractedText']),
        linkMetadata: _storedLinkMetadata(json['linkMetadata']),
        status: _storedEnumValue(
          CaptureStatus.values,
          _storedOptionalEnumName(json['status']),
          CaptureStatus.ready,
        ),
        syncState: _storedEnumValue(
          CaptureSyncState.values,
          _storedOptionalEnumName(json['syncState']),
          CaptureSyncState.localOnly,
        ),
        origin: _storedEnumValue(
          CaptureOrigin.values,
          _storedOptionalEnumName(json['origin']),
          CaptureOrigin.inApp,
        ),
        isRead: _storedOptionalBool(json['isRead']) ?? false,
        isFavorite: _storedOptionalBool(json['isFavorite']) ?? false,
        syncErrorCode: _storedOptionalString(json['syncErrorCode']),
      );
    } on CaptureFailure {
      rethrow;
    } catch (_) {
      throw const CaptureFailure(
        'CAPTURE_STORAGE_ERROR',
        'Stored capture data is invalid.',
      );
    }
  }
}

class CaptureInput {
  final CaptureKind kind;
  final CaptureOrigin origin;
  final String? title;
  final String? text;
  final String? sourceUri;
  final String? name;
  final String? path;
  final Uint8List? bytes;
  final String? mimeType;
  final String? extension;
  final int? byteSize;

  const CaptureInput._({
    required this.kind,
    required this.origin,
    this.title,
    this.text,
    this.sourceUri,
    this.name,
    this.path,
    this.bytes,
    this.mimeType,
    this.extension,
    this.byteSize,
  });

  factory CaptureInput.text(
    String value, {
    CaptureOrigin origin = CaptureOrigin.inApp,
    String? title,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const CaptureFailure('CAPTURE_EMPTY', 'Capture text is empty.');
    }
    _validateBoundedText(trimmed);
    final normalizedTitle = _normalizeOptionalText(title);

    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      final normalized = _normalizeSourceUri(trimmed)!;
      return CaptureInput._(
        kind: CaptureKind.link,
        origin: origin,
        title: normalizedTitle,
        text: normalized,
        sourceUri: normalized,
      );
    }

    return CaptureInput._(
      kind: CaptureKind.text,
      origin: origin,
      title: normalizedTitle,
      text: trimmed,
    );
  }

  factory CaptureInput.file({
    required String name,
    String? path,
    required Uint8List bytes,
    required String mimeType,
    String? title,
    CaptureOrigin origin = CaptureOrigin.inApp,
  }) {
    final trimmedName = name.trim();
    final normalizedMimeType = mimeType.trim();
    if (trimmedName.isEmpty || bytes.isEmpty || normalizedMimeType.isEmpty) {
      throw const CaptureFailure('CAPTURE_EMPTY', 'Capture file is empty.');
    }
    if (bytes.length > _maxCaptureBytes) {
      throw const CaptureFailure(
        'CAPTURE_SIZE_LIMIT',
        'Capture file exceeds the size limit.',
      );
    }
    _validateBoundedText(normalizedMimeType);

    final copiedBytes = Uint8List.fromList(bytes);
    final lowerMimeType = normalizedMimeType.toLowerCase();
    final kind = lowerMimeType.startsWith('image/')
        ? CaptureKind.image
        : lowerMimeType.startsWith('audio/')
        ? CaptureKind.audio
        : CaptureKind.file;

    return CaptureInput._(
      kind: kind,
      origin: origin,
      title: _normalizeOptionalText(title),
      name: trimmedName,
      path: path,
      bytes: copiedBytes,
      mimeType: normalizedMimeType,
      extension: _extensionFor(trimmedName),
      byteSize: copiedBytes.length,
    );
  }

  String? get fileName => name;
}

String? _normalizeSourceUri(String? value) {
  if (value == null) return null;
  _validateBoundedText(value);
  final trimmed = value.trim();
  try {
    final normalized = normalizeLinkUrl(trimmed).toString();
    return _validateBoundedText(normalized);
  } on LinkUrlValidationException {
    throw const CaptureFailure(
      'CAPTURE_INVALID_URL',
      'Capture URL is invalid.',
    );
  }
}

String? _normalizeOptionalText(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return _validateBoundedText(trimmed);
}

String? _validateBoundedText(String? value) {
  if (value != null && utf8.encode(value).length > _maxCaptureTextBytes) {
    throw const CaptureFailure(
      'CAPTURE_SIZE_LIMIT',
      'Capture text exceeds the size limit.',
    );
  }
  return value;
}

int? _validateByteSize(int? value) {
  if (value != null && (value < 0 || value > _maxCaptureBytes)) {
    throw const CaptureFailure(
      'CAPTURE_STORAGE_ERROR',
      'Stored capture size is invalid.',
    );
  }
  return value;
}

String? _extensionFor(String name) {
  final lastSeparator = name.lastIndexOf(RegExp(r'[\\/]'));
  final lastDot = name.lastIndexOf('.');
  if (lastDot <= lastSeparator || lastDot == name.length - 1) return null;
  return name.substring(lastDot + 1).toLowerCase();
}

String _storedRequiredString(Object? value) {
  if (value is String) return value;
  throw const CaptureFailure(
    'CAPTURE_STORAGE_ERROR',
    'Stored capture data is invalid.',
  );
}

String? _storedOptionalString(Object? value) {
  if (value == null || value is String) return value as String?;
  throw const CaptureFailure(
    'CAPTURE_STORAGE_ERROR',
    'Stored capture data is invalid.',
  );
}

DateTime _storedDate(Object? value) {
  final raw = _storedRequiredString(value);
  try {
    return DateTime.parse(raw);
  } on FormatException {
    throw const CaptureFailure(
      'CAPTURE_STORAGE_ERROR',
      'Stored capture date is invalid.',
    );
  }
}

int? _storedByteSize(Object? value) {
  if (value == null) return null;
  if (value is! int) {
    throw const CaptureFailure(
      'CAPTURE_STORAGE_ERROR',
      'Stored capture size is invalid.',
    );
  }
  return _validateByteSize(value);
}

CaptureLinkMetadata? _storedLinkMetadata(Object? value) {
  if (value == null) return null;
  if (value is! Map) {
    throw const CaptureFailure(
      'CAPTURE_STORAGE_ERROR',
      'Stored capture metadata is invalid.',
    );
  }
  return CaptureLinkMetadata.fromJson(Map<String, dynamic>.from(value));
}

String? _storedOptionalEnumName(Object? value) {
  if (value == null || value is String) return value as String?;
  throw const CaptureFailure(
    'CAPTURE_STORAGE_ERROR',
    'Stored capture state is invalid.',
  );
}

bool? _storedOptionalBool(Object? value) {
  if (value == null || value is bool) return value as bool?;
  throw const CaptureFailure(
    'CAPTURE_STORAGE_ERROR',
    'Stored capture flag is invalid.',
  );
}

T _storedEnumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw == null) return fallback;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw const CaptureFailure(
    'CAPTURE_STORAGE_ERROR',
    'Stored capture state is invalid.',
  );
}
