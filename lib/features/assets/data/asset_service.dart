import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../../data/remote/supabase_service.dart';

Future<Uint8List?> readPlatformFileBytes(
  PlatformFile file, {
  required int maxBytes,
}) async {
  if (maxBytes <= 0) return null;
  final declaredLength = await file.length();
  if (declaredLength <= 0 || declaredLength > maxBytes) return null;

  final builder = BytesBuilder(copy: false);
  var total = 0;
  try {
    await for (final chunk in file.readAsByteStream()) {
      if (chunk.isEmpty) continue;
      total += chunk.length;
      if (total > maxBytes) return null;
      builder.add(chunk);
    }
  } catch (_) {
    return null;
  }
  if (total == 0) return null;
  return builder.takeBytes();
}

class AssetPickerResult {
  final String name;
  final String? path;
  final String? remoteUrl;
  final String? storagePath;

  /// Allows the library service to clean up only paths created by this picker.
  final bool storagePathOwned;
  final Uint8List? bytes;
  final int? size;
  final String? extension;
  final String? errorMessage;

  AssetPickerResult({
    required this.name,
    this.path,
    this.remoteUrl,
    this.storagePath,
    this.storagePathOwned = false,
    this.bytes,
    this.size,
    this.extension,
    this.errorMessage,
  }) {
    if (size != null && size! < 0) {
      throw ArgumentError.value(size, 'size', 'File size cannot be negative.');
    }
  }

  String get formattedSize {
    final bytesCount = size ?? bytes?.lengthInBytes ?? 0;
    if (bytesCount <= 0) return '0 B';
    if (bytesCount < 1024) return '$bytesCount B';
    if (bytesCount < 1024 * 1024) {
      return '${(bytesCount / 1024).toStringAsFixed(1)} KB';
    }
    if (bytesCount < 1024 * 1024 * 1024) {
      return '${(bytesCount / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytesCount / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get fileExt {
    if (extension != null && extension!.isNotEmpty) {
      return extension!.toUpperCase();
    }
    if (name.contains('.')) {
      return name.split('.').last.toUpperCase();
    }
    return 'FILE';
  }

  String get detectedMimeType {
    final mimeName = extension?.trim().isNotEmpty == true && !name.contains('.')
        ? '$name.$extension'
        : name;
    return inferAssetMimeType(mimeName);
  }

  /// Returns only stable metadata that can cross a durable boundary.
  ///
  /// Picker paths, provider URLs, and preview data URLs are runtime values.
  /// Callers that need a durable local copy must materialize [bytes] through
  /// the appropriate owned artifact store first.
  String? get durableReference {
    final storage = storagePath?.trim();
    if (storage != null &&
        storage.isNotEmpty &&
        storage == storagePath &&
        !storage.contains('?') &&
        !storage.contains('#') &&
        !storage.contains('\\')) {
      return storagePath;
    }
    return null;
  }

  String? get previewUrl {
    if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      return remoteUrl;
    }
    if (path != null && path!.isNotEmpty) return path;
    if (bytes != null && bytes!.isNotEmpty) {
      final base64Str = base64Encode(bytes!);
      final mimeType = detectedMimeType;
      return 'data:$mimeType;base64,$base64Str';
    }
    return path;
  }
}

const _assetMimeTypes = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'zip': 'application/zip',
  'rar': 'application/vnd.rar',
  '7z': 'application/x-7z-compressed',
  'tar': 'application/x-tar',
  'gz': 'application/gzip',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'xml': 'application/xml',
  'html': 'text/html',
  'htm': 'text/html',
  'png': 'image/png',
  'svg': 'image/svg+xml',
  'bmp': 'image/bmp',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'mp4': 'video/mp4',
  'webm': 'video/webm',
  'avi': 'video/x-msvideo',
  'mkv': 'video/x-matroska',
  'mov': 'video/quicktime',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'ogg': 'audio/ogg',
  'flac': 'audio/flac',
  'glb': 'model/gltf-binary',
  'gltf': 'model/gltf+json',
};

String inferAssetMimeType(
  String fileName, {
  String fallback = 'application/octet-stream',
}) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return fallback;
  return _assetMimeTypes[fileName.substring(dot + 1).toLowerCase()] ?? fallback;
}

