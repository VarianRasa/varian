import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'external_url_policy.dart';
import 'supabase_service.dart';

/// A durable, bucket-relative reference to a private Storage object.
///
/// This type deliberately contains no signed URL. Signed URLs are runtime
/// credentials and must only exist inside the resolver while an asset is being
/// fetched or rendered.
class StorageAssetReference {
  final String bucket;
  final String path;

  const StorageAssetReference({required this.bucket, required this.path});

  factory StorageAssetReference.parse({
    required String bucket,
    required String path,
    required String projectId,
    Set<String> allowedBuckets = const {'assets'},
  }) {
    final normalizedBucket = bucket.trim();
    final normalizedPath = path.trim();
    if (normalizedBucket != bucket || normalizedPath != path) {
      throw const FormatException(
        'Storage references cannot contain surrounding whitespace.',
      );
    }
    if (!allowedBuckets.contains(normalizedBucket)) {
      throw FormatException(
        'Storage bucket is not allowed: $normalizedBucket.',
      );
    }
    if (normalizedPath.isEmpty || normalizedPath.length > 512) {
      throw const FormatException('Storage path length is invalid.');
    }
    if (normalizedPath.contains('?') ||
        normalizedPath.contains('#') ||
        normalizedPath.contains('\\') ||
        normalizedPath.startsWith('/') ||
        normalizedPath.endsWith('/')) {
      throw const FormatException(
        'Storage path must be relative and normalized.',
      );
    }
    if (_hasControlCharacter(normalizedPath)) {
      throw const FormatException('Storage path contains a control character.');
    }

    final segments = normalizedPath.split('/');
    if (segments.length < 2 ||
        segments.length > 32 ||
        segments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              segment.length > 120 ||
              !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(segment),
        )) {
      throw const FormatException('Storage path segments are invalid.');
    }

    final normalizedProjectId = projectId.trim();
    if (normalizedProjectId.isEmpty ||
        normalizedProjectId != projectId ||
        normalizedProjectId.contains('/') ||
        !_isSafeSegment(normalizedProjectId)) {
      throw const FormatException('Project scope is invalid.');
    }

    final scopedProjectId = segments.first == 'drawing-paper'
        ? (segments.length > 1 ? segments[1] : null)
        : segments.first;
    if (scopedProjectId != normalizedProjectId) {
      throw const FormatException(
        'Storage path is outside the active project.',
      );
    }

    return StorageAssetReference(
      bucket: normalizedBucket,
      path: normalizedPath,
    );
  }

  static StorageAssetReference? tryParse({
    required String bucket,
    required String path,
    required String projectId,
    Set<String> allowedBuckets = const {'assets'},
  }) {
    try {
      return StorageAssetReference.parse(
        bucket: bucket,
        path: path,
        projectId: projectId,
        allowedBuckets: allowedBuckets,
      );
    } on FormatException {
      return null;
    }
  }

  String get cacheKey => '$bucket:$path';

  static bool _isSafeSegment(String value) =>
      value.length <= 120 &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value);

  static bool _hasControlCharacter(String value) =>
      value.codeUnits.any((code) => code <= 0x1f || code == 0x7f);
}

/// Runtime-only result for a source that can be rendered or downloaded.
///
/// [uri] may contain a signed query string for a private Storage object. It is
/// intentionally not serializable and callers must not place it in a payload,
/// log, cache key, or remote row. Prefer [SupabaseStoragePathResolver.readBytes]
/// when a consumer can render from bytes.
class RuntimeAssetResolution {
  final String source;
  final String? uri;
  final Uint8List? bytes;
  final DateTime? expiresAt;
  final bool isPrivateStorage;

  const RuntimeAssetResolution({
    required this.source,
    this.uri,
    this.bytes,
    this.expiresAt,
    this.isPrivateStorage = false,
  });
}

typedef SignedAssetUrlLoader =
    Future<String?> Function({
      required String bucket,
      required String path,
      required int expiresIn,
      String? expectedUserId,
    });

/// Resolves durable private Storage paths into transient runtime delivery.
///
/// The resolver is deliberately independent from Riverpod so image caches,
/// media controllers, download actions, and model loaders can share the same
/// account/project fencing rules. Inject [signedUrlLoader] and [currentUserId]
/// in tests; production callers should pass [syncService].
class SupabaseStoragePathResolver {
  final SupabaseSyncService? syncService;
  final SignedAssetUrlLoader? signedUrlLoader;
  final String? Function()? currentUserId;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration signedUrlLifetime;
  final Duration expirySafetyWindow;
  final Set<String> allowedBuckets;

