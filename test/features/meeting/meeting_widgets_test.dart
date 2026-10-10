import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/meeting/data/meeting_configuration.dart';
import 'package:varian/features/meeting/data/meeting_media_credentials.dart';
import 'package:varian/features/meeting/data/meeting_media_port.dart';
import 'package:varian/features/meeting/data/meeting_repository.dart';
import 'package:varian/features/meeting/domain/meeting_models.dart';
import 'package:varian/features/meeting/presentation/meeting_screen.dart';
import 'package:varian/features/meeting/presentation/widgets/meeting_participants_panel.dart';
import 'package:varian/features/meeting/presentation/widgets/meeting_toolbar.dart';
import 'package:varian/features/meeting/presentation/widgets/participant_tile.dart';
import 'package:varian/features/meeting/state/meeting_controller.dart';

const projectId = 'project-1';
const meetingId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const creatorId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  testWidgets(
    'participant tile exposes screen share, mute, camera, and speaking states',
    (tester) async {
      const participant = MeetingParticipant(
        identity: 'remote-1',
        displayName: 'Ada Lovelace',
        role: MeetingParticipantRole.publisher,
        microphoneEnabled: false,
        cameraEnabled: false,
        screenShareEnabled: true,
        isSpeaking: true,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            height: 220,
            child: ParticipantTile(participant: participant, pinned: true),
          ),
        ),
      );

      expect(find.text('Screen share'), findsOneWidget);
      expect(find.text('Camera off'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ParticipantTile),
          matching: find.bySemanticsLabel(RegExp('Ada Lovelace')),
        ),
        findsAtLeastNWidgets(1),
      );
    },
  );
  testWidgets('participant overlay chrome uses shared spacing tokens', (
    tester,
  ) async {
    const participant = MeetingParticipant(
      identity: 'remote-spacing',
      displayName: 'Spacing check',
      role: MeetingParticipantRole.publisher,
      microphoneEnabled: false,
      cameraEnabled: false,
      screenShareEnabled: true,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 220,
          child: ParticipantTile(participant: participant, pinned: true),
        ),
      ),
    );

    final tile = find.byType(ParticipantTile);
    final tileRect = tester.getRect(tile);
    final badges = find.byType(UiBadge);
    final cameraBadge = tester.getRect(badges.at(0));
    final screenShareBadge = tester.getRect(badges.at(1));
    final name = tester.getRect(find.text('Spacing check'));
    final labelSurface = tester.widget<UiSurface>(
      find
          .ancestor(
            of: find.text('Spacing check'),
            matching: find.byType(UiSurface),
          )
          .first,
    );
    expect(
      cameraBadge.top - tileRect.top,
      AppSpacing.sm + AppSpacing.xxs + AppBorder.thin,
    );
    expect(
      tileRect.right - screenShareBadge.right,
      AppSpacing.sm + AppSpacing.xxs + AppBorder.thin,
    );
    expect(
      labelSurface.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + AppSpacing.xxs,
      ),
    );
    expect(name.left - tileRect.left, greaterThanOrEqualTo(AppSpacing.md));
  });
  testWidgets('participant label has token-backed opaque contrast panel', (
    tester,
  ) async {
    const participant = MeetingParticipant(
      identity: 'remote-opaque',
      displayName: 'Visible over video',
      role: MeetingParticipantRole.publisher,
      cameraEnabled: true,
    );
    final media = FakeMedia();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SizedBox(
          height: 220,
          child: ParticipantTile(
            participant: participant,
            media: media,
            videoSource: MeetingVideoSource.camera,
          ),
        ),
      ),
    );

    final tile = find.byType(ParticipantTile);
    final labelPanel = tester
        .widgetList<UiSurface>(
          find.descendant(of: tile, matching: find.byType(UiSurface)),
        )
        .singleWhere((surface) => surface.color != null);
    final text = tester.widget<Text>(find.text('Visible over video'));
    final foreground = text.style!.color!;
    final background = labelPanel.color!;
    expect(labelPanel.bordered, isTrue);
    expect(background, AppTokens.dark.panelElevated);
    expect(foreground, AppTokens.dark.text);

    final lighter =
        foreground.computeLuminance() > background.computeLuminance()
        ? foreground.computeLuminance()
        : background.computeLuminance();
    final darker = foreground.computeLuminance() > background.computeLuminance()
        ? background.computeLuminance()
        : foreground.computeLuminance();
    expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xFF112233),
      ),
      findsOneWidget,
    );
    expect(find.text('Visible over video'), findsOneWidget);
  });

  testWidgets(
    'toolbar invokes controls and hides publish actions for viewers',
    (tester) async {
      final state = MeetingState(
        projectId: projectId,
        status: MeetingStatus.connected,
        localMicrophoneEnabled: true,
        isHost: true,
        canPublish: true,
      );
      var mic = 0;
      var camera = 0;
      var screen = 0;
      var leave = 0;
      var end = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MeetingToolbar(
            state: state,
            onToggleMicrophone: () => mic++,
            onToggleCamera: () => camera++,
            onToggleScreenShare: () => screen++,
            onLeave: () => leave++,
            onEnd: () => end++,
          ),
        ),
      );
      await tester.tap(find.byTooltip('Mute microphone').first);
      await tester.tap(find.byTooltip('Turn camera on').first);
      await tester.tap(find.byTooltip('Start screen sharing').first);
      await tester.tap(find.byTooltip('Leave meeting').first);
      await tester.tap(find.byTooltip('End meeting for everyone').first);
      expect([mic, camera, screen, leave, end], [1, 1, 1, 1, 1]);

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingToolbar(
            state: state.copyWith(isHost: false),
            canPublish: false,
            onLeave: () {},
          ),
        ),
      );
      expect(find.byTooltip('Mute microphone'), findsAtLeastNWidgets(1));
      expect(find.byTooltip('End meeting for everyone'), findsNothing);
    },
  );

  testWidgets('toolbar disables all actions while an action is in flight', (
    tester,
  ) async {
    final state = MeetingState(
      projectId: projectId,
      status: MeetingStatus.connected,
      isHost: true,
      canPublish: true,
      actionInFlight: true,
    );
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MeetingToolbar(
          state: state,
          onToggleMicrophone: () => calls++,
          onToggleCamera: () => calls++,
          onToggleScreenShare: () => calls++,
          onParticipants: () => calls++,
          onLeave: () => calls++,
          onEnd: () => calls++,
        ),
      ),
    );

    for (final tooltip in [
      'Unmute microphone',
      'Turn camera on',
      'Start screen sharing',
      'Show participants',
      'Leave meeting',
      'End meeting for everyone',
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is UiIconButton &&
              widget.tooltip == tooltip &&
              widget.onPressed == null,
        ),
        findsOneWidget,
      );
    }
    expect(calls, 0);
  });

  testWidgets(
    'reconnecting keeps leave/end available but disables media commands',
    (tester) async {
      final state = MeetingState(
        projectId: projectId,
        status: MeetingStatus.reconnecting,
        isHost: true,
        canPublish: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeetingToolbar(
              state: state,
              onToggleMicrophone: () {},
              onToggleCamera: () {},
              onToggleScreenShare: () {},
              onParticipants: () {},
              onLeave: () {},
              onEnd: () {},
            ),
          ),
        ),
      );

      for (final tooltip in [
        'Unmute microphone',
        'Turn camera on',
        'Start screen sharing',
      ]) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is UiIconButton &&
                widget.tooltip == tooltip &&
                widget.onPressed == null,
          ),
          findsOneWidget,
        );
      }
      for (final tooltip in ['Leave meeting', 'End meeting for everyone']) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is UiIconButton &&
                widget.tooltip == tooltip &&
                widget.onPressed != null,
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'participants panel bounds populated local rows and host action',
    (tester) async {
      tester.view.physicalSize = const Size(420, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const participant = MeetingParticipant(
        identity: 'remote',
        displayName: 'Remote participant',
        role: MeetingParticipantRole.viewer,
      );
      final state = MeetingState(
        projectId: projectId,
        status: MeetingStatus.connected,
        isHost: true,
        participants: {
          'remote': participant,
          'local': participant.copyWith(
            identity: 'local',
            displayName: 'You',
            isLocal: true,
          ),
          '': participant.copyWith(identity: ''),
        },
      );
      var removed = '';
      await tester.pumpWidget(
        MaterialApp(
          home: MeetingParticipantsPanel(
            state: state,
            onRemoveParticipant: (identity) async => removed = identity,
          ),
        ),
      );
      final panel = tester.getRect(find.byType(MeetingParticipantsPanel));
      final row = tester.getRect(
        find.byKey(const ValueKey('participant-remote-row')),
      );
      final remove = tester.getRect(find.byTooltip('Remove participant'));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(420));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(700));
      expect(row.left, greaterThanOrEqualTo(panel.left));
      expect(row.right, lessThanOrEqualTo(panel.right));
      expect(row.top, greaterThanOrEqualTo(panel.top));
      expect(row.bottom, lessThanOrEqualTo(panel.bottom));
      expect(remove.left, greaterThanOrEqualTo(row.left));
      expect(remove.right, lessThanOrEqualTo(row.right));
      expect(remove.top, greaterThanOrEqualTo(row.top));
      expect(remove.bottom, lessThanOrEqualTo(row.bottom));
      await tester.tap(find.byTooltip('Remove participant'));
      expect(removed, 'remote');

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingParticipantsPanel(
            state: state.copyWith(isHost: false),
            onRemoveParticipant: (_) async {},
          ),
        ),
      );
      expect(find.byTooltip('Remove participant'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('participants remain reachable when the panel is short', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final participants = {
      for (var index = 0; index < 6; index++)
        'remote-$index': MeetingParticipant(
          identity: 'remote-$index',
          displayName: 'Remote participant $index',
          role: MeetingParticipantRole.viewer,
        ),
    };

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 180,
          child: MeetingParticipantsPanel(
            state: MeetingState(
              projectId: projectId,
              status: MeetingStatus.connected,
              participants: participants,
            ),
          ),
        ),
      ),
    );

    final scrollable = find.descendant(
      of: find.byType(MeetingParticipantsPanel),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Remote participant 5'),
      180,
      scrollable: scrollable,
    );

    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('participant-remote-5-row')))
          .flagsCollection
          .isHidden,
      isFalse,
    );
    expect(find.text('Remote participant 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'compact meeting screen keeps host chrome in bounds and opens participants',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final media = FakeMedia();
      final controller = MeetingController(
        projectId: projectId,
        repository: FakeRepository(),
        media: media,
        configuration: enabledConfiguration,
      );
      await controller.startMeeting();
      await tester.pumpWidget(scope(controller, media: media));
      await tester.pumpAndSettle();

      final screenBounds = tester.getRect(find.byType(MeetingScreen));
      final toolbarBounds = tester.getRect(find.byType(MeetingToolbar));
      expect(find.text('Video meeting'), findsOneWidget);
      expect(find.byTooltip('Back to meeting entry'), findsOneWidget);
      expect(toolbarBounds.left, greaterThanOrEqualTo(screenBounds.left));
      expect(toolbarBounds.right, lessThanOrEqualTo(screenBounds.right));
      expect(toolbarBounds.top, greaterThanOrEqualTo(screenBounds.top));
      expect(toolbarBounds.bottom, lessThanOrEqualTo(screenBounds.bottom));

      for (final tooltip in [
        'Unmute microphone',
        'Turn camera on',
        'Start screen sharing',
        'Show participants',
        'Leave meeting',
        'End meeting for everyone',
      ]) {
        final control = find.byTooltip(tooltip);
        expect(control, findsOneWidget);
        final bounds = tester.getRect(control);
        expect(bounds.left, greaterThanOrEqualTo(screenBounds.left));
        expect(bounds.right, lessThanOrEqualTo(screenBounds.right));
        expect(bounds.top, greaterThanOrEqualTo(screenBounds.top));
        expect(bounds.bottom, lessThanOrEqualTo(screenBounds.bottom));
      }

      await tester.tap(find.byTooltip('Show participants'));
      await tester.pumpAndSettle();
      expect(find.byType(MeetingParticipantsPanel), findsOneWidget);
      final participants = tester.getRect(
        find.byType(MeetingParticipantsPanel).last,
      );
      expect(participants.left, greaterThanOrEqualTo(0));
      expect(participants.right, lessThanOrEqualTo(320));
      expect(participants.bottom, lessThanOrEqualTo(568));
      expect(find.text('You'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await controller.disposeAsync();
    },
  );
  testWidgets('participant grid follows available-width breakpoints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(839, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final media = FakeMedia();
    final controller = MeetingController(
      projectId: projectId,
      repository: FakeRepository(),
      media: media,
      configuration: enabledConfiguration,
    );
    await controller.startMeeting();
    await tester.pumpWidget(scope(controller, media: media));
    for (var index = 0; index < 3; index++) {
      media.emit(
        MeetingMediaEvent.participantJoined(
          MeetingParticipant(
            identity: 'remote-$index',
            displayName: 'Remote $index',
            role: MeetingParticipantRole.viewer,
          ),
        ),
      );
    }
    await tester.pump();
    final initialGridRect = tester.getRect(
      find.byKey(const Key('meeting-participant-grid')),
    );
    final initialToolbar = tester.getRect(find.byType(MeetingToolbar));
    expect(initialGridRect.left, greaterThanOrEqualTo(0));
    expect(initialGridRect.right, lessThanOrEqualTo(839));
    expect(initialGridRect.bottom, lessThanOrEqualTo(initialToolbar.top));
    expect(find.byType(MeetingParticipantsPanel), findsNothing);

    int columns() =>
        (tester
                    .widget<GridView>(
                      find.byKey(const Key('meeting-participant-grid')),
                    )
                    .gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount;

    expect(columns(), 1);
    tester.view.physicalSize = const Size(840, 800);
    await tester.pump();
    expect(find.byType(MeetingParticipantsPanel), findsOneWidget);
    final panel = tester.getRect(find.byType(MeetingParticipantsPanel));
    final gridAtBreakpoint = tester.getRect(
      find.byKey(const Key('meeting-participant-grid')),
    );
    expect(panel.width, 264);
    expect(gridAtBreakpoint.right, lessThanOrEqualTo(panel.left));
    expect(panel.bottom, lessThanOrEqualTo(800));
    expect(columns(), 1);
    tester.view.physicalSize = const Size(1300, 800);
    await tester.pump();
    expect(columns(), 2);

    tester.view.physicalSize = const Size(1600, 900);
    await tester.pump();
    expect(columns(), 3);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await controller.disposeAsync();
  });
  testWidgets(
    'stage renders empty, participant, reconnecting, error, and ended states',
    (tester) async {
      final media = FakeMedia();
      final repository = FakeRepository();
      final controller = MeetingController(
        projectId: projectId,
        repository: repository,
        media: media,
        configuration: enabledConfiguration,
      );
      await controller.startMeeting();
      await tester.pumpWidget(scope(controller));
      expect(find.text('You'), findsOneWidget);

      media.emit(
        MeetingMediaEvent.participantJoined(
          const MeetingParticipant(
            identity: 'remote',
            displayName: 'Remote',
            role: MeetingParticipantRole.viewer,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('meeting-participant-grid')), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);

      media.emit(
        MeetingMediaEvent.connectionChanged(MeetingStatus.reconnecting),
      );
      await tester.pump();
      expect(find.text('Reconnecting to the video service…'), findsOneWidget);
      expect(find.byTooltip('Leave meeting'), findsAtLeastNWidgets(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.disposeAsync();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final enabledConfiguration = MeetingConfiguration(
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
  createdBy: creatorId,
  createdAt: DateTime.utc(2026, 9, 15),
);
final token = MeetingMediaCredentials.fromProviderValues(
  token: 'token',
  serverUrl: 'wss://meeting.example.test',
  expiresAt: DateTime.utc(2099),
  identity: creatorId,
);

Widget scope(MeetingController controller, {MeetingMediaPort? media}) =>
    ProviderScope(
      overrides: [
        meetingConfigurationProvider.overrideWithValue(enabledConfiguration),
        meetingControllerProvider(projectId).overrideWith((ref) => controller),
        if (media != null)
          meetingMediaPortProvider(projectId).overrideWithValue(media),
      ],
      child: const MaterialApp(
        home: MeetingScreen(meetingId: meetingId, projectId: projectId),
      ),
    );

class FakeRepository extends MeetingRepository {
  FakeRepository() : super(null);
  final _sessions = StreamController<MeetingSession>.broadcast(sync: true);
  @override
  Future<MeetingSession> createMeeting({
    required String projectId,
    int maxParticipants = 8,
  }) async => session;
  @override
  Future<MeetingMediaCredentials> requestToken({
    required String meetingId,
  }) async => token;
  @override
  Stream<MeetingSession> watchMeeting(String meetingId) => _sessions.stream;
}

class FakeMedia implements MeetingMediaPort {
  @override
  bool get canPublish => true;
  final _events = StreamController<MeetingMediaEvent>.broadcast(sync: true);
  @override
  Stream<MeetingMediaEvent> get events => _events.stream;
  @override
  String? get localIdentity => null;

  @override
  Widget? buildVideoSurface(MeetingVideoSurface surface) =>
      const ColoredBox(color: Color(0xFF112233));
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
  Future<void> setScreenShareEnabled(bool enabled) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async => _events.close();
  void emit(MeetingMediaEvent event) => _events.add(event);
}
