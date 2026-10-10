import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/meeting/data/meeting_configuration.dart';
import 'package:varian/features/meeting/data/meeting_media_credentials.dart';
import 'package:varian/features/meeting/data/meeting_media_port.dart';
import 'package:varian/features/meeting/data/meeting_repository.dart';
import 'package:varian/features/meeting/domain/meeting_errors.dart';
import 'package:varian/features/meeting/domain/meeting_models.dart';
import 'package:varian/features/meeting/state/meeting_controller.dart';

const projectId = 'project-1';
const meetingId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const creatorId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  late FakeRepository repository;
  late FakeMedia media;
  late MeetingController controller;

  setUp(() {
    repository = FakeRepository();
    media = FakeMedia();
    controller = MeetingController(
      projectId: projectId,
      repository: repository,
      media: media,
      configuration: enabledConfiguration,
    );
  });

  tearDown(() async {
    await controller.disposeAsync();
  });

  test('start creates, tokenizes, connects, then applies defaults', () async {
    final result = await controller.startMeeting(maxParticipants: 4);

    expect(result.id, meetingId);
    expect(controller.state.status, MeetingStatus.connected);
    expect(controller.state.isHost, isTrue);
    expect(repository.createCalls, 1);
    expect(repository.tokenCalls, 1);
    expect(media.calls, <String>[
      'connect',
      'microphone:false',
      'camera:false',
      'screen:false',
    ]);
  });

  test('concurrent duplicate joins share one repository operation', () async {
    repository.holdJoin = true;
    final first = controller.join(meetingId: meetingId);
    final second = controller.join(meetingId: meetingId);
    expect(identical(first, second), isTrue);

    repository.completeJoin();
    await Future.wait([first, second]);
    expect(repository.joinCalls, 1);
    expect(controller.state.meetingId, meetingId);
  });

  test('viewer cannot publish or toggle local media', () async {
    controller = MeetingController(
      projectId: projectId,
      repository: repository,
      media: media,
      configuration: enabledConfiguration,
    );
    media.canPublishValue = false;
    await controller.join(meetingId: meetingId);

    await controller.toggleMicrophone();
    await controller.toggleCamera();
    await controller.toggleScreenShare();

    expect(media.controlCalls, isEmpty);
    expect(controller.state.canPublish, isFalse);
    expect(controller.state.isHost, isTrue);
  });

  test(
    'toggles update observable local state after provider command',
    () async {
      await controller.startMeeting();
      await controller.toggleMicrophone();
      await controller.toggleCamera();
      await controller.toggleScreenShare();

      expect(media.controlCalls.skip(3), <String>[
        'microphone:true',
        'camera:true',
        'screen:true',
      ]);
      expect(controller.state.localMicrophoneEnabled, isTrue);
      expect(controller.state.localCameraEnabled, isTrue);
      expect(controller.state.localScreenShareEnabled, isTrue);
    },
  );

  test(
    'failed media connect clears session and permits deliberate retry',
    () async {
      media.throwConnect = true;
      await expectLater(
        controller.startMeeting(),
        throwsA(isA<MeetingControllerException>()),
      );
      expect(controller.state.session, isNull);
      expect(controller.state.status, MeetingStatus.error);
      expect(repository.watchCancels, 1);
      expect(media.disconnectCalls, 1);

      media.throwConnect = false;
      await controller.startMeeting();
      expect(repository.createCalls, 2);
      expect(controller.state.status, MeetingStatus.connected);
    },
  );

  test(
    'leave cancels the durable session watcher before resetting state',
    () async {
      await controller.startMeeting();
      expect(repository.watchCalls, 1);
      await controller.leave();
      expect(repository.watchCancels, 1);
      repository.emit(endedSession);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, MeetingStatus.idle);
    },
  );

  test('control failure is nonterminal and preserves the meeting', () async {
    await controller.startMeeting();
    media.throwControl = true;
    await controller.toggleCamera();
    expect(controller.state.status, MeetingStatus.connected);
    expect(controller.state.session, isNotNull);
    expect(controller.state.errorCode, MeetingErrorCode.providerUnavailable);
    expect(media.disconnectCalls, 0);
  });

  test(
    'reconnect preserves session and participants, provider error clears them',
    () async {
      await controller.startMeeting();
      media.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.participantJoined,
          identity: 'remote',
          displayName: 'Remote',
          role: MeetingParticipantRole.publisher,
        ),
      );
      media.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.reconnecting,
        ),
      );
      expect(controller.state.status, MeetingStatus.reconnecting);
      expect(controller.state.session?.id, meetingId);
      expect(controller.state.participants, hasLength(1));
      media.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.reconnected,
        ),
      );
      expect(controller.state.status, MeetingStatus.connected);

      media.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.error,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, MeetingStatus.connected);
      expect(controller.state.errorCode, MeetingErrorCode.providerUnavailable);
      expect(controller.state.errorMessage, isNot(contains('raw')));
      expect(controller.state.participants, hasLength(1));
      expect(media.disconnectCalls, 0);
    },
  );

  test('ended media event cleans local state and participants', () async {
    await controller.startMeeting();
    media.emit(
      const MeetingMediaProviderEvent(
        type: MeetingMediaProviderEventType.participantJoined,
        identity: 'remote',
      ),
    );
    media.emit(
      const MeetingMediaProviderEvent(
        type: MeetingMediaProviderEventType.disconnected,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, MeetingStatus.ended);
    expect(controller.state.participants, isEmpty);
    expect(controller.state.localMicrophoneEnabled, isFalse);
  });

  test(
    'intentional disconnect ended event cannot resurrect terminal cleanup',
    () async {
      await controller.startMeeting();
      media.emitEndedOnDisconnect = true;
      await controller.leave();

      expect(controller.state.status, MeetingStatus.idle);
      expect(controller.state.session, isNull);
      expect(media.disconnectCalls, 1);
    },
  );

  test('leave disconnects without ending the durable session', () async {
    await controller.startMeeting();
    await controller.leave();

    expect(repository.endCalls, 0);
    expect(media.disconnectCalls, 1);
    expect(controller.state.status, MeetingStatus.idle);
    expect(controller.state.session, isNull);
  });

  test('endForEveryone ends durably before local cleanup', () async {
    await controller.startMeeting();
    await controller.endForEveryone();

    expect(repository.endCalls, 1);
    expect(media.disconnectCalls, 1);
    expect(controller.state.status, MeetingStatus.ended);
    expect(controller.state.session?.status, MeetingStatus.ended);
  });

  test(
    'feature disabled or invalid project fails before network/device',
    () async {
      final disabled = MeetingController(
        projectId: projectId,
        repository: repository,
        media: media,
        configuration: MeetingConfiguration(
          isEnabled: false,
          serverUrl: 'wss://meeting.example.test',
          maxParticipants: 8,
        ),
      );
      await expectLater(
        disabled.startMeeting(),
        throwsA(isA<MeetingControllerException>()),
      );
      expect(repository.createCalls, 0);
      await disabled.disposeAsync();

      final invalid = MeetingController(
        projectId: ' ',
        repository: repository,
        media: media,
        configuration: enabledConfiguration,
      );
      await expectLater(
        invalid.join(meetingId: meetingId),
        throwsA(isA<MeetingControllerException>()),
      );
      expect(repository.joinCalls, 0);
      await invalid.disposeAsync();
    },
  );

  test(
    'token refresh requests a token without creating another session',
    () async {
      await controller.startMeeting();
      media.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.tokenRefreshRequested,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(repository.createCalls, 1);
      expect(repository.tokenCalls, 2);
      expect(controller.state.status, MeetingStatus.connected);
      expect(controller.state.errorCode, isNull);
      expect(media.disconnectCalls, 0);
    },
  );

  test(
    'dispose invalidates stale completion and cleans media idempotently',
    () async {
      repository.holdCreate = true;
      final future = controller.startMeeting();
      await controller.disposeAsync();
      repository.completeCreate();
      await expectLater(future, throwsA(isA<MeetingControllerException>()));
      await controller.disposeAsync();
      expect(media.disconnectCalls, 1);
      expect(media.disposeCalls, 1);
      expect(controller.state.status, isNot(MeetingStatus.connected));
    },
  );
}

