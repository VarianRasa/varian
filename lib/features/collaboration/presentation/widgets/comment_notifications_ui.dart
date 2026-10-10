import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import '../../domain/comment_notifications.dart';
import '../../state/collaboration_provider.dart';

IconData commentNotificationIcon(CommentNotificationType type) =>
    switch (type) {
      CommentNotificationType.mention => Icons.alternate_email_rounded,
      CommentNotificationType.reply => Icons.reply_rounded,
      CommentNotificationType.assignment => Icons.person_add_alt_1_rounded,
      CommentNotificationType.dueDate => Icons.event_outlined,
      CommentNotificationType.resolved => Icons.task_alt_rounded,
    };

String commentNotificationTypeLabel(CommentNotificationType type) =>
    switch (type) {
      CommentNotificationType.mention => 'Mention',
      CommentNotificationType.reply => 'Balasan',
      CommentNotificationType.assignment => 'Assignee',
      CommentNotificationType.dueDate => 'Due date',
      CommentNotificationType.resolved => 'Resolved',
    };

String _formatNotificationTime(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final date = MaterialLocalizations.of(context).formatShortDate(local);
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date · $time';
}

class CommentNotificationInboxButton extends ConsumerWidget {
  final String projectId;
  final String userId;
  final ValueChanged<CommentNotification>? onSelected;

