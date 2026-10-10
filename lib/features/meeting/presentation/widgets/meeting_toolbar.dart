import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../domain/meeting_models.dart';

class MeetingToolbar extends StatelessWidget {
  const MeetingToolbar({
    required this.state,
    this.onToggleMicrophone,
    this.onToggleCamera,
    this.onToggleScreenShare,
    this.onParticipants,
    this.onLeave,
    this.onEnd,
    this.canPublish = true,
    this.isLoading = false,
    super.key,
  });

  final MeetingState state;
  final FutureOr<void> Function()? onToggleMicrophone;
  final FutureOr<void> Function()? onToggleCamera;
  final FutureOr<void> Function()? onToggleScreenShare;
  final VoidCallback? onParticipants;
  final FutureOr<void> Function()? onLeave;
  final FutureOr<void> Function()? onEnd;
  final bool canPublish;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final active =
        state.status == MeetingStatus.connected ||
        state.status == MeetingStatus.reconnecting;
    final busy = isLoading || state.actionInFlight;
    final controlsActive = active && !busy;
    final mediaControlsActive =
        state.status == MeetingStatus.connected && !busy && canPublish;
    final canLeave = controlsActive && onLeave != null;
    final canEnd = controlsActive && state.isHost && onEnd != null;
    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Semantics(
        container: true,
        label: 'Meeting controls',
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _control(
              context,
              label: state.localMicrophoneEnabled
                  ? 'Mute microphone'
                  : 'Unmute microphone',
              icon: state.localMicrophoneEnabled
                  ? Icons.mic
                  : Icons.mic_off_outlined,
              onPressed: mediaControlsActive ? onToggleMicrophone : null,
            ),
            _control(
              context,
              label: state.localCameraEnabled
                  ? 'Turn camera off'
                  : 'Turn camera on',
              icon: state.localCameraEnabled
                  ? Icons.videocam
                  : Icons.videocam_off_outlined,
              onPressed: mediaControlsActive ? onToggleCamera : null,
            ),
            _control(
              context,
              label: state.localScreenShareEnabled
                  ? 'Stop screen sharing'
                  : 'Start screen sharing',
              icon: state.localScreenShareEnabled
                  ? Icons.stop_screen_share_outlined
                  : Icons.screen_share_outlined,
              onPressed: mediaControlsActive ? onToggleScreenShare : null,
            ),
            _control(
              context,
              label: 'Show participants',
              icon: Icons.people_outline,
              onPressed: controlsActive ? onParticipants : null,
            ),
            _control(
              context,
              label: 'Leave meeting',
              icon: Icons.call_end_outlined,
              onPressed: canLeave ? onLeave : null,
              color: Theme.of(context).colorScheme.error,
            ),
            if (state.isHost)
              _control(
                context,
                label: 'End meeting for everyone',
                icon: Icons.stop_circle_outlined,
                onPressed: canEnd ? onEnd : null,
                color: Theme.of(context).colorScheme.error,
              ),
            if (state.status == MeetingStatus.reconnecting)
              const UiBadge('Reconnecting', variant: UiBadgeVariant.warning),
            if (state.errorMessage != null)
              UiBadge('Connection issue', variant: UiBadgeVariant.destructive),
          ],
        ),
      ),
    );
  }

  Widget _control(
    BuildContext context, {
    required String label,
    required IconData icon,
    required FutureOr<void> Function()? onPressed,
    Color? color,
  }) => UiIconButton(
    icon: icon,
    tooltip: label,
    onPressed: onPressed == null ? null : () => onPressed(),
    color: color,
    size: UiButtonSize.lg,
  );
}
