@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/data/remote/supabase_sync_provider.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/collaboration/domain/crdt_engine.dart';
import 'package:varian/features/collaboration/state/collaboration_session_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('host and guest exchange canvas edits over the Realtime wire', () async {
    final server = await _CollaborationServer.start();
    addTearDown(server.close);
    final host = await server.connect('actor-b-host');
    final guest = await server.connect('actor-a-guest');

    for (var edit = 0; edit < 12; edit++) {
      final sender = edit.isEven ? guest : host;
      final receiver = edit.isEven ? host : guest;
      final shape = sender.nodes.firstWhere((node) => node.id == 'shape');
      final updated = shape.copyWith(
        x: 100.0 + edit * 10,
        y: 200.0 + edit,
        width: 250.0 + edit,
        height: 120.0 + edit,
        rotation: edit * 0.1,
        opacity: 0.5,
        payload: (shape.payload as ShapePayload).copyWith(
          cornerRadius: edit.isEven ? 80 : 0,
          fill: edit.isEven ? Colors.green : Colors.blue,
        ),
      );
      sender.container.read(documentNodesProvider.notifier).updateNode(updated);
      await _waitFor(
        () =>
            receiver.nodes.firstWhere((node) => node.id == 'shape').x ==
            updated.x,
      );
      expect(
        receiver.nodes.firstWhere((node) => node.id == 'shape').toJson(),
        updated.toJson(),
      );
    }

    guest.container.read(documentNodesProvider.notifier).setNodes([
      ...guest.nodes,
      guest.nodes.first.copyWith(id: 'new-shape'),
    ]);
    await _waitFor(() => host.nodes.any((node) => node.id == 'new-shape'));
    const edge = CanvasEdge(
      id: 'edge',
      sourceNodeId: 'shape',
      targetNodeId: 'new-shape',
    );
    host.container.read(documentEdgesProvider.notifier).setEdges([edge]);
    await _waitFor(
      () => guest.container.read(documentEdgesProvider).length == 1,
    );
    guest.container.read(documentEdgesProvider.notifier).setEdges([]);
    await _waitFor(() => host.container.read(documentEdgesProvider).isEmpty);
    host.container
        .read(documentNodesProvider.notifier)
        .setNodes(host.nodes.where((node) => node.id != 'shape').toList());
    await _waitFor(() => !guest.nodes.any((node) => node.id == 'shape'));
    await _waitFor(
      () =>
          host.controller.state.pendingOperations == 0 &&
          guest.controller.state.pendingOperations == 0,
    );
    expect(
      guest.nodes.map((node) => node.toJson()),
      host.nodes.map((node) => node.toJson()),
    );
    expect(host.controller.state.isLive, isTrue);
    expect(guest.controller.state.isLive, isTrue);
  });

  test('coalesces concurrent room joins into one subscription', () async {
    final server = await _CollaborationServer.start();
    addTearDown(server.close);
    final client = await server.createClient('actor-concurrent-join');
    final transport = SupabaseCollaborationTransport(client);
    addTearDown(() async {
      await transport.leave();
      await client.dispose();
    });

    final firstJoin = transport.join(
      projectId: server.initial.document.projectId,
      userId: 'actor-concurrent-join',
      userName: 'Concurrent Join',
      userColor: Colors.blue,
    );
    final secondJoin = transport.join(
      projectId: server.initial.document.projectId,
      userId: 'actor-concurrent-join',
      userName: 'Concurrent Join',
      userColor: Colors.blue,
    );

    await Future.wait([firstJoin, secondJoin]);
    expect(transport.isConnected, isTrue);
  });

  test(
    'duplicate CRDT delivery is idempotent across realtime and storage',
    () async {
      final server = await _CollaborationServer.start();
      addTearDown(server.close);
      final host = await server.connect('actor-b-host');
      final guest = await server.connect('actor-a-guest');
      final publisherClient = await server.createClient(
        'actor-duplicate-publisher',
      );
      final publisher = SupabaseCollaborationTransport(publisherClient);
      addTearDown(() async {
        await publisher.leave();
        await publisherClient.dispose();
      });

      await publisher.join(
        projectId: server.initial.document.projectId,
        userId: 'actor-duplicate-publisher',
        userName: 'Duplicate Publisher',
        userColor: Colors.orange,
      );
      final operation = CrdtOperation.create(
        projectId: server.initial.document.projectId,
        dot: const CrdtDot(actorId: 'actor-duplicate-publisher', counter: 100),
        dependencies: server.initial.version,
        kind: CrdtOperationKind.nodeFieldSet,
        targetId: 'shape',
        field: 'x',
        value: {'value': 777.0},
      );

      await publisher.publish(operation);
      await publisher.publish(operation);
      await _waitFor(
        () => host.nodes.firstWhere((node) => node.id == 'shape').x == 777.0,
      );
      await _waitFor(
        () => guest.nodes.firstWhere((node) => node.id == 'shape').x == 777.0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(server.operations, hasLength(1));
      expect(
        host.nodes.firstWhere((node) => node.id == 'shape').toJson(),
        guest.nodes.firstWhere((node) => node.id == 'shape').toJson(),
      );
      expect(host.controller.state.pendingOperations, 0);
      expect(guest.controller.state.pendingOperations, 0);
    },
  );

  test(
    'control events update role, follow, screen consent, and reconnect',
    () async {
      final server = await _CollaborationServer.start();
      addTearDown(server.close);
      final host = await server.connect('actor-b-host');
      final guest = await server.connect(
        'actor-a-guest',
        role: CollaborationRole.editor,
      );

      final controlClient = await server.createClient('actor-control');
      addTearDown(controlClient.dispose);
      final controlChannel = controlClient.channel(
        'canvas_room:${server.initial.document.projectId}',
      );
      final subscribed = Completer<void>();
      controlChannel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed &&
            !subscribed.isCompleted) {
          subscribed.complete();
        } else if (!subscribed.isCompleted && error != null) {
          subscribed.completeError(error);
        }
      });
      await subscribed.future.timeout(const Duration(seconds: 2));
      addTearDown(controlChannel.unsubscribe);

      final roleChange = CollaborationControlEvent(
        eventId: 'role-change',
        projectId: server.initial.document.projectId,
        actorId: host.controller.localUserId!,
        targetUserId: guest.controller.localUserId!,
        type: CollaborationControlEventType.memberRoleChanged,
        payload: {'role': CollaborationRole.viewer.wireName},
        createdAt: DateTime.utc(2026, 9, 12),
      );
      final roleResponse = await controlChannel.sendBroadcastMessage(
        event: 'collaboration_control',
        payload: roleChange.toJson(),
      );
      expect(roleResponse, ChannelResponse.ok);
      await _waitFor(() => guest.controller.role == CollaborationRole.viewer);
      expect(guest.controller.canEditCanvas, isFalse);

      final hostX = host.nodes.firstWhere((node) => node.id == 'shape').x;
      final viewerAttempt = guest.nodes
          .firstWhere((node) => node.id == 'shape')
          .copyWith(x: hostX + 123);
      guest.container
          .read(documentNodesProvider.notifier)
          .updateNode(viewerAttempt);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(host.nodes.firstWhere((node) => node.id == 'shape').x, hostX);
      expect(guest.controller.state.pendingOperations, 0);

      await guest.controller.requestFollow(host.controller.localUserId!);
      await _waitFor(() => host.controller.state.followRequest != null);
      final followRequest = host.controller.state.followRequest!;
      await host.controller.respondToFollow(
        request: followRequest,
        approved: true,
      );
      await _waitFor(
        () =>
            guest.controller.state.followingUserId ==
            host.controller.localUserId,
      );
      await guest.controller.stopFollowing();
      await _waitFor(() => guest.controller.state.followingUserId == null);

      await guest.controller.requestScreenShare(host.controller.localUserId!);
      await _waitFor(() => host.controller.state.screenShareRequest != null);
      final screenRequest = host.controller.state.screenShareRequest!;
      await host.controller.respondToScreenShare(
        request: screenRequest,
        approved: false,
      );
      await _waitFor(
        () =>
            guest.controller.state.screenTracking.status ==
            ScreenTrackingStatus.stopped,
      );

      await guest.controller.reconnect();
      await _waitFor(() => guest.controller.state.isLive);
    },
  );

  test(
    'persists a prepared Drawing Paper preview in the collaborative snapshot',
    () async {
      final server = await _CollaborationServer.start();
      addTearDown(server.close);
      final host = await server.connect('actor-b-host');
      final paper = host.nodes.firstWhere((node) => node.id == 'paper');
      final preparedPayload = (paper.payload as DrawingPaperPayload).copyWith(
        compositePreviewRef: 'drawing-paper/project-wire/paper/preview-v1.png',
      );
      final preparedDocument = server.initial.document.copyWith(
        nodes: [paper.copyWith(payload: preparedPayload)],
      );
      expect(preparedPayload.compositePreviewRef, isNot(contains('?')));

      final persisted = await host.controller.persistSnapshot(
        preparedDocument: preparedDocument,
      );

      expect(persisted, isTrue);
      final snapshotDocument = CanvasDocument.fromJson(
        Map<String, dynamic>.from(server.snapshotState!['document'] as Map),
      );
      final snapshotPayload =
          snapshotDocument.nodes.single.payload as DrawingPaperPayload;
      expect(
        snapshotPayload.compositePreviewRef,
        'drawing-paper/project-wire/paper/preview-v1.png',
      );
    },
  );

  test('host seeds a new room before the first guest edit', () async {
    final server = await _CollaborationServer.start(
      includeInitialSnapshot: false,
    );
    addTearDown(server.close);
    final host = await server.connect('actor-b-host');

    expect(host.controller.state.isLive, isTrue);
    expect(server.snapshotState, isNotNull);

    final guest = await server.connect('actor-a-guest');
    await _waitFor(() => guest.nodes.any((node) => node.id == 'shape'));

    final hostShape = host.nodes.firstWhere((node) => node.id == 'shape');
    final hostEdit = hostShape.copyWith(x: 512, y: 384);
    host.container.read(documentNodesProvider.notifier).updateNode(hostEdit);
    await _waitFor(
      () => guest.nodes.firstWhere((node) => node.id == 'shape').x == 512,
    );
    expect(
      guest.nodes.firstWhere((node) => node.id == 'shape').toJson(),
      hostEdit.toJson(),
    );

    final guestEdit = hostEdit.copyWith(x: 640, y: 420);
    guest.container.read(documentNodesProvider.notifier).updateNode(guestEdit);
    await _waitFor(
      () => host.nodes.firstWhere((node) => node.id == 'shape').x == 640,
    );
    expect(
      host.nodes.firstWhere((node) => node.id == 'shape').toJson(),
      guestEdit.toJson(),
    );
  });

  test('combined text and geometry edits arrive together', () async {
    final server = await _CollaborationServer.start();
    addTearDown(server.close);
    final host = await server.connect('actor-b-host');
    final guest = await server.connect('actor-a-guest');
    final text = guest.nodes.firstWhere((node) => node.id == 'text');
    final updated = text.copyWith(
      x: 320,
      width: 450,
      name: 'Edited title',
      payload: (text.payload as TextPayload).copyWith(
        text: 'hello guest',
        fontSize: 32,
      ),
    );
    guest.container.read(documentNodesProvider.notifier).updateNode(updated);
    await _waitFor(
      () =>
          (host.nodes.firstWhere((node) => node.id == 'text').payload
                  as TextPayload)
              .text ==
          'hello guest',
    );
    expect(
      host.nodes.firstWhere((node) => node.id == 'text').toJson(),
      updated.toJson(),
    );
    final next = updated.copyWith(
      x: 640,
      payload: (updated.payload as TextPayload).copyWith(text: 'hello host'),
    );
    host.container.read(documentNodesProvider.notifier).updateNode(next);
    await _waitFor(
      () =>
          (guest.nodes.firstWhere((node) => node.id == 'text').payload
                  as TextPayload)
              .text ==
          'hello host',
    );
    expect(
      guest.nodes.firstWhere((node) => node.id == 'text').toJson(),
      next.toJson(),
    );
  });

  test('renaming a member updates the existing roster identity', () async {
    final server = await _CollaborationServer.start();
    addTearDown(server.close);
    final host = await server.connect('actor-b-host');
    final guest = await server.connect('actor-a-guest');

    final guestUserId = guest.controller.localUserId!;
    await _waitFor(
      () => host.controller.state.members.containsKey(guestUserId),
    );

    await guest.controller.updateDisplayName('Blue Otter 12');
    await _waitFor(
      () =>
          host.controller.state.members[guestUserId]?.displayName ==
          'Blue Otter 12',
    );

    expect(
      host.controller.state.members[guestUserId]?.displayName,
      equals('Blue Otter 12'),
    );
    expect(host.controller.state.members.containsKey(guestUserId), isTrue);
  });

  test(
    'moving Drawing Paper does not disappear into the stroke-only path',
    () async {
      final server = await _CollaborationServer.start();
      addTearDown(server.close);
      final host = await server.connect('actor-b-host');
      final guest = await server.connect('actor-a-guest');
      final paper = guest.nodes.firstWhere((node) => node.id == 'paper');
      final updated = paper.copyWith(x: 420, y: 210, width: 550, rotation: 0.2);
      guest.container.read(documentNodesProvider.notifier).updateNode(updated);
      await _waitFor(
        () =>
            host.nodes.firstWhere((node) => node.id == 'paper').x == updated.x,
      );
      expect(
        host.nodes.firstWhere((node) => node.id == 'paper').toJson(),
        updated.toJson(),
      );
    },
  );

  test('does not persist a snapshot after remote membership removal', () async {
    final server = await _CollaborationServer.start();
    addTearDown(server.close);
    await server.connect('actor-b-host');
    final guest = await server.connect('actor-a-guest');
    final snapshotAttemptsBeforeRemoval = server.snapshotSaveAttempts;

    final controlClient = await server.createClient('actor-b-control');
    addTearDown(controlClient.dispose);
    final controlChannel = controlClient.channel(
      'canvas_room:${server.initial.document.projectId}',
    );
    final subscribed = Completer<void>();
    controlChannel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed &&
          !subscribed.isCompleted) {
        subscribed.complete();
      } else if (!subscribed.isCompleted && error != null) {
        subscribed.completeError(error);
      }
    });
    await subscribed.future.timeout(const Duration(seconds: 2));

    final removal = CollaborationControlEvent(
      eventId: 'remove-guest',
      projectId: server.initial.document.projectId,
      actorId: 'actor-b-host',
      targetUserId: guest.controller.localUserId,
      type: CollaborationControlEventType.memberRemoved,
      payload: const {},
      createdAt: DateTime.utc(2026, 9, 12),
    );
    final response = await controlChannel.sendBroadcastMessage(
      event: 'collaboration_control',
      payload: removal.toJson(),
    );

    expect(response, ChannelResponse.ok);
    await _waitFor(
      () =>
          guest.controller.state.connection ==
          CollaborationConnectionState.disconnected,
    );
    expect(server.snapshotSaveAttempts, snapshotAttemptsBeforeRemoval);
    await controlChannel.unsubscribe();
  });

  test('room revoke disconnects the owner and every connected guest', () async {
    final server = await _CollaborationServer.start();
    addTearDown(server.close);
    final host = await server.connect('actor-b-host');
    final guest = await server.connect('actor-a-guest');
    final guestUserId = guest.controller.localUserId!;

    await _waitFor(
      () => host.controller.state.members.containsKey(guestUserId),
    );
    guest.controller.updatePresence(
      worldPosition: const Offset(120, 80),
      selectedNodeIds: const {'shape'},
      activeNodeId: 'shape',
    );
    await _waitFor(
      () => host.controller.state.collaborators.containsKey(guestUserId),
    );

    await host.controller.disableRoom();
    await _waitFor(
      () =>
          host.controller.state.connection ==
              CollaborationConnectionState.disconnected &&
          guest.controller.state.connection ==
              CollaborationConnectionState.disconnected,
    );
    expect(guest.controller.state.pendingOperations, 0);
    expect(host.controller.state.collaborators, isEmpty);
    expect(host.controller.state.members[guestUserId]?.online, isFalse);
    expect(
      guest.controller.state.screenTracking.status,
      ScreenTrackingStatus.stopped,
    );
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    condition(),
    isTrue,
    reason: 'The remote canvas did not converge in time',
  );
}

