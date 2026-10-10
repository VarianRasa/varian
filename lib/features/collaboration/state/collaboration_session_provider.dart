import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/remote/supabase_storage_path_resolver.dart';
import '../../../data/local/account_scoped_local_storage.dart';
import '../../../data/local/durable/project_session.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../data/remote/supabase_sync_provider.dart';
import '../../../domain/models/collaboration.dart';
import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/document.dart';
import '../../../domain/models/document_asset.dart';
import '../../../domain/models/design_tokens.dart';
import '../../../domain/models/drawing_paper_payload.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../canvas/state/document_edges_provider.dart';
import '../../drawing_paper/domain/models/raster_edit_operation.dart';
import '../../canvas/state/document_assets_provider.dart';
import '../../canvas/state/document_nodes_provider.dart';
import '../../canvas/state/design_token_provider.dart';
import '../../canvas/state/viewport_provider.dart';
import '../data/screen_tracking_service.dart';
import '../data/supabase_collaboration_transport.dart';
import '../domain/comment_notifications.dart';
import '../domain/crdt_engine.dart';
import '../domain/sync_models.dart';
import 'collaboration_provider.dart';
import '../../meeting/domain/meeting_models.dart';
import '../../meeting/state/meeting_controller.dart';

export '../data/supabase_collaboration_transport.dart';

List<CrdtOperation> coalescePendingNodeOperations(
  List<CrdtOperation> operations, {
  int preservePrefix = 0,
}) {
  final result = <CrdtOperation>[];
  final latestNodeOperationIndex = <String, int>{};
  for (var index = 0; index < operations.length; index++) {
    final operation = operations[index];
    if (index < preservePrefix ||
        operation.kind != CrdtOperationKind.nodeUpsert) {
      latestNodeOperationIndex.remove(operation.targetId);
      result.add(operation);
      continue;
    }

    final previousIndex = latestNodeOperationIndex[operation.targetId];
    if (previousIndex == null) {
      latestNodeOperationIndex[operation.targetId] = result.length;
      result.add(operation);
    } else {
      final previous = result[previousIndex];
      result[previousIndex] = operation.withDependencies(previous.dependencies);
    }
  }
  return result;
}

Map<String, dynamic> _recoveryOperationJson(CrdtOperation operation) {
  final json = operation.toPersistenceJson();
  return {...json, 'value': _redactRecoveryValue(json['value'])};
}

Object? _redactRecoveryValue(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _isSensitiveRecoveryKey(entry.key.toString())
            ? '[REDACTED]'
            : _redactRecoveryValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_redactRecoveryValue).toList(growable: false);
  }
  return value;
}

bool _isSensitiveRecoveryKey(String key) => RegExp(
  r'(token|secret|password|authorization|api[_-]?key|access[_-]?token|signed[_-]?url)',
  caseSensitive: false,
).hasMatch(key);

@visibleForTesting
final collaborationVerifiedRoleForTestingProvider =
    Provider<CollaborationRole?>((ref) => null);

final collaborationSessionProvider = StateNotifierProvider.autoDispose
    .family<CollaborationSessionController, CollaborationSessionState, String>(
      (ref, projectId) => CollaborationSessionController(
        ref,
        projectId,
        onMeetingTermination: (reason) async {
          if (!ref.exists(meetingControllerProvider(projectId))) return;
          final meetingProvider = meetingControllerProvider(projectId);
          final meetingState = ref.read(meetingProvider);
          if (reason == MeetingTerminationReason.roomRevoked &&
              meetingState.isHost &&
              meetingState.meetingId != null) {
            try {
              await ref
                  .read(meetingRepositoryProvider(projectId))
                  .endMeeting(
                    meetingId: meetingState.meetingId!,
                    reason: 'room_revoked',
                  );
            } catch (_) {
              // Local cleanup and collaboration leave still run if the
              // durable operation has already won a race or is unavailable.
            }
          }
          final controller = ref.read(meetingProvider.notifier);
          await controller.handleExternalTermination(reason);
        },
        onMeetingParticipantRemoved: (identity) async {
          if (!ref.exists(meetingControllerProvider(projectId))) return;
          final controller = ref.read(
            meetingControllerProvider(projectId).notifier,
          );
          await controller.removeParticipant(identity);
        },
      ),
    );

class CollaborationSessionState {
  final String projectId;
  final CollaborationConnectionState connection;
  final CollaborationRole role;
  final int pendingOperations;
  final CollaborationSyncStatus syncStatus;
  final List<CollaborationConflict> conflicts;
  final Map<String, RemotePresence> collaborators;
  final Map<String, CanvasMember> members;
  final String? followingUserId;
  final CollaborationControlEvent? followRequest;
  final ScreenTrackingSnapshot screenTracking;
  final CollaborationControlEvent? screenShareRequest;
  final CollaborationNotice? notice;
  final String? errorMessage;

  const CollaborationSessionState({
    required this.projectId,
    this.connection = CollaborationConnectionState.disconnected,
    this.role = CollaborationRole.viewer,
    this.pendingOperations = 0,
    this.syncStatus = CollaborationSyncStatus.synced,
    this.conflicts = const [],
    this.collaborators = const {},
    this.members = const {},
    this.followingUserId,
    this.followRequest,
    this.screenTracking = const ScreenTrackingSnapshot(
      status: ScreenTrackingStatus.idle,
    ),
    this.screenShareRequest,
    this.notice,
    this.errorMessage,
  });

  bool get isLive => connection == CollaborationConnectionState.live;
  bool get isOffline => connection == CollaborationConnectionState.offline;
  CollaborationPermissions get permissions => CollaborationPermissions(role);
  bool get isHost => permissions.isHost;

  int get participantCount => switch (connection) {
    CollaborationConnectionState.disconnected ||
    CollaborationConnectionState.offline ||
    CollaborationConnectionState.error => 0,
    _ =>
      members.values.where((member) => member.online).isNotEmpty
          ? members.values.where((member) => member.online).length
          : collaborators.length + 1,
  };

