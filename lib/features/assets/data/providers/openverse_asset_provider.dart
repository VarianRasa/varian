import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/asset_library.dart';
import 'asset_provider_contract.dart';

bool _hasOpenverseControlCharacter(String value) =>
    value.codeUnits.any((code) => code < 0x20 || code == 0x7f);

class OpenverseAssetProvider implements AssetCatalogProvider {
  static const _maxQueryLength = 200;
  static const _maxPageSize = 100;
  static const _maxResponseBytes = 2 * 1024 * 1024;

  final http.Client client;
  final Uri baseUri;
  final Duration timeout;
  final Map<String, String> headers;

  OpenverseAssetProvider({
    http.Client? client,
    Uri? baseUri,
    Duration timeout = const Duration(seconds: 12),
    Map<String, String> headers = const {},
  }) : client = client ?? http.Client(),
       baseUri = _validateBaseUri(
         baseUri ?? Uri.parse('https://api.openverse.org/v1/'),
       ),
       timeout = _validateTimeout(timeout),
       headers = Map.unmodifiable(headers);

  @override
  String get id => 'openverse';

  @override
  Future<AssetLibraryPage> search(AssetLibraryQuery query) async {
    final endpoint = _endpointFor(query.kind);
    if (endpoint == null) return const AssetLibraryPage();
    if (_hasOpenverseControlCharacter(query.query)) {
      throw AssetProviderException(id, 'Search query is invalid.');
    }
    final searchQuery = query.query.trim();
    if (searchQuery.length > _maxQueryLength ||
        _hasOpenverseControlCharacter(searchQuery)) {
      throw AssetProviderException(id, 'Search query is invalid.');
    }
    if (query.pageSize < 1 || query.pageSize > 100) {
      throw AssetProviderException(id, 'Page size is invalid.');
    }
    final rawCursor = query.cursor;
    if (rawCursor != null &&
        (_hasOpenverseControlCharacter(rawCursor) ||
            rawCursor != rawCursor.trim())) {
      throw AssetProviderException(id, 'Page cursor is invalid.');
    }
    final page = rawCursor == null ? 1 : int.tryParse(rawCursor);
    if (page == null || page < 1 || page > 10000) {
      throw AssetProviderException(id, 'Page cursor is invalid.');
    }
    final uri = baseUri
        .resolve(endpoint)
        .replace(
          queryParameters: {
            'q': searchQuery,
            'page': '$page',
            'page_size': '${query.pageSize.clamp(1, 100)}',
          },
        );

    final deadline = DateTime.now().add(timeout);
    final abortTrigger = Completer<void>();
    final abortTimer = Timer(timeout, () {
      if (!abortTrigger.isCompleted) abortTrigger.complete();
    });
    try {
      final request =
          http.AbortableRequest('GET', uri, abortTrigger: abortTrigger.future)
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers.addAll(headers);
      final response = await client.send(request).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _cancelResponse(response);
        throw AssetProviderException(
          id,
          response.statusCode == 429
              ? 'Provider rate limit reached.'
              : 'Provider returned an error.',
          statusCode: response.statusCode,
        );
      }
      final declaredLength = int.tryParse(
        response.headers['content-length'] ?? '',
      );
      if (declaredLength != null && declaredLength > _maxResponseBytes) {
        await _cancelResponse(response);
        throw AssetProviderException(id, 'Provider response is too large.');
      }
      final contentType = response.headers['content-type']?.toLowerCase();
      if (contentType != null &&
          contentType.isNotEmpty &&
          !contentType.contains('json')) {
        await _cancelResponse(response);
        throw AssetProviderException(id, 'Provider response is invalid.');
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        await _cancelResponse(response);
        throw AssetProviderException(id, 'Provider request timed out.');
      }
      final body = await _readLimitedBody(response, remaining, abortTrigger);
      final decoded = _decodeObject(utf8.decode(body, allowMalformed: false));
      final rawResults = decoded['results'];
      if (rawResults is! List || rawResults.length > _maxPageSize) {
        throw AssetProviderException(id, 'Provider response is invalid');
      }

      final now = DateTime.now().toUtc();
      final items = <AssetLibraryItem>[];
      for (final value in rawResults) {
        if (value is! Map) continue;
        final item = _parseItem(
          Map<String, dynamic>.from(value),
          scopeId: query.scopeId,
          now: now,
        );
        if (item != null) items.add(item);
      }

      final pageCount = _readInt(decoded['page_count']);
      final next = pageCount != null && page < pageCount && page < 10000
          ? '${page + 1}'
          : null;
      return AssetLibraryPage(items: items, nextCursor: next);
    } on AssetProviderException {
      rethrow;
    } catch (error) {
      if (error is TimeoutException && !abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
      throw AssetProviderException(
        id,
        error is TimeoutException
            ? 'Provider request timed out.'
            : 'Search request failed.',
        statusCode: null,
      );
    } finally {
      // The timer covers both response headers and the streamed body, but it
      // should not retain a completed request after the method returns.
      abortTimer.cancel();
    }
  }

