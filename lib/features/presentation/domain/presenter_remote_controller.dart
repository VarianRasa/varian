import 'remote_presenter_control.dart';

enum PresenterRemoteCommandDisposition { applied, duplicate, rejected }

class PresenterRemoteCommandResult {
  final PresenterRemoteCommandDisposition disposition;
  final PresenterRemoteAction? action;
  final int frameIndex;
  final bool paused;
  final String? reason;

  const PresenterRemoteCommandResult({
    required this.disposition,
    required this.frameIndex,
    required this.paused,
    this.action,
    this.reason,
  });

  bool get applied => disposition == PresenterRemoteCommandDisposition.applied;
}

class PresenterRemoteCommandController {
  PresenterRemoteSession? _session;
  final Set<String> _appliedCommandIds = <String>{};
  late int _currentFrameIndex;
  late bool _paused;

  PresenterRemoteCommandController({
    PresenterRemoteSession? session,
    int currentFrameIndex = 0,
    bool paused = false,
  }) {
    _session = session;
    _currentFrameIndex = currentFrameIndex;
    _paused = paused;
  }

  PresenterRemoteSession? get session => _session;
  int get currentFrameIndex => _currentFrameIndex;
  bool get paused => _paused;

  void setSession(PresenterRemoteSession? session) {
    _session = session;
    if (session == null) _appliedCommandIds.clear();
  }

  void syncLocalFrame(int frameIndex, int frameCount) {
    if (frameCount <= 0) return;
    _currentFrameIndex = frameIndex.clamp(0, frameCount - 1).toInt();
  }

  PresenterRemoteCommandResult apply(
    PresenterRemoteCommand command, {
    required DateTime now,
    required int frameCount,
  }) {
    final session = _session;
    if (session == null || frameCount <= 0) {
      return _rejected('Presenter remote session is unavailable.');
    }
    if (_appliedCommandIds.contains(command.commandId)) {
      return _result(PresenterRemoteCommandDisposition.duplicate, command);
    }
    if (!command.isValidFor(session, now)) {
      return _rejected('Presenter remote command is expired or unauthorized.');
    }

    final nextIndex = switch (command.action) {
      PresenterRemoteAction.next =>
        (_currentFrameIndex + 1).clamp(0, frameCount - 1).toInt(),
      PresenterRemoteAction.previous =>
        (_currentFrameIndex - 1).clamp(0, frameCount - 1).toInt(),
      PresenterRemoteAction.jump =>
        command.frameIndex == null
            ? -1
            : command.frameIndex!.clamp(0, frameCount - 1).toInt(),
      _ => _currentFrameIndex,
    };
    if (nextIndex < 0) {
      return _rejected('Presenter remote jump is missing a frame index.');
    }

    switch (command.action) {
      case PresenterRemoteAction.pause:
        _paused = true;
      case PresenterRemoteAction.resume:
        _paused = false;
      case PresenterRemoteAction.stop:
        _session = session.copyWith(consentGranted: false);
      case PresenterRemoteAction.next:
      case PresenterRemoteAction.previous:
      case PresenterRemoteAction.jump:
        _currentFrameIndex = nextIndex;
    }
    _appliedCommandIds.add(command.commandId);
    return _result(PresenterRemoteCommandDisposition.applied, command);
  }

  PresenterRemoteCommandResult _rejected(String reason) =>
      PresenterRemoteCommandResult(
        disposition: PresenterRemoteCommandDisposition.rejected,
        frameIndex: _currentFrameIndex,
        paused: _paused,
        reason: reason,
      );

  PresenterRemoteCommandResult _result(
    PresenterRemoteCommandDisposition disposition,
    PresenterRemoteCommand command,
  ) => PresenterRemoteCommandResult(
    disposition: disposition,
    action: command.action,
    frameIndex: _currentFrameIndex,
    paused: _paused,
  );
}
