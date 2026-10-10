import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/meeting/data/meeting_configuration.dart';
import 'package:varian/features/meeting/data/meeting_media_credentials.dart';
import 'package:varian/features/meeting/data/meeting_media_port.dart';
import 'package:varian/features/meeting/data/meeting_repository.dart';
import 'package:varian/features/meeting/domain/meeting_errors.dart';
import 'package:varian/features/meeting/domain/meeting_models.dart';
import 'package:varian/features/meeting/state/meeting_controller.dart';

const projectId = 'project-task10';
const meetingId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const secondMeetingId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const localIdentity = 'owner-1';
const removableIdentity = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

void main() {
  test(
    'external room revoke terminal cleanup is idempotent and ignores late media',
    () async {
      final media = FakeMedia();
      final controller = makeController(media);
      await controller.startMeeting();
      media.emit(
        MeetingMediaEvent.participantJoined(
          const MeetingParticipant(
            identity: 'remote',
            displayName: 'Remote',
            role: MeetingParticipantRole.viewer,
          ),
        ),
      );
      await controller.handleExternalTermination(
        MeetingTerminationReason.roomRevoked,
      );
      final disconnects = media.disconnectCalls;
      expect(controller.state.status, MeetingStatus.error);
      expect(controller.state.errorCode, MeetingErrorCode.providerUnavailable);
      expect(controller.state.participants, isEmpty);
      media.emit(
        MeetingMediaEvent.participantJoined(
          const MeetingParticipant(
            identity: 'late',
            displayName: 'Late',
            role: MeetingParticipantRole.viewer,
          ),
        ),
      );
      await controller.handleExternalTermination(
        MeetingTerminationReason.ended,
      );
      expect(controller.state.errorCode, MeetingErrorCode.providerUnavailable);
      expect(media.disconnectCalls, disconnects);
      await controller.disposeAsync();
    },
  );

  test('durable ended reasons map to stable terminal state', () async {
    final repository = FakeRepository(
      endedSession: session.copyWith(
        status: MeetingStatus.ended,
        endedAt: DateTime.utc(2026, 9, 15),
        endedReason: MeetingTerminationReason.removed,
      ),
    );
    final media = FakeMedia();
    final controller = makeController(media, repository: repository);
    await controller.startMeeting();
    repository.emit(repository.endedSession!);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.status, MeetingStatus.ended);
    expect(controller.state.errorCode, MeetingErrorCode.removed);
    await controller.disposeAsync();
  });

  test(
    'participant left matching token identity is terminal, remote leave is roster-only',
    () async {
      final media = FakeMedia();
      final controller = makeController(media);
      await controller.startMeeting();
      media.emit(
        MeetingMediaEvent.participantJoined(
          const MeetingParticipant(
            identity: 'remote',
            displayName: 'Remote',
            role: MeetingParticipantRole.viewer,
          ),
        ),
      );
      media.emit(MeetingMediaEvent.participantLeft('remote'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, MeetingStatus.connected);
      media.emit(MeetingMediaEvent.participantLeft(localIdentity));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, MeetingStatus.ended);
      expect(controller.state.errorCode, MeetingErrorCode.removed);
      await controller.disposeAsync();
    },
  );

  test(
    'token refresh retries finitely and leaves stable provider error',
    () async {
      final repository = FakeRepository(refreshFailures: 5);
      final media = FakeMedia();
      final controller = makeController(media, repository: repository);
      await controller.startMeeting();
      media.emit(MeetingMediaEvent.tokenRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(repository.tokenCalls, 4);
      expect(controller.state.errorCode, MeetingErrorCode.providerUnavailable);
      expect(controller.state.session, isNotNull);
      await controller.disposeAsync();
    },
  );

  test('duplicate leave shares one cleanup operation', () async {
    final media = FakeMedia();
    final controller = makeController(media);
    await controller.startMeeting();
    await Future.wait<void>([controller.leave(), controller.leave()]);
    expect(media.disconnectCalls, 1);
    expect(controller.state.status, MeetingStatus.idle);
    await controller.disposeAsync();
  });

  test('terminal leave then join rebinds media events', () async {
    final media = FakeMedia();
    final controller = makeController(media);
    await controller.startMeeting();
    await controller.handleExternalTermination(MeetingTerminationReason.ended);
    await controller.leave();
    await controller.startMeeting();
    expect(controller.state.status, MeetingStatus.connected);
    media.emit(MeetingMediaEvent.connectionChanged(MeetingStatus.reconnecting));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.status, MeetingStatus.reconnecting);
    await controller.disposeAsync();
  });

  test(
    'dispose invalidates late terminal events and disconnects once',
    () async {
      final media = FakeMedia();
      final controller = makeController(media);
      await controller.startMeeting();
      await controller.disposeAsync();
      media.emit(MeetingMediaEvent.connectionChanged(MeetingStatus.ended));
      await controller.handleExternalTermination(
        MeetingTerminationReason.ended,
      );
      expect(media.disconnectCalls, 1);
    },
  );

  test('duplicate external termination shares one cleanup operation', () async {
    final media = FakeMedia()..holdDisconnect = true;
    final controller = makeController(media);
    await controller.startMeeting();

    final first = controller.handleExternalTermination(
      MeetingTerminationReason.roomRevoked,
    );
    final second = controller.handleExternalTermination(
      MeetingTerminationReason.expired,
    );

    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(media.disconnectCalls, 1);
    media.completeDisconnect();
    await Future.wait<void>([first, second]);

    expect(controller.state.status, MeetingStatus.error);
    expect(
      controller.state.terminationReason,
      MeetingTerminationReason.roomRevoked,
    );
    expect(media.disconnectCalls, 1);
    await controller.disposeAsync();
  });

  test('end-for-everyone racing with room revoke cleans up once', () async {
    final repository = RaceRepository();
    final media = FakeMedia();
    final controller = makeController(media, repository: repository);
    await controller.startMeeting();
    repository.holdEnd = true;

    final end = controller.endForEveryone();
    await Future<void>.delayed(Duration.zero);
    final revoke = controller.handleExternalTermination(
      MeetingTerminationReason.roomRevoked,
    );
    repository.completeEnd();
    await Future.wait<void>([end, revoke]);

    expect(repository.endCalls, 1);
    expect(media.disconnectCalls, 1);
    expect(controller.state.status, MeetingStatus.error);
    expect(
      controller.state.terminationReason,
      MeetingTerminationReason.roomRevoked,
    );
    await controller.disposeAsync();
    await repository.close();
  });

  test('duplicate end calls issue one repository call', () async {
    final repository = RaceRepository()..holdEnd = true;
    final media = FakeMedia();
    final controller = makeController(media, repository: repository);
    await controller.startMeeting();

    final first = controller.endForEveryone();
    final second = controller.endForEveryone();
    expect(identical(first, second), isTrue);
    expect(repository.endCalls, 1);

    repository.completeEnd();
    await Future.wait<void>([first, second]);
    expect(repository.endCalls, 1);
    expect(controller.state.status, MeetingStatus.ended);
    await controller.disposeAsync();
    await repository.close();
  });

  test('stale end completion cannot affect a new joined meeting', () async {
    final repository = RaceRepository(
      createSessions: [session],
      joinSessions: [secondSession],
    )..holdEnd = true;
    final media = FakeMedia();
    final controller = makeController(media, repository: repository);
    await controller.startMeeting();

    final staleEnd = controller.endForEveryone();
    await Future<void>.delayed(Duration.zero);
    await controller.leave();
    await controller.join(meetingId: secondMeetingId);
    expect(controller.state.meetingId, secondMeetingId);
    expect(repository.endCalls, 1);

    final currentEnd = controller.endForEveryone();
    expect(repository.endCalls, 2);
    repository.completeEnd(
      session.copyWith(
        status: MeetingStatus.ended,
        endedAt: DateTime.utc(2026, 9, 15, 2),
        endedReason: MeetingTerminationReason.ended,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.status, MeetingStatus.connected);
    expect(controller.state.meetingId, secondMeetingId);
    repository.completeEnd(secondEndedSession);
    await Future.wait<void>([staleEnd, currentEnd]);

    expect(controller.state.status, MeetingStatus.ended);
    expect(controller.state.session?.id, secondMeetingId);
    await controller.disposeAsync();
    await repository.close();
  });

  test(
    'duplicate remove calls for one identity issue one repository call',
    () async {
      final repository = RaceRepository()..holdRemove = true;
      final media = FakeMedia();
      final controller = makeController(media, repository: repository);
      await controller.startMeeting();

      final first = controller.removeParticipant(removableIdentity);
      final second = controller.removeParticipant(
        removableIdentity.toUpperCase(),
      );
      expect(identical(first, second), isTrue);
      expect(repository.removeCalls, 1);

      repository.completeRemove();
      await Future.wait<void>([first, second]);
      expect(repository.removeCalls, 1);
      expect(controller.state.status, MeetingStatus.connected);
      await controller.disposeAsync();
      await repository.close();
    },
  );

  test('stale remove completion after terminal cleanup is ignored', () async {
    final repository = RaceRepository()..holdRemove = true;
    final media = FakeMedia();
    final controller = makeController(media, repository: repository);
    await controller.startMeeting();

    final remove = controller.removeParticipant(removableIdentity);
    await Future<void>.delayed(Duration.zero);
    await controller.handleExternalTermination(
      MeetingTerminationReason.expired,
    );
    repository.completeRemove();
    await remove;

    expect(controller.state.status, MeetingStatus.error);
    expect(
      controller.state.terminationReason,
      MeetingTerminationReason.expired,
    );
    expect(controller.state.actionInFlight, isFalse);
    expect(media.disconnectCalls, 1);
    await controller.disposeAsync();
    await repository.close();
  });

  test('room revoke while reconnecting terminalizes and cleans once', () async {
    final media = FakeMedia();
    final controller = makeController(media);
    await controller.startMeeting();
    media.emit(MeetingMediaEvent.connectionChanged(MeetingStatus.reconnecting));
    await Future<void>.delayed(Duration.zero);

    await controller.handleExternalTermination(
      MeetingTerminationReason.roomRevoked,
    );

    expect(controller.state.status, MeetingStatus.error);
    expect(
      controller.state.terminationReason,
      MeetingTerminationReason.roomRevoked,
    );
    expect(controller.state.participants, isEmpty);
    expect(media.disconnectCalls, 1);
    await controller.disposeAsync();
  });

  test('provider error while reconnecting terminalizes safely', () async {
    final media = FakeMedia();
    final controller = makeController(media);
    await controller.startMeeting();
    media.emit(MeetingMediaEvent.connectionChanged(MeetingStatus.reconnecting));
    media.emit(MeetingMediaEvent.providerError());
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, MeetingStatus.error);
    expect(controller.state.errorCode, MeetingErrorCode.providerUnavailable);
    expect(
      controller.state.terminationReason,
      MeetingTerminationReason.providerError,
    );
    expect(media.disconnectCalls, 1);
    await controller.disposeAsync();
  });

  test(
    'provider removal and room-ended errors terminalize the meeting',
    () async {
      for (final entry in {
        MeetingErrorCode.removed: MeetingStatus.ended,
        MeetingErrorCode.ended: MeetingStatus.ended,
      }.entries) {
        final media = FakeMedia();
        final controller = makeController(media);
        await controller.startMeeting();
        media.emit(MeetingMediaEvent.providerError(errorCode: entry.key));
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.status, entry.value);
        expect(
          controller.state.errorCode,
          entry.key == MeetingErrorCode.ended ? isNull : entry.key,
        );
        await controller.disposeAsync();
      }
    },
  );

  test('late media events after terminal state are ignored', () async {
    final media = FakeMedia();
    final controller = makeController(media);
    await controller.startMeeting();
    await controller.handleExternalTermination(
      MeetingTerminationReason.expired,
    );

    media.emit(
      MeetingMediaEvent.participantJoined(
        const MeetingParticipant(
          identity: removableIdentity,
          displayName: 'Late',
          role: MeetingParticipantRole.publisher,
        ),
      ),
    );
    media.emit(
      MeetingMediaEvent.localMediaChanged(
        microphoneEnabled: true,
        cameraEnabled: true,
        screenShareEnabled: true,
      ),
    );
    media.emit(MeetingMediaEvent.connectionChanged(MeetingStatus.connected));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, MeetingStatus.error);
    expect(controller.state.participants, isEmpty);
    expect(controller.state.localMicrophoneEnabled, isFalse);
    expect(media.disconnectCalls, 1);
    await controller.disposeAsync();
  });

  test('token refresh retry exhaustion is bounded', () async {
    final repository = FakeRepository(refreshFailures: 10);
    final media = FakeMedia();
    final controller = makeController(media, repository: repository);
    await controller.startMeeting();
    media.emit(MeetingMediaEvent.tokenRefreshRequested());
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(repository.tokenCalls, 4);
    expect(controller.state.errorCode, MeetingErrorCode.providerUnavailable);
    await controller.disposeAsync();
  });

  test('token refresh retry is cancelled after leave', () async {
    final repository = FakeRepository(refreshFailures: 10);
    final media = FakeMedia();
    final controller = makeController(media, repository: repository);
    await controller.startMeeting();
    media.emit(MeetingMediaEvent.tokenRefreshRequested());
    await Future<void>.delayed(Duration.zero);
    await controller.leave();
    final callsAfterLeave = repository.tokenCalls;
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(repository.tokenCalls, callsAfterLeave);
    expect(controller.state.status, MeetingStatus.idle);
    await controller.disposeAsync();
  });

  test('token refresh retry is ignored after terminalization', () async {
    final repository = FakeRepository(refreshFailures: 10);
    final media = FakeMedia();
    final controller = makeController(media, repository: repository);
    await controller.startMeeting();
    media.emit(MeetingMediaEvent.tokenRefreshRequested());
    await Future<void>.delayed(Duration.zero);
    await controller.handleExternalTermination(MeetingTerminationReason.ended);
    final callsAfterTerminal = repository.tokenCalls;
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(repository.tokenCalls, callsAfterTerminal);
    expect(controller.state.status, MeetingStatus.ended);
    await controller.disposeAsync();
  });

  test('terminal leave then join rebinds media and session events', () async {
    final repository = RaceRepository(
      createSessions: [session],
      joinSessions: [secondSession],
    );
    final media = FakeMedia();
    final controller = makeController(media, repository: repository);
    await controller.startMeeting();
    await controller.handleExternalTermination(MeetingTerminationReason.ended);
    await controller.leave();
    await controller.join(meetingId: secondMeetingId);

    expect(repository.watchCalls, 2);
    expect(controller.state.status, MeetingStatus.connected);
    media.emit(MeetingMediaEvent.connectionChanged(MeetingStatus.reconnecting));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.status, MeetingStatus.reconnecting);
    repository.emit(secondEndedSession);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, MeetingStatus.ended);
    expect(controller.state.meetingId, isNull);
    expect(media.disconnectCalls, 2);
    await controller.disposeAsync();
    await repository.close();
  });

  test(
    'meeting cleanup does not issue a screen-tracking stop command',
    () async {
      final media = FakeMedia();
      final controller = makeController(media);
      await controller.startMeeting();
      final defaultScreenCommands = media.screenShareCalls;

      await controller.handleExternalTermination(
        MeetingTerminationReason.ended,
      );

      expect(media.screenShareCalls, defaultScreenCommands);
      expect(media.disconnectCalls, 1);
      await controller.disposeAsync();
    },
  );
}