  String? _endpointFor(AssetLibraryItemKind? kind) {
    if (kind == AssetLibraryItemKind.model3d ||
        kind == AssetLibraryItemKind.video ||
        kind == AssetLibraryItemKind.file) {
      return null;
    }
    if (kind == AssetLibraryItemKind.audio) return 'audio/';
    return 'images/';
  }

  AssetLibraryItem? _parseItem(
    Map<String, dynamic> raw, {
    required String scopeId,
    required DateTime now,
  }) {
    final providerAssetId =
        _readIdentifier(raw['id']) ??
        _readIdentifier(raw['foreign_identifier']);
    final title = _readString(raw['title']) ?? providerAssetId;
    if (providerAssetId == null || title == null) return null;

    final mediaType =
        (_readString(raw['mimetype']) ??
                _readString(raw['mime_type']) ??
                'application/octet-stream')
            .toLowerCase();
    if (!mediaType.startsWith('image/') && !mediaType.startsWith('audio/')) {
      return null;
    }
    final kind = mediaType.startsWith('audio/')
        ? AssetLibraryItemKind.audio
        : AssetLibraryItemKind.image;
    final sizeBytes = _readInt(raw['filesize']);
    if (sizeBytes != null && (sizeBytes < 0 || sizeBytes > 512 * 1024 * 1024)) {
      return null;
    }
    final sourceUrl =
        _readUrl(raw['foreign_landing_url']) ?? _readUrl(raw['url']);
    final downloadUrl = _readUrl(raw['url']);
    final previewUrl = _readUrl(raw['thumbnail']) ?? downloadUrl;
    if (sourceUrl == null && downloadUrl == null) return null;

    final license = _licenseLabel(
      _readString(raw['license']),
      _readString(raw['license_version']),
    );
    final tags = _readTags(raw['tags']);
    try {
      return AssetLibraryItem(
        id: 'openverse:$providerAssetId',
        scopeId: scopeId,
        kind: kind,
        source: AssetLibrarySource.openverse,
        name: title,
        creator: _readString(raw['creator']),
        creatorUrl: _readUrl(raw['creator_url']),
        sourceUrl: sourceUrl,
        previewUrl: previewUrl,
        downloadUrl: downloadUrl,
        mimeType: mediaType,
        sizeBytes: sizeBytes,
        width: _readInt(raw['width']),
        height: _readInt(raw['height']),
        license: license,
        licenseUrl: _readUrl(raw['license_url']),
        attribution: _attribution(title, _readString(raw['creator'])),
        tags: tags,
        providerAssetId: providerAssetId,
        createdAt: now,
        updatedAt: now,
        metadata: {
          'provider': id,
          'providerAssetId': providerAssetId,
          if (_readString(raw['foreign_identifier']) != null)
            'foreignIdentifier': _readString(raw['foreign_identifier']),
        },
      );
    } on ArgumentError {
      return null;
    }
  }

