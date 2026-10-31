import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/home/presentation/project_route_screen.dart';

import '../../test_app.dart';

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _authenticate(SupabaseClient client, String userId) async {
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
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('direct project route loads a local document without auth', (
    tester,
  ) async {
    final created = DateTime(2026, 9, 19, 8);
    final metadata = LocalProjectMetadata(
      id: 'local-project',
      name: 'Local canvas',
      createdAt: created,
      updatedAt: created,
    );
    final document = CanvasDocument(projectId: metadata.id, updatedAt: created);
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      'ccs_doc_${metadata.id}': jsonEncode(document.toJson()),
    });

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          ProjectRouteScreen(
            projectId: 'local-project',
            editorBuilder: (projectId, projectName, role) => Text(projectName),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('project-route-editor')), findsOneWidget);
    expect(find.text('Local canvas'), findsWidgets);
  });

  testWidgets('brand-new local project opens without a saved document', (
    tester,
  ) async {
    final created = DateTime(2026, 9, 28, 12);
    final metadata = LocalProjectMetadata(
      id: 'new-local-project',
      name: 'Untitled Doc',
      createdAt: created,
      updatedAt: created,
    );
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
    });

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          ProjectRouteScreen(
            projectId: metadata.id,
            editorBuilder: (projectId, projectName, role) => Text(projectName),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('project-route-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('project-route-error')), findsNothing);
    expect(find.text('Untitled Doc'), findsNothing);
    expect(find.text('2026-09-28 12:00'), findsWidgets);
  });

  testWidgets('durable project data wins over stale SharedPreferences data', (
    tester,
  ) async {
    final created = DateTime(2026, 9, 19, 8);
    const projectId = 'durable-project';
    final metadata = LocalProjectMetadata(
      id: projectId,
      name: 'Durable canvas',
      createdAt: created,
      updatedAt: created,
    );
    final staleNode = CanvasNode(
      id: 'stale-node',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 100,
      height: 80,
      payload: ShapePayload(),
    );
    final durableNode = CanvasNode(
      id: 'durable-node',
      type: NodeType.rectangle,
      x: 20,
      y: 30,
      width: 140,
      height: 90,
      payload: ShapePayload(),
    );
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      'ccs_doc_$projectId': jsonEncode(
        CanvasDocument(
          projectId: projectId,
          nodes: [staleNode],
          updatedAt: created,
        ).toJson(),
      ),
    });

    final store = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    addTearDown(store.close);
    await store.saveCanvasDocument(
      CanvasDocument(
        projectId: projectId,
        nodes: [durableNode],
        updatedAt: created.add(const Duration(minutes: 1)),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [durableProjectStoreProvider.overrideWithValue(store)],
        child: testApp(
          ProjectRouteScreen(
            projectId: projectId,
            editorBuilder: (projectId, projectName, role) => Consumer(
              builder: (context, ref, child) {
                final nodes = ref.watch(documentNodesProvider);
                return Column(
                  children: [
                    Text(projectName),
                    Text(nodes.map((node) => node.id).join(',')),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('durable-node'), findsOneWidget);
    expect(find.text('stale-node'), findsNothing);
  });

  testWidgets(
    'same provider scope reloads and recreates the editor when project changes',
    (tester) async {
      final created = DateTime(2026, 9, 19, 8);
      final first = LocalProjectMetadata(
        id: 'project-a',
        name: 'Project A',
        createdAt: created,
        updatedAt: created,
      );
      final second = LocalProjectMetadata(
        id: 'project-b',
        name: 'Project B',
        createdAt: created,
        updatedAt: created,
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([
          first.toJson(),
          second.toJson(),
        ]),
        'ccs_doc_${first.id}': jsonEncode(
          CanvasDocument(projectId: first.id, updatedAt: created).toJson(),
        ),
        'ccs_doc_${second.id}': jsonEncode(
          CanvasDocument(projectId: second.id, updatedAt: created).toJson(),
        ),
      });

      final projectStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(projectStore.close);
      final providerContainer = ProviderContainer(
        overrides: [
          durableProjectStoreProvider.overrideWithValue(projectStore),
        ],
      );
      addTearDown(providerContainer.dispose);
      Widget route(String projectId) => UncontrolledProviderScope(
        container: providerContainer,
        child: testApp(
          ProjectRouteScreen(
            projectId: projectId,
            editorBuilder: (id, name, role) => _EditorLifecycleProbe(
              key: ValueKey('editor-probe:$id'),
              initialProjectId: id,
              projectName: name,
            ),
          ),
        ),
      );

      await tester.pumpWidget(route(first.id));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('initialized:project-a Project A'), findsOneWidget);

      final routeContainer = providerContainer;
      final autosaveLease = routeContainer.listen(
        autosaveControllerProvider,
        (_, _) {},
      );
      addTearDown(autosaveLease.close);
      final autosave = routeContainer.read(autosaveControllerProvider);
      autosave.init(first.id);
      routeContainer
          .read(documentNodesProvider.notifier)
          .addNode(
            CanvasNode(
              id: 'pending-a-node',
              type: NodeType.rectangle,
              x: 10,
              y: 20,
              width: 120,
              height: 80,
              payload: ShapePayload(),
            ),
          );
      expect(
        autosave.currentDocument().nodes.map((node) => node.id),
        contains('pending-a-node'),
      );
      final firstEditorState = tester.state<_EditorLifecycleProbeState>(
        find.byKey(const ValueKey('editor-probe:project-a')),
      );
      await tester.pumpWidget(route(second.id));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('initialized:project-b Project B'), findsOneWidget);
      expect(find.text('initialized:project-a Project A'), findsNothing);
      expect(
        find.byKey(const ValueKey('project-route-editor-surface:project-b')),
        findsOneWidget,
      );
      expect(firstEditorState.mounted, isFalse);
      final savedProjectA = await projectStore.loadCanvasDocument(first.id);
      expect(
        savedProjectA?.nodes.map((node) => node.id),
        contains('pending-a-node'),
      );
      expect(
        routeContainer.read(autosaveControllerProvider).activeProjectId,
        isNull,
      );
    },
  );

  testWidgets('route reloads when the project ID changes', (tester) async {
    final created = DateTime(2026, 9, 19, 8);
    final first = LocalProjectMetadata(
      id: 'project-a',
      name: 'Project A',
      createdAt: created,
      updatedAt: created,
    );
    final second = LocalProjectMetadata(
      id: 'project-b',
      name: 'Project B',
      createdAt: created,
      updatedAt: created,
    );
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([first.toJson(), second.toJson()]),
      'ccs_doc_${first.id}': jsonEncode(
        CanvasDocument(projectId: first.id, updatedAt: created).toJson(),
      ),
      'ccs_doc_${second.id}': jsonEncode(
        CanvasDocument(projectId: second.id, updatedAt: created).toJson(),
      ),
    });

    Widget route(String projectId) => ProviderScope(
      child: testApp(
        ProjectRouteScreen(
          projectId: projectId,
          editorBuilder: (projectId, projectName, role) => Text(projectName),
        ),
      ),
    );

    await tester.pumpWidget(route(first.id));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Project A'), findsWidgets);

    await tester.pumpWidget(route(second.id));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Project B'), findsWidgets);
    expect(find.text('Project A'), findsNothing);
  });

  testWidgets(
    'joined project without local content does not open a blank editor',
    (tester) async {
      final created = DateTime(2026, 9, 19, 8);
      final metadata = LocalProjectMetadata(
        id: 'joined-project',
        name: 'Joined project',
        createdAt: created,
        updatedAt: created,
        collaborationRoomCode: '482917',
        collaborationRole: 'editor',
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(const ProjectRouteScreen(projectId: 'joined-project')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('project-route-auth-required')),
        findsOneWidget,
      );
      expect(
        find.text('Sign in required for this collaboration project'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'cloud-backed route verifies server ownership before fetching snapshot',
    (tester) async {
      const projectId = 'owned-cloud-project';
      const accountId = 'cloud-owner';
      final created = DateTime.utc(2026, 10, 1);
      final metadata = LocalProjectMetadata(
        id: projectId,
        name: 'Cloud canvas',
        createdAt: created,
        updatedAt: created,
        cloudOwnerId: accountId,
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final requests = <String>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path == '/rest/v1/projects') {
            expect(request.method, 'GET');
            expect(request.url.queryParameters['id'], 'eq.$projectId');
            return http.Response(
              jsonEncode({'owner_id': accountId}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path == '/rest/v1/canvas_snapshots') {
            expect(request.method, 'GET');
            expect(
              requests.take(requests.length - 1),
              contains('/rest/v1/projects'),
            );
            return http.Response(
              jsonEncode({
                'document_data': CanvasDocument(
                  projectId: projectId,
                  updatedAt: created,
                ).toJson(),
              }),
              200,
              headers: {
                'content-type': 'application/json',
                'content-range': '0-0/1',
              },
              request: request,
            );
          }
          fail('Unexpected cloud request: ${request.url}');
        }),
      );
      // Supabase's JSON isolate teardown hangs when the test runner is exiting.
      addTearDown(() => client.auth.stopAutoRefresh());
      await _authenticate(client, accountId);
      final durableStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(durableStore.close);

      final routeLocalStorage = LocalStorageService(
        durableProjectStore: durableStore,
      );
      final routeSync = SupabaseSyncService(client);
      final routeAuthOverride = authUserProvider.overrideWith(
        (ref) => Stream.value(client.auth.currentUser),
      );
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(routeLocalStorage),
          durableProjectStoreProvider.overrideWithValue(durableStore),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(routeSync),
          routeAuthOverride,
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            ProjectRouteScreen(
              projectId: projectId,
              editorBuilder: (projectId, projectName, role) =>
                  Text(projectName),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(requests, ['/rest/v1/projects', '/rest/v1/canvas_snapshots']);
      expect(
        find.byKey(const ValueKey('project-route-editor')),
        findsOneWidget,
      );
      expect(find.text('Cloud canvas'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cloud-backed route fails closed when owner snapshot fetch fails',
    (tester) async {
      const projectId = 'owned-cloud-project';
      const accountId = 'cloud-owner';
      final created = DateTime.utc(2026, 10, 1);
      final metadata = LocalProjectMetadata(
        id: projectId,
        name: 'Cloud canvas',
        createdAt: created,
        updatedAt: created,
        cloudOwnerId: accountId,
      );
      final localDocument = CanvasDocument(
        projectId: projectId,
        nodes: [
          CanvasNode(
            id: 'local-only-node',
            type: NodeType.rectangle,
            x: 12,
            y: 24,
            width: 120,
            height: 80,
            payload: ShapePayload(),
          ),
        ],
        updatedAt: created.add(const Duration(minutes: 1)),
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects') {
            expect(request.method, 'GET');
            return http.Response(
              jsonEncode({'owner_id': accountId}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'message': 'snapshot read unavailable'}),
              500,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'POST') {
            return http.Response('', 201, request: request);
          }
          fail('Unexpected cloud request: ${request.url}');
        }),
      );
      await _authenticate(client, accountId);
      final durableStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(durableStore.close);
      addTearDown(() => client.auth.stopAutoRefresh());
      await durableStore.saveCanvasDocument(localDocument);
      final localStorage = LocalStorageService(
        durableProjectStore: durableStore,
      );
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
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
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            ProjectRouteScreen(
              projectId: projectId,
              editorBuilder: (projectId, projectName, role) =>
                  Text(projectName),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const ValueKey('project-route-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-route-editor')), findsNothing);
      expect(
        requests.map((request) => (request.method, request.url.path)).toList(),
        [('GET', '/rest/v1/projects'), ('GET', '/rest/v1/canvas_snapshots')],
      );
      expect(
        requests.any(
          (request) => request.url.path.startsWith('/storage/v1/object/'),
        ),
        isFalse,
      );
      final unchangedLocalDocument = await durableStore.loadCanvasDocument(
        projectId,
      );
      expect(
        unchangedLocalDocument?.toPersistenceJson(),
        localDocument.toPersistenceJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'future local timestamp cannot overwrite divergent cloud content',
    (tester) async {
      const projectId = 'future-local-cloud-project';
      const accountId = 'cloud-owner';
      final created = DateTime.utc(2026, 10, 1);
      final metadata = LocalProjectMetadata(
        id: projectId,
        name: 'Cloud canvas',
        createdAt: created,
        updatedAt: created,
        cloudOwnerId: accountId,
      );
      final localDocument = CanvasDocument(
        projectId: projectId,
        nodes: [
          CanvasNode(
            id: 'stale-local-node',
            type: NodeType.rectangle,
            x: 10,
            y: 20,
            width: 120,
            height: 80,
            payload: ShapePayload(),
          ),
        ],
        updatedAt: DateTime.utc(2035, 1, 1),
      );
      final cloudDocument = CanvasDocument(
        projectId: projectId,
        nodes: [
          CanvasNode(
            id: 'newer-cloud-node',
            type: NodeType.rectangle,
            x: 30,
            y: 40,
            width: 160,
            height: 90,
            payload: ShapePayload(),
          ),
        ],
        updatedAt: created,
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final requests = <(String, String)>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add((request.method, request.url.path));
          if (request.url.path == '/rest/v1/projects' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'owner_id': accountId}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'document_data': cloudDocument.toJson()}),
              200,
              headers: {
                'content-type': 'application/json',
                'content-range': '0-0/1',
              },
              request: request,
            );
          }
          if (request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'PATCH') {
            return http.Response(
              jsonEncode([
                {'project_id': projectId, 'revision': 1},
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          fail('Unexpected cloud request: ${request.method} ${request.url}');
        }),
      );
      addTearDown(() => client.auth.stopAutoRefresh());
      await _authenticate(client, accountId);
      final durableStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(durableStore.close);
      await durableStore.saveCanvasDocument(localDocument);
      final localStorage = LocalStorageService(
        durableProjectStore: durableStore,
      );
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            ProjectRouteScreen(
              projectId: projectId,
              editorBuilder: (id, name, role) => Text(name),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byKey(const ValueKey('project-route-conflict')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('project-route-editor')), findsNothing);
      expect(requests, [
        ('GET', '/rest/v1/projects'),
        ('GET', '/rest/v1/canvas_snapshots'),
      ]);
      expect(
        (await durableStore.loadCanvasDocument(projectId))?.toPersistenceJson(),
        localDocument.toPersistenceJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed durable and fallback flush keeps auth-transition draft locked',
    (tester) async {
      const projectId = 'unsaved-auth-transition-project';
      const accountId = 'original-owner';
      final created = DateTime.utc(2026, 10, 1);
      final metadata = LocalProjectMetadata(
        id: projectId,
        name: 'Cloud canvas',
        createdAt: created,
        updatedAt: created,
        cloudOwnerId: accountId,
      );
      final cloudDocument = CanvasDocument(
        projectId: projectId,
        nodes: [
          CanvasNode(
            id: 'existing-cloud-node',
            type: NodeType.rectangle,
            x: 10,
            y: 20,
            width: 120,
            height: 80,
            payload: ShapePayload(),
          ),
        ],
        updatedAt: created,
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final requests = <(String, String)>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add((request.method, request.url.path));
          if (request.url.path == '/rest/v1/projects') {
            return http.Response(
              jsonEncode({'owner_id': accountId}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({'document_data': cloudDocument.toJson()}),
              200,
              headers: {
                'content-type': 'application/json',
                'content-range': '0-0/1',
              },
              request: request,
            );
          }
          fail('Unexpected cloud write during auth transition.');
        }),
      );
      addTearDown(() => client.auth.stopAutoRefresh());
      await _authenticate(client, accountId);
      var failDurableWrites = true;
      final durableStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
        beforeSnapshotWrite: () async {
          if (failDurableWrites) {
            throw StateError('durable write unavailable');
          }
        },
      );
      addTearDown(durableStore.close);
      final localStorage = _ToggleFailingDocumentStorage(
        durableProjectStore: durableStore,
      );
      final authEvents = StreamController<User?>.broadcast();
      addTearDown(authEvents.close);
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
          durableProjectStoreProvider.overrideWithValue(durableStore),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(
            SupabaseSyncService(client),
          ),
          authUserProvider.overrideWith((ref) {
            return Stream<User?>.multi((controller) {
              controller.add(client.auth.currentUser);
              final subscription = authEvents.stream.listen(controller.add);
              controller.onCancel = subscription.cancel;
            });
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            ProjectRouteScreen(
              projectId: projectId,
              editorBuilder: (id, name, role) => Consumer(
                builder: (context, ref, _) => Text(
                  ref
                      .watch(documentNodesProvider)
                      .map((node) => node.id)
                      .join(','),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('project-route-editor')),
        findsOneWidget,
      );
      expect(find.text('existing-cloud-node'), findsOneWidget);

      final autosaveLease = container.listen(
        autosaveControllerProvider,
        (_, _) {},
      );
      addTearDown(autosaveLease.close);
      final autosave = container.read(autosaveControllerProvider);
      autosave.init(projectId, syncCloud: false);
      container
          .read(documentNodesProvider.notifier)
          .addNode(
            CanvasNode(
              id: 'only-in-memory-node',
              type: NodeType.rectangle,
              x: 50,
              y: 60,
              width: 100,
              height: 70,
              payload: ShapePayload(),
            ),
          );
      localStorage.failDocumentSaves = true;

      await _authenticate(client, 'replacement-account');
      authEvents.add(client.auth.currentUser);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byKey(const ValueKey('project-route-unsaved-transition')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('project-route-editor')), findsNothing);
      expect(
        container.read(documentNodesProvider).map((node) => node.id),
        containsAll(['existing-cloud-node', 'only-in-memory-node']),
      );
      final recovery = container.read(
        projectRouteTransitionRecoveryProvider(projectId),
      );
      expect(recovery?.accountId, accountId);
      expect(
        recovery?.document.nodes.map((node) => node.id),
        contains('only-in-memory-node'),
      );
      expect(requests, [
        ('GET', '/rest/v1/projects'),
        ('GET', '/rest/v1/canvas_snapshots'),
      ]);
      failDurableWrites = false;
      localStorage.failDocumentSaves = false;
      await _authenticate(client, accountId);
      authEvents.add(client.auth.currentUser);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('project-route-conflict')),
        findsOneWidget,
      );
      expect(
        (await durableStore.loadCanvasDocument(
          projectId,
        ))?.nodes.map((node) => node.id),
        containsAll(['existing-cloud-node', 'only-in-memory-node']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cloud-backed route stops before snapshot fetch when server owner differs',
    (tester) async {
      const projectId = 'owned-cloud-project';
      const accountId = 'cloud-owner';
      final created = DateTime.utc(2026, 10, 1);
      final metadata = LocalProjectMetadata(
        id: projectId,
        name: 'Cloud canvas',
        createdAt: created,
        updatedAt: created,
        cloudOwnerId: accountId,
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      final requests = <String>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          expect(request.url.path, '/rest/v1/projects');
          return http.Response(
            jsonEncode({'owner_id': 'different-owner'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      // Supabase's JSON isolate teardown hangs when the test runner is exiting.
      addTearDown(() => client.auth.stopAutoRefresh());
      await _authenticate(client, accountId);

      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(LocalStorageService()),
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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            ProjectRouteScreen(
              projectId: projectId,
              editorBuilder: (projectId, projectName, role) =>
                  Text(projectName),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(requests, ['/rest/v1/projects']);
      expect(
        find.byKey(const ValueKey('project-route-auth-required')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('project-route-editor')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collaboration role in local metadata requires a valid room join',
    (tester) async {
      const projectId = 'joined-project';
      const accountId = 'collaborator';
      final created = DateTime.utc(2026, 10, 1);
      final metadata = LocalProjectMetadata(
        id: projectId,
        name: 'Joined project',
        createdAt: created,
        updatedAt: created,
        collaborationRole: 'editor',
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
        'ccs_doc_$projectId': jsonEncode(
          CanvasDocument(projectId: projectId, updatedAt: created).toJson(),
        ),
      });
      final requests = <String>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          fail('A local role without a room code must not fetch snapshots.');
        }),
      );
      // Supabase's JSON isolate teardown hangs when the test runner is exiting.
      addTearDown(() => client.auth.stopAutoRefresh());
      await _authenticate(client, accountId);

      final container = ProviderContainer(
        overrides: [
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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            ProjectRouteScreen(
              projectId: projectId,
              editorBuilder: (projectId, projectName, role) =>
                  Text(projectName),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(requests, isEmpty);
      expect(
        find.byKey(const ValueKey('project-route-membership-required')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('project-route-editor')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cloud project route does not fabricate missing local metadata', (
    tester,
  ) async {
    const projectId = 'remote-only-project';
    const accountId = 'cloud-owner';
    SharedPreferences.setMockInitialValues({});
    final requests = <String>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request.url.path);
        fail('A missing local project must not probe cloud snapshots.');
      }),
    );
    // Supabase's JSON isolate teardown hangs when the test runner is exiting.
    addTearDown(() => client.auth.stopAutoRefresh());
    await _authenticate(client, accountId);
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        authUserProvider.overrideWith(
          (ref) => Stream.value(client.auth.currentUser),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const ProjectRouteScreen(projectId: projectId)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(requests, isEmpty);
    expect(
      find.byKey(const ValueKey('project-route-not-found')),
      findsOneWidget,
    );
    expect(find.text('Untitled Project'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing direct project route shows a recoverable state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(const ProjectRouteScreen(projectId: 'missing-project')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('project-route-not-found')),
      findsOneWidget,
    );
    expect(find.text('Project not found'), findsWidgets);
    final surface = tester.getRect(
      find.byKey(const ValueKey('project-route-not-found')),
    );
    expect(surface.left, greaterThanOrEqualTo(AppSpacing.md));
    expect(surface.right, lessThanOrEqualTo(320 - AppSpacing.md));
    expect(surface.width, lessThanOrEqualTo(320 - AppSpacing.md * 2));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Back to canvas'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Icon>(find.byType(Icon).first).size,
      AppControlSize.regular,
    );
  });

  testWidgets('missing project recovery stays contained on a wide route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(const ProjectRouteScreen(projectId: 'missing-project')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final surface = tester.getRect(
      find.byKey(const ValueKey('project-route-not-found')),
    );
    expect(surface.width, lessThanOrEqualTo(560));
    expect(surface.left, greaterThanOrEqualTo(0));
    expect(surface.right, lessThanOrEqualTo(1280));
    expect(surface.top, greaterThanOrEqualTo(0));
    expect(surface.bottom, lessThanOrEqualTo(800));
    for (final label in ['Retry', 'Back to canvas']) {
      final action = tester.getRect(find.text(label));
      expect(action.left, greaterThanOrEqualTo(surface.left));
      expect(action.right, lessThanOrEqualTo(surface.right));
      expect(action.top, greaterThanOrEqualTo(surface.top));
      expect(action.bottom, lessThanOrEqualTo(surface.bottom));
    }
    expect(tester.takeException(), isNull);
  });
}

class _ToggleFailingDocumentStorage extends LocalStorageService {
  _ToggleFailingDocumentStorage({required super.durableProjectStore});

  bool failDocumentSaves = false;

  @override
  Future<LocalSaveResult> saveDocument(
    CanvasDocument doc, {
    bool Function()? shouldWriteMetadata,
  }) {
    if (failDocumentSaves) {
      throw LocalStorageException(
        'Test fallback save failed.',
        StateError('fallback write unavailable'),
      );
    }
    return super.saveDocument(doc, shouldWriteMetadata: shouldWriteMetadata);
  }
}

class _EditorLifecycleProbe extends StatefulWidget {
  const _EditorLifecycleProbe({
    required this.initialProjectId,
    required this.projectName,
    super.key,
  });

  final String initialProjectId;
  final String projectName;

  @override
  State<_EditorLifecycleProbe> createState() => _EditorLifecycleProbeState();
}

class _EditorLifecycleProbeState extends State<_EditorLifecycleProbe> {
  @override
  Widget build(BuildContext context) =>
      Text('initialized:${widget.initialProjectId} ${widget.projectName}');
}
