import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/remote/supabase_service.dart';
import '../../../domain/models/collaboration.dart';
import '../../../domain/models/document.dart';
import '../domain/crdt_engine.dart';

enum CollaborationConnectionState {
  disconnected,
  connecting,
  catchingUp,
  live,
  offline,
  error,
}

Map<String, dynamic>? extractCrdtOperationPayload(
  Map<String, dynamic> payload,
) {
  dynamic candidate = payload;
  for (var depth = 0; depth < 3; depth++) {
    if (candidate is! Map) return null;
    final normalized = Map<String, dynamic>.from(candidate);
    if (normalized['projectId'] is String && normalized['dot'] is Map) {
      return normalized;
    }
    final nestedPayload = normalized['payload'];
    if (nestedPayload is Map) {
      candidate = nestedPayload;
      continue;
    }
    final nestedData = normalized['data'];
    if (nestedData is Map) {
      candidate = nestedData;
      continue;
    }
    return null;
  }
  return null;
}

Map<String, dynamic>? extractCollaborationPresencePayload(
  Map<String, dynamic> payload,
) {
  dynamic candidate = payload;
  for (var depth = 0; depth < 3; depth++) {
    if (candidate is! Map) return null;
    final normalized = Map<String, dynamic>.from(candidate);
    if (normalized['userId'] is String) return normalized;
    final nestedPayload = normalized['payload'];
    if (nestedPayload is Map) {
      candidate = nestedPayload;
      continue;
    }
    final nestedData = normalized['data'];
    if (nestedData is Map) {
      candidate = nestedData;
      continue;
    }
    return null;
  }
  return null;
}

Map<String, dynamic>? extractCollaborationControlPayload(
  Map<String, dynamic> payload,
) {
  dynamic candidate = payload;
  for (var depth = 0; depth < 3; depth++) {
    if (candidate is! Map) return null;
    final normalized = Map<String, dynamic>.from(candidate);
    if (normalized['eventId'] is String &&
        normalized['projectId'] is String &&
        normalized['actorId'] is String &&
        (normalized['controlType'] is String || normalized['type'] is String) &&
        normalized['payload'] is Map) {
      return normalized;
    }
    final nestedPayload = normalized['payload'];
    if (nestedPayload is Map) {
      candidate = nestedPayload;
      continue;
    }
    final nestedData = normalized['data'];
    if (nestedData is Map) {
      candidate = nestedData;
      continue;
    }
    return null;
  }
  return null;
}

bool isLocalCrdtOperation(CrdtOperation operation, String localActorId) =>
    operation.dot.actorId == localActorId;

Map<String, dynamic> roomDisabledBroadcastPayload() => <String, dynamic>{
  'reason': 'host_revoked',
};

class CrdtDelta {
  final CanvasDocument? document;
  final CrdtVersionVector version;
  final Map<String, dynamic> state;
  final List<CanvasComment> comments;
  final List<CrdtOperation> operations;

  CrdtDelta({
    this.document,
    CrdtVersionVector? version,
    this.state = const {},
    this.comments = const [],
    this.operations = const [],
  }) : version = version ?? CrdtVersionVector();
}

