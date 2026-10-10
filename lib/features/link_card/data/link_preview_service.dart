import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/link_url_policy.dart';
import 'link_preview_parser.dart';

class LinkPreviewException implements Exception {
  final String message;

  const LinkPreviewException(this.message);

  @override
  String toString() => message;
}

Uri? normalizeLinkPreviewAssetUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  if (uri.path == '/link-preview' && uri.queryParameters.containsKey('asset')) {
    return uri.replace(
      scheme: 'https',
      path: '/functions/v1/link-preview',
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
  }
  return uri;
}

class LinkPreviewProxy {
  final Uri endpoint;
  final String anonKey;
  final http.Client client;
  final Duration timeout;

  LinkPreviewProxy({
    required this.endpoint,
    required this.anonKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : client = client ?? http.Client();

  static Uri? endpointFor(String supabaseUrl) {
    final base = Uri.tryParse(supabaseUrl.trim());
    if (base == null ||
        (base.scheme != 'http' && base.scheme != 'https') ||
        base.host.isEmpty) {
      return null;
    }
    final path = base.path.replaceFirst(RegExp(r'/+$'), '');
    return base.replace(
      path: '$path/functions/v1/link-preview',
      query: null,
      fragment: null,
    );
  }

  static Uri? assetUriFor(String supabaseUrl, Uri source) {
    final endpoint = endpointFor(supabaseUrl);
    if (endpoint == null) return null;
    final normalizedSource =
        normalizeLinkPreviewAssetUri(source.toString()) ?? source;
    if (normalizedSource.scheme == endpoint.scheme &&
        normalizedSource.host == endpoint.host &&
        normalizedSource.port == endpoint.port &&
        normalizedSource.path == endpoint.path &&
        normalizedSource.queryParameters.containsKey('asset')) {
      return normalizedSource;
    }
    try {
      final publicSource = normalizeLinkUrl(normalizedSource.toString());
      return endpoint.replace(
        queryParameters: {'asset': publicSource.toString()},
      );
    } on LinkUrlValidationException {
      return null;
    }
  }

  Future<LinkPreviewMetadata> fetch(String input) async {
    final source = normalizeLinkUrl(input).toString();
    final response = await client
        .post(
          endpoint,
          headers: {
            'apikey': anonKey,
            'authorization': 'Bearer $anonKey',
            'content-type': 'application/json',
            'accept': 'application/json',
          },
          body: jsonEncode({'url': source}),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LinkPreviewException(_errorMessage(response));
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException();
      }
      return _metadataFromJson(decoded, source);
    } on LinkPreviewException {
      rethrow;
    } catch (_) {
      throw const LinkPreviewException('Preview tidak dapat dimuat.');
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return 'Preview tidak dapat dimuat.';
  }

  LinkPreviewMetadata _metadataFromJson(
    Map<dynamic, dynamic> json,
    String source,
  ) {
    final finalUri =
        _safeHttpUri(json['finalUrl'] ?? json['url']) ??
        normalizeLinkUrl(source);
    final mediaType = LinkPreviewMediaType.values.firstWhere(
      (value) => value.name == json['mediaType'],
      orElse: () => LinkPreviewMediaType.webpage,
    );
    return LinkPreviewMetadata(
      finalUri: finalUri,
      mediaType: mediaType,
      title: _text(json['title']) ?? finalUri.host,
      description: _text(json['description']),
      faviconUri: _safeHttpUri(json['faviconUrl']),
      imageUri: _safeHttpUri(json['imageUrl']),
      siteName: _text(json['siteName']) ?? finalUri.host,
    );
  }

  Uri? _safeHttpUri(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    if (uri.host == endpoint.host && uri.path == '/link-preview') {
      return endpoint.replace(
        query: uri.query,
        fragment: uri.fragment.isEmpty ? null : uri.fragment,
      );
    }
    return uri;
  }

  String? _text(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}

class LinkPreviewService {
  final http.Client client;
  final LinkPreviewProxy? proxy;
  final Future<void> Function(Uri) ensureDestination;
  final Duration timeout;
  final int maxBodyBytes;
  final int maxRedirects;

  LinkPreviewService({
    http.Client? client,
    this.proxy,
    Future<void> Function(Uri)? ensureDestination,
    this.timeout = const Duration(seconds: 8),
    this.maxBodyBytes = 1024 * 1024,
    this.maxRedirects = 3,
  }) : client = client ?? http.Client(),
       ensureDestination = ensureDestination ?? ensurePublicDestination;

  Future<LinkPreviewMetadata> fetch(String input) async {
    if (proxy != null) return proxy!.fetch(input);
    var uri = normalizeLinkUrl(input);
    try {
      for (var redirects = 0; redirects <= maxRedirects; redirects++) {
        await ensureDestination(uri);
        final request = http.Request('GET', uri)
          ..followRedirects = false
          ..headers['accept'] = 'text/html,application/xhtml+xml';
        final response = await client.send(request).timeout(timeout);
        if (response.isRedirect) {
          if (redirects == maxRedirects) {
            throw const LinkPreviewException('Terlalu banyak pengalihan.');
          }
          final location = response.headers['location'];
          if (location == null) {
            throw const LinkPreviewException('Pengalihan tidak valid.');
          }
          uri = normalizeLinkUrl(uri.resolve(location).toString());
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw LinkPreviewException(
            'Halaman merespons ${response.statusCode}.',
          );
        }
        final contentType =
            response.headers['content-type']?.toLowerCase() ?? '';
        if (!contentType.contains('text/html') &&
            !contentType.contains('application/xhtml+xml')) {
          return _mediaMetadata(uri, contentType);
        }
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(timeout)) {
          final remaining = maxBodyBytes - bytes.length;
          if (remaining <= 0) break;
          bytes.addAll(
            chunk.length <= remaining ? chunk : chunk.take(remaining),
          );
          if (bytes.length >= maxBodyBytes) break;
        }
        return parseLinkPreviewHtml(
          html: utf8.decode(bytes, allowMalformed: true),
          finalUri: uri,
        );
      }
      throw const LinkPreviewException('Terlalu banyak pengalihan.');
    } on LinkPreviewException {
      rethrow;
    } on LinkUrlValidationException catch (error) {
      throw LinkPreviewException(error.message);
    } on TimeoutException {
      throw const LinkPreviewException('Waktu pengambilan preview habis.');
    } catch (_) {
      throw const LinkPreviewException('Preview tidak dapat dimuat.');
    }
  }

  LinkPreviewMetadata _mediaMetadata(Uri uri, String contentType) {
    final mediaType = contentType.startsWith('image/')
        ? LinkPreviewMediaType.image
        : contentType.startsWith('video/')
        ? LinkPreviewMediaType.video
        : contentType.startsWith('audio/')
        ? LinkPreviewMediaType.audio
        : contentType == 'application/pdf'
        ? LinkPreviewMediaType.pdf
        : LinkPreviewMediaType.file;
    final filename = uri.pathSegments.isEmpty
        ? uri.host
        : uri.pathSegments.last;
    return LinkPreviewMetadata(
      finalUri: uri,
      mediaType: mediaType,
      title: filename.isEmpty ? uri.host : filename,
      siteName: uri.host,
      imageUri: mediaType == LinkPreviewMediaType.image ? uri : null,
    );
  }
}
