import 'package:flutter/material.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/collaboration.dart';

typedef CommentAttachmentPicker = Future<CommentAttachment?> Function();

class CommentMetadataPanel extends StatelessWidget {
  final CanvasComment comment;
  final bool readOnly;
  final ValueChanged<CanvasComment> onChanged;
  final CommentAttachmentPicker? onPickAttachment;

  const CommentMetadataPanel({
    required this.comment,
    required this.readOnly,
    required this.onChanged,
    this.onPickAttachment,
    super.key,
  });

  Future<String?> _askText(
    BuildContext context, {
    required String title,
    required String fieldKey,
    required String saveKey,
    String initialValue = '',
    String hint = '',
  }) async {
    return showUiDialog<String>(
      context: context,
      builder: (dialogContext) {
        var value = initialValue;
        return UiDialog(
          semanticsLabel: title,
          constraints: AppResponsive.dialogConstraints(
            dialogContext,
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
                const SizedBox(height: AppSpacing.md),
                UiTextField(
                  key: ValueKey(fieldKey),
                  label: title,
                  hint: hint.isEmpty ? null : hint,
                  initialValue: initialValue,
                  autofocus: true,
                  onChanged: (next) => value = next,
                  onSubmitted: (next) => Navigator.of(context).pop(next),
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
                      child: const Text('Batal'),
                    ),
                    UiButton(
                      key: ValueKey(saveKey),
                      onPressed: () => Navigator.of(context).pop(value),
                      child: const Text('Simpan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addLabel(BuildContext context) async {
    if (readOnly) return;
    final value = await _askText(
      context,
      title: 'Tambah label',
      fieldKey: 'comment-label-field',
      saveKey: 'comment-label-save',
      hint: 'Contoh: priority',
    );
    if (!context.mounted) return;
    final label = value?.trim() ?? '';
    if (label.isEmpty) return;
    onChanged(comment.copyWith(labels: [...comment.normalizedLabels, label]));
  }

  Future<void> _assign(BuildContext context) async {
    if (readOnly) return;
    final value = await _askText(
      context,
      title: 'Tetapkan assignee',
      fieldKey: 'comment-assignee-field',
      saveKey: 'comment-assignee-save',
      initialValue: comment.assigneeName ?? '',
      hint: 'Nama collaborator',
    );
    if (!context.mounted || value == null) return;
    final assignee = value.trim();
    onChanged(
      comment.copyWith(
        assigneeId: assignee.isEmpty ? null : assignee,
        assigneeName: assignee.isEmpty ? null : assignee,
      ),
    );
  }

  Future<void> _pickDueDate(BuildContext context) async {
    if (readOnly) return;
    final now = DateTime.now();
    final initial = comment.dueDate ?? now;
    final selected = await showUiDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
      initialDate: initial.isBefore(DateTime(now.year - 10))
          ? DateTime(now.year - 10)
          : initial.isAfter(DateTime(now.year + 20))
          ? DateTime(now.year + 20)
          : initial,
    );
    if (!context.mounted || selected == null) return;
    onChanged(comment.copyWith(dueDate: selected));
  }

  Future<void> _pickAttachment() async {
    if (readOnly || onPickAttachment == null) return;
    final attachment = await onPickAttachment!();
    if (attachment == null) return;
    onChanged(
      comment.copyWith(attachments: [...comment.attachments, attachment]),
    );
  }

  void _removeLabel(String label) {
    if (readOnly) return;
    onChanged(
      comment.copyWith(
        labels: comment.normalizedLabels
            .where((item) => item != label)
            .toList(growable: false),
      ),
    );
  }

  void _removeAttachment(CommentAttachment attachment) {
    if (readOnly) return;
    onChanged(
      comment.copyWith(
        attachments: comment.attachments
            .where((item) => item.id != attachment.id)
            .toList(growable: false),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final labels = comment.normalizedLabels;
    final dueDate = comment.dueDate;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: UiSurface(
        key: ValueKey('comment-metadata-${comment.id}'),
        color: tokens.panel,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 14, color: tokens.textMuted),
                const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                Text(
                  'Metadata',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Label',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: tokens.textMuted,
                    fontSize: 10,
                  ),
                ),
                for (final label in labels)
                  Material(
                    type: MaterialType.transparency,
                    child: InputChip(
                      key: ValueKey('comment-label-$label'),
                      label: Text(label, style: const TextStyle(fontSize: 10)),
                      onDeleted: readOnly ? null : () => _removeLabel(label),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                UiButton(
                  key: ValueKey('comment-add-label-${comment.id}'),
                  onPressed: readOnly ? null : () => _addLabel(context),
                  variant: UiButtonVariant.ghost,
                  size: UiButtonSize.sm,
                  prefix: const Icon(Icons.add_rounded, size: 13),
                  child: const Text('Label'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        comment.assigneeName?.trim().isNotEmpty == true
                            ? comment.assigneeName!
                            : 'Belum ditugaskan',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tokens.text, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.xs,
                  children: [
                    UiButton(
                      key: ValueKey('comment-assign-${comment.id}'),
                      onPressed: readOnly ? null : () => _assign(context),
                      variant: UiButtonVariant.outline,
                      size: UiButtonSize.sm,
                      child: Text(
                        comment.assigneeId == null ? 'Assign' : 'Ubah',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    if (!readOnly && comment.assigneeId != null)
                      UiIconButton(
                        key: ValueKey('comment-clear-assignee-${comment.id}'),
                        icon: Icons.close_rounded,
                        tooltip: 'Hapus assignee',
                        onPressed: () => onChanged(
                          comment.copyWith(
                            assigneeId: null,
                            assigneeName: null,
                          ),
                        ),
                        size: UiButtonSize.sm,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            Row(
              children: [
                Icon(Icons.event_outlined, size: 14, color: tokens.textMuted),
                const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                Expanded(
                  child: Text(
                    dueDate == null
                        ? 'Tidak ada due date'
                        : 'Due ${_formatDate(dueDate)}${comment.isOverdue(DateTime.now()) ? ' · Terlambat' : ''}',
                    style: TextStyle(
                      color: comment.isOverdue(DateTime.now())
                          ? tokens.danger
                          : tokens.text,
                      fontSize: 11,
                    ),
                  ),
                ),
                UiButton(
                  key: ValueKey('comment-due-${comment.id}'),
                  onPressed: readOnly ? null : () => _pickDueDate(context),
                  variant: UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  child: Text(
                    dueDate == null ? 'Set date' : 'Ubah',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (!readOnly && dueDate != null)
                  UiIconButton(
                    key: ValueKey('comment-clear-due-${comment.id}'),
                    icon: Icons.close_rounded,
                    tooltip: 'Hapus due date',
                    onPressed: () => onChanged(comment.copyWith(dueDate: null)),
                    size: UiButtonSize.sm,
                  ),
              ],
            ),
            if (comment.attachments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final attachment in comment.attachments)
                UiSurface(
                  key: ValueKey('comment-attachment-${attachment.id}'),
                  color: tokens.panelElevated,
                  borderRadius: BorderRadius.circular(tokens.controlRadius),
                  bordered: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.attach_file_rounded,
                        size: 15,
                        color: tokens.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              attachment.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.text,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              '${attachment.mimeType} · ${_formatBytes(attachment.sizeBytes)}',
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!readOnly) ...[
                        const SizedBox(width: AppSpacing.xs),
                        UiIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Hapus attachment',
                          onPressed: () => _removeAttachment(attachment),
                          size: UiButtonSize.sm,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
            if (onPickAttachment != null)
              Align(
                alignment: Alignment.centerLeft,
                child: UiButton(
                  key: ValueKey('comment-add-attachment-${comment.id}'),
                  onPressed: readOnly ? null : _pickAttachment,
                  variant: UiButtonVariant.ghost,
                  size: UiButtonSize.sm,
                  prefix: const Icon(Icons.attach_file_rounded, size: 13),
                  child: const Text('Attachment'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