final enabledConfiguration = MeetingConfiguration(
  isEnabled: true,
  serverUrl: 'wss://meeting.example.test',
  maxParticipants: 8,
);

MeetingSession activeSession() => MeetingSession(
  id: meetingId,
  projectId: projectId,
  provider: 'livekit',
  providerRoomName: 'room-$meetingId',
  status: MeetingStatus.connected,
  createdBy: creatorId,
  createdAt: DateTime.utc(2026, 9, 15),
);

final endedSession = activeSession().copyWith(
  status: MeetingStatus.ended,
  endedAt: DateTime.utc(2026, 9, 15, 1),
  endedReason: MeetingTerminationReason.ended,
);

final token = MeetingMediaCredentials.fromProviderValues(
  token: 'token',
  serverUrl: 'wss://meeting.example.test',
  expiresAt: DateTime.utc(2099),
  identity: creatorId,
);

class FakeRepository extends MeetingRepository {
  FakeRepository() : super(null);

  late final StreamController<MeetingSession> _sessions =
      StreamController<MeetingSession>.broadcast(
        sync: true,
        onCancel: () => watchCancels++,
      );
  final _createCompleter = Completer<MeetingSession>();
  final _joinCompleter = Completer<MeetingSession>();
  int createCalls = 0;
  int joinCalls = 0;
  int tokenCalls = 0;
  int endCalls = 0;
  int watchCalls = 0;
  int watchCancels = 0;
  bool holdCreate = false;
  bool holdJoin = false;

  @override
  Future<MeetingSession> createMeeting({
    required String projectId,
    int maxParticipants = 8,
  }) {
    createCalls++;
    if (holdCreate) return _createCompleter.future;
    return Future.value(activeSession());
  }