CrdtDelta decodeCrdtDeltaResponse(
  Object? response, {
  required String projectId,
  required CrdtVersionVector version,
}) {
  if (response is! List) return CrdtDelta(version: version);

  CanvasDocument? document;
  var nextVersion = version;
  var state = <String, dynamic>{};
  final comments = <CanvasComment>[];
  final operations = <CrdtOperation>[];

  for (final rawRow in response) {
    if (rawRow is! Map) continue;
    final row = Map<String, dynamic>.from(rawRow);
    final rawSnapshot = row['snapshot'];
    if (rawSnapshot is Map) {
      final snapshot = Map<String, dynamic>.from(rawSnapshot);
      nextVersion = CrdtVersionVector.fromJson(snapshot['version']);
      final rawState = snapshot['state'];
      if (rawState is Map) {
        final envelope = Map<String, dynamic>.from(rawState);
        final rawDocument = envelope['document'];
        if (rawDocument is Map) {
          final decoded = CanvasDocument.fromJson(
            Map<String, dynamic>.from(rawDocument),
          );
          if (decoded.projectId != projectId) {
            throw const FormatException(
              'Collaboration delta document project mismatch.',
            );
          }
          document = decoded;
        }
        final rawCrdt = envelope['crdt'];
        if (rawCrdt is Map) {
          state = Map<String, dynamic>.from(rawCrdt);
        }
        final rawComments = envelope['comments'];
        if (rawComments is List) {
          comments.addAll(
            rawComments.whereType<Map>().map(
              (comment) =>
                  CanvasComment.fromJson(Map<String, dynamic>.from(comment)),
            ),
          );
        }
      }
    }
    final rawOperation = row['operation'];
    if (rawOperation is Map) {
      try {
        final operation = CrdtOperation.fromJson(
          Map<String, dynamic>.from(rawOperation),
        );
        if (operation.projectId != projectId) {
          throw const FormatException(
            'Collaboration delta operation project mismatch.',
          );
        }
        operations.add(operation);
      } catch (error) {
        if (error is FormatException &&
            error.message.contains('project mismatch')) {
          rethrow;
        }
        debugPrint('[CollaborationTransport] Ignoring invalid delta: $error');
      }
    }
  }

  return CrdtDelta(
    document: document,
    version: nextVersion,
    state: state,
    comments: comments,
    operations: operations,
  );
}

class SupabaseCollaborationTransport {
  final SupabaseClient? Function() _clientProvider;
  final void Function(CrdtOperation operation)? onRemoteOperation;
  final void Function(Map<String, dynamic> presence)? onRemotePresence;
  final void Function(Map<String, dynamic> presence)? onPresenceJoin;
  final void Function(String userId)? onPresenceLeave;
  final void Function(Map<String, dynamic> presence)? onPresenceLeavePayload;
  final void Function(CollaborationControlEvent event)? onControlEvent;
  final VoidCallback? onRoomDisabled;
  final void Function(CollaborationConnectionState state, Object? error)?
  onConnectionStateChanged;

  RealtimeChannel? _channel;
  bool _subscribed = false;
  Future<void>? _joinFuture;
  Timer? _reconnectTimer;
  Timer? _memberLifecycleTimer;
  Completer<void>? _subscriptionReady;
  bool _keepConnected = false;
  bool _reconnecting = false;
  int _reconnectAttempt = 0;
  int _channelGeneration = 0;
  int _joinIntent = 0;
  String? _accountId;
  String? _projectId;
  String? _userId;
  String? _memberId;
  String? _userName;
  Color? _userColor;

  SupabaseCollaborationTransport(
    SupabaseClient? client, {
    SupabaseClient? Function()? clientProvider,
    this.onRemoteOperation,
    this.onRemotePresence,
    this.onPresenceJoin,
    this.onPresenceLeave,
    this.onPresenceLeavePayload,
    this.onControlEvent,
    this.onRoomDisabled,
    this.onConnectionStateChanged,
  }) : _clientProvider = clientProvider ?? (() => client);