class _CanvasClient {
  final SupabaseClient client;
  final ProviderContainer container;
  final CollaborationSessionController controller;
  final ProviderSubscription<CollaborationSessionState> subscription;

  _CanvasClient(
    this.client,
    this.container,
    this.controller,
    this.subscription,
  );

  List<CanvasNode> get nodes => container.read(documentNodesProvider);

  Future<void> close() async {
    await controller.leave();
    subscription.close();
    container.dispose();
    await client.dispose();
  }
}

class _CollaborationServer {
  final HttpServer server;
  final CrdtDocumentSession initial;
  final bool includeInitialSnapshot;
  final DurableProjectStore durableStore;
  final List<_CanvasClient> clients = [];
  final Map<String, CollaborationRole> rolesByActor = {};
  final Map<WebSocket, Map<String, dynamic>> topics = {};
  final Map<String, Map<String, dynamic>> operations = {};
  Map<String, dynamic>? snapshotState;
  Map<String, dynamic>? snapshotVersion;
  int snapshotSaveAttempts = 0;
  bool closing = false;

  _CollaborationServer(
    this.server,
    this.initial,
    this.durableStore, {
    this.includeInitialSnapshot = true,
  });

  static Future<_CollaborationServer> start({
    bool includeInitialSnapshot = true,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final initial = CrdtDocumentSession.fromDocument(
      CanvasDocument(
        projectId: 'project-wire',
        updatedAt: DateTime.utc(2026, 1, 1),
        nodes: [
          CanvasNode(
            id: 'shape',
            type: NodeType.rectangle,
            x: 0,
            y: 0,
            width: 200,
            height: 100,
            payload: ShapePayload(),
          ),
          CanvasNode(
            id: 'text',
            type: NodeType.text,
            x: 0,
            y: 140,
            width: 200,
            height: 80,
            payload: TextPayload(text: 'hello'),
          ),
          CanvasNode(
            id: 'paper',
            type: NodeType.drawingPaper,
            x: 0,
            y: 300,
            width: 400,
            height: 400,
            payload: DrawingPaperPayload(
              layers: [const DrawingLayer(id: 'ink', name: 'Ink')],
            ),
          ),
        ],
      ),
      actorId: 'actor-z-previous-session',
    );
    for (final node in initial.document.nodes) {
      initial.upsertNode(node);
    }
    final durableStore = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    final backend = _CollaborationServer(
      server,
      initial,
      durableStore,
      includeInitialSnapshot: includeInitialSnapshot,
    );
    server.listen(backend._handleRequest);
    return backend;
  }

  Future<SupabaseClient> createClient(String actorId) async {
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions: const RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: Duration.zero,
      ),
      httpClient: MockClient((request) async {
        final body = request.body.trim();
        final params = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
        final response = _handleJsonRequest(
          request.method,
          request.url.pathSegments.last,
          params as Map,
          request.headers['authorization'],
        );
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final expiration =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    String encodePart(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final token =
        '${encodePart({'alg': 'HS256'})}.${encodePart({'sub': actorId, 'exp': expiration})}.test-signature';
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'token_type': 'bearer',
        'expires_at': expiration,
        'expires_in': 3600,
        'refresh_token': 'test-refresh',
        'user': {
          'id': actorId,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    return client;
  }

  Future<_CanvasClient> connect(
    String actorId, {
    CollaborationRole role = CollaborationRole.owner,
  }) async {
    final client = await createClient(actorId);
    await LocalStorageService().saveProjectMetadata(
      LocalProjectMetadata(
        id: initial.document.projectId,
        name: 'Wire test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        collaborationRoomCode: '123456',
        collaborationRole: role.wireName,
        collaborationAccountId: actorId,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        durableProjectStoreProvider.overrideWithValue(durableStore),
      ],
    );
    container
        .read(documentNodesProvider.notifier)
        .setNodes(initial.document.nodes);
    container.read(supabaseSyncServiceProvider);
    final subscription = container.listen(
      collaborationSessionProvider(initial.projectId),
      (_, _) {},
    );
    final controller = container.read(
      collaborationSessionProvider(initial.projectId).notifier,
    );
    rolesByActor[actorId] = role;
    final connected = _CanvasClient(
      client,
      container,
      controller,
      subscription,
    );
    clients.add(connected);
    await controller.start(
      initialDocument: initial.document,
      userId: actorId,
      userName: actorId,
      userColor: Colors.blue,
      role: role,
    );
    expect(
      controller.state.isLive,
      isTrue,
      reason: controller.state.errorMessage,
    );
    return connected;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      topics[socket] = {};
      socket.listen(
        (frame) => _handleFrame(socket, jsonDecode(frame as String) as List),
        onDone: () => topics.remove(socket),
      );
      return;
    }
    final body = await utf8.decoder.bind(request).join();
    final params = body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map;
    final response = _handleJsonRequest(
      request.method,
      request.uri.pathSegments.last,
      params,
      request.headers.value(HttpHeaders.authorizationHeader),
    );
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }

  Object? _handleJsonRequest(
    String method,
    String endpoint,
    Map params,
    String? authorization,
  ) {
    Object? response;
    switch (endpoint) {
      case 'join_collaboration_room':
        final roomCode = params['p_room_code']?.toString() ?? '';
        final actorId = _actorIdFromAuthorization(authorization);
        final role =
            (rolesByActor[actorId] ?? CollaborationRole.editor).wireName;
        response = {
          'id': 'room-$roomCode',
          'project_id': initial.document.projectId,
          'project_name': 'Wire test',
          'room_code': roomCode,
          'role': role,
          'created_at': '2026-01-01T00:00:00Z',
          'expires_at': null,
        };
      case 'workspace_members':
        response = <Map<String, dynamic>>[];
      case 'upsert_workspace_member_profile':
        response = {
          'project_id': initial.projectId,
          'user_id': _actorIdFromAuthorization(authorization),
          'role': 'editor',
          'display_name': params['p_display_name'] ?? 'Collaborator',
          'avatar_url': params['p_avatar_url'],
        };
      case 'get_canvas_crdt_delta':
        final version = CrdtVersionVector.fromJson(params['p_version_vector']);
        final snapshot = snapshotState == null && includeInitialSnapshot
            ? {
                'version': initial.version.toJson(),
                'state': jsonDecode(initial.encodeState()),
              }
            : snapshotState == null
            ? null
            : {
                'version': snapshotVersion ?? const <String, dynamic>{},
                'state': snapshotState,
              };
        response = [
          if (snapshot != null) {'snapshot': snapshot},
          for (final operation in operations.values)
            if ((operation['dot']['counter'] as int) >
                version[operation['dot']['actorId'] as String])
              {'operation': operation},
        ];
      case 'append_canvas_crdt_operation':
        final operation = Map<String, dynamic>.from(
          params['p_operation'] as Map,
        );
        operations[operation['opId'] as String] = operation;
        response = null;
      case 'save_canvas_crdt_snapshot':
        snapshotSaveAttempts++;
        snapshotState = Map<String, dynamic>.from(
          params['p_state_json'] as Map,
        );
        snapshotVersion = Map<String, dynamic>.from(
          params['p_version_vector'] as Map,
        );
        response = null;
      default:
        response = null;
    }
    return response;
  }

  String _actorIdFromAuthorization(String? authorization) {
    if (authorization == null) return 'test-user';
    final token = authorization.replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    );
    final parts = token.split('.');
    if (parts.length < 2) return 'test-user';
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is Map && payload['sub'] is String) {
        return payload['sub'] as String;
      }
    } catch (_) {}
    return 'test-user';
  }

