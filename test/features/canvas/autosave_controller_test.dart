import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/viewport_provider.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_viewport;
import 'package:varian/features/canvas/presentation/canvas_screen.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import '../../test_app.dart';

String _encodeAuthTokenPart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _authenticateTestClient(
  SupabaseClient client, {
  required String userId,
}) async {
  client.auth.stopAutoRefresh();
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final token =
      '${_encodeAuthTokenPart({'alg': 'HS256'})}.${_encodeAuthTokenPart({'sub': userId, 'exp': expiration})}.test-signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'test-refresh-$userId',
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

class _RetryingAutosaveSyncService extends SupabaseSyncService {
  _RetryingAutosaveSyncService({
    required this.cloudDocument,
    this.ownershipVerificationStarted,
    this.releaseOwnershipVerification,
    this.failOwnershipVerificationWith,
  }) : super(null);

  final CanvasDocument cloudDocument;
  final Completer<void>? ownershipVerificationStarted;
  final Completer<void>? releaseOwnershipVerification;
  final Object? failOwnershipVerificationWith;

  final List<CanvasDocument> syncedDocuments = [];
  var syncAttempts = 0;
  var reconciliationReads = 0;
  var failFirstSync = true;

  @override
  bool get isConfigured => true;

  @override
  bool get isAuthenticated => true;

  @override
  Future<void> verifyProjectOwnership(
    String projectId, {
    required String expectedUserId,
  }) async {
    if (ownershipVerificationStarted != null &&
        !ownershipVerificationStarted!.isCompleted) {
      ownershipVerificationStarted!.complete();
    }
    if (releaseOwnershipVerification != null) {
      await releaseOwnershipVerification!.future;
    }
    final failure = failOwnershipVerificationWith;
    if (failure != null) throw failure;
  }

  @override
  Future<void> syncDocumentSnapshot(
    CanvasDocument document, {
    String? expectedUserId,
    bool Function()? isOperationCurrent,
  }) async {
    syncAttempts++;
    if (failFirstSync) {
      failFirstSync = false;
      throw TimeoutException('network unavailable');
    }
    syncedDocuments.add(document);
  }

  @override
  Future<CanvasDocument?> fetchDocumentSnapshot(String projectId) async {
    reconciliationReads++;
    return cloudDocument;
  }
}

class _FailingAutosaveLocalStorageService extends LocalStorageService {
  var failDocumentWrites = false;

  @override
  Future<LocalSaveResult> saveDocument(
    CanvasDocument doc, {
    bool Function()? shouldWriteMetadata,
  }) async {
    if (failDocumentWrites) {
      throw LocalStorageException(
        'Local document write failed.',
        StateError('fallback write unavailable'),
      );
    }
    return super.saveDocument(doc, shouldWriteMetadata: shouldWriteMetadata);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer();
    final keepAlive = container.listen(autosaveControllerProvider, (_, _) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });
    return container;
  }

  CanvasNode testNode(String id) => CanvasNode(
    id: id,
    type: NodeType.rectangle,
    x: 100,
    y: 100,
    width: 120,
    height: 80,
    payload: ShapePayload(),
  );

  test('canvas changes are autosaved and survive document reload', () async {
    final container = createContainer();
    final autosave = container.read(autosaveControllerProvider);
    autosave.init('project_1');

    container.read(documentNodesProvider.notifier).addNode(testNode('tool_1'));

    await Future<void>.delayed(const Duration(milliseconds: 900));

    final saved = await container
        .read(localStorageServiceProvider)
        .loadDocument('project_1');
    expect(saved?.nodes.map((node) => node.id), contains('tool_1'));
  });

  test('pending canvas changes are flushed immediately on exit', () async {
    final container = createContainer();
    final autosave = container.read(autosaveControllerProvider);
    autosave.init('project_2');

    container.read(documentNodesProvider.notifier).addNode(testNode('tool_2'));
    container
        .read(documentEdgesProvider.notifier)
        .addEdge(
          const CanvasEdge(
            id: 'edge_2',
            sourceNodeId: 'tool_2',
            targetNodeId: 'tool_2',
          ),
        );
    container.read(viewportProvider.notifier).setPosition(40, 60);
    container.read(viewportProvider.notifier).setZoom(1.5);
    await autosave.saveImmediately();

    final saved = await container
        .read(localStorageServiceProvider)
        .loadDocument('project_2');
    expect(saved?.nodes.map((node) => node.id), contains('tool_2'));
    expect(saved?.edges.map((edge) => edge.id), contains('edge_2'));
    expect(saved?.viewport.x, 40);
    expect(saved?.viewport.y, 60);
    expect(saved?.viewport.zoom, 1.5);

    final durable = await container
        .read(projectPersistenceSessionProvider('project_2'))
        .loadDocument();
    expect(durable?.nodes.map((node) => node.id), contains('tool_2'));
    expect(durable?.edges.map((edge) => edge.id), contains('edge_2'));
    expect(durable?.viewport.zoom, 1.5);
  });

  test(
    'provider-owned durable session survives an async save boundary',
    () async {
      final container = createContainer();
      final autosave = container.read(autosaveControllerProvider);
      autosave.init('project_async_session');
      container
          .read(documentNodesProvider.notifier)
          .addNode(testNode('async_node'));

      final saving = autosave.saveImmediately();
      await Future<void>.delayed(Duration.zero);
      final session = container.read(
        projectPersistenceSessionProvider('project_async_session'),
      );
      expect(session.isDisposed, isFalse);
      await saving;

      final durable = await session.loadDocument();
      expect(durable?.nodes.map((node) => node.id), contains('async_node'));
    },
  );

  test('flushDurable waits for the pending durable snapshot write', () async {
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    final store = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
      beforeSnapshotWrite: () async {
        writeStarted.complete();
        await releaseWrite.future;
      },
    );
    final container = ProviderContainer(
      overrides: [durableProjectStoreProvider.overrideWithValue(store)],
    );
    addTearDown(() async {
      container.dispose();
      await store.close();
    });
    final keepAlive = container.listen(autosaveControllerProvider, (_, _) {});
    addTearDown(keepAlive.close);
    final autosave = container.read(autosaveControllerProvider);
    autosave.init('project_gated');
    container.read(documentNodesProvider.notifier).addNode(testNode('gated'));

    final flush = autosave.flushDurable();
    await writeStarted.future;
    var completed = false;
    unawaited(flush.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    releaseWrite.complete();
    await flush;
    expect(completed, isTrue);
    expect(
      (await store.loadCanvasDocument('project_gated'))?.nodes.single.id,
      'gated',
    );
  });

  test(
    'flushDurable persists the latest revision after an overlapping edit',
    () async {
      final firstWriteStarted = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      var snapshotWrites = 0;
      final store = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
        beforeSnapshotWrite: () async {
          snapshotWrites++;
          if (snapshotWrites == 1) {
            firstWriteStarted.complete();
            await releaseFirstWrite.future;
          }
        },
      );
      final container = ProviderContainer(
        overrides: [durableProjectStoreProvider.overrideWithValue(store)],
      );
      addTearDown(() async {
        container.dispose();
        await store.close();
      });
      final keepAlive = container.listen(autosaveControllerProvider, (_, _) {});
      addTearDown(keepAlive.close);
      final autosave = container.read(autosaveControllerProvider);
      autosave.init('project_revision');
      container.read(documentNodesProvider.notifier).addNode(testNode('first'));

      final flush = autosave.flushDurable();
      await firstWriteStarted.future;
      container
          .read(documentNodesProvider.notifier)
          .addNode(testNode('second'));
      releaseFirstWrite.complete();
      await flush;

      final saved = await store.loadCanvasDocument('project_revision');
      expect(
        saved?.nodes.map((node) => node.id),
        containsAll(<String>['first', 'second']),
      );
      expect(snapshotWrites, greaterThanOrEqualTo(2));
    },
  );

  test(
    'auth transition cancels pending cloud retry until project reconciliation',
    () async {
      const projectId = 'project_auth_retry';
      final cloudDocument = CanvasDocument(
        projectId: projectId,
        nodes: [testNode('cloud-current')],
        updatedAt: DateTime.utc(2026, 10, 1),
      );
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await _authenticateTestClient(client, userId: 'account-a');

      var failDurableWrites = false;
      final gatedStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
        beforeSnapshotWrite: () async {
          if (failDurableWrites) {
            throw StateError('durable write unavailable');
          }
        },
      );
      final localStorage = LocalStorageService();
      await localStorage.saveProjectMetadata(
        LocalProjectMetadata(
          id: projectId,
          name: 'Auth retry project',
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          cloudOwnerId: 'account-a',
        ),
      );
      final sync = _RetryingAutosaveSyncService(cloudDocument: cloudDocument);
      final container = ProviderContainer(
        overrides: [
          durableProjectStoreProvider.overrideWithValue(gatedStore),
          localStorageServiceProvider.overrideWithValue(localStorage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(sync),
        ],
      );
      final keepAlive = container.listen(autosaveControllerProvider, (_, _) {});
      final autosave = container.read(autosaveControllerProvider);
      addTearDown(() async {
        await autosave.dispose();
        keepAlive.close();
        container.dispose();
        sync.dispose();
        client.dispose();
        await gatedStore.close();
      });

      autosave.init(projectId, syncCloud: true);
      container
          .read(documentNodesProvider.notifier)
          .addNode(testNode('durable-draft'));
      await autosave.saveImmediately(syncCloud: true);
      final cloudAttemptDeadline = DateTime.now().add(
        const Duration(seconds: 1),
      );
      while (container.read(syncStatusProvider).status !=
          SyncStatus.cloudPending) {
        if (DateTime.now().isAfter(cloudAttemptDeadline)) {
          fail('Cloud sync did not reach its retryable failure state.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(sync.syncAttempts, 1);

      container
          .read(documentNodesProvider.notifier)
          .addNode(testNode('newer-local-draft'));
      failDurableWrites = true;
      await expectLater(
        autosave.flushDurable(deactivateAfterFlush: true),
        throwsA(isA<StateError>()),
      );
      final durableDraft = await gatedStore.loadCanvasDocument(projectId);
      expect(
        durableDraft?.nodes.map((node) => node.id),
        contains('durable-draft'),
      );
      expect(
        (await localStorage.loadDocument(
          projectId,
        ))?.nodes.map((node) => node.id),
        contains('newer-local-draft'),
      );

      await _authenticateTestClient(client, userId: 'account-b');
      await _authenticateTestClient(client, userId: 'account-a');
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(
        sync.syncAttempts,
        1,
        reason: 'A stale cloud retry must wait for route reconciliation.',
      );
      expect(sync.syncedDocuments, isEmpty);

      final reconciled = await sync.fetchDocumentSnapshot(projectId);
      expect(sync.reconciliationReads, 1);
      expect(
        reconciled?.nodes.map((node) => node.id),
        contains('cloud-current'),
      );
      expect(sync.syncAttempts, 1);
      expect(sync.syncedDocuments, isEmpty);

      failDurableWrites = false;
      autosave.init(projectId, syncCloud: true);
    },
  );

  test(
    'failed account A sync cannot change account B status before auth cleanup',
    () async {
      const projectId = 'project_stale_sync_status';
      final ownershipStarted = Completer<void>();
      final releaseOwnership = Completer<void>();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await _authenticateTestClient(client, userId: 'account-a');

      final store = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      final localStorage = LocalStorageService();
      await localStorage.saveProjectMetadata(
        LocalProjectMetadata(
          id: projectId,
          name: 'Stale sync status project',
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          cloudOwnerId: 'account-a',
        ),
      );
      final sync = _RetryingAutosaveSyncService(
        cloudDocument: CanvasDocument(
          projectId: projectId,
          nodes: const [],
          updatedAt: DateTime.utc(2026, 10, 1),
        ),
        ownershipVerificationStarted: ownershipStarted,
        releaseOwnershipVerification: releaseOwnership,
        failOwnershipVerificationWith: StateError('ownership request failed'),
      );
      final container = ProviderContainer(
        overrides: [
          durableProjectStoreProvider.overrideWithValue(store),
          localStorageServiceProvider.overrideWithValue(localStorage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(sync),
        ],
      );
      final keepAlive = container.listen(autosaveControllerProvider, (_, _) {});
      final autosave = container.read(autosaveControllerProvider);
      addTearDown(() async {
        await autosave.dispose();
        keepAlive.close();
        container.dispose();
        sync.dispose();
        client.dispose();
        await store.close();
      });

      autosave.init(projectId, syncCloud: true);
      container
          .read(documentNodesProvider.notifier)
          .addNode(testNode('account-a-local-draft'));
      await autosave.saveImmediately(syncCloud: true);
      await ownershipStarted.future;

      expect(
        (await store.loadCanvasDocument(projectId))?.nodes.single.id,
        'account-a-local-draft',
      );
      await _authenticateTestClient(client, userId: 'account-b');
      container.read(syncStatusProvider.notifier).state = SyncState(
        status: SyncStatus.synced,
        lastSyncedAt: DateTime.utc(2026, 10, 2),
      );

      // Fail A's pending request before the auth cleanup listener advances the
      // cloud operation epoch. Account B's already-published status must win.
      releaseOwnership.complete();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(syncStatusProvider).status, SyncStatus.synced);
      expect(
        (await store.loadCanvasDocument(projectId))?.nodes.single.id,
        'account-a-local-draft',
        reason: 'Fencing a stale cloud result must not discard local saves.',
      );
    },
  );

  test(
    'auth transition invalidates the service write after ownership preflight',
    () async {
      const projectId = 'project_auth_service_preflight';
      final ownershipStarted = Completer<void>();
      final releaseOwnership = Completer<void>();
      final requests = <http.Request>[];
      var ownershipReads = 0;
      late final SupabaseClient client;
      client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/projects') {
            ownershipReads++;
            if (ownershipReads == 2) {
              ownershipStarted.complete();
              await releaseOwnership.future;
            }
            return http.Response(
              jsonEncode({'owner_id': 'account-a'}),
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
          fail('Invalidated autosave must not write a cloud snapshot.');
        }),
      );
      await _authenticateTestClient(client, userId: 'account-a');

      final gatedStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      final localStorage = LocalStorageService();
      await localStorage.saveProjectMetadata(
        LocalProjectMetadata(
          id: projectId,
          name: 'Service preflight project',
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          cloudOwnerId: 'account-a',
        ),
      );
      final service = SupabaseSyncService(client);
      final container = ProviderContainer(
        overrides: [
          durableProjectStoreProvider.overrideWithValue(gatedStore),
          localStorageServiceProvider.overrideWithValue(localStorage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(service),
        ],
      );
      final keepAlive = container.listen(autosaveControllerProvider, (_, _) {});
      final autosave = container.read(autosaveControllerProvider);
      addTearDown(() async {
        await autosave.dispose();
        keepAlive.close();
        container.dispose();
        service.dispose();
        client.dispose();
        await gatedStore.close();
      });

      autosave.init(projectId, syncCloud: true);
      container
          .read(documentNodesProvider.notifier)
          .addNode(testNode('service-preflight-draft'));
      await autosave.saveImmediately(syncCloud: true);
      await ownershipStarted.future;

      await _authenticateTestClient(client, userId: 'account-b');
      await autosave.flushDurable(deactivateAfterFlush: true);
      await _authenticateTestClient(client, userId: 'account-a');
      releaseOwnership.complete();
      await Future<void>.delayed(Duration.zero);

      expect(ownershipReads, 2);
      expect(
        requests.where(
          (request) =>
              request.url.path == '/rest/v1/canvas_snapshots' &&
              request.method != 'GET',
        ),
        isEmpty,
      );
      expect(requests, hasLength(2));
    },
  );

  test(
    'auth transition invalidates a cloud sync blocked in ownership preflight',
    () async {
      const projectId = 'project_auth_preflight';
      final verificationStarted = Completer<void>();
      final releaseVerification = Completer<void>();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await _authenticateTestClient(client, userId: 'account-a');

      var failDurableWrites = false;
      final gatedStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
        beforeSnapshotWrite: () async {
          if (failDurableWrites) {
            throw StateError('durable write unavailable');
          }
        },
      );
      final localStorage = _FailingAutosaveLocalStorageService();
      await localStorage.saveProjectMetadata(
        LocalProjectMetadata(
          id: projectId,
          name: 'Auth preflight project',
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          cloudOwnerId: 'account-a',
        ),
      );
      final sync = _RetryingAutosaveSyncService(
        cloudDocument: CanvasDocument(
          projectId: projectId,
          nodes: const [],
          updatedAt: DateTime.utc(2026, 10, 1),
        ),
        ownershipVerificationStarted: verificationStarted,
        releaseOwnershipVerification: releaseVerification,
      );
      final container = ProviderContainer(
        overrides: [
          durableProjectStoreProvider.overrideWithValue(gatedStore),
          localStorageServiceProvider.overrideWithValue(localStorage),
          supabaseClientProvider.overrideWithValue(client),
          supabaseSyncServiceProvider.overrideWithValue(sync),
        ],
      );
      final keepAlive = container.listen(autosaveControllerProvider, (_, _) {});
      final autosave = container.read(autosaveControllerProvider);
      addTearDown(() async {
        await autosave.dispose();
        keepAlive.close();
        container.dispose();
        sync.dispose();
        client.dispose();
        await gatedStore.close();
      });

      autosave.init(projectId, syncCloud: true);
      container
          .read(documentNodesProvider.notifier)
          .addNode(testNode('preflight-draft'));
      final initialSave = autosave.saveImmediately(syncCloud: true);
      await verificationStarted.future;
      await initialSave;

      container
          .read(documentNodesProvider.notifier)
          .addNode(testNode('auth-transition-draft'));
      await _authenticateTestClient(client, userId: 'account-b');
      failDurableWrites = true;
      localStorage.failDocumentWrites = true;
      await expectLater(
        autosave.flushDurable(deactivateAfterFlush: true),
        throwsA(isA<StateError>()),
      );

      await _authenticateTestClient(client, userId: 'account-a');
      releaseVerification.complete();
      await Future<void>.delayed(Duration.zero);

      expect(
        sync.syncAttempts,
        0,
        reason: 'The blocked sync belongs to the pre-transition auth epoch.',
      );
      expect(sync.syncedDocuments, isEmpty);
    },
  );

  test('restoring a snapshot replaces canvas state and persists it', () async {
    final container = createContainer();
    final autosave = container.read(autosaveControllerProvider);
    autosave.init('project_restore');
    container
        .read(documentNodesProvider.notifier)
        .addNode(testNode('old_node'));
    await autosave.saveImmediately();

    final restored = CanvasDocument(
      projectId: 'project_restore',
      nodes: [testNode('restored_node')],
      edges: const [
        CanvasEdge(
          id: 'restored_edge',
          sourceNodeId: 'restored_node',
          targetNodeId: 'restored_node',
        ),
      ],
      viewport: const canvas_viewport.Viewport(x: 12, y: 24, zoom: 1.25),
      updatedAt: DateTime.now(),
    );
    await autosave.restoreDocument(restored);

    expect(
      container.read(documentNodesProvider).map((node) => node.id),
      contains('restored_node'),
    );
    expect(
      container.read(documentNodesProvider).map((node) => node.id),
      isNot(contains('old_node')),
    );
    final saved = await container
        .read(localStorageServiceProvider)
        .loadDocument('project_restore');
    expect(saved?.nodes.map((node) => node.id), contains('restored_node'));
    expect(saved?.edges.map((edge) => edge.id), contains('restored_edge'));
    expect(saved?.viewport.zoom, 1.25);
    expect(container.read(historyProvider).canUndo, isFalse);
  });

  testWidgets('CanvasScreen edits flush before the project route is popped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const CanvasScreen(projectId: 'project_3')),
      ),
    );
    await tester.pump();
    await tester.pump();

    final autosave = container.read(autosaveControllerProvider);
    expect(autosave.activeProjectId, 'project_3');
    container.read(documentNodesProvider.notifier).addNode(testNode('tool_3'));
    await tester.pump();

    // GoRouter awaits this boundary from the project route's onExit callback;
    // widget disposal alone is synchronous and cannot guarantee the final save.
    await autosave.flush();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    final saved = await container
        .read(localStorageServiceProvider)
        .loadDocument('project_3');
    expect(saved?.nodes.map((node) => node.id), contains('tool_3'));
    final durable = await container
        .read(projectPersistenceSessionProvider('project_3'))
        .loadDocument();
    expect(durable?.nodes.map((node) => node.id), contains('tool_3'));
  });

  testWidgets(
    'CanvasScreen renders video cards without an audio payload cast',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentNodesProvider.notifier)
          .addNode(
            CanvasNode(
              id: 'video-card-1',
              type: NodeType.videoCard,
              x: 100,
              y: 100,
              width: 240,
              height: 150,
              payload: VideoPayload(),
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(const CanvasScreen(projectId: 'project_5')),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read-only CanvasScreen does not autosave local changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const CanvasScreen(projectId: 'project_4', readOnly: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    container.read(documentNodesProvider.notifier).addNode(testNode('tool_4'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    final saved = await container
        .read(localStorageServiceProvider)
        .loadDocument('project_4');
    expect(saved, isNull);
  });
}
