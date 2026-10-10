import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

import '../../../../app/widgets/ui_primitives.dart';
import '../../data/meeting_media_port.dart';
import '../../domain/meeting_models.dart';

class ParticipantTile extends StatelessWidget {
  const ParticipantTile({
    required this.participant,
    this.media,
    this.videoSource,
    this.selected = false,
    this.pinned = false,
    this.onTap,
    super.key,
  });

  final MeetingParticipant participant;
  final MeetingMediaPort? media;
  final MeetingVideoSource? videoSource;
  final bool selected;
  final bool pinned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final initials = _initials(participant.displayName, participant.identity);
    final colorScheme = Theme.of(context).colorScheme;
    final videoSurface = _buildVideoSurface();
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: _semanticsLabel(),
      child: UiSurface(
        key: ValueKey('participant-${participant.identity}-tile'),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(tokens.panelRadius),
        borderColor: participant.isSpeaking || selected
            ? tokens.accent
            : tokens.panelBorder,
        borderWidth: participant.isSpeaking || selected
            ? AppBorder.focus
            : AppBorder.thin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tokens.panelRadius),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  videoSurface ??
                      ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: CircleAvatar(
                            radius: 32,
                            child: Text(initials),
                          ),
                        ),
                      ),
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.sm + AppSpacing.xxs,
                    child: UiSurface(
                      color: tokens.panelElevated,
                      borderRadius: BorderRadius.circular(tokens.controlRadius),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs + AppSpacing.xxs,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              participant.displayName.isEmpty
                                  ? participant.identity
                                  : participant.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: tokens.text),
                            ),
                          ),
                          if (!participant.microphoneEnabled)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: AppSpacing.xs + AppSpacing.xxs,
                              ),
                              child: Icon(
                                Icons.mic_off_outlined,
                                size: 18,
                                color: tokens.text,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!participant.cameraEnabled)
                    const Positioned(
                      top: AppSpacing.sm + AppSpacing.xxs,
                      left: AppSpacing.sm + AppSpacing.xxs,
                      child: UiBadge(
                        'Camera off',
                        variant: UiBadgeVariant.warning,
                      ),
                    ),
                  if (participant.screenShareEnabled)
                    const Positioned(
                      top: AppSpacing.sm + AppSpacing.xxs,
                      right: AppSpacing.sm + AppSpacing.xxs,
                      child: UiBadge(
                        'Screen share',
                        variant: UiBadgeVariant.info,
                      ),
                    ),
                  if (pinned)
                    const Positioned(
                      bottom: 42,
                      right: AppSpacing.sm + AppSpacing.xxs,
                      child: Icon(Icons.push_pin_outlined, size: 18),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildVideoSurface() {
    final source =
        videoSource ??
        (participant.screenShareEnabled
            ? MeetingVideoSource.screenShare
            : participant.cameraEnabled
            ? MeetingVideoSource.camera
            : null);
    if (source == null ||
        (source == MeetingVideoSource.camera && !participant.cameraEnabled) ||
        (source == MeetingVideoSource.screenShare &&
            !participant.screenShareEnabled)) {
      return null;
    }
    final provider = media;
    if (provider == null) return null;
    try {
      final providerIdentity = provider.localIdentity?.trim();
      final identity =
          participant.isLocal &&
              providerIdentity != null &&
              providerIdentity.isNotEmpty
          ? providerIdentity
          : participant.identity;
      return provider.buildVideoSurface(
        MeetingVideoSurface(
          identity: identity,
          source: source,
          isLocal: participant.isLocal,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  String _semanticsLabel() {
    final name = participant.displayName.isEmpty
        ? participant.identity
        : participant.displayName;
    final states = <String>[
      participant.isLocal ? 'Local participant' : 'Remote participant',
      if (!participant.microphoneEnabled) 'microphone muted',
      if (!participant.cameraEnabled) 'camera off',
      if (participant.screenShareEnabled) 'screen sharing',
      if (participant.isSpeaking) 'speaking',
      if (pinned) 'pinned',
    ];
    return '$name, ${states.join(', ')}';
  }

  static String _initials(String displayName, String identity) {
    final source = displayName.trim().isEmpty
        ? identity.trim()
        : displayName.trim();
    final words = source
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '?';
    }
    if (words.length == 1) {
      return words.first.characters.take(2).toString().toUpperCase();
    }
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }
}