  const CommentNotificationInboxButton({
    required this.projectId,
    required this.userId,
    this.onSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    final scope = CommentNotificationScope(
      projectId: projectId,
      userId: userId,
    );
    final state = ref.watch(commentNotificationsProvider(scope));
    final unreadCount = state.unreadCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        UiIconButton(
          key: const ValueKey('canvas-comment-notifications'),
          icon: unreadCount == 0
              ? Icons.notifications_none_outlined
              : Icons.notifications_active_outlined,
          tooltip: 'Notifikasi komentar',
          onPressed: () => showCommentNotificationInbox(
            context,
            projectId: projectId,
            userId: userId,
            onSelected: onSelected,
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 0,
            top: -2,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('canvas-comment-notifications-badge'),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: tokens.danger,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: tokens.panelElevated,
                    width: AppBorder.thin,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: tokens.accentForeground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> showCommentNotificationInbox(
  BuildContext context, {
  required String projectId,
  required String userId,
  ValueChanged<CommentNotification>? onSelected,
}) => showUiDialog<void>(
  context: context,
  builder: (_) => CommentNotificationInboxDialog(
    projectId: projectId,
    userId: userId,
    onSelected: onSelected,
  ),
);

class CommentNotificationInboxDialog extends ConsumerStatefulWidget {
  final String projectId;
  final String userId;
  final ValueChanged<CommentNotification>? onSelected;

  const CommentNotificationInboxDialog({
    required this.projectId,
    required this.userId,
    this.onSelected,
    super.key,
  });

  @override
  ConsumerState<CommentNotificationInboxDialog> createState() =>
      _CommentNotificationInboxDialogState();
}

class _CommentNotificationInboxDialogState
    extends ConsumerState<CommentNotificationInboxDialog> {
  bool _unreadOnly = false;

  CommentNotificationScope get _scope => CommentNotificationScope(
    projectId: widget.projectId,
    userId: widget.userId,
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commentNotificationsProvider(_scope));
    final notifier = ref.read(commentNotificationsProvider(_scope).notifier);
    final notifications = CommentNotificationCenter(
      state.notifications,
    ).filtered(unreadOnly: _unreadOnly);
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 560);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 520);

    return UiDialog(
      semanticsLabel: 'Comment notification inbox',
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
                  const Icon(Icons.notifications_none_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Notifikasi komentar',
                      style: style.titleTextStyle,
                    ),
                  ),
                  if (state.unreadCount > 0)
                    UiBadge('${state.unreadCount} baru'),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Tutup notifikasi komentar',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs + AppSpacing.xxs,
                runSpacing: AppSpacing.xs + AppSpacing.xxs,
                children: [
                  UiButton(
                    onPressed: () => setState(() => _unreadOnly = false),
                    variant: _unreadOnly
                        ? UiButtonVariant.outline
                        : UiButtonVariant.primary,
                    size: UiButtonSize.sm,
                    child: const Text('Semua'),
                  ),
                  UiButton(
                    onPressed: () => setState(() => _unreadOnly = true),
                    variant: _unreadOnly
                        ? UiButtonVariant.primary
                        : UiButtonVariant.outline,
                    size: UiButtonSize.sm,
                    child: const Text('Belum dibaca'),
                  ),
                  UiButton(
                    onPressed: state.unreadCount == 0
                        ? null
                        : () => unawaited(notifier.markAllRead()),
                    variant: UiButtonVariant.ghost,
                    size: UiButtonSize.sm,
                    child: const Text('Tandai semua'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              Expanded(
                child: _buildNotificationList(
                  dialogContext,
                  state: state,
                  notifications: notifications,
                  onSelected: (notification) {
                    unawaited(notifier.markRead(notification.id));
                    widget.onSelected?.call(notification);
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  variant: UiButtonVariant.ghost,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Tutup'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationList(
    BuildContext context, {
    required CommentNotificationInboxState state,
    required List<CommentNotification> notifications,
    required ValueChanged<CommentNotification> onSelected,
  }) {
    if (state.isLoading && state.notifications.isEmpty) {
      return const UiLoadingState(label: 'Memuat notifikasi komentar');
    }
    if (state.errorMessage != null && state.notifications.isEmpty) {
      return UiAlert(
        title: 'Notifikasi tidak dapat dimuat',
        description: state.errorMessage!,
        icon: Icons.error_outline,
        variant: UiAlertVariant.destructive,
        liveRegion: true,
      );
    }
    if (notifications.isEmpty) {
      return UiEmptyState(
        icon: Icons.notifications_none_outlined,
        title: _unreadOnly
            ? 'Tidak ada notifikasi baru'
            : 'Belum ada notifikasi',
        message: _unreadOnly
            ? 'Semua notifikasi komentar sudah dibaca.'
            : 'Notifikasi komentar akan muncul di sini.',
      );
    }

    final tokens = context.appTokens;
    return ListView.separated(
      itemCount: notifications.length,
      separatorBuilder: (_, _) =>
          Divider(color: tokens.panelBorder, height: AppBorder.thin),
      itemBuilder: (context, index) {
        final notification = notifications[index];
        final unread = !notification.isRead;
        return Semantics(
          key: ValueKey('comment-notification-${notification.id}'),
          button: true,
          label:
              '${unread ? 'Belum dibaca' : 'Sudah dibaca'}. ${notification.actorName}. ${commentNotificationTypeLabel(notification.type)}. ${notification.message}',
          onTap: () => onSelected(notification),
          child: ExcludeSemantics(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => onSelected(notification),
                borderRadius: BorderRadius.circular(tokens.controlRadius),
                child: UiSurface(
                  color: unread ? tokens.accentSoft : tokens.panelElevated,
                  borderRadius: BorderRadius.circular(tokens.controlRadius),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: AppControlSize.compact,
                        height: AppControlSize.compact,
                        decoration: BoxDecoration(
                          color: unread
                              ? tokens.accent.withValues(alpha: 0.16)
                              : tokens.panel,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          commentNotificationIcon(notification.type),
                          size: 16,
                          color: unread ? tokens.accent : tokens.textMuted,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    notification.actorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.text,
                                      fontSize: 12,
                                      fontWeight: unread
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                UiBadge(
                                  commentNotificationTypeLabel(
                                    notification.type,
                                  ),
                                  variant: UiBadgeVariant.secondary,
                                ),
                              ],
                            ),
                            const SizedBox(
                              height: AppSpacing.xxs + AppSpacing.xs,
                            ),
                            Text(
                              notification.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _formatNotificationTime(
                                context,
                                notification.createdAt,
                              ),
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(
                            top: AppSpacing.xs + AppSpacing.xxs / 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
