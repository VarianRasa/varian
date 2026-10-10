import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/artifacts/transient_artifact_hydrator.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/home/state/home_provider.dart';

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _authenticate(
  SupabaseClient client, {
  String userId = 'account-1',
}) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final token =
      '${_encodePart({'alg': 'HS256'})}.${_encodePart({'sub': userId, 'exp': expiration})}.signature';
  client.auth.stopAutoRefresh();
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': {
        'id': userId,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-01T00:00:00Z',
      },
    }),
  );
}

http.Response _jsonResponse(
  Object body, {
  required http.Request request,
  int statusCode = 200,
}) => http.Response(
  jsonEncode(body),
  statusCode,
  request: request,
  headers: {'content-type': 'application/json', 'content-range': '0-0/1'},
);

class _AdoptionRaceStorage extends LocalStorageService {
  final adoptionMetadataWriteStarted = Completer<void>();
  final releaseAdoptionMetadataWrite = Completer<void>();
  var gateNextAdoptionMetadataWrite = true;

  Future<void> _pauseAdoptionMetadataWrite(LocalProjectMetadata meta) async {
    if (!gateNextAdoptionMetadataWrite ||
        meta.id != 'local-project' ||
        meta.cloudOwnerId != 'account-1' ||
        !meta.cloudMetadataSyncPending) {
      return;
    }
    gateNextAdoptionMetadataWrite = false;
    adoptionMetadataWriteStarted.complete();
    await releaseAdoptionMetadataWrite.future;
  }

  @override
  Future<void> saveProjectMetadata(
    LocalProjectMetadata meta, {
    bool Function()? shouldWrite,
  }) async {
    await _pauseAdoptionMetadataWrite(meta);
    await super.saveProjectMetadata(meta, shouldWrite: shouldWrite);
  }

  @override
  Future<bool> saveProjectMetadataIfRevisionUnchanged(
    LocalProjectMetadata meta, {
    required int expectedRevision,
    bool Function()? shouldWrite,
  }) async {
    await _pauseAdoptionMetadataWrite(meta);
    return super.saveProjectMetadataIfRevisionUnchanged(
      meta,
      expectedRevision: expectedRevision,
      shouldWrite: shouldWrite,
    );
  }
}

class _AdoptionRaceSyncService extends SupabaseSyncService {
  _AdoptionRaceSyncService() : super(null);

  var failFirstMetadataSync = true;
  LocalProjectMetadata? syncedMetadata;

  @override
  Future<void> adoptDocumentSnapshot(
    CanvasDocument doc, {
    required String expectedUserId,
  }) async {}

  @override
  Future<void> verifyProjectOwnership(
    String projectId, {
    required String expectedUserId,
  }) async {}

  @override
  Future<void> syncProjectMetadata(
    LocalProjectMetadata metadata, {
    String? expectedUserId,
  }) async {
    if (failFirstMetadataSync) {
      failFirstMetadataSync = false;
      throw const SyncException('Metadata service unavailable.');
    }
    syncedMetadata = metadata;
  }

  @override
  Future<List<LocalProjectMetadata>> fetchOwnedProjectMetadata({
    String? expectedUserId,
  }) async => const [];
}