/// Performs a cheap client-side signature check before bytes are uploaded.
/// Storage and server-side metadata validation remain authoritative.
bool assetBytesMatchMimeSignature(List<int> bytes, String mimeType) {
  final normalizedMimeType = mimeType.trim().toLowerCase();
  if (bytes.isEmpty || normalizedMimeType == 'application/octet-stream') {
    return true;
  }
  bool startsWith(List<int> prefix, {int offset = 0}) {
    if (bytes.length < offset + prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[offset + index] != prefix[index]) return false;
    }
    return true;
  }

  bool containsAscii(String value) {
    final needle = value.codeUnits;
    final limit = bytes.length - needle.length;
    for (var start = 0; start <= limit && start < 1024; start++) {
      var matches = true;
      for (var index = 0; index < needle.length; index++) {
        final actual = bytes[start + index];
        final expected = needle[index];
        final lowerActual = actual >= 65 && actual <= 90 ? actual + 32 : actual;
        final lowerExpected = expected >= 65 && expected <= 90
            ? expected + 32
            : expected;
        if (lowerActual != lowerExpected) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  return switch (normalizedMimeType) {
    'image/png' => startsWith([137, 80, 78, 71, 13, 10, 26, 10]),
    'image/jpeg' => startsWith([255, 216, 255]),
    'image/gif' => startsWith('GIF'.codeUnits),
    'image/webp' =>
      startsWith('RIFF'.codeUnits) && startsWith('WEBP'.codeUnits, offset: 8),
    'image/bmp' => startsWith('BM'.codeUnits),
    'image/svg+xml' => containsAscii('<svg'),
    'application/pdf' => startsWith('%PDF-'.codeUnits),
    'application/zip' ||
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
    'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
      startsWith([80, 75, 3, 4]) || startsWith([80, 75, 5, 6]),
    'application/msword' ||
    'application/vnd.ms-excel' ||
    'application/vnd.ms-powerpoint' => startsWith([
      208,
      207,
      17,
      224,
      161,
      177,
      26,
      225,
    ]),
    'application/vnd.rar' =>
      startsWith([82, 97, 114, 33, 26, 7, 0]) ||
          startsWith([82, 97, 114, 33, 26, 7, 1, 0]),
    'application/x-7z-compressed' => startsWith([55, 122, 188, 175, 39, 28]),
    'application/gzip' => startsWith([31, 139]),
    'application/x-tar' => startsWith('ustar'.codeUnits, offset: 257),
    'application/json' ||
    'model/gltf+json' => containsAscii('{') || containsAscii('['),
    'application/xml' => containsAscii('<'),
    'model/gltf-binary' => startsWith('glTF'.codeUnits),
    'video/mp4' ||
    'video/quicktime' ||
    'audio/mp4' => startsWith('ftyp'.codeUnits, offset: 4),
    'video/x-msvideo' =>
      startsWith('RIFF'.codeUnits) && startsWith('AVI '.codeUnits, offset: 8),
    'video/x-matroska' || 'video/webm' => startsWith([26, 69, 223, 163]),
    'audio/wav' =>
      startsWith('RIFF'.codeUnits) && startsWith('WAVE'.codeUnits, offset: 8),
    'audio/mpeg' =>
      startsWith('ID3'.codeUnits) ||
          (bytes.length >= 2 && bytes[0] == 255 && (bytes[1] & 224) == 224),
    'audio/aac' =>
      bytes.length >= 2 && bytes[0] == 255 && (bytes[1] & 246) == 240,
    'audio/flac' => startsWith('fLaC'.codeUnits),
    'audio/ogg' => startsWith('OggS'.codeUnits),
    _ => true,
  };
}

String safeAssetStorageSegment(String value, {String fallback = 'asset'}) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'^\.+|\.+$'), '');
  if (normalized.isEmpty) return fallback;
  final end = normalized.length > 120 ? 120 : normalized.length;
  return normalized.substring(0, end);
}

class AssetService {
  static const _uuid = Uuid();
  static const _managedStorageFolders = {
    'images',
    'files',
    'audio',
    'video',
    'library',
  };

  final SupabaseSyncService? syncService;

  AssetService([this.syncService]);

  Future<Uint8List?> _extractBytes(
    PlatformFile file, {
    int maxBytes = 512 * 1024 * 1024,
  }) async {
    final bytes = await readPlatformFileBytes(file, maxBytes: maxBytes);
    if (bytes == null) {
      debugPrint('[AssetService] Failed to read picked file bytes.');
    }
    return bytes;
  }

  String? _extension(PlatformFile file) {
    final dot = file.name.lastIndexOf('.');
    if (dot < 0 || dot == file.name.length - 1) return null;
    return file.name.substring(dot + 1).toLowerCase();
  }

  Future<List<PlatformFile>?> _pickFiles({
    required FileType type,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    if (allowMultiple) {
      // file_picker v12 exposes multi-selection through pickFiles; its
      // platform interface no longer accepts an allowMultiple argument.
      return FilePicker.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
      );
    }
    final file = await FilePicker.pickFile(
      type: type,
      allowedExtensions: allowedExtensions,
    );
    return file == null ? null : [file];
  }

