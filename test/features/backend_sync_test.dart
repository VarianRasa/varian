import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/artifacts/transient_artifact_hydrator.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/publishing/domain/published_snapshot.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';

String _runtimeKey() =>
    String.fromCharCodes(const [114, 117, 110, 116, 105, 109, 101]);

String _testKey() => String.fromCharCodes(const [116, 101, 115, 116]);

Future<void> _authenticate(
  SupabaseClient client, {
  String userId = 'asset-user',
}) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;

  String encodePart(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  final token =
      '${encodePart({'alg': 'HS256'})}.${encodePart({'sub': userId, 'exp': expiration})}.test-signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'asset-refresh',
      'user': {
        'id': userId,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

Future<({bool sawStorageList, bool sawDownload, bool sawSnapshotWrite})>
_runSnapshotAssetCancellationScenario({
  required bool invalidateDuringList,
}) async {
  final imageStore = MemoryImageArtifactStore();
  final bytes = Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]);
  final artifact = await imageStore.save(bytes, fileName: 'hero.png');
  final checksum = sha256.convert(bytes).toString();
  final assetPath =
      '/storage/v1/object/assets/project-1/snapshots/$checksum.png';
  var operationCurrent = true;
  var sawStorageList = false;
  var sawDownload = false;
  var sawSnapshotWrite = false;

  final client = SupabaseClient(
    'https://example.supabase.co',
    _testKey(),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      if (request.url.path == '/rest/v1/projects') {
        return http.Response(
          jsonEncode({'owner_id': 'asset-user'}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (request.url.path == '/rest/v1/canvas_snapshots') {
        if (request.method == 'GET') {
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        sawSnapshotWrite = true;
        return http.Response('{}', 201, request: request);
      }
      if (request.url.path == assetPath) {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'message': 'The resource already exists'}),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        sawDownload = true;
        if (!invalidateDuringList) operationCurrent = false;
        return http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'image/png'},
          request: request,
        );
      }
      if (request.url.path == '/storage/v1/object/list/assets') {
        sawStorageList = true;
        if (invalidateDuringList) operationCurrent = false;
        return http.Response(
          jsonEncode([
            {
              'name': '$checksum.png',
              'id': 'snapshot-asset',
              'bucket_id': 'assets',
              'owner': 'asset-user',
              'updated_at': '2026-10-01T00:00:00Z',
              'created_at': '2026-10-01T00:00:00Z',
              'last_accessed_at': null,
              'metadata': null,
              'buckets': null,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      throw StateError(
        'Unexpected snapshot cancellation request: ${request.url}',
      );
    }),
  );

  try {
    await _authenticate(client);
    final document = CanvasDocument(
      projectId: 'project-1',
      assets: DocumentAssetManifest(
        entries: {
          'hero': DocumentAsset(
            id: 'hero',
            kind: DocumentAssetKind.image,
            storage: DocumentAssetStorage.local,
            name: 'hero.png',
            mimeType: 'image/png',
            sizeBytes: bytes.length,
            durableReference: artifact.reference,
            createdAt: DateTime.utc(2026, 9, 25),
            updatedAt: DateTime.utc(2026, 9, 25),
          ),
        },
      ),
      updatedAt: DateTime.utc(2026, 9, 25),
    );

    await SupabaseSyncService(
      client,
      artifactHydrator: TransientArtifactHydrator(
        imageArtifactStore: imageStore,
      ),
    ).syncDocumentSnapshot(
      document,
      expectedUserId: 'asset-user',
      isOperationCurrent: () => operationCurrent,
    );
  } finally {
    await client.dispose();
  }

  return (
    sawStorageList: sawStorageList,
    sawDownload: sawDownload,
    sawSnapshotWrite: sawSnapshotWrite,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Backend Sync & Connection Integrity Tests', () {
    test(
      'BackendConfig detects missing keys and validates OpenAI connection',
      () async {
        const emptyConfig = BackendConfig(supabaseUrl: '', supabaseAnonKey: '');
        expect(emptyConfig.isOpenAiConfigured, false);
        expect(emptyConfig.isSupabaseConfigured, false);

        final (ok, error) = await emptyConfig.testOpenAiConnection();
        expect(ok, false);
        expect(error, contains('empty'));
      },
    );

    test('tests Supabase credentials provided at runtime', () async {
      final result = await testSupabaseConnection(
        url: 'https://example.supabase.co',
        publishableKey: _runtimeKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/settings');
          expect(request.headers['apikey'], _runtimeKey());
          expect(
            request.headers['authorization'],
            ['Bearer', _runtimeKey()].join(' '),
          );
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(result.$1, true);
      expect(result.$2, isNull);
    });

    test(
      'does not treat a missing application table as invalid Supabase config',
      () async {
        final result = await testSupabaseConnection(
          url: 'https://example.supabase.co',
          publishableKey: _runtimeKey(),
          httpClient: MockClient((request) async {
            expect(request.url.path, '/auth/v1/settings');
            return http.Response(
              '{}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        expect(result.$1, true);
      },
    );

    test('discovers image models without generating an image', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/models');
        expect(
          request.headers['authorization'],
          ['Bearer', _testKey()].join(' '),
        );
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'gpt-4o-mini'},
              {'id': 'gpt-image-2'},
              {'id': 'dall-e-3'},
              {'id': 'gemini-2.5-flash-image-preview'},
              {
                'id': 'provider-specific-model',
                'capabilities': ['image_generation'],
              },
              {'id': 'claude-opus-4-6-thinking'},
            ],
          }),
          200,
        );
      });

      final result = await BackendConfig(
        openAiApiKey: _testKey(),
        openAiBaseUrl: 'https://example.test/v1',
        openAiModel: 'gpt-4o-mini',
      ).discoverImageModels(client);

      expect(result, [
        'dall-e-3',
        'gemini-2.5-flash-image-preview',
        'gpt-image-2',
        'provider-specific-model',
      ]);
    });

    test('separates image model from chat model', () {
      const config = BackendConfig(
        openAiModel: 'claude-opus-4-6-thinking',
        openAiImageModel: 'gpt-image-2',
      );

      expect(config.openAiModel, 'claude-opus-4-6-thinking');
      expect(config.openAiImageModel, 'gpt-image-2');
    });

    test('supports universal image API mode values', () {
      const config = BackendConfig(imageApiMode: ImageApiMode.responses);

      expect(config.imageApiMode, ImageApiMode.responses);
      expect(
        BackendConfig.parseImageApiMode('chatCompletions'),
        ImageApiMode.chatCompletions,
      );
      expect(
        BackendConfig.parseImageApiMode('imagesGenerations'),
        ImageApiMode.imagesGenerations,
      );
      expect(BackendConfig.parseImageApiMode('unknown'), ImageApiMode.auto);
    });

    test('supports independent image edit API mode values', () {
      const config = BackendConfig(
        imageEditApiMode: ImageEditApiMode.responses,
      );

      expect(const BackendConfig().imageEditApiMode, ImageEditApiMode.auto);
      expect(config.imageEditApiMode, ImageEditApiMode.responses);
      expect(
        config
            .copyWith(imageEditApiMode: ImageEditApiMode.chatCompletions)
            .imageEditApiMode,
        ImageEditApiMode.chatCompletions,
      );
      expect(
        BackendConfig.parseImageEditApiMode('imagesEdits'),
        ImageEditApiMode.imagesEdits,
      );
      expect(
        BackendConfig.parseImageEditApiMode('unknown'),
        ImageEditApiMode.auto,
      );
    });

    test('persists selected image API mode', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = BackendConfigNotifier();
      await notifier.waitUntilReady();
      await notifier.saveConfig(
        BackendConfig(
          openAiApiKey: _testKey(),
          openAiModel: 'chat-model',
          openAiImageModel: 'custom-image-model',
          imageApiMode: ImageApiMode.chatCompletions,
          imageEditApiMode: ImageEditApiMode.chatCompletions,
        ),
      );

      final reloaded = BackendConfigNotifier();
      await reloaded.waitUntilReady();
      expect(reloaded.state.imageApiMode, ImageApiMode.chatCompletions);
      expect(reloaded.state.imageEditApiMode, ImageEditApiMode.chatCompletions);
      expect(reloaded.state.openAiImageModel, 'custom-image-model');
    });

    test(
      'SupabaseSyncService testConnection returns error when uninitialized',
      () async {
        final syncService = SupabaseSyncService(null);
        expect(syncService.isConfigured, false);

        final (ok, error) = await syncService.testConnection();
        expect(ok, false);
        expect(error, contains('not initialized'));
      },
    );

    test(
      'preserves actionable auth errors for cloud snapshot writes',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            fail('Unauthenticated snapshot writes must fail before HTTP.');
          }),
        );
        addTearDown(client.dispose);

        final service = SupabaseSyncService(client);
        await expectLater(
          service.syncDocumentSnapshot(
            CanvasDocument(
              projectId: 'project-1',
              updatedAt: DateTime.utc(2026, 9, 12),
            ),
          ),
          throwsA(
            isA<SyncException>().having(
              (error) => error.message,
              'message',
              'Sign in is required before writing cloud canvas data.',
            ),
          ),
        );
      },
    );

    test(
      'stops a snapshot sync invalidated while its ownership preflight waits',
      () async {
        final ownershipStarted = Completer<void>();
        final releaseOwnership = Completer<void>();
        final requests = <http.Request>[];
        late final SupabaseClient client;
        client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            expect(request.url.path, '/rest/v1/projects');
            if (!ownershipStarted.isCompleted) {
              ownershipStarted.complete();
              await releaseOwnership.future;
            }
            return http.Response(
              jsonEncode({'owner_id': 'account-a'}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client, userId: 'account-a');

        var operationCurrent = true;
        final syncing = SupabaseSyncService(client).syncDocumentSnapshot(
          CanvasDocument(
            projectId: 'project-1',
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
          expectedUserId: 'account-a',
          isOperationCurrent: () => operationCurrent,
        );
        await ownershipStarted.future;

        await _authenticate(client, userId: 'account-b');
        operationCurrent = false;
        await _authenticate(client, userId: 'account-a');
        releaseOwnership.complete();
        await syncing;

        expect(
          requests.where(
            (request) =>
                request.url.path == '/rest/v1/canvas_snapshots' &&
                request.method != 'GET',
          ),
          isEmpty,
        );
        expect(requests, hasLength(1));
      },
    );

    test(
      'stops an invalidated editor upload after authorization preflight',
      () async {
        final authorizationStarted = Completer<void>();
        final releaseAuthorization = Completer<void>();
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            expect(request.url.path, '/rest/v1/rpc/can_edit_project');
            authorizationStarted.complete();
            await releaseAuthorization.future;
            return http.Response('true', 200, request: request);
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client, userId: 'account-a');

        var operationCurrent = true;
        final upload = SupabaseSyncService(client).uploadAssetForProjectEditor(
          bucket: 'assets',
          path: 'project-1/collaboration/image.png',
          bytes: Uint8List.fromList(const [1, 2, 3]),
          expectedUserId: 'account-a',
          isOperationCurrent: () => operationCurrent,
        );
        await authorizationStarted.future;

        await _authenticate(client, userId: 'account-b');
        operationCurrent = false;
        await _authenticate(client, userId: 'account-a');
        releaseAuthorization.complete();
        expect(await upload, isNull);

        expect(
          requests.where(
            (request) =>
                request.url.path.startsWith('/storage/v1/object/assets/'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'denies ordinary snapshot sync for an ownerless server project',
      () async {
        final requests = <http.Request>[];
        final imageStore = MemoryImageArtifactStore();
        final bytes = Uint8List.fromList(const [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        final artifact = await imageStore.save(bytes, fileName: 'local.png');
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/rest/v1/projects') {
              expect(request.method, 'GET');
              expect(request.url.queryParameters['id'], 'eq.local-project');
              return http.Response(
                jsonEncode({'owner_id': null}),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            if (request.url.path.startsWith('/storage/v1/object/')) {
              return http.Response(
                jsonEncode({'Key': request.url.pathSegments.skip(4).join('/')}),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            if (request.url.path == '/rest/v1/canvas_snapshots') {
              return http.Response('{}', 200, request: request);
            }
            if (request.url.path ==
                '/rest/v1/rpc/claim_canvas_project_ownership') {
              return http.Response('null', 200, request: request);
            }
            fail('Unexpected ownerless snapshot request: ${request.url}');
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client, userId: 'project-owner');

        final service = SupabaseSyncService(
          client,
          artifactHydrator: TransientArtifactHydrator(
            imageArtifactStore: imageStore,
          ),
        );
        final document = CanvasDocument(
          projectId: 'local-project',
          assets: DocumentAssetManifest(
            entries: {
              'local-image': DocumentAsset(
                id: 'local-image',
                kind: DocumentAssetKind.image,
                storage: DocumentAssetStorage.local,
                name: 'local.png',
                mimeType: 'image/png',
                sizeBytes: bytes.length,
                durableReference: artifact.reference,
                createdAt: DateTime.utc(2026, 10, 1),
                updatedAt: DateTime.utc(2026, 10, 1),
              ),
            },
          ),
          updatedAt: DateTime.utc(2026, 10, 1),
        );

        await expectLater(
          service.syncDocumentSnapshot(
            document,
            expectedUserId: 'project-owner',
          ),
          throwsA(
            isA<SyncException>().having(
              (error) => error.message,
              'message',
              'This local project must be adopted before cloud sync.',
            ),
          ),
        );

        expect(requests.map((request) => request.url.path), [
          '/rest/v1/projects',
        ]);
        expect(
          requests.any(
            (request) => request.url.path.startsWith('/storage/v1/'),
          ),
          isFalse,
        );
        expect(
          requests.any(
            (request) =>
                request.url.path == '/rest/v1/canvas_snapshots' &&
                request.method != 'GET',
          ),
          isFalse,
        );
        expect(
          requests.any(
            (request) =>
                request.url.path ==
                '/rest/v1/rpc/claim_canvas_project_ownership',
          ),
          isFalse,
        );
      },
    );

    test(
      'reads server project ownership for the authenticated account',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/rest/v1/projects');
            expect(request.url.queryParameters['select'], 'id,owner_id');
            expect(request.url.queryParameters['id'], 'eq.project-owner');
            return http.Response(
              jsonEncode({'id': 'project-owner', 'owner_id': 'project-owner'}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client, userId: 'project-owner');

        final eligibility = await SupabaseSyncService(client)
            .getWorkspaceOwnerEligibility(
              'project-owner',
              expectedUserId: 'project-owner',
            );

        expect(eligibility.projectId, 'project-owner');
        expect(eligibility.isOwner, isTrue);
      },
    );

    test('does not treat project membership as cloud ownership', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/projects');
          return http.Response(
            jsonEncode({'id': 'project-shared', 'owner_id': 'another-owner'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, userId: 'project-member');

      final eligibility = await SupabaseSyncService(client)
          .getWorkspaceOwnerEligibility(
            'project-shared',
            expectedUserId: 'project-member',
          );

      expect(eligibility.projectId, 'project-shared');
      expect(eligibility.isOwner, isFalse);
    });

    test('rejects ownership lookup when the account changes', () async {
      late final SupabaseClient client;
      client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          await _authenticate(client, userId: 'different-account');
          return http.Response(
            jsonEncode({'id': 'project-owner', 'owner_id': 'project-owner'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, userId: 'project-owner');

      await expectLater(
        SupabaseSyncService(client).getWorkspaceOwnerEligibility(
          'project-owner',
          expectedUserId: 'project-owner',
        ),
        throwsA(
          isA<SyncException>().having(
            (error) => error.message,
            'message',
            'The cloud account changed during this action.',
          ),
        ),
      );
    });

    test('rejects unknown governance deletion status', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_workspace_governance');
          return http.Response(
            jsonEncode({
              'projectId': 'project-owner',
              'policy': const {},
              'usage': const {},
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, userId: 'project-owner');

      await expectLater(
        SupabaseSyncService(client).getWorkspaceGovernance('project-owner'),
        throwsA(isA<SyncException>()),
      );
    });

    test('reads deletion status from the server governance RPC', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/rpc/get_workspace_governance');
          expect(jsonDecode(request.body), {'p_project_id': 'project-owner'});
          return http.Response(
            jsonEncode({
              'projectId': 'project-owner',
              'policy': const {},
              'usage': const {},
              'deletionRequestedAt': '2026-09-27T10:15:00Z',
              'archivedAt': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, userId: 'project-owner');

      final snapshot = await SupabaseSyncService(
        client,
      ).getWorkspaceGovernance('project-owner');

      expect(snapshot.projectId, 'project-owner');
      expect(
        snapshot.deletionRequestedAt,
        DateTime.parse('2026-09-27T10:15:00Z'),
      );
      expect(snapshot.hasPendingDeletionRequest, isTrue);
    });

    test('rejects a governance response scoped to another project', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_workspace_governance');
          return http.Response(
            jsonEncode({
              'projectId': 'project-other',
              'policy': const {},
              'usage': const {},
              'deletionRequestedAt': null,
              'archivedAt': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, userId: 'project-owner');

      await expectLater(
        SupabaseSyncService(client).getWorkspaceGovernance('project-owner'),
        throwsA(isA<SyncException>()),
      );
    });

    test(
      'rechecks the account after reading project deletion status',
      () async {
        late final SupabaseClient client;
        client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            expect(request.url.path, '/rest/v1/rpc/get_workspace_governance');
            await _authenticate(client, userId: 'different-account');
            return http.Response(
              jsonEncode({
                'projectId': 'project-owner',
                'policy': const {},
                'usage': const {},
                'deletionRequestedAt': null,
                'archivedAt': null,
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client, userId: 'project-owner');

        await expectLater(
          SupabaseSyncService(client).getWorkspaceGovernance('project-owner'),
          throwsA(isA<SyncException>()),
        );
      },
    );

    test('rechecks the account after a project deletion request', () async {
      late final SupabaseClient client;
      client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/request_project_deletion');
          await _authenticate(client, userId: 'different-account');
          return http.Response(
            jsonEncode({
              'projectId': 'project-owner',
              'deletionRequestedAt': '2026-09-27T10:15:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, userId: 'project-owner');

      await expectLater(
        SupabaseSyncService(client).requestProjectDeletion(
          'project-owner',
          expectedUserId: 'project-owner',
        ),
        throwsA(
          isA<SyncException>().having(
            (error) => error.message,
            'message',
            'The cloud account changed during this action.',
          ),
        ),
      );
    });

    test('rejects an invalid project deletion request receipt', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/request_project_deletion');
          return http.Response('null', 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, userId: 'project-owner');

      await expectLater(
        SupabaseSyncService(client).requestProjectDeletion('project-owner'),
        throwsA(isA<SyncException>()),
      );
    });

    test('requests project deletion through the owner RPC contract', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/rpc/request_project_deletion');
          expect(jsonDecode(request.body), {'p_project_id': 'project-owner'});
          return http.Response(
            jsonEncode({
              'projectId': 'project-owner',
              'deletionRequestedAt': '2026-09-27T10:15:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final receipt = await SupabaseSyncService(
        client,
      ).requestProjectDeletion('project-owner');
      expect(receipt.projectId, 'project-owner');
      expect(
        receipt.deletionRequestedAt,
        DateTime.parse('2026-09-27T10:15:00Z'),
      );
    });

    test('cancels project deletion through the owner RPC contract', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/rpc/cancel_project_deletion');
          expect(jsonDecode(request.body), {'p_project_id': 'project-owner'});
          return http.Response('null', 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      await expectLater(
        SupabaseSyncService(client).cancelProjectDeletion('project-owner'),
        completes,
      );
    });

    test('rechecks the account after cancelling project deletion', () async {
      late final SupabaseClient client;
      client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/cancel_project_deletion');
          await _authenticate(client, userId: 'different-account');
          return http.Response('null', 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, userId: 'project-owner');

      await expectLater(
        SupabaseSyncService(client).cancelProjectDeletion(
          'project-owner',
          expectedUserId: 'project-owner',
        ),
        throwsA(
          isA<SyncException>().having(
            (error) => error.message,
            'message',
            'The cloud account changed during this action.',
          ),
        ),
      );
    });

    test('requires authentication before project deletion RPCs', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          fail('Unauthenticated deletion actions must fail before HTTP.');
        }),
      );
      addTearDown(client.dispose);
      final service = SupabaseSyncService(client);

      await expectLater(
        service.requestProjectDeletion('project-owner'),
        throwsA(
          isA<SyncException>().having(
            (error) => error.message,
            'message',
            'Sign in is required before writing cloud canvas data.',
          ),
        ),
      );
      await expectLater(
        service.cancelProjectDeletion('project-owner'),
        throwsA(isA<SyncException>()),
      );
    });

    test('rejects non-success deletion RPC responses', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/request_project_deletion');
          return http.Response(
            jsonEncode({'message': 'owner only'}),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      await expectLater(
        SupabaseSyncService(client).requestProjectDeletion('project-joined'),
        throwsA(isA<SyncException>()),
      );
    });

    test('rejects a cloud document embedded for another project', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/canvas_snapshots');
          return http.Response(
            jsonEncode({
              'document_data': CanvasDocument(
                projectId: 'project-b',
                updatedAt: DateTime.utc(2026, 9, 12),
              ).toJson(),
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-0/1',
            },
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      await expectLater(
        SupabaseSyncService(client).fetchDocumentSnapshot('project-a'),
        throwsA(
          isA<SyncException>().having(
            (error) => error.cause,
            'cause',
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('project mismatch'),
            ),
          ),
        ),
      );
    });

    test(
      'rejects a collaboration snapshot document from another project',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            expect(request.url.path, '/rest/v1/rpc/get_canvas_crdt_delta');
            return http.Response(
              jsonEncode([
                {
                  'snapshot': {
                    'version': const {},
                    'state': {
                      'document': CanvasDocument(
                        projectId: 'project-b',
                        updatedAt: DateTime.utc(2026, 9, 12),
                      ).toJson(),
                    },
                  },
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        await expectLater(
          SupabaseSyncService(client).fetchCollaborationSnapshot('project-a'),
          throwsA(
            isA<SyncException>().having(
              (error) => error.cause,
              'cause',
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                contains('project mismatch'),
              ),
            ),
          ),
        );
      },
    );

    test('rejects a collaboration operation from another project', () async {
      final operation = {
        'v': 1,
        'projectId': 'project-b',
        'opId': 'actor-b:1',
        'dot': {'actorId': 'actor-b', 'counter': 1},
        'dependencies': const {},
        'kind': 'nodeDelete',
        'targetId': 'node-b',
        'field': null,
        'value': const {},
      };
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_canvas_crdt_delta');
          return http.Response(
            jsonEncode([
              {'operation': operation},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      await expectLater(
        SupabaseSyncService(client).fetchCollaborationSnapshot('project-a'),
        throwsA(
          isA<SyncException>().having(
            (error) => error.cause,
            'cause',
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('project mismatch'),
            ),
          ),
        ),
      );
    });

    test('rejects an unknown collaborative data URI MIME type', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          fail('Unknown MIME must fail before Storage HTTP.');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final path = await SupabaseSyncService(client)
          .uploadCollaborativeImageAsset(
            projectId: 'project-1',
            assetId: 'node-unknown',
            source: 'data:application/octet-stream;base64,AQID',
          );
      expect(path, isNull);
    });

    test(
      'uploads a generated data URI as a stable collaborative asset',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/projects') {
              expect(request.method, 'GET');
              expect(request.url.queryParameters['id'], 'eq.project-1');
              return http.Response(
                jsonEncode({'owner_id': 'asset-user'}),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            expect(
              request.url.path,
              '/storage/v1/object/assets/project-1/ai/node-1.png',
            );
            return http.Response(
              jsonEncode({'Key': 'assets/project-1/ai/node-1.png'}),
              200,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        final url = await SupabaseSyncService(client)
            .uploadCollaborativeImageAsset(
              projectId: 'project-1',
              assetId: 'node-1',
              source: 'data:image/png;base64,iVBORw0KGgo=',
            );

        expect(url, 'project-1/ai/node-1.png');
        expect(url, isNot(contains('/public/')));
      },
    );

    test(
      'uploads Drawing Paper previews using the embedded project scope',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/projects') {
              expect(request.url.queryParameters['id'], 'eq.project-1');
              return http.Response(
                jsonEncode({'owner_id': 'asset-user'}),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            expect(
              request.url.path,
              '/storage/v1/object/assets/drawing-paper/project-1/paper/0-deadbeef.png',
            );
            return http.Response(
              jsonEncode({
                'Key': 'assets/drawing-paper/project-1/paper/0-deadbeef.png',
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        final path = await SupabaseSyncService(client).uploadAsset(
          bucket: 'assets',
          path: 'drawing-paper/project-1/paper/0-deadbeef.png',
          bytes: Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]),
          contentType: 'image/png',
          expectedUserId: 'asset-user',
        );

        expect(path, 'drawing-paper/project-1/paper/0-deadbeef.png');
      },
    );

    test(
      'rejects direct project asset uploads for a foreign owner before Storage',
      () async {
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            requests.add(request);
            expect(request.method, 'GET');
            expect(request.url.path, '/rest/v1/projects');
            expect(request.url.queryParameters['id'], 'eq.project-1');
            return http.Response(
              jsonEncode({'owner_id': 'another-owner'}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client, userId: 'asset-user');

        await expectLater(
          SupabaseSyncService(client).uploadAsset(
            bucket: 'assets',
            path: 'drawing-paper/project-1/paper/preview.png',
            bytes: Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]),
            contentType: 'image/png',
            expectedUserId: 'asset-user',
          ),
          throwsA(
            isA<SyncException>().having(
              (error) => error.message,
              'message',
              'The signed-in account does not own this project.',
            ),
          ),
        );

        expect(requests, hasLength(1));
        expect(
          requests.any(
            (request) => request.url.path.startsWith('/storage/v1/'),
          ),
          isFalse,
        );
        expect(
          requests.any(
            (request) =>
                request.url.path.contains('claim_canvas_project_ownership'),
          ),
          isFalse,
        );
      },
    );

    test('does not stage already private project storage paths', () {
      final service = SupabaseSyncService(null);
      final asset = DocumentAsset(
        id: 'remote-asset',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.remote,
        name: 'image.png',
        mimeType: 'image/png',
        durableReference: 'project-1/collaboration/remote-v1.png',
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      );

      expect(
        service.requiresCollaborativeAssetDeliveryForTesting(asset),
        isFalse,
      );
    });

    test(
      'stages a generic file for an editor without requiring project ownership',
      () async {
        final fileStore = MemoryFileArtifactStore();
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final artifact = await fileStore.save(bytes, fileName: 'data.bin');
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/rest/v1/rpc/can_edit_project') {
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), {'p_project_id': 'project-1'});
              return http.Response('true', 200, request: request);
            }
            expect(
              request.url.path,
              '/storage/v1/object/assets/project-1/collaboration/generic-asset-v1.bin',
            );
            expect(request.method, 'POST');
            return http.Response(
              jsonEncode({
                'Key': 'assets/project-1/collaboration/generic-asset-v1.bin',
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        final service = SupabaseSyncService(
          client,
          artifactHydrator: TransientArtifactHydrator(
            fileArtifactStore: fileStore,
          ),
        );
        final asset = DocumentAsset(
          id: 'generic-asset',
          kind: DocumentAssetKind.document,
          storage: DocumentAssetStorage.local,
          name: 'data.bin',
          mimeType: 'application/octet-stream',
          sizeBytes: bytes.length,
          durableReference: artifact.reference,
          createdAt: DateTime.utc(2026, 9, 25),
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        final prepared = await service.prepareCollaborativeAsset(
          projectId: 'project-1',
          asset: asset,
        );

        expect(prepared?.durableReference, isNotNull);
        expect(
          prepared?.durableReference,
          'project-1/collaboration/generic-asset-v1.bin',
        );
        expect(prepared?.remoteUrl, isNull);
        expect(prepared?.localPath, isNull);
        expect(prepared?.sizeBytes, bytes.length);
        expect(requests.map((request) => request.url.path), [
          '/rest/v1/rpc/can_edit_project',
          '/storage/v1/object/assets/project-1/collaboration/generic-asset-v1.bin',
        ]);
      },
    );

    test('does not upload collaborative assets for a viewer', () async {
      final fileStore = MemoryFileArtifactStore();
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final artifact = await fileStore.save(bytes, fileName: 'data.bin');
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.url.path, '/rest/v1/rpc/can_edit_project');
          return http.Response('false', 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      await expectLater(
        SupabaseSyncService(
          client,
          artifactHydrator: TransientArtifactHydrator(
            fileArtifactStore: fileStore,
          ),
        ).prepareCollaborativeAsset(
          projectId: 'project-1',
          asset: DocumentAsset(
            id: 'generic-asset',
            kind: DocumentAssetKind.document,
            storage: DocumentAssetStorage.local,
            name: 'data.bin',
            mimeType: 'application/octet-stream',
            sizeBytes: bytes.length,
            durableReference: artifact.reference,
            createdAt: DateTime.utc(2026, 9, 25),
            updatedAt: DateTime.utc(2026, 9, 25),
          ),
          expectedUserId: 'asset-user',
        ),
        throwsA(
          isA<SyncException>().having(
            (error) => error.message,
            'message',
            'The signed-in account cannot edit this project.',
          ),
        ),
      );

      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/rest/v1/rpc/can_edit_project');
    });

    test(
      'stages every local asset before a collaborative document is persisted',
      () async {
        final imageStore = MemoryImageArtifactStore();
        final bytes = Uint8List.fromList(const [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        final artifact = await imageStore.save(bytes, fileName: 'hero.png');
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/rpc/can_edit_project') {
              expect(jsonDecode(request.body), {'p_project_id': 'project-1'});
              return http.Response('true', 200, request: request);
            }
            expect(
              request.url.path,
              '/storage/v1/object/assets/project-1/collaboration/hero-v1.png',
            );
            return http.Response(
              jsonEncode({'Key': 'assets/project-1/collaboration/hero-v1.png'}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        final service = SupabaseSyncService(
          client,
          artifactHydrator: TransientArtifactHydrator(
            imageArtifactStore: imageStore,
          ),
        );
        final document = CanvasDocument(
          projectId: 'project-1',
          assets: DocumentAssetManifest(
            entries: {
              'hero': DocumentAsset(
                id: 'hero',
                kind: DocumentAssetKind.image,
                storage: DocumentAssetStorage.local,
                name: 'hero.png',
                mimeType: 'image/png',
                sizeBytes: bytes.length,
                durableReference: artifact.reference,
                createdAt: DateTime.utc(2026, 9, 25),
                updatedAt: DateTime.utc(2026, 9, 25),
              ),
            },
          ),
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        final prepared = await service.prepareCollaborativeDocument(document);

        expect(prepared, isNotNull);
        expect(
          prepared!.assets['hero']!.durableReference,
          'project-1/collaboration/hero-v1.png',
        );
        expect(prepared.assets['hero']!.localPath, isNull);
        expect(prepared.assets['hero']!.remoteUrl, isNull);
      },
    );

    test(
      'rejects a keyed collaborative dependency with a mismatched reference',
      () async {
        final asset = DocumentAsset(
          id: 'hero',
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.remote,
          name: 'hero.png',
          mimeType: 'image/png',
          durableReference: 'project-1/library/hero.png',
          createdAt: DateTime.utc(2026, 9, 25),
          updatedAt: DateTime.utc(2026, 9, 25),
        );
        final document = CanvasDocument(
          projectId: 'project-1',
          nodes: [
            CanvasNode(
              id: 'hero-node',
              type: NodeType.image,
              x: 0,
              y: 0,
              width: 100,
              height: 100,
              payload: ImagePayload(
                assetId: asset.id,
                storagePath: 'project-1/library/other.png',
              ),
            ),
          ],
          assets: DocumentAssetManifest(entries: {asset.id: asset}),
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        final prepared = await SupabaseSyncService(
          null,
        ).prepareCollaborativeDocument(document);

        expect(prepared, isNull);
      },
    );

    test(
      'rejects an unkeyed dependency when kind and reference are not unique',
      () async {
        final first = DocumentAsset(
          id: 'hero-a',
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.remote,
          name: 'hero-a.png',
          mimeType: 'image/png',
          durableReference: 'project-1/library/shared.png',
          createdAt: DateTime.utc(2026, 9, 25),
          updatedAt: DateTime.utc(2026, 9, 25),
        );
        final second = first.copyWith(id: 'hero-b');
        final document = CanvasDocument(
          projectId: 'project-1',
          nodes: [
            CanvasNode(
              id: 'hero-node',
              type: NodeType.image,
              x: 0,
              y: 0,
              width: 100,
              height: 100,
              payload: ImagePayload(storagePath: first.durableReference),
            ),
          ],
          assets: DocumentAssetManifest(
            entries: {first.id: first, second.id: second},
          ),
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        final prepared = await SupabaseSyncService(
          null,
        ).prepareCollaborativeDocument(document);

        expect(prepared, isNull);
      },
    );

    test(
      'rejects a collaborative document whose node asset is absent from the manifest',
      () async {
        final document = CanvasDocument(
          projectId: 'project-1',
          nodes: [
            CanvasNode(
              id: 'hero-node',
              type: NodeType.image,
              x: 0,
              y: 0,
              width: 100,
              height: 100,
              payload: ImagePayload(
                assetId: 'missing-hero',
                imageArtifactReference: 'varian-image://missing-hero',
              ),
            ),
          ],
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        final prepared = await SupabaseSyncService(
          null,
        ).prepareCollaborativeDocument(document);

        expect(prepared, isNull);
      },
    );

    test('stages image assets before an insert-only snapshot write', () async {
      final imageStore = MemoryImageArtifactStore();
      final bytes = Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]);
      final artifact = await imageStore.save(bytes, fileName: 'hero.png');
      var uploadObserved = false;
      var snapshotObserved = false;
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          if (request.url.path == '/rest/v1/projects') {
            expect(request.method, 'GET');
            expect(request.url.queryParameters['id'], 'eq.project-1');
            return http.Response(
              jsonEncode({'owner_id': 'asset-user'}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'GET') {
            return http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path ==
              '/storage/v1/object/assets/project-1/snapshots/4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6.png') {
            uploadObserved = true;
            expect(request.method, 'POST');
            expect(request.headers['x-upsert'], 'false');
            return http.Response(
              jsonEncode({'Key': request.url.pathSegments.skip(4).join('/')}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'POST') {
            snapshotObserved = true;
            expect(uploadObserved, isTrue);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final data = Map<String, dynamic>.from(
              body['document_data'] as Map,
            );
            final assets = Map<String, dynamic>.from(data['assets'] as Map);
            final item = (assets['items'] as List).single as Map;
            expect(
              item['durableReference'],
              startsWith('project-1/snapshots/'),
            );
            expect(item.containsKey('localPath'), isFalse);
            expect(item.containsKey('remoteUrl'), isFalse);
            expect(body['revision'], 0);
            return http.Response('{}', 201, request: request);
          }
          if (request.url.path == '/rest/v1/rpc/can_edit_project') {
            expect(jsonDecode(request.body), {'p_project_id': 'project-1'});
            return http.Response('true', 200, request: request);
          }
          fail('Unexpected snapshot staging request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final document = CanvasDocument(
        projectId: 'project-1',
        assets: DocumentAssetManifest(
          entries: {
            'hero': DocumentAsset(
              id: 'hero',
              kind: DocumentAssetKind.image,
              storage: DocumentAssetStorage.local,
              name: 'hero.png',
              mimeType: 'image/png',
              sizeBytes: bytes.length,
              durableReference: artifact.reference,
              localPath: '/tmp/hero.png',
              createdAt: DateTime.utc(2026, 9, 25),
              updatedAt: DateTime.utc(2026, 9, 25),
            ),
          },
        ),
        updatedAt: DateTime.utc(2026, 9, 25),
      );

      await SupabaseSyncService(
        client,
        artifactHydrator: TransientArtifactHydrator(
          imageArtifactStore: imageStore,
        ),
      ).syncDocumentSnapshot(document, expectedUserId: 'asset-user');

      expect(uploadObserved, isTrue);
      expect(snapshotObserved, isTrue);
    });

    test(
      'does not download an existing snapshot asset after Storage list invalidates the operation',
      () async {
        final result = await _runSnapshotAssetCancellationScenario(
          invalidateDuringList: true,
        );

        expect(result.sawStorageList, isTrue);
        expect(result.sawDownload, isFalse);
        expect(result.sawSnapshotWrite, isFalse);
      },
    );

    test(
      'does not write a snapshot after existing-asset preflight invalidates the operation',
      () async {
        final result = await _runSnapshotAssetCancellationScenario(
          invalidateDuringList: false,
        );

        expect(result.sawStorageList, isTrue);
        expect(result.sawDownload, isTrue);
        expect(result.sawSnapshotWrite, isFalse);
      },
    );

    test(
      'reuses an existing content-addressed snapshot asset only when bytes match',
      () async {
        final imageStore = MemoryImageArtifactStore();
        final bytes = Uint8List.fromList(const [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        final artifact = await imageStore.save(bytes, fileName: 'hero.png');
        final expectedPath =
            '/storage/v1/object/assets/project-1/snapshots/4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6.png';
        final requests = <http.Request>[];
        var sawStorageList = false;
        var sawMatchingDownload = false;
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/rest/v1/projects') {
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode({'owner_id': 'asset-user'}),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            if (request.url.path == '/rest/v1/canvas_snapshots' &&
                request.method == 'GET') {
              return http.Response(
                '[]',
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            if (request.url.path == expectedPath) {
              if (request.method == 'POST') {
                expect(request.headers['x-upsert'], 'false');
                return http.Response(
                  jsonEncode({
                    'message': 'The resource already exists',
                    'error': 'Duplicate',
                  }),
                  400,
                  headers: {'content-type': 'application/json'},
                  request: request,
                );
              }
              expect(request.method, 'GET');
              sawMatchingDownload = true;
              expect(sawStorageList, isTrue);
              return http.Response.bytes(
                bytes,
                200,
                headers: {'content-type': 'image/png'},
                request: request,
              );
            }
            if (request.url.path == '/storage/v1/object/list/assets') {
              sawStorageList = true;
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              expect(body['prefix'], 'project-1/snapshots');
              expect(
                body['search'],
                '4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6.png',
              );
              return http.Response(
                jsonEncode([
                  {
                    'name':
                        '4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6.png',
                    'id': 'snapshot-asset',
                    'bucket_id': 'assets',
                    'owner': 'asset-user',
                    'updated_at': '2026-10-01T00:00:00Z',
                    'created_at': '2026-10-01T00:00:00Z',
                    'last_accessed_at': null,
                    'metadata': null,
                    'buckets': null,
                  },
                ]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            if (request.url.path == '/rest/v1/canvas_snapshots' &&
                request.method == 'POST') {
              return http.Response('{}', 201, request: request);
            }
            throw StateError(
              'Unexpected snapshot asset request: ${request.url}',
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        final document = CanvasDocument(
          projectId: 'project-1',
          assets: DocumentAssetManifest(
            entries: {
              'hero': DocumentAsset(
                id: 'hero',
                kind: DocumentAssetKind.image,
                storage: DocumentAssetStorage.local,
                name: 'hero.png',
                mimeType: 'image/png',
                sizeBytes: bytes.length,
                durableReference: artifact.reference,
                createdAt: DateTime.utc(2026, 9, 25),
                updatedAt: DateTime.utc(2026, 9, 25),
              ),
            },
          ),
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        await SupabaseSyncService(
          client,
          artifactHydrator: TransientArtifactHydrator(
            imageArtifactStore: imageStore,
          ),
        ).syncDocumentSnapshot(document, expectedUserId: 'asset-user');

        expect(sawStorageList, isTrue);
        expect(sawMatchingDownload, isTrue);
        expect(
          requests.map((request) => request.url.path),
          containsAllInOrder([
            '/rest/v1/projects',
            '/rest/v1/canvas_snapshots',
            '/rest/v1/projects',
            '/storage/v1/object/assets/project-1/snapshots/4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6.png',
            '/storage/v1/object/list/assets',
            expectedPath,
            '/rest/v1/canvas_snapshots',
          ]),
        );
      },
    );

    test(
      'rejects an existing content-addressed snapshot asset with mismatched bytes',
      () async {
        final imageStore = MemoryImageArtifactStore();
        final bytes = Uint8List.fromList(const [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        final artifact = await imageStore.save(bytes, fileName: 'hero.png');
        final requests = <http.Request>[];
        var sawStorageList = false;
        var sawMismatchingDownload = false;
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/rest/v1/projects') {
              return http.Response(
                jsonEncode({'owner_id': 'asset-user'}),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            if (request.url.path == '/rest/v1/canvas_snapshots' &&
                request.method == 'GET') {
              return http.Response(
                '[]',
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            if (request.url.path.startsWith(
              '/storage/v1/object/assets/project-1/snapshots/',
            )) {
              if (request.method == 'POST') {
                expect(request.headers['x-upsert'], 'false');
                return http.Response(
                  jsonEncode({'message': 'The resource already exists'}),
                  400,
                  headers: {'content-type': 'application/json'},
                  request: request,
                );
              }
              if (request.method == 'GET') {
                expect(sawStorageList, isTrue);
                sawMismatchingDownload = true;
                return http.Response.bytes(
                  Uint8List.fromList(const [137, 80, 78, 71, 0, 0, 0, 0]),
                  200,
                  headers: {'content-type': 'image/png'},
                  request: request,
                );
              }
            }
            if (request.url.path == '/storage/v1/object/list/assets') {
              sawStorageList = true;
              return http.Response(
                jsonEncode([
                  {
                    'name':
                        '4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6.png',
                    'id': 'snapshot-asset',
                    'bucket_id': 'assets',
                    'owner': 'asset-user',
                    'updated_at': '2026-10-01T00:00:00Z',
                    'created_at': '2026-10-01T00:00:00Z',
                    'last_accessed_at': null,
                    'metadata': null,
                    'buckets': null,
                  },
                ]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            throw StateError(
              'Unexpected snapshot asset request: ${request.url}',
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        final document = CanvasDocument(
          projectId: 'project-1',
          assets: DocumentAssetManifest(
            entries: {
              'hero': DocumentAsset(
                id: 'hero',
                kind: DocumentAssetKind.image,
                storage: DocumentAssetStorage.local,
                name: 'hero.png',
                mimeType: 'image/png',
                sizeBytes: bytes.length,
                durableReference: artifact.reference,
                createdAt: DateTime.utc(2026, 9, 25),
                updatedAt: DateTime.utc(2026, 9, 25),
              ),
            },
          ),
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        await expectLater(
          SupabaseSyncService(
            client,
            artifactHydrator: TransientArtifactHydrator(
              imageArtifactStore: imageStore,
            ),
          ).syncDocumentSnapshot(document, expectedUserId: 'asset-user'),
          throwsA(isA<SyncException>()),
        );

        expect(sawStorageList, isTrue);
        expect(sawMismatchingDownload, isTrue);
        expect(
          requests.any(
            (request) =>
                request.url.path == '/rest/v1/canvas_snapshots' &&
                request.method != 'GET',
          ),
          isFalse,
        );
      },
    );

    test(
      'stages assets and recomputes the hash before publishing a snapshot',
      () async {
        final imageStore = MemoryImageArtifactStore();
        final bytes = Uint8List.fromList(const [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        final artifact = await imageStore.save(bytes, fileName: 'hero.png');
        var uploadObserved = false;
        var publishObserved = false;
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/rpc/can_edit_project') {
              expect(jsonDecode(request.body), {'p_project_id': 'project-1'});
              return http.Response('true', 200, request: request);
            }
            if (request.url.path ==
                '/storage/v1/object/assets/project-1/collaboration/hero-v1.png') {
              uploadObserved = true;
              return http.Response(
                jsonEncode({
                  'Key': 'assets/project-1/collaboration/hero-v1.png',
                }),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            if (request.url.path == '/rest/v1/rpc/publish_canvas_snapshot') {
              publishObserved = true;
              expect(uploadObserved, isTrue);
              final params = jsonDecode(request.body) as Map<String, dynamic>;
              final data = Map<String, dynamic>.from(
                params['p_document_data'] as Map,
              );
              final assets = Map<String, dynamic>.from(data['assets'] as Map);
              final item = (assets['items'] as List).single as Map;
              expect(
                item['durableReference'],
                'project-1/collaboration/hero-v1.png',
              );
              expect(item.containsKey('localPath'), isFalse);
              expect(item.containsKey('remoteUrl'), isFalse);
              final expectedHash = sha256
                  .convert(utf8.encode(jsonEncode(data)))
                  .toString();
              expect(params['p_content_hash'], expectedHash);
              return http.Response('{}', 200, request: request);
            }
            fail('Unexpected snapshot publication request: ${request.url}');
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        final document = CanvasDocument(
          projectId: 'project-1',
          assets: DocumentAssetManifest(
            entries: {
              'hero': DocumentAsset(
                id: 'hero',
                kind: DocumentAssetKind.image,
                storage: DocumentAssetStorage.local,
                name: 'hero.png',
                mimeType: 'image/png',
                sizeBytes: bytes.length,
                durableReference: artifact.reference,
                localPath: '/tmp/hero.png',
                createdAt: DateTime.utc(2026, 9, 25),
                updatedAt: DateTime.utc(2026, 9, 25),
              ),
            },
          ),
          updatedAt: DateTime.utc(2026, 9, 25),
        );
        final snapshot = PublishedSnapshot.publish(
          document,
          publishedBy: 'asset-user',
          access: PublishedAccess.private,
        );

        await SupabaseSyncService(
          client,
          artifactHydrator: TransientArtifactHydrator(
            imageArtifactStore: imageStore,
          ),
        ).publishCanvasSnapshot(snapshot);

        expect(uploadObserved, isTrue);
        expect(publishObserved, isTrue);
      },
    );

    test('fails closed when a local artifact cannot be staged', () async {
      final service = SupabaseSyncService(null);
      final asset = DocumentAsset(
        id: 'missing-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'missing.png',
        mimeType: 'image/png',
        durableReference: 'varian-image://missing-1',
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      );

      expect(
        await service.prepareCollaborativeAsset(
          projectId: 'project-1',
          asset: asset,
        ),
        isNull,
      );
    });

    test(
      'rejects a byte-backed asset without a durable source before publication',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            fail('An unportable asset must fail before any cloud request.');
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        final asset = DocumentAsset(
          id: 'unlinked-image',
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.local,
          name: 'unlinked.png',
          mimeType: 'image/png',
          createdAt: DateTime.utc(2026, 9, 25),
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        expect(
          await SupabaseSyncService(
            client,
          ).prepareCollaborativeAsset(projectId: 'project-1', asset: asset),
          isNull,
        );
      },
    );

    test(
      'rejects a local-path-only asset before collaborative publication',
      () async {
        final service = SupabaseSyncService(null);
        final asset = DocumentAsset(
          id: 'local-only-image',
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.local,
          name: 'local.png',
          mimeType: 'image/png',
          localPath: 'C:\\\\Users\\\\tester\\\\local.png',
          createdAt: DateTime.utc(2026, 9, 25),
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        expect(
          service.requiresCollaborativeAssetDeliveryForTesting(asset),
          isTrue,
        );
        expect(
          await service.prepareCollaborativeAsset(
            projectId: 'project-1',
            asset: asset,
          ),
          isNull,
        );
      },
    );

    test(
      'rejects a local-path-only asset even when its storage is remote',
      () async {
        final service = SupabaseSyncService(null);
        final asset = DocumentAsset(
          id: 'unlinked-remote-image',
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.remote,
          name: 'local.png',
          mimeType: 'image/png',
          localPath: '/tmp/local.png',
          createdAt: DateTime.utc(2026, 9, 25),
          updatedAt: DateTime.utc(2026, 9, 25),
        );

        expect(
          await service.prepareCollaborativeAsset(
            projectId: 'project-1',
            asset: asset,
          ),
          isNull,
        );
      },
    );

    test(
      'rejects invalid signed URL expiry without making a request',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            fail('Invalid expiry must fail before Storage HTTP.');
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        await expectLater(
          SupabaseSyncService(client).signedAssetUrl(
            bucket: 'assets',
            path: 'project-1/library/object.png',
            expiresIn: 59,
          ),
          throwsArgumentError,
        );
        await expectLater(
          SupabaseSyncService(client).signedAssetUrl(
            bucket: 'assets',
            path: 'project-1/library/object.png',
            expiresIn: 3601,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'keeps stable Storage paths separate from transient signed URLs',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          _testKey(),
          httpClient: MockClient((request) async {
            expect(
              request.url.path,
              '/storage/v1/object/sign/assets/project-1/library/object.png',
            );
            expect(request.url.query, isEmpty);
            return http.Response(
              jsonEncode({
                'signedURL':
                    '/object/sign/assets/project-1/library/object.png?token=redacted-test',
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await _authenticate(client);

        final service = SupabaseSyncService(client);
        final signed = await service.signedAssetUrl(
          bucket: 'assets',
          path: 'project-1/library/object.png',
        );
        expect(signed, startsWith('https://example.supabase.co/'));
        expect(signed, contains('?token=redacted-test'));
        expect('project-1/library/object.png', isNot(contains('?')));
      },
    );

    test('AIService sets isSimulated flag when API key is missing', () async {
      final aiService = AIService(
        const BackendConfig(),
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        MemoryImageArtifactStore(),
      );
      final now = DateTime.now();
      final job = AIJob(
        id: 'test_ai_job',
        projectId: 'proj_1',
        capability: AICapability.textToImage,
        prompt: 'Modernist villa with pool',
        createdAt: now,
        updatedAt: now,
      );

      final result = await aiService.executeJob(job, <CanvasNode>[]);
      expect(result.status, AIJobStatus.completed);
      expect(result.isSimulated, true);
      expect(result.resultAssetUrl, isNull);
      expect(result.resultImageUrls, isEmpty);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(
        validImageArtifactReference(result.resultArtifact?.reference),
        isNotNull,
      );
      expect(result.resultText, contains('Simulated'));
    });

    test('SyncState model tracks status and error messages', () {
      final initial = SyncState(lastSyncedAt: DateTime.now());
      expect(initial.status, SyncStatus.localOnly);

      final syncing = initial.copyWith(status: SyncStatus.syncing);
      expect(syncing.status, SyncStatus.syncing);

      final errorState = initial.copyWith(
        status: SyncStatus.error,
        errorMessage: 'Network timeout',
      );
      expect(errorState.status, SyncStatus.error);
      expect(errorState.errorMessage, 'Network timeout');
    });

    test('AssetPickerResult calculates previewUrl correctly', () {
      final remoteResult = AssetPickerResult(
        name: 'render.mp4',
        remoteUrl: 'https://cdn.supabase.co/assets/render.mp4',
      );
      expect(
        remoteResult.previewUrl,
        'https://cdn.supabase.co/assets/render.mp4',
      );

      final localResult = AssetPickerResult(
        name: 'render.mp4',
        path: '/local/path/render.mp4',
      );
      expect(localResult.previewUrl, '/local/path/render.mp4');
    });

    test(
      'AssetPickerResult keeps local previews out of durable references',
      () {
        final localResult = AssetPickerResult(
          name: 'mask.png',
          path: '/local/path/mask.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
        expect(localResult.durableReference, isNull);
        expect(localResult.previewUrl, '/local/path/mask.png');

        final previewOnlyResult = AssetPickerResult(
          name: 'mask.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
        expect(previewOnlyResult.durableReference, isNull);
        expect(
          previewOnlyResult.previewUrl,
          startsWith('data:image/png;base64,'),
        );
      },
    );
  });
}