  CollaborationSessionState copyWith({
    CollaborationConnectionState? connection,
    CollaborationRole? role,
    int? pendingOperations,
    CollaborationSyncStatus? syncStatus,
    List<CollaborationConflict>? conflicts,
    Map<String, RemotePresence>? collaborators,
    Map<String, CanvasMember>? members,
    String? followingUserId,
    CollaborationControlEvent? followRequest,
    ScreenTrackingSnapshot? screenTracking,
    CollaborationControlEvent? screenShareRequest,
    CollaborationNotice? notice,
    bool clearFollowingUser = false,
    bool clearFollowRequest = false,
    bool clearScreenShareRequest = false,
    String? errorMessage,
    bool clearError = false,
  }) => CollaborationSessionState(
    projectId: projectId,
    connection: connection ?? this.connection,
    role: role ?? this.role,
    pendingOperations: pendingOperations ?? this.pendingOperations,
    syncStatus: syncStatus ?? this.syncStatus,
    conflicts: conflicts ?? this.conflicts,
    collaborators: collaborators ?? this.collaborators,
    members: members ?? this.members,
    followingUserId: clearFollowingUser
        ? null
        : (followingUserId ?? this.followingUserId),
    followRequest: clearFollowRequest
        ? null
        : (followRequest ?? this.followRequest),
    screenTracking: screenTracking ?? this.screenTracking,
    screenShareRequest: clearScreenShareRequest
        ? null
        : (screenShareRequest ?? this.screenShareRequest),
    notice: notice ?? this.notice,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

class RemotePresence {
  final String userId;
  final String userName;
  final Color userColor;
  final double x;
  final double y;
  final Set<String> selectedNodeIds;
  final String? activeNodeId;
  final bool editing;
  final double viewportX;
  final double viewportY;
  final double viewportZoom;
  final DateTime lastActive;

  const RemotePresence({
    required this.userId,
    required this.userName,
    required this.userColor,
    required this.x,
    required this.y,
    this.selectedNodeIds = const {},
    this.activeNodeId,
    this.editing = false,
    this.viewportX = 0,
    this.viewportY = 0,
    this.viewportZoom = 1,
    required this.lastActive,
  });

  RemoteCursor get cursor => RemoteCursor(
    userId: userId,
    userName: userName,
    userColor: userColor,
    x: x,
    y: y,
    selectedNodeId: activeNodeId,
    lastActive: lastActive,
  );
}

final _activeCollaborationControllers = <CollaborationSessionController>{};

Future<void> discardActiveCollaborationCloudState({
  String? expectedAccountId,
}) async {
  final pending = [
    for (final controller in List<CollaborationSessionController>.of(
      _activeCollaborationControllers,
    ))
      if (expectedAccountId == null ||
          controller.localAccountId == expectedAccountId)
        controller.discardCloudStateOnDispose(),
  ];
  await Future.wait(pending);
}

class CollaborationSessionController
    extends StateNotifier<CollaborationSessionState> {
  static const _presenceExpiry = Duration(seconds: 50);

  final Ref _ref;
  final String projectId;
  final Future<void> Function(MeetingTerminationReason reason)?
  _onMeetingTermination;
  final Future<void> Function(String identity)? _onMeetingParticipantRemoved;
  late final SupabaseCollaborationTransport _transport;
  late final SupabaseSyncService _syncService = _ref.read(
    supabaseSyncServiceProvider,
  );
  final LocalStorageService _localStorage = LocalStorageService();
  late final ProjectSession _projectSession = _ref.read(
    projectSessionProvider(projectId),
  );
  final List<CrdtOperation> _pending = [];
  final Map<String, Future<void>> _assetUploadInFlight = {};
  final Map<String, String> _assetUploadFingerprints = {};
  Future<void>? _leaveFuture;
  Timer? _presenceTimer;
  Timer? _presenceExpiryTimer;
  Timer? _memberHeartbeatTimer;
  bool _memberHeartbeatInFlight = false;
  Map<String, dynamic>? _pendingPresence;
  Map<String, dynamic>? _lastPresencePayload;
  final Map<String, DateTime> _remotePresenceSeenAt = {};
  bool _presenceSending = false;
  bool _started = false;
  bool _leaving = false;
  bool _disposed = false;
  bool _discardCloudStateOnDispose = false;
  int _accountQueueGeneration = 0;
  int _lifecycleGeneration = 0;
  bool _readOnly = false;
  bool _membershipRevoked = false;
  CollaborationRole _role = CollaborationRole.viewer;
  bool _hasVerifiedMembership = false;
  bool _remoteApply = false;
  bool _suppressStateUpdates = false;
  Future<void>? _flushFuture;
  Future<void>? _pendingQueueSave;
  CrdtOperation? _inFlightOperation;
  Future<void>? _reconnectCatchUpFuture;
  CrdtDocumentSession? _session;
  late final ScreenTrackingService _screenTracking;
  String? _screenPeerUserId;
  String? _localUserId;
  String? _localAccountId;
  String? _localUserName;
  Color? _localUserColor;

  CollaborationProjectionScope get _projectionScope =>
      CollaborationProjectionScope(
        projectId: projectId,
        accountId: _localAccountId ?? 'local-device',
      );

  CommentsNotifier get _projectComments =>
      _ref.read(collaborationCommentsProvider(_projectionScope).notifier);

  RemoteCursorsNotifier get _projectCursors =>
      _ref.read(collaborationRemoteCursorsProvider(_projectionScope).notifier);

  void _clearProjectComments() {
    _projectComments.clear();
    if (_localAccountId == null) _ref.read(commentsProvider.notifier).clear();
  }

  void _clearProjectCursors() {
    _projectCursors.clearCursors();
    if (_localAccountId == null) {
      _ref.read(remoteCursorsProvider.notifier).clearCursors();
    }
  }

  CollaborationSessionController(
    this._ref,
    this.projectId, {
    this._onMeetingTermination,
    this._onMeetingParticipantRemoved,
  }) : super(CollaborationSessionState(projectId: projectId)) {
    _activeCollaborationControllers.add(this);
    _transport = SupabaseCollaborationTransport(
      _ref.read(supabaseClientProvider),
      clientProvider: () => _ref.read(supabaseClientProvider),
      onRemoteOperation: _handleRemoteOperation,
      onRemotePresence: _handleRemotePresence,
      onPresenceJoin: _handlePresenceJoin,
      onPresenceLeavePayload: _handlePresenceLeave,
      onControlEvent: _handleControlEvent,
      onRoomDisabled: _handleRoomDisabled,
      onConnectionStateChanged: _handleConnectionState,
    );
    _screenTracking = ScreenTrackingService(
      onSignal: _sendScreenSignal,
      onChanged: _handleScreenTrackingChanged,
    );
    _ref.listen<List<CanvasNode>>(documentNodesProvider, (previous, next) {
      _recordNodeTransition(previous ?? const [], next);
    });
    _ref.listen<List<CanvasEdge>>(documentEdgesProvider, (previous, next) {
      _recordEdgeTransition(previous ?? const [], next);
    });
    _ref.listen<DocumentAssetManifest>(documentAssetsProvider, (
      previous,
      next,
    ) {
      _recordAssetTransition(previous ?? const DocumentAssetManifest(), next);
    });
    _ref.listen<DesignTokenSet>(designTokenSetProvider, (previous, next) {
      _recordTokenTransition(previous ?? const DesignTokenSet(), next);
    });
  }

  /// Prevents account-scoped cloud state from being persisted while a route
  /// is being torn down for sign-out or account switching.
  Future<void> discardCloudStateOnDispose() async {
    _lifecycleGeneration++;
    _discardCloudStateOnDispose = true;
    _pending.clear();
    _inFlightOperation = null;
    _pendingPresence = null;
    _lastPresencePayload = null;
    _remotePresenceSeenAt.clear();
    if (!_disposed) {
      try {
        _clearProjectCursors();
        _clearProjectComments();
      } catch (_) {
        // The owning ProviderContainer may already be closing.
      }
      state = state.copyWith(
        connection: CollaborationConnectionState.disconnected,
        pendingOperations: 0,
        collaborators: const {},
        members: const {},
        clearError: true,
      );
    }
    try {
      await _localStorage.clearAccountScopedCollaborationQueue(
        projectId,
        expectedAccountId: _localAccountId,
      );
    } catch (_) {
      // Durable cleanup still runs when compatibility storage fails.
    }
    try {
      await _queuePersistenceBarrier();
    } catch (_) {
      // A failed queued write must not prevent scoped durable cleanup.
    }
    try {
      await _projectSession.store.clearCollaborationQueue(
        projectId,
        accountId: _localAccountId,
        generation: _accountQueueGeneration,
      );
    } catch (_) {
      // Account cleanup continues even if durable queue storage is unavailable.
    }
    try {
      await _room.leave(updateState: false);
    } catch (_) {
      // Provider disposal still clears in-memory collaboration state.
    }
  }

  Future<CanvasDocument?> start({
    required CanvasDocument initialDocument,
    required String userId,
    required String userName,
    required Color userColor,
    Iterable<CanvasComment> initialComments = const [],
    CollaborationRole role = CollaborationRole.viewer,
    bool readOnly = false,
  }) async {
    final activeLeave = _leaveFuture;
    if (_leaving && activeLeave != null) await activeLeave;
    if (_disposed || _discardCloudStateOnDispose) return _session?.document;
    if (_started) return _session?.document;
    initialDocument.assets.validateIdentity();
    final operationGeneration = ++_lifecycleGeneration;
    _leaving = false;
    _started = true;
    _readOnly = readOnly;
    _membershipRevoked = false;
    final testVerifiedRole = !_transport.isConfigured
        ? _ref.read(collaborationVerifiedRoleForTestingProvider)
        : null;
    _hasVerifiedMembership = testVerifiedRole != null;
    _role = testVerifiedRole ?? role;
    state = state.copyWith(role: _role);
    _localUserId = userId;
    final client = _ref.read(supabaseClientProvider);
    _localAccountId =
        client?.auth.currentUser?.id ?? client?.auth.currentSession?.user.id;
    _localUserName = userName;
    _localUserColor = userColor;
    _session = CrdtDocumentSession.fromDocument(
      initialDocument,
      actorId: userId,
    )..seedComments(initialComments);
    _projectComments.reconcile(initialComments);
    if (_localAccountId == null) {
      _ref.read(commentsProvider.notifier).reconcile(initialComments);
    }
    try {
      _accountQueueGeneration = await _localStorage
          .accountScopedCollaborationGeneration(accountId: _localAccountId);
      final durableQueue = _decodeDurableQueue(
        await _projectSession.store.readCollaborationQueue(
          projectId,
          accountId: _localAccountId,
          generation: _accountQueueGeneration,
        ),
      );
      final persistedQueue = durableQueue.isNotEmpty
          ? durableQueue
          : await _localStorage.loadAccountScopedCollaborationQueue(
              projectId,
              generation: _accountQueueGeneration,
              accountId: _localAccountId,
            );
      if (_disposed || _discardCloudStateOnDispose) {
        return _session?.document;
      }
      _pending
        ..clear()
        ..addAll(
          coalescePendingNodeOperations(
            persistedQueue
                .where((operation) => operation.projectId == projectId)
                .toList(growable: false),
          ),
        );
      state = state.copyWith(
        pendingOperations: _pending.length,
        syncStatus: _pending.isEmpty
            ? CollaborationSyncStatus.synced
            : CollaborationSyncStatus.savedLocally,
      );
    } catch (error) {
      debugPrint(
        '[CollaborationSession] Pending queue recovery failed: $error',
      );
    }
    if (_disposed || _discardCloudStateOnDispose) {
      return _session?.document;
    }
    if (!_transport.isConfigured) {
      _applyPendingLocally();
      _setConnection(
        CollaborationConnectionState.disconnected,
        clearError: true,
      );
      return _session!.document;
    }

    try {
      final restoredRoom = await _restoreRoomMembership(
        generation: operationGeneration,
      );
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      if (restoredRoom == null) {
        _hasVerifiedMembership = false;
        return _session?.document;
      }
      _hasVerifiedMembership = true;
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      await _transport.join(
        projectId: projectId,
        userId: userId,
        memberId: _memberUserId,
        accountId: _localAccountId,
        userName: userName,
        userColor: userColor,
      );
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      await _loadMembers();
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      await _syncLocalMemberProfile();
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      _startMemberHeartbeat();
      _startPresenceExpiryTimer();
      _setConnection(CollaborationConnectionState.catchingUp);
      final delta = await _transport.fetchDelta(
        projectId: projectId,
        version: _session!.version,
      );
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      if (delta.document != null) {
        _session = CrdtDocumentSession.fromSnapshot(
          document: delta.document!,
          actorId: userId,
          version: delta.version,
          state: delta.state,
          comments: delta.comments,
        );
        _applyMaterializedState();
      } else {
        _session!.seedComments(delta.comments);
        if (permissions.isHost) {
          await _seedInitialCrdtSnapshot();
          if (!_cloudOperationIsCurrent(operationGeneration)) {
            return _session?.document;
          }
        }
      }
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      for (final operation in delta.operations) {
        applyRemoteOperation(operation);
      }
      for (final operation in List<CrdtOperation>.from(_pending)) {
        applyRemoteOperation(operation);
      }
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      _setConnection(CollaborationConnectionState.live, clearError: true);
      await _flushPending();
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      return _session!.document;
    } catch (error) {
      if (!_cloudOperationIsCurrent(operationGeneration)) {
        return _session?.document;
      }
      debugPrint('[CollaborationSession] Collaboration start failed: $error');
      _applyPendingLocally();
      _setConnection(CollaborationConnectionState.offline, error: error);
      // Local editing remains available. Pending operations will be retried
      // after a later reconnect instead of being discarded.
      return _session?.document;
    }
  }

  SupabaseCollaborationTransport get _room => _transport;

  Future<void> _seedInitialCrdtSnapshot() async {
    final generation = _lifecycleGeneration;
    if (!_canEditCanvas ||
        !_accountIsCurrent ||
        _leaving ||
        !_cloudOperationIsCurrent(generation)) {
      return;
    }
    if (!await _prepareSessionAssetsForSnapshot(generation: generation)) {
      return;
    }
    if (!_cloudOperationIsCurrent(generation) || _leaving) return;
    final session = _session;
    if (session == null) return;
    final encoded = jsonDecode(session.encodeState());
    if (encoded is! Map) return;

    await _room.saveSnapshot(
      projectId: projectId,
      state: Map<String, dynamic>.from(encoded),
      version: session.version,
    );
    if (!_accountIsCurrent) return;
    try {
      await _room.updateCheckpoint(
        projectId: projectId,
        version: session.version,
      );
    } catch (error) {
      debugPrint('[CollaborationSession] Initial checkpoint skipped: $error');
    }
  }

  CollaborationRole get role => _role;
  String? get localAccountId => _localAccountId;
  String? get localUserId => _localAccountId ?? _localUserId;
  CollaborationPermissions get permissions => CollaborationPermissions(_role);
  bool get canEditCanvas => _canEditCanvas;
  bool get canComment => _canComment;
  CollaborationConnectionState get connectionState => state.connection;
  CollaborationSyncStatus get syncStatus => state.syncStatus;
  int get pendingOperationCount => state.pendingOperations;
  List<CrdtOperation> get pendingOperationDetails =>
      List.unmodifiable(_pending);

  String exportRecoveryBundle() => jsonEncode({
    'type': 'varian.collaboration-recovery',
    'schemaVersion': 1,
    'projectId': projectId,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'role': _role.wireName,
    'connection': state.connection.name,
    'syncStatus': state.syncStatus.name,
    'pendingOperations': _pending
        .map(_recoveryOperationJson)
        .toList(growable: false),
    'conflicts': state.conflicts
        .map(
          (conflict) => {
            'id': conflict.id,
            'targetId': conflict.targetId,
            'field': conflict.field,
            'detectedAt': conflict.detectedAt.toUtc().toIso8601String(),
            'localOperation': _recoveryOperationJson(conflict.localOperation),
            'remoteOperation': _recoveryOperationJson(conflict.remoteOperation),
          },
        )
        .toList(growable: false),
    'sessionVersion': _session?.version.toJson(),
    'errorMessage': state.errorMessage,
  });

  bool get _canEditCanvas =>
      !_readOnly &&
      !_membershipRevoked &&
      _hasVerifiedMembership &&
      permissions.canEditCanvas;
  bool get _canComment =>
      !_readOnly &&
      !_membershipRevoked &&
      _hasVerifiedMembership &&
      permissions.canComment;
  String? get _memberUserId => _localAccountId ?? _localUserId;

  bool get _accountIsCurrent {
    if (_disposed || _discardCloudStateOnDispose) return false;
    final expectedAccountId = _localAccountId;
    final client = _ref.read(supabaseClientProvider);
    final currentAccountId =
        client?.auth.currentUser?.id ?? client?.auth.currentSession?.user.id;
    return expectedAccountId != null && currentAccountId == expectedAccountId;
  }

  bool _cloudOperationIsCurrent(int generation) =>
      !_disposed &&
      !_discardCloudStateOnDispose &&
      generation == _lifecycleGeneration &&
      _accountIsCurrent;

  Future<CanvasRoom?> _restoreRoomMembership({int? generation}) async {
    final operationGeneration = generation ?? _lifecycleGeneration;
    final client = _ref.read(supabaseClientProvider);
    if (client == null || !_hasFlutterBinding) return null;
    if (!_cloudOperationIsCurrent(operationGeneration)) return null;

    CanvasRoom? cachedRoom;
    try {
      cachedRoom = await CollaborationRoomCache.read(projectId);
    } catch (error) {
      debugPrint('[CollaborationSession] Room cache read failed: $error');
    }
    if (!_cloudOperationIsCurrent(operationGeneration)) return null;

    if (cachedRoom == null) {
      try {
        final projects = await LocalStorageService().getProjects();
        final metadata = projects
            .where((project) => project.id == projectId)
            .firstOrNull;
        final roomCode = metadata?.collaborationRoomCode?.trim() ?? '';
        if (CanvasRoom.isValidRoomCode(roomCode)) {
          cachedRoom = CanvasRoom(
            id: '',
            projectId: projectId,
            projectName: metadata?.name ?? 'Untitled Project',
            roomCode: roomCode,
            role: metadata?.collaborationRole ?? _role.wireName,
            expiresAt: metadata?.collaborationRoomExpiresAt,
          );
        }
      } catch (error) {
        debugPrint(
          '[CollaborationSession] Room metadata recovery failed: $error',
        );
      }
      if (!_cloudOperationIsCurrent(operationGeneration)) return null;
    }

    if (cachedRoom == null ||
        !CanvasRoom.isValidRoomCode(cachedRoom.roomCode) ||
        !_cloudOperationIsCurrent(operationGeneration)) {
      return null;
    }

    try {
      final joinedRoom = await _syncService.joinCollaborationRoom(
        roomCode: cachedRoom.roomCode,
        displayName: _localUserName ?? 'Collaborator',
        expectedUserId: _localAccountId,
      );
      if (joinedRoom.projectId != projectId) {
        debugPrint(
          '[CollaborationSession] Ignoring room for another project: '
          '${joinedRoom.projectId}',
        );
        return null;
      }
      if (!_cloudOperationIsCurrent(operationGeneration)) return null;
      _role = CollaborationRole.fromWire(joinedRoom.role);
      _hasVerifiedMembership = true;
      state = state.copyWith(role: _role);
      try {
        await CollaborationRoomCache.write(
          joinedRoom,
          accountId: _localAccountId,
        );
      } catch (error) {
        debugPrint('[CollaborationSession] Room cache refresh failed: $error');
      }
      if (!_cloudOperationIsCurrent(operationGeneration)) return null;
      return joinedRoom;
    } catch (error) {
      debugPrint(
        '[CollaborationSession] Room membership recovery skipped: $error',
      );
      return null;
    }
  }

  bool get _hasFlutterBinding {
    try {
      WidgetsBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _syncLocalMemberProfile() async {
    final userId = _localUserId;
    final userName = _localUserName;
    final memberUserId = _memberUserId;
    if (userId == null || userName == null || memberUserId == null) return;
    if (_localAccountId != null && !_accountIsCurrent) return;
    try {
      final existing = state.members[memberUserId];
      final displayName = CollaborationDisplayNameGenerator.resolve(
        stableId: memberUserId,
        preferredName: existing?.displayName ?? userName,
      );
      final member = await _syncService.upsertWorkspaceMemberProfile(
        projectId: projectId,
        displayName: displayName,
        expectedUserId: _localAccountId,
      );
      if (_localAccountId != null && !_accountIsCurrent) return;
      _localUserName = member.displayName;
      state = state.copyWith(
        members: {
          ...state.members,
          member.userId: member.copyWith(online: true),
        },
      );
    } catch (error) {
      debugPrint('[CollaborationSession] Member profile sync failed: $error');
    }
  }

  void _startMemberHeartbeat() {
    _memberHeartbeatTimer?.cancel();
    _memberHeartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_memberHeartbeatInFlight ||
          !_started ||
          _memberUserId == null ||
          (_localAccountId != null && !_accountIsCurrent)) {
        return;
      }
      _memberHeartbeatInFlight = true;
      unawaited(() async {
        try {
          final member = await _syncService.touchWorkspaceMember(
            projectId,
            expectedUserId: _localAccountId,
          );
          if (!_disposed &&
              !_discardCloudStateOnDispose &&
              _started &&
              (_localAccountId == null || _accountIsCurrent)) {
            state = state.copyWith(
              members: {
                ...state.members,
                member.userId: member.copyWith(online: true),
              },
            );
          }
        } catch (error) {
          debugPrint('[CollaborationSession] Member heartbeat failed: $error');
        } finally {
          _memberHeartbeatInFlight = false;
        }
      }());
    });
  }

  void _startPresenceExpiryTimer() {
    _presenceExpiryTimer?.cancel();
    _presenceExpiryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pruneStalePresence();
    });
  }

  void _pruneStalePresence() {
    if (_disposed || _discardCloudStateOnDispose || !_started) return;
    final now = DateTime.now();
    final staleUsers = _remotePresenceSeenAt.entries
        .where((entry) => now.difference(entry.value) > _presenceExpiry)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final userId in staleUsers) {
      _remotePresenceSeenAt.remove(userId);
      _removePresence(userId);
    }
  }

  Future<void> _loadMembers() async {
    try {
      if (_localAccountId != null && !_accountIsCurrent) return;
      final memberUserId = _memberUserId;
      final members = await _syncService.listProjectMembers(
        projectId,
        expectedUserId: _localAccountId,
      );
      final now = DateTime.now();
      final memberMap = {
        for (final member in members)
          member.userId: member.copyWith(
            online:
                member.userId == memberUserId ||
                state.collaborators.containsKey(member.userId) ||
                (member.lastSeenAt != null &&
                    now.difference(member.lastSeenAt!.toLocal()).inSeconds <
                        45),
          ),
      };
      final localMember = memberUserId == null ? null : memberMap[memberUserId];
      if (localMember == null && memberUserId != null) {
        memberMap[memberUserId] = CanvasMember(
          projectId: projectId,
          userId: memberUserId,
          role: _role.wireName,
          displayName: _localUserName ?? 'You',
          online: true,
        );
      }
      final resolvedLocalMember = memberUserId == null
          ? null
          : memberMap[memberUserId];
      if (!_started ||
          _disposed ||
          _discardCloudStateOnDispose ||
          (_localAccountId != null && !_accountIsCurrent)) {
        return;
      }
      if (resolvedLocalMember != null) {
        _role = resolvedLocalMember.collaborationRole;
      }
      state = state.copyWith(members: memberMap, role: _role);
    } catch (error) {
      debugPrint('[CollaborationSession] Member roster load failed: $error');
    }
  }

  Future<void> refreshMembers() => _loadMembers();

  Future<void> updateDisplayName(String value) async {
    if (!_started) {
      throw const SyncException(
        'Join the collaboration room before editing your name.',
      );
    }
    final memberUserId = _memberUserId;
    if (memberUserId == null) {
      throw const SyncException('Sign in is required to edit your name.');
    }
    final displayName = CollaborationDisplayNameGenerator.validate(value);
    final expectedUserId = _localAccountId;
    if (expectedUserId == null || !_accountIsCurrent) {
      throw const SyncException('Collaboration session is no longer active.');
    }
    final member = await _syncService.upsertWorkspaceMemberProfile(
      projectId: projectId,
      displayName: displayName,
      expectedUserId: expectedUserId,
    );
    if (!_accountIsCurrent) {
      throw const SyncException('Collaboration session is no longer active.');
    }
    _localUserName = member.displayName;
    _transport.updateLocalUserName(member.displayName);
    state = state.copyWith(
      members: {...state.members, memberUserId: member.copyWith(online: true)},
    );
    final presence = <String, dynamic>{
      ...?_lastPresencePayload,
      'userId': _memberUserId ?? _localUserId,
      'sessionId': _localUserId,
      'userName': member.displayName,
      'userColor': _localUserColor?.toARGB32() ?? 0xFFF97316,
      'x': (_lastPresencePayload?['x'] as num?)?.toDouble() ?? 0,
      'y': (_lastPresencePayload?['y'] as num?)?.toDouble() ?? 0,
      'selectedNodeIds':
          _lastPresencePayload?['selectedNodeIds'] ?? const <String>[],
      'activeNodeId': _lastPresencePayload?['activeNodeId'],
      'editing': _lastPresencePayload?['editing'] == true,
      'viewportX':
          (_lastPresencePayload?['viewportX'] as num?)?.toDouble() ?? 0,
      'viewportY':
          (_lastPresencePayload?['viewportY'] as num?)?.toDouble() ?? 0,
      'viewportZoom':
          (_lastPresencePayload?['viewportZoom'] as num?)?.toDouble() ?? 1,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    _lastPresencePayload = presence;
    _pendingPresence = presence;
    if (_room.isConnected) _schedulePresenceUpdate();
    await _broadcastControlEvent(
      type: CollaborationControlEventType.memberProfileUpdated,
      targetUserId: memberUserId,
      payload: {'displayName': member.displayName},
    );
  }

  String _newControlEventId() =>
      '${_localUserId ?? 'anonymous'}-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> changeMemberRole({
    required String userId,
    required CollaborationRole role,
  }) async {
    if (!permissions.canManageMembers || role == CollaborationRole.owner) {
      throw const SyncException('Only the host can assign guest roles.');
    }
    if (userId == _memberUserId) {
      throw const SyncException('The host role cannot be changed here.');
    }
    final expectedUserId = _localAccountId;
    if (expectedUserId == null || !_accountIsCurrent) {
      throw const SyncException('Collaboration session is no longer active.');
    }
    final member = await _syncService.setProjectMemberRole(
      projectId: projectId,
      userId: userId,
      role: role.wireName,
      expectedUserId: expectedUserId,
    );
    if (!_accountIsCurrent) {
      throw const SyncException('Collaboration session is no longer active.');
    }
    final previousMember = state.members[member.userId];
    state = state.copyWith(
      members: {
        ...state.members,
        member.userId: member.copyWith(
          displayName: previousMember?.displayName,
          online: previousMember?.online,
          cursorActive: previousMember?.cursorActive,
          lastSeenAt: previousMember?.lastSeenAt,
        ),
      },
    );
    await _broadcastControlEvent(
      type: CollaborationControlEventType.memberRoleChanged,
      targetUserId: userId,
      payload: {'role': role.wireName},
    );
  }

  Future<void> removeMember(String userId) async {
    if (!permissions.canManageMembers || userId == _memberUserId) {
      throw const SyncException('Only the host can remove a guest.');
    }
    final expectedUserId = _localAccountId;
    if (expectedUserId == null || !_accountIsCurrent) {
      throw const SyncException('Collaboration session is no longer active.');
    }
    // Remove the provider participant first so collaboration membership is
    // never revoked while a meeting participant remains connected.
    await _onMeetingParticipantRemoved?.call(userId);
    if (!_accountIsCurrent) {
      throw const SyncException('Collaboration session is no longer active.');
    }
    await _syncService.removeProjectMember(
      projectId: projectId,
      userId: userId,
      expectedUserId: expectedUserId,
    );
    if (!_accountIsCurrent) {
      throw const SyncException('Collaboration session is no longer active.');
    }
    final members = {...state.members}..remove(userId);
    state = state.copyWith(members: members);
    await _broadcastControlEvent(
      type: CollaborationControlEventType.memberRemoved,
      targetUserId: userId,
      payload: const {},
    );
  }

  Future<void> requestFollow(String targetUserId) async {
    if (!permissions.canRequestFollow || targetUserId == _memberUserId) return;
    final requestId = _newControlEventId();
    await _broadcastControlEvent(
      type: CollaborationControlEventType.followRequest,
      targetUserId: targetUserId,
      payload: {
        'requestId': requestId,
        'requesterName': _localUserName ?? 'Collaborator',
      },
    );
  }

  Future<void> respondToFollow({
    required CollaborationControlEvent request,
    required bool approved,
  }) async {
    if (request.type != CollaborationControlEventType.followRequest ||
        request.targetUserId != _memberUserId) {
      return;
    }
    await _broadcastControlEvent(
      type: CollaborationControlEventType.followResponse,
      targetUserId: request.actorId,
      payload: {
        'requestId': request.payload['requestId'],
        'approved': approved,
        'followUserId': _localUserId,
      },
    );
    state = state.copyWith(clearFollowRequest: true);
  }

  Future<void> stopFollowing() async {
    final targetUserId = state.followingUserId;
    if (targetUserId == null) return;
    state = state.copyWith(clearFollowingUser: true);
    await _broadcastControlEvent(
      type: CollaborationControlEventType.followState,
      targetUserId: targetUserId,
      payload: const {'active': false},
    );
  }

  Future<void> requestScreenShare(String targetUserId) async {
    if (targetUserId == _memberUserId || !permissions.canRequestScreenShare) {
      return;
    }
    final requestId = _newControlEventId();
    _screenPeerUserId = targetUserId;
    state = state.copyWith(
      screenTracking: const ScreenTrackingSnapshot(
        status: ScreenTrackingStatus.requesting,
      ),
    );
    await _broadcastControlEvent(
      type: CollaborationControlEventType.screenShareRequest,
      targetUserId: targetUserId,
      payload: {
        'requestId': requestId,
        'requesterName': _localUserName ?? 'Collaborator',
      },
    );
  }

  Future<void> respondToScreenShare({
    required CollaborationControlEvent request,
    required bool approved,
  }) async {
    if (request.type != CollaborationControlEventType.screenShareRequest ||
        request.targetUserId != _memberUserId) {
      return;
    }
    final shareId = request.payload['requestId']?.toString();
    if (shareId == null || shareId.isEmpty) return;
    state = state.copyWith(clearScreenShareRequest: true);
    _screenPeerUserId = request.actorId;
    if (!approved) {
      await _broadcastControlEvent(
        type: CollaborationControlEventType.screenShareResponse,
        targetUserId: request.actorId,
        payload: {'requestId': shareId, 'approved': false},
      );
      state = state.copyWith(
        screenTracking: const ScreenTrackingSnapshot(
          status: ScreenTrackingStatus.stopped,
        ),
      );
      return;
    }
    try {
      await _broadcastControlEvent(
        type: CollaborationControlEventType.screenShareResponse,
        targetUserId: request.actorId,
        payload: {'requestId': shareId, 'approved': true},
      );
      await _screenTracking.startSharing(
        peerUserId: request.actorId,
        shareId: shareId,
      );
    } catch (error) {
      state = state.copyWith(
        screenTracking: ScreenTrackingSnapshot(
          status: ScreenTrackingStatus.error,
          errorMessage: error.toString(),
        ),
      );
      await _broadcastControlEvent(
        type: CollaborationControlEventType.screenShareState,
        targetUserId: request.actorId,
        payload: const {'active': false, 'reason': 'capture_failed'},
      );
    }
  }

  Future<void> stopScreenTracking() async {
    final targetUserId = _screenPeerUserId ?? state.screenTracking.peerUserId;
    await _screenTracking.stop();
    state = state.copyWith(
      screenTracking: const ScreenTrackingSnapshot(
        status: ScreenTrackingStatus.stopped,
      ),
    );
    if (targetUserId != null) {
      await _broadcastControlEvent(
        type: CollaborationControlEventType.screenShareState,
        targetUserId: targetUserId,
        payload: const {'active': false, 'reason': 'stopped'},
      );
    }
    _screenPeerUserId = null;
  }

  Future<void> _sendScreenSignal(
    String peerUserId,
    Map<String, dynamic> signal,
  ) => _broadcastControlEvent(
    type: CollaborationControlEventType.screenShareSignal,
    targetUserId: peerUserId,
    payload: signal,
  );

  void _handleScreenTrackingChanged(ScreenTrackingSnapshot snapshot) {
    if (_disposed || _discardCloudStateOnDispose || _suppressStateUpdates) {
      return;
    }
    state = state.copyWith(screenTracking: snapshot);
  }

  Future<void> _broadcastControlEvent({
    required CollaborationControlEventType type,
    String? targetUserId,
    required Map<String, dynamic> payload,
  }) async {
    final actorId = _localUserId;
    if (actorId == null) return;
    try {
      await _room.broadcastControlEvent(
        CollaborationControlEvent(
          eventId: _newControlEventId(),
          projectId: projectId,
          actorId: actorId,
          targetUserId: targetUserId,
          type: type,
          payload: payload,
          createdAt: DateTime.now(),
        ),
      );
    } catch (error) {
      debugPrint('[CollaborationSession] Control event failed: $error');
    }
  }

  void _handleControlEvent(CollaborationControlEvent event) {
    if (_disposed || _discardCloudStateOnDispose || !_started) return;
    final targetUserId = event.targetUserId;
    switch (event.type) {
      case CollaborationControlEventType.memberRoleChanged:
        if (targetUserId == null) return;
        final nextRole = CollaborationRole.fromWire(event.payload['role']);
        final member = state.members[targetUserId];
        if (member != null) {
          state = state.copyWith(
            members: {
              ...state.members,
              targetUserId: member.copyWith(role: nextRole.wireName),
            },
          );
        }
        if (targetUserId == _memberUserId) {
          _role = nextRole;
          state = state.copyWith(role: nextRole);
          if (!_canEditCanvas) {
            _pending.clear();
            unawaited(_persistPendingQueue());
            state = state.copyWith(
              pendingOperations: 0,
              syncStatus: state.conflicts.isEmpty
                  ? CollaborationSyncStatus.synced
                  : CollaborationSyncStatus.conflicted,
            );
          }
        }
        final changedMember = state.members[targetUserId];
        _emitNotice(
          userId: targetUserId,
          displayName: changedMember?.displayName ?? targetUserId,
          kind: CollaborationNoticeKind.roleChanged,
          role: nextRole,
        );
      case CollaborationControlEventType.memberRemoved:
        if (targetUserId == null) return;
        final removedMember = state.members[targetUserId];
        if (targetUserId == _memberUserId) {
          _membershipRevoked = true;
          _emitNotice(
            userId: targetUserId,
            displayName: removedMember?.displayName ?? targetUserId,
            kind: CollaborationNoticeKind.removed,
          );
          _setConnection(
            CollaborationConnectionState.error,
            error: const SyncException('You were removed from this room.'),
          );
          unawaited(
            _terminateMeetingAndLeave(MeetingTerminationReason.removed),
          );
        } else {
          final members = {...state.members}..remove(targetUserId);
          state = state.copyWith(members: members);
          _removePresence(targetUserId);
          _emitNotice(
            userId: targetUserId,
            displayName: removedMember?.displayName ?? targetUserId,
            kind: CollaborationNoticeKind.removed,
          );
        }
      case CollaborationControlEventType.memberProfileUpdated:
        if (targetUserId == null) return;
        final member = state.members[targetUserId];
        if (member == null) return;
        final nextName = event.payload['displayName']?.toString();
        state = state.copyWith(
          members: {
            ...state.members,
            targetUserId: member.copyWith(
              displayName: nextName,
              avatarUrl: event.payload['avatarUrl']?.toString(),
            ),
          },
        );
        _emitNotice(
          userId: targetUserId,
          displayName: nextName ?? member.displayName,
          kind: CollaborationNoticeKind.profileUpdated,
        );
      case CollaborationControlEventType.followRequest:
        if (targetUserId == _memberUserId) {
          state = state.copyWith(followRequest: event);
        }
      case CollaborationControlEventType.followResponse:
        if (targetUserId != _localUserId) return;
        final approved = event.payload['approved'] == true;
        state = state.copyWith(
          clearFollowingUser: !approved,
          followingUserId: approved ? event.actorId : null,
        );
      case CollaborationControlEventType.followState:
        if (event.type == CollaborationControlEventType.followState) {
          final active = event.payload['active'] == true;
          if (!active &&
              (targetUserId == _localUserId ||
                  event.actorId == state.followingUserId)) {
            state = state.copyWith(clearFollowingUser: true);
          }
        }
      case CollaborationControlEventType.screenShareRequest:
        if (targetUserId == _memberUserId) {
          state = state.copyWith(
            screenShareRequest: event,
            screenTracking: ScreenTrackingSnapshot(
              status: ScreenTrackingStatus.awaitingConsent,
              peerUserId: event.actorId,
            ),
          );
        }
      case CollaborationControlEventType.screenShareResponse:
        if (targetUserId != _localUserId) return;
        final approved = event.payload['approved'] == true;
        final shareId = event.payload['requestId']?.toString();
        if (!approved || shareId == null || shareId.isEmpty) {
          _screenPeerUserId = null;
          state = state.copyWith(
            screenTracking: const ScreenTrackingSnapshot(
              status: ScreenTrackingStatus.stopped,
            ),
          );
        } else {
          _screenPeerUserId = event.actorId;
          unawaited(
            _screenTracking.prepareViewer(
              peerUserId: event.actorId,
              shareId: shareId,
            ),
          );
        }
      case CollaborationControlEventType.screenShareSignal:
        if (targetUserId != _localUserId) return;
        _screenPeerUserId = event.actorId;
        unawaited(_screenTracking.handleSignal(event.payload));
      case CollaborationControlEventType.screenShareState:
        if (targetUserId == _localUserId ||
            event.actorId == _screenPeerUserId) {
          unawaited(_stopScreenTrackingLocally());
        }
        break;
    }
  }

  Future<void> _stopScreenTrackingLocally() async {
    await _screenTracking.stop();
    _screenPeerUserId = null;
    if (!_disposed && !_suppressStateUpdates) {
      state = state.copyWith(
        screenTracking: const ScreenTrackingSnapshot(
          status: ScreenTrackingStatus.stopped,
        ),
        clearScreenShareRequest: true,
      );
    }
  }

  void _recordNodeTransition(List<CanvasNode> previous, List<CanvasNode> next) {
    final session = _session;
    if (_discardCloudStateOnDispose ||
        !_started ||
        !_canEditCanvas ||
        _remoteApply ||
        session == null) {
      return;
    }
    final before = {for (final node in previous) node.id: node};
    final after = {for (final node in next) node.id: node};

    for (final id in before.keys) {
      if (!after.containsKey(id)) session.deleteNode(id);
    }
    for (final entry in after.entries) {
      final oldNode = before[entry.key];
      if (oldNode == null) {
        _tryUpsertNode(session, entry.value);
        continue;
      }
      if (oldNode.toPersistenceJson().toString() ==
          entry.value.toPersistenceJson().toString()) {
        continue;
      }
      if (_recordDrawingTransition(session, oldNode, entry.value)) {
        continue;
      }
      if (_recordTextTransition(session, oldNode, entry.value)) {
        continue;
      }
      _tryUpsertNode(session, entry.value);
    }
    _queueSessionOperations();
  }

  bool _tryUpsertNode(CrdtDocumentSession session, CanvasNode node) {
    try {
      session.upsertNode(node);
      return true;
    } on FormatException catch (error) {
      debugPrint(
        '[CollaborationSession] Node update skipped because it is too large: $error',
      );
      if (!_disposed && !_suppressStateUpdates) {
        state = state.copyWith(
          syncStatus: CollaborationSyncStatus.failed,
          errorMessage:
              'Asset is too large to sync. Upload it or choose a smaller file.',
        );
      }
      return false;
    }
  }

  bool _recordDrawingTransition(
    CrdtDocumentSession session,
    CanvasNode before,
    CanvasNode after,
  ) {
    final beforePayload = before.payload;
    final afterPayload = after.payload;
    if (beforePayload is! DrawingPaperPayload ||
        afterPayload is! DrawingPaperPayload) {
      return false;
    }
    if (jsonEncode(
          before.copyWith(payload: afterPayload).toPersistenceJson(),
        ) !=
        jsonEncode(after.toPersistenceJson())) {
      return false;
    }
    final requiresNodeUpsert =
        _strokeFreePayload(beforePayload).toJson().toString() !=
        _strokeFreePayload(afterPayload).toJson().toString();

    final upserts = <({String pageId, String layerId, DrawingStroke stroke})>[];
    final deletes = <({String pageId, String layerId, String strokeId})>[];
    final rasterUpserts = <({String pageId, RasterEditOperation operation})>[];
    final rasterResets = <String>[];

    void collectRasterOperations(
      String pageId,
      DrawingPaperPayload oldPage,
      DrawingPaperPayload newPage,
    ) {
      final oldOperations = {
        for (final operation in oldPage.rasterOperations)
          operation.id: operation,
      };
      final newOperationIds = newPage.rasterOperations
          .map((operation) => operation.id)
          .toSet();
      final requiresReset = oldOperations.keys.any(
        (id) => !newOperationIds.contains(id),
      );
      if (requiresReset) rasterResets.add(pageId);
      for (final operation in newPage.rasterOperations) {
        final oldOperation = oldOperations[operation.id];
        if (requiresReset ||
            oldOperation == null ||
            jsonEncode(oldOperation.toJson()) !=
                jsonEncode(operation.toJson())) {
          rasterUpserts.add((pageId: pageId, operation: operation));
        }
      }
    }

    bool collectPage(
      String pageId,
      DrawingPaperPayload oldPage,
      DrawingPaperPayload newPage,
    ) {
      collectRasterOperations(pageId, oldPage, newPage);
      final oldLayerIds = oldPage.layers.map((layer) => layer.id).toList();
      final newLayerIds = newPage.layers.map((layer) => layer.id).toList();
      if (oldLayerIds.toSet().length != oldLayerIds.length ||
          newLayerIds.toSet().length != newLayerIds.length ||
          oldLayerIds.toSet().difference(newLayerIds.toSet()).isNotEmpty ||
          newLayerIds.toSet().difference(oldLayerIds.toSet()).isNotEmpty) {
        return false;
      }
      final oldLayers = {for (final layer in oldPage.layers) layer.id: layer};
      final newLayers = {for (final layer in newPage.layers) layer.id: layer};
      for (final layerId in oldLayerIds) {
        final oldStrokes = {
          for (final stroke in oldLayers[layerId]!.strokes) stroke.id: stroke,
        };
        final newStrokes = {
          for (final stroke in newLayers[layerId]!.strokes) stroke.id: stroke,
        };
        for (final oldStroke in oldStrokes.entries) {
          if (!newStrokes.containsKey(oldStroke.key)) {
            deletes.add((
              pageId: pageId,
              layerId: layerId,
              strokeId: oldStroke.key,
            ));
          }
        }
        for (final newStroke in newStrokes.entries) {
          final oldStroke = oldStrokes[newStroke.key];
          if (oldStroke == null ||
              oldStroke.toJson().toString() !=
                  newStroke.value.toJson().toString()) {
            upserts.add((
              pageId: pageId,
              layerId: layerId,
              stroke: newStroke.value,
            ));
          }
        }
      }

      final oldPages = {for (final page in oldPage.studioPages) page.id: page};
      final newPages = {for (final page in newPage.studioPages) page.id: page};
      final oldPageIds = oldPage.studioPages.map((page) => page.id).toList();
      final newPageIds = newPage.studioPages.map((page) => page.id).toList();
      if (oldPageIds.toSet().length != oldPageIds.length ||
          newPageIds.toSet().length != newPageIds.length ||
          oldPageIds.toSet().difference(newPageIds.toSet()).isNotEmpty ||
          newPageIds.toSet().difference(oldPageIds.toSet()).isNotEmpty) {
        return false;
      }
      for (final nestedPageId in oldPageIds) {
        final oldNestedPage = oldPages[nestedPageId]!;
        final newNestedPage = newPages[nestedPageId]!;
        if (!collectPage(
          nestedPageId,
          oldNestedPage.payload,
          newNestedPage.payload,
        )) {
          return false;
        }
      }
      return true;
    }

    if (!collectPage('root-page', beforePayload, afterPayload)) {
      return false;
    }

    try {
      if (requiresNodeUpsert && !_tryUpsertNode(session, after)) {
        return true;
      }
      for (final delete in deletes) {
        session.deleteStroke(
          nodeId: after.id,
          pageId: delete.pageId,
          layerId: delete.layerId,
          strokeId: delete.strokeId,
        );
      }
      for (final upsert in upserts) {
        session.upsertStroke(
          nodeId: after.id,
          pageId: upsert.pageId,
          layerId: upsert.layerId,
          stroke: upsert.stroke,
        );
      }
      for (final pageId in rasterResets) {
        session.resetRasterOperations(nodeId: after.id, pageId: pageId);
      }
      for (final raster in rasterUpserts) {
        session.addRasterOperation(
          nodeId: after.id,
          pageId: raster.pageId,
          operation: raster.operation.toJson(),
        );
      }
    } on FormatException catch (error) {
      debugPrint(
        '[CollaborationSession] Drawing Paper update skipped because it is '
        'too large: $error',
      );
      if (!_disposed && !_suppressStateUpdates) {
        state = state.copyWith(
          syncStatus: CollaborationSyncStatus.failed,
          errorMessage:
              'Asset is too large to sync. Upload it or choose a smaller file.',
        );
      }
    }
    return true;
  }

  DrawingPaperPayload _strokeFreePayload(DrawingPaperPayload payload) {
    return payload.copyWith(
      rasterRevision: 0,
      compositePreviewRef: null,
      rasterOperations: const [],
      layers: payload.layers
          .map((layer) => layer.copyWith(strokes: const []))
          .toList(),
      studioPages: payload.studioPages
          .map(
            (page) => page.copyWith(payload: _strokeFreePayload(page.payload)),
          )
          .toList(),
    );
  }

  bool _recordTextTransition(
    CrdtDocumentSession session,
    CanvasNode before,
    CanvasNode after,
  ) {
    final textFields = <String, (String, String)>{
      if (before.name != after.name && after.name != null)
        'name': (before.name ?? '', after.name!),
      if (before.payload is TextPayload && after.payload is TextPayload)
        if ((before.payload as TextPayload).text !=
            (after.payload as TextPayload).text)
          'payload.text': (
            (before.payload as TextPayload).text,
            (after.payload as TextPayload).text,
          ),
      if (before.payload is StickyNotePayload &&
          after.payload is StickyNotePayload)
        if ((before.payload as StickyNotePayload).text !=
            (after.payload as StickyNotePayload).text)
          'payload.text': (
            (before.payload as StickyNotePayload).text,
            (after.payload as StickyNotePayload).text,
          ),
      if (before.payload is ShapePayload && after.payload is ShapePayload)
        if ((before.payload as ShapePayload).label !=
            (after.payload as ShapePayload).label)
          'payload.label': (
            (before.payload as ShapePayload).label,
            (after.payload as ShapePayload).label,
          ),
    };
    if (textFields.isEmpty) return false;
    final changedFields = textFields.entries
        .where((entry) => entry.value.$1 != entry.value.$2)
        .toList();
    if (changedFields.length != 1) return false;
    final entry = changedFields.single;
    final beforeFields = before.toJson();
    final afterFields = after.toJson();
    final path = entry.key.split('.');
    if (path.length == 1) {
      beforeFields.remove(path.single);
      afterFields.remove(path.single);
    } else {
      (beforeFields[path.first] as Map).remove(path.last);
      (afterFields[path.first] as Map).remove(path.last);
    }
    if (jsonEncode(beforeFields) != jsonEncode(afterFields)) return false;
    session.replaceText(
      nodeId: after.id,
      field: entry.key,
      value: entry.value.$2,
    );
    return true;
  }

  void _recordEdgeTransition(List<CanvasEdge> previous, List<CanvasEdge> next) {
    final session = _session;
    if (_discardCloudStateOnDispose ||
        !_started ||
        !_canEditCanvas ||
        _remoteApply ||
        session == null) {
      return;
    }
    final before = {for (final edge in previous) edge.id: edge};
    final after = {for (final edge in next) edge.id: edge};
    for (final id in before.keys) {
      if (!after.containsKey(id)) session.deleteEdge(id);
    }
    for (final entry in after.entries) {
      final oldEdge = before[entry.key];
      if (oldEdge == null ||
          oldEdge.toJson().toString() != entry.value.toJson().toString()) {
        session.upsertEdge(entry.value);
      }
    }
    _queueSessionOperations();
  }

  void _recordAssetTransition(
    DocumentAssetManifest previous,
    DocumentAssetManifest next,
  ) {
    final session = _session;
    if (_discardCloudStateOnDispose ||
        _leaving ||
        !_started ||
        !_canEditCanvas ||
        _remoteApply ||
        session == null) {
      return;
    }
    try {
      previous.validateIdentity();
      next.validateIdentity();
    } on FormatException catch (error) {
      debugPrint(
        '[CollaborationSession] Asset update skipped because its manifest '
        'identity is invalid: $error',
      );
      if (!_disposed && !_suppressStateUpdates) {
        state = state.copyWith(
          syncStatus: CollaborationSyncStatus.failed,
          errorMessage: error.message,
        );
      }
      return;
    }
    for (final assetId in previous.entries.keys) {
      if (!next.entries.containsKey(assetId)) session.deleteAsset(assetId);
    }
    for (final entry in next.entries.entries) {
      final oldAsset = previous.entries[entry.key];
      if (oldAsset == null ||
          oldAsset.toJson().toString() != entry.value.toJson().toString()) {
        if (_requiresCollaborativeAssetDelivery(entry.value)) {
          _stageCollaborativeAsset(entry.value);
        } else {
          session.upsertAsset(entry.value);
        }
      }
    }
    _queueSessionOperations();
  }

  @visibleForTesting
  bool requiresCollaborativeAssetDeliveryForTesting(DocumentAsset asset) =>
      _requiresCollaborativeAssetDelivery(asset);

  bool _requiresCollaborativeAssetDelivery(DocumentAsset asset) {
    final remoteUrl = asset.remoteUrl?.trim() ?? '';
    final durableReference = asset.durableReference?.trim() ?? '';
    if (remoteUrl.contains('/storage/v1/object/public/assets/') &&
        durableReference.isNotEmpty) {
      return false;
    }
    final source = (durableReference.isNotEmpty ? durableReference : remoteUrl)
        .trim();
    if (source.isEmpty) return asset.localPath?.trim().isNotEmpty == true;
    final storageReference = StorageAssetReference.tryParse(
      bucket: 'assets',
      path: source,
      projectId: projectId,
    );
    if (storageReference != null) return false;
    if (source.contains('/') &&
        !source.startsWith('data:') &&
        !source.startsWith('http://') &&
        !source.startsWith('https://') &&
        Uri.tryParse(source)?.scheme == null) {
      return true;
    }
    final scheme = Uri.tryParse(source)?.scheme.toLowerCase();
    if (const {
      'varian-image',
      'varian-file',
      'varian-media',
      'varian-video',
      'varian-model3d',
    }.contains(scheme)) {
      return true;
    }
    return source.startsWith('data:') ||
        source.startsWith('http://') ||
        source.startsWith('https://');
  }

  void _stageCollaborativeAsset(DocumentAsset asset) {
    if (_disposed || _discardCloudStateOnDispose || _leaving) return;
    final fingerprint = jsonEncode(asset.toJson());
    final inFlight = _assetUploadInFlight[asset.id];
    if (inFlight != null && _assetUploadFingerprints[asset.id] == fingerprint) {
      return;
    }
    final generation = _lifecycleGeneration;
    final expectedUserId = _localAccountId;
    final future =
        () async {
          final prepared = await _syncService.prepareCollaborativeAsset(
            projectId: projectId,
            asset: asset,
            expectedUserId: expectedUserId,
          );
          if (!_cloudOperationIsCurrent(generation) ||
              !_started ||
              _leaving ||
              _session == null) {
            return;
          }
          if (prepared == null) {
            debugPrint(
              '[CollaborationSession] Refusing to publish asset without portable delivery: ${asset.id}',
            );
            return;
          }
          final currentAsset = _session!.document.assets.entries[asset.id];
          if (currentAsset == null ||
              jsonEncode(currentAsset.toJson()) != fingerprint) {
            return;
          }
          _session!.upsertAsset(prepared);
          final previousRemoteApply = _remoteApply;
          _remoteApply = true;
          try {
            _applyMaterializedState();
          } finally {
            _remoteApply = previousRemoteApply;
          }
          _queueSessionOperations();
        }().catchError((error) {
          debugPrint('[CollaborationSession] Asset delivery failed: $error');
        });
    _assetUploadInFlight[asset.id] = future;
    _assetUploadFingerprints[asset.id] = fingerprint;
    unawaited(
      future.whenComplete(() {
        if (identical(_assetUploadInFlight[asset.id], future)) {
          _assetUploadInFlight.remove(asset.id);
          _assetUploadFingerprints.remove(asset.id);
        }
      }),
    );
  }

  void _recordTokenTransition(DesignTokenSet previous, DesignTokenSet next) {
    final session = _session;
    if (_discardCloudStateOnDispose ||
        !_started ||
        !_canEditCanvas ||
        _remoteApply ||
        session == null) {
      return;
    }
    for (final tokenId in previous.entries.keys) {
      if (!next.entries.containsKey(tokenId)) session.deleteToken(tokenId);
    }
    for (final entry in next.entries.entries) {
      final oldToken = previous.entries[entry.key];
      if (oldToken == null ||
          oldToken.toJson().toString() != entry.value.toJson().toString() ||
          previous.modes.toString() != next.modes.toString() ||
          previous.version != next.version) {
        session.upsertToken(
          entry.value,
          modes: next.modes,
          version: next.version,
        );
      }
    }
    _queueSessionOperations();
  }

  void _queueSessionOperations() {
    final session = _session;
    if (_leaving ||
        session == null ||
        (_localAccountId != null && !_accountIsCurrent)) {
      return;
    }
    final operations = session.drainOutbound();
    if (operations.isEmpty) return;
    _pending.addAll(operations);
    final compacted = coalescePendingNodeOperations(
      _pending,
      preservePrefix: _inFlightOperation != null || _flushFuture != null
          ? 1
          : 0,
    );
    _pending
      ..clear()
      ..addAll(compacted);
    state = state.copyWith(pendingOperations: _pending.length);
    if (_pending.isNotEmpty) {
      state = state.copyWith(syncStatus: CollaborationSyncStatus.savedLocally);
    }
    unawaited(_persistPendingQueue());
    if (state.isLive && _room.isConnected) unawaited(_flushPending());
  }

  Future<void> _persistPendingQueue() async {
    final previous = _pendingQueueSave;
    final save = (previous ?? Future<void>.value()).then((_) async {
      final generation = _lifecycleGeneration;
      final accountId = _localAccountId;
      final accountQueueGeneration = _accountQueueGeneration;
      final operations = List<CrdtOperation>.of(_pending);
      if (!_queuePersistenceIsCurrent(generation, accountId)) return;
      final queueJson = jsonEncode(
        operations.map((operation) => operation.toPersistenceJson()).toList(),
      );
      try {
        // Durable storage is authoritative. Scope the primary queue by the
        // account generation so a late write cannot replace another account's
        // queue for the same project.
        await _projectSession.store.writeCollaborationQueue(
          projectId: projectId,
          queueJson: queueJson,
          accountId: accountId,
          generation: accountQueueGeneration,
        );
        if (!_queuePersistenceIsCurrent(generation, accountId)) return;
        await _localStorage.saveAccountScopedCollaborationQueue(
          projectId,
          operations,
          generation: accountQueueGeneration,
          accountId: accountId,
        );
      } catch (error) {
        final message = error.toString().toLowerCase();
        if (!message.contains('already been closed') &&
            !message.contains('database is closed') &&
            !_disposed) {
          debugPrint(
            '[CollaborationSession] Pending queue save failed: $error',
          );
        }
      }
    });
    _pendingQueueSave = save.whenComplete(() {
      if (identical(_pendingQueueSave, save)) _pendingQueueSave = null;
    });
    return save;
  }

  bool _queuePersistenceIsCurrent(int generation, String? accountId) =>
      !_disposed &&
      !_discardCloudStateOnDispose &&
      generation == _lifecycleGeneration &&
      (accountId == null || _accountIsCurrent);

  Future<void> _queuePersistenceBarrier() async {
    final save = _pendingQueueSave;
    if (save != null) await save;
  }

  Future<void> _clearPersistedPendingQueue() async {
    final generation = _lifecycleGeneration;
    final accountId = _localAccountId;
    final accountQueueGeneration = _accountQueueGeneration;
    await _queuePersistenceBarrier();
    if (!_queuePersistenceIsCurrent(generation, accountId)) return;
    try {
      await _projectSession.store.clearCollaborationQueue(
        projectId,
        accountId: accountId,
        generation: accountQueueGeneration,
      );
    } catch (error) {
      if (!_disposed) {
        debugPrint('[CollaborationSession] Pending queue clear failed: $error');
      }
    }
  }

  List<CrdtOperation> _decodeDurableQueue(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final operations = <CrdtOperation>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final operation = CrdtOperation.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (operation.projectId == projectId) operations.add(operation);
        } catch (_) {
          // Ignore one malformed queue item and recover the rest.
        }
      }
      return operations;
    } catch (_) {
      return const [];
    }
  }

  void _applyPendingLocally() {
    final session = _session;
    if (session == null || _pending.isEmpty) return;
    _remoteApply = true;
    try {
      for (final operation in List<CrdtOperation>.from(_pending)) {
        session.applyRemote(operation);
      }
      _applyMaterializedState();
    } finally {
      _remoteApply = false;
    }
  }

  void upsertComment(CanvasComment comment) {
    final session = _session;
    if (!_started || !_canComment || session == null) return;
    final previous = _commentById(comment.id);
    _projectComments.upsertComment(comment);
    if (_localAccountId == null) {
      _ref.read(commentsProvider.notifier).upsertComment(comment);
    }
    session.upsertComment(comment);
    _recordCommentNotifications(previous: previous, current: comment);
    _queueSessionOperations();
  }

  void deleteComment(String commentId) {
    final session = _session;
    if (!_started || !_canComment || session == null) return;
    _projectComments.deleteComment(commentId);
    if (_localAccountId == null) {
      _ref.read(commentsProvider.notifier).deleteComment(commentId);
    }
    session.deleteComment(commentId);
    _queueSessionOperations();
  }

  void insertCommentReply({
    required String commentId,
    required CommentReply reply,
  }) {
    final session = _session;
    if (!_started || !_canComment || session == null) return;
    final previous = _commentById(commentId);
    session.insertCommentReply(commentId: commentId, reply: reply);
    final current = _commentById(commentId);
    if (current != null) {
      _recordCommentNotifications(
        previous: previous,
        current: current,
        actorId: reply.authorId,
        actorName: reply.authorName,
      );
    }
    _updateMaterializedComment(commentId);
    _queueSessionOperations();
  }

  void upsertCommentReply({
    required String commentId,
    required CommentReply reply,
  }) {
    final session = _session;
    if (!_started || !_canComment || session == null) return;
    final previous = _commentById(commentId);
    session.upsertCommentReply(commentId: commentId, reply: reply);
    final current = _commentById(commentId);
    if (current != null) {
      _recordCommentNotifications(
        previous: previous,
        current: current,
        actorId: reply.authorId,
        actorName: reply.authorName,
      );
    }
    _updateMaterializedComment(commentId);
    _queueSessionOperations();
  }

  void deleteCommentReply({
    required String commentId,
    required String replyId,
  }) {
    final session = _session;
    if (!_started || !_canComment || session == null) return;
    session.deleteCommentReply(commentId: commentId, replyId: replyId);
    _updateMaterializedComment(commentId);
    _queueSessionOperations();
  }

  void setCommentReaction({
    required String commentId,
    required String userId,
    required String emoji,
    required bool active,
  }) {
    final session = _session;
    if (!_started || !_canComment || session == null) return;
    session.setCommentReaction(
      commentId: commentId,
      userId: userId,
      emoji: emoji,
      active: active,
    );
    _updateMaterializedComment(commentId);
    _queueSessionOperations();
  }

  bool isCommentReactionActive({
    required String commentId,
    required String userId,
    required String emoji,
  }) =>
      _session?.isCommentReactionActive(
        commentId: commentId,
        userId: userId,
        emoji: emoji,
      ) ??
      false;

  void setCommentResolved({required String commentId, required bool resolved}) {
    final session = _session;
    if (!_started || !_canComment || session == null) return;
    final previous = _commentById(commentId);
    session.setCommentResolved(commentId: commentId, resolved: resolved);
    final current = _commentById(commentId);
    if (current != null) {
      _recordCommentNotifications(previous: previous, current: current);
    }
    _updateMaterializedComment(commentId);
    _queueSessionOperations();
  }

  CanvasComment? _commentById(String commentId) {
    for (final comment in _session?.comments ?? const <CanvasComment>[]) {
      if (comment.id == commentId) return comment;
    }
    return null;
  }

  String _commentActorName(CanvasComment comment, String actorId) {
    for (final reply in comment.replies.reversed) {
      if (reply.authorId == actorId) return reply.authorName;
    }
    if (comment.authorId == actorId) return comment.authorName;
    return 'Collaborator';
  }

  void _recordCommentNotifications({
    required CanvasComment? previous,
    required CanvasComment current,
    String? actorId,
    String? actorName,
  }) {
    final localUserId = _memberUserId;
    if (localUserId == null) return;
    final effectiveActorId = actorId ?? _localUserId ?? current.authorId;
    final effectiveActorName =
        actorName ?? _localUserName ?? current.authorName;
    final notifications = CommentNotificationFactory.fromCommentChange(
      projectId: projectId,
      localUserId: localUserId,
      localUserName: _localUserName ?? '',
      localIdentityAliases: [_localUserId ?? ''],
      previous: previous,
      current: current,
      actorId: effectiveActorId,
      actorName: effectiveActorName,
    );
    if (notifications.isEmpty) return;
    final scope = CommentNotificationScope(
      projectId: projectId,
      userId: localUserId,
    );
    final notifier = _ref.read(commentNotificationsProvider(scope).notifier);
    unawaited(() async {
      await notifier.ready;
      for (final notification in notifications) {
        notifier.upsert(notification);
      }
    }());
  }

  void _updateMaterializedComment(String commentId) {
    final comment = _session?.comments
        .where((candidate) => candidate.id == commentId)
        .firstOrNull;
    if (comment != null) {
      _projectComments.upsertComment(comment);
      if (_localAccountId == null) {
        _ref.read(commentsProvider.notifier).upsertComment(comment);
      }
    }
  }

  Future<void> _flushPending({bool allowLeaving = false}) {
    if (_disposed ||
        _discardCloudStateOnDispose ||
        (!allowLeaving && _leaving) ||
        _pending.isEmpty ||
        !state.isLive ||
        !_room.isConnected) {
      return Future<void>.value();
    }
    state = state.copyWith(syncStatus: CollaborationSyncStatus.syncing);
    final activeFlush = _flushFuture;
    if (activeFlush != null) return activeFlush;

    final flush = _flushPendingInternal(allowLeaving: allowLeaving);
    _flushFuture = flush;
    return flush.whenComplete(() {
      if (identical(_flushFuture, flush)) _flushFuture = null;
    });
  }

  Future<void> _flushPendingInternal({bool allowLeaving = false}) async {
    try {
      while (_pending.isNotEmpty) {
        if (_disposed ||
            _discardCloudStateOnDispose ||
            (!allowLeaving && _leaving) ||
            (_localAccountId != null && !_accountIsCurrent)) {
          return;
        }
        final operation = _pending.first;
        _inFlightOperation = operation;
        try {
          await _room.publish(operation);
        } finally {
          if (identical(_inFlightOperation, operation)) {
            _inFlightOperation = null;
          }
        }
        if (_disposed ||
            _discardCloudStateOnDispose ||
            _leaving ||
            (_localAccountId != null && !_accountIsCurrent)) {
          return;
        }
        final pendingIndex = _pending.indexWhere(
          (candidate) => candidate.opId == operation.opId,
        );
        if (pendingIndex >= 0) _pending.removeAt(pendingIndex);
        unawaited(_persistPendingQueue());
        if (_pending.isEmpty) {
          unawaited(_clearPersistedPendingQueue());
        }
        if (!_disposed && !_discardCloudStateOnDispose) {
          state = state.copyWith(pendingOperations: _pending.length);
        }
      }
      if (!_disposed && !_discardCloudStateOnDispose) {
        state = state.copyWith(
          syncStatus: state.conflicts.isEmpty
              ? CollaborationSyncStatus.synced
              : CollaborationSyncStatus.conflicted,
        );
      }
    } catch (error) {
      if (error is! SyncException ||
          error.message != 'Cloud backend is not configured.') {
        debugPrint(
          '[CollaborationSession] Pending operation flush failed: $error',
        );
      }
      _setConnection(CollaborationConnectionState.offline, error: error);
      if (!_disposed && !_discardCloudStateOnDispose) {
        state = state.copyWith(syncStatus: CollaborationSyncStatus.failed);
      }
    }
  }

  Future<void> retryPendingOperation(String operationId) =>
      retryPendingOperations(operationId: operationId);

  Future<void> retryPendingOperations({String? operationId}) async {
    if (_disposed ||
        _discardCloudStateOnDispose ||
        !_started ||
        _pending.isEmpty) {
      return;
    }
    if (operationId != null &&
        !_pending.any((operation) => operation.opId == operationId)) {
      return;
    }
    state = state.copyWith(syncStatus: CollaborationSyncStatus.syncing);
    try {
      if (!_room.isConnected) {
        final userId = _localUserId;
        final userName = _localUserName;
        final userColor = _localUserColor;
        if (!_room.isConfigured ||
            userId == null ||
            userName == null ||
            userColor == null) {
          if (!_disposed) {
            state = state.copyWith(
              syncStatus: CollaborationSyncStatus.savedLocally,
            );
          }
          return;
        }
        await _room.join(
          projectId: projectId,
          userId: userId,
          memberId: _memberUserId,
          accountId: _localAccountId,
          userName: userName,
          userColor: userColor,
        );
      }
      if (_room.isConnected) {
        await _catchUpAfterReconnect();
      }
      if (!_disposed &&
          !_discardCloudStateOnDispose &&
          _pending.isNotEmpty &&
          !_room.isConnected) {
        state = state.copyWith(
          syncStatus: CollaborationSyncStatus.failed,
          errorMessage: 'Realtime collaboration channel is offline.',
        );
      }
    } catch (error) {
      if (_disposed || _discardCloudStateOnDispose) return;
      _setConnection(CollaborationConnectionState.offline, error: error);
      state = state.copyWith(syncStatus: CollaborationSyncStatus.failed);
    }
  }

  void _handleRemoteOperation(CrdtOperation operation) {
    applyRemoteOperation(operation);
  }

  /// Applies a transport-delivered operation and reconciles all materialized
  /// state, including comments removed by a remote tombstone.
  void applyRemoteOperation(CrdtOperation operation) {
    if (_disposed ||
        _discardCloudStateOnDispose ||
        !_started ||
        (_localAccountId != null && !_accountIsCurrent)) {
      return;
    }
    final session = _session;
    if (session == null) return;
    final previous = _commentById(operation.targetId);
    _recordConcurrentConflict(operation);
    final result = session.applyRemote(operation);
    if (result == CrdtApplyStatus.applied) {
      final current = _commentById(operation.targetId);
      if (current != null) {
        _recordCommentNotifications(
          previous: previous,
          current: current,
          actorId: operation.dot.actorId,
          actorName: _commentActorName(current, operation.dot.actorId),
        );
      }
      _applyMaterializedState();
      unawaited(_updateCheckpointSafely(session.version));
    } else if (result == CrdtApplyStatus.buffered &&
        _started &&
        state.isLive &&
        _room.isConnected) {
      unawaited(_catchUpAfterReconnect());
    }
  }

  void _recordConcurrentConflict(CrdtOperation remoteOperation) {
    if (remoteOperation.dot.actorId == _localUserId) return;
    final localOperation = _pending
        .where(
          (operation) =>
              operation.targetId == remoteOperation.targetId &&
              operation.opId != remoteOperation.opId &&
              operation.dot.actorId != remoteOperation.dot.actorId &&
              operation.kind == remoteOperation.kind &&
              operation.field == remoteOperation.field,
        )
        .firstOrNull;
    if (localOperation == null ||
        !_operationsConcurrent(localOperation, remoteOperation)) {
      return;
    }
    final conflictId = '${localOperation.opId}:${remoteOperation.opId}';
    if (state.conflicts.any((conflict) => conflict.id == conflictId)) return;
    state = state.copyWith(
      conflicts: [
        ...state.conflicts,
        CollaborationConflict(
          id: conflictId,
          targetId: remoteOperation.targetId,
          field: remoteOperation.field,
          localOperation: localOperation,
          remoteOperation: remoteOperation,
          detectedAt: DateTime.now(),
        ),
      ],
      syncStatus: CollaborationSyncStatus.conflicted,
    );
  }

  bool _operationsConcurrent(CrdtOperation first, CrdtOperation second) {
    final firstDot = CrdtVersionVector({first.dot.actorId: first.dot.counter});
    final secondDot = CrdtVersionVector({
      second.dot.actorId: second.dot.counter,
    });
    return !first.dependencies.satisfies(secondDot) &&
        !second.dependencies.satisfies(firstDot);
  }

  void resolveConflict(String conflictId, ConflictResolutionChoice choice) {
    final conflict = state.conflicts
        .where((candidate) => candidate.id == conflictId)
        .firstOrNull;
    final session = _session;
    if (conflict == null || session == null) return;
    _pending.removeWhere(
      (operation) =>
          operation.opId == conflict.localOperation.opId ||
          (operation.targetId == conflict.targetId &&
              operation.dot.actorId == _localUserId),
    );
    final value = switch (choice) {
      ConflictResolutionChoice.keepLocal => conflict.localOperation.value,
      ConflictResolutionChoice.keepRemote => conflict.remoteOperation.value,
      ConflictResolutionChoice.merge => _mergeConflictValues(conflict),
    };
    session.reissueOperation(
      choice == ConflictResolutionChoice.keepLocal
          ? conflict.localOperation
          : conflict.remoteOperation,
      value: value,
    );
    final remaining = state.conflicts
        .where((candidate) => candidate.id != conflictId)
        .toList(growable: false);
    state = state.copyWith(
      conflicts: remaining,
      syncStatus: remaining.isEmpty
          ? CollaborationSyncStatus.savedLocally
          : CollaborationSyncStatus.conflicted,
      pendingOperations: _pending.length,
    );
    _applyMaterializedState();
    _queueSessionOperations();
  }

  Map<String, dynamic> _mergeConflictValues(CollaborationConflict conflict) {
    final merged = <String, dynamic>{...conflict.remoteOperation.value};
    for (final entry in conflict.localOperation.value.entries) {
      final remoteValue = merged[entry.key];
      if (entry.value is Map && remoteValue is Map) {
        merged[entry.key] = {
          ...Map<String, dynamic>.from(remoteValue),
          ...Map<String, dynamic>.from(entry.value as Map),
        };
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  Future<void> _updateCheckpointSafely(CrdtVersionVector version) async {
    if (_disposed || _discardCloudStateOnDispose || !_started || _leaving) {
      return;
    }
    final generation = _lifecycleGeneration;
    final accountId = _localAccountId;
    try {
      await _room.updateCheckpoint(projectId: projectId, version: version);
      if (!_cloudOperationIsCurrent(generation) ||
          !_started ||
          _leaving ||
          _localAccountId != accountId) {
        return;
      }
    } catch (error) {
      if (!_disposed &&
          !_discardCloudStateOnDispose &&
          _cloudOperationIsCurrent(generation)) {
        debugPrint('[CollaborationSession] Checkpoint update failed: $error');
      }
    }
  }

  void _applyMaterializedState() {
    if (_disposed ||
        _discardCloudStateOnDispose ||
        (_localAccountId != null && !_accountIsCurrent)) {
      return;
    }
    final session = _session;
    if (session == null) return;
    _remoteApply = true;
    try {
      _ref
          .read(documentNodesProvider.notifier)
          .setNodes(session.document.nodes, clearSelection: false);
      _ref
          .read(documentEdgesProvider.notifier)
          .setEdges(session.document.edges);
      _ref
          .read(documentAssetsProvider.notifier)
          .setManifest(session.document.assets);
      _ref
          .read(designTokenSetProvider.notifier)
          .setSet(session.document.tokens);
      _projectComments.reconcile(session.comments);
      if (_localAccountId == null) {
        _ref.read(commentsProvider.notifier).reconcile(session.comments);
      }
    } finally {
      _remoteApply = false;
    }
  }

  void updatePresence({
    required Offset worldPosition,
    required Set<String> selectedNodeIds,
    double viewportX = 0,
    double viewportY = 0,
    double viewportZoom = 1,
    String? activeNodeId,
    bool editing = false,
  }) {
    if (_disposed ||
        _discardCloudStateOnDispose ||
        !_started ||
        _localUserId == null ||
        _localUserName == null) {
      return;
    }
    final presence = <String, dynamic>{
      'userId': _memberUserId ?? _localUserId,
      'sessionId': _localUserId,
      'userName': _localUserName,
      'userColor': _localUserColor?.toARGB32() ?? 0xFFF97316,
      'x': worldPosition.dx,
      'y': worldPosition.dy,
      'selectedNodeIds': selectedNodeIds.toList(growable: false),
      'activeNodeId': activeNodeId,
      'editing': editing,
      'viewportX': viewportX,
      'viewportY': viewportY,
      'viewportZoom': viewportZoom,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    _lastPresencePayload = presence;
    _pendingPresence = presence;
    _schedulePresenceUpdate();
  }

  void _schedulePresenceUpdate() {
    if (_presenceTimer != null ||
        _presenceSending ||
        _pendingPresence == null) {
      return;
    }
    _presenceTimer = Timer(const Duration(milliseconds: 120), () {
      _presenceTimer = null;
      if (_disposed || _discardCloudStateOnDispose) return;
      final presence = _pendingPresence;
      _pendingPresence = null;
      if (presence == null) return;
      _presenceSending = true;
      unawaited(() async {
        try {
          await _room.broadcastPresence(presence);
        } catch (error) {
          debugPrint('[CollaborationSession] Presence update failed: $error');
        } finally {
          _presenceSending = false;
          _schedulePresenceUpdate();
        }
      }());
    });
  }

  void _handleRemotePresence(Map<String, dynamic> payload) {
    if (_disposed || _discardCloudStateOnDispose || !_started) return;
    final userId = payload['userId']?.toString();
    if (userId == null ||
        userId == _localUserId ||
        userId == _memberUserId ||
        payload['sessionId']?.toString() == _localUserId) {
      return;
    }
    _remotePresenceSeenAt[userId] = DateTime.now();
    final existingMember = state.members[userId];
    final displayName = CollaborationDisplayNameGenerator.resolve(
      stableId: userId,
      preferredName:
          payload['userName']?.toString() ?? existingMember?.displayName,
    );
    final selected = payload['selectedNodeIds'];
    final presence = RemotePresence(
      userId: userId,
      userName: displayName,
      userColor: Color((payload['userColor'] as num?)?.toInt() ?? 0xFFF97316),
      x: (payload['x'] as num?)?.toDouble() ?? 0.0,
      y: (payload['y'] as num?)?.toDouble() ?? 0.0,
      selectedNodeIds: selected is List
          ? selected.map((value) => value.toString()).toSet()
          : const {},
      activeNodeId: payload['activeNodeId']?.toString(),
      editing: payload['editing'] as bool? ?? false,
      viewportX: (payload['viewportX'] as num?)?.toDouble() ?? 0,
      viewportY: (payload['viewportY'] as num?)?.toDouble() ?? 0,
      viewportZoom: (payload['viewportZoom'] as num?)?.toDouble() ?? 1,
      lastActive: DateTime.now(),
    );
    state = state.copyWith(
      collaborators: {...state.collaborators, userId: presence},
      members: {
        ...state.members,
        userId:
            (existingMember ??
                    CanvasMember(
                      projectId: projectId,
                      userId: userId,
                      role: CollaborationRole.viewer.wireName,
                      displayName: displayName,
                    ))
                .copyWith(
                  displayName: displayName,
                  online: true,
                  cursorActive: presence.editing,
                  lastSeenAt: presence.lastActive,
                ),
      },
    );
    if (state.followingUserId == userId) {
      final viewport = _ref.read(viewportProvider.notifier);
      viewport.setPosition(presence.viewportX, presence.viewportY);
      viewport.setZoom(presence.viewportZoom);
    }
    _projectCursors.updateCursor(
      presence.userId,
      presence.userName,
      presence.userColor,
      presence.x,
      presence.y,
      selectedNodeId: presence.activeNodeId,
      selectedNodeIds: presence.selectedNodeIds,
    );
    if (_localAccountId == null) {
      _ref
          .read(remoteCursorsProvider.notifier)
          .updateCursor(
            presence.userId,
            presence.userName,
            presence.userColor,
            presence.x,
            presence.y,
            selectedNodeId: presence.activeNodeId,
            selectedNodeIds: presence.selectedNodeIds,
          );
    }
  }

  void _handlePresenceJoin(Map<String, dynamic> payload) {
    if (_disposed || _discardCloudStateOnDispose || !_started) return;
    final userId = payload['userId']?.toString();
    if (userId == null ||
        userId.isEmpty ||
        userId == _localUserId ||
        userId == _memberUserId ||
        payload['sessionId']?.toString() == _localUserId) {
      return;
    }
    _remotePresenceSeenAt[userId] = DateTime.now();
    final member = state.members[userId];
    final wasOnline = member?.online ?? false;
    final displayName = CollaborationDisplayNameGenerator.resolve(
      stableId: userId,
      preferredName: payload['userName']?.toString() ?? member?.displayName,
    );
    state = state.copyWith(
      members: {
        ...state.members,
        userId:
            (member ??
                    CanvasMember(
                      projectId: projectId,
                      userId: userId,
                      role: CollaborationRole.viewer.wireName,
                      displayName: displayName,
                    ))
                .copyWith(
                  displayName: displayName,
                  online: true,
                  lastSeenAt: DateTime.now(),
                ),
      },
    );
    if (wasOnline) return;
    _emitNotice(
      userId: userId,
      displayName: displayName,
      kind: CollaborationNoticeKind.joined,
    );
  }

  void _handlePresenceLeave(Map<String, dynamic> payload) {
    if (_disposed || _discardCloudStateOnDispose || !_started) return;
    final userId = payload['userId']?.toString();
    if (userId == null ||
        userId.isEmpty ||
        userId == _localUserId ||
        userId == _memberUserId ||
        payload['sessionId']?.toString() == _localUserId) {
      return;
    }
    final member = state.members[userId];
    final wasOnline = member?.online ?? state.collaborators.containsKey(userId);
    _removePresence(userId);
    if (!wasOnline) return;
    _emitNotice(
      userId: userId,
      displayName: CollaborationDisplayNameGenerator.resolve(
        stableId: userId,
        preferredName: payload['userName']?.toString() ?? member?.displayName,
      ),
      kind: CollaborationNoticeKind.left,
    );
  }

  void _emitNotice({
    required String userId,
    required String displayName,
    required CollaborationNoticeKind kind,
    CollaborationRole? role,
  }) {
    if (_disposed || _discardCloudStateOnDispose) return;
    final normalizedName = CollaborationDisplayNameGenerator.resolve(
      stableId: userId,
      preferredName: displayName,
    );
    state = state.copyWith(
      notice: CollaborationNotice(
        id: '${kind.name}-$userId-${DateTime.now().microsecondsSinceEpoch}',
        userId: userId,
        displayName: normalizedName,
        kind: kind,
        role: role,
        createdAt: DateTime.now(),
      ),
    );
  }

  void _removePresence(String userId) {
    if (_disposed || _discardCloudStateOnDispose) return;
    _remotePresenceSeenAt.remove(userId);
    final collaborators = {...state.collaborators}..remove(userId);
    final member = state.members[userId];
    state = state.copyWith(
      collaborators: collaborators,
      members: member == null
          ? state.members
          : {
              ...state.members,
              userId: member.copyWith(online: false, cursorActive: false),
            },
    );
    _projectCursors.removeCursor(userId);
    if (_localAccountId == null) {
      _ref.read(remoteCursorsProvider.notifier).removeCursor(userId);
    }
  }

  void _clearRemotePresence() {
    _remotePresenceSeenAt.clear();
    final localUserId = _memberUserId ?? _localUserId;
    state = state.copyWith(
      collaborators: const {},
      members: {
        for (final entry in state.members.entries)
          entry.key: entry.key == localUserId || entry.key == _localUserId
              ? entry.value
              : entry.value.copyWith(online: false, cursorActive: false),
      },
    );
  }

  void _handleRoomDisabled() {
    if (_disposed || _discardCloudStateOnDispose || !_started) return;
    unawaited(_terminateMeetingAndLeave(MeetingTerminationReason.roomRevoked));
  }

  Future<void> _terminateMeetingAndLeave(
    MeetingTerminationReason reason,
  ) async {
    try {
      await _onMeetingTermination?.call(reason);
    } finally {
      if (!_disposed && !_discardCloudStateOnDispose) await leave();
    }
  }

  void _handleConnectionState(
    CollaborationConnectionState connection,
    Object? error,
  ) {
    if (_disposed ||
        _discardCloudStateOnDispose ||
        !_started ||
        _suppressStateUpdates) {
      return;
    }
    final previousConnection = state.connection;
    if (connection == CollaborationConnectionState.offline ||
        connection == CollaborationConnectionState.disconnected) {
      _clearRemotePresence();
      _clearProjectCursors();
    }
    _setConnection(connection, error: error);
    if (connection == CollaborationConnectionState.live) {
      unawaited(_flushPending());
    }
    if (connection == CollaborationConnectionState.catchingUp &&
        previousConnection == CollaborationConnectionState.offline) {
      unawaited(_catchUpAfterReconnect());
    }
  }

  Future<void> _catchUpAfterReconnect() {
    final activeCatchUp = _reconnectCatchUpFuture;
    if (activeCatchUp != null) return activeCatchUp;
    final catchUp = _catchUpAfterReconnectInternal();
    _reconnectCatchUpFuture = catchUp;
    return catchUp.whenComplete(() {
      if (identical(_reconnectCatchUpFuture, catchUp)) {
        _reconnectCatchUpFuture = null;
      }
    });
  }

  Future<void> _catchUpAfterReconnectInternal() async {
    final generation = _lifecycleGeneration;
    final session = _session;
    if (!_cloudOperationIsCurrent(generation) || !_started || session == null) {
      return;
    }
    try {
      final delta = await _room.fetchDelta(
        projectId: projectId,
        version: session.version,
      );
      if (!_cloudOperationIsCurrent(generation)) return;
      final pending = List<CrdtOperation>.from(_pending);
      final shouldApplySnapshot =
          delta.document != null && !session.version.satisfies(delta.version);
      if (shouldApplySnapshot) {
        _session = CrdtDocumentSession.fromSnapshot(
          document: delta.document!,
          actorId: _localUserId!,
          version: delta.version,
          state: delta.state,
          comments: delta.comments,
        );
        _applyMaterializedState();
      }
      for (final operation in delta.operations) {
        applyRemoteOperation(operation);
      }
      for (final operation in pending) {
        applyRemoteOperation(operation);
      }
      if (!_cloudOperationIsCurrent(generation)) return;
      _setConnection(CollaborationConnectionState.live, clearError: true);
      await _flushPending();
      if (!_cloudOperationIsCurrent(generation)) return;
    } catch (error) {
      if (!_cloudOperationIsCurrent(generation)) return;
      _setConnection(CollaborationConnectionState.offline, error: error);
    }
  }

  void _setConnection(
    CollaborationConnectionState connection, {
    Object? error,
    bool clearError = false,
  }) {
    if (_disposed || _discardCloudStateOnDispose || _suppressStateUpdates) {
      return;
    }
    state = state.copyWith(
      connection: connection,
      errorMessage: error?.toString(),
      clearError: clearError,
    );
  }

  bool get isStarted => _started;
  bool get hasVerifiedMembership => _hasVerifiedMembership;

  String? get lastErrorMessage => state.errorMessage;

  String? get localUserName => _localUserName;

  Future<bool> _prepareSessionAssetsForSnapshot({
    required int generation,
    bool allowLeaving = false,
  }) async {
    final session = _session;
    if (session == null || !_cloudOperationIsCurrent(generation)) return false;
    final document = session.document;
    final prepared = await _syncService.prepareCollaborativeDocument(
      document,
      expectedUserId: _localAccountId,
    );
    if (prepared == null ||
        !_cloudOperationIsCurrent(generation) ||
        (!allowLeaving && _leaving) ||
        prepared.projectId != projectId) {
      return false;
    }
    if (jsonEncode(prepared.assets.toPersistenceJson()) ==
        jsonEncode(document.assets.toPersistenceJson())) {
      return true;
    }
    _session = CrdtDocumentSession.fromDocument(
      prepared,
      actorId: _localUserId ?? 'collaboration-host',
    )..seedComments(session.comments);
    _applyMaterializedState();
    return true;
  }

  @visibleForTesting
  bool applyPreparedDocumentForTesting(CanvasDocument preparedDocument) =>
      _applyPreparedDocumentToSession(
        preparedDocument: preparedDocument,
        generation: _lifecycleGeneration,
      );

  bool _applyPreparedDocumentToSession({
    required CanvasDocument preparedDocument,
    required int generation,
    bool allowLeaving = false,
  }) {
    try {
      preparedDocument.assets.validateIdentity();
    } on FormatException catch (error) {
      debugPrint(
        '[CollaborationSession] Prepared document rejected because its asset '
        'manifest identity is invalid: $error',
      );
      if (!_disposed && !_suppressStateUpdates) {
        state = state.copyWith(
          syncStatus: CollaborationSyncStatus.failed,
          errorMessage: error.message,
        );
      }
      return false;
    }
    final session = _session;
    if (session == null ||
        !_cloudOperationIsCurrent(generation) ||
        (!allowLeaving && _leaving) ||
        preparedDocument.projectId != projectId) {
      return false;
    }

    final currentDocument = session.document;
    final currentNodes = {
      for (final node in currentDocument.nodes) node.id: node,
    };
    final preparedNodes = {
      for (final node in preparedDocument.nodes) node.id: node,
    };
    final currentEdges = {
      for (final edge in currentDocument.edges) edge.id: edge,
    };
    final preparedEdges = {
      for (final edge in preparedDocument.edges) edge.id: edge,
    };
    final currentAssets = currentDocument.assets.entries;
    final preparedAssets = preparedDocument.assets.entries;
    final currentTokens = currentDocument.tokens.entries;
    final preparedTokens = preparedDocument.tokens.entries;

    final previousRemoteApply = _remoteApply;
    _remoteApply = true;
    try {
      for (final id in currentNodes.keys) {
        if (!preparedNodes.containsKey(id)) session.deleteNode(id);
      }
      for (final entry in preparedNodes.entries) {
        final current = currentNodes[entry.key];
        if (current == null ||
            jsonEncode(current.toPersistenceJson()) !=
                jsonEncode(entry.value.toPersistenceJson())) {
          session.upsertNode(entry.value);
        }
      }

      for (final id in currentEdges.keys) {
        if (!preparedEdges.containsKey(id)) session.deleteEdge(id);
      }
      for (final entry in preparedEdges.entries) {
        final current = currentEdges[entry.key];
        if (current == null ||
            jsonEncode(current.toPersistenceJson()) !=
                jsonEncode(entry.value.toPersistenceJson())) {
          session.upsertEdge(entry.value);
        }
      }

      for (final id in currentAssets.keys) {
        if (!preparedAssets.containsKey(id)) session.deleteAsset(id);
      }
      for (final entry in preparedAssets.entries) {
        final current = currentAssets[entry.key];
        if (current == null ||
            jsonEncode(current.toPersistenceJson()) !=
                jsonEncode(entry.value.toPersistenceJson())) {
          session.upsertAsset(entry.value);
        }
      }

      for (final id in currentTokens.keys) {
        if (!preparedTokens.containsKey(id)) session.deleteToken(id);
      }
      for (final entry in preparedTokens.entries) {
        final current = currentTokens[entry.key];
        if (current == null ||
            jsonEncode(current.toJson()) != jsonEncode(entry.value.toJson()) ||
            currentDocument.tokens.version != preparedDocument.tokens.version ||
            currentDocument.tokens.modes.toString() !=
                preparedDocument.tokens.modes.toString()) {
          session.upsertToken(
            entry.value,
            modes: preparedDocument.tokens.modes,
            version: preparedDocument.tokens.version,
          );
        }
      }
    } catch (error) {
      debugPrint(
        '[CollaborationSession] Prepared document merge failed: $error',
      );
      return false;
    } finally {
      _remoteApply = previousRemoteApply;
    }

    if (!_cloudOperationIsCurrent(generation) || (!allowLeaving && _leaving)) {
      return false;
    }
    _applyMaterializedState();
    _queueSessionOperations();
    return true;
  }

  Future<bool> _awaitCollaborativeAssetStaging({
    required int generation,
    bool allowLeaving = false,
  }) async {
    while (_assetUploadInFlight.isNotEmpty) {
      final pending = List<Future<void>>.of(_assetUploadInFlight.values);
      await Future.wait(pending);
      if (!_cloudOperationIsCurrent(generation) ||
          (!allowLeaving && _leaving)) {
        return false;
      }
    }
    final session = _session;
    if (session == null || !_cloudOperationIsCurrent(generation)) return false;
    final unresolved = session.document.assets.items.any(
      _requiresCollaborativeAssetDelivery,
    );
    return !unresolved;
  }

  Future<bool> persistSnapshot({
    bool allowLeaving = false,
    CanvasDocument? preparedDocument,
  }) async {
    final generation = _lifecycleGeneration;
    var session = _session;
    if (!_cloudOperationIsCurrent(generation) ||
        (!allowLeaving && _leaving) ||
        !_started ||
        session == null) {
      return false;
    }
    if (!_canEditCanvas) return true;
    if (preparedDocument != null &&
        !_applyPreparedDocumentToSession(
          preparedDocument: preparedDocument,
          generation: generation,
          allowLeaving: allowLeaving,
        )) {
      return false;
    }
    if (!await _awaitCollaborativeAssetStaging(
      generation: generation,
      allowLeaving: allowLeaving,
    )) {
      return false;
    }
    if (!_cloudOperationIsCurrent(generation)) return false;
    await _flushPending(allowLeaving: allowLeaving);
    if (!await _awaitCollaborativeAssetStaging(
      generation: generation,
      allowLeaving: allowLeaving,
    )) {
      return false;
    }
    if (!_cloudOperationIsCurrent(generation) ||
        (!allowLeaving && _leaving) ||
        _pending.isNotEmpty) {
      return false;
    }
    // Asset preparation and remote reconciliation can replace the CRDT
    // session while the asynchronous staging barrier is open. Encode and
    // checkpoint the current session, never the instance captured at entry.
    session = _session;
    if (session == null) return false;
    final encoded = jsonDecode(session.encodeState());
    if (encoded is! Map || !_cloudOperationIsCurrent(generation)) {
      return false;
    }
    await _room.saveSnapshot(
      projectId: projectId,
      state: Map<String, dynamic>.from(encoded),
      version: session.version,
    );
    if (!_cloudOperationIsCurrent(generation)) return false;
    try {
      await _room.updateCheckpoint(
        projectId: projectId,
        version: session.version,
      );
    } catch (error) {
      if (_cloudOperationIsCurrent(generation)) {
        debugPrint('[CollaborationSession] Checkpoint update skipped: $error');
      }
    }
    return _cloudOperationIsCurrent(generation);
  }

  Future<void> reconnect() async {
    if (_disposed || _discardCloudStateOnDispose || !_started || _leaving) {
      return;
    }
    final generation = _lifecycleGeneration;
    final accountId = _localAccountId;
    final session = _session;
    final userId = _localUserId;
    final userName = _localUserName;
    final userColor = _localUserColor;
    if (session == null ||
        userId == null ||
        userName == null ||
        userColor == null) {
      return;
    }
    await _room.join(
      projectId: projectId,
      userId: userId,
      memberId: _memberUserId,
      accountId: accountId,
      userName: userName,
      userColor: userColor,
    );
    if (!_cloudOperationIsCurrent(generation) ||
        !_started ||
        _leaving ||
        _localAccountId != accountId) {
      return;
    }
    await _catchUpAfterReconnect();
  }

  Future<void> disableRoom() async {
    if (!permissions.canManageRoom) {
      throw const SyncException('Only the host can disable the room.');
    }
    await _onMeetingTermination?.call(MeetingTerminationReason.roomRevoked);
    await _room.broadcastRoomDisabled();
    await leave();
  }

  Future<void> leave({bool updateState = true}) {
    final activeLeave = _leaveFuture;
    if (activeLeave != null) return activeLeave;
    final leave = _leaveInternal(updateState: updateState);
    _leaveFuture = leave;
    return leave.whenComplete(() {
      if (identical(_leaveFuture, leave)) _leaveFuture = null;
    });
  }

  Future<void> _leaveInternal({required bool updateState}) async {
    if (_leaving) return;
    _leaving = true;
    _lifecycleGeneration++;
    final previousSuppressStateUpdates = _suppressStateUpdates;
    if (!updateState) _suppressStateUpdates = true;
    _presenceTimer?.cancel();
    _presenceExpiryTimer?.cancel();
    _presenceExpiryTimer = null;
    _memberHeartbeatTimer?.cancel();
    _memberHeartbeatTimer = null;
    _pendingPresence = null;
    _lastPresencePayload = null;
    _remotePresenceSeenAt.clear();
    if (updateState && !_disposed && !_discardCloudStateOnDispose) {
      _clearRemotePresence();
      _clearProjectCursors();
    }
    var snapshotPersisted = false;
    try {
      if (_started &&
          _session != null &&
          _room.isConfigured &&
          _canEditCanvas) {
        try {
          if (await _prepareSessionAssetsForSnapshot(
            generation: _lifecycleGeneration,
            allowLeaving: true,
          )) {
            snapshotPersisted = await persistSnapshot(allowLeaving: true);
          }
        } catch (error) {
          debugPrint('[CollaborationSession] Leave snapshot failed: $error');
        }
      }
      _started = false;
      _inFlightOperation = null;
      if (snapshotPersisted || _pending.isEmpty) {
        _pending.clear();
      }
      await _persistPendingQueue();
      await _stopScreenTrackingLocally();
      await _room.leave();
    } finally {
      _suppressStateUpdates = previousSuppressStateUpdates;
      _session = null;
      _leaving = false;
      if (!_disposed && updateState) {
        _clearProjectCursors();
        _clearProjectComments();
        state = state.copyWith(
          connection: CollaborationConnectionState.disconnected,
          pendingOperations: 0,
          collaborators: const {},
          clearError: true,
        );
      }
    }
    if (_disposed || !updateState) return;
    _clearProjectCursors();
    _clearProjectComments();
    state = state.copyWith(
      connection: CollaborationConnectionState.disconnected,
      pendingOperations: 0,
      collaborators: const {},
      clearError: true,
    );
  }

  @override
  void dispose() {
    _activeCollaborationControllers.remove(this);
    try {
      _clearProjectCursors();
      _clearProjectComments();
    } catch (_) {
      // The owning ProviderContainer may already be closing.
    }
    _disposed = true;
    _presenceTimer?.cancel();
    _presenceExpiryTimer?.cancel();
    _presenceExpiryTimer = null;
    _memberHeartbeatTimer?.cancel();
    _memberHeartbeatTimer = null;
    _pendingPresence = null;
    _lastPresencePayload = null;
    _remotePresenceSeenAt.clear();
    unawaited(() async {
      _started = false;
      _session = null;
      _pending.clear();
      _inFlightOperation = null;
      _assetUploadInFlight.clear();
      await _room.leave();
      if (_activeCollaborationControllers.isEmpty) {
        try {
          _clearProjectCursors();
          _clearProjectComments();
        } catch (_) {
          // The owning ProviderContainer may already be closing.
        }
      }
    }());
    unawaited(_screenTracking.dispose());
    super.dispose();
  }
}
