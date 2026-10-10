import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:varian/domain/models/node_payload.dart';

class ChartSourceException implements Exception {
  final String message;

  const ChartSourceException(this.message);

  @override
  String toString() => message;
}

/// Loads chart data from a public JSON endpoint without carrying credentials.
class ChartSourceLoader {
  static const maxResponseBytes = 1024 * 1024;
  static const requestTimeout = Duration(seconds: 8);

  final http.Client _client;
  final bool _ownsClient;

  ChartSourceLoader({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  Future<ChartPayload> load(String rawUrl) async {
    final uri = _parseUrl(rawUrl);
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..maxRedirects = 0;

    try {
      final body = await _loadResponse(request).timeout(requestTimeout);
      final decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
      final data = _chartDataMap(decoded);
      final rawCategories = data['categories'];
      final rawSeries = data['series'];
      if (rawCategories is! List || rawSeries is! List) {
        throw const ChartSourceException(
          'Chart source must contain categories and series arrays.',
        );
      }
      if (rawSeries.isEmpty ||
          rawSeries.any(
            (item) => item is! Map<String, dynamic> && item is! Map,
          )) {
        throw const ChartSourceException(
          'Chart source contains no valid series data.',
        );
      }

      return ChartPayload.fromJson(data);
    } on ChartSourceException {
      rethrow;
    } on TimeoutException {
      throw const ChartSourceException('Chart source request timed out.');
    } on FormatException {
      throw const ChartSourceException('Chart source returned invalid JSON.');
    } catch (_) {
      throw const ChartSourceException('Chart source could not be loaded.');
    }
  }

  Uri _parseUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      throw const ChartSourceException(
        'Chart source URL must use HTTP(S) without credentials.',
      );
    }
    return uri;
  }

  Future<List<int>> _loadResponse(http.Request request) async {
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChartSourceException(
        'Chart source returned HTTP ${response.statusCode}.',
      );
    }
    if (response.contentLength != null &&
        response.contentLength! > maxResponseBytes) {
      throw const ChartSourceException('Chart source response is too large.');
    }
    return _readResponse(response);
  }

  Future<List<int>> _readResponse(http.StreamedResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const ChartSourceException('Chart source response is too large.');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Map<String, dynamic> _chartDataMap(Object? decoded) {
    if (decoded is! Map) {
      throw const ChartSourceException(
        'Chart source must return a JSON object.',
      );
    }
    final root = Map<String, dynamic>.from(decoded);
    final nested = root['data'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    return root;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