  Future<int?> _size(PlatformFile file) async {
    try {
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  String? _path(PlatformFile file) => file.path;

  // FilePicker v12 streams bytes on demand instead of exposing a bytes field.
  // Keep the result contract unchanged for callers.
  Future<AssetPickerResult> _result(
    PlatformFile file, {
    String? remoteUrl,
    String? storagePath,
    bool storagePathOwned = false,
    Uint8List? bytes,
    int? size,
    String? errorMessage,
    bool includePath = true,
  }) async => AssetPickerResult(
    name: file.name,
    path: includePath && !kIsWeb ? _path(file) : null,
    remoteUrl: remoteUrl,
    storagePath: storagePath,
    storagePathOwned: storagePathOwned,
    bytes: bytes,
    size: size ?? await _size(file),
    extension: _extension(file),
    errorMessage: errorMessage,
  );

  Future<AssetPickerResult?> _pickAsset({
    required FileType type,
    List<String>? allowedExtensions,
    required String folder,
    required String fallbackMimeType,
    String? projectId,
    String? storageFolder,
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = await _pickAssets(
      type: type,
      allowedExtensions: allowedExtensions,
      folder: folder,
      fallbackMimeType: fallbackMimeType,
      projectId: projectId,
      storageFolder: storageFolder,
      onProgress: onProgress,
    );
    if (results.isEmpty) return null;
    final result = results.first;
    if (result.errorMessage != null &&
        result.durableReference == null &&
        (result.bytes == null || result.bytes!.isEmpty)) {
      return null;
    }
    return result;
  }

  Future<List<AssetPickerResult>> _pickAssets({
    required FileType type,
    List<String>? allowedExtensions,
    required String folder,
    required String fallbackMimeType,
    String? projectId,
    String? storageFolder,
    bool allowMultiple = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    final normalizedStorageFolder = storageFolder?.trim().toLowerCase();
    if (normalizedStorageFolder != null &&
        (storageFolder != normalizedStorageFolder ||
            !_managedStorageFolders.contains(normalizedStorageFolder))) {
      throw ArgumentError.value(
        storageFolder,
        'storageFolder',
        'Asset uploads must use a managed Storage namespace.',
      );
    }
    final normalizedProjectId = projectId?.trim();
    if (normalizedProjectId != null &&
        (normalizedProjectId.isEmpty ||
            projectId != normalizedProjectId ||
            safeAssetStorageSegment(normalizedProjectId, fallback: '') !=
                normalizedProjectId)) {
      throw ArgumentError.value(
        projectId,
        'projectId',
        'Asset uploads require a path-safe project identifier.',
      );
    }
    final expectedUserId = syncService?.currentUserId;
    final files = await _pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    );
    if (files == null || files.isEmpty) return const [];

    var cloudUploadAuthorized = false;
    var cloudAuthorizationFailed = false;
    if (syncService?.isConfigured == true && normalizedProjectId != null) {
      if (expectedUserId != null && expectedUserId.isNotEmpty) {
        try {
          await syncService!.verifyProjectOwnership(
            normalizedProjectId,
            expectedUserId: expectedUserId,
          );
          cloudUploadAuthorized = true;
        } catch (_) {
          // Keep the picked bytes locally when cloud ownership is not verified.
          cloudAuthorizationFailed = true;
        }
      } else {
        cloudAuthorizationFailed = true;
      }
    }

    final results = <AssetPickerResult>[];
    if (cloudAuthorizationFailed) {
      debugPrint('[AssetService] Project ownership was not verified.');
    }
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final fileSize = await _size(file);
      if (fileSize != null && fileSize > 512 * 1024 * 1024) {
        results.add(
          await _result(
            file,
            size: fileSize,
            errorMessage: 'File exceeds the 512 MB upload limit.',
            includePath: false,
          ),
        );
        onProgress?.call(index + 1, files.length);
        continue;
      }
      final bytes = await readPlatformFileBytes(
        file,
        maxBytes: 512 * 1024 * 1024,
      );
      String? readError;
      if (bytes == null) {
        readError = fileSize == null || fileSize <= 0
            ? 'File could not be read.'
            : 'File is empty or exceeds the 512 MB upload limit.';
      }
      if (readError != null || bytes == null) {
        results.add(
          await _result(
            file,
            size: fileSize,
            errorMessage: readError ?? 'File is empty.',
            includePath: false,
          ),
        );
        onProgress?.call(index + 1, files.length);
        continue;
      }
      if (bytes.lengthInBytes > 512 * 1024 * 1024) {
        results.add(
          await _result(
            file,
            size: bytes.lengthInBytes,
            errorMessage: 'File exceeds the 512 MB upload limit.',
            includePath: false,
          ),
        );
        onProgress?.call(index + 1, files.length);
        continue;
      }
      final mimeType = inferAssetMimeType(
        file.name,
        fallback: fallbackMimeType,
      );
      if (!assetBytesMatchMimeSignature(bytes, mimeType)) {
        results.add(
          await _result(
            file,
            size: bytes.lengthInBytes,
            errorMessage: 'File contents do not match its MIME type.',
            includePath: false,
          ),
        );
        onProgress?.call(index + 1, files.length);
        continue;
      }
      String? storagePath;
      String? errorMessage = cloudAuthorizationFailed
          ? 'Cloud upload skipped because project ownership could not be verified.'
          : null;
      if (cloudUploadAuthorized &&
          syncService != null &&
          normalizedProjectId != null &&
          expectedUserId != null) {
        final candidatePath =
            '${safeAssetStorageSegment(normalizedProjectId, fallback: 'global')}/${normalizedStorageFolder ?? folder}/${_uuid.v4()}_${safeAssetStorageSegment(file.name)}';
        try {
          final uploadedPath = await syncService!.uploadAssetForProjectEditor(
            bucket: 'assets',
            path: candidatePath,
            bytes: bytes,
            contentType: mimeType,
            upsert: false,
            expectedUserId: expectedUserId,
          );
          if (uploadedPath?.trim() == candidatePath) {
            storagePath = uploadedPath;
          } else {
            errorMessage =
                'Cloud upload failed; kept an offline copy when possible.';
          }
        } catch (error) {
          debugPrint('[AssetService] Cloud upload failed: $error');
          errorMessage =
              'Cloud upload failed; kept an offline copy when possible.';
        }
      }
      results.add(
        await _result(
          file,
          remoteUrl: null,
          storagePath: storagePath,
          storagePathOwned: storagePath != null,
          bytes: bytes,
          errorMessage: errorMessage,
        ),
      );
      onProgress?.call(index + 1, files.length);
    }
    return results;
  }

  Future<AssetPickerResult?> pickImage({String? projectId}) => _pickAsset(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    folder: 'images',
    fallbackMimeType: 'image/png',
    projectId: projectId,
  );

  Future<List<AssetPickerResult>> pickImages({
    String? projectId,
    void Function(int completed, int total)? onProgress,
  }) => _pickAssets(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    folder: 'images',
    fallbackMimeType: 'image/png',
    projectId: projectId,
    allowMultiple: true,
    onProgress: onProgress,
  );

  Future<AssetPickerResult?> pickAnyFile({
    String? projectId,
    String storageFolder = 'files',
  }) => _pickAsset(
    type: FileType.any,
    folder: 'files',
    fallbackMimeType: 'application/octet-stream',
    projectId: projectId,
    storageFolder: storageFolder,
  );

  Future<List<AssetPickerResult>> pickAnyFiles({
    String? projectId,
    String storageFolder = 'library',
    void Function(int completed, int total)? onProgress,
  }) => _pickAssets(
    type: FileType.any,
    folder: 'files',
    fallbackMimeType: 'application/octet-stream',
    projectId: projectId,
    storageFolder: storageFolder,
    allowMultiple: true,
    onProgress: onProgress,
  );

  Future<AssetPickerResult?> pickGlb() async {
    final files = await _pickFiles(
      type: FileType.custom,
      allowedExtensions: ['glb'],
    );
    if (files == null || files.isEmpty) return null;
    final file = files.first;
    final size = await _size(file);
    if (size != null && size > 512 * 1024 * 1024) return null;
    final bytes = await _extractBytes(file, maxBytes: 512 * 1024 * 1024);
    if (bytes == null ||
        bytes.lengthInBytes > 512 * 1024 * 1024 ||
        !assetBytesMatchMimeSignature(bytes, 'model/gltf-binary')) {
      return null;
    }
    return _result(file, bytes: bytes, size: bytes.lengthInBytes);
  }

  Future<AssetPickerResult?> pickVideo({String? projectId}) => _pickAsset(
    type: FileType.custom,
    allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'webm'],
    folder: 'video',
    fallbackMimeType: 'video/mp4',
    projectId: projectId,
  );

  Future<AssetPickerResult?> pickAudio({String? projectId}) => _pickAsset(
    type: FileType.custom,
    allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
    folder: 'audio',
    fallbackMimeType: 'audio/mpeg',
    projectId: projectId,
  );
}
