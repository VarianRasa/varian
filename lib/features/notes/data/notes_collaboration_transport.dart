import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/remote/supabase_service.dart';

final notesCollaborationTransportProvider =
    Provider<NotesCollaborationTransport>((ref) {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) {
        throw StateError('Notes collaboration requires an account.');
      }
      final transport = NotesCollaborationTransport(client);
      ref.onDispose(() => unawaited(transport.leave()));
      return transport;
    });

enum NotesConnectionState { disconnected, connecting, live, denied, error }

class NotesCursorAnchor {
  const NotesCursorAnchor({required this.atomId, required this.bias});
  final String? atomId;
  final String bias;

  Map<String, dynamic> toJson() => {'atomId': atomId, 'bias': bias};

  static NotesCursorAnchor? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    if (map.length != 2 ||
        !map.containsKey('atomId') ||
        !map.containsKey('bias')) {
      return null;
    }
    final atomId = map['atomId'];
    final bias = map['bias'];
    if ((atomId != null && atomId is! String) ||
        (bias != 'before' && bias != 'after')) {
      return null;
    }
    return NotesCursorAnchor(atomId: atomId as String?, bias: bias as String);
  }
}

String? parseNotesOperationHint(Map<String, dynamic> payload, String noteId) {
  final operationId = payload['operationId'];
  if (payload.length != 1 ||
      operationId is! String ||
      operationId.length > 256 ||
      !operationId.startsWith('$noteId:')) {
    return null;
  }
  return operationId;
}

({String userId, NotesCursorAnchor? anchor})? parseNotesCursorPayload(
  Map<String, dynamic> payload, {
  required String localUserId,
}) {
  if (payload.length != 2) return null;
  final userId = payload['userId'];
  if (userId is! String || userId.isEmpty || userId == localUserId) return null;
  final rawAnchor = payload['anchor'];
  if (rawAnchor == null) return (userId: userId, anchor: null);
  final anchor = NotesCursorAnchor.fromJson(rawAnchor);
  return anchor == null ? null : (userId: userId, anchor: anchor);
}

class NotesCollaborationTransport {
  NotesCollaborationTransport(this._client);
  final SupabaseClient _client;
  RealtimeChannel? _channel;
  Timer? _reconnectTimer;
  final Set<String> _seenOperationIds = {};
  int _reconnectAttempts = 0;
  bool _reconnecting = false;
  String? _noteId;
  String? _projectId;
  String? _accountId;
  int _generation = 0;
  NotesConnectionState state = NotesConnectionState.disconnected;
  void Function(String operationId)? onOperationHint;
  void Function(Map<String, dynamic> operation)? onRemoteOperation;
  void Function(String userId, NotesCursorAnchor? anchor)? onCursor;
  void Function(NotesConnectionState state)? onState;

  String? get _currentUserId =>
      _client.auth.currentUser?.id ?? _client.auth.currentSession?.user.id;

  Future<void> join(String noteId, String projectId) async {
    final userId = _currentUserId;
    if (userId == null) throw StateError('Authentication required.');
    if (_noteId == noteId &&
        _projectId == projectId &&
        _accountId == userId &&
        _channel != null) {
      return;
    }
    await _leave(resetReconnectAttempts: !_reconnecting);
    final generation = ++_generation;
    _noteId = noteId;
    _projectId = projectId;
    _accountId = userId;
    _setState(NotesConnectionState.connecting);
    try {
      // The RPC is the authorization boundary; it checks current note/project access.
      await _client.rpc(
        'get_workspace_note_crdt_delta',
        params: {
          'p_note_id': noteId,
          'p_since': <String, dynamic>{},
          'p_limit': 1,
        },
      );
      final note = await _client
          .from('workspace_notes')
          .select('project_id')
          .eq('id', noteId)
          .maybeSingle();
      if (note == null || note['project_id'] != projectId) {
        throw const PostgrestException(
          code: '42501',
          message: 'Notes membership denied.',
        );
      }
      if (!_isCurrent(generation, userId)) return;
      final channel = _client.channel(
        'notes:$noteId',
        opts: const RealtimeChannelConfig(private: true),
      );
      channel.onBroadcast(
        event: 'operation_hint',
        callback: (payload) {
          if (!_isCurrent(generation, userId)) return;
          unawaited(_receiveOperationHint(payload, generation, userId));
        },
      );
      channel.onBroadcast(
        event: 'cursor',
        callback: (payload) {
          if (!_isCurrent(generation, userId)) return;
          final cursor = parseNotesCursorPayload(payload, localUserId: userId);
          if (cursor != null) onCursor?.call(cursor.userId, cursor.anchor);
        },
      );
      _channel = channel;
      channel.subscribe((status, [error]) {
        if (!_isCurrent(generation, userId)) return;
        if (status == RealtimeSubscribeStatus.subscribed) {
          _reconnectAttempts = 0;
          _setState(NotesConnectionState.live);
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.timedOut) {
          _setState(NotesConnectionState.error);
          _scheduleReconnect(generation, userId);
        }
      });
    } catch (error) {
      if (_isCurrent(generation, userId)) {
        _setState(
          error is PostgrestException && error.code == '42501'
              ? NotesConnectionState.denied
              : NotesConnectionState.error,
        );
      }
      rethrow;
    }
  }