void main() {
  test(
    'loads only the signed-in owner catalog with cloud freshness and pin',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/rest/v1/projects' => _jsonResponse([
              {
                'id': 'project-1',
                'owner_id': 'account-1',
                'name': 'Cloud board',
                'created_at': '2026-10-01T08:00:00Z',
                'updated_at': '2026-10-03T08:00:00Z',
                'archived_at': null,
                'trashed_at': null,
              },
            ], request: request),
            '/rest/v1/canvas_snapshots' => _jsonResponse([
              {'project_id': 'project-1', 'updated_at': '2026-10-05T08:00:00Z'},
            ], request: request),
            '/rest/v1/user_project_preferences' => _jsonResponse([
              {'project_id': 'project-1', 'is_pinned': true},
            ], request: request),
            _ => throw StateError('Unexpected cloud request: ${request.url}'),
          };
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      final projects = await SupabaseSyncService(
        client,
      ).fetchOwnedProjectMetadata(expectedUserId: 'account-1');

      expect(projects, hasLength(1));
      expect(projects.single.name, 'Cloud board');
      expect(projects.single.isPinned, isTrue);
      expect(projects.single.cloudOwnerId, 'account-1');
      expect(projects.single.cloudUpdatedAt, DateTime.utc(2026, 10, 5, 8));
      expect(requests.first.url.queryParameters['owner_id'], 'eq.account-1');
    },
  );

  test(
    'syncs metadata and the account pin preference for an owned project',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/rest/v1/rpc/claim_canvas_project_ownership' => _jsonResponse({
              'id': 'project-1',
            }, request: request),
            '/rest/v1/projects' => _jsonResponse([
              {'id': 'project-1'},
            ], request: request),
            '/rest/v1/user_project_preferences' => _jsonResponse(
              {},
              request: request,
            ),
            _ => throw StateError('Unexpected cloud request: ${request.url}'),
          };
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final metadata = LocalProjectMetadata(
        id: 'project-1',
        name: 'My board',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 5),
        isPinned: true,
        status: ProjectStatus.archived,
        cloudOwnerId: 'account-1',
      );

      await SupabaseSyncService(
        client,
      ).syncProjectMetadata(metadata, expectedUserId: 'account-1');

      expect(
        requests.map((request) => request.url.path),
        containsAll(['/rest/v1/projects', '/rest/v1/user_project_preferences']),
      );
      expect(
        requests.any(
          (request) =>
              request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership',
        ),
        isFalse,
      );
      final projectUpdate = requests.firstWhere(
        (request) => request.url.path == '/rest/v1/projects',
      );
      final projectBody =
          jsonDecode(projectUpdate.body) as Map<String, dynamic>;
      expect(projectBody['name'], 'My board');
      expect(projectBody['archived_at'], isNotNull);
      expect(projectBody['updated_by'], 'account-1');
      final pinUpdate = requests.firstWhere(
        (request) => request.url.path == '/rest/v1/user_project_preferences',
      );
      final pinBody = jsonDecode(pinUpdate.body) as Map<String, dynamic>;
      expect(pinBody['user_id'], 'account-1');
      expect(pinBody['project_id'], 'project-1');
      expect(pinBody['is_pinned'], isTrue);
      expect(DateTime.tryParse(pinBody['updated_at'] as String), isNotNull);
    },
  );

  test(
    'deletes a cloud project only through the authenticated owner filter',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return _jsonResponse([], request: request);
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      await SupabaseSyncService(
        client,
      ).deleteOwnedProject('project-1', expectedUserId: 'account-1');

      final deleteRequest = requests.single;
      expect(deleteRequest.method, 'DELETE');
      expect(deleteRequest.url.path, '/rest/v1/projects');
      expect(deleteRequest.url.queryParameters['id'], 'eq.project-1');
      expect(deleteRequest.url.queryParameters['owner_id'], 'eq.account-1');
    },
  );

  test(
    'purging a cloud-owned project never mutates the cloud catalog',
    () async {
      final metadata = LocalProjectMetadata(
        id: 'project-1',
        name: 'Cloud board',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 3),
        cloudOwnerId: 'account-1',
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/rest/v1/projects' => _jsonResponse([
              {
                'id': 'project-1',
                'owner_id': 'account-1',
                'name': 'Cloud board',
                'created_at': '2026-10-01T00:00:00Z',
                'updated_at': '2026-10-03T00:00:00Z',
                'archived_at': null,
                'trashed_at': null,
              },
            ], request: request),
            '/rest/v1/canvas_snapshots' => _jsonResponse([], request: request),
            '/rest/v1/user_project_preferences' => _jsonResponse(
              [],
              request: request,
            ),
            _ => throw StateError('Unexpected cloud request: ${request.url}'),
          };
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(homeProjectsProvider.notifier);
      await notifier.purgeProject('project-1');

      expect(notifier.state.value!.single.id, 'project-1');
      expect(notifier.state.value!.single.cloudOwnerId, 'account-1');
      expect((await storage.getProjects()).single.id, 'project-1');
      expect(requests, isNotEmpty);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(
        requests.any(
          (request) =>
              request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership',
        ),
        isFalse,
      );
    },
  );

  test(
    'adopts a local document only through the explicit adoption API',
    () async {
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([
          LocalProjectMetadata(
            id: 'local-project',
            name: 'Adopted local board',
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
            isPinned: true,
            status: ProjectStatus.archived,
          ).toJson(),
        ]),
      });
      final requests = <http.Request>[];
      var ownershipClaimed = false;
      var ownershipClaimCount = 0;
      var failMetadataSync = true;
      var cloudName = 'Cloud board';
      var cloudArchived = false;
      var cloudPinned = false;
      Map<String, dynamic>? storedSnapshot;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects') {
            if (request.url.queryParameters['select'] == 'owner_id') {
              return _jsonResponse({
                'owner_id': ownershipClaimed ? 'account-1' : null,
              }, request: request);
            }
            if (request.method == 'PATCH') {
              if (failMetadataSync) {
                return http.Response(
                  jsonEncode({'message': 'Cloud unavailable', 'code': 'XX000'}),
                  500,
                  request: request,
                  headers: {'content-type': 'application/json'},
                );
              }
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              cloudName = body['name'] as String;
              cloudArchived = body['archived_at'] != null;
              return _jsonResponse([
                {'id': 'local-project'},
              ], request: request);
            }
            if (request.method != 'GET') {
              throw StateError('Unexpected project mutation: ${request.url}');
            }
            return _jsonResponse(
              ownershipClaimed
                  ? [
                      {
                        'id': 'local-project',
                        'owner_id': 'account-1',
                        'name': cloudName,
                        'created_at': '2026-10-01T00:00:00Z',
                        'updated_at': '2026-10-06T00:00:00Z',
                        'archived_at': cloudArchived
                            ? '2026-10-06T00:00:00Z'
                            : null,
                        'trashed_at': null,
                      },
                    ]
                  : const [],
              request: request,
            );
          }
          if (request.url.path ==
              '/rest/v1/rpc/claim_canvas_project_ownership') {
            ownershipClaimed = true;
            ownershipClaimCount++;
            return _jsonResponse({'id': 'local-project'}, request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            if (request.method == 'GET') {
              final selectedColumns = request.url.queryParameters['select'];
              if (selectedColumns ==
                      'project_id,updated_at,revision,document_data' ||
                  selectedColumns == 'project_id,updated_at,revision') {
                return _jsonResponse(
                  storedSnapshot ?? const [],
                  request: request,
                );
              }
              return _jsonResponse(
                storedSnapshot == null
                    ? [
                        {
                          'project_id': 'local-project',
                          'updated_at': '2026-10-06T00:00:00Z',
                        },
                      ]
                    : [
                        {
                          'project_id': 'local-project',
                          'updated_at': storedSnapshot!['updated_at'],
                        },
                      ],
                request: request,
              );
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            storedSnapshot = {
              'project_id': body['project_id'],
              'updated_at': body['updated_at'],
              'revision': body['revision'],
              'document_data': body['document_data'],
            };
            if (storedSnapshot != null && body['revision'] == 0) {
              return http.Response(
                jsonEncode({'message': 'Response lost after commit'}),
                500,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('', 201, request: request);
          }
          if (request.url.path == '/rest/v1/user_project_preferences') {
            if (request.method == 'GET') {
              return _jsonResponse(
                cloudPinned
                    ? [
                        {'project_id': 'local-project', 'is_pinned': true},
                      ]
                    : const [],
                request: request,
              );
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            cloudPinned = body['is_pinned'] as bool;
            return http.Response('', 201, request: request);
          }
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final durableStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(durableStore.close);
      await durableStore.saveCanvasDocument(
        CanvasDocument(
          projectId: 'local-project',
          updatedAt: DateTime.utc(2026, 10, 6),
        ),
      );
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          durableProjectStoreProvider.overrideWithValue(durableStore),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
          authUserProvider.overrideWith(
            (ref) => Stream.value(client.auth.currentUser),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(homeProjectsProvider.notifier);
      await expectLater(
        notifier.adoptProjectToCloud(
          'local-project',
          expectedAccountId: 'account-1',
        ),
        throwsA(isA<SyncException>()),
      );
      final claimedButPending = (await storage.getProjects()).single;
      expect(claimedButPending.cloudOwnerId, 'account-1');
      expect(claimedButPending.name, 'Adopted local board');
      expect(claimedButPending.isPinned, isTrue);
      expect(claimedButPending.status, ProjectStatus.archived);
      expect(claimedButPending.cloudMetadataSyncPending, isTrue);

      failMetadataSync = false;
      await notifier.loadProjects();

      expect(
        requests.map((request) => request.url.path),
        contains('/rest/v1/rpc/claim_canvas_project_ownership'),
      );
      expect(ownershipClaimCount, 1);
      expect(
        requests
            .where(
              (request) =>
                  request.url.path == '/rest/v1/canvas_snapshots' &&
                  request.method == 'GET' &&
                  request.url.queryParameters['select'] ==
                      'project_id,updated_at,revision,document_data',
            )
            .length,
        3,
      );
      final storedMetadata = (await storage.getProjects()).single;
      expect(storedMetadata.cloudOwnerId, 'account-1');
      expect(storedMetadata.cloudMetadataSyncPending, isFalse);
      expect(cloudName, 'Adopted local board');
      expect(cloudArchived, isTrue);
      expect(cloudPinned, isTrue);
      expect(
        requests
            .where(
              (request) =>
                  request.url.path == '/rest/v1/projects' &&
                  request.method == 'PATCH',
            )
            .length,
        2,
      );
      expect(
        (await durableStore.loadCanvasDocument('local-project'))?.updatedAt,
        DateTime.utc(2026, 10, 6),
      );
    },
  );

  test(
    'preserves a concurrent local rename during explicit adoption metadata save',
    () async {
      final original = LocalProjectMetadata(
        id: 'local-project',
        name: 'Local board',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([original.toJson()]),
      });
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final storage = _AdoptionRaceStorage();
      final sync = _AdoptionRaceSyncService();
      final durableStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(durableStore.close);
      await durableStore.saveCanvasDocument(
        CanvasDocument(
          projectId: original.id,
          updatedAt: DateTime.utc(2026, 10, 6),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          durableProjectStoreProvider.overrideWithValue(durableStore),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(sync),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(homeProjectsProvider.notifier);

      final adoption = notifier.adoptProjectToCloud(
        original.id,
        expectedAccountId: 'account-1',
      );
      await storage.adoptionMetadataWriteStarted.future;
      await notifier.renameProject(original.id, 'Concurrent local rename');
      storage.releaseAdoptionMetadataWrite.complete();

      await expectLater(adoption, throwsA(isA<SyncException>()));

      final afterConflict = (await storage.getProjects()).single;
      expect(afterConflict.name, 'Concurrent local rename');
      expect(afterConflict.cloudOwnerId, 'account-1');
      expect(afterConflict.cloudMetadataSyncPending, isTrue);
      expect(afterConflict.cloudAdoptionPendingAccountId, 'account-1');

      sync.failFirstMetadataSync = false;
      await notifier.loadProjects();

      final recovered = (await storage.getProjects()).single;
      expect(recovered.name, 'Concurrent local rename');
      expect(recovered.cloudOwnerId, 'account-1');
      expect(recovered.cloudMetadataSyncPending, isFalse);
      expect(recovered.cloudAdoptionPendingAccountId, isNull);
      expect(sync.syncedMetadata?.name, 'Concurrent local rename');
    },
  );

  test('retries adoption after a committed snapshot response is lost', () async {
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([
        LocalProjectMetadata(
          id: 'local-project',
          name: 'Local board',
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
        ).toJson(),
      ]),
    });
    final requests = <http.Request>[];
    Map<String, dynamic>? storedSnapshot;
    var ownershipClaimed = false;
    var ownershipClaimCount = 0;
    var snapshotWriteCount = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/projects') {
          if (request.method == 'PATCH') {
            return _jsonResponse([
              {'id': 'local-project'},
            ], request: request);
          }
          final selection = request.url.queryParameters['select'];
          if (selection == 'owner_id') {
            return _jsonResponse({
              'owner_id': ownershipClaimed ? 'account-1' : null,
            }, request: request);
          }
          if (selection ==
              'id,owner_id,name,created_at,updated_at,archived_at,trashed_at') {
            return _jsonResponse(
              ownershipClaimed
                  ? [
                      {
                        'id': 'local-project',
                        'owner_id': 'account-1',
                        'name': 'Local board',
                        'created_at': '2026-10-01T00:00:00Z',
                        'updated_at': '2026-10-06T00:00:00Z',
                        'archived_at': null,
                        'trashed_at': null,
                      },
                    ]
                  : const [],
              request: request,
            );
          }
        }
        if (request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership') {
          ownershipClaimed = true;
          ownershipClaimCount++;
          return _jsonResponse({'id': 'local-project'}, request: request);
        }
        if (request.url.path == '/rest/v1/canvas_snapshots') {
          if (request.method == 'GET') {
            if (request.url.queryParameters['select'] ==
                'project_id,updated_at,revision,document_data') {
              return _jsonResponse(
                storedSnapshot ?? const [],
                request: request,
              );
            }
            if (request.url.queryParameters['select'] ==
                'project_id,updated_at') {
              return _jsonResponse(
                storedSnapshot == null
                    ? const []
                    : [
                        {
                          'project_id': 'local-project',
                          'updated_at': storedSnapshot!['updated_at'],
                        },
                      ],
                request: request,
              );
            }
          }
          if (request.method == 'POST') {
            snapshotWriteCount++;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            storedSnapshot = {
              'project_id': body['project_id'],
              'updated_at': body['updated_at'],
              'revision': body['revision'],
              'document_data': body['document_data'],
            };
            if (snapshotWriteCount == 1) {
              return http.Response(
                jsonEncode({'message': 'Response lost after commit'}),
                500,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('', 201, request: request);
          }
        }
        if (request.url.path == '/rest/v1/user_project_preferences') {
          return _jsonResponse(const [], request: request);
        }
        throw StateError('Unexpected adoption request: ${request.url}');
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final durableStore = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    addTearDown(durableStore.close);
    await durableStore.saveCanvasDocument(
      CanvasDocument(
        projectId: 'local-project',
        updatedAt: DateTime.utc(2026, 10, 6),
      ),
    );
    final storage = LocalStorageService();
    final container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        durableProjectStoreProvider.overrideWithValue(durableStore),
        supabaseClientProvider.overrideWithValue(client),
        supabaseSyncServiceProvider.overrideWithValue(
          SupabaseSyncService(client),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(homeProjectsProvider.notifier)
        .adoptProjectToCloud('local-project', expectedAccountId: 'account-1');

    expect(ownershipClaimCount, 1);
    expect(snapshotWriteCount, 1);
    expect(storedSnapshot, isNotNull);
    expect((await storage.getProjects()).single.cloudOwnerId, 'account-1');
    expect(
      (await durableStore.loadCanvasDocument('local-project'))?.updatedAt,
      DateTime.utc(2026, 10, 6),
    );
    expect(
      requests.where(
        (request) =>
            request.url.path == '/rest/v1/canvas_snapshots' &&
            request.method == 'GET' &&
            request.url.queryParameters['select'] ==
                'project_id,updated_at,revision,document_data',
      ),
      hasLength(2),
    );
  });

  test(
    'claims project ownership before staging adopted image assets',
    () async {
      final imageStore = MemoryImageArtifactStore();
      final bytes = Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]);
      final artifact = await imageStore.save(bytes, fileName: 'local.png');
      final requests = <http.Request>[];
      var ownershipClaimed = false;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects') {
            expect(request.method, 'GET');
            if (request.url.queryParameters['select'] == 'owner_id') {
              return _jsonResponse({
                'owner_id': ownershipClaimed ? 'account-1' : null,
              }, request: request);
            }
            if (request.url.queryParameters['select'] == 'id,owner_id') {
              return _jsonResponse({
                'id': 'local-project',
                'owner_id': ownershipClaimed ? 'account-1' : null,
              }, request: request);
            }
            fail('Unexpected project request: ${request.url}');
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            if (request.method == 'GET') {
              expect(
                request.url.queryParameters['select'],
                'project_id,updated_at,revision,document_data',
              );
              return _jsonResponse(const [], request: request);
            }
            expect(request.method, 'POST');
            expect(ownershipClaimed, isTrue);
            expect(jsonDecode(request.body)['revision'], 0);
            return http.Response('', 201, request: request);
          }
          if (request.url.path ==
              '/rest/v1/rpc/claim_canvas_project_ownership') {
            expect(request.method, 'POST');
            ownershipClaimed = true;
            return _jsonResponse({'id': 'local-project'}, request: request);
          }
          if (request.url.path == '/rest/v1/rpc/can_edit_project') {
            expect(ownershipClaimed, isTrue);
            return _jsonResponse(true, request: request);
          }
          if (request.url.path.startsWith(
            '/storage/v1/object/assets/local-project/snapshots/',
          )) {
            expect(ownershipClaimed, isTrue);
            expect(request.method, 'POST');
            expect(request.headers['x-upsert'], 'false');
            return http.Response(
              jsonEncode({'Key': request.url.pathSegments.skip(4).join('/')}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          fail('Unexpected adoption request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

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
              localPath: '/tmp/local.png',
              createdAt: DateTime.utc(2026, 10, 1),
              updatedAt: DateTime.utc(2026, 10, 1),
            ),
          },
        ),
        updatedAt: DateTime.utc(2026, 10, 1),
      );

      await SupabaseSyncService(
        client,
        artifactHydrator: TransientArtifactHydrator(
          imageArtifactStore: imageStore,
        ),
      ).adoptDocumentSnapshot(document, expectedUserId: 'account-1');

      expect(
        requests.map((request) {
          if (request.url.path == '/rest/v1/projects') return 'owner lookup';
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            return request.method == 'GET'
                ? 'snapshot preflight'
                : 'snapshot insert';
          }
          if (request.url.path ==
              '/rest/v1/rpc/claim_canvas_project_ownership') {
            return 'ownership claim';
          }
          if (request.url.path == '/rest/v1/rpc/can_edit_project') {
            return 'editor authorization';
          }
          if (request.url.path.startsWith('/storage/v1/object/')) {
            return 'Storage upload';
          }
          return request.url.path;
        }),
        [
          'owner lookup',
          'snapshot preflight',
          'ownership claim',
          'owner lookup',
          'owner lookup',
          'Storage upload',
          'snapshot insert',
        ],
      );
    },
  );

  test('retries adoption of staged image content without reuploading', () async {
    final imageStore = MemoryImageArtifactStore();
    final bytes = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/2ioAAAAASUVORK5CYII=',
      ),
    );
    final artifact = await imageStore.save(bytes, fileName: 'local.png');
    final localDocument = CanvasDocument(
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
            localPath: '/tmp/local.png',
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        },
      ),
      updatedAt: DateTime.utc(2026, 10, 1),
    );
    final requests = <http.Request>[];
    Map<String, dynamic>? storedSnapshot;
    var ownershipClaimed = false;
    var ownershipClaimCount = 0;
    var storageUploadCount = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/projects') {
          if (request.url.queryParameters['select'] == 'owner_id') {
            return _jsonResponse({
              'owner_id': ownershipClaimed ? 'account-1' : null,
            }, request: request);
          }
          fail('Unexpected project catalog request: ${request.url}');
        }
        if (request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership') {
          ownershipClaimed = true;
          ownershipClaimCount++;
          return _jsonResponse({'id': 'local-project'}, request: request);
        }
        if (request.url.path == '/rest/v1/rpc/can_edit_project') {
          expect(ownershipClaimed, isTrue);
          return _jsonResponse(true, request: request);
        }
        if (request.url.path.startsWith(
          '/storage/v1/object/assets/local-project/snapshots/',
        )) {
          storageUploadCount++;
          expect(request.method, 'POST');
          expect(request.headers['x-upsert'], 'false');
          return http.Response(
            jsonEncode({'Key': request.url.pathSegments.skip(4).join('/')}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path == '/rest/v1/canvas_snapshots') {
          if (request.method == 'GET') {
            return _jsonResponse(
              storedSnapshot == null
                  ? const []
                  : {
                      'project_id': 'local-project',
                      'updated_at': '2026-10-06T00:00:00Z',
                      'revision': 0,
                      'document_data': storedSnapshot,
                    },
              request: request,
            );
          }
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            storedSnapshot = Map<String, dynamic>.from(
              body['document_data'] as Map,
            );
            return http.Response('', 201, request: request);
          }
          fail('Unexpected snapshot mutation: ${request.url}');
        }
        fail('Unexpected adoption request: ${request.url}');
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

    await service.adoptDocumentSnapshot(
      localDocument,
      expectedUserId: 'account-1',
    );
    final firstAttemptRequests = requests.length;
    expect(storedSnapshot, isNotNull);
    expect(
      requests.where(
        (request) => request.url.path.startsWith('/storage/v1/object/'),
      ),
      hasLength(1),
    );

    await service.adoptDocumentSnapshot(
      localDocument,
      expectedUserId: 'account-1',
    );

    expect(requests.length, greaterThan(firstAttemptRequests));
    expect(
      requests
          .skip(firstAttemptRequests)
          .where(
            (request) => request.url.path.startsWith('/storage/v1/object/'),
          ),
      isEmpty,
    );
    expect(
      requests
          .skip(firstAttemptRequests)
          .where(
            (request) =>
                request.url.path == '/rest/v1/canvas_snapshots' &&
                request.method != 'GET',
          ),
      isEmpty,
    );
    expect(
      requests
          .skip(firstAttemptRequests)
          .where(
            (request) =>
                request.url.path ==
                '/rest/v1/rpc/claim_canvas_project_ownership',
          ),
      isEmpty,
    );
    expect(ownershipClaimCount, 1);
    expect(storageUploadCount, 1);
    expect(storedSnapshot, isNotNull);
    final storedAsset = DocumentAssetManifest.fromJson(
      storedSnapshot!['assets'],
    )['local-image'];
    expect(
      storedAsset?.durableReference,
      startsWith('local-project/snapshots/'),
    );
    expect(storedAsset?.storage, DocumentAssetStorage.remote);
  });

  test('rejects adoption when a newer cloud snapshot differs', () async {
    final localDocument = CanvasDocument(
      projectId: 'local-project',
      metadata: const {'source': 'local'},
      updatedAt: DateTime.utc(2026, 10, 5),
    );
    var ownershipClaimed = false;
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/projects') {
          if (request.url.queryParameters['select'] == 'owner_id') {
            return _jsonResponse({
              'owner_id': ownershipClaimed ? 'account-1' : null,
            }, request: request);
          }
          throw StateError('Unexpected projects request: ${request.url}');
        }
        if (request.url.path == '/rest/v1/canvas_snapshots') {
          expect(request.method, 'GET');
          return _jsonResponse({
            'project_id': 'local-project',
            'updated_at': '2026-10-06T00:00:00Z',
            'document_data': CanvasDocument(
              projectId: 'local-project',
              metadata: const {'source': 'cloud'},
              updatedAt: DateTime.utc(2026, 10, 6),
            ).toPersistenceJson(),
          }, request: request);
        }
        if (request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership') {
          ownershipClaimed = true;
          return _jsonResponse({'id': 'local-project'}, request: request);
        }
        throw StateError('Unexpected cloud request: ${request.url}');
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    await expectLater(
      SupabaseSyncService(
        client,
      ).adoptDocumentSnapshot(localDocument, expectedUserId: 'account-1'),
      throwsA(
        isA<SyncException>().having(
          (error) => error.message,
          'message',
          contains('A cloud snapshot already exists with different content'),
        ),
      ),
    );

    expect(
      requests.any(
        (request) =>
            request.url.path == '/rest/v1/canvas_snapshots' &&
            request.method == 'GET',
      ),
      isTrue,
    );
    expect(ownershipClaimed, isFalse);
    expect(
      requests.where(
        (request) =>
            request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership',
      ),
      isEmpty,
    );
    expect(
      requests.where(
        (request) =>
            request.url.path == '/rest/v1/canvas_snapshots' &&
            request.method != 'GET',
      ),
      isEmpty,
    );
  });

  test(
    'accepts an idempotent adoption retry for matching cloud content',
    () async {
      final localDocument = CanvasDocument(
        projectId: 'local-project',
        metadata: const {'source': 'local'},
        updatedAt: DateTime.utc(2026, 10, 5),
      );
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects') {
            expect(request.method, 'GET');
            return _jsonResponse({'owner_id': 'account-1'}, request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            expect(request.method, 'GET');
            return _jsonResponse({
              'project_id': 'local-project',
              'updated_at': '2026-10-06T00:00:00Z',
              'document_data': localDocument.toPersistenceJson(),
            }, request: request);
          }
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      await SupabaseSyncService(
        client,
      ).adoptDocumentSnapshot(localDocument, expectedUserId: 'account-1');

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
              request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership',
        ),
        isFalse,
      );
    },
  );

  test(
    'rejects idempotent adoption when a local snapshot asset is unresolved',
    () async {
      final metadata = LocalProjectMetadata(
        id: 'local-project',
        name: 'Local board',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      );
      final localDocument = CanvasDocument(
        projectId: metadata.id,
        assets: DocumentAssetManifest(
          entries: {
            'missing-image': DocumentAsset(
              id: 'missing-image',
              kind: DocumentAssetKind.image,
              storage: DocumentAssetStorage.local,
              name: 'missing.png',
              mimeType: 'image/png',
              durableReference: 'varian-image://missing-hero',
              createdAt: DateTime.utc(2026, 10, 1),
              updatedAt: DateTime.utc(2026, 10, 1),
            ),
          },
        ),
        updatedAt: DateTime.utc(2026, 10, 1),
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects' &&
              request.url.queryParameters['select'] == 'owner_id') {
            return _jsonResponse({'owner_id': null}, request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            expect(request.method, 'GET');
            return _jsonResponse({
              'project_id': metadata.id,
              'updated_at': '2026-10-02T00:00:00Z',
              'revision': 0,
              'document_data': localDocument.toPersistenceJson(),
            }, request: request);
          }
          fail(
            'Unresolved local asset must not reach cloud mutation: ${request.url}',
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final durableStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(durableStore.close);
      await durableStore.saveCanvasDocument(localDocument);
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          durableProjectStoreProvider.overrideWithValue(durableStore),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(
              client,
              artifactHydrator: TransientArtifactHydrator(
                imageArtifactStore: MemoryImageArtifactStore(),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(homeProjectsProvider.notifier)
            .adoptProjectToCloud(metadata.id, expectedAccountId: 'account-1'),
        throwsA(isA<SyncException>()),
      );

      expect((await storage.getProjects()).single.cloudOwnerId, isNull);
      expect(
        (await durableStore.loadCanvasDocument(
          metadata.id,
        ))?.toPersistenceJson(),
        localDocument.toPersistenceJson(),
      );
      expect(
        requests.any(
          (request) =>
              request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership',
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
    },
  );

  test(
    'increments the observed revision after a successful snapshot CAS',
    () async {
      final document = CanvasDocument(
        projectId: 'local-project',
        metadata: const {'source': 'local'},
        updatedAt: DateTime.utc(2026, 10, 6),
      );
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects') {
            return _jsonResponse({'owner_id': 'account-1'}, request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'GET') {
            return _jsonResponse({
              'project_id': document.projectId,
              'updated_at': '2026-10-04T00:00:00Z',
              'revision': 7,
            }, request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'PATCH') {
            expect(request.url.queryParameters['revision'], 'eq.7');
            expect(
              request.url.queryParameters['updated_at'],
              'eq.2026-10-04T00:00:00Z',
            );
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['revision'], 8);
            expect(body['document_data'], document.toPersistenceJson());
            return _jsonResponse([
              {'project_id': document.projectId, 'revision': 8},
            ], request: request);
          }
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      await SupabaseSyncService(
        client,
      ).syncDocumentSnapshot(document, expectedUserId: 'account-1');

      expect(
        requests.where(
          (request) =>
              request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'PATCH',
        ),
        hasLength(1),
      );
    },
  );

  test('does not replace a snapshot inserted by a competing writer', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/projects') {
          return _jsonResponse({'owner_id': 'account-1'}, request: request);
        }
        if (request.url.path == '/rest/v1/canvas_snapshots' &&
            request.method == 'GET') {
          return _jsonResponse(const [], request: request);
        }
        if (request.url.path == '/rest/v1/canvas_snapshots' &&
            request.method == 'POST') {
          return _jsonResponse(
            {'code': '23505', 'message': 'duplicate snapshot'},
            request: request,
            statusCode: 409,
          );
        }
        throw StateError('Unexpected cloud request: ${request.url}');
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    await expectLater(
      SupabaseSyncService(client).syncDocumentSnapshot(
        CanvasDocument(
          projectId: 'local-project',
          metadata: const {'source': 'local'},
          updatedAt: DateTime.utc(2026, 10, 6),
        ),
        expectedUserId: 'account-1',
      ),
      throwsA(isA<SyncException>()),
    );

    expect(
      requests.where(
        (request) =>
            request.url.path == '/rest/v1/canvas_snapshots' &&
            request.method == 'POST',
      ),
      hasLength(1),
    );
    expect(
      requests.any(
        (request) =>
            request.url.path == '/rest/v1/canvas_snapshots' &&
            request.method == 'PATCH',
      ),
      isFalse,
    );
  });

  test(
    'rejects ordinary snapshot sync when a competing update wins CAS',
    () async {
      final localDocument = CanvasDocument(
        projectId: 'local-project',
        metadata: const {'source': 'local'},
        updatedAt: DateTime.utc(2026, 10, 6),
      );
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects') {
            expect(request.method, 'GET');
            return _jsonResponse({'owner_id': 'account-1'}, request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            if (request.method == 'GET') {
              expect(
                request.url.queryParameters['select'],
                'project_id,updated_at,revision',
              );
              return _jsonResponse({
                'project_id': 'local-project',
                'updated_at': '2026-10-04T00:00:00Z',
                'revision': 7,
              }, request: request);
            }
            expect(request.method, 'PATCH');
            expect(request.url.queryParameters['revision'], 'eq.7');
            expect(
              request.url.queryParameters['updated_at'],
              'eq.2026-10-04T00:00:00Z',
            );
            expect(
              request.url.queryParameters['project_id'],
              'eq.local-project',
            );
            return _jsonResponse(const [], request: request);
          }
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);

      await expectLater(
        SupabaseSyncService(
          client,
        ).syncDocumentSnapshot(localDocument, expectedUserId: 'account-1'),
        throwsA(
          isA<SyncException>().having(
            (error) => error.message,
            'message',
            contains('cloud snapshot changed during sync'),
          ),
        ),
      );

      expect(
        requests.where(
          (request) =>
              request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'PATCH',
        ),
        hasLength(1),
      );
      expect(
        requests.any(
          (request) =>
              request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership',
        ),
        isFalse,
      );
    },
  );

  test(
    'rejects adoption when the confirmed account is no longer active',
    () async {
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([
          LocalProjectMetadata(
            id: 'local-project',
            name: 'Local board',
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
          ).toJson(),
        ]),
      });
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          fail('Account mismatch must fail before cloud requests.');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          supabaseClientProvider.overrideWithValue(client),
          authUserProvider.overrideWith((ref) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(homeProjectsProvider.notifier)
            .adoptProjectToCloud(
              'local-project',
              expectedAccountId: 'different-account',
            ),
        throwsA(isA<SyncException>()),
      );
      expect((await storage.getProjects()).single.cloudOwnerId, isNull);
    },
  );

  test(
    'catalog refresh preserves rename and pin intent made while cloud is loading',
    () async {
      final metadata = LocalProjectMetadata(
        id: 'project-1',
        name: 'Old name',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
        cloudOwnerId: 'account-1',
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final catalogCompleter = Completer<void>();
      final delayedCatalog = Completer<http.Response>();
      final metadataPatchBodies = <Map<String, dynamic>>[];
      late http.Request catalogRequest;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'GET' &&
              request.url.queryParameters['select'] != 'owner_id') {
            catalogRequest = request;
            catalogCompleter.complete();
            return delayedCatalog.future;
          }
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'GET' &&
              request.url.queryParameters['select'] == 'owner_id') {
            return _jsonResponse({'owner_id': 'account-1'}, request: request);
          }
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'PATCH') {
            metadataPatchBodies.add(
              Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            );
            return http.Response(
              jsonEncode({'message': 'Cloud unavailable', 'code': 'XX000'}),
              500,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            return _jsonResponse([
              {'project_id': 'project-1', 'updated_at': '2026-10-03T00:00:00Z'},
            ], request: request);
          }
          if (request.url.path == '/rest/v1/user_project_preferences') {
            return _jsonResponse(const [], request: request);
          }
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(homeProjectsProvider.notifier);

      final refresh = notifier.loadProjects();
      await catalogCompleter.future;
      await expectLater(
        notifier.renameProject('project-1', 'Renamed during refresh'),
        throwsA(isA<SyncException>()),
      );
      await expectLater(
        notifier.togglePinned('project-1'),
        throwsA(isA<SyncException>()),
      );
      delayedCatalog.complete(
        _jsonResponse([
          {
            'id': 'project-1',
            'owner_id': 'account-1',
            'name': 'Old name',
            'created_at': '2026-10-01T00:00:00Z',
            'updated_at': '2026-10-02T00:00:00Z',
            'archived_at': null,
            'trashed_at': null,
          },
        ], request: catalogRequest),
      );
      await refresh;

      final refreshed = notifier.state.value!.single;
      final cached = (await storage.getProjects()).single;
      for (final project in [refreshed, cached]) {
        expect(project.name, 'Renamed during refresh');
        expect(project.isPinned, isTrue);
        expect(project.cloudMetadataSyncPending, isTrue);
      }
      expect(metadataPatchBodies, hasLength(3));
      expect(metadataPatchBodies.last['name'], 'Renamed during refresh');
      expect(
        metadataPatchBodies.last['updated_at'],
        isNot('2026-10-02T00:00:00.000Z'),
      );
    },
  );

  test(
    'stale catalog response cannot overwrite successfully synced local metadata edits',
    () async {
      final metadata = LocalProjectMetadata(
        id: 'project-1',
        name: 'Old name',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
        thumbnailPath: 'local-thumbnail.png',
        cloudOwnerId: 'account-1',
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final catalogStarted = Completer<void>();
      final delayedCatalog = Completer<http.Response>();
      var shouldDelayCatalog = true;
      late http.Request catalogRequest;
      final metadataPatchBodies = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'GET' &&
              request.url.queryParameters['select'] != 'owner_id' &&
              shouldDelayCatalog) {
            shouldDelayCatalog = false;
            catalogRequest = request;
            catalogStarted.complete();
            return delayedCatalog.future;
          }
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'GET' &&
              request.url.queryParameters['select'] == 'owner_id') {
            return _jsonResponse({'owner_id': 'account-1'}, request: request);
          }
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'PATCH') {
            metadataPatchBodies.add(
              Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            );
            return _jsonResponse([
              {'id': 'project-1'},
            ], request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            return _jsonResponse([
              {'project_id': 'project-1', 'updated_at': '2026-10-03T00:00:00Z'},
            ], request: request);
          }
          if (request.url.path == '/rest/v1/user_project_preferences') {
            if (request.method == 'GET') {
              // This refresh's catalog snapshot predates the local pin edit.
              return _jsonResponse(const [], request: request);
            }
            return http.Response('', 201, request: request);
          }
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(homeProjectsProvider.notifier);

      final refresh = notifier.loadProjects();
      await catalogStarted.future;
      await notifier.renameProject('project-1', 'Renamed while refreshing');
      final successfullySynced = (await storage.getProjects()).single;
      expect(successfullySynced.cloudMetadataSyncPending, isFalse);
      await storage.saveProjectMetadata(
        successfullySynced.copyWith(thumbnailPath: 'edited-thumbnail.png'),
      );
      expect(metadataPatchBodies, hasLength(1));

      delayedCatalog.complete(
        _jsonResponse([
          {
            'id': 'project-1',
            'owner_id': 'account-1',
            'name': 'Old name',
            'created_at': '2026-10-01T00:00:00Z',
            'updated_at': '2026-10-02T00:00:00Z',
            'archived_at': null,
            'trashed_at': null,
          },
        ], request: catalogRequest),
      );
      await refresh;

      final refreshed = notifier.state.value!.single;
      final cached = (await storage.getProjects()).single;
      for (final project in [refreshed, cached]) {
        expect(project.name, 'Renamed while refreshing');
        expect(project.isPinned, isFalse);
        expect(project.status, ProjectStatus.active);
        expect(project.cloudMetadataSyncPending, isFalse);
        expect(project.cloudOwnerId, 'account-1');
        expect(project.thumbnailPath, 'edited-thumbnail.png');
      }
    },
  );

  test('catalog refresh keeps newer local snapshots local-only', () async {
    final metadata = LocalProjectMetadata(
      id: 'local-project',
      name: 'Local board',
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
    );
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
    });
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/rest/v1/projects' => _jsonResponse([
            {
              'id': 'local-project',
              'owner_id': 'account-1',
              'name': 'Older cloud board',
              'created_at': '2026-10-01T00:00:00Z',
              'updated_at': '2026-10-02T00:00:00Z',
              'archived_at': null,
              'trashed_at': null,
            },
          ], request: request),
          '/rest/v1/canvas_snapshots' => _jsonResponse([
            {
              'project_id': 'local-project',
              'updated_at': '2026-10-02T00:00:00Z',
            },
          ], request: request),
          '/rest/v1/user_project_preferences' => _jsonResponse(
            [],
            request: request,
          ),
          _ => throw StateError('Unexpected cloud request: ${request.url}'),
        };
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final durableStore = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    final localDocument = CanvasDocument(
      projectId: metadata.id,
      updatedAt: DateTime.utc(2026, 10, 6),
    );
    await durableStore.saveCanvasDocument(localDocument);
    addTearDown(durableStore.close);
    final storage = LocalStorageService();
    final container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        durableProjectStoreProvider.overrideWithValue(durableStore),
        supabaseClientProvider.overrideWithValue(client),
        supabaseSyncServiceProvider.overrideWithValue(
          SupabaseSyncService(client),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(homeProjectsProvider.notifier);
    await notifier.loadProjects();

    expect(notifier.state.value!.single.name, 'Local board');
    expect(notifier.state.value!.single.cloudOwnerId, isNull);
    expect((await storage.getProjects()).single.name, 'Local board');
    expect((await storage.getProjects()).single.cloudOwnerId, isNull);
    expect(
      (await durableStore.loadCanvasDocument(metadata.id))?.updatedAt,
      localDocument.updatedAt,
    );
    expect(requests, isNotEmpty);
    expect(requests.every((request) => request.method == 'GET'), isTrue);
    expect(
      requests.any(
        (request) =>
            request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership',
      ),
      isFalse,
    );
  });

  test(
    'catalog refresh does not adopt a local project with a matching cloud ID',
    () async {
      final metadata = LocalProjectMetadata(
        id: 'collision-project',
        name: 'Private local board',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 7),
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/rest/v1/projects' => _jsonResponse([
              {
                'id': 'collision-project',
                'owner_id': 'account-1',
                'name': 'Cloud board',
                'created_at': '2026-10-01T00:00:00Z',
                'updated_at': '2026-10-02T00:00:00Z',
                'archived_at': null,
                'trashed_at': null,
              },
            ], request: request),
            '/rest/v1/canvas_snapshots' => _jsonResponse([
              {
                'project_id': 'collision-project',
                'updated_at': '2026-10-02T00:00:00Z',
              },
            ], request: request),
            '/rest/v1/user_project_preferences' => _jsonResponse(
              const [],
              request: request,
            ),
            _ => throw StateError('Unexpected cloud request: ${request.url}'),
          };
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(homeProjectsProvider.notifier);
      await notifier.loadProjects();

      expect(notifier.state.value!.single.name, 'Private local board');
      expect(notifier.state.value!.single.cloudOwnerId, isNull);
      expect((await storage.getProjects()).single.name, 'Private local board');
      expect((await storage.getProjects()).single.cloudOwnerId, isNull);
      expect(requests.any((request) => request.method != 'GET'), isFalse);
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

  test('refresh preserves a locally trashed cloud project', () async {
    final trashedAt = DateTime.utc(2026, 10, 7, 12);
    final metadata = LocalProjectMetadata(
      id: 'trashed-project',
      name: 'Local board name',
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: trashedAt,
      status: ProjectStatus.trashed,
      trashedAt: trashedAt,
      cloudOwnerId: 'account-1',
    );
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
    });
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/rest/v1/projects' => _jsonResponse([
            {
              'id': 'trashed-project',
              'owner_id': 'account-1',
              'name': 'Cloud board name',
              'created_at': '2026-10-01T00:00:00Z',
              'updated_at': '2026-10-03T00:00:00Z',
              'archived_at': null,
              'trashed_at': null,
            },
          ], request: request),
          '/rest/v1/canvas_snapshots' => _jsonResponse([
            {
              'project_id': 'trashed-project',
              'updated_at': '2026-10-03T00:00:00Z',
            },
          ], request: request),
          '/rest/v1/user_project_preferences' => _jsonResponse(
            const [],
            request: request,
          ),
          _ => throw StateError('Unexpected cloud request: ${request.url}'),
        };
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final storage = LocalStorageService();
    final container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        supabaseClientProvider.overrideWithValue(client),
        supabaseSyncServiceProvider.overrideWithValue(
          SupabaseSyncService(client),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(homeProjectsProvider.notifier);
    await notifier.loadProjects();

    final merged = notifier.state.value!.single;
    final cached = (await storage.getProjects()).single;
    for (final project in [merged, cached]) {
      expect(project.status, ProjectStatus.trashed);
      expect(project.trashedAt, trashedAt);
      expect(project.name, 'Local board name');
      expect(project.cloudOwnerId, 'account-1');
    }
    expect(requests.every((request) => request.method == 'GET'), isTrue);
  });

  test(
    'persists a cloud pin locally before sync and retries it after refresh',
    () async {
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([
          LocalProjectMetadata(
            id: 'project-1',
            name: 'Cloud board',
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
            cloudOwnerId: 'account-1',
          ).toJson(),
        ]),
      });
      final requests = <http.Request>[];
      var failPreferenceSync = true;
      var cloudPinned = false;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects') {
            if (request.method == 'PATCH') {
              return _jsonResponse([
                {'id': 'project-1'},
              ], request: request);
            }
            if (request.url.queryParameters['select'] == 'owner_id') {
              return _jsonResponse({'owner_id': 'account-1'}, request: request);
            }
            return _jsonResponse([
              {
                'id': 'project-1',
                'owner_id': 'account-1',
                'name': 'Cloud board',
                'created_at': '2026-10-01T00:00:00Z',
                'updated_at': '2026-10-03T00:00:00Z',
                'archived_at': null,
                'trashed_at': null,
              },
            ], request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            return _jsonResponse([
              {'project_id': 'project-1', 'updated_at': '2026-10-03T00:00:00Z'},
            ], request: request);
          }
          if (request.url.path == '/rest/v1/user_project_preferences') {
            if (request.method == 'GET') {
              return _jsonResponse(
                cloudPinned
                    ? [
                        {'project_id': 'project-1', 'is_pinned': true},
                      ]
                    : const [],
                request: request,
              );
            }
            if (failPreferenceSync) {
              failPreferenceSync = false;
              return http.Response(
                jsonEncode({'message': 'Cloud unavailable', 'code': 'XX000'}),
                500,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            cloudPinned =
                (jsonDecode(request.body) as Map<String, dynamic>)['is_pinned']
                    as bool;
            return http.Response('', 201, request: request);
          }
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(homeProjectsProvider.notifier);
      await notifier.loadProjects();
      await expectLater(
        notifier.togglePinned('project-1'),
        throwsA(isA<SyncException>()),
      );

      final pending = (await storage.getProjects()).single;
      expect(pending.isPinned, isTrue);
      expect(pending.cloudMetadataSyncPending, isTrue);
      final ownerVerificationIndex = requests.indexWhere(
        (request) =>
            request.url.path == '/rest/v1/projects' &&
            request.method == 'GET' &&
            request.url.queryParameters['select'] == 'owner_id',
      );
      final failedPreferenceIndex = requests.indexWhere(
        (request) =>
            request.url.path == '/rest/v1/user_project_preferences' &&
            request.method == 'POST',
      );
      expect(ownerVerificationIndex, greaterThanOrEqualTo(0));
      expect(failedPreferenceIndex, greaterThan(ownerVerificationIndex));

      await notifier.loadProjects();

      final refreshed = notifier.state.value!.single;
      final cached = (await storage.getProjects()).single;
      expect(refreshed.isPinned, isTrue);
      expect(refreshed.cloudMetadataSyncPending, isFalse);
      expect(cached.isPinned, isTrue);
      expect(cached.cloudMetadataSyncPending, isFalse);
      expect(cloudPinned, isTrue);
    },
  );

  test('renames a cloud-owned project after verifying ownership', () async {
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([
        LocalProjectMetadata(
          id: 'project-1',
          name: 'Old name',
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          cloudOwnerId: 'account-1',
        ).toJson(),
      ]),
    });
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/rest/v1/projects' when request.method == 'GET' => _jsonResponse({
            'owner_id': 'account-1',
          }, request: request),
          '/rest/v1/projects' when request.method == 'PATCH' => _jsonResponse([
            {'id': 'project-1'},
          ], request: request),
          '/rest/v1/user_project_preferences' => _jsonResponse(
            const [],
            request: request,
          ),
          _ => throw StateError('Unexpected cloud request: ${request.url}'),
        };
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final storage = LocalStorageService();
    final container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        supabaseClientProvider.overrideWithValue(client),
        supabaseSyncServiceProvider.overrideWithValue(
          SupabaseSyncService(client),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(homeProjectsProvider.notifier);
    await notifier.renameProject('project-1', 'Renamed board');

    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'GET /rest/v1/projects',
      'PATCH /rest/v1/projects',
      'POST /rest/v1/user_project_preferences',
    ]);
    expect(notifier.state.value!.single.name, 'Renamed board');
    expect((await storage.getProjects()).single.name, 'Renamed board');
  });

  test('renames a local-only project without cloud catalog requests', () async {
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([
        LocalProjectMetadata(
          id: 'local-project',
          name: 'Old name',
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
        ).toJson(),
      ]),
    });
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        throw StateError(
          'Local-only rename made a cloud request: ${request.url}',
        );
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final storage = LocalStorageService();
    final container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        supabaseClientProvider.overrideWithValue(client),
        supabaseSyncServiceProvider.overrideWithValue(
          SupabaseSyncService(client),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(homeProjectsProvider.notifier);
    await notifier.renameProject('local-project', 'Renamed local board');

    expect(requests, isEmpty);
    expect(notifier.state.value!.single.name, 'Renamed local board');
    expect((await storage.getProjects()).single.name, 'Renamed local board');
  });

  test(
    'keeps a rename pending when ownership verification is unavailable',
    () async {
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([
          LocalProjectMetadata(
            id: 'project-1',
            name: 'Old name',
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
            cloudOwnerId: 'account-1',
          ).toJson(),
        ]),
      });
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'message': 'Cloud unavailable', 'code': 'XX000'}),
            500,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(homeProjectsProvider.notifier);
      await expectLater(
        notifier.renameProject('project-1', 'Renamed board'),
        throwsA(isA<Exception>()),
      );

      final pending = (await storage.getProjects()).single;
      expect(pending.name, 'Renamed board');
      expect(pending.cloudMetadataSyncPending, isTrue);
      expect(notifier.state.value!.single.name, 'Renamed board');
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.queryParameters['select'], 'owner_id');
    },
  );

  test(
    'resumes only an account-fenced explicit adoption intent after verification fails',
    () async {
      final localMetadata = LocalProjectMetadata(
        id: 'local-project',
        name: 'Local board',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
        isPinned: true,
        status: ProjectStatus.archived,
      );
      final collisionMetadata = LocalProjectMetadata(
        id: 'collision-project',
        name: 'Private local board',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 7),
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([
          localMetadata.toJson(),
          collisionMetadata.toJson(),
        ]),
      });
      final storage = LocalStorageService();
      final requests = <http.Request>[];
      var ownershipClaimed = false;
      var postSnapshotOwnershipVerificationFailures = 2;
      var storedSnapshot = false;
      var cloudName = 'Cloud board';
      var cloudArchived = false;
      var cloudPinned = false;
      final localDocument = CanvasDocument(
        projectId: 'local-project',
        metadata: const {'source': 'local'},
        updatedAt: DateTime.utc(2026, 10, 6),
      );
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects') {
            final selection = request.url.queryParameters['select'];
            if (selection == 'owner_id') {
              if (ownershipClaimed &&
                  storedSnapshot &&
                  postSnapshotOwnershipVerificationFailures > 0) {
                postSnapshotOwnershipVerificationFailures--;
                return http.Response(
                  jsonEncode({'message': 'Verification unavailable'}),
                  500,
                  request: request,
                  headers: {'content-type': 'application/json'},
                );
              }
              return _jsonResponse({
                'owner_id': ownershipClaimed ? 'account-1' : null,
              }, request: request);
            }
            if (request.method == 'PATCH') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              cloudName = body['name'] as String;
              cloudArchived = body['archived_at'] != null;
              return _jsonResponse([
                {'id': 'local-project'},
              ], request: request);
            }
            if (selection ==
                'id,owner_id,name,created_at,updated_at,archived_at,trashed_at') {
              return _jsonResponse([
                {
                  'id': 'local-project',
                  'owner_id': 'account-1',
                  'name': cloudName,
                  'created_at': '2026-10-01T00:00:00Z',
                  'updated_at': '2026-10-06T00:00:00Z',
                  'archived_at': cloudArchived ? '2026-10-06T00:00:00Z' : null,
                  'trashed_at': null,
                },
                {
                  'id': 'collision-project',
                  'owner_id': 'account-1',
                  'name': 'Cloud collision',
                  'created_at': '2026-10-01T00:00:00Z',
                  'updated_at': '2026-10-02T00:00:00Z',
                  'archived_at': null,
                  'trashed_at': null,
                },
              ], request: request);
            }
            fail('Unexpected project request: ${request.url}');
          }
          if (request.url.path ==
              '/rest/v1/rpc/claim_canvas_project_ownership') {
            final beforeClaim = (await storage.getProjects()).firstWhere(
              (project) => project.id == 'local-project',
            );
            if (!ownershipClaimed) {
              expect(beforeClaim.cloudAdoptionPendingAccountId, 'account-1');
            }
            ownershipClaimed = true;
            return _jsonResponse({'id': 'local-project'}, request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            if (request.method == 'GET') {
              if (request.url.queryParameters['select'] ==
                  'project_id,updated_at,revision,document_data') {
                return _jsonResponse(
                  storedSnapshot
                      ? {
                          'project_id': 'local-project',
                          'updated_at': '2026-10-06T00:00:00Z',
                          'revision': 0,
                          'document_data': localDocument.toPersistenceJson(),
                        }
                      : const [],
                  request: request,
                );
              }
              return _jsonResponse([
                if (storedSnapshot)
                  {
                    'project_id': 'local-project',
                    'updated_at': '2026-10-06T00:00:00Z',
                  },
                {
                  'project_id': 'collision-project',
                  'updated_at': '2026-10-02T00:00:00Z',
                },
              ], request: request);
            }
            storedSnapshot = true;
            return http.Response('', 201, request: request);
          }
          if (request.url.path == '/rest/v1/user_project_preferences') {
            if (request.method == 'GET') {
              return _jsonResponse(
                cloudPinned
                    ? [
                        {'project_id': 'local-project', 'is_pinned': true},
                      ]
                    : const [],
                request: request,
              );
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['project_id'] == 'local-project') {
              cloudPinned = body['is_pinned'] as bool;
            }
            return http.Response('', 201, request: request);
          }
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final durableStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(durableStore.close);
      await durableStore.saveCanvasDocument(localDocument);
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          durableProjectStoreProvider.overrideWithValue(durableStore),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(homeProjectsProvider.notifier);

      await expectLater(
        notifier.adoptProjectToCloud(
          'local-project',
          expectedAccountId: 'account-1',
        ),
        throwsA(isA<Exception>()),
      );

      final afterFailure = (await storage.getProjects()).firstWhere(
        (project) => project.id == 'local-project',
      );
      expect(afterFailure.cloudOwnerId, isNull);
      expect(afterFailure.cloudAdoptionPendingAccountId, 'account-1');
      expect(afterFailure.name, localMetadata.name);
      expect(afterFailure.isPinned, isTrue);
      expect(afterFailure.status, ProjectStatus.archived);
      expect(
        (await durableStore.loadCanvasDocument(
          'local-project',
        ))?.toPersistenceJson(),
        localDocument.toPersistenceJson(),
      );

      await notifier.loadProjects();

      final recovered = (await storage.getProjects()).firstWhere(
        (project) => project.id == 'local-project',
      );
      final collision = (await storage.getProjects()).firstWhere(
        (project) => project.id == 'collision-project',
      );
      expect(recovered.cloudOwnerId, 'account-1');
      expect(recovered.cloudMetadataSyncPending, isFalse);
      expect(recovered.cloudAdoptionPendingAccountId, isNull);
      expect(recovered.name, localMetadata.name);
      expect(recovered.isPinned, isTrue);
      expect(recovered.status, ProjectStatus.archived);
      expect(collision.cloudOwnerId, isNull);
      expect(collision.name, collisionMetadata.name);
      expect(
        requests.where(
          (request) =>
              request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership',
        ),
        hasLength(1),
      );
      expect(
        requests.where(
          (request) =>
              request.url.path == '/rest/v1/projects' &&
              request.method == 'PATCH' &&
              request.url.queryParameters['id'] == 'eq.collision-project',
        ),
        isEmpty,
      );
      expect(cloudName, localMetadata.name);
      expect(cloudArchived, isTrue);
      expect(cloudPinned, isTrue);
      expect(
        (await durableStore.loadCanvasDocument(
          'local-project',
        ))?.toPersistenceJson(),
        localDocument.toPersistenceJson(),
      );
    },
  );

  test('does not resume an adoption intent under another account', () async {
    final metadata = LocalProjectMetadata(
      id: 'local-project',
      name: 'Private local board',
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      cloudAdoptionPendingAccountId: 'account-1',
    );
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
    });
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/projects') {
          return _jsonResponse(const [], request: request);
        }
        if (request.url.path == '/rest/v1/canvas_snapshots') {
          return _jsonResponse(const [], request: request);
        }
        if (request.url.path == '/rest/v1/user_project_preferences') {
          return _jsonResponse(const [], request: request);
        }
        fail(
          'Unexpected request during a foreign-account refresh: ${request.url}',
        );
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client, userId: 'account-2');
    final durableStore = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    addTearDown(durableStore.close);
    final localDocument = CanvasDocument(
      projectId: 'local-project',
      updatedAt: DateTime.utc(2026, 10, 6),
    );
    await durableStore.saveCanvasDocument(localDocument);
    final storage = LocalStorageService();
    final container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        durableProjectStoreProvider.overrideWithValue(durableStore),
        supabaseClientProvider.overrideWithValue(client),
        supabaseSyncServiceProvider.overrideWithValue(
          SupabaseSyncService(client),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(homeProjectsProvider.notifier);
    await notifier.loadProjects();

    final stillPending = (await storage.getProjects()).single;
    expect(stillPending.cloudOwnerId, isNull);
    expect(stillPending.cloudAdoptionPendingAccountId, 'account-1');
    expect(notifier.state.value!.single.id, 'local-project');
    expect(
      (await durableStore.loadCanvasDocument(
        'local-project',
      ))?.toPersistenceJson(),
      localDocument.toPersistenceJson(),
    );
    expect(requests.every((request) => request.method == 'GET'), isTrue);
    expect(
      requests.any(
        (request) =>
            request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership',
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
  });

  test(
    'retries a failed rename despite server clock skew on refresh',
    () async {
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([
          LocalProjectMetadata(
            id: 'project-1',
            name: 'Old name',
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
            cloudOwnerId: 'account-1',
          ).toJson(),
        ]),
      });
      final requests = <http.Request>[];
      var failFirstMetadataSync = true;
      var cloudName = 'Old name';
      var cloudPinned = false;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'GET' &&
              request.url.queryParameters['select'] == 'owner_id') {
            return _jsonResponse({'owner_id': 'account-1'}, request: request);
          }
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'PATCH') {
            if (failFirstMetadataSync) {
              failFirstMetadataSync = false;
              return http.Response(
                jsonEncode({'message': 'Cloud unavailable', 'code': 'XX000'}),
                500,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            cloudName =
                (jsonDecode(request.body) as Map<String, dynamic>)['name']
                    as String;
            return _jsonResponse([
              {'id': 'project-1'},
            ], request: request);
          }
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'GET' &&
              request.url.queryParameters['select'] != 'owner_id') {
            return _jsonResponse([
              {
                'id': 'project-1',
                'owner_id': 'account-1',
                'name': cloudName,
                'created_at': '2026-10-01T00:00:00Z',
                'updated_at': '2099-10-01T00:00:00Z',
                'archived_at': null,
                'trashed_at': null,
              },
            ], request: request);
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            return _jsonResponse([
              {'project_id': 'project-1', 'updated_at': '2099-10-01T00:00:00Z'},
            ], request: request);
          }
          if (request.url.path == '/rest/v1/user_project_preferences') {
            if (request.method == 'GET') {
              return _jsonResponse(
                cloudPinned
                    ? [
                        {'project_id': 'project-1', 'is_pinned': true},
                      ]
                    : const [],
                request: request,
              );
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            cloudPinned = body['is_pinned'] as bool;
            return http.Response('', 201, request: request);
          }
          throw StateError('Unexpected cloud request: ${request.url}');
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client);
      final storage = LocalStorageService();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(homeProjectsProvider.notifier);
      await expectLater(
        notifier.renameProject('project-1', 'Renamed board'),
        throwsA(isA<SyncException>()),
      );

      final afterFailure = (await storage.getProjects()).single;
      expect(afterFailure.name, 'Renamed board');
      expect(afterFailure.cloudMetadataSyncPending, isTrue);
      expect(notifier.state.value!.single.name, 'Renamed board');

      await notifier.loadProjects();

      final refreshed = notifier.state.value!.single;
      final cached = (await storage.getProjects()).single;
      expect(refreshed.name, 'Renamed board');
      expect(refreshed.cloudMetadataSyncPending, isFalse);
      expect(cached.name, 'Renamed board');
      expect(cached.cloudMetadataSyncPending, isFalse);
      expect(cloudName, 'Renamed board');
      expect(cloudPinned, isFalse);
      expect(
        requests.where(
          (request) =>
              request.url.path == '/rest/v1/projects' &&
              request.method == 'PATCH',
        ),
        hasLength(2),
      );
      expect(
        requests.where(
          (request) =>
              request.url.path == '/rest/v1/user_project_preferences' &&
              request.method == 'POST',
        ),
        hasLength(1),
      );
    },
  );
}
