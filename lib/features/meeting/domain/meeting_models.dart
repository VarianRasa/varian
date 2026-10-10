import 'dart:collection';

import 'meeting_errors.dart';

enum MeetingStatus {
  idle,
  creating,
  joining,
  connected,
  reconnecting,
  ended,
  error;

  String toWire() => name;
  static MeetingStatus fromWire(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'idle' => MeetingStatus.idle,
        'creating' => MeetingStatus.creating,
        'joining' => MeetingStatus.joining,
        'connected' || 'active' => MeetingStatus.connected,
        'reconnecting' || 'reconnecting_media' => MeetingStatus.reconnecting,
        'ended' => MeetingStatus.ended,
        'error' || 'failed' => MeetingStatus.error,
        _ => MeetingStatus.idle,
      };
}

enum MeetingParticipantRole {
  host,
  publisher,
  viewer;

  String toWire() => name;
  static MeetingParticipantRole fromWire(String? value) => switch (value
      ?.trim()
      .toLowerCase()) {
    'host' || 'owner' => MeetingParticipantRole.host,
    'publisher' || 'editor' || 'commenter' => MeetingParticipantRole.publisher,
    'viewer' => MeetingParticipantRole.viewer,
    _ => MeetingParticipantRole.viewer,
  };
}

enum MeetingTerminationReason {
  ended,
  removed,
  roomRevoked,
  expired,
  providerError;

  String toWire() => switch (this) {
    MeetingTerminationReason.ended => 'ended',
    MeetingTerminationReason.removed => 'removed',
    MeetingTerminationReason.roomRevoked => 'room_revoked',
    MeetingTerminationReason.expired => 'expired',
    MeetingTerminationReason.providerError => 'provider_error',
  };
  static MeetingTerminationReason? fromWire(String? value) =>
      switch (value?.trim().toLowerCase()) {
        null || '' => null,
        'ended' || 'host_ended' => MeetingTerminationReason.ended,
        'removed' || 'participant_removed' => MeetingTerminationReason.removed,
        'room_revoked' || 'roomrevoked' => MeetingTerminationReason.roomRevoked,
        'expired' || 'room_expired' => MeetingTerminationReason.expired,
        'provider_error' ||
        'providererror' => MeetingTerminationReason.providerError,
        _ => MeetingTerminationReason.providerError,
      };
}

enum MeetingMediaEventType {
  connectionChanged,
  localMediaChanged,
  participantJoined,
  participantLeft,
  trackSubscribed,
  trackUnsubscribed,
  activeSpeakerChanged,
  tokenRefreshRequested,
  providerError;

  String toWire() => switch (this) {
    MeetingMediaEventType.connectionChanged => 'connection_changed',
    MeetingMediaEventType.localMediaChanged => 'local_media_changed',
    MeetingMediaEventType.participantJoined => 'participant_joined',
    MeetingMediaEventType.participantLeft => 'participant_left',
    MeetingMediaEventType.trackSubscribed => 'track_subscribed',
    MeetingMediaEventType.trackUnsubscribed => 'track_unsubscribed',
    MeetingMediaEventType.activeSpeakerChanged => 'active_speaker_changed',
    MeetingMediaEventType.tokenRefreshRequested => 'token_refresh_requested',
    MeetingMediaEventType.providerError => 'provider_error',
  };
  static MeetingMediaEventType fromWire(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'connection_changed' ||
        'connection_state_changed' => MeetingMediaEventType.connectionChanged,
        'local_media_changed' ||
        'local_media_state_changed' => MeetingMediaEventType.localMediaChanged,
        'participant_joined' => MeetingMediaEventType.participantJoined,
        'participant_left' => MeetingMediaEventType.participantLeft,
        'track_subscribed' => MeetingMediaEventType.trackSubscribed,
        'track_unsubscribed' => MeetingMediaEventType.trackUnsubscribed,
        'active_speaker_changed' ||
        'active_speaker' => MeetingMediaEventType.activeSpeakerChanged,
        'token_refresh_requested' ||
        'token_refresh' => MeetingMediaEventType.tokenRefreshRequested,
        'provider_error' => MeetingMediaEventType.providerError,
        _ => MeetingMediaEventType.providerError,
      };
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

class _Unset {
  const _Unset();
}

const _unset = _Unset();
String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;
String? _nullableString(Object? value) => value is String ? value : null;
bool _bool(Object? value) => value is bool ? value : false;
bool? _nullableBool(Object? value) => value is bool ? value : null;
Map<String, dynamic>? _jsonMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is String) result[entry.key as String] = entry.value;
  }
  return result;
}