final configuration = MeetingConfiguration(
  isEnabled: true,
  serverUrl: 'wss://meeting.example.test',
  maxParticipants: 8,
);
final session = MeetingSession(
  id: meetingId,
  projectId: projectId,
  provider: 'livekit',
  providerRoomName: 'room',
  status: MeetingStatus.connected,
  createdBy: localIdentity,
  createdAt: DateTime.utc(2026, 9, 15),
);
final secondSession = session.copyWith(
  id: secondMeetingId,
  providerRoomName: 'room-second',
);
final secondEndedSession = secondSession.copyWith(
  status: MeetingStatus.ended,
  endedAt: DateTime.utc(2026, 9, 15, 3),
  endedReason: MeetingTerminationReason.ended,
);
final token = MeetingMediaCredentials.fromProviderValues(
  token: 'opaque',
  serverUrl: 'wss://meeting.example.test',
  expiresAt: DateTime.utc(2099),
  identity: localIdentity,
);

MeetingController makeController(
  FakeMedia media, {
  MeetingRepository? repository,
}) => MeetingController(
  projectId: projectId,
  repository: repository ?? FakeRepository(),
  media: media,
  configuration: configuration,
);

class FakeRepository extends MeetingRepository {
  FakeRepository({this.refreshFailures = 0, this.endedSession}) : super(null);
  final int refreshFailures;
  final MeetingSession? endedSession;
  final _sessions = StreamController<MeetingSession>.broadcast(sync: true);
  int tokenCalls = 0;
  @override
  Future<MeetingSession> createMeeting({
    required String projectId,
    int maxParticipants = 8,
  }) async => session;
  @override
  Future<MeetingMediaCredentials> requestToken({
    required String meetingId,
  }) async {
    tokenCalls++;
    if (tokenCalls > 1 && tokenCalls <= refreshFailures + 1) {
      throw const MeetingRepositoryException(
        MeetingErrorCode.providerUnavailable,
      );
    }
    return token;
  }

