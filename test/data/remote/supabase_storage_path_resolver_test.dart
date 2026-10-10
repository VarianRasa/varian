import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/data/remote/supabase_storage_path_resolver.dart';

void main() {
  group('StorageAssetReference', () {
    test('accepts project-scoped and drawing-paper paths', () {
      expect(
        StorageAssetReference.parse(
          bucket: 'assets',
          path: 'project-1/library/object.png',
          projectId: 'project-1',
        ).cacheKey,
        'assets:project-1/library/object.png',
      );
      expect(
        StorageAssetReference.parse(
          bucket: 'assets',
          path: 'drawing-paper/project-1/revision.png',
          projectId: 'project-1',
        ).path,
        'drawing-paper/project-1/revision.png',
      );
    });

    test('rejects unsafe paths and foreign project scope', () {
      final invalid = <String>[
        'project-1/library/../object.png',
        'project-1/library/object.png?token=secret',
        'project-1/library/object.png\n',
        'project-1/library/object.png ',
        'project-2/library/object.png',
        'project-1//object.png',
        '/project-1/library/object.png',
      ];
      for (final path in invalid) {
        expect(
          StorageAssetReference.tryParse(
            bucket: 'assets',
            path: path,
            projectId: 'project-1',
          ),
          isNull,
          reason: path,
        );
      }
    });
  });

  group('SupabaseStoragePathResolver', () {
    test('passes through non-storage sources without signing', () async {
      var signCalls = 0;
      final resolver = SupabaseStoragePathResolver(
        currentUserId: () => 'user-1',
        signedUrlLoader:
            ({
              required bucket,
              required path,
              required expiresIn,
              expectedUserId,
            }) async {
              signCalls++;
              return null;
            },
      );
      addTearDown(resolver.dispose);

      final result = await resolver.resolve(
        projectId: 'project-1',
        source: 'https://cdn.example.test/image.png',
      );

      expect(result?.uri, 'https://cdn.example.test/image.png');
      expect(signCalls, 0);
    });

    test('deduplicates signing and caches by stable path', () async {
      final gate = Completer<void>();
      var signCalls = 0;
      final resolver = SupabaseStoragePathResolver(
        currentUserId: () => 'user-1',
        signedUrlLoader:
            ({
              required bucket,
              required path,
              required expiresIn,
              expectedUserId,
            }) async {
              signCalls++;
              await gate.future;
              return 'https://storage.example.test/object/$signCalls';
            },
      );
      addTearDown(resolver.dispose);

      final first = resolver.resolve(
        projectId: 'project-1',
        storagePath: 'project-1/library/object.png',
        expectedUserId: 'user-1',
      );
      final second = resolver.resolve(
        projectId: 'project-1',
        storagePath: 'project-1/library/object.png',
        expectedUserId: 'user-1',
      );
      gate.complete();

      final results = await Future.wait([first, second]);
      expect(results[0]?.uri, results[1]?.uri);
      expect(signCalls, 1);

      final cached = await resolver.resolve(
        projectId: 'project-1',
        source: 'project-1/library/object.png',
        expectedUserId: 'user-1',
      );
      expect(cached?.uri, results[0]?.uri);
      expect(signCalls, 1);
    });

    test('does not hydrate without an active account', () async {
      var signCalls = 0;
      final resolver = SupabaseStoragePathResolver(
        currentUserId: () => null,
        signedUrlLoader:
            ({
              required bucket,
              required path,
              required expiresIn,
              expectedUserId,
            }) async {
              signCalls++;
              return 'https://storage.example.test/object';
            },
      );
      addTearDown(resolver.dispose);

      final result = await resolver.resolve(
        projectId: 'project-1',
        source: 'project-1/library/object.png',
      );

      expect(result, isNull);
      expect(signCalls, 0);
    });

    test('refreshes once after a protected download response', () async {
      var signCalls = 0;
      var downloadCalls = 0;
      final resolver = SupabaseStoragePathResolver(
        currentUserId: () => 'user-1',
        signedUrlLoader:
            ({
              required bucket,
              required path,
              required expiresIn,
              expectedUserId,
            }) async {
              signCalls++;
              return 'https://storage.example.test/object/$signCalls';
            },
        httpClient: MockClient((request) async {
          downloadCalls++;
          if (downloadCalls == 1) return http.Response('expired', 403);
          return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
        }),
      );
      addTearDown(resolver.dispose);

      final bytes = await resolver.readBytes(
        projectId: 'project-1',
        source: 'project-1/library/object.png',
        expectedUserId: 'user-1',
      );

      expect(bytes, [1, 2, 3]);
      expect(signCalls, 2);
      expect(downloadCalls, 2);
    });

    test('does not return a signed URL after an account switch', () async {
      var currentAccount = 'user-1';
      final gate = Completer<void>();
      final resolver = SupabaseStoragePathResolver(
        currentUserId: () => currentAccount,
        signedUrlLoader:
            ({
              required bucket,
              required path,
              required expiresIn,
              expectedUserId,
            }) async {
              await gate.future;
              return 'https://storage.example.test/object?token=runtime-only';
            },
      );
      addTearDown(resolver.dispose);

      final pending = resolver.resolve(
        projectId: 'project-1',
        source: 'project-1/library/object.png',
        expectedUserId: 'user-1',
      );
      currentAccount = 'user-2';
      gate.complete();

      expect(await pending, isNull);
    });
  });
}
