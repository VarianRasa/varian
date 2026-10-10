import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/meeting_errors.dart';
import '../domain/meeting_models.dart';
import 'meeting_media_credentials.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
const _meetingReasons = {
  'host_ended',
  'room_revoked',
  'expired',
  'admin_ended',
};

class MeetingFunctionResponse {
  const MeetingFunctionResponse({required this.status, this.data});

  final int status;
  final Object? data;
}

typedef MeetingRpc =
    Future<Object?> Function(String name, Map<String, dynamic> params);
typedef MeetingFunctionInvoker =
    Future<MeetingFunctionResponse> Function(
      String name,
      Map<String, dynamic> body,
    );
typedef MeetingRows = Stream<Map<String, dynamic>> Function(String meetingId);
typedef MeetingParticipantRemover =
    Future<void> Function(String meetingId, String identity);

class MeetingRepositoryException implements Exception {
  const MeetingRepositoryException(this.code);

  final MeetingErrorCode code;

  String get message => MeetingErrorMessage.forCode(code);

  @override
  String toString() => 'MeetingRepositoryException: $message';
}

class MeetingRepository {
  MeetingRepository(
    this._client, {
    this._rpc,
    this._invoke,
    this._rows,
    this._currentUserId,
    this._removeParticipant,
  });

  final SupabaseClient? _client;
  final MeetingRpc? _rpc;
  final MeetingFunctionInvoker? _invoke;
  final MeetingRows? _rows;
  final String? _currentUserId;
  final MeetingParticipantRemover? _removeParticipant;
  final _watchSubscriptions = <StreamSubscription<dynamic>>{};
  final _watchControllers = <StreamController<MeetingSession>>{};
  bool _disposed = false;

  Future<MeetingSession> createMeeting({
    required String projectId,
    int maxParticipants = 8,
  }) async {
    if (!_isProjectId(projectId) ||
        maxParticipants < 2 ||
        maxParticipants > 8) {
      throw const MeetingRepositoryException(MeetingErrorCode.unavailable);
    }
    final response = await _callRpc('create_meeting_session', {
      'p_project_id': projectId,
      'p_max_participants': maxParticipants,
    });
    return _parseSession(response, expectedProjectId: projectId);
  }

  Future<MeetingSession> joinMeeting({required String meetingId}) async {
    _requireMeetingId(meetingId);
    final response = await _callRpc('join_meeting_session', {
      'p_meeting_id': meetingId,
    });
    return _parseSession(response, expectedMeetingId: meetingId);
  }

  Future<MeetingMediaCredentials> requestToken({
    required String meetingId,
  }) async {
    _requireMeetingId(meetingId);
    final response = await _callFunction('meeting-token', {
      'meetingId': meetingId,
    });
    if (response.status < 200 || response.status >= 300) {
      throw _functionError(response.data, response.status);
    }
    final currentUserId = _currentUserId ?? _client?.auth.currentUser?.id;
    return _parseToken(response.data, expectedIdentity: currentUserId);
  }

  Future<MeetingSession> endMeeting({
    required String meetingId,
    String reason = 'host_ended',
  }) async {
    _requireMeetingId(meetingId);
    if (!_meetingReasons.contains(reason)) {
      throw const MeetingRepositoryException(MeetingErrorCode.unavailable);
    }
    final response = await _callRpc('end_meeting_session', {
      'p_meeting_id': meetingId,
      'p_reason': reason,
    });
    return _parseSession(response, expectedMeetingId: meetingId);
  }

