import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/presentation/data/supabase_presenter_remote_transport.dart';
import 'package:varian/features/presentation/domain/presenter_remote_controller.dart';
import 'package:varian/features/presentation/domain/remote_presenter_control.dart';

void main() {
  test('remote presenter requires consent and an unexpired role', () {
    final now = DateTime.utc(2026, 9, 11);
    final session = PresenterRemoteSession(
      sessionId: 'session-1',
      projectId: 'project-1',
      presenterId: 'user-1',
      role: PresenterRemoteRole.presenter,
      expiresAt: now.add(const Duration(minutes: 5)),
    );

    expect(session.isActive(now), isFalse);
    expect(session.grantConsent().isActive(now), isTrue);
    expect(
      session.grantConsent().canPerform(PresenterRemoteAction.next, now),
      isTrue,
    );
  });

  test('remote command rejects expired or mismatched sessions', () {
    final now = DateTime.utc(2026, 9, 11);
    final session = PresenterRemoteSession(
      sessionId: 'session-1',
      projectId: 'project-1',
      presenterId: 'user-1',
      role: PresenterRemoteRole.owner,
      expiresAt: now.add(const Duration(minutes: 5)),
      consentGranted: true,
    );
    final command = PresenterRemoteCommand(
      commandId: 'command-1',
      sessionId: 'session-1',
      action: PresenterRemoteAction.jump,
      frameIndex: 2,
      createdAt: now,
    );

    expect(command.isValidFor(session, now), isTrue);
    expect(
      command.isValidFor(session.copyWith(sessionId: 'other'), now),
      isFalse,
    );
  });

  test('remote session and command round-trip through JSON', () {
    final session = PresenterRemoteSession(
      sessionId: 'session-1',
      projectId: 'project-1',
      presenterId: 'presenter-1',
      role: PresenterRemoteRole.presenter,
      expiresAt: DateTime.utc(2026, 9, 11, 12),
      consentGranted: true,
    );
    final command = PresenterRemoteCommand(
      commandId: 'command-1',
      sessionId: session.sessionId,
      action: PresenterRemoteAction.jump,
      frameIndex: 3,
      createdAt: DateTime.utc(2026, 9, 11, 11),
      actorId: 'remote-1',
      projectId: session.projectId,
    );

    expect(
      PresenterRemoteSession.fromJson(session.toJson()).toJson(),
      session.toJson(),
    );
    expect(
      PresenterRemoteCommand.fromJson(command.toJson()).toJson(),
      command.toJson(),
    );
  });

  test(
    'remote command controller applies commands once and rejects replay',
    () {
      final now = DateTime.utc(2026, 9, 11, 11);
      final controller = PresenterRemoteCommandController(
        session: PresenterRemoteSession(
          sessionId: 'session-1',
          projectId: 'project-1',
          presenterId: 'presenter-1',
          role: PresenterRemoteRole.presenter,
          expiresAt: DateTime.utc(2026, 9, 11, 12),
          consentGranted: true,
        ),
      );
      final command = PresenterRemoteCommand(
        commandId: 'command-1',
        sessionId: 'session-1',
        action: PresenterRemoteAction.next,
        createdAt: now,
      );

      final applied = controller.apply(command, now: now, frameCount: 4);
      final replay = controller.apply(command, now: now, frameCount: 4);

      expect(applied.disposition, PresenterRemoteCommandDisposition.applied);
      expect(applied.frameIndex, 1);
      expect(replay.disposition, PresenterRemoteCommandDisposition.duplicate);
      expect(controller.currentFrameIndex, 1);
    },
  );

  test('remote controller handles pause, jump, and stop expiry', () {
    final now = DateTime.utc(2026, 9, 11, 11);
    final controller = PresenterRemoteCommandController(
      session: PresenterRemoteSession(
        sessionId: 'session-1',
        projectId: 'project-1',
        presenterId: 'presenter-1',
        role: PresenterRemoteRole.owner,
        expiresAt: DateTime.utc(2026, 9, 11, 12),
        consentGranted: true,
      ),
    );

    final paused = controller.apply(
      PresenterRemoteCommand(
        commandId: 'pause',
        sessionId: 'session-1',
        action: PresenterRemoteAction.pause,
        createdAt: DateTime.utc(2026, 9, 11, 11),
      ),
      now: now,
      frameCount: 4,
    );
    final jumped = controller.apply(
      PresenterRemoteCommand(
        commandId: 'jump',
        sessionId: 'session-1',
        action: PresenterRemoteAction.jump,
        frameIndex: 2,
        createdAt: DateTime.utc(2026, 9, 11, 11),
      ),
      now: now,
      frameCount: 4,
    );
    final stopped = controller.apply(
      PresenterRemoteCommand(
        commandId: 'stop',
        sessionId: 'session-1',
        action: PresenterRemoteAction.stop,
        createdAt: DateTime.utc(2026, 9, 11, 11),
      ),
      now: now,
      frameCount: 4,
    );

    expect(paused.paused, isTrue);
    expect(jumped.frameIndex, 2);
    expect(stopped.applied, isTrue);
    expect(controller.session!.isActive(now), isFalse);
  });

  test('remote transport parser unwraps Realtime payloads', () {
    final payload = extractPresenterRemoteCommandPayload({
      'event': 'presenter_command',
      'payload': {
        'commandId': 'command-1',
        'sessionId': 'session-1',
        'action': 'next',
      },
    });

    expect(payload?['commandId'], 'command-1');
    expect(extractPresenterRemoteCommandPayload({'action': 'next'}), isNull);
  });
}
