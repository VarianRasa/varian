import 'package:flutter/material.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../domain/meeting_models.dart';

class MeetingParticipantsPanel extends StatelessWidget {
  const MeetingParticipantsPanel({
    required this.state,
    this.onRemoveParticipant,
    super.key,
  });

  final MeetingState state;
  final Future<void> Function(String identity)? onRemoveParticipant;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final participants = state.participants.values.toList(growable: false);
    return Semantics(
      container: true,
      label: 'Meeting participants, ${participants.length}',
      child: UiSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Participants',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: tokens.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                UiBadge('${participants.length}'),
              ],
            ),
            Expanded(
              child: participants.isEmpty
                  ? const UiEmptyState(
                      icon: Icons.groups_outlined,
                      title: 'No participants yet',
                      message: 'Other meeting participants will appear here.',
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: participants.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) =>
                          _participantRow(context, participants[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _participantRow(BuildContext context, MeetingParticipant participant) {
    final tokens = context.appTokens;
    final canRemove =
        state.isHost &&
        !participant.isLocal &&
        onRemoveParticipant != null &&
        _validIdentity(participant.identity);
    return UiSurface(
      key: ValueKey('participant-${participant.identity}-row'),
      color: tokens.panelElevated,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: tokens.accentSoft,
            foregroundColor: tokens.text,
            child: Text(
              _initials(participant.displayName, participant.identity),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.displayName.isEmpty
                      ? participant.identity
                      : participant.displayName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  participant.isHost ? 'Host' : participant.role.toWire(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          if (canRemove)
            UiIconButton(
              icon: Icons.person_remove_outlined,
              tooltip: 'Remove participant',
              size: UiButtonSize.xs,
              onPressed: () => onRemoveParticipant!(participant.identity),
            ),
        ],
      ),
    );
  }

  static bool _validIdentity(String value) =>
      value.trim().isNotEmpty &&
      !value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

  static String _initials(String displayName, String identity) {
    final value = displayName.trim().isEmpty
        ? identity.trim()
        : displayName.trim();
    if (value.isEmpty) return '?';
    final parts = value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