  SupabaseClient? get _client {
    try {
      return _clientProvider();
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => _client != null;
  bool get isConnected => _subscribed;

  bool _accountIsCurrent([int? generation]) {
    if (generation != null && generation != _channelGeneration) return false;
    final client = _client;
    final currentAccountId =
        client?.auth.currentUser?.id ?? client?.auth.currentSession?.user.id;
    return _accountId != null && currentAccountId == _accountId;
  }

  bool _channelIsCurrent(RealtimeChannel channel, int generation) =>
      identical(_channel, channel) &&
      generation == _channelGeneration &&
      _accountIsCurrent(generation);

  bool _joinIntentMatches(int intent, String expectedAccountId) {
    if (intent != _joinIntent) return false;
    final currentUser =
        _client?.auth.currentUser ?? _client?.auth.currentSession?.user;
    return currentUser?.id == expectedAccountId;
  }

  bool _joinIntentIsActive(int intent, String expectedAccountId) =>
      _keepConnected && _joinIntentMatches(intent, expectedAccountId);

  void _ensureAccountCurrent() {
    if (!_accountIsCurrent()) {
      throw const SyncException('Collaboration session is no longer active.');
    }
  }

  void updateLocalUserName(String userName) {
    _userName = userName.trim().isEmpty ? 'Collaborator' : userName.trim();
  }

  Future<void> join({
    required String projectId,
    required String userId,
    String? memberId,
    String? accountId,
    required String userName,
    required Color userColor,
  }) {
    final activeJoin = _joinFuture;
    if (activeJoin != null) return activeJoin;

    final joinIntent = ++_joinIntent;
    final joinFuture = _joinWithRetry(
      projectId: projectId,
      userId: userId,
      memberId: memberId,
      accountId: accountId,
      userName: userName,
      userColor: userColor,
      joinIntent: joinIntent,
    );
    _joinFuture = joinFuture;
    return joinFuture.whenComplete(() {
      if (identical(_joinFuture, joinFuture)) _joinFuture = null;
    });
  }

  Future<void> _joinWithRetry({
    required String projectId,
    required String userId,
    String? memberId,
    String? accountId,
    required String userName,
    required Color userColor,
    required int joinIntent,
  }) async {
    final expectedAccountId =
        accountId ??
        _client?.auth.currentUser?.id ??
        _client?.auth.currentSession?.user.id;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _joinOnce(
          projectId: projectId,
          userId: userId,
          memberId: memberId,
          accountId: accountId,
          userName: userName,
          userColor: userColor,
          joinIntent: joinIntent,
        );
        return;
      } catch (error) {
        if (!_keepConnected ||
            attempt == 1 ||
            _isNonRetryableJoinError(error)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final currentUser =
            _client?.auth.currentUser ?? _client?.auth.currentSession?.user;
        if (!_keepConnected ||
            expectedAccountId == null ||
            currentUser?.id != expectedAccountId) {
          throw const SyncException(
            'Realtime collaboration channel was closed.',
          );
        }
      }
    }
  }

  bool _isNonRetryableJoinError(Object error) =>
      error is SyncException &&
      (error.message == 'Cloud backend is not configured.' ||
          error.message.contains('Sign in is required'));

  Future<void> _joinOnce({
    required String projectId,
    required String userId,
    String? memberId,
    String? accountId,
    required String userName,
    required Color userColor,
    required int joinIntent,
  }) async {
    final client = _client;
    if (client == null) return;
    final user = client.auth.currentUser ?? client.auth.currentSession?.user;
    if (user == null) {
      throw const SyncException(
        'Sign in is required before joining a collaboration room.',
      );
    }

    final expectedGeneration = _channelGeneration + 1;
    final expectedAccountId = accountId ?? user.id;
    if (!_joinIntentMatches(joinIntent, expectedAccountId)) {
      throw const SyncException('Realtime collaboration channel was closed.');
    }
    await leave(updateState: false, invalidateJoinIntent: false);
    if (_channelGeneration != expectedGeneration ||
        !_joinIntentMatches(joinIntent, expectedAccountId)) {
      throw const SyncException('Realtime collaboration channel was closed.');
    }
    final currentUser =
        _client?.auth.currentUser ?? _client?.auth.currentSession?.user;
    if (currentUser == null || currentUser.id != expectedAccountId) {
      throw const SyncException(
        'Sign in is required before joining a collaboration room.',
      );
    }
    final generation = _channelGeneration;
    _accountId = expectedAccountId;
    _keepConnected = true;
    if (!_reconnecting) _reconnectAttempt = 0;
    _projectId = projectId;
    _userId = userId;
    _memberId = memberId;
    _userName = userName;
    _userColor = userColor;
    if (!_joinIntentIsActive(joinIntent, expectedAccountId)) {
      throw const SyncException('Realtime collaboration channel was closed.');
    }
    _setState(CollaborationConnectionState.connecting);
    if (!_joinIntentIsActive(joinIntent, expectedAccountId)) {
      throw const SyncException('Realtime collaboration channel was closed.');
    }
    final channel = client.channel('canvas_room:$projectId');
    if (!_joinIntentIsActive(joinIntent, expectedAccountId)) {
      await channel.unsubscribe();
      throw const SyncException('Realtime collaboration channel was closed.');
    }
    final subscriptionReady = Completer<void>();
    _subscriptionReady = subscriptionReady;

    channel.onBroadcast(
      event: 'crdt_operation',
      callback: (payload) {
        if (!_channelIsCurrent(channel, generation)) return;
        _handleOperationBroadcast(payload, projectId, userId);
      },
    );

    channel.onBroadcast(
      event: 'comment_operation',
      callback: (payload) {
        if (!_channelIsCurrent(channel, generation)) return;
        _handleOperationBroadcast(payload, projectId, userId);
      },
    );

    channel.onBroadcast(
      event: 'cursor_update',
      callback: (payload) {
        if (!_channelIsCurrent(channel, generation)) return;
        _handlePresenceBroadcast(payload, userId);
      },
    );

    channel.onBroadcast(
      event: 'collaboration_control',
      callback: (payload) {
        if (!_channelIsCurrent(channel, generation)) return;
        _handleControlBroadcast(payload, projectId, userId);
      },
    );

    channel.onBroadcast(
      event: 'room_disabled',
      callback: (_) {
        if (!_channelIsCurrent(channel, generation)) return;
        _keepConnected = false;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _memberLifecycleTimer?.cancel();
        _memberLifecycleTimer = null;
        onRoomDisabled?.call();
      },
    );

    // Do not use Realtime Presence for high-churn canvas state. Supabase
    // applies a strict Presence track rate limit, and a reconnect storm can
    // turn an otherwise healthy room into a channelError. Cursor/viewport
    // updates use broadcast instead; these low-frequency lifecycle events
    // provide roster join/leave notifications without calling track().
    channel.onBroadcast(
      event: 'member_joined',
      callback: (payload) {
        if (!_channelIsCurrent(channel, generation)) return;
        _handleMemberLifecycleBroadcast(payload, userId, joined: true);
      },
    );
    channel.onBroadcast(
      event: 'member_left',
      callback: (payload) {
        if (!_channelIsCurrent(channel, generation)) return;
        _handleMemberLifecycleBroadcast(payload, userId, joined: false);
      },
    );
    channel.onBroadcast(
      event: 'member_heartbeat',
      callback: (payload) {
        if (!_channelIsCurrent(channel, generation)) return;
        _handleMemberLifecycleBroadcast(payload, userId, joined: true);
      },
    );

    if (!_joinIntentIsActive(joinIntent, expectedAccountId)) {
      await channel.unsubscribe();
      throw const SyncException('Realtime collaboration channel was closed.');
    }
    _channel = channel;
    channel.subscribe((status, [error]) {
      if (!_channelIsCurrent(channel, generation)) return;
      debugPrint(
        '[CollaborationTransport] canvas_room:$projectId status=$status error=$error',
      );
      if (status == RealtimeSubscribeStatus.subscribed) {
        _subscribed = true;
        _reconnectAttempt = 0;
        _setState(CollaborationConnectionState.catchingUp);
        if (!subscriptionReady.isCompleted) subscriptionReady.complete();
        unawaited(
          _announceMemberLifecycle(
            channel,
            generation: generation,
            userId: userId,
            memberId: memberId,
            userName: userName,
            userColor: userColor,
            joined: true,
          ),
        );
        _startMemberLifecycleHeartbeat(
          channel,
          generation: generation,
          userId: userId,
          memberId: memberId,
          userName: userName,
          userColor: userColor,
        );
      } else if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _subscribed = false;
        _memberLifecycleTimer?.cancel();
        _memberLifecycleTimer = null;
        _channel = null;
        final reason =
            error ?? StateError('Realtime channel subscription $status.');
        if (!subscriptionReady.isCompleted) {
          subscriptionReady.completeError(reason);
        }
        _setState(CollaborationConnectionState.offline, reason);
        unawaited(client.removeChannel(channel).catchError((_) => 'error'));
        _scheduleReconnect();
      }
    });

    if (!_joinIntentIsActive(joinIntent, expectedAccountId)) {
      _channel = null;
      _subscribed = false;
      if (identical(_subscriptionReady, subscriptionReady)) {
        _subscriptionReady = null;
      }
      await channel.unsubscribe();
      throw const SyncException('Realtime collaboration channel was closed.');
    }

    try {
      await subscriptionReady.future.timeout(const Duration(seconds: 15));
      if (!_channelIsCurrent(channel, generation) ||
          !_joinIntentIsActive(joinIntent, expectedAccountId)) {
        throw const SyncException('Realtime collaboration channel was closed.');
      }
    } finally {
      if (identical(_subscriptionReady, subscriptionReady)) {
        _subscriptionReady = null;
      }
    }
  }