  Future<Uint8List> _readLimitedBody(
    http.StreamedResponse response,
    Duration bodyTimeout,
    Completer<void> abortTrigger,
  ) async {
    final builder = BytesBuilder(copy: false);
    final deadline = DateTime.now().add(bodyTimeout);
    var length = 0;
    try {
      await for (final chunk in response.stream.timeout(bodyTimeout)) {
        if (DateTime.now().isAfter(deadline)) {
          throw AssetProviderException(id, 'Provider response timed out.');
        }
        length += chunk.length;
        if (length > _maxResponseBytes) {
          throw AssetProviderException(id, 'Provider response is too large.');
        }
        builder.add(chunk);
      }
      if (DateTime.now().isAfter(deadline)) {
        throw AssetProviderException(id, 'Provider response timed out.');
      }
    } on AssetProviderException {
      if (!abortTrigger.isCompleted) abortTrigger.complete();
      rethrow;
    } on TimeoutException {
      if (!abortTrigger.isCompleted) abortTrigger.complete();
      throw AssetProviderException(id, 'Provider response timed out.');
    } catch (_) {
      if (!abortTrigger.isCompleted) abortTrigger.complete();
      throw AssetProviderException(id, 'Search request failed.');
    }
    return builder.takeBytes();
  }

  Future<void> _cancelResponse(http.StreamedResponse response) async {
    await response.stream.listen((_) {}, onError: (_) {}).cancel();
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Normalized provider error below avoids exposing response contents.
    }
    throw AssetProviderException(id, 'Provider response is invalid');
  }

  static Uri _validateBaseUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'Provider base URLs must be HTTPS without credentials or queries.',
      );
    }
    final path = uri.path.isEmpty
        ? '/'
        : uri.path.endsWith('/')
        ? uri.path
        : '${uri.path}/';
    return uri.replace(path: path);
  }

  static Duration _validateTimeout(Duration value) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(
        value,
        'timeout',
        'Provider timeouts must be positive.',
      );
    }
    return value;
  }

  String? _readString(Object? value) {
    if (value is! String || _hasOpenverseControlCharacter(value)) {
      return null;
    }
    final result = value.trim();
    return result.isEmpty ? null : result;
  }

  String? _readUrl(Object? value) {
    if (value is! String) return null;
    final raw = value;
    final result = raw.trim();
    if (result.isEmpty) return null;
    final uri = Uri.tryParse(result);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        raw.codeUnits.any((code) => code <= 0x20 || code == 0x7f)) {
      return null;
    }
    return result;
  }

  int? _readInt(Object? value) {
    if (value is num) {
      if (!value.isFinite || value != value.truncate()) return null;
      return value.toInt();
    }
    final raw = value is String ? value : null;
    if (raw == null ||
        raw != raw.trim() ||
        _hasOpenverseControlCharacter(raw)) {
      return null;
    }
    return int.tryParse(raw);
  }

  String? _readIdentifier(Object? value) {
    if (value is! String ||
        value != value.trim() ||
        _hasOpenverseControlCharacter(value)) {
      return null;
    }
    return value.isEmpty ? null : value;
  }

  List<String> _readTags(Object? value) {
    if (value is! List) return const [];
    return [
      for (final tag in value)
        if (tag is String &&
            !tag.codeUnits.any((code) => code < 0x20 || code == 0x7f) &&
            tag.trim().isNotEmpty)
          tag.trim()
        else if (tag is Map &&
            tag['name'] is String &&
            !(tag['name'] as String).codeUnits.any(
              (code) => code < 0x20 || code == 0x7f,
            ) &&
            (tag['name'] as String).trim().isNotEmpty)
          (tag['name'] as String).trim(),
    ];
  }

  String? _licenseLabel(String? license, String? version) {
    if (license == null) return null;
    final label = license.toUpperCase();
    return version == null ? label : '$label $version';
  }

  String? _attribution(String title, String? creator) {
    if (creator == null) return title;
    return '$title — $creator';
  }
}