  final Map<String, _SignedUrlEntry> _signedUrlCache = {};
  final Map<String, Future<_SignedUrlEntry?>> _signedUrlRequests = {};
  int _generation = 0;
  bool _disposed = false;

  bool _isActiveGeneration(int generation) =>
      !_disposed && generation == _generation;

  String? get activeUserId => _effectiveUserId;

  StorageAssetReference? _parseStorageCandidate({
    required String projectId,
    required String? source,
    required String? storagePath,
    required String bucket,
  }) {
    for (final candidate in [storagePath, source]) {
      final value = candidate?.trim();
      if (value == null || value.isEmpty) continue;
      final parsed = parseReference(
        path: value,
        projectId: projectId,
        bucket: bucket,
      );
      if (parsed != null) return parsed;
    }
    return null;
  }

  static bool _isLocalPath(String value) {
    final normalized = value.toLowerCase();
    return normalized.startsWith('file:') ||
        normalized.startsWith('/') ||
        normalized.startsWith('./') ||
        normalized.startsWith('../') ||
        value.contains('\\\\') ||
        RegExp(r'^[a-z]:[\\/]').hasMatch(value);
  }

  SupabaseStoragePathResolver({
    this.syncService,
    this.signedUrlLoader,
    this.currentUserId,
    http.Client? httpClient,
    this.signedUrlLifetime = const Duration(minutes: 15),
    this.expirySafetyWindow = const Duration(seconds: 15),
    this.allowedBuckets = const {'assets'},
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null {
    if (signedUrlLifetime < const Duration(minutes: 1) ||
        signedUrlLifetime > const Duration(hours: 1)) {
      throw ArgumentError.value(
        signedUrlLifetime,
        'signedUrlLifetime',
        'Signed URL lifetime must be between one minute and one hour.',
      );
    }
    if (expirySafetyWindow < Duration.zero ||
        expirySafetyWindow >= signedUrlLifetime) {
      throw ArgumentError.value(
        expirySafetyWindow,
        'expirySafetyWindow',
        'Expiry safety window must be shorter than the signed URL lifetime.',
      );
    }
    if (allowedBuckets.isEmpty ||
        allowedBuckets.any((bucket) {
          return bucket.isEmpty ||
              bucket != bucket.trim() ||
              !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(bucket);
        })) {
      throw ArgumentError.value(
        allowedBuckets,
        'allowedBuckets',
        'Storage buckets must use safe names.',
      );
    }
  }

  String? get _effectiveUserId {
    final explicit = currentUserId?.call() ?? syncService?.currentUserId;
    final normalized = explicit?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  bool isStoragePath(
    String? source, {
    required String projectId,
    String bucket = 'assets',
  }) {
    final value = source;
    if (value == null || value.isEmpty || value != value.trim()) return false;
    return StorageAssetReference.tryParse(
          bucket: bucket,
          path: value,
          projectId: projectId,
          allowedBuckets: allowedBuckets,
        ) !=
        null;
  }

  StorageAssetReference? parseReference({
    required String path,
    required String projectId,
    String bucket = 'assets',
  }) => StorageAssetReference.tryParse(
    bucket: bucket,
    path: path,
    projectId: projectId,
    allowedBuckets: allowedBuckets,
  );

  /// Resolves either a durable Storage path or an already-runtime source.
  ///
  /// Direct data/blob/http/local/internal/raster references pass through and
  /// are never sent to Storage. Private Storage paths require an authenticated
  /// account and an active project scope.
  Future<RuntimeAssetResolution?> resolve({
    required String projectId,
    String? source,
    String? storagePath,
    String bucket = 'assets',
    String? expectedUserId,
    bool forceRefresh = false,
  }) async {
    if (_disposed) return null;
    final reference = _parseStorageCandidate(
      projectId: projectId,
      source: source,
      storagePath: storagePath,
      bucket: bucket,
    );
    final candidate = reference == null
        ? _firstNonEmpty(source, storagePath)
        : reference.path;
    if (candidate == null) return null;

    if (reference == null) {
      if (_looksLikeStoragePath(candidate) && !_isLocalPath(candidate)) {
        return null;
      }
      return RuntimeAssetResolution(source: candidate, uri: candidate);
    }

    final accountId = _fencedAccountId(expectedUserId);
    if (accountId == null || signedUrlLoader == null && syncService == null) {
      return null;
    }
    final generation = _generation;
    final entry = await _signedUrl(
      reference,
      expectedUserId: accountId,
      forceRefresh: forceRefresh,
    );
    if (!_isActiveGeneration(generation) ||
        entry == null ||
        !_accountMatches(accountId)) {
      return null;
    }
    return RuntimeAssetResolution(
      source: reference.path,
      uri: entry.url,
      expiresAt: entry.expiresAt,
      isPrivateStorage: true,
    );
  }

  /// Reads bytes without returning a signed URL to the caller.
  Future<Uint8List?> readBytes({
    required String projectId,
    String? source,
    String? storagePath,
    String bucket = 'assets',
    String? expectedUserId,
    int maxBytes = 50 * 1024 * 1024,
  }) async {
    if (_disposed) return null;
    final generation = _generation;
    if (maxBytes <= 0) return null;

    final reference = _parseStorageCandidate(
      projectId: projectId,
      source: source,
      storagePath: storagePath,
      bucket: bucket,
    );
    final candidate = reference == null
        ? _firstNonEmpty(source, storagePath)
        : reference.path;
    if (candidate == null) return null;

    if (reference != null) {
      final accountId = _fencedAccountId(expectedUserId);
      if (accountId == null || signedUrlLoader == null && syncService == null) {
        return null;
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        final entry = await _signedUrl(
          reference,
          expectedUserId: accountId,
          forceRefresh: attempt > 0,
        );
        if (!_isActiveGeneration(generation) ||
            entry == null ||
            !_accountMatches(accountId)) {
          return null;
        }
        try {
          final response = await _getBoundedResponse(
            Uri.parse(entry.url),
            maxBytes: maxBytes,
          );
          if (!_isActiveGeneration(generation)) return null;
          if (response != null &&
              response.statusCode >= 200 &&
              response.statusCode < 300 &&
              response.bodyBytes.isNotEmpty &&
              response.bodyBytes.length <= maxBytes &&
              _accountMatches(accountId)) {
            return Uint8List.fromList(response.bodyBytes);
          }
          if (response == null ||
              (response.statusCode != 401 && response.statusCode != 403)) {
            return null;
          }
          _signedUrlCache.remove(reference.cacheKey);
        } catch (_) {
          if (attempt == 0 && _isActiveGeneration(generation)) {
            _signedUrlCache.remove(reference.cacheKey);
            continue;
          }
          return null;
        }
      }
      return null;
    }

    final normalized = candidate.toLowerCase();
    if (normalized.startsWith('data:')) {
      return _decodeDataUri(candidate, maxBytes: maxBytes);
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    try {
      final publicUri = ExternalUrlPolicy.publicUri(candidate);
      if (publicUri == null) return null;
      final response = await _getBoundedResponse(publicUri, maxBytes: maxBytes);
      if (!_isActiveGeneration(generation) || response == null) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (response.bodyBytes.isEmpty || response.bodyBytes.length > maxBytes) {
        return null;
      }
      return Uint8List.fromList(response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  Future<_BoundedResponse?> _getBoundedResponse(
    Uri uri, {
    required int maxBytes,
  }) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _httpClient
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.isRedirect ||
        response.statusCode == 301 ||
        response.statusCode == 302 ||
        response.statusCode == 303 ||
        response.statusCode == 307 ||
        response.statusCode == 308) {
      return null;
    }
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxBytes) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (builder.length + chunk.length > maxBytes) return null;
      builder.add(chunk);
    }
    return _BoundedResponse(
      statusCode: response.statusCode,
      bodyBytes: builder.takeBytes(),
    );
  }

  /// Clears only transient delivery state. Durable paths remain untouched.
  void clear({String? bucket, String? path}) {
    if (bucket == null || path == null) {
      _signedUrlCache.clear();
      return;
    }
    _signedUrlCache.remove('$bucket:$path');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _signedUrlCache.clear();
    _signedUrlRequests.clear();
    if (_ownsHttpClient) _httpClient.close();
  }

  Future<_SignedUrlEntry?> _signedUrl(
    StorageAssetReference reference, {
    required String expectedUserId,
    required bool forceRefresh,
  }) {
    final now = DateTime.now().toUtc();
    final cached = _signedUrlCache[reference.cacheKey];
    if (!forceRefresh &&
        cached != null &&
        cached.accountId == expectedUserId &&
        cached.expiresAt.isAfter(now.add(expirySafetyWindow)) &&
        _accountMatches(expectedUserId)) {
      return Future.value(cached);
    }

    final requestKey = '${reference.cacheKey}:$expectedUserId';
    final activeRequest = _signedUrlRequests[requestKey];
    if (activeRequest != null) return activeRequest;

    final request = _loadSignedUrl(reference, expectedUserId: expectedUserId);
    _signedUrlRequests[requestKey] = request;
    return request.whenComplete(() {
      if (identical(_signedUrlRequests[requestKey], request)) {
        _signedUrlRequests.remove(requestKey);
      }
    });
  }

  Future<_SignedUrlEntry?> _loadSignedUrl(
    StorageAssetReference reference, {
    required String expectedUserId,
  }) async {
    if (!_accountMatches(expectedUserId)) return null;
    final loader =
        signedUrlLoader ??
        (syncService == null
            ? null
            : ({
                required String bucket,
                required String path,
                required int expiresIn,
                String? expectedUserId,
              }) => syncService!.signedAssetUrl(
                bucket: bucket,
                path: path,
                expiresIn: expiresIn,
                expectedUserId: expectedUserId,
              ));
    if (loader == null) return null;

    final expiresIn = signedUrlLifetime.inSeconds;
    final signed = await loader(
      bucket: reference.bucket,
      path: reference.path,
      expiresIn: expiresIn,
      expectedUserId: expectedUserId,
    );
    if (!_accountMatches(expectedUserId)) return null;
    final value = signed?.trim();
    if (value == null || value.isEmpty || value != signed) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    if (_disposed) return null;
    final entry = _SignedUrlEntry(
      url: value,
      accountId: expectedUserId,
      expiresAt: DateTime.now().toUtc().add(signedUrlLifetime),
    );
    _signedUrlCache[reference.cacheKey] = entry;
    return entry;
  }

  String? _fencedAccountId(String? expectedUserId) {
    final requested = expectedUserId?.trim();
    final accountId = requested == null || requested.isEmpty
        ? _effectiveUserId
        : requested;
    if (accountId == null || accountId.isEmpty) return null;
    if (requested != null && requested.isNotEmpty && requested != accountId) {
      return null;
    }
    return _accountMatches(accountId) ? accountId : null;
  }

  bool _accountMatches(String expectedUserId) {
    final current = _effectiveUserId;
    return current == expectedUserId;
  }

  static String? _firstNonEmpty(String? first, String? second) {
    final firstValue = first?.trim();
    if (firstValue != null && firstValue.isNotEmpty) return firstValue;
    final secondValue = second?.trim();
    return secondValue == null || secondValue.isEmpty ? null : secondValue;
  }

  static bool _looksLikeStoragePath(String value) {
    final normalized = value.toLowerCase();
    if (normalized.startsWith('data:') ||
        normalized.startsWith('blob:') ||
        normalized.startsWith('file:') ||
        normalized.startsWith('raster://') ||
        normalized.startsWith('memory://') ||
        normalized.startsWith('internal://') ||
        normalized.startsWith('http://') ||
        normalized.startsWith('https://')) {
      return false;
    }
    return value.contains('/') || value.contains('?') || value.contains('#');
  }

  static Uint8List? _decodeDataUri(String value, {required int maxBytes}) {
    final comma = value.indexOf(',');
    if (comma <= 5) return null;
    final metadata = value.substring(5, comma).toLowerCase();
    if (!metadata.contains(';base64')) return null;
    try {
      final bytes = base64Decode(base64.normalize(value.substring(comma + 1)));
      if (bytes.isEmpty || bytes.length > maxBytes) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }
}

class _BoundedResponse {
  final int statusCode;
  final Uint8List bodyBytes;

  const _BoundedResponse({required this.statusCode, required this.bodyBytes});
}

class _SignedUrlEntry {
  final String url;
  final String accountId;
  final DateTime expiresAt;

  const _SignedUrlEntry({
    required this.url,
    required this.accountId,
    required this.expiresAt,
  });
}
