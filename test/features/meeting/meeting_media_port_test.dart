import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/meeting/data/livekit_meeting_media.dart';
import 'package:varian/features/meeting/data/meeting_media_credentials.dart';
import 'package:varian/features/meeting/data/meeting_media_port.dart';
import 'package:varian/features/meeting/domain/meeting_errors.dart';
import 'package:varian/features/meeting/domain/meeting_models.dart';

void main() {
  late FakeProvider provider;
  late LiveKitMeetingMedia media;
  late StreamSubscription<MeetingMediaEvent> subscription;
  late List<MeetingMediaEvent> events;

  setUp(() {
    provider = FakeProvider();
    media = LiveKitMeetingMedia(providerFactory: () => provider);
    events = <MeetingMediaEvent>[];
    subscription = media.events.listen(events.add);
  });

  MeetingMediaCredentials credentials(
    String token, {
    String serverUrl = 'wss://livekit.example.test',
  }) => MeetingMediaCredentials.fromProviderValues(
    token: token,
    serverUrl: serverUrl,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    identity: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  );

  tearDown(() async {
    await subscription.cancel();
    await media.dispose();
  });

  test(
    'connect is idempotent and controls run only after connection',
    () async {
      await media.setMicrophoneEnabled(true);
      expect(provider.microphoneCalls, isEmpty);

      await media.connect(credentials: credentials('token'));
      await media.connect(credentials: credentials('token-2'));
      await media.setMicrophoneEnabled(true);
      await media.setCameraEnabled(false);
      await media.setScreenShareEnabled(true);

      expect(provider.connectCalls, 1);
      expect(provider.microphoneCalls, [true]);
      expect(provider.cameraCalls, [false]);
      expect(provider.screenShareCalls, [true]);
    },
  );

  test(
    'maps participants, tracks, speakers, reconnects, token refresh, and end',
    () async {
      await media.connect(credentials: credentials('token'));
      provider.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.participantJoined,
          identity: 'remote-1',
          displayName: 'Remote',
          role: MeetingParticipantRole.publisher,
        ),
      );
      provider.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.trackSubscribed,
          identity: 'remote-1',
          trackKind: 'camera',
        ),
      );
      provider.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.activeSpeakerChanged,
          identity: 'remote-1',
          isSpeaking: true,
        ),
      );
      provider.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.reconnecting,
        ),
      );
      provider.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.tokenRefreshRequested,
        ),
      );
      provider.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.error,
          errorCode: MeetingErrorCode.providerUnavailable,
        ),
      );
      provider.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.disconnected,
        ),
      );

      expect(
        events.map((event) => event.type),
        containsAll(<MeetingMediaEventType>[
          MeetingMediaEventType.connectionChanged,
          MeetingMediaEventType.participantJoined,
          MeetingMediaEventType.trackSubscribed,
          MeetingMediaEventType.activeSpeakerChanged,
          MeetingMediaEventType.tokenRefreshRequested,
          MeetingMediaEventType.providerError,
        ]),
      );
      final participant = events.firstWhere(
        (event) => event.type == MeetingMediaEventType.participantJoined,
      );
      expect(participant.participant?.identity, 'remote-1');
      expect(
        events
            .firstWhere(
              (event) => event.type == MeetingMediaEventType.trackSubscribed,
            )
            .trackKind,
        'camera',
      );
      expect(
        events
            .where(
              (event) => event.type == MeetingMediaEventType.connectionChanged,
            )
            .map((event) => event.status),
        <MeetingStatus>[
          MeetingStatus.connected,
          MeetingStatus.reconnecting,
          MeetingStatus.ended,
        ],
      );
      expect(
        events
            .where((event) => event.type == MeetingMediaEventType.providerError)
            .single
            .errorCode,
        MeetingErrorCode.providerUnavailable,
      );
    },
  );

  test(
    'external screen-share unpublish emits deterministic local state',
    () async {
      await media.connect(credentials: credentials('token'));
      provider.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.participantStateChanged,
          identity: 'local',
          isLocal: true,
          screenShareEnabled: true,
        ),
      );
      provider.emit(
        const MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.participantStateChanged,
          identity: 'local',
          isLocal: true,
        ),
      );

      final localEvents = events
          .where(
            (event) => event.type == MeetingMediaEventType.localMediaChanged,
          )
          .toList();
      expect(localEvents, hasLength(2));
      expect(localEvents.first.screenShareEnabled, isTrue);
      expect(localEvents.last.screenShareEnabled, isFalse);
    },
  );

  test(
    'invalid endpoint and empty token fail before provider access',
    () async {
      expect(
        () => media.connect(
          credentials: credentials(
            'token',
            serverUrl: 'http://livekit.example.test',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => media.connect(credentials: credentials(' ')),
        throwsArgumentError,
      );
      expect(provider.connectCalls, 0);
    },
  );

  test('cleanup is idempotent and releases provider once', () async {
    await media.connect(credentials: credentials('token'));
    await media.disconnect();
    await media.disconnect();
    await media.dispose();
    await media.dispose();

    expect(provider.disconnectCalls, 1);
    expect(provider.disposeCalls, 1);
  });

  test(
    'provider errors are stable and do not expose raw signaling details',
    () async {
      provider.canPublishValue = false;
      await media.connect(credentials: credentials('token'));
      await media.setCameraEnabled(true);
      final error = events.lastWhere(
        (event) => event.type == MeetingMediaEventType.providerError,
      );
      expect(error.errorCode, MeetingErrorCode.authorizationError);

      provider.canPublishValue = true;
      provider.throwOnCamera = true;
      await media.setCameraEnabled(true);
      final transportError = events.lastWhere(
        (event) => event.type == MeetingMediaEventType.providerError,
      );
      expect(transportError.errorCode, MeetingErrorCode.providerUnavailable);
    },
  );
}

final class FakeProvider implements MeetingMediaProvider {
  final StreamController<MeetingMediaProviderEvent> _controller =
      StreamController<MeetingMediaProviderEvent>.broadcast(sync: true);
  int connectCalls = 0;
  int disconnectCalls = 0;
  int disposeCalls = 0;
  final microphoneCalls = <bool>[];
  final cameraCalls = <bool>[];
  final screenShareCalls = <bool>[];
  bool canPublishValue = true;
  bool throwOnCamera = false;
  final tokenUpdates = <String>[];

  @override
  Stream<MeetingMediaProviderEvent> get events => _controller.stream;
  @override
  String? get localIdentity => null;

  @override
  Widget? buildVideoSurface(MeetingVideoSurface surface) => null;

  @override
  bool get canPublish => canPublishValue;

  @override
  Future<void> connect({
    required String serverUrl,
    required String token,
  }) async => connectCalls++;

  @override
  Future<void> updateToken(String token) async => tokenUpdates.add(token);

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async =>
      microphoneCalls.add(enabled);

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    if (throwOnCamera) throw StateError('raw provider signaling detail');
    cameraCalls.add(enabled);
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async =>
      screenShareCalls.add(enabled);

  @override
  Future<void> disconnect() async => disconnectCalls++;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _controller.close();
  }

  void emit(MeetingMediaProviderEvent event) => _controller.add(event);
}