  void _handleOperationBroadcast(
    Map<String, dynamic> payload,
    String projectId,
    String localUserId,
  ) {
    final operationPayload = extractCrdtOperationPayload(payload);
    if (operationPayload == null ||
        operationPayload['projectId'] != projectId ||
        operationPayload['opId'] is! String ||
        operationPayload['dot'] is! Map) {
      return;
    }
    final dot = Map<String, dynamic>.from(operationPayload['dot'] as Map);
    if (dot['actorId'] is! String || dot['counter'] is! num) return;
    try {
      final operation = CrdtOperation.fromJson(operationPayload);
      if (isLocalCrdtOperation(operation, localUserId)) return;
      onRemoteOperation?.call(operation);
    } catch (error) {
      debugPrint('[CollaborationTransport] Invalid operation payload: $error');
    }
  }

  void _handlePresenceBroadcast(
    Map<String, dynamic> payload,
    String localUserId,
  ) {
    final presence = extractCollaborationPresencePayload(payload);
    if (presence == null ||
        presence['userId']?.toString() == localUserId ||
        presence['userId']?.toString() == _memberId ||
        presence['sessionId']?.toString() == localUserId) {
      return;
    }
    onRemotePresence?.call(presence);
  }

  void _handleMemberLifecycleBroadcast(
    Map<String, dynamic> payload,
    String localUserId, {
    required bool joined,
  }) {
    final presence = extractCollaborationPresencePayload(payload);
    if (presence == null) return;
    final remoteUserId = presence['userId']?.toString();
    if (remoteUserId == null ||
        remoteUserId.isEmpty ||
        remoteUserId == localUserId ||
        remoteUserId == _memberId ||
        presence['sessionId']?.toString() == localUserId) {
      return;
    }
    if (joined) {
      onPresenceJoin?.call(presence);
    } else {
      onPresenceLeave?.call(remoteUserId);
      onPresenceLeavePayload?.call(presence);
    }
  }