  Future<void> removeParticipant({
    required String meetingId,
    required String identity,
  }) async {
    _requireMeetingId(meetingId);
    if (!_uuidPattern.hasMatch(identity)) {
      throw const MeetingRepositoryException(MeetingErrorCode.unavailable);
    }
    try {
      final remover = _removeParticipant;
      if (remover != null) {
        await remover(meetingId, identity);
        return;
      }
      final response = await _callFunction('meeting-remove-participant', {
        'meetingId': meetingId,
        'identity': identity,
      });
      if (response.status < 200 || response.status >= 300) {
        throw _functionError(response.data, response.status);
      }
      final row = _singleMap(response.data);
      if (row == null || row['removed'] is! bool) {
        throw const MeetingRepositoryException(
          MeetingErrorCode.providerUnavailable,
        );
      }
    } on MeetingRepositoryException {
      rethrow;
    } catch (_) {
      throw const MeetingRepositoryException(
        MeetingErrorCode.providerUnavailable,
      );
    }
  }

  Stream<MeetingSession> watchMeeting(String meetingId) {
    if (_disposed || !_isMeetingId(meetingId)) {
      return Stream<MeetingSession>.error(
        const MeetingRepositoryException(MeetingErrorCode.unavailable),
      );
    }

    final controller = StreamController<MeetingSession>();
    _watchControllers.add(controller);
    StreamSubscription<dynamic>? subscription;
    var terminal = false;
    var errorForwarded = false;

    Future<void> stop() async {
      final current = subscription;
      subscription = null;
      if (current != null) {
        await current.cancel();
        _watchSubscriptions.remove(current);
      }
      _watchControllers.remove(controller);
      if (!controller.isClosed) await controller.close();
    }

    controller.onListen = () {
      try {
        final source = _rows != null
            ? _rows(meetingId)
            : _watchRowsFromClient(meetingId);
        final current = source.listen(
          (row) {
            if (terminal) return;
            try {
              final session = _parseSession(row, expectedMeetingId: meetingId);
              controller.add(session);
              if (session.isEnded) {
                terminal = true;
                unawaited(stop());
              }
            } on MeetingRepositoryException {
              // Realtime payloads are untrusted; invalid rows are ignored.
            }
          },
          onError: (_, _) {
            if (terminal || errorForwarded) return;
            errorForwarded = true;
            if (!controller.isClosed) {
              controller.addError(
                const MeetingRepositoryException(
                  MeetingErrorCode.providerUnavailable,
                ),
              );
            }
            unawaited(stop());
          },
          onDone: () {
            if (!terminal) unawaited(stop());
          },
        );
        subscription = current;
        _watchSubscriptions.add(current);
      } catch (error) {
        unawaited(() async {
          if (!controller.isClosed) {
            controller.addError(
              error is MeetingRepositoryException
                  ? error
                  : const MeetingRepositoryException(
                      MeetingErrorCode.providerUnavailable,
                    ),
            );
          }
          await stop();
        }());
      }
    };
    controller.onCancel = () async {
      final current = subscription;
      subscription = null;
      if (current != null) {
        await current.cancel();
        _watchSubscriptions.remove(current);
      }
      _watchControllers.remove(controller);
    };
    return controller.stream;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _watchSubscriptions,
    );
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    _watchSubscriptions.clear();
    final controllers = List<StreamController<MeetingSession>>.from(
      _watchControllers,
    );
    for (final controller in controllers) {
      if (!controller.isClosed) await controller.close();
    }
    _watchControllers.clear();
  }

  Future<Object?> _callRpc(String name, Map<String, dynamic> params) async {
    try {
      if (_rpc != null) return await _rpc(name, params);
      final client = _client;
      if (client == null) _throwUnavailable();
      return await client.rpc(name, params: params);
    } catch (error) {
      if (error is MeetingRepositoryException) rethrow;
      throw _mapBackendError(error);
    }
  }

  Future<MeetingFunctionResponse> _callFunction(
    String name,
    Map<String, dynamic> body,
  ) async {
    try {
      if (_invoke != null) return await _invoke(name, body);
      final client = _client;
      if (client == null) _throwUnavailable();
      final response = await client.functions.invoke(name, body: body);
      return MeetingFunctionResponse(
        status: response.status,
        data: response.data,
      );
    } catch (error) {
      if (error is MeetingRepositoryException) rethrow;
      throw _mapFunctionException(error);
    }
  }

  Stream<Map<String, dynamic>> _watchRowsFromClient(String meetingId) {
    final client = _client;
    if (client == null) _throwUnavailable();
    final channel = client.channel('public:meeting_sessions');
    final controller = StreamController<Map<String, dynamic>>();

    void failChannel() {
      if (controller.isClosed) return;
      controller.addError(
        const MeetingRepositoryException(MeetingErrorCode.providerUnavailable),
      );
      unawaited(channel.unsubscribe());
      unawaited(controller.close());
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'meeting_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: meetingId,
          ),
          callback: (payload) {
            final record = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            if (!controller.isClosed) controller.add(record);
          },
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            failChannel();
          }
        });
    controller.onCancel = () async {
      await channel.unsubscribe();
    };
    return controller.stream;
  }

  Never _throwUnavailable() {
    throw const MeetingRepositoryException(MeetingErrorCode.unavailable);
  }

  static bool _isProjectId(String value) =>
      value.trim().isNotEmpty &&
      !RegExp(r'[\u0000-\u001f\u007f]').hasMatch(value);

  static bool _isMeetingId(String value) => _uuidPattern.hasMatch(value.trim());

  static void _requireMeetingId(String value) {
    if (!_isMeetingId(value)) _throwInvalid();
  }

  static MeetingSession _parseSession(
    Object? value, {
    String? expectedProjectId,
    String? expectedMeetingId,
  }) {
    final row = _singleMap(value);
    if (row == null) _throwInvalid();
    final id = row['id'];
    final projectId = row['project_id'];
    final provider = row['provider'];
    final room = row['provider_room_name'];
    final status = row['status'];
    final createdBy = row['created_by'];
    final createdAt = row['created_at'];
    final endedAt = row['ended_at'];
    final endedReason = row['ended_reason'];
    final maxParticipants = row['max_participants'];
    final parsedDate = createdAt is String
        ? DateTime.tryParse(createdAt)
        : null;
    final parsedEndedAt = endedAt is String ? DateTime.tryParse(endedAt) : null;
    final ended = status == 'ended';
    if (id is! String ||
        !_isMeetingId(id) ||
        projectId is! String ||
        projectId.trim().isEmpty ||
        provider != 'livekit' ||
        room is! String ||
        room.trim().isEmpty ||
        status is! String ||
        (status != 'active' && status != 'ended') ||
        createdBy is! String ||
        !_isMeetingId(createdBy) ||
        parsedDate == null ||
        maxParticipants is! int ||
        maxParticipants < 2 ||
        maxParticipants > 8 ||
        (ended &&
            (parsedEndedAt == null ||
                endedReason is! String ||
                !_meetingReasons.contains(endedReason))) ||
        (!ended && (endedAt != null || endedReason != null)) ||
        (expectedProjectId != null && projectId != expectedProjectId) ||
        (expectedMeetingId != null &&
            id.toLowerCase() != expectedMeetingId.toLowerCase())) {
      _throwInvalid();
    }
    return MeetingSession.fromJson(row);
  }

  static MeetingMediaCredentials _parseToken(
    Object? value, {
    String? expectedIdentity,
  }) {
    final row = _singleMap(value);
    if (row == null) _throwInvalid();
    final token = row['token'];
    final serverUrl = row['serverUrl'];
    final expiresAt = row['expiresAt'];
    final identity = row['identity'];
    final parsedExpiry = expiresAt is String
        ? DateTime.tryParse(expiresAt)
        : null;
    Uri? parsedUrl;
    if (serverUrl is String) parsedUrl = Uri.tryParse(serverUrl);
    final exactTokenShape =
        row.length == 4 &&
        row.keys.toSet().containsAll({
          'token',
          'serverUrl',
          'expiresAt',
          'identity',
        });
    if (!exactTokenShape ||
        token is! String ||
        token.trim().isEmpty ||
        serverUrl is! String ||
        parsedUrl == null ||
        parsedUrl.host.isEmpty ||
        (parsedUrl.scheme != 'wss' && parsedUrl.scheme != 'https') ||
        parsedUrl.userInfo.isNotEmpty ||
        parsedUrl.hasQuery ||
        parsedUrl.hasFragment ||
        parsedExpiry == null ||
        !parsedExpiry.toUtc().isAfter(DateTime.now().toUtc()) ||
        identity is! String ||
        !_uuidPattern.hasMatch(identity) ||
        (expectedIdentity != null &&
            identity.toLowerCase() != expectedIdentity.toLowerCase())) {
      _throwInvalid();
    }
    return MeetingMediaCredentials.fromProviderValues(
      token: token,
      serverUrl: serverUrl,
      expiresAt: parsedExpiry.toUtc(),
      identity: identity,
    );
  }

  static Map<String, dynamic>? _singleMap(Object? value) {
    if (value is Map) return _stringMap(value);
    if (value is List && value.length == 1 && value.first is Map) {
      return _stringMap(value.first as Map);
    }
    return null;
  }

  static Map<String, dynamic> _stringMap(Map value) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) return <String, dynamic>{};
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static Never _throwInvalid() {
    throw const MeetingRepositoryException(MeetingErrorCode.unavailable);
  }

  static MeetingRepositoryException _functionError(Object? data, int status) {
    return MeetingRepositoryException(
      _mapWireCode(_structuredErrorCode(data), status),
    );
  }

  static MeetingRepositoryException _mapBackendError(Object error) {
    return MeetingRepositoryException(_mapWireCode(_errorCode(error), null));
  }

  static MeetingRepositoryException _mapFunctionException(Object error) {
    final details = _property(error, 'details');
    final status = _property(error, 'status');
    final code = _structuredErrorCode(details) ?? _errorCode(error);
    if (code == null && status == null) {
      return const MeetingRepositoryException(
        MeetingErrorCode.providerUnavailable,
      );
    }
    return MeetingRepositoryException(
      _mapWireCode(code, status is int ? status : null),
    );
  }

  static Object? _property(Object value, String name) {
    try {
      final dynamic dynamicValue = value;
      if (name == 'details') return dynamicValue.details;
      if (name == 'status') return dynamicValue.status;
      return dynamicValue.code;
    } catch (_) {
      return null;
    }
  }

  static String? _structuredErrorCode(Object? value) {
    if (value is! Map) return null;
    final nested = value['error'];
    final source = nested is Map ? nested : value;
    final code = source['code'];
    return code is String ? code : null;
  }

  static String? _errorCode(Object error) {
    final value = _property(error, 'code');
    return value is String ? value : null;
  }

  static MeetingErrorCode _mapWireCode(String? value, int? status) {
    if (value == null && status != null && status >= 500) {
      return MeetingErrorCode.providerUnavailable;
    }
    switch (value?.toLowerCase()) {
      case 'p0003':
      case 'ended':
        return MeetingErrorCode.ended;
      case '42501':
      case 'authorization_error':
      case 'permission_denied':
      case 'unauthorized':
        return MeetingErrorCode.authorizationError;
      case 'capacity_full':
        return MeetingErrorCode.capacityFull;
      case 'provider_unavailable':
      case 'provider_error':
        return MeetingErrorCode.providerUnavailable;
      case 'removed':
        return MeetingErrorCode.removed;
    }
    switch (status) {
      case 401:
      case 403:
        return MeetingErrorCode.authorizationError;
      case 409:
        return MeetingErrorCode.capacityFull;
      case 410:
        return MeetingErrorCode.ended;
      case 503:
        return MeetingErrorCode.providerUnavailable;
      default:
        return MeetingErrorCode.unavailable;
    }
  }
}