  void _handleFrame(WebSocket socket, List frame) {
    if (socket.readyState != WebSocket.open) return;
    final joinRef = frame[0];
    final reference = frame[1];
    final topic = frame[2] as String;
    final event = frame[3];
    if (event == 'phx_join') topics[socket]![topic] = joinRef;
    _sendFrame(socket, [
      joinRef,
      reference,
      topic,
      'phx_reply',
      {'status': 'ok', 'response': {}},
    ]);
    if (event == 'broadcast') {
      for (final peer in topics.entries) {
        if (peer.key != socket &&
            peer.key.readyState == WebSocket.open &&
            peer.value.containsKey(topic)) {
          _sendFrame(peer.key, [
            peer.value[topic],
            null,
            topic,
            'broadcast',
            frame[4],
          ]);
        }
      }
    }
    if (event == 'phx_leave') topics[socket]?.remove(topic);
  }

  Future<void> close() async {
    closing = true;
    for (final client in clients) {
      await client.close();
    }
    await durableStore.close();
    for (final socket in topics.keys.toList()) {
      await socket.close();
    }
    await server.close(force: true);
  }

  void _sendFrame(WebSocket socket, List frame) {
    try {
      socket.add(jsonEncode(frame));
    } on StateError {
      if (!closing) rethrow;
    }
  }
}