MeetingParticipant? _participant(Object? value) {
  final json = _jsonMap(value);
  return json == null ? null : MeetingParticipant.fromJson(json);
}

DateTime? _date(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

DateTime _requiredDate(Object? value) => _date(value) ?? _epoch;
MeetingTerminationReason? _terminationReason(Object? value) {
  if (value == null) return null;
  return MeetingTerminationReason.fromWire(
    value is String ? value : '__malformed__',
  );
}

MeetingStatus _sessionStatus(
  MeetingStatus current,
  MeetingStatus requested,
  DateTime? endedAt,
) =>
    (current == MeetingStatus.ended || endedAt != null) &&
        requested != MeetingStatus.ended
    ? MeetingStatus.ended
    : requested;
MeetingSession? _session(Object? value) {
  final json = _jsonMap(value);
  return json == null ? null : MeetingSession.fromJson(json);
}

int _limit(Object? value) {
  final n = value is num ? value.toInt() : int.tryParse('$value');
  return n == null || n < 2 || n > 8 ? 8 : n;
}

class MeetingSession {
  const MeetingSession({
    required this.id,
    required this.projectId,
    required this.provider,
    required this.providerRoomName,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.endedAt,
    this.endedReason,
    this.maxParticipants = 8,
  });
  final String id;
  final String projectId;
  final String provider;
  final String providerRoomName;
  final MeetingStatus status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? endedAt;
  final MeetingTerminationReason? endedReason;
  final int maxParticipants;
  bool get isEnded => status == MeetingStatus.ended || endedAt != null;
  bool get isActive => !isEnded;

  factory MeetingSession.fromJson(Map<String, dynamic> json) => MeetingSession(
    id: _string(json['id']),
    projectId: _string(json['project_id'] ?? json['projectId']),
    provider: _string(json['provider'], 'livekit'),
    providerRoomName: _string(
      json['provider_room_name'] ?? json['providerRoomName'],
    ),
    status: MeetingStatus.fromWire(_nullableString(json['status'])),
    createdBy: _string(json['created_by'] ?? json['createdBy']),
    createdAt: _requiredDate(json['created_at'] ?? json['createdAt']),
    endedAt: _date(json['ended_at'] ?? json['endedAt']),
    endedReason: _terminationReason(
      json['ended_reason'] ?? json['endedReason'],
    ),
    maxParticipants: _limit(
      json['max_participants'] ?? json['maxParticipants'],
    ),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'provider': provider,
    'provider_room_name': providerRoomName,
    'status': status.toWire(),
    'created_by': createdBy,
    'created_at': createdAt.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'ended_reason': endedReason?.toWire(),
    'max_participants': maxParticipants,
  };
  MeetingSession copyWith({
    String? id,
    String? projectId,
    String? provider,
    String? providerRoomName,
    MeetingStatus? status,
    String? createdBy,
    DateTime? createdAt,
    Object? endedAt = _unset,
    Object? endedReason = _unset,
    int? maxParticipants,
  }) => MeetingSession(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    provider: provider ?? this.provider,
    providerRoomName: providerRoomName ?? this.providerRoomName,
    status: _sessionStatus(this.status, status ?? this.status, this.endedAt),
    createdBy: createdBy ?? this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    endedAt: identical(endedAt, _unset) ? this.endedAt : endedAt as DateTime?,
    endedReason: identical(endedReason, _unset)
        ? this.endedReason
        : endedReason as MeetingTerminationReason?,
    maxParticipants: maxParticipants ?? this.maxParticipants,
  );
  @override
  bool operator ==(Object other) =>
      other is MeetingSession &&
      id == other.id &&
      projectId == other.projectId &&
      provider == other.provider &&
      providerRoomName == other.providerRoomName &&
      status == other.status &&
      createdBy == other.createdBy &&
      createdAt == other.createdAt &&
      endedAt == other.endedAt &&
      endedReason == other.endedReason &&
      maxParticipants == other.maxParticipants;
  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    provider,
    providerRoomName,
    status,
    createdBy,
    createdAt,
    endedAt,
    endedReason,
    maxParticipants,
  );
}