  Future<void> _announceMemberLifecycle(
    RealtimeChannel channel, {
    int? generation,
    required String userId,
    String? memberId,
    required String userName,
    required Color userColor,
    required bool joined,
    bool heartbeat = false,
  }) async {
    if ((generation != null && !_channelIsCurrent(channel, generation)) ||
        !_subscribed) {
      return;
    }
    try {
      final response = await channel.sendBroadcastMessage(
        event: heartbeat
            ? 'member_heartbeat'
            : joined
            ? 'member_joined'
            : 'member_left',
        payload: {
          'userId': memberId ?? userId,
          'sessionId': userId,
          'userName': userName,
          'userColor': userColor.toARGB32(),
          'x': 0.0,
          'y': 0.0,
          'selectedNodeIds': const <String>[],
          'activeNodeId': null,
          'editing': false,
          'viewportX': 0.0,
          'viewportY': 0.0,
          'viewportZoom': 1.0,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (response != ChannelResponse.ok) {
        debugPrint(
          '[CollaborationTransport] Member lifecycle broadcast returned $response.',
        );
      }
    } catch (error) {
      debugPrint(
        '[CollaborationTransport] Member lifecycle broadcast failed: $error',
      );
    }
  }

  void _startMemberLifecycleHeartbeat(
    RealtimeChannel channel, {
    required int generation,
    required String userId,
    String? memberId,
    required String userName,
    required Color userColor,
  }) {
    _memberLifecycleTimer?.cancel();
    _memberLifecycleTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_channelIsCurrent(channel, generation)) return;
      unawaited(
        _announceMemberLifecycle(
          channel,
          generation: generation,
          userId: userId,
          memberId: memberId,
          userName: userName,
          userColor: userColor,
          joined: true,
          heartbeat: true,
        ),
      );
    });
  }

  void _handleControlBroadcast(
    Map<String, dynamic> payload,
    String projectId,
    String localUserId,
  ) {
    final controlPayload = extractCollaborationControlPayload(payload);
    if (controlPayload == null) {
      return;
    }
    final event = CollaborationControlEvent.tryParse(controlPayload);
    if (event == null ||
        event.projectId != projectId ||
        event.actorId == localUserId) {
      return;
    }
    onControlEvent?.call(event);
  }

  void _scheduleReconnect() {
    if (!_keepConnected ||
        !_accountIsCurrent() ||
        _reconnectTimer != null ||
        _client == null) {
      return;
    }
    final projectId = _projectId;
    final userId = _userId;
    final memberId = _memberId;
    final userName = _userName;
    final userColor = _userColor;
    if (projectId == null ||
        userId == null ||
        userName == null ||
        userColor == null) {
      return;
    }
    const delays = [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ];
    final delay = delays[_reconnectAttempt.clamp(0, delays.length - 1).toInt()];
    final generation = _channelGeneration;
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (generation != _channelGeneration) return;
      unawaited(
        _reconnect(
          projectId,
          userId,
          memberId,
          userName,
          userColor,
          generation: generation,
        ),
      );
    });
  }

  Future<void> _reconnect(
    String projectId,
    String userId,
    String? memberId,
    String userName,
    Color userColor, {
    required int generation,
  }) async {
    if (!_keepConnected ||
        generation != _channelGeneration ||
        !_accountIsCurrent() ||
        _reconnecting) {
      return;
    }
    _reconnecting = true;
    try {
      await join(
        projectId: projectId,
        userId: userId,
        memberId: memberId,
        accountId: _accountId,
        userName: userName,
        userColor: userColor,
      );
    } catch (error) {
      _setState(CollaborationConnectionState.offline, error);
      _scheduleReconnect();
    } finally {
      _reconnecting = false;
    }
  }

  Future<CrdtDelta> fetchDelta({
    required String projectId,
    required CrdtVersionVector version,
  }) async {
    _ensureAccountCurrent();
    final client = _client;
    if (client == null) return CrdtDelta(version: version);
    final response = await client.rpc(
      'get_canvas_crdt_delta',
      params: {'p_project_id': projectId, 'p_version_vector': version.toJson()},
    );
    return decodeCrdtDeltaResponse(
      response,
      projectId: projectId,
      version: version,
    );
  }

  Future<void> append(CrdtOperation operation) async {
    _ensureAccountCurrent();
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    await client.rpc(
      'append_canvas_crdt_operation',
      params: {
        'p_project_id': operation.projectId,
        'p_operation': operation.toPersistenceJson(),
      },
    );
  }

  Future<void> broadcast(CrdtOperation operation) async {
    _ensureAccountCurrent();
    final channel = _channel;
    if (channel == null || !_subscribed) {
      throw const SyncException('Realtime collaboration channel is offline.');
    }
    final event = operation.kind.name.startsWith('comment')
        ? 'comment_operation'
        : 'crdt_operation';
    final response = await channel.sendBroadcastMessage(
      event: event,
      payload: operation.toPersistenceJson(),
    );
    if (response != ChannelResponse.ok) {
      throw SyncException('Realtime broadcast returned $response.');
    }
  }

  Future<void> broadcastRoomDisabled() async {
    _ensureAccountCurrent();
    final channel = _channel;
    if (channel == null || !_subscribed) return;
    try {
      await channel.sendBroadcastMessage(
        event: 'room_disabled',
        payload: roomDisabledBroadcastPayload(),
      );
    } catch (error) {
      debugPrint(
        '[CollaborationTransport] Room disabled broadcast failed: $error',
      );
    }
  }

  Future<void> publish(CrdtOperation operation) async {
    // The database append is the durable source of truth. A broadcast can
    // fail during a transient websocket reconnect even after the operation is
    // safely stored; receivers catch it through the next delta/catch-up.
    await append(operation);
    try {
      await broadcast(operation);
    } catch (error) {
      debugPrint(
        '[CollaborationTransport] Realtime broadcast deferred after durable append: $error',
      );
    }
  }

  Future<void> updateCheckpoint({
    required String projectId,
    required CrdtVersionVector version,
  }) async {
    _ensureAccountCurrent();
    final client = _client;
    final userId =
        client?.auth.currentUser?.id ?? client?.auth.currentSession?.user.id;
    if (client == null || userId == null) return;
    await client.from('canvas_collaboration_checkpoints').upsert({
      'project_id': projectId,
      'user_id': userId,
      'version_vector': version.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> saveSnapshot({
    required String projectId,
    required Map<String, dynamic> state,
    required CrdtVersionVector version,
  }) async {
    _ensureAccountCurrent();
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    await client.rpc(
      'save_canvas_crdt_snapshot',
      params: {
        'p_project_id': projectId,
        'p_state_json': state,
        'p_version_vector': version.toJson(),
      },
    );
  }

  Future<void> trackPresence(Map<String, dynamic> presence) async {
    // Preserve the old API without using Supabase Presence track(). Presence
    // has a strict server-side rate limit; canvas cursors use broadcast.
    await broadcastPresence(presence);
  }

  Future<void> broadcastPresence(Map<String, dynamic> presence) async {
    _ensureAccountCurrent();
    final channel = _channel;
    if (channel == null || !_subscribed) {
      throw const SyncException('Realtime collaboration channel is offline.');
    }
    final response = await channel.sendBroadcastMessage(
      event: 'cursor_update',
      payload: presence,
    );
    if (response != ChannelResponse.ok) {
      throw SyncException('Realtime cursor broadcast returned $response.');
    }
  }

  Future<void> broadcastControlEvent(CollaborationControlEvent event) async {
    _ensureAccountCurrent();
    final channel = _channel;
    if (channel == null || !_subscribed) {
      throw const SyncException('Realtime collaboration channel is offline.');
    }
    final response = await channel.sendBroadcastMessage(
      event: 'collaboration_control',
      payload: event.toJson(),
    );
    if (response != ChannelResponse.ok) {
      throw SyncException('Realtime collaboration control returned $response.');
    }
  }

  Future<void> leave({
    bool updateState = true,
    bool invalidateJoinIntent = true,
  }) async {
    if (invalidateJoinIntent) _joinIntent++;
    _channelGeneration++;
    _keepConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _memberLifecycleTimer?.cancel();
    _memberLifecycleTimer = null;
    final subscriptionReady = _subscriptionReady;
    _subscriptionReady = null;
    if (subscriptionReady != null && !subscriptionReady.isCompleted) {
      subscriptionReady.completeError(
        const SyncException('Realtime collaboration channel was closed.'),
      );
    }
    if (updateState) _reconnecting = false;
    final channel = _channel;
    final userId = _userId;
    final memberId = _memberId;
    final userName = _userName;
    final userColor = _userColor;
    if (updateState &&
        channel != null &&
        _subscribed &&
        userId != null &&
        userName != null &&
        userColor != null) {
      await _announceMemberLifecycle(
        channel,
        userId: userId,
        memberId: memberId,
        userName: userName,
        userColor: userColor,
        joined: false,
      );
    }
    _projectId = null;
    _userId = null;
    _memberId = null;
    _userName = null;
    _userColor = null;
    _accountId = null;
    _channel = null;
    _subscribed = false;
    if (channel != null) await channel.unsubscribe();
    if (updateState) _setState(CollaborationConnectionState.disconnected);
  }

  void _setState(CollaborationConnectionState state, [Object? error]) {
    onConnectionStateChanged?.call(state, error);
  }
}