  @override
  Stream<MeetingSession> watchMeeting(String meetingId) => _sessions.stream;
  void emit(MeetingSession value) => _sessions.add(value);
}

class FakeMedia implements MeetingMediaPort {
  final _events = StreamController<MeetingMediaEvent>.broadcast(sync: true);
  int disconnectCalls = 0;
  int screenShareCalls = 0;
  bool holdDisconnect = false;
  Completer<void>? _disconnectCompleter;
  @override
  bool get canPublish => true;
  @override
  String? get localIdentity => 'owner-1';
  @override
  Stream<MeetingMediaEvent> get events => _events.stream;
  @override
  Widget? buildVideoSurface(MeetingVideoSurface surface) => null;
  @override
  Future<void> connect({required MeetingMediaCredentials credentials}) async {}
  @override
  Future<void> updateToken({
    required MeetingMediaCredentials credentials,
  }) async {}
  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}
  @override
  Future<void> setCameraEnabled(bool enabled) async {}
  @override
  Future<void> setScreenShareEnabled(bool enabled) async => screenShareCalls++;
  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    if (holdDisconnect) {
      _disconnectCompleter ??= Completer<void>();
      await _disconnectCompleter!.future;
    }
  }

  @override
  Future<void> dispose() async => _events.close();
  void completeDisconnect() {
    _disconnectCompleter?.complete();
  }

  void emit(MeetingMediaEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

class RaceRepository extends MeetingRepository {
  RaceRepository({
    List<MeetingSession>? createSessions,
    List<MeetingSession>? joinSessions,
  }) : _createSessions = createSessions ?? [session],
       _joinSessions = joinSessions ?? const [],
       super(null);

  final List<MeetingSession> _createSessions;
  final List<MeetingSession> _joinSessions;
  final _sessionEvents = StreamController<MeetingSession>.broadcast(sync: true);
  final _pendingEnds = <Completer<MeetingSession>>[];
  final _pendingRemoves = <Completer<void>>[];
  int _createIndex = 0;
  int _joinIndex = 0;
  int createCalls = 0;
  int joinCalls = 0;
  int tokenCalls = 0;
  int endCalls = 0;
  int removeCalls = 0;
  int watchCalls = 0;
  bool holdEnd = false;
  bool holdRemove = false;

  @override
  Future<MeetingSession> createMeeting({
    required String projectId,
    int maxParticipants = 8,
  }) async {
    createCalls++;
    final index = _createIndex++;
    return _createSessions[index.clamp(0, _createSessions.length - 1)];
  }

  @override
  Future<MeetingSession> joinMeeting({required String meetingId}) async {
    joinCalls++;
    final index = _joinIndex++;
    if (_joinSessions.isEmpty) return session;
    return _joinSessions[index.clamp(0, _joinSessions.length - 1)];
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
    return _sessionEvents.stream;
  }

  @override
  Future<MeetingSession> endMeeting({
    required String meetingId,
    String reason = 'host_ended',
  }) {
    endCalls++;
    if (holdEnd) {
      final completer = Completer<MeetingSession>();
      _pendingEnds.add(completer);
      return completer.future;
    }
    return Future.value(
      secondEndedSession.id == meetingId
          ? secondEndedSession
          : session.copyWith(
              status: MeetingStatus.ended,
              endedAt: DateTime.utc(2026, 9, 15, 2),
              endedReason: MeetingTerminationReason.ended,
            ),
    );
  }

  @override
  Future<void> removeParticipant({
    required String meetingId,
    required String identity,
  }) {
    removeCalls++;
    if (holdRemove) {
      final completer = Completer<void>();
      _pendingRemoves.add(completer);
      return completer.future;
    }
    return Future<void>.value();
  }

  void completeEnd([MeetingSession? value]) {
    if (_pendingEnds.isEmpty) return;
    final completer = _pendingEnds.removeAt(0);
    completer.complete(
      value ??
          session.copyWith(
            status: MeetingStatus.ended,
            endedAt: DateTime.utc(2026, 9, 15, 2),
            endedReason: MeetingTerminationReason.ended,
          ),
    );
  }

  void completeRemove() {
    if (_pendingRemoves.isEmpty) return;
    _pendingRemoves.removeAt(0).complete();
  }

  void emit(MeetingSession value) => _sessionEvents.add(value);

  Future<void> close() => _sessionEvents.close();
}
