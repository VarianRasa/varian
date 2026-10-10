import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/meeting/data/meeting_media_credentials.dart';
import 'package:varian/features/meeting/domain/meeting_errors.dart';
import 'package:varian/features/meeting/domain/meeting_models.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 15, 10, 20, 30);

  group('meeting wire enums', () {
    test('parse and serialize known values deterministically', () {
      expect(
        MeetingStatus.fromWire('reconnecting'),
        MeetingStatus.reconnecting,
      );
      expect(MeetingStatus.connected.toWire(), 'connected');
      expect(
        MeetingParticipantRole.fromWire('host'),
        MeetingParticipantRole.host,
      );
      expect(
        MeetingTerminationReason.fromWire('room_revoked'),
        MeetingTerminationReason.roomRevoked,
      );
      expect(MeetingTerminationReason.roomRevoked.toWire(), 'room_revoked');
    });

    test('malformed values use controlled fallbacks', () {
      expect(MeetingStatus.fromWire('what'), MeetingStatus.idle);
      expect(
        MeetingParticipantRole.fromWire(null),
        MeetingParticipantRole.viewer,
      );
      expect(
        MeetingTerminationReason.fromWire('what'),
        MeetingTerminationReason.providerError,
      );
    });
  });

  test('session JSON round-trip preserves durable fields', () {
    final session = MeetingSession(
      id: 'meeting-1',
      projectId: 'project-1',
      provider: 'livekit',
      providerRoomName: 'room-random',
      status: MeetingStatus.connected,
      createdBy: 'user-1',
      createdAt: createdAt,
      endedAt: null,
      endedReason: null,
      maxParticipants: 8,
    );
    final restored = MeetingSession.fromJson(session.toJson());
    expect(restored, session);
    expect(restored.toJson()['created_at'], createdAt.toIso8601String());
  });

  test('session malformed wire data has deterministic safe defaults', () {
    final session = MeetingSession.fromJson({
      'id': 42,
      'project_id': null,
      'provider': null,
      'provider_room_name': null,
      'status': Object(),
      'created_by': null,
      'created_at': 'not-a-date',
      'ended_at': 'also-not-a-date',
      'ended_reason': 1,
      'max_participants': 'not-a-number',
    });
    expect(session.id, '');
    expect(session.projectId, '');
    expect(session.provider, 'livekit');
    expect(session.status, MeetingStatus.idle);
    expect(
      session.createdAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    expect(session.endedAt, isNull);
    expect(session.endedReason, MeetingTerminationReason.providerError);
    expect(session.maxParticipants, 8);
  });

  test('participant role derives publishing and subscription capabilities', () {
    const viewer = MeetingParticipant(
      identity: 'viewer-1',
      displayName: 'Viewer',
      role: MeetingParticipantRole.viewer,
    );
    final host = viewer.copyWith(
      role: MeetingParticipantRole.host,
      isLocal: true,
    );
    expect(viewer.canPublish, isFalse);
    expect(viewer.canSubscribe, isTrue);
    expect(viewer.isHost, isFalse);
    expect(host.canPublish, isTrue);
    expect(host.isHost, isTrue);
    expect(MeetingParticipant.fromJson(viewer.toJson()), viewer);
  });

  test(
    'media credentials stay boundary-only and are not state serializable',
    () {
      final credentials = MeetingMediaCredentials.fromProviderValues(
        token: 'short-lived',
        serverUrl: 'https://video.example',
        expiresAt: createdAt,
        identity: 'u1',
      );
      expect(credentials.identity, 'u1');
      final captured = <String>[];
      credentials.use<void>(({
        required String serverUrl,
        required String token,
      }) async {
        captured
          ..add(serverUrl)
          ..add(token);
      });
      expect(captured, ['https://video.example', 'short-lived']);
      expect(
        MeetingState.initial(projectId: 'project-1').toJson(),
        isNot(contains('token')),
      );
    },
  );

  test(
    'media events expose app-level data without provider negotiation details',
    () {
      const participant = MeetingParticipant(
        identity: 'u2',
        displayName: 'Guest',
        role: MeetingParticipantRole.publisher,
      );
      final event = MeetingMediaEvent.participantJoined(participant);
      expect(event.type, MeetingMediaEventType.participantJoined);
      expect(event.participant, participant);
      expect(event.toJson().containsKey('sdp'), isFalse);
      expect(event.toJson().containsKey('ice'), isFalse);
      expect(
        MeetingMediaEvent.connectionChanged(MeetingStatus.connected).status,
        MeetingStatus.connected,
      );
    },
  );

  test('state is immutable and terminal ended cannot return to connected', () {
    final initial = MeetingState.initial(
      projectId: 'project-1',
      meetingId: 'meeting-1',
    );
    expect(initial.status, MeetingStatus.idle);
    expect(initial.participants, isEmpty);
    final connected = initial.copyWith(
      status: MeetingStatus.connected,
      isHost: true,
    );
    expect(connected.status, MeetingStatus.connected);
    expect(connected.isHost, isTrue);
    final ended = connected.copyWith(
      status: MeetingStatus.ended,
      errorCode: MeetingErrorCode.ended,
    );
    final attemptedRevival = ended.copyWith(status: MeetingStatus.connected);
    expect(attemptedRevival.status, MeetingStatus.ended);
    expect(attemptedRevival.errorCode, MeetingErrorCode.ended);
    expect(
      ended
          .copyWith(
            participants: {
              'u': const MeetingParticipant(
                identity: 'u',
                displayName: 'U',
                role: MeetingParticipantRole.viewer,
              ),
            },
          )
          .participants,
      hasLength(1),
    );
  });

  test('state actionInFlight survives JSON round-trip and copyWith', () {
    final state = MeetingState(
      projectId: 'project-1',
      status: MeetingStatus.connected,
      actionInFlight: true,
    );

    final restored = MeetingState.fromJson(state.toJson());
    expect(restored.actionInFlight, isTrue);
    expect(state.copyWith(actionInFlight: false).actionInFlight, isFalse);
  });

  test('error mapping is user-facing and never leaks provider details', () {
    expect(
      MeetingErrorMessage.forCode(MeetingErrorCode.ended),
      'Meeting sudah diakhiri oleh host.',
    );
    expect(
      MeetingErrorMessage.forCode(MeetingErrorCode.removed),
      'Anda dikeluarkan dari meeting.',
    );
    expect(
      MeetingErrorMessage.forCode(MeetingErrorCode.providerUnavailable),
      contains('tidak tersedia'),
    );
  });

  test('ended session cannot be revived by copyWith', () {
    final ended = MeetingSession(
      id: 'm',
      projectId: 'p',
      provider: 'livekit',
      providerRoomName: 'r',
      status: MeetingStatus.ended,
      createdBy: 'u',
      createdAt: createdAt,
      endedAt: createdAt,
      endedReason: MeetingTerminationReason.ended,
    );
    expect(
      ended.copyWith(status: MeetingStatus.connected).status,
      MeetingStatus.ended,
    );
    expect(ended.copyWith(status: MeetingStatus.connected).isEnded, isTrue);
  });

  test('token refresh event is a signal and malformed JSON is safe', () {
    final refresh = MeetingMediaEvent.tokenRefreshRequested();
    expect(refresh.toJson().containsKey('token'), isFalse);
    final participant = MeetingParticipant.fromJson({
      'identity': 1,
      'display_name': <String>[],
      'role': 2,
      'is_local': 'yes',
      'microphone_enabled': 1,
      'camera_enabled': <int>[],
      'screen_share_enabled': Object(),
      'is_speaking': 'no',
    });
    expect(participant.identity, '');
    expect(participant.role, MeetingParticipantRole.viewer);
    expect(participant.isLocal, isFalse);
    final event = MeetingMediaEvent.fromJson({
      'type': 1,
      'status': Object(),
      'participant': <int>[1],
      'participant_identity': 4,
      'track_kind': Object(),
      'microphone_enabled': 'on',
      'camera_enabled': 1,
      'screen_share_enabled': <String>[],
      'is_speaking': Object(),
      'error_code': 9,
      'error_message': 8,
    });
    expect(event.type, MeetingMediaEventType.providerError);
    expect(event.status, MeetingStatus.idle);
    expect(event.participant, isNull);
    expect(event.microphoneEnabled, isNull);
    expect(event.errorCode, MeetingErrorCode.unavailable);
    final state = MeetingState.fromJson({
      'project_id': 9,
      'meeting_id': Object(),
      'session': <String>['bad'],
      'participants': {
        1: <String, dynamic>{'identity': 'ignored'},
      },
      'local_microphone_enabled': 'on',
      'local_camera_enabled': 1,
      'local_screen_share_enabled': Object(),
      'status': 3,
      'error_code': Object(),
      'error_message': 4,
      'is_host': 'yes',
    });
    expect(state.projectId, '');
    expect(state.meetingId, isNull);
    expect(state.session, isNull);
    expect(state.participants, isEmpty);
    expect(state.status, MeetingStatus.idle);
    expect(state.isHost, isFalse);
  });
}
