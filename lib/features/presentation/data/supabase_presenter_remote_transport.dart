import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/remote/supabase_service.dart';
import '../domain/remote_presenter_control.dart';

Map<String, dynamic>? extractPresenterRemoteCommandPayload(
  Map<String, dynamic> payload,
) {
  dynamic candidate = payload;
  for (var depth = 0; depth < 3; depth++) {
    if (candidate is! Map) return null;
    final normalized = Map<String, dynamic>.from(candidate);
    if (normalized['commandId'] is String &&
        normalized['sessionId'] is String &&
        normalized['action'] is String) {
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

class SupabasePresenterRemoteTransport {
  final SupabaseClient? Function() _clientProvider;
  final SupabaseSyncService? _providedSyncService;
  final StreamController<PresenterRemoteCommand> _commands =
      StreamController<PresenterRemoteCommand>.broadcast();

  RealtimeChannel? _channel;
  PresenterRemoteSession? _session;
  SupabaseSyncService? _ownedSyncService;
  String? _localActorId;
  bool _subscribed = false;
  bool _disposed = false;

  SupabasePresenterRemoteTransport(
    SupabaseClient? client, {
    SupabaseClient? Function()? clientProvider,
    SupabaseSyncService? syncService,
  }) : _clientProvider = clientProvider ?? (() => client),
       _providedSyncService = syncService;

  SupabaseClient? get _client {
    try {
      return _clientProvider();
    } catch (_) {
      return null;
    }
  }

  SupabaseSyncService? get _syncService {
    final provided = _providedSyncService;
    if (provided != null) return provided;
    final client = _client;
    if (client == null) return null;
    return _ownedSyncService ??= SupabaseSyncService(client);
  }

  Stream<PresenterRemoteCommand> get commands => _commands.stream;
  bool get isConnected => _subscribed;

  Future<void> join({
    required PresenterRemoteSession session,
    required String localActorId,
  }) async {
    if (_disposed) {
      throw const SyncException('Presenter remote transport is disposed.');
    }
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final user = client.auth.currentUser ?? client.auth.currentSession?.user;
    if (user == null) {
      throw const SyncException(
        'Sign in is required before joining presenter remote control.',
      );
    }
    final syncService = _syncService;
    if (syncService == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final currentSession = await syncService.getPresenterRemoteSession(
      session.sessionId,
    );
    if (!currentSession.consentGranted ||
        !currentSession.isActive(DateTime.now().toUtc())) {
      throw const SyncException(
        'Presenter remote session is expired or revoked.',
      );
    }

    await leave();
    final ready = Completer<void>();
    final channel = client.channel('presentation_remote:${session.sessionId}');
    channel.onBroadcast(
      event: 'presenter_command',
      callback: (payload) {
        final normalized = extractPresenterRemoteCommandPayload(payload);
        if (normalized == null ||
            normalized['sessionId'] != session.sessionId ||
            normalized['actorId']?.toString() == localActorId) {
          return;
        }
        try {
          _commands.add(PresenterRemoteCommand.fromJson(normalized));
        } catch (_) {
          // Ignore malformed broadcasts; the sender still has an auditable ID.
        }
      },
    );
    _session = session;
    _localActorId = localActorId;
    _channel = channel;
    channel.subscribe((status, [error]) {
      if (!identical(_channel, channel)) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        _subscribed = true;
        if (!ready.isCompleted) ready.complete();
      } else if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _subscribed = false;
        final reason = error ?? StateError('Presenter remote channel $status.');
        if (!ready.isCompleted) ready.completeError(reason);
      }
    });

    try {
      await ready.future.timeout(const Duration(seconds: 15));
    } catch (error) {
      await leave();
      if (error is SyncException) rethrow;
      throw SyncException('Failed to join presenter remote control.', error);
    }
  }

  Future<void> send(PresenterRemoteCommand command) async {
    final channel = _channel;
    final session = _session;
    final actorId = _localActorId;
    if (channel == null || session == null || actorId == null || !_subscribed) {
      throw const SyncException('Presenter remote channel is not connected.');
    }
    if (!command.isValidFor(session, DateTime.now().toUtc())) {
      throw const SyncException(
        'Presenter remote command is expired or unauthorized.',
      );
    }
    final syncService = _syncService;
    if (syncService == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final persisted = await syncService.appendPresenterRemoteCommand(command);
    final payload = persisted.toJson()
      ..['actorId'] = persisted.actorId ?? actorId
      ..['projectId'] = persisted.projectId ?? session.projectId;
    final response = await channel.sendBroadcastMessage(
      event: 'presenter_command',
      payload: payload,
    );
    if (response != ChannelResponse.ok) {
      throw SyncException(
        'Presenter remote command was not delivered: $response',
      );
    }
  }

  Future<void> leave() async {
    final client = _client;
    final channel = _channel;
    _channel = null;
    _session = null;
    _localActorId = null;
    _subscribed = false;
    if (client != null && channel != null) {
      try {
        await client.removeChannel(channel);
      } catch (_) {
        channel.unsubscribe();
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await leave();
    await _commands.close();
    _ownedSyncService?.dispose();
    _ownedSyncService = null;
  }
}
