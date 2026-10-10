import 'package:flutter/material.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'comment_metadata_ui.dart';

String formatCommentTimestamp(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final date = MaterialLocalizations.of(context).formatMediumDate(local);
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat:
        MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false,
  );
  return '$date · $time';
}

double _commentPanelWidth(BuildContext context) {
  final viewportWidth = MediaQuery.sizeOf(context).width;
  final availableWidth = viewportWidth - AppSpacing.page * 2;
  if (!AppResponsive.isCompact(context)) {
    return availableWidth.clamp(280.0, 360.0).toDouble();
  }
  return availableWidth.clamp(0.0, 360.0).toDouble();
}

double _boundedCommentPanelWidth(BuildContext context, double? maxWidth) {
  final width = _commentPanelWidth(context);
  return maxWidth == null ? width : width.clamp(0.0, maxWidth).toDouble();
}

class CommentAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final double radius;

  const CommentAvatar({
    required this.name,
    required this.color,
    this.radius = 14,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = name.trim();
    final initial = normalized.isEmpty ? '?' : normalized[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initial,
        style: TextStyle(
          color: color.computeLuminance() > 0.5
              ? AppTokens.dark.accentForeground
              : AppTokens.light.accentForeground,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class CommentDraftEditor extends StatefulWidget {
  final CanvasComment comment;
  final bool readOnly;
  final VoidCallback onCancel;
  final ValueChanged<String> onSave;

  const CommentDraftEditor({
    required this.comment,
    required this.readOnly,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  @override
  State<CommentDraftEditor> createState() => _CommentDraftEditorState();
}

class _CommentDraftEditorState extends State<CommentDraftEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.comment.text);
  }

  @override
  void didUpdateWidget(covariant CommentDraftEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.id != widget.comment.id) {
      _controller.text = widget.comment.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.readOnly) return;
    widget.onSave(text);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Container(
      width: _commentPanelWidth(context),
      margin: const EdgeInsets.only(left: AppSpacing.sm),
      child: UiSurface(
        color: tokens.panelElevated,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CommentAvatar(
                  name: widget.comment.authorName,
                  color: tokens.accent,
                  radius: 13,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Komentar baru',
                        style: Theme.of(context).textTheme.labelMedium!
                            .copyWith(
                              color: tokens.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Bagikan catatan untuk kolaborator',
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: tokens.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatCommentTimestamp(context, widget.comment.createdAt),
                  style: TextStyle(color: tokens.textMuted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
            UiTextField(
              controller: _controller,
              autofocus: true,
              enabled: !widget.readOnly,
              hint: 'Tulis komentar untuk kolaborator...',
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                UiButton(
                  onPressed: widget.onCancel,
                  variant: UiButtonVariant.ghost,
                  size: UiButtonSize.sm,
                  child: const Text('Batal'),
                ),
                const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                UiButton(
                  onPressed: widget.readOnly ? null : _save,
                  size: UiButtonSize.sm,
                  prefix: const Icon(Icons.send_rounded, size: 14),
                  child: const Text('Kirim komentar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class NewCommentComposer extends StatefulWidget {
  final String threadId;
  final bool readOnly;
  final ValueChanged<String> onSubmit;

  const NewCommentComposer({
    required this.threadId,
    required this.readOnly,
    required this.onSubmit,
    super.key,
  });

  @override
  State<NewCommentComposer> createState() => _NewCommentComposerState();
}

class _NewCommentComposerState extends State<NewCommentComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.readOnly) return;
    widget.onSubmit(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return UiSurface(
      color: tokens.panel,
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_comment_outlined, size: 14, color: tokens.accent),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Komentar baru',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: tokens.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Enter untuk kirim',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: tokens.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: UiTextField(
                  key: ValueKey('comment-new-field-${widget.threadId}'),
                  controller: _controller,
                  enabled: !widget.readOnly,
                  hint: 'Tulis komentar baru di feedback ini...',
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              UiIconButton(
                key: ValueKey('comment-new-send-${widget.threadId}'),
                icon: Icons.send_rounded,
                tooltip: 'Kirim komentar baru',
                onPressed: widget.readOnly ? null : _submit,
                variant: UiButtonVariant.primary,
                size: UiButtonSize.sm,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum CommentReplyAction { edit, delete }

class CommentReplyTile extends StatefulWidget {
  final CommentReply reply;
  final bool readOnly;
  final ValueChanged<String>? onEdit;
  final VoidCallback? onDelete;

  const CommentReplyTile({
    required this.reply,
    required this.readOnly,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  @override
  State<CommentReplyTile> createState() => _CommentReplyTileState();
}

class _CommentReplyTileState extends State<CommentReplyTile> {
  late final TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.reply.text);
  }

  @override
  void didUpdateWidget(covariant CommentReplyTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reply.id != widget.reply.id) {
      _controller.text = widget.reply.text;
      _isEditing = false;
    } else if (!_isEditing && oldWidget.reply.text != widget.reply.text) {
      _controller.text = widget.reply.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEdit() {
    if (widget.readOnly || widget.onEdit == null) return;
    _controller
      ..text = widget.reply.text
      ..selection = TextSelection.collapsed(offset: widget.reply.text.length);
    setState(() => _isEditing = true);
  }

  void _saveEdit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.readOnly || widget.onEdit == null) return;
    widget.onEdit!(text);
    if (mounted) setState(() => _isEditing = false);
  }

  void _handleAction(CommentReplyAction action) {
    switch (action) {
      case CommentReplyAction.edit:
        _startEdit();
      case CommentReplyAction.delete:
        if (!widget.readOnly) widget.onDelete?.call();
    }
  }

  Widget _buildEditor(BuildContext context, AppTokens tokens) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: UiSurface(
      color: tokens.panelElevated,
      padding: const EdgeInsets.all(AppSpacing.sm),
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderColor: tokens.accent.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UiTextField(
            key: ValueKey('reply-edit-field-${widget.reply.id}'),
            controller: _controller,
            autofocus: true,
            hint: 'Edit balasan...',
            minLines: 1,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              UiButton(
                key: ValueKey('reply-edit-cancel-${widget.reply.id}'),
                onPressed: () => setState(() => _isEditing = false),
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                child: const Text('Batal'),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              UiButton(
                key: ValueKey('reply-edit-save-${widget.reply.id}'),
                onPressed: _saveEdit,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.check_rounded, size: 13),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final canShowMenu = widget.onEdit != null || widget.onDelete != null;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: UiSurface(
        color: tokens.panel,
        padding: const EdgeInsets.all(AppSpacing.sm),
        borderRadius: BorderRadius.circular(AppRadius.panel),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommentAvatar(
              name: widget.reply.authorName,
              color: tokens.info,
              radius: 11,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.xs + AppSpacing.xxs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              widget.reply.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.text,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (widget.reply.editedAt != null)
                              Text(
                                'Edited',
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 9,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                      Flexible(
                        child: Text(
                          formatCommentTimestamp(
                            context,
                            widget.reply.createdAt,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 9,
                          ),
                        ),
                      ),
                      if (canShowMenu)
                        UiMenuButton<CommentReplyAction>(
                          buttonKey: ValueKey('reply-menu-${widget.reply.id}'),
                          tooltip: 'Aksi balasan',
                          icon: Icons.more_horiz_rounded,
                          items: [
                            UiMenuAction(
                              value: CommentReplyAction.edit,
                              label: 'Edit balasan',
                              icon: Icons.edit_outlined,
                              enabled:
                                  !widget.readOnly && widget.onEdit != null,
                            ),
                            UiMenuAction(
                              value: CommentReplyAction.delete,
                              label: 'Hapus balasan',
                              icon: Icons.delete_outline_rounded,
                              enabled:
                                  !widget.readOnly && widget.onDelete != null,
                              destructive: true,
                            ),
                          ],
                          onSelected: _handleAction,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (_isEditing)
                    _buildEditor(context, tokens)
                  else
                    Text(
                      widget.reply.text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum CommentCardAction { reply, reaction, edit, resolve, delete }

class CanvasCommentCard extends StatefulWidget {
  final CanvasComment comment;
  final bool readOnly;
  final ValueChanged<String> onReply;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onReaction;
  final ValueChanged<bool> onResolve;
  final VoidCallback onDelete;
  final void Function(CommentReply, String)? onEditReply;
  final ValueChanged<CommentReply>? onDeleteReply;
  final ValueChanged<CanvasComment>? onMetadataChanged;
  final CommentAttachmentPicker? onPickAttachment;
  final VoidCallback? onDismiss;
  final bool embedded;

  const CanvasCommentCard({
    required this.comment,
    required this.readOnly,
    required this.onReply,
    required this.onEdit,
    required this.onReaction,
    required this.onResolve,
    required this.onDelete,
    this.onEditReply,
    this.onDeleteReply,
    this.onMetadataChanged,
    this.onPickAttachment,
    this.onDismiss,
    this.embedded = false,
    super.key,
  });

  @override
  State<CanvasCommentCard> createState() => _CanvasCommentCardState();
}

class _CanvasCommentCardState extends State<CanvasCommentCard> {
  final _replyController = TextEditingController();
  final _editController = TextEditingController();
  bool _isReplying = false;
  bool _isEditing = false;
  bool _showReactionPicker = false;
  bool _showAllReplies = false;

  static const _reactionOptions = ['👍', '❤️', '🎉', '🚀', '👀'];

  @override
  void initState() {
    super.initState();
    _editController.text = widget.comment.text;
  }

  @override
  void didUpdateWidget(covariant CanvasCommentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.id != widget.comment.id) {
      _replyController.clear();
      _editController.text = widget.comment.text;
      _isReplying = false;
      _isEditing = false;
      _showReactionPicker = false;
      _showAllReplies = false;
    } else if (!_isEditing && oldWidget.comment.text != widget.comment.text) {
      _editController.text = widget.comment.text;
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    _editController.dispose();
    super.dispose();
  }

  void _startReply() {
    if (widget.readOnly) return;
    setState(() {
      _isReplying = true;
      _isEditing = false;
      _showReactionPicker = false;
    });
  }

  void _startEdit() {
    if (widget.readOnly) return;
    _editController
      ..text = widget.comment.text
      ..selection = TextSelection.collapsed(offset: widget.comment.text.length);
    setState(() {
      _isEditing = true;
      _isReplying = false;
      _showReactionPicker = false;
    });
  }

  void _submitReply() {
    final text = _replyController.text.trim();
    if (text.isEmpty || widget.readOnly) return;
    widget.onReply(text);
    if (mounted) {
      setState(() {
        _replyController.clear();
        _isReplying = false;
      });
    }
  }

  void _saveEdit() {
    final text = _editController.text.trim();
    if (text.isEmpty || widget.readOnly) return;
    widget.onEdit(text);
    if (mounted) {
      setState(() => _isEditing = false);
    }
  }

  void _selectReaction(String emoji) {
    if (widget.readOnly) return;
    widget.onReaction(emoji);
    if (mounted) {
      setState(() => _showReactionPicker = false);
    }
  }

  void _handleAction(CommentCardAction action) {
    switch (action) {
      case CommentCardAction.reply:
        _startReply();
      case CommentCardAction.reaction:
        if (widget.readOnly) return;
        setState(() {
          _showReactionPicker = !_showReactionPicker;
          _isReplying = false;
          _isEditing = false;
        });
      case CommentCardAction.edit:
        _startEdit();
      case CommentCardAction.resolve:
        if (!widget.readOnly) widget.onResolve(!widget.comment.resolved);
      case CommentCardAction.delete:
        if (!widget.readOnly) widget.onDelete();
    }
  }

  Widget _buildReplyPreview(CommentReply reply) => CommentReplyTile(
    key: ValueKey('comment-reply-${widget.comment.id}-${reply.id}'),
    reply: reply,
    readOnly: widget.readOnly,
    onEdit: widget.onEditReply == null
        ? null
        : (text) => widget.onEditReply!(reply, text),
    onDelete: widget.onDeleteReply == null
        ? null
        : () => widget.onDeleteReply!(reply),
  );

  Widget _buildEditEditor(BuildContext context, AppTokens tokens) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: UiSurface(
      color: tokens.panel,
      padding: const EdgeInsets.all(AppSpacing.sm),
      borderRadius: BorderRadius.circular(AppRadius.panel),
      borderColor: tokens.accent.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 14, color: tokens.accent),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Text(
                'Edit komentar',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: tokens.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          UiTextField(
            key: ValueKey('comment-edit-field-${widget.comment.id}'),
            controller: _editController,
            autofocus: true,
            hint: 'Perbarui komentar...',
            minLines: 2,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              UiButton(
                key: ValueKey('comment-edit-cancel-${widget.comment.id}'),
                onPressed: () => setState(() => _isEditing = false),
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                child: const Text('Batal'),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              UiButton(
                key: ValueKey('comment-edit-save-${widget.comment.id}'),
                onPressed: _saveEdit,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.check_rounded, size: 14),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildReactionPicker(BuildContext context, AppTokens tokens) =>
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm + AppSpacing.xxs),
        child: UiSurface(
          color: tokens.panel,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm + AppSpacing.xxs,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          borderRadius: BorderRadius.circular(AppRadius.panel),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.emoji_emotions_outlined,
                size: 14,
                color: tokens.textMuted,
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final emoji in _reactionOptions)
                      UiButton(
                        key: ValueKey(
                          'comment-reaction-option-${widget.comment.id}-$emoji',
                        ),
                        onPressed: () => _selectReaction(emoji),
                        variant: (widget.comment.reactions[emoji] ?? 0) > 0
                            ? UiButtonVariant.primary
                            : UiButtonVariant.ghost,
                        size: UiButtonSize.sm,
                        semanticsLabel: 'Beri reaksi $emoji',
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
              UiIconButton(
                key: ValueKey('comment-reaction-close-${widget.comment.id}'),
                icon: Icons.close_rounded,
                tooltip: 'Tutup pilihan reaksi',
                onPressed: () => setState(() => _showReactionPicker = false),
                size: UiButtonSize.sm,
              ),
            ],
          ),
        ),
      );

  Widget _buildReplyComposer(BuildContext context, AppTokens tokens) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: UiSurface(
      color: tokens.panel,
      padding: const EdgeInsets.all(AppSpacing.sm),
      borderRadius: BorderRadius.circular(AppRadius.panel),
      borderColor: tokens.accent.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.reply_rounded, size: 14, color: tokens.accent),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Expanded(
                child: Text(
                  'Membalas ${widget.comment.authorName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              UiIconButton(
                key: ValueKey('comment-reply-close-${widget.comment.id}'),
                icon: Icons.close_rounded,
                tooltip: 'Batal membalas',
                onPressed: () => setState(() {
                  _replyController.clear();
                  _isReplying = false;
                }),
                size: UiButtonSize.sm,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: UiTextField(
                  key: ValueKey('comment-reply-field-${widget.comment.id}'),
                  controller: _replyController,
                  autofocus: true,
                  hint: 'Tulis balasan...',
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) => _submitReply(),
                ),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              UiIconButton(
                key: ValueKey('comment-reply-send-${widget.comment.id}'),
                icon: Icons.send_rounded,
                tooltip: 'Kirim balasan',
                onPressed: _submitReply,
                variant: UiButtonVariant.primary,
                size: UiButtonSize.sm,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildReactionChip(AppTokens tokens, String emoji, int count) =>
      UiButton(
        key: ValueKey('comment-reaction-$emoji-${widget.comment.id}'),
        onPressed: widget.readOnly ? null : () => _selectReaction(emoji),
        variant: UiButtonVariant.ghost,
        size: UiButtonSize.sm,
        child: Text(
          '$emoji $count',
          style: TextStyle(color: tokens.textMuted, fontSize: 10),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final visibleReplies = _showAllReplies
        ? widget.comment.replies
        : widget.comment.replies.take(3).toList();
    final remainingReplies =
        widget.comment.replies.length - visibleReplies.length;
    final reactions = widget.comment.reactions.entries
        .where((entry) => entry.value > 0)
        .toList();

    final commentContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommentAvatar(
              name: widget.comment.authorName,
              color: tokens.accent,
              radius: 16,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.comment.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                      Text(
                        'Komentar',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.comment.editedAt != null) ...[
                        const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                        Text(
                          'Edited',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 9,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    formatCommentTimestamp(context, widget.comment.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.textMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (widget.comment.resolved)
              const UiBadge('Selesai', variant: UiBadgeVariant.secondary),
            UiMenuButton<CommentCardAction>(
              buttonKey: ValueKey('comment-menu-${widget.comment.id}'),
              tooltip: 'Aksi komentar',
              icon: Icons.more_horiz_rounded,
              items: [
                UiMenuAction(
                  value: CommentCardAction.reply,
                  label: 'Balas',
                  icon: Icons.reply_rounded,
                  enabled: !widget.readOnly,
                ),
                UiMenuAction(
                  value: CommentCardAction.reaction,
                  label: 'Beri reaksi',
                  icon: Icons.add_reaction_outlined,
                  enabled: !widget.readOnly,
                ),
                UiMenuAction(
                  value: CommentCardAction.edit,
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  enabled: !widget.readOnly,
                ),
                UiMenuAction(
                  value: CommentCardAction.resolve,
                  label: widget.comment.resolved
                      ? 'Buka kembali'
                      : 'Selesaikan',
                  icon: widget.comment.resolved
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline_rounded,
                  enabled: !widget.readOnly,
                ),
                UiMenuAction(
                  value: CommentCardAction.delete,
                  label: 'Hapus',
                  icon: Icons.delete_outline_rounded,
                  enabled: !widget.readOnly,
                  destructive: true,
                ),
              ],
              onSelected: _handleAction,
            ),
            if (widget.onDismiss != null)
              UiIconButton(
                key: ValueKey('comment-dismiss-${widget.comment.id}'),
                icon: Icons.close_rounded,
                tooltip: 'Tutup komentar',
                onPressed: widget.onDismiss,
                size: UiButtonSize.sm,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_isEditing)
          _buildEditEditor(context, tokens)
        else
          Text(
            widget.comment.text,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: widget.comment.resolved ? tokens.textMuted : tokens.text,
              decoration: widget.comment.resolved
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              decorationThickness: widget.comment.resolved ? 1.4 : null,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        if (widget.onMetadataChanged != null)
          CommentMetadataPanel(
            comment: widget.comment,
            readOnly: widget.readOnly,
            onChanged: widget.onMetadataChanged!,
            onPickAttachment: widget.onPickAttachment,
          ),
        if (reactions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final entry in reactions)
                _buildReactionChip(tokens, entry.key, entry.value),
            ],
          ),
        ],
        if (_showReactionPicker) _buildReactionPicker(context, tokens),
        if (widget.comment.replies.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.forum_outlined, size: 14, color: tokens.textMuted),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Text(
                'Balasan',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: tokens.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              UiBadge('${widget.comment.replies.length}'),
            ],
          ),
          for (final reply in visibleReplies) _buildReplyPreview(reply),
          if (remainingReplies > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: UiButton(
                key: ValueKey('comment-show-replies-${widget.comment.id}'),
                onPressed: () => setState(() => _showAllReplies = true),
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.expand_more_rounded, size: 14),
                child: Text(
                  'Lihat $remainingReplies balasan lainnya',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            )
          else if (_showAllReplies && widget.comment.replies.length > 3)
            Align(
              alignment: Alignment.centerLeft,
              child: UiButton(
                key: ValueKey('comment-collapse-replies-${widget.comment.id}'),
                onPressed: () => setState(() => _showAllReplies = false),
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.expand_less_rounded, size: 14),
                child: const Text(
                  'Sembunyikan balasan',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (widget.comment.replies.isNotEmpty)
              UiButton(
                key: ValueKey('comment-replies-count-${widget.comment.id}'),
                onPressed: () =>
                    setState(() => _showAllReplies = !_showAllReplies),
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.forum_outlined, size: 14),
                child: Text(
                  '${widget.comment.replies.length} balasan',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            if (widget.comment.resolved)
              const UiBadge('Selesai', variant: UiBadgeVariant.secondary),
          ],
        ),
        if (_isReplying) _buildReplyComposer(context, tokens),
        if (widget.comment.resolved) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Thread ini sudah diselesaikan.',
            style: TextStyle(color: tokens.success, fontSize: 10),
          ),
        ],
      ],
    );
    if (widget.embedded) return commentContent;

    return Container(
      width: _commentPanelWidth(context),
      margin: const EdgeInsets.only(left: AppSpacing.sm),
      child: UiSurface(
        color: tokens.panelElevated,
        padding: const EdgeInsets.all(AppSpacing.md),
        borderColor: widget.comment.resolved
            ? tokens.success.withValues(alpha: 0.8)
            : null,
        child: commentContent,
      ),
    );
  }
}

class CanvasCommentThreadCard extends StatelessWidget {
  final List<CanvasComment> comments;
  final bool readOnly;
  final void Function(CanvasComment, String) onReply;
  final void Function(CanvasComment, String) onEdit;
  final void Function(CanvasComment, String) onReaction;
  final void Function(CanvasComment, bool) onResolve;
  final ValueChanged<CanvasComment> onDelete;
  final void Function(CanvasComment, CommentReply, String)? onEditReply;
  final void Function(CanvasComment, CommentReply)? onDeleteReply;
  final void Function(CanvasComment, CanvasComment)? onMetadataChanged;
  final Future<CommentAttachment?> Function(CanvasComment)? onPickAttachment;
  final ValueChanged<String> onCreateNewComment;
  final VoidCallback? onDismiss;

  const CanvasCommentThreadCard({
    required this.comments,
    required this.readOnly,
    required this.onReply,
    required this.onEdit,
    required this.onReaction,
    required this.onResolve,
    required this.onDelete,
    required this.onCreateNewComment,
    this.onEditReply,
    this.onDeleteReply,
    this.onMetadataChanged,
    this.onPickAttachment,
    this.onDismiss,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final ordered = [...comments]
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    if (ordered.isEmpty) return const SizedBox.shrink();
    final threadId = ordered.first.feedbackThreadKey;
    final hasResolvedComment = ordered.any((comment) => comment.resolved);

    return LayoutBuilder(
      builder: (context, constraints) => Container(
        width: _boundedCommentPanelWidth(
          context,
          constraints.hasBoundedWidth ? constraints.maxWidth : null,
        ),
        margin: const EdgeInsets.only(left: AppSpacing.sm),
        child: UiSurface(
          color: tokens.panelElevated,
          padding: const EdgeInsets.all(AppSpacing.md),
          borderColor: hasResolvedComment
              ? tokens.success.withValues(alpha: 0.8)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 14,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  Text(
                    'Feedback',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: tokens.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  UiBadge('${ordered.length} komentar'),
                ],
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              for (var index = 0; index < ordered.length; index++) ...[
                CanvasCommentCard(
                  key: ValueKey('comment-card-${ordered[index].id}'),
                  comment: ordered[index],
                  readOnly: readOnly,
                  embedded: true,
                  onReply: (text) => onReply(ordered[index], text),
                  onEdit: (text) => onEdit(ordered[index], text),
                  onReaction: (emoji) => onReaction(ordered[index], emoji),
                  onResolve: (resolved) => onResolve(ordered[index], resolved),
                  onDelete: () => onDelete(ordered[index]),
                  onMetadataChanged: onMetadataChanged == null
                      ? null
                      : (updated) =>
                            onMetadataChanged!(ordered[index], updated),
                  onPickAttachment: onPickAttachment == null
                      ? null
                      : () => onPickAttachment!(ordered[index]),
                  onEditReply: onEditReply == null
                      ? null
                      : (reply, text) =>
                            onEditReply!(ordered[index], reply, text),
                  onDeleteReply: onDeleteReply == null
                      ? null
                      : (reply) => onDeleteReply!(ordered[index], reply),
                  onDismiss: index == 0 ? onDismiss : null,
                ),
                if (index < ordered.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Divider(
                      height: AppBorder.thin,
                      color: tokens.panelBorder,
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.md),
              NewCommentComposer(
                threadId: threadId,
                readOnly: readOnly,
                onSubmit: onCreateNewComment,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
