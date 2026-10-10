import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/collaboration/domain/comment_notifications.dart';
import 'package:varian/features/collaboration/presentation/widgets/comment_ui.dart';
import 'package:varian/features/collaboration/presentation/widgets/comment_metadata_ui.dart';

class CommentThreadDialog extends StatefulWidget {
  final CanvasComment comment;
  final bool readOnly;
  final String localUserId;
  final String localUserName;
  final bool Function(String emoji)? isReactionActive;
  final ValueChanged<CommentReply>? onReply;
  final ValueChanged<String>? onToggleReaction;
  final ValueChanged<bool>? onResolveChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onCreateNewComment;
  final ValueChanged<CanvasComment>? onUpdate;
  final CommentAttachmentPicker? onPickAttachment;

  const CommentThreadDialog({
    super.key,
    required this.comment,
    required this.localUserId,
    required this.localUserName,
    this.isReactionActive,
    this.readOnly = false,
    this.onReply,
    this.onToggleReaction,
    this.onResolveChanged,
    this.onDelete,
    this.onCreateNewComment,
    this.onUpdate,
    this.onPickAttachment,
  });

  @override
  State<CommentThreadDialog> createState() => _CommentThreadDialogState();
}

class _CommentThreadDialogState extends State<CommentThreadDialog> {
  late CanvasComment _currentComment;
  final _replyController = TextEditingController();
  bool _replyMode = false;

  @override
  void initState() {
    super.initState();
    _currentComment = widget.comment;
  }