  void _scheduleReconnect(int generation, String userId) {
    if (_reconnectTimer != null || _reconnectAttempts >= 5) return;
    final noteId = _noteId;
    final projectId = _projectId;
    if (noteId == null || projectId == null) return;
    _reconnectAttempts++;
    _reconnectTimer = Timer(
      Duration(milliseconds: 300 * _reconnectAttempts),
      () async {
        _reconnectTimer = null;
        if (!_isCurrent(generation, userId)) return;
        final channel = _channel;
        _channel = null;
        _reconnecting = true;
        try {
          if (channel != null) await _client.removeChannel(channel);
          await join(noteId, projectId);
        } catch (_) {
          _setState(NotesConnectionState.error);
        } finally {
          _reconnecting = false;
        }
      },
    );
  }

  Future<void> _receiveOperationHint(
    Map<String, dynamic> payload,
    int generation,
    String userId,
  ) async {
    final noteId = _noteId;
    if (noteId == null) return;
    final operationId = parseNotesOperationHint(payload, noteId);
    if (operationId == null || !_seenOperationIds.add(operationId)) return;
    if (_seenOperationIds.length > 5000) {
      _seenOperationIds.remove(_seenOperationIds.first);
    }
    try {
      final row = await _client
          .from('workspace_note_crdt_operations')
          .select('operation_json')
          .eq('note_id', noteId)
          .eq('op_id', operationId)
          .maybeSingle();
      if (!_isCurrent(generation, userId) || row == null) return;
      final rawOperation = row['operation_json'];
      if (rawOperation is! Map) return;
      final operation = Map<String, dynamic>.from(rawOperation);
      if (operation['noteId'] != noteId || operation['opId'] != operationId) {
        return;
      }
      onOperationHint?.call(operationId);
      onRemoteOperation?.call(operation);
    } catch (_) {
      _seenOperationIds.remove(operationId);
    }
  }

  Future<void> broadcastOperationHint(String operationId) async {
    final channel = _channel;
    final noteId = _noteId;
    if (channel == null || noteId == null) {
      throw StateError('Notes channel is not joined.');
    }
    if (parseNotesOperationHint({'operationId': operationId}, noteId) == null) {
      throw ArgumentError.value(operationId, 'operationId');
    }
    await channel.sendBroadcastMessage(
      event: 'operation_hint',
      payload: {'operationId': operationId},
    );
  }

  Future<void> publishCursor(NotesCursorAnchor? anchor) async {
    final channel = _channel;
    final userId = _accountId;
    if (channel == null || userId == null) {
      throw StateError('Notes channel is not joined.');
    }
    if (anchor != null &&
        (anchor.bias != 'before' && anchor.bias != 'after' ||
            (anchor.atomId?.length ?? 0) > 256)) {
      throw ArgumentError.value(anchor, 'anchor');
    }
    await channel.sendBroadcastMessage(
      event: 'cursor',
      payload: {'userId': userId, 'anchor': anchor?.toJson()},
    );
  }

  Future<void> leave() => _leave(resetReconnectAttempts: true);

  Future<void> _leave({required bool resetReconnectAttempts}) async {
    ++_generation;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (resetReconnectAttempts) _reconnectAttempts = 0;
    _seenOperationIds.clear();
    final channel = _channel;
    _channel = null;
    _noteId = null;
    _projectId = null;
    _accountId = null;
    if (channel != null) await _client.removeChannel(channel);
    _setState(NotesConnectionState.disconnected);
  }

  bool _isCurrent(int generation, String userId) =>
      generation == _generation &&
      _accountId == userId &&
      _currentUserId == userId;

  void _setState(NotesConnectionState next) {
    state = next;
    onState?.call(next);
  }
}
