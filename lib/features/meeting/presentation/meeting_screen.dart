import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/responsive.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../data/meeting_configuration.dart';
import '../data/meeting_media_port.dart';
import '../domain/meeting_models.dart';
import '../state/meeting_controller.dart';
import 'widgets/meeting_participants_panel.dart';
import 'widgets/meeting_toolbar.dart';
import 'widgets/participant_tile.dart';

final meetingSelectedParticipantProvider = StateProvider.autoDispose
    .family<String?, String>((ref, projectId) => null);
final meetingRemoveInFlightProvider = StateProvider.autoDispose
    .family<String?, String>((ref, projectId) => null);

class MeetingScreen extends ConsumerWidget {
  const MeetingScreen({
    required this.meetingId,
    required this.projectId,
    this.media,
    super.key,
  });
  final String meetingId;
  final String projectId;
  final MeetingMediaPort? media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configuration = ref.watch(meetingConfigurationProvider);
    if (!_validRoute(configuration, meetingId, projectId)) {
      return const UiPageScaffold(
        title: SizedBox.shrink(),
        showHeader: false,
        child: _StageMessage(
          icon: Icons.error_outline,
          message: 'This meeting link is invalid or unavailable.',
        ),
      );
    }
    final state = ref.watch(meetingControllerProvider(projectId));
    if (state.meetingId != null && state.meetingId != meetingId) {
      return const UiPageScaffold(
        title: SizedBox.shrink(),
        showHeader: false,
        child: _StageMessage(
          icon: Icons.error_outline,
          message: 'This meeting belongs to another meeting link.',
        ),
      );
    }
    final controller = ref.read(meetingControllerProvider(projectId).notifier);
    final MeetingMediaPort mediaPort =
        media ?? ref.watch(meetingMediaPortProvider(projectId));
    final selectedIdentity = ref.watch(
      meetingSelectedParticipantProvider(projectId),
    );
    final displayState = _withLocalParticipant(state, mediaPort);
    final active =
        state.status == MeetingStatus.connected ||
        state.status == MeetingStatus.reconnecting;
    final mediaControlsActive =
        state.status == MeetingStatus.connected && state.canPublish;
    return UiPageScaffold(
      title: const Text('Video meeting'),
      leading: UiIconButton(
        icon: Icons.arrow_back,
        tooltip: 'Back to meeting entry',
        size: UiButtonSize.xs,
        onPressed: () => context.pop(),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _statusBanner(context, state),
            Expanded(
              child: _body(
                context,
                ref,
                displayState,
                controller,
                selectedIdentity,
                mediaPort,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: MeetingToolbar(
                state: state,
                canPublish: mediaControlsActive,
                isLoading:
                    state.status == MeetingStatus.creating ||
                    state.status == MeetingStatus.joining ||
                    state.actionInFlight,
                onToggleMicrophone: mediaControlsActive
                    ? controller.toggleMicrophone
                    : null,
                onToggleCamera: mediaControlsActive
                    ? controller.toggleCamera
                    : null,
                onToggleScreenShare: mediaControlsActive
                    ? controller.toggleScreenShare
                    : null,
                onParticipants: () =>
                    _showParticipants(context, displayState, controller, ref),
                onLeave: active
                    ? () => _confirmLeave(context, controller)
                    : null,
                onEnd: active && state.isHost
                    ? () => _confirmEnd(context, controller)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    MeetingState state,
    MeetingController controller,
    String? selectedIdentity,
    MeetingMediaPort media,
  ) {
    final grid = _participantGrid(context, ref, state, selectedIdentity, media);
    if (context.isNarrowLayout) {
      return Padding(padding: const EdgeInsets.all(AppSpacing.md), child: grid);
    }
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: grid,
          ),
        ),
        if (!context.isCompactLayout)
          SizedBox(
            width: 280,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: MeetingParticipantsPanel(
                state: state,
                onRemoveParticipant: state.isHost
                    ? (identity) =>
                          _confirmRemove(context, controller, ref, identity)
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _participantGrid(
    BuildContext context,
    WidgetRef ref,
    MeetingState state,
    String? selectedIdentity,
    MeetingMediaPort media,
  ) {
    final participants = state.participants.values.toList(growable: false);
    if (state.status == MeetingStatus.ended) {
      return _StageMessage(
        icon: Icons.stop_circle_outlined,
        message: _terminalMessage(state),
      );
    }
    if (state.status == MeetingStatus.error) {
      return _StageMessage(
        icon: Icons.error_outline,
        message: state.terminationReason == null
            ? (state.errorMessage ?? 'Video meeting is unavailable.')
            : _terminalMessage(state),
      );
    }
    if (participants.isEmpty) {
      return const _StageMessage(
        icon: Icons.groups_outlined,
        message: 'Waiting for participants to join.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < AppBreakpoints.medium
            ? 1
            : width < AppBreakpoints.expanded
            ? 2
            : 3;
        return GridView.builder(
          key: const Key('meeting-participant-grid'),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.45,
          ),
          itemCount: participants.length,
          itemBuilder: (context, index) {
            final participant = participants[index];
            return ParticipantTile(
              participant: participant,
              media: media,
              selected: selectedIdentity == participant.identity,
              pinned: selectedIdentity == participant.identity,
              onTap: () =>
                  ref
                      .read(
                        meetingSelectedParticipantProvider(projectId).notifier,
                      )
                      .state = selectedIdentity == participant.identity
                  ? null
                  : participant.identity,
            );
          },
        );
      },
    );
  }

  Future<void> _showParticipants(
    BuildContext context,
    MeetingState state,
    MeetingController controller,
    WidgetRef ref,
  ) => showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: MeetingParticipantsPanel(
          state: state,
          onRemoveParticipant: state.isHost
              ? (identity) => _confirmRemove(context, controller, ref, identity)
              : null,
        ),
      ),
    ),
  );

  Future<void> _confirmRemove(
    BuildContext context,
    MeetingController controller,
    WidgetRef ref,
    String identity,
  ) async {
    if (!context.mounted ||
        identity.isEmpty ||
        identity.startsWith('local:') ||
        ref.read(meetingRemoveInFlightProvider(projectId)) != null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    ref.read(meetingRemoveInFlightProvider(projectId).notifier).state =
        identity;
    try {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => UiDialog(
              semanticsLabel: 'Remove participant',
              constraints: AppResponsive.dialogConstraints(
                context,
                maxWidth: 420,
                maxHeight: 260,
              ),
              builder: (context, style) => Padding(
                padding: AppResponsive.dialogPadding(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Remove participant?', style: style.titleTextStyle),
                    const SizedBox(height: AppSpacing.md - AppSpacing.xxs),
                    Text(
                      'This participant will be disconnected from the meeting.',
                      style: style.bodyTextStyle,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        UiButton(
                          onPressed: () => Navigator.pop(context, false),
                          variant: UiButtonVariant.ghost,
                          size: UiButtonSize.xs,
                          child: const Text('Cancel'),
                        ),
                        UiButton(
                          onPressed: () => Navigator.pop(context, true),
                          variant: UiButtonVariant.destructive,
                          size: UiButtonSize.xs,
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ) ??
          false;
      if (confirmed) {
        await controller.removeParticipant(identity);
      }
    } finally {
      if (context.mounted) {
        ref.read(meetingRemoveInFlightProvider(projectId).notifier).state =
            null;
      }
    }
  }

  Future<void> _confirmLeave(
    BuildContext context,
    MeetingController controller,
  ) async {
    final confirmed = await _confirm(
      context,
      'Leave meeting?',
      'You will leave this meeting. The meeting will continue for others.',
      'Leave',
    );
    if (confirmed) {
      await controller.leave();
    }
    if (confirmed && context.mounted) context.pop();
  }

  Future<void> _confirmEnd(
    BuildContext context,
    MeetingController controller,
  ) async {
    if (!await _confirm(
      context,
      'End meeting for everyone?',
      'This permanently ends the meeting for all participants.',
      'End meeting',
    )) {
      return;
    }
    await controller.endForEveryone();
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
    String label,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => UiDialog(
          semanticsLabel: title,
          constraints: AppResponsive.dialogConstraints(
            context,
            maxWidth: 420,
            maxHeight: 260,
          ),
          builder: (context, style) => Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: style.titleTextStyle),
                const SizedBox(height: AppSpacing.md - AppSpacing.xxs),
                Text(message, style: style.bodyTextStyle),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    UiButton(
                      onPressed: () => Navigator.pop(context, false),
                      variant: UiButtonVariant.ghost,
                      size: UiButtonSize.xs,
                      child: const Text('Cancel'),
                    ),
                    UiButton(
                      onPressed: () => Navigator.pop(context, true),
                      variant: label == 'End meeting'
                          ? UiButtonVariant.destructive
                          : UiButtonVariant.primary,
                      size: UiButtonSize.xs,
                      child: Text(label),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;

  Widget _statusBanner(BuildContext context, MeetingState state) {
    final tokens = context.appTokens;
    final reconnecting = state.status == MeetingStatus.reconnecting;
    final loading =
        state.status == MeetingStatus.creating ||
        state.status == MeetingStatus.joining;
    final message = state.errorMessage;
    if (!reconnecting && !loading && message == null) {
      return const SizedBox.shrink();
    }
    if (loading) {
      return const UiLinearProgressIndicator(height: 2);
    }
    final color = reconnecting ? tokens.warning : tokens.danger;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: UiSurface(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        color: color.withValues(alpha: 0.08),
        borderColor: color.withValues(alpha: 0.28),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(
                reconnecting ? Icons.sync : Icons.error_outline,
                size: 18,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  reconnecting
                      ? 'Reconnecting to the video service…'
                      : message!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _terminalMessage(MeetingState state) =>
    switch (state.terminationReason) {
      MeetingTerminationReason.removed => 'Anda dikeluarkan dari meeting.',
      MeetingTerminationReason.roomRevoked =>
        'Akses meeting dihentikan oleh ruang kolaborasi.',
      MeetingTerminationReason.expired => 'Meeting ini sudah kedaluwarsa.',
      MeetingTerminationReason.providerError =>
        'Layanan video sedang tidak tersedia. Coba lagi.',
      MeetingTerminationReason.ended ||
      null => 'Meeting sudah diakhiri oleh host.',
    };

MeetingState _withLocalParticipant(MeetingState state, MeetingMediaPort media) {
  if (state.status != MeetingStatus.connected &&
      state.status != MeetingStatus.reconnecting) {
    return state;
  }
  final providerIdentity = media.localIdentity?.trim();
  final identity = providerIdentity == null || providerIdentity.isEmpty
      ? 'local:${state.projectId}'
      : providerIdentity;
  final participants = {...state.participants};
  final syntheticIdentity = 'local:${state.projectId}';
  if (identity != syntheticIdentity &&
      participants[syntheticIdentity]?.isLocal == true) {
    participants.remove(syntheticIdentity);
  }
  if (participants.containsKey(identity)) {
    return participants.length == state.participants.length
        ? state
        : state.copyWith(participants: participants);
  }
  participants[identity] = MeetingParticipant(
    identity: identity,
    displayName: 'You',
    role: state.isHost
        ? MeetingParticipantRole.host
        : state.canPublish
        ? MeetingParticipantRole.publisher
        : MeetingParticipantRole.viewer,
    isLocal: true,
    microphoneEnabled: state.localMicrophoneEnabled,
    cameraEnabled: state.localCameraEnabled,
    screenShareEnabled: state.localScreenShareEnabled,
  );
  return state.copyWith(participants: participants);
}

bool _validRoute(
  MeetingConfiguration configuration,
  String meetingId,
  String projectId,
) {
  const hex = '0123456789abcdefABCDEF';
  const projectChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~-';
  final uuidShape =
      meetingId.length == 36 &&
      meetingId[8] == '-' &&
      meetingId[13] == '-' &&
      meetingId[18] == '-' &&
      meetingId[23] == '-' &&
      '12345'.contains(meetingId[14]) &&
      '89abAB'.contains(meetingId[19]);
  final uuidChars =
      uuidShape &&
      meetingId.codeUnits.every(
        (unit) => unit == 45 || hex.contains(String.fromCharCode(unit)),
      );
  final projectValid =
      projectId.isNotEmpty &&
      projectId.length <= 128 &&
      projectId.codeUnits.every(
        (unit) => projectChars.contains(String.fromCharCode(unit)),
      );
  return configuration.isAvailable && uuidChars && projectValid;
}

class _StageMessage extends StatelessWidget {
  const _StageMessage({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final isError = icon == Icons.error_outline;
    final color = isError ? tokens.danger : tokens.accent;
    return Center(
      child: Padding(
        padding: AppResponsive.pagePadding(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Semantics(
            liveRegion: true,
            label: message,
            child: UiSurface(
              color: tokens.panelElevated,
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 42, color: color),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium!.copyWith(color: tokens.text),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