  @override
  void didUpdateWidget(covariant CommentThreadDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.id != widget.comment.id) {
      _currentComment = widget.comment;
      _replyController.clear();
      _replyMode = false;
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  void _sendReply() {
    final text = _replyController.text.trim();
    if (text.isEmpty || widget.readOnly) return;

    final foundMentions = CommentNotificationFactory.extractMentions(text);
    final reply = CommentReply(
      id: const Uuid().v4(),
      authorId: widget.localUserId,
      authorName: widget.localUserName.trim().isEmpty
          ? 'Collaborator'
          : widget.localUserName.trim(),
      text: text,
      createdAt: DateTime.now(),
    );
    final updated = _currentComment.copyWith(
      replies: [..._currentComment.replies, reply],
      mentions: {..._currentComment.mentions, ...foundMentions}.toList(),
    );
    setState(() {
      _currentComment = updated;
      _replyController.clear();
    });
    widget.onReply?.call(reply);
    widget.onUpdate?.call(updated);
  }

  void _toggleReaction(String emoji) {
    final currentCount = _currentComment.reactions[emoji] ?? 0;
    final active = widget.isReactionActive?.call(emoji) ?? currentCount > 0;
    final updatedReactions = Map<String, int>.from(_currentComment.reactions);
    if (active) {
      if (currentCount <= 1) {
        updatedReactions.remove(emoji);
      } else {
        updatedReactions[emoji] = currentCount - 1;
      }
    } else {
      updatedReactions[emoji] = currentCount + 1;
    }
    final updated = _currentComment.copyWith(reactions: updatedReactions);
    setState(() => _currentComment = updated);
    widget.onToggleReaction?.call(emoji);
    widget.onUpdate?.call(updated);
  }

  void _setResolved(bool resolved) {
    final updated = _currentComment.copyWith(resolved: resolved);
    setState(() => _currentComment = updated);
    widget.onResolveChanged?.call(resolved);
    widget.onUpdate?.call(updated);
  }

  void _deleteComment() {
    widget.onDelete?.call();
    if (mounted) Navigator.of(context).pop();
  }

  void _startNewComment() {
    widget.onCreateNewComment?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildReply(
    BuildContext context,
    CommentReply reply,
    AppTokens tokens,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xxs),
      decoration: BoxDecoration(
        color: tokens.panelElevated,
        border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CommentAvatar(name: reply.authorName, color: tokens.info),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reply.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      formatCommentTimestamp(context, reply.createdAt),
                      style: TextStyle(color: tokens.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              UiIconButton(
                icon: Icons.reply_rounded,
                tooltip: 'Balas komentar utama',
                onPressed: widget.readOnly
                    ? null
                    : () => setState(() => _replyMode = true),
                size: UiButtonSize.sm,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            reply.text,
            style: TextStyle(color: tokens.text, fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, AppTokens tokens) {
    if (widget.readOnly) {
      return Text(
        'Mode hanya baca. Anda tetap dapat melihat seluruh riwayat komentar.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall!.copyWith(color: tokens.textMuted, fontSize: 11),
      );
    }

    if (!_replyMode) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Ingin menambahkan sesuatu pada canvas ini?',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: tokens.textMuted,
                fontSize: 11,
              ),
            ),
          ),
          UiButton(
            onPressed: () => setState(() => _replyMode = true),
            size: UiButtonSize.sm,
            prefix: const Icon(Icons.reply_rounded, size: 14),
            child: const Text('Balas'),
          ),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
          UiButton(
            onPressed: widget.onCreateNewComment == null
                ? null
                : _startNewComment,
            variant: UiButtonVariant.outline,
            size: UiButtonSize.sm,
            prefix: const Icon(Icons.add_comment_outlined, size: 14),
            child: const Text('Komentar baru'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.reply_rounded, size: 14, color: tokens.accent),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Membalas ${_currentComment.authorName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: tokens.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            UiButton(
              onPressed: () {
                _replyController.clear();
                setState(() => _replyMode = false);
              },
              variant: UiButtonVariant.ghost,
              size: UiButtonSize.sm,
              child: const Text('Batal'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: UiTextField(
                controller: _replyController,
                autofocus: true,
                hint: 'Tulis balasan atau gunakan @nama...',
                minLines: 2,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onSubmitted: (_) => _sendReply(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            UiIconButton(
              icon: Icons.send_rounded,
              tooltip: 'Kirim balasan',
              onPressed: _sendReply,
              variant: UiButtonVariant.primary,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - AppSpacing.page * 2).clamp(0.0, 560.0);
    final titleName = _currentComment.authorName.trim().isEmpty
        ? 'Collaborator'
        : _currentComment.authorName;

    return UiDialog(
      semanticsLabel: 'Comment thread',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 560,
        maxHeight: 760,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CommentAvatar(
                    name: titleName,
                    color: tokens.accent,
                    radius: 17,
                  ),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thread komentar',
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(
                                color: tokens.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          titleName,
                          style: TextStyle(
                            color: tokens.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          formatCommentTimestamp(
                            context,
                            _currentComment.createdAt,
                          ),
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_currentComment.resolved)
                    const UiBadge('Selesai', variant: UiBadgeVariant.success),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Tutup thread komentar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.height * 0.58),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UiSurface(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          color: tokens.panel,
                          child: Text(
                            _currentComment.text.isEmpty
                                ? 'Komentar belum memiliki isi.'
                                : _currentComment.text,
                            style: TextStyle(
                              color: tokens.text,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                        if (_currentComment.mentions.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.xs + AppSpacing.xxs,
                            runSpacing: AppSpacing.xs,
                            children: _currentComment.mentions
                                .map(
                                  (mention) => UiBadge(
                                    '@$mention',
                                    variant: UiBadgeVariant.secondary,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        CommentMetadataPanel(
                          comment: _currentComment,
                          readOnly: widget.readOnly,
                          onChanged: (updated) {
                            setState(() => _currentComment = updated);
                            widget.onUpdate?.call(updated);
                          },
                          onPickAttachment: widget.onPickAttachment,
                        ),
                        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final emoji in const ['👍', '❤️', '🚀', '👀'])
                              Builder(
                                builder: (context) {
                                  final active =
                                      widget.isReactionActive?.call(emoji) ??
                                      (_currentComment.reactions[emoji] ?? 0) >
                                          0;
                                  final count =
                                      _currentComment.reactions[emoji] ?? 0;
                                  return UiButton(
                                    onPressed: widget.readOnly
                                        ? null
                                        : () => _toggleReaction(emoji),
                                    variant: active
                                        ? UiButtonVariant.primary
                                        : UiButtonVariant.outline,
                                    size: UiButtonSize.sm,
                                    selected: active,
                                    semanticsLabel:
                                        '$emoji reaction, $count ${active ? 'selected' : 'not selected'}',
                                    child: Text(
                                      '$emoji $count',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  );
                                },
                              ),
                            if (!widget.readOnly)
                              UiButton(
                                onPressed: () =>
                                    _setResolved(!_currentComment.resolved),
                                variant: UiButtonVariant.ghost,
                                size: UiButtonSize.sm,
                                child: Text(
                                  _currentComment.resolved
                                      ? 'Buka lagi'
                                      : 'Selesaikan',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                        Row(
                          children: [
                            Text(
                              'Balasan',
                              style: Theme.of(context).textTheme.titleSmall!
                                  .copyWith(
                                    color: tokens.text,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(
                              width: AppSpacing.xs + AppSpacing.xxs,
                            ),
                            UiBadge('${_currentComment.replies.length}'),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (_currentComment.replies.isEmpty)
                          Text(
                            'Belum ada balasan. Mulai percakapan dari composer di bawah.',
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(
                                  color: tokens.textMuted,
                                  fontSize: 11,
                                ),
                          )
                        else
                          for (final reply in _currentComment.replies) ...[
                            _buildReply(context, reply, tokens),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(color: tokens.panelBorder, height: AppBorder.thin),
              const SizedBox(height: AppSpacing.md),
              _buildComposer(context, tokens),
              if (!widget.readOnly) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: UiButton(
                    onPressed: _deleteComment,
                    variant: UiButtonVariant.ghost,
                    size: UiButtonSize.sm,
                    prefix: const Icon(Icons.delete_outline_rounded, size: 14),
                    child: const Text('Hapus komentar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
