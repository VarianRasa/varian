import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

final _integrationEnabled =
    (Platform.environment['ASSET_LIBRARY_INTEGRATION'] ?? '') == '1' &&
    (Platform.environment['SUPABASE_URL'] ?? '').trim().isNotEmpty &&
    (Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] ?? '').trim().isNotEmpty;

void main() {
  test(
    'keeps Storage objects and catalog rows separate and rejects overwrites',
    () async {
      final baseUrl = Platform.environment['SUPABASE_URL']!.trim().replaceFirst(
        RegExp(r'/+$'),
        '',
      );
      final serviceKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY']!
          .trim();
      final suffix = _randomSuffix();
      final projectId = 'asset-library-it-$suffix';
      final path =
          '$projectId/library/550e8400-e29b-41d4-a716-446655440000_$suffix.png';
      final itemId = 'integration-item-$suffix';
      final api = _SupabaseHttp(baseUrl, serviceKey);
      final pngHeader = Uint8List.fromList(const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);

      try {
        await api.request(
          'POST',
          '/rest/v1/projects',
          jsonBody: {'id': projectId},
        );
        await api.request(
          'POST',
          '/rest/v1/workspace_entitlements',
          jsonBody: {
            'project_id': projectId,
            'provider': 'manual',
            'plan_id': 'asset-library-integration',
            'status': 'active',
            'limits': {'assetBytes': pngHeader.length},
            'overage_policy': 'block',
          },
        );

        await api.request(
          'POST',
          '/storage/v1/object/assets/$path',
          bytes: pngHeader,
          headers: const {'Content-Type': 'image/png', 'x-upsert': 'false'},
        );
        final overwrite = await api.request(
          'POST',
          '/storage/v1/object/assets/$path',
          bytes: pngHeader,
          headers: const {'Content-Type': 'image/png', 'x-upsert': 'false'},
          allowError: true,
        );
        expect(
          overwrite.statusCode < 200 || overwrite.statusCode > 299,
          isTrue,
        );

        await api.request(
          'POST',
          '/rest/v1/asset_library_items',
          jsonBody: {
            'id': itemId,
            'project_id': projectId,
            'kind': 'image',
            'source': 'upload',
            'status': 'ready',
            'name': 'Integration logo',
            'source_url': 'https://example.org/integration/$suffix.png',
            'mime_type': 'image/png',
            'size_bytes': pngHeader.length,
            'storage_path': path,
            'tags': <String>[],
            'metadata': <String, dynamic>{},
          },
        );

        final catalog = await api.request(
          'GET',
          '/rest/v1/asset_library_items?project_id=eq.$projectId&id=eq.$itemId&select=id,storage_path',
        );
        expect(catalog.statusCode, 200);
        expect(catalog.jsonBody, hasLength(1));
        expect(catalog.jsonBody.single['storage_path'], path);

        // The application must remove the binary through Storage's API before
        // deleting the catalog row. The catalog remains inspectable until the
        // explicit row deletion below.
        await api.request(
          'DELETE',
          '/storage/v1/object/assets',
          jsonBody: {
            'prefixes': [path],
          },
        );
        final objectAfterStorageDelete = await api.request(
          'GET',
          '/storage/v1/object/assets/$path',
          allowError: true,
        );
        expect(
          objectAfterStorageDelete.statusCode < 200 ||
              objectAfterStorageDelete.statusCode > 299,
          isTrue,
        );
        final afterStorageDelete = await api.request(
          'GET',
          '/rest/v1/asset_library_items?project_id=eq.$projectId&id=eq.$itemId&select=id',
        );
        expect(afterStorageDelete.jsonBody, hasLength(1));

        await api.request(
          'DELETE',
          '/rest/v1/asset_library_items?project_id=eq.$projectId&id=eq.$itemId',
        );
        final afterCatalogDelete = await api.request(
          'GET',
          '/rest/v1/asset_library_items?project_id=eq.$projectId&id=eq.$itemId&select=id',
        );
        expect(afterCatalogDelete.jsonBody, isEmpty);
      } finally {
        await api.request(
          'DELETE',
          '/storage/v1/object/assets',
          jsonBody: {
            'prefixes': [path],
          },
          allowError: true,
        );
        await api.request(
          'DELETE',
          '/rest/v1/projects?id=eq.$projectId',
          allowError: true,
        );
        api.close();
      }
    },
    skip: _integrationEnabled
        ? false
        : 'Set ASSET_LIBRARY_INTEGRATION=1 with Supabase credentials.',
  );
}

String _randomSuffix() {
  final random = Random.secure();
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final entropy = random.nextInt(1 << 30).toRadixString(36);
  return '$timestamp-$entropy';
}

class _SupabaseResponse {
  final int statusCode;
  final String body;

  const _SupabaseResponse(this.statusCode, this.body);

  dynamic get jsonBody => body.trim().isEmpty ? null : jsonDecode(body);
}

class _SupabaseHttp {
  final String baseUrl;
  final String serviceKey;
  final HttpClient _client = HttpClient();

  _SupabaseHttp(this.baseUrl, this.serviceKey);

  Future<_SupabaseResponse> request(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? jsonBody,
    Uint8List? bytes,
    bool allowError = false,
  }) async {
    final request = await _client.openUrl(method, Uri.parse('$baseUrl$path'));
    request.followRedirects = false;
    request.headers.set('apikey', serviceKey);
    request.headers.set('Authorization', 'Bearer $serviceKey');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (jsonBody != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(jsonBody));
    } else if (bytes != null) {
      request.add(bytes);
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bodyBytes = <int>[];
    await for (final chunk in response) {
      bodyBytes.addAll(chunk);
      if (bodyBytes.length > 128 * 1024) {
        throw StateError('Supabase integration response exceeded 128 KB.');
      }
    }
    final result = _SupabaseResponse(
      response.statusCode,
      utf8.decode(bodyBytes),
    );
    if (!allowError && (result.statusCode < 200 || result.statusCode > 299)) {
      final detail = result.body.trim();
      throw StateError(
        'Supabase integration request failed for $method $path '
        '(${result.statusCode})${detail.isEmpty ? '' : ': $detail'}',
      );
    }
    return result;
  }

  void close() => _client.close(force: true);
}