  @override
  Future<MeetingSession> joinMeeting({required String meetingId}) {
    joinCalls++;
    if (holdJoin) return _joinCompleter.future;
    return Future.value(activeSession());
  }

  @override
  Future<MeetingMediaCredentials> requestToken({
    required String meetingId,
  }) async {
    tokenCalls++;
    return token;
  }

  @override
  Stream<MeetingSession> watchMeeting(String meetingId) {
    watchCalls++;
    return _sessions.stream;
  }

  void emit(MeetingSession session) => _sessions.add(session);

  @override
  Future<MeetingSession> endMeeting({
    required String meetingId,
    String reason = 'host_ended',
  }) async {
    endCalls++;
    return endedSession;
  }

  @override
  Future<void> removeParticipant({
    required String meetingId,
    required String identity,
  }) async {}

  void completeCreate() {
    if (!_createCompleter.isCompleted) {
      _createCompleter.complete(activeSession());
    }
  }

  void completeJoin() {
    holdJoin = false;
    if (!_joinCompleter.isCompleted) {
      _joinCompleter.complete(activeSession());
    }
  }
}

class FakeMedia implements MeetingMediaPort {
  final _events = StreamController<MeetingMediaEvent>.broadcast(sync: true);
  final calls = <String>[];
  final controlCalls = <String>[];
  int disconnectCalls = 0;
  int disposeCalls = 0;
  bool connected = false;
  bool canPublishValue = true;
  bool throwConnect = false;
  bool throwControl = false;
  bool emitEndedOnDisconnect = false;

  @override
  bool get canPublish => canPublishValue;

  @override
  String? get localIdentity => creatorId;

  @override
  Widget? buildVideoSurface(MeetingVideoSurface surface) => null;

  @override
  Stream<MeetingMediaEvent> get events => _events.stream;

  @override
  Future<void> connect({required MeetingMediaCredentials credentials}) async {
    if (throwConnect) throw StateError('raw connect failure');
    connected = true;
    calls.add('connect');
  }

  @override
  Future<void> updateToken({
    required MeetingMediaCredentials credentials,
  }) async {
    if (throwControl) throw StateError('raw token refresh failure');
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (throwControl) throw StateError('raw control failure');
    controlCalls.add('microphone:$enabled');
    calls.add('microphone:$enabled');
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    if (throwControl) throw StateError('raw control failure');
    controlCalls.add('camera:$enabled');
    calls.add('camera:$enabled');
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {
    if (throwControl) throw StateError('raw control failure');
    controlCalls.add('screen:$enabled');
    calls.add('screen:$enabled');
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    connected = false;
    if (emitEndedOnDisconnect) {
      _events.add(MeetingMediaEvent.connectionChanged(MeetingStatus.ended));
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _events.close();
  }

  void emit(MeetingMediaProviderEvent event) {
    final mapped = switch (event.type) {
      MeetingMediaProviderEventType.connected =>
        MeetingMediaEvent.connectionChanged(MeetingStatus.connected),
      MeetingMediaProviderEventType.reconnecting =>
        MeetingMediaEvent.connectionChanged(MeetingStatus.reconnecting),
      MeetingMediaProviderEventType.reconnected =>
        MeetingMediaEvent.connectionChanged(MeetingStatus.connected),
      MeetingMediaProviderEventType.disconnected =>
        MeetingMediaEvent.connectionChanged(MeetingStatus.ended),
      MeetingMediaProviderEventType.error => MeetingMediaEvent.providerError(
        errorCode: event.errorCode,
      ),
      MeetingMediaProviderEventType.tokenRefreshRequested =>
        MeetingMediaEvent.tokenRefreshRequested(),
      MeetingMediaProviderEventType.participantJoined =>
        MeetingMediaEvent.participantJoined(
          MeetingParticipant(
            identity: event.identity ?? '',
            displayName: event.displayName ?? '',
            role: event.role,
          ),
        ),
      MeetingMediaProviderEventType.participantLeft =>
        MeetingMediaEvent.participantLeft(event.identity ?? ''),
      MeetingMediaProviderEventType.trackSubscribed =>
        MeetingMediaEvent.trackSubscribed(
          identity: event.identity ?? '',
          trackKind: event.trackKind ?? '',
        ),
      MeetingMediaProviderEventType.trackUnsubscribed =>
        MeetingMediaEvent.trackUnsubscribed(
          identity: event.identity ?? '',
          trackKind: event.trackKind ?? '',
        ),
      MeetingMediaProviderEventType.participantStateChanged =>
        MeetingMediaEvent.localMediaChanged(
          microphoneEnabled: event.microphoneEnabled,
          cameraEnabled: event.cameraEnabled,
          screenShareEnabled: event.screenShareEnabled,
        ),
      MeetingMediaProviderEventType.activeSpeakerChanged =>
        MeetingMediaEvent.activeSpeakerChanged(
          identity: event.identity ?? '',
          isSpeaking: event.isSpeaking,
        ),
    };
    _events.add(mapped);
  }
}
