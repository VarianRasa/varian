import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/features/assets/data/providers/asset_provider_contract.dart';
import 'package:varian/features/assets/data/providers/openverse_asset_provider.dart';
import 'package:varian/features/assets/domain/asset_library.dart';

class _SlowBodyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    const body = '{"results":[]}';
    final stream = Stream<List<int>>.periodic(
      const Duration(milliseconds: 5),
      (index) => [body.codeUnitAt(index)],
    ).take(body.length);
    return http.StreamedResponse(
      stream,
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  test('normalizes Openverse image results and pagination', () async {
    Uri? requested;
    final provider = OpenverseAssetProvider(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'page': 1,
            'page_count': 2,
            'results': [
              {
                'id': 'abc',
                'title': 'A lake',
                'creator': 'Ada',
                'creator_url': 'https://example.org/ada',
                'url': 'https://cdn.example.org/lake.jpg',
                'thumbnail': 'https://cdn.example.org/lake-thumb.jpg',
                'foreign_landing_url': 'https://example.org/lake',
                'mimetype': 'image/jpeg',
                'license': 'cc0',
                'license_version': '1.0',
                'license_url':
                    'https://creativecommons.org/publicdomain/zero/1.0/',
                'width': 1600,
                'height': 900,
                'filesize': 1234,
                'tags': [
                  {'name': 'nature'},
                  {'name': 'lake'},
                ],
              },
              {
                'id': 'unsafe',
                'title': 'HTML response',
                'url': 'https://example.org/page',
                'mimetype': 'text/html',
              },
              {
                'id': ' spaced-id ',
                'title': 'Whitespace identifier',
                'url': 'https://example.org/whitespace.jpg',
                'mimetype': 'image/jpeg',
              },
              {
                'id': 'whitespace-url',
                'title': 'Unsafe URL whitespace',
                'url': 'https://example.org/unsafe.png\n',
                'mimetype': 'image/png',
              },
              {'title': 'Missing id'},
            ],
          }),
          200,
        );
      }),
    );

    final page = await provider.search(
      const AssetLibraryQuery(
        scopeId: 'project-1',
        query: 'lake',
        kind: AssetLibraryItemKind.image,
        pageSize: 12,
      ),
    );

    expect(requested?.path, '/v1/images/');
    expect(requested?.queryParameters['q'], 'lake');
    expect(requested?.queryParameters['page_size'], '12');
    expect(page.items, hasLength(1));
    expect(page.items.single.id, 'openverse:abc');
    expect(page.items.single.creator, 'Ada');
    expect(page.items.single.license, 'CC0 1.0');
    expect(page.items.single.tags, ['nature', 'lake']);
    expect(page.nextCursor, '2');
  });

  test('rejects unsafe provider endpoints and oversized responses', () async {
    expect(
      () =>
          OpenverseAssetProvider(baseUri: Uri.parse('http://example.org/v1/')),
      throwsArgumentError,
    );
    expect(
      () => OpenverseAssetProvider(
        baseUri: Uri.parse('https://example.org/v1/?token=secret'),
      ),
      throwsArgumentError,
    );

    final provider = OpenverseAssetProvider(
      client: MockClient(
        (_) async => http.Response('x' * (2 * 1024 * 1024 + 1), 200),
      ),
    );
    await expectLater(
      provider.search(
        const AssetLibraryQuery(
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
        ),
      ),
      throwsA(isA<AssetProviderException>()),
    );
  });

  test('does not follow redirects from an untrusted provider', () async {
    var followed = true;
    final provider = OpenverseAssetProvider(
      client: MockClient((request) async {
        followed = request.followRedirects;
        return http.Response(
          '',
          302,
          headers: const {'location': 'https://evil.example/redirect'},
        );
      }),
    );

    await expectLater(
      provider.search(
        const AssetLibraryQuery(
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
        ),
      ),
      throwsA(isA<AssetProviderException>()),
    );
    expect(followed, isFalse);
  });

  test('enforces a total timeout while reading a slow response body', () async {
    final provider = OpenverseAssetProvider(
      client: _SlowBodyClient(),
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      provider.search(
        const AssetLibraryQuery(
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
        ),
      ),
      throwsA(isA<AssetProviderException>()),
    );
  });

  test('rejects malformed page cursors before making a request', () async {
    var requested = false;
    final provider = OpenverseAssetProvider(
      client: MockClient((_) async {
        requested = true;
        return http.Response('{"results":[]}', 200);
      }),
    );

    await expectLater(
      provider.search(
        const AssetLibraryQuery(
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          cursor: 'not-a-page',
        ),
      ),
      throwsA(isA<AssetProviderException>()),
    );
    await expectLater(
      provider.search(
        const AssetLibraryQuery(
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          cursor: '0',
        ),
      ),
      throwsA(isA<AssetProviderException>()),
    );
    await expectLater(
      provider.search(
        const AssetLibraryQuery(
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          cursor: '2\n',
        ),
      ),
      throwsA(isA<AssetProviderException>()),
    );
    await expectLater(
      provider.search(
        const AssetLibraryQuery(
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          query: 'lake\n',
        ),
      ),
      throwsA(isA<AssetProviderException>()),
    );
    expect(requested, isFalse);
  });

  test('rejects non-success responses and unsupported kinds', () async {
    final provider = OpenverseAssetProvider(
      client: MockClient((_) async => http.Response('rate limited', 429)),
    );

    expect(
      provider.search(
        const AssetLibraryQuery(
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
        ),
      ),
      throwsA(isA<AssetProviderException>()),
    );

    final unsupported =
        await OpenverseAssetProvider(
          client: MockClient((_) async => http.Response('{}', 200)),
        ).search(
          const AssetLibraryQuery(
            scopeId: 'project-1',
            kind: AssetLibraryItemKind.model3d,
          ),
        );
    expect(unsupported.items, isEmpty);
  });
}