class MeetingParticipant {
  const MeetingParticipant({
    required this.identity,
    required this.displayName,
    required this.role,
    this.isLocal = false,
    this.microphoneEnabled = false,
    this.cameraEnabled = false,
    this.screenShareEnabled = false,
    this.isSpeaking = false,
  });
  final String identity;
  final String displayName;
  final MeetingParticipantRole role;
  final bool isLocal;
  final bool microphoneEnabled;
  final bool cameraEnabled;
  final bool screenShareEnabled;
  final bool isSpeaking;
  bool get isHost => role == MeetingParticipantRole.host;
  bool get canPublish => role != MeetingParticipantRole.viewer;
  bool get canSubscribe => true;
  bool get canPublishMedia => canPublish;
  bool get canSubscribeMedia => canSubscribe;
  factory MeetingParticipant.fromJson(Map<String, dynamic> json) =>
      MeetingParticipant(
        identity: _string(json['identity']),
        displayName: _string(json['display_name'] ?? json['displayName']),
        role: MeetingParticipantRole.fromWire(_nullableString(json['role'])),
        isLocal: _bool(json['is_local'] ?? json['isLocal']),
        microphoneEnabled: _bool(
          json['microphone_enabled'] ?? json['microphoneEnabled'],
        ),
        cameraEnabled: _bool(json['camera_enabled'] ?? json['cameraEnabled']),
        screenShareEnabled: _bool(
          json['screen_share_enabled'] ?? json['screenShareEnabled'],
        ),
        isSpeaking: _bool(json['is_speaking'] ?? json['isSpeaking']),
      );
  Map<String, dynamic> toJson() => {
    'identity': identity,
    'display_name': displayName,
    'role': role.toWire(),
    'is_local': isLocal,
    'microphone_enabled': microphoneEnabled,
    'camera_enabled': cameraEnabled,
    'screen_share_enabled': screenShareEnabled,
    'is_speaking': isSpeaking,
  };
  MeetingParticipant copyWith({
    String? identity,
    String? displayName,
    MeetingParticipantRole? role,
    bool? isLocal,
    bool? microphoneEnabled,
    bool? cameraEnabled,
    bool? screenShareEnabled,
    bool? isSpeaking,
  }) => MeetingParticipant(
    identity: identity ?? this.identity,
    displayName: displayName ?? this.displayName,
    role: role ?? this.role,
    isLocal: isLocal ?? this.isLocal,
    microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
    cameraEnabled: cameraEnabled ?? this.cameraEnabled,
    screenShareEnabled: screenShareEnabled ?? this.screenShareEnabled,
    isSpeaking: isSpeaking ?? this.isSpeaking,
  );
  @override
  bool operator ==(Object other) =>
      other is MeetingParticipant &&
      identity == other.identity &&
      displayName == other.displayName &&
      role == other.role &&
      isLocal == other.isLocal &&
      microphoneEnabled == other.microphoneEnabled &&
      cameraEnabled == other.cameraEnabled &&
      screenShareEnabled == other.screenShareEnabled &&
      isSpeaking == other.isSpeaking;
  @override
  int get hashCode => Object.hash(
    identity,
    displayName,
    role,
    isLocal,
    microphoneEnabled,
    cameraEnabled,
    screenShareEnabled,
    isSpeaking,
  );
}

