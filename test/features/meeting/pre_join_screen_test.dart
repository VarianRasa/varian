import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/meeting/data/meeting_configuration.dart';
import 'package:varian/features/meeting/data/meeting_media_credentials.dart';
import 'package:varian/features/meeting/data/meeting_media_port.dart';
import 'package:varian/features/meeting/data/meeting_repository.dart';
import 'package:varian/features/meeting/domain/meeting_errors.dart';
import 'package:varian/features/meeting/domain/meeting_models.dart';
import 'package:varian/features/meeting/presentation/pre_join_screen.dart';
import 'package:varian/features/meeting/state/meeting_controller.dart';

const projectId = 'project-1';
const meetingId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const creatorId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

final enabledConfig = MeetingConfiguration(
  isEnabled: true,
  serverUrl: 'wss://meeting.example.test',
  maxParticipants: 8,
);

void main() {
  testWidgets('pre-join content and action remain usable on a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final media = FakeMedia();
    final controller = makeController(media);

    await tester.pumpWidget(scope(controller, media));
    await tester.pumpAndSettle();

    expect(find.byType(UiPageScaffold), findsOneWidget);
    expect(find.byKey(const Key('meeting-join-button')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('meeting-join-button')));
    await tester.tap(find.byKey(const Key('meeting-join-button')));
    await tester.pumpAndSettle();

    expect(media.connectCalls, 1);
    expect(controller.state.status, MeetingStatus.connected);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disabled configuration renders unavailable without creating media',
    (tester) async {
      final media = FakeMedia();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            meetingConfigurationProvider.overrideWithValue(
              MeetingConfiguration(
                isEnabled: false,
                serverUrl: 'wss://meeting.example.test',
                maxParticipants: 8,
              ),
            ),
          ],
          child: const MaterialApp(
            home: PreJoinScreen(meetingId: meetingId, projectId: projectId),
          ),
        ),
      );

      expect(find.byKey(const Key('meeting-unavailable')), findsOneWidget);
      expect(media.connectCalls, 0);
    },
  );

  testWidgets(
    'malformed identifiers render safe unavailable state before provider creation',
    (tester) async {
      final media = FakeMedia();
      final controller = makeController(media);
      await tester.pumpWidget(
        scope(controller, media, meetingId: 'not-a-uuid'),
      );

      expect(find.byKey(const Key('meeting-unavailable')), findsOneWidget);
      expect(media.connectCalls, 0);
    },
  );

  testWidgets('join button is the only path that invokes controller/media', (
    tester,
  ) async {
    final media = FakeMedia();
    final controller = makeController(media);
    await tester.pumpWidget(scope(controller, media));
    expect(media.calls, isEmpty);

    await tester.tap(find.byKey(const Key('meeting-join-button')));
    await tester.pumpAndSettle();

    expect(controller.state.status, MeetingStatus.connected);
    expect(media.connectCalls, 1);
    expect(find.text('You are connected to this meeting.'), findsOneWidget);
  });

  testWidgets(
    'terminal controller state is not masked as connected after join',
    (tester) async {
      final media = FakeMedia();
      final controller = makeController(media);
      await tester.pumpWidget(scope(controller, media));
      await tester.tap(find.byKey(const Key('meeting-join-button')));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);

      media.emit(
        MeetingMediaEvent.providerError(
          errorCode: MeetingErrorCode.providerUnavailable,
        ),
      );
      await tester.pump();

      expect(find.text('Connected'), findsNothing);
      expect(find.byKey(const Key('meeting-join-button')), findsOneWidget);
    },
  );

  testWidgets('permission failure renders retry and retry invokes join again', (
    tester,
  ) async {
    final media = FakeMedia();
    final repository = FakeRepository()..denyJoin = true;
    final controller = makeController(media, repository: repository);
    await tester.pumpWidget(scope(controller, media, repository: repository));
    await tester.tap(find.byKey(const Key('meeting-join-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('meeting-error')), findsOneWidget);
    expect(repository.joinCalls, 1);
    repository.denyJoin = false;
    await tester.tap(find.byKey(const Key('meeting-join-button')));
    await tester.pumpAndSettle();
    expect(repository.joinCalls, 2);
    expect(controller.state.status, MeetingStatus.connected);
  });

  testWidgets('unmounting while join is pending does not update disposed UI', (
    tester,
  ) async {
    final media = FakeMedia();
    final repository = FakeRepository()..holdJoin = true;
    final controller = makeController(media, repository: repository);
    await tester.pumpWidget(scope(controller, media, repository: repository));
    await tester.tap(find.byKey(const Key('meeting-join-button')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    repository.completeJoin();
    await tester.pump();

    expect(find.byType(PreJoinScreen), findsNothing);
  });
}

Widget scope(
  MeetingController controller,
  FakeMedia media, {
  FakeRepository? repository,
  String meetingId = meetingId,
}) {
  final repo = repository ?? FakeRepository();
  return ProviderScope(
    overrides: [
      meetingConfigurationProvider.overrideWithValue(enabledConfig),
      meetingControllerProvider(projectId).overrideWith((ref) => controller),
      meetingRepositoryProvider(projectId).overrideWithValue(repo),
      meetingMediaPortProvider(projectId).overrideWithValue(media),
    ],
    child: MaterialApp(
      home: PreJoinScreen(meetingId: meetingId, projectId: projectId),
    ),
  );
}

MeetingController makeController(
  FakeMedia media, {
  FakeRepository? repository,
}) => MeetingController(
  projectId: projectId,
  repository: repository ?? FakeRepository(),
  media: media,
  configuration: enabledConfig,
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

final token = MeetingMediaCredentials.fromProviderValues(
  token: 'token',
  serverUrl: 'wss://meeting.example.test',
  expiresAt: DateTime.utc(2099),
  identity: creatorId,
);

class FakeRepository extends MeetingRepository {
  FakeRepository() : super(null);

  int joinCalls = 0;
  bool denyJoin = false;
  bool holdJoin = false;
  final _joinCompleter = Completer<MeetingSession>();

  @override
  Future<MeetingSession> joinMeeting({required String meetingId}) async {
    joinCalls++;
    if (denyJoin) {
      throw const MeetingRepositoryException(MeetingErrorCode.permissionDenied);
    }
    if (holdJoin) return _joinCompleter.future;
    return activeSession();
  }

  @override
  Future<MeetingMediaCredentials> requestToken({
    required String meetingId,
  }) async => token;

  @override
  Stream<MeetingSession> watchMeeting(String meetingId) => const Stream.empty();

  void completeJoin() {
    if (!_joinCompleter.isCompleted) _joinCompleter.complete(activeSession());
  }
}

class FakeMedia implements MeetingMediaPort {
  final _events = StreamController<MeetingMediaEvent>.broadcast(sync: true);
  final calls = <String>[];
  int connectCalls = 0;

  @override
  bool get canPublish => true;
  @override
  String? get localIdentity => null;

  @override
  Widget? buildVideoSurface(MeetingVideoSurface surface) => null;
  @override
  Stream<MeetingMediaEvent> get events => _events.stream;

  @override
  Future<void> connect({required MeetingMediaCredentials credentials}) async {
    connectCalls++;
    calls.add('connect');
  }

  @override
  Future<void> updateToken({
    required MeetingMediaCredentials credentials,
  }) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async =>
      calls.add('microphone');

  @override
  Future<void> setCameraEnabled(bool enabled) async => calls.add('camera');

  @override
  Future<void> setScreenShareEnabled(bool enabled) async => calls.add('screen');

  @override
  Future<void> disconnect() async => calls.add('disconnect');

  @override
  Future<void> dispose() async => _events.close();

  void emit(MeetingMediaEvent event) => _events.add(event);
}
