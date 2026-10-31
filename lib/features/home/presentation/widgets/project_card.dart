import 'package:flutter/material.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../../../data/local/local_storage_service.dart';
import '../../../../data/local/durable/durable_project_store.dart';
import 'project_preview_gate.dart';

enum _ProjectCardAction {
  togglePinned,
  rename,
  duplicate,
  restore,
  deletePermanently,
  archive,
  delete,
  adopt,
  deleteFromCloud,
}

class ProjectCard extends StatelessWidget {
  final LocalProjectMetadata project;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<String> onRename;
  final VoidCallback? onTogglePinned;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onDuplicate;
  final VoidCallback? onPurge;
  final VoidCallback? onAdopt;
  final VoidCallback? onCloudDelete;
  final String? cloudDeletionStatusLabel;
  final bool cloudDeletionFailed;
  final DurableProjectStore? durableStore;

  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
    this.onTogglePinned,
    this.onArchive,
    this.onRestore,
    this.onDuplicate,
    this.onPurge,
    this.onAdopt,
    this.onCloudDelete,
    this.cloudDeletionStatusLabel,
    this.cloudDeletionFailed = false,
    this.durableStore,
  });

  @override
  Widget build(BuildContext context) {
    return UiCard(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Semantics(
                  label: CreativeStudioLocalizations.of(
                    context,
                  ).homeOpenDocumentSemanticsLabel(project.name),
                  button: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DeferredProjectPreview(
                          project: project,
                          durableStore: durableStore,
                        ),
                      ),
                      _buildFooter(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: UiMenuButton<_ProjectCardAction>(
              tooltip: CreativeStudioLocalizations.of(
                context,
              ).homeProjectActionsTooltip,
              icon: Icons.more_horiz,
              onSelected: (action) {
                switch (action) {
                  case _ProjectCardAction.togglePinned:
                    onTogglePinned?.call();
                  case _ProjectCardAction.rename:
                    _showRenameDialog(context);
                  case _ProjectCardAction.duplicate:
                    onDuplicate?.call();
                  case _ProjectCardAction.restore:
                    onRestore?.call();
                  case _ProjectCardAction.deletePermanently:
                    onPurge?.call();
                  case _ProjectCardAction.archive:
                    onArchive?.call();
                  case _ProjectCardAction.delete:
                    onDelete();
                  case _ProjectCardAction.adopt:
                    onAdopt?.call();
                  case _ProjectCardAction.deleteFromCloud:
                    onCloudDelete?.call();
                }
              },
              items: [
                if (onAdopt != null)
                  UiMenuAction(
                    value: _ProjectCardAction.adopt,
                    label: CreativeStudioLocalizations.of(
                      context,
                    ).homeProjectAdoptAction,
                    icon: Icons.cloud_upload_outlined,
                  ),
                if (onCloudDelete != null)
                  UiMenuAction(
                    value: _ProjectCardAction.deleteFromCloud,
                    label:
                        cloudDeletionStatusLabel ??
                        CreativeStudioLocalizations.of(
                          context,
                        ).homeProjectDeleteFromCloudAction,
                    icon: Icons.cloud_off_outlined,
                    destructive: cloudDeletionFailed,
                  ),
                UiMenuAction(
                  value: _ProjectCardAction.togglePinned,
                  label: project.isPinned
                      ? CreativeStudioLocalizations.of(
                          context,
                        ).homeProjectUnpinAction
                      : CreativeStudioLocalizations.of(
                          context,
                        ).homeProjectPinAction,
                  icon: project.isPinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  enabled: onTogglePinned != null,
                ),
                UiMenuAction(
                  value: _ProjectCardAction.rename,
                  label: CreativeStudioLocalizations.of(
                    context,
                  ).homeProjectRenameAction,
                  icon: Icons.drive_file_rename_outline,
                ),
                UiMenuAction(
                  value: _ProjectCardAction.duplicate,
                  label: CreativeStudioLocalizations.of(
                    context,
                  ).homeProjectDuplicateAction,
                  icon: Icons.copy_outlined,
                  enabled: onDuplicate != null,
                ),
                if (project.status == ProjectStatus.trashed) ...[
                  UiMenuAction(
                    value: _ProjectCardAction.restore,
                    label: CreativeStudioLocalizations.of(
                      context,
                    ).homeProjectRestoreAction,
                    icon: Icons.restore,
                    enabled: onRestore != null,
                  ),
                  UiMenuAction(
                    value: _ProjectCardAction.deletePermanently,
                    label: CreativeStudioLocalizations.of(
                      context,
                    ).homeProjectDeletePermanentlyAction,
                    icon: Icons.delete_forever,
                    enabled: onPurge != null,
                    destructive: true,
                  ),
                ] else if (project.status == ProjectStatus.archived) ...[
                  UiMenuAction(
                    value: _ProjectCardAction.restore,
                    label: CreativeStudioLocalizations.of(
                      context,
                    ).homeProjectRestoreAction,
                    icon: Icons.unarchive_outlined,
                    enabled: onRestore != null,
                  ),
                  UiMenuAction(
                    value: _ProjectCardAction.delete,
                    label: CreativeStudioLocalizations.of(
                      context,
                    ).homeProjectDeleteAction,
                    icon: Icons.delete_outline,
                    destructive: true,
                  ),
                ] else ...[
                  UiMenuAction(
                    value: _ProjectCardAction.archive,
                    label: CreativeStudioLocalizations.of(
                      context,
                    ).homeProjectArchiveAction,
                    icon: Icons.archive_outlined,
                    enabled: onArchive != null,
                  ),
                  UiMenuAction(
                    value: _ProjectCardAction.delete,
                    label: CreativeStudioLocalizations.of(
                      context,
                    ).homeProjectDeleteAction,
                    icon: Icons.delete_outline,
                    destructive: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final tokens = context.appTokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xl * 2,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: tokens.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CreativeStudioLocalizations.of(
              context,
            ).homeProjectModifiedLabel(_formatDate(project.updatedAt)),
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: tokens.textMuted,
              fontFamily: 'monospace',
              letterSpacing: .2,
            ),
          ),
          if (project.isCollaborationRoom) ...[
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                Icon(Icons.groups_outlined, size: 13, color: tokens.accent),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    CreativeStudioLocalizations.of(
                      context,
                    ).homeProjectCollaborationRoomLabel(
                      project.collaborationRoomCode!,
                      project.collaborationRole ?? 'member',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: tokens.accent,
                      fontFamily: 'monospace',
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (cloudDeletionStatusLabel != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                Icon(
                  cloudDeletionFailed
                      ? Icons.error_outline
                      : Icons.cloud_sync_outlined,
                  size: 13,
                  color: cloudDeletionFailed ? tokens.danger : tokens.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    cloudDeletionStatusLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: cloudDeletionFailed
                          ? tokens.danger
                          : tokens.accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: project.name);
    showUiDialog(
      context: context,
      builder: (dialogContext) {
        final keyboardInset = MediaQuery.viewInsetsOf(dialogContext).bottom;
        final maxHeight =
            (AppResponsive.dialogHeight(dialogContext, preferred: 480) -
                    keyboardInset)
                .clamp(0.0, 480.0)
                .toDouble();
        return UiDialog(
          constraints: AppResponsive.dialogConstraints(
            dialogContext,
            maxWidth: 420,
            maxHeight: maxHeight,
          ),
          semanticsLabel: CreativeStudioLocalizations.of(
            dialogContext,
          ).homeRenameDocumentSemanticsLabel,
          builder: (context, style) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Padding(
                padding: AppResponsive.dialogPadding(dialogContext),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.drive_file_rename_outline,
                          color: context.appTokens.accent,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          CreativeStudioLocalizations.of(
                            context,
                          ).homeRenameDocumentTitle,
                          style: style.titleTextStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    UiTextField(
                      controller: controller,
                      label: CreativeStudioLocalizations.of(
                        context,
                      ).homeDocumentNameLabel,
                      hint: CreativeStudioLocalizations.of(
                        context,
                      ).homeDocumentNameHint,
                      autofocus: true,
                      onSubmitted: (_) {
                        if (controller.text.trim().isNotEmpty) {
                          onRename(controller.text.trim());
                          Navigator.pop(dialogContext);
                        }
                      },
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        UiButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          variant: UiButtonVariant.ghost,
                          child: Text(
                            CreativeStudioLocalizations.of(
                              context,
                            ).cancel.toUpperCase(),
                          ),
                        ),
                        UiButton(
                          onPressed: () {
                            final name = controller.text.trim();
                            if (name.isEmpty) return;
                            onRename(name);
                            Navigator.pop(dialogContext);
                          },
                          child: Text(
                            CreativeStudioLocalizations.of(
                              context,
                            ).save.toUpperCase(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
