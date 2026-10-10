import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../app/responsive.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../../../data/remote/supabase_service.dart';
import '../../../../domain/models/collaboration.dart';
import '../../../export/data/export_file_saver.dart';
import '../../domain/crdt_primitives.dart';
import '../../domain/sync_models.dart';
import '../../state/collaboration_session_provider.dart';

Future<void> showCollaboratorsPanel(
  BuildContext context, {
  required String projectId,
}) async {
  await showUiDialog(
    context: context,
    builder: (_) => CollaboratorsPanel(projectId: projectId),
  );
}

class CollaboratorsPanel extends ConsumerWidget {
  final String projectId;

  const CollaboratorsPanel({super.key, required this.projectId});

  String _displayName(CanvasMember member) {
    final name = member.displayName.trim();
    if (name.isNotEmpty) return name;
    if (member.userId.length <= 10) return member.userId;
    return '${member.userId.substring(0, 8)}…';
  }

  String _activityLabel(CanvasMember member) {
    if (member.online) return member.cursorActive ? 'Editing now' : 'Online';
    final lastSeen = member.lastSeenAt;
    if (lastSeen == null) return 'Offline';
    final age = DateTime.now().difference(lastSeen.toLocal());
    if (age.inMinutes < 1) return 'Seen just now';
    if (age.inHours < 1) return 'Seen ${age.inMinutes}m ago';
    if (age.inDays < 1) return 'Seen ${age.inHours}h ago';
    return 'Seen ${age.inDays}d ago';
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String? role,
  ) async {
    if (role == null) return;
    try {
      await ref
          .read(collaborationSessionProvider(projectId).notifier)
          .changeMemberRole(
            userId: userId,
            role: CollaborationRole.fromWire(role),
          );
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        error is SyncException
            ? error.message
            : 'Could not update member role.',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    CanvasMember member,
  ) async {
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Remove collaborator',
        constraints: AppResponsive.dialogConstraints(
          dialogContext,
          maxWidth: 420,
          maxHeight: 240,
        ),
        builder: (context, style) => Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Remove member?', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${_displayName(member)} will lose access to this collaboration room.',
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(collaborationSessionProvider(projectId).notifier)
          .removeMember(member.userId);
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        error is SyncException ? error.message : 'Could not remove member.',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _requestFollow(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    try {
      await ref
          .read(collaborationSessionProvider(projectId).notifier)
          .requestFollow(userId);
      if (!context.mounted) return;
      showUiToast(context, 'Follow request sent.');
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        error is SyncException ? error.message : 'Could not request follow.',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _respondToFollow(
    BuildContext context,
    WidgetRef ref,
    CollaborationControlEvent request,
    bool approved,
  ) async {
    try {
      await ref
          .read(collaborationSessionProvider(projectId).notifier)
          .respondToFollow(request: request, approved: approved);
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        error is SyncException ? error.message : 'Could not respond to follow.',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _requestScreenShare(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    try {
      await ref
          .read(collaborationSessionProvider(projectId).notifier)
          .requestScreenShare(userId);
      if (!context.mounted) return;
      showUiToast(context, 'Screen tracking request sent.');
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        error is SyncException
            ? error.message
            : 'Could not request screen tracking.',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _editDisplayName(
    BuildContext context,
    WidgetRef ref,
    CanvasMember member,
  ) async {
    final controller = TextEditingController(text: _displayName(member));
    final nextName = await showUiDialog<String>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Edit display name',
        constraints: AppResponsive.dialogConstraints(
          dialogContext,
          maxWidth: 420,
          maxHeight: 300,
        ),
        builder: (context, style) => Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit display name', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              UiTextField(
                controller: controller,
                label: 'Display name',
                hint: 'Example: Amber Fox 42',
                autofocus: true,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                inputFormatters: const [],
                onSubmitted: (value) => Navigator.of(context).pop(value),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    onPressed: () => Navigator.of(context).pop(controller.text),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (nextName == null || !context.mounted) return;
    try {
      await ref
          .read(collaborationSessionProvider(projectId).notifier)
          .updateDisplayName(nextName);
      if (context.mounted) {
        showUiToast(context, 'Display name updated.');
      }
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        error is SyncException
            ? error.message
            : 'Could not update display name.',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _respondToScreenShare(
    BuildContext context,
    WidgetRef ref,
    CollaborationControlEvent request,
    bool approved,
  ) async {
    try {
      await ref
          .read(collaborationSessionProvider(projectId).notifier)
          .respondToScreenShare(request: request, approved: approved);
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        error is SyncException
            ? error.message
            : 'Could not respond to screen tracking.',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _retrySync(
    BuildContext context,
    WidgetRef ref, {
    String? operationId,
  }) async {
    try {
      final controller = ref.read(
        collaborationSessionProvider(projectId).notifier,
      );
      if (operationId == null) {
        await controller.retryPendingOperations();
      } else {
        await controller.retryPendingOperation(operationId);
      }
      if (!context.mounted) return;
      final syncState = ref.read(collaborationSessionProvider(projectId));
      showUiToast(
        context,
        syncState.syncStatus == CollaborationSyncStatus.failed
            ? 'Sync failed. Changes remain local.'
            : operationId == null
            ? 'Sync retry finished.'
            : 'Operation retry finished.',
        variant: syncState.syncStatus == CollaborationSyncStatus.failed
            ? UiToastVariant.error
            : UiToastVariant.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        error is SyncException ? error.message : 'Could not retry sync.',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _exportRecoveryBundle(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final json = ref
          .read(collaborationSessionProvider(projectId).notifier)
          .exportRecoveryBundle();
      final outcome = await ExportFileSaver().save(
        fileName: 'varian-$projectId-recovery.json',
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
        dialogTitle: 'Export collaboration recovery bundle',
      );
      if (!context.mounted) return;
      showUiToast(
        context,
        outcome == ExportSaveOutcome.canceled
            ? 'Recovery export canceled.'
            : 'Recovery bundle exported.',
      );
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        error is SyncException
            ? error.message
            : 'Could not export recovery bundle.',
        variant: UiToastVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    final collaboration = ref.watch(collaborationSessionProvider(projectId));
    final pendingDetails = ref
        .read(collaborationSessionProvider(projectId).notifier)
        .pendingOperationDetails;
    final screenTrackingFailed =
        collaboration.screenTracking.status == ScreenTrackingStatus.error;
    final members = collaboration.members.values.toList()
      ..sort((a, b) {
        if (a.role == 'owner' && b.role != 'owner') return -1;
        if (b.role == 'owner' && a.role != 'owner') return 1;
        if (a.online != b.online) return a.online ? -1 : 1;
        return _displayName(
          a,
        ).toLowerCase().compareTo(_displayName(b).toLowerCase());
      });

    final maxWidth = AppResponsive.dialogWidth(context, preferred: 560);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 720);
    return UiDialog(
      semanticsLabel: 'Collaboration members',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('COLLABORATORS', style: style.titleTextStyle),
                  ),
                  UiBadge(
                    '${collaboration.participantCount} online',
                    variant: UiBadgeVariant.secondary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${members.length} member${members.length == 1 ? '' : 's'} · ${collaboration.role.label}',
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                      if (collaboration.pendingOperations > 0 ||
                          collaboration.syncStatus !=
                              CollaborationSyncStatus.synced) ...[
                        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                        UiSurface(
                          color:
                              collaboration.syncStatus ==
                                  CollaborationSyncStatus.failed
                              ? tokens.danger.withValues(alpha: 0.12)
                              : tokens.panelElevated,
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          borderColor: tokens.panelBorder,
                          borderWidth: AppBorder.thin,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              UiAlert(
                                title: _syncStatusLabel(collaboration),
                                icon:
                                    collaboration.syncStatus ==
                                        CollaborationSyncStatus.conflicted
                                    ? Icons.warning_amber_outlined
                                    : Icons.cloud_outlined,
                                variant: switch (collaboration.syncStatus) {
                                  CollaborationSyncStatus.failed =>
                                    UiAlertVariant.destructive,
                                  CollaborationSyncStatus.conflicted =>
                                    UiAlertVariant.warning,
                                  CollaborationSyncStatus.syncing =>
                                    UiAlertVariant.info,
                                  CollaborationSyncStatus.synced =>
                                    UiAlertVariant.success,
                                  CollaborationSyncStatus.savedLocally ||
                                  CollaborationSyncStatus.paused =>
                                    UiAlertVariant.warning,
                                },
                                liveRegion: true,
                              ),
                              if (pendingDetails.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Pending operations',
                                  style: Theme.of(context).textTheme.labelSmall!
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                for (final operation in pendingDetails.take(5))
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppSpacing.xs - AppSpacing.xxs,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _operationLabel(operation),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall!
                                                .copyWith(
                                                  color: tokens.textMuted,
                                                ),
                                          ),
                                        ),
                                        UiButton(
                                          variant: UiButtonVariant.ghost,
                                          size: UiButtonSize.sm,
                                          onPressed: () => _retrySync(
                                            context,
                                            ref,
                                            operationId: operation.opId,
                                          ),
                                          child: const Text('Retry'),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (pendingDetails.length > 5)
                                  Text(
                                    '+ ${pendingDetails.length - 5} more operation${pendingDetails.length - 5 == 1 ? '' : 's'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall!
                                        .copyWith(color: tokens.textMuted),
                                  ),
                              ],
                              const SizedBox(
                                height: AppSpacing.xs + AppSpacing.xxs,
                              ),
                              Wrap(
                                spacing: AppSpacing.xs + AppSpacing.xxs,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  if (pendingDetails.isNotEmpty ||
                                      collaboration.syncStatus ==
                                          CollaborationSyncStatus.failed)
                                    UiButton(
                                      variant: UiButtonVariant.ghost,
                                      size: UiButtonSize.sm,
                                      onPressed: () => _retrySync(context, ref),
                                      child: const Text('Retry sync'),
                                    ),
                                  UiButton(
                                    variant: UiButtonVariant.ghost,
                                    size: UiButtonSize.sm,
                                    onPressed: () =>
                                        _exportRecoveryBundle(context, ref),
                                    child: const Text('Export recovery'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (collaboration.conflicts.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                        UiSurface(
                          color: tokens.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          borderColor: tokens.panelBorder,
                          borderWidth: AppBorder.thin,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Conflicting edits',
                                style: Theme.of(context).textTheme.titleSmall!
                                    .copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(
                                height: AppSpacing.xs + AppSpacing.xxs,
                              ),
                              Text(
                                'Local edits are still on this device. Remote edits came from another collaborator. Choose which value to keep, or merge them before retrying sync.',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall!.copyWith(fontSize: 11),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              for (final conflict
                                  in collaboration.conflicts) ...[
                                Text(
                                  conflict.description,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                const SizedBox(
                                  height: AppSpacing.xs + AppSpacing.xxs,
                                ),
                                Wrap(
                                  spacing: AppSpacing.xs + AppSpacing.xxs,
                                  runSpacing: AppSpacing.xs + AppSpacing.xxs,
                                  children: [
                                    _conflictAction(
                                      ref,
                                      conflict.id,
                                      ConflictResolutionChoice.keepLocal,
                                      'Keep local',
                                    ),
                                    _conflictAction(
                                      ref,
                                      conflict.id,
                                      ConflictResolutionChoice.keepRemote,
                                      'Keep remote',
                                    ),
                                    _conflictAction(
                                      ref,
                                      conflict.id,
                                      ConflictResolutionChoice.merge,
                                      'Merge',
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                      if (collaboration.followRequest != null) ...[
                        UiSurface(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          borderColor: tokens.panelBorder,
                          borderWidth: AppBorder.thin,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              const Icon(Icons.visibility_outlined, size: 18),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '${collaboration.followRequest!.payload['requesterName'] ?? 'A collaborator'} wants to follow your viewport.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              UiIconButton(
                                icon: Icons.check,
                                tooltip: 'Approve follow',
                                onPressed: () => _respondToFollow(
                                  context,
                                  ref,
                                  collaboration.followRequest!,
                                  true,
                                ),
                              ),
                              UiIconButton(
                                icon: Icons.close,
                                tooltip: 'Reject follow',
                                onPressed: () => _respondToFollow(
                                  context,
                                  ref,
                                  collaboration.followRequest!,
                                  false,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (collaboration.followingUserId != null) ...[
                        UiSurface(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          bordered: false,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.visibility_outlined, size: 16),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Following a collaborator viewport.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              UiButton(
                                variant: UiButtonVariant.ghost,
                                size: UiButtonSize.sm,
                                onPressed: () => ref
                                    .read(
                                      collaborationSessionProvider(
                                        projectId,
                                      ).notifier,
                                    )
                                    .stopFollowing(),
                                child: const Text('Stop'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (collaboration.screenShareRequest != null) ...[
                        UiSurface(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          borderColor: tokens.panelBorder,
                          borderWidth: AppBorder.thin,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              const Icon(Icons.screen_share_outlined, size: 18),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '${collaboration.screenShareRequest!.payload['requesterName'] ?? 'A collaborator'} wants to view your screen. You must approve the OS/browser consent dialog.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              UiIconButton(
                                icon: Icons.check,
                                tooltip: 'Allow screen tracking',
                                onPressed: () => _respondToScreenShare(
                                  context,
                                  ref,
                                  collaboration.screenShareRequest!,
                                  true,
                                ),
                              ),
                              UiIconButton(
                                icon: Icons.close,
                                tooltip: 'Reject screen tracking',
                                onPressed: () => _respondToScreenShare(
                                  context,
                                  ref,
                                  collaboration.screenShareRequest!,
                                  false,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (collaboration.screenTracking.status ==
                              ScreenTrackingStatus.requesting ||
                          collaboration.screenTracking.status ==
                              ScreenTrackingStatus.awaitingConsent ||
                          collaboration.screenTracking.status ==
                              ScreenTrackingStatus.connecting ||
                          collaboration.screenTracking.status ==
                              ScreenTrackingStatus.sharing ||
                          collaboration.screenTracking.status ==
                              ScreenTrackingStatus.viewing ||
                          collaboration.screenTracking.status ==
                              ScreenTrackingStatus.error) ...[
                        UiSurface(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          bordered: false,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.screen_share_outlined,
                                    size: 16,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      screenTrackingFailed
                                          ? 'Screen tracking unavailable.'
                                          : 'Screen tracking active or awaiting consent.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                  if (!screenTrackingFailed)
                                    UiButton(
                                      variant: UiButtonVariant.ghost,
                                      size: UiButtonSize.sm,
                                      onPressed: () => ref
                                          .read(
                                            collaborationSessionProvider(
                                              projectId,
                                            ).notifier,
                                          )
                                          .stopScreenTracking(),
                                      child: const Text('Stop'),
                                    ),
                                ],
                              ),
                              if (collaboration.screenTracking.renderer !=
                                  null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                SizedBox(
                                  height: 190,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.control,
                                    ),
                                    child: RTCVideoView(
                                      collaboration.screenTracking.renderer!,
                                      objectFit: RTCVideoViewObjectFit
                                          .RTCVideoViewObjectFitContain,
                                    ),
                                  ),
                                ),
                              ],
                              if (collaboration.screenTracking.errorMessage !=
                                  null)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      collaboration
                                          .screenTracking
                                          .errorMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall!
                                          .copyWith(color: tokens.danger),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      'Follow viewport remains available as a lower-bandwidth fallback.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall!
                                          .copyWith(color: tokens.textMuted),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (members.isEmpty)
                        Text(
                          'No member profile is available yet.',
                          style: style.bodyTextStyle.copyWith(
                            color: tokens.textMuted,
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: members.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final controller = ref.read(
                              collaborationSessionProvider(projectId).notifier,
                            );
                            final isSelf =
                                member.userId == controller.localUserId;
                            final canManage =
                                collaboration.permissions.canManageMembers &&
                                !isSelf &&
                                member.role != CollaborationRole.owner.wireName;
                            return UiSurface(
                              color: tokens.panelElevated,
                              borderRadius: BorderRadius.circular(
                                AppRadius.panel,
                              ),
                              borderColor: tokens.panelBorder,
                              borderWidth: AppBorder.thin,
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final nameAndActivity = Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 17,
                                            backgroundColor: tokens.accent
                                                .withValues(alpha: 0.18),
                                            child: Text(
                                              _displayName(
                                                member,
                                              ).characters.first.toUpperCase(),
                                              style: TextStyle(
                                                color: tokens.accent,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(
                                            width:
                                                AppSpacing.sm + AppSpacing.xxs,
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _displayName(member),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(
                                                  height: AppSpacing.xxs,
                                                ),
                                                Text(
                                                  _activityLabel(member),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall!
                                                      .copyWith(
                                                        color: member.online
                                                            ? tokens.success
                                                            : tokens.textMuted,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                      final memberActions = <Widget>[
                                        if (isSelf)
                                          UiIconButton(
                                            tooltip: 'Edit display name',
                                            icon: Icons.edit_outlined,
                                            onPressed: () => _editDisplayName(
                                              context,
                                              ref,
                                              member,
                                            ),
                                          ),
                                        if (canManage)
                                          SizedBox(
                                            width: 130,
                                            height:
                                                AppControlSize.minimumHitTarget,
                                            child: UiSelect<String>(
                                              value: member.role == 'owner'
                                                  ? 'editor'
                                                  : member.role,
                                              items: const {
                                                'Editor': 'editor',
                                                'Commenter': 'commenter',
                                                'Viewer': 'viewer',
                                              },
                                              onChanged: (value) => _changeRole(
                                                context,
                                                ref,
                                                member.userId,
                                                value,
                                              ),
                                            ),
                                          )
                                        else
                                          Padding(
                                            padding: const EdgeInsets.all(
                                              AppSpacing.sm,
                                            ),
                                            child: Text(
                                              member.collaborationRole.label,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall!
                                                  .copyWith(
                                                    color: tokens.textMuted,
                                                  ),
                                            ),
                                          ),
                                        if (canManage)
                                          UiIconButton(
                                            tooltip: 'Remove member',
                                            icon: Icons.person_remove_outlined,
                                            onPressed: () => _removeMember(
                                              context,
                                              ref,
                                              member,
                                            ),
                                          ),
                                        if (!isSelf && member.online)
                                          UiIconButton(
                                            tooltip:
                                                collaboration.followingUserId ==
                                                    member.userId
                                                ? 'Stop following'
                                                : 'Request viewport follow',
                                            icon:
                                                collaboration.followingUserId ==
                                                    member.userId
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                            onPressed: () =>
                                                collaboration.followingUserId ==
                                                    member.userId
                                                ? ref
                                                      .read(
                                                        collaborationSessionProvider(
                                                          projectId,
                                                        ).notifier,
                                                      )
                                                      .stopFollowing()
                                                : _requestFollow(
                                                    context,
                                                    ref,
                                                    member.userId,
                                                  ),
                                          ),
                                        if (!isSelf && member.online)
                                          UiIconButton(
                                            tooltip: 'Request screen tracking',
                                            icon: Icons.screen_share_outlined,
                                            onPressed: () =>
                                                _requestScreenShare(
                                                  context,
                                                  ref,
                                                  member.userId,
                                                ),
                                          ),
                                      ];
                                      if (constraints.maxWidth < 360) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            nameAndActivity,
                                            const SizedBox(
                                              height: AppSpacing.sm,
                                            ),
                                            Wrap(
                                              spacing: AppSpacing.xxs,
                                              runSpacing: AppSpacing.xxs,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: memberActions,
                                            ),
                                          ],
                                        );
                                      }
                                      return Row(
                                        children: [
                                          Expanded(child: nameAndActivity),
                                          ...memberActions,
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  variant: UiButtonVariant.ghost,
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _syncStatusLabel(
    CollaborationSessionState state,
  ) => switch (state.syncStatus) {
    CollaborationSyncStatus.synced => 'All changes are synced.',
    CollaborationSyncStatus.savedLocally =>
      '${state.pendingOperations} change${state.pendingOperations == 1 ? '' : 's'} saved locally.',
    CollaborationSyncStatus.syncing => 'Syncing changes…',
    CollaborationSyncStatus.conflicted => 'Resolve conflicting edits.',
    CollaborationSyncStatus.failed => 'Sync failed. Changes remain local.',
    CollaborationSyncStatus.paused => 'Sync is paused.',
  };

  String _operationLabel(CrdtOperation operation) {
    final readableKind = operation.kind.name
        .replaceAllMapped(
          RegExp(r'([A-Z])'),
          (match) => ' ${match.group(1)!.toLowerCase()}',
        )
        .trim();
    final target = operation.targetId.length > 28
        ? '${operation.targetId.substring(0, 25)}…'
        : operation.targetId;
    final field = operation.field == null ? '' : '.${operation.field}';
    return '$readableKind · $target$field';
  }

  Widget _conflictAction(
    WidgetRef ref,
    String conflictId,
    ConflictResolutionChoice choice,
    String label,
  ) => UiButton(
    variant: UiButtonVariant.ghost,
    size: UiButtonSize.sm,
    onPressed: () => ref
        .read(collaborationSessionProvider(projectId).notifier)
        .resolveConflict(conflictId, choice),
    child: Text(label),
  );
}