class MeetingMediaEvent {
  const MeetingMediaEvent({
    required this.type,
    this.status,
    this.participant,
    this.participantIdentity,
    this.trackKind,
    this.microphoneEnabled,
    this.cameraEnabled,
    this.screenShareEnabled,
    this.isSpeaking,
    this.errorCode,
  });
  final MeetingMediaEventType type;
  final MeetingStatus? status;
  final MeetingParticipant? participant;
  final String? participantIdentity;
  final String? trackKind;
  final bool? microphoneEnabled;
  final bool? cameraEnabled;
  final bool? screenShareEnabled;
  final bool? isSpeaking;
  final MeetingErrorCode? errorCode;
  factory MeetingMediaEvent.connectionChanged(MeetingStatus status) =>
      MeetingMediaEvent(
        type: MeetingMediaEventType.connectionChanged,
        status: status,
      );
  factory MeetingMediaEvent.connectionStateChanged(MeetingStatus status) =>
      MeetingMediaEvent.connectionChanged(status);
  factory MeetingMediaEvent.localMediaChanged({
    bool? microphoneEnabled,
    bool? cameraEnabled,
    bool? screenShareEnabled,
  }) => MeetingMediaEvent(
    type: MeetingMediaEventType.localMediaChanged,
    microphoneEnabled: microphoneEnabled,
    cameraEnabled: cameraEnabled,
    screenShareEnabled: screenShareEnabled,
  );
  factory MeetingMediaEvent.participantJoined(MeetingParticipant participant) =>
      MeetingMediaEvent(
        type: MeetingMediaEventType.participantJoined,
        participant: participant,
      );
  factory MeetingMediaEvent.participantLeft(String identity) =>
      MeetingMediaEvent(
        type: MeetingMediaEventType.participantLeft,
        participantIdentity: identity,
      );
  factory MeetingMediaEvent.trackSubscribed({
    required String identity,
    required String trackKind,
  }) => MeetingMediaEvent(
    type: MeetingMediaEventType.trackSubscribed,
    participantIdentity: identity,
    trackKind: trackKind,
  );
  factory MeetingMediaEvent.trackUnsubscribed({
    required String identity,
    required String trackKind,
  }) => MeetingMediaEvent(
    type: MeetingMediaEventType.trackUnsubscribed,
    participantIdentity: identity,
    trackKind: trackKind,
  );
  factory MeetingMediaEvent.activeSpeakerChanged({
    required String identity,
    required bool isSpeaking,
  }) => MeetingMediaEvent(
    type: MeetingMediaEventType.activeSpeakerChanged,
    participantIdentity: identity,
    isSpeaking: isSpeaking,
  );
  factory MeetingMediaEvent.tokenRefreshRequested() => const MeetingMediaEvent(
    type: MeetingMediaEventType.tokenRefreshRequested,
  );
  factory MeetingMediaEvent.providerError({
    MeetingErrorCode errorCode = MeetingErrorCode.providerUnavailable,
  }) => MeetingMediaEvent(
    type: MeetingMediaEventType.providerError,
    errorCode: errorCode,
  );
  factory MeetingMediaEvent.fromJson(Map<String, dynamic> json) =>
      MeetingMediaEvent(
        type: MeetingMediaEventType.fromWire(_nullableString(json['type'])),
        status: json['status'] == null
            ? null
            : MeetingStatus.fromWire(_nullableString(json['status'])),
        participant: _participant(json['participant']),
        participantIdentity: _nullableString(
          json['participant_identity'] ?? json['participantIdentity'],
        ),
        trackKind: _nullableString(json['track_kind'] ?? json['trackKind']),
        microphoneEnabled: _nullableBool(
          json['microphone_enabled'] ?? json['microphoneEnabled'],
        ),
        cameraEnabled: _nullableBool(
          json['camera_enabled'] ?? json['cameraEnabled'],
        ),
        screenShareEnabled: _nullableBool(
          json['screen_share_enabled'] ?? json['screenShareEnabled'],
        ),
        isSpeaking: _nullableBool(json['is_speaking'] ?? json['isSpeaking']),
        errorCode: json['error_code'] == null && json['errorCode'] == null
            ? null
            : MeetingErrorCodeWire.fromWire(
                _nullableString(json['error_code'] ?? json['errorCode']),
              ),
      );
  Map<String, dynamic> toJson() => {
    'type': type.toWire(),
    'status': status?.toWire(),
    'participant': participant?.toJson(),
    'participant_identity': participantIdentity,
    'track_kind': trackKind,
    'microphone_enabled': microphoneEnabled,
    'camera_enabled': cameraEnabled,
    'screen_share_enabled': screenShareEnabled,
    'is_speaking': isSpeaking,
    'error_code': errorCode?.toWire(),
  };
  MeetingMediaEvent copyWith({
    MeetingMediaEventType? type,
    Object? status = _unset,
    Object? participant = _unset,
    Object? participantIdentity = _unset,
    Object? trackKind = _unset,
    Object? microphoneEnabled = _unset,
    Object? cameraEnabled = _unset,
    Object? screenShareEnabled = _unset,
    Object? isSpeaking = _unset,
    Object? errorCode = _unset,
  }) => MeetingMediaEvent(
    type: type ?? this.type,
    status: identical(status, _unset) ? this.status : status as MeetingStatus?,
    participant: identical(participant, _unset)
        ? this.participant
        : participant as MeetingParticipant?,
    participantIdentity: identical(participantIdentity, _unset)
        ? this.participantIdentity
        : participantIdentity as String?,
    trackKind: identical(trackKind, _unset)
        ? this.trackKind
        : trackKind as String?,
    microphoneEnabled: identical(microphoneEnabled, _unset)
        ? this.microphoneEnabled
        : microphoneEnabled as bool?,
    cameraEnabled: identical(cameraEnabled, _unset)
        ? this.cameraEnabled
        : cameraEnabled as bool?,
    screenShareEnabled: identical(screenShareEnabled, _unset)
        ? this.screenShareEnabled
        : screenShareEnabled as bool?,
    isSpeaking: identical(isSpeaking, _unset)
        ? this.isSpeaking
        : isSpeaking as bool?,
    errorCode: identical(errorCode, _unset)
        ? this.errorCode
        : errorCode as MeetingErrorCode?,
  );
  @override
  bool operator ==(Object other) =>
      other is MeetingMediaEvent &&
      type == other.type &&
      status == other.status &&
      participant == other.participant &&
      participantIdentity == other.participantIdentity &&
      trackKind == other.trackKind &&
      microphoneEnabled == other.microphoneEnabled &&
      cameraEnabled == other.cameraEnabled &&
      screenShareEnabled == other.screenShareEnabled &&
      isSpeaking == other.isSpeaking &&
      errorCode == other.errorCode;
  @override
  int get hashCode => Object.hash(
    type,
    status,
    participant,
    participantIdentity,
    trackKind,
    microphoneEnabled,
    cameraEnabled,
    screenShareEnabled,
    isSpeaking,
    errorCode,
  );
}

