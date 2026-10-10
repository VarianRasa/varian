import 'dart:convert';

import 'package:http/http.dart' as http;

class MapLocationResult {
  final String displayName;
  final double latitude;
  final double longitude;

  const MapLocationResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
}

class MapLocationServiceException implements Exception {
  final String message;

  const MapLocationServiceException(this.message);

  @override
  String toString() => message;
}

class MapLocationService {
  final http.Client _client;
  final Uri _baseUri;
  final String _userAgent;

  MapLocationService({
    http.Client? client,
    Uri? baseUri,
    this._userAgent = 'Varian/1.0 (OpenStreetMap geocoding)',
  }) : _client = client ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://nominatim.openstreetmap.org');

  Future<List<MapLocationResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final response = await _request('/search', {
      'q': trimmed,
      'format': 'jsonv2',
      'limit': '5',
      'addressdetails': '1',
    });
    final decoded = _decodeList(response);
    return decoded.map(_parseResult).whereType<MapLocationResult>().toList();
  }

  Future<MapLocationResult?> reverse(double latitude, double longitude) async {
    final response = await _request('/reverse', {
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'format': 'jsonv2',
      'zoom': '18',
      'addressdetails': '1',
    });
    if (response.trim().isEmpty) return null;
    final decoded = jsonDecode(response);
    if (decoded is! Map<String, dynamic>) return null;
    return _parseResult(decoded);
  }

  Future<String> _request(String path, Map<String, String> parameters) async {
    try {
      final uri = _baseUri.replace(
        path: '${_baseUri.path}$path',
        queryParameters: parameters,
      );
      final response = await _client
          .get(
            uri,
            headers: {'Accept': 'application/json', 'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const MapLocationServiceException('Geocoding request failed.');
      }
      return response.body;
    } on MapLocationServiceException {
      rethrow;
    } on FormatException {
      throw const MapLocationServiceException('Invalid geocoding response.');
    } catch (_) {
      throw const MapLocationServiceException(
        'Unable to reach geocoding service.',
      );
    }
  }

  List<dynamic> _decodeList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List<dynamic>) {
      throw const MapLocationServiceException('Invalid geocoding response.');
    }
    return decoded;
  }

  MapLocationResult? _parseResult(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final latitude = double.tryParse('${value['lat']}');
    final longitude = double.tryParse('${value['lon']}');
    final displayName = value['display_name'];
    if (latitude == null ||
        longitude == null ||
        displayName is! String ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return null;
    }
    return MapLocationResult(
      displayName: displayName,
      latitude: latitude,
      longitude: longitude,
    );
  }
}