class MeetingState {
  MeetingState({
    required this.projectId,
    this.meetingId,
    this.session,
    Map<String, MeetingParticipant>? participants,
    this.localMicrophoneEnabled = false,
    this.localCameraEnabled = false,
    this.localScreenShareEnabled = false,
    this.status = MeetingStatus.idle,
    this.errorCode,
    this.errorMessage,
    this.isHost = false,
    this.canPublish = false,
    this.terminationReason,
    this.actionInFlight = false,
  }) : participants = UnmodifiableMapView(
         Map<String, MeetingParticipant>.unmodifiable(participants ?? const {}),
       );
  final String projectId;
  final String? meetingId;
  final MeetingSession? session;
  final Map<String, MeetingParticipant> participants;
  final bool localMicrophoneEnabled;
  final bool localCameraEnabled;
  final bool localScreenShareEnabled;
  final MeetingStatus status;
  final MeetingErrorCode? errorCode;
  final String? errorMessage;
  final bool isHost;
  final bool canPublish;
  final MeetingTerminationReason? terminationReason;
  final bool actionInFlight;
  factory MeetingState.initial({
    required String projectId,
    String? meetingId,
  }) => MeetingState(projectId: projectId, meetingId: meetingId);
  factory MeetingState.fromJson(Map<String, dynamic> json) {
    final parsed = <String, MeetingParticipant>{};
    final raw = json['participants'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is String && entry.value is Map) {
          parsed['${entry.key}'] = MeetingParticipant.fromJson(
            _jsonMap(entry.value)!,
          );
        }
      }
    }
    return MeetingState(
      projectId: _string(json['project_id'] ?? json['projectId']),
      meetingId: _nullableString(json['meeting_id'] ?? json['meetingId']),
      session: _session(json['session']),
      participants: parsed,
      localMicrophoneEnabled: _bool(
        json['local_microphone_enabled'] ?? json['localMicrophoneEnabled'],
      ),
      localCameraEnabled: _bool(
        json['local_camera_enabled'] ?? json['localCameraEnabled'],
      ),
      localScreenShareEnabled: _bool(
        json['local_screen_share_enabled'] ?? json['localScreenShareEnabled'],
      ),
      status: MeetingStatus.fromWire(_nullableString(json['status'])),
      errorCode: json['error_code'] == null && json['errorCode'] == null
          ? null
          : MeetingErrorCodeWire.fromWire(
              _nullableString(json['error_code'] ?? json['errorCode']),
            ),
      errorMessage: _nullableString(
        json['error_message'] ?? json['errorMessage'],
      ),
      isHost: _bool(json['is_host'] ?? json['isHost']),
      canPublish: _bool(json['can_publish'] ?? json['canPublish']),
      terminationReason: _terminationReason(
        json['termination_reason'] ?? json['terminationReason'],
      ),
      actionInFlight: _bool(json['action_in_flight'] ?? json['actionInFlight']),
    );
  }
  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'meeting_id': meetingId,
    'session': session?.toJson(),
    'participants': {
      for (final entry in participants.entries) entry.key: entry.value.toJson(),
    },
    'local_microphone_enabled': localMicrophoneEnabled,
    'local_camera_enabled': localCameraEnabled,
    'local_screen_share_enabled': localScreenShareEnabled,
    'status': status.toWire(),
    'error_code': errorCode?.toWire(),
    'error_message': errorMessage,
    'is_host': isHost,
    'can_publish': canPublish,
    'termination_reason': terminationReason?.toWire(),
    'action_in_flight': actionInFlight,
  };
  MeetingState copyWith({
    String? projectId,
    Object? meetingId = _unset,
    Object? session = _unset,
    Map<String, MeetingParticipant>? participants,
    bool? localMicrophoneEnabled,
    bool? localCameraEnabled,
    bool? localScreenShareEnabled,
    MeetingStatus? status,
    Object? errorCode = _unset,
    Object? errorMessage = _unset,
    bool? isHost,
    bool? canPublish,
    Object? terminationReason = _unset,
    bool? actionInFlight,
  }) {
    final requested = status ?? this.status;
    final next =
        this.status == MeetingStatus.ended && requested != MeetingStatus.ended
        ? MeetingStatus.ended
        : requested;
    return MeetingState(
      projectId: projectId ?? this.projectId,
      meetingId: identical(meetingId, _unset)
          ? this.meetingId
          : meetingId as String?,
      session: identical(session, _unset)
          ? this.session
          : session as MeetingSession?,
      participants: participants ?? this.participants,
      localMicrophoneEnabled:
          localMicrophoneEnabled ?? this.localMicrophoneEnabled,
      localCameraEnabled: localCameraEnabled ?? this.localCameraEnabled,
      localScreenShareEnabled:
          localScreenShareEnabled ?? this.localScreenShareEnabled,
      status: next,
      errorCode: identical(errorCode, _unset)
          ? this.errorCode
          : errorCode as MeetingErrorCode?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      isHost: isHost ?? this.isHost,
      canPublish: canPublish ?? this.canPublish,
      terminationReason: identical(terminationReason, _unset)
          ? this.terminationReason
          : terminationReason as MeetingTerminationReason?,
      actionInFlight: actionInFlight ?? this.actionInFlight,
    );
  }
}
