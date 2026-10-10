import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import '../../../../data/local/local_storage_service.dart';
import '../../../onboarding/presentation/onboarding_dialog.dart';
import '../../../onboarding/state/onboarding_provider.dart';

class WorkspaceHelpButton extends ConsumerWidget {
  const WorkspaceHelpButton({super.key});

  Future<void> _resumeOnboarding(BuildContext context, WidgetRef ref) async {
    await ref.read(onboardingProvider.notifier).resume();
    if (context.mounted) await showOnboardingDialog(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = MenuController();
    final copy = CreativeStudioLocalizations.of(context);
    return MenuAnchor(
      key: const ValueKey('workspace-help-popover'),
      controller: controller,
      alignmentOffset: const Offset(0, AppSpacing.sm),
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Builder(
            builder: (context) {
              final tokens = context.appTokens;
              return UiSurface(
                color: tokens.panelElevated,
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 18,
                          color: tokens.accent,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            copy.workspaceQuickStart,
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(
                                  color: tokens.text,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        UiIconButton(
                          icon: Icons.close,
                          tooltip: copy.workspaceHelpClose,
                          size: UiButtonSize.sm,
                          onPressed: controller.close,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _HelpStep(number: '1', text: copy.workspaceHelpStepOne),
                    const SizedBox(height: AppSpacing.sm),
                    _HelpStep(number: '2', text: copy.workspaceHelpStepTwo),
                    const SizedBox(height: AppSpacing.sm),
                    _HelpStep(number: '3', text: copy.workspaceHelpStepThree),
                    const SizedBox(height: AppSpacing.sm),
                    _HelpStep(number: '4', text: copy.workspaceHelpStepFour),
                    const SizedBox(height: AppSpacing.md),
                    UiButton(
                      key: const ValueKey('resume-onboarding-button'),
                      onPressed: () {
                        controller.close();
                        unawaited(_resumeOnboarding(context, ref));
                      },
                      variant: UiButtonVariant.outline,
                      prefix: const Icon(Icons.school_outlined),
                      child: Text(copy.workspaceResumeGuide),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
      builder: (context, controller, child) => UiIconButton(
        key: const ValueKey('workspace-help-button'),
        icon: Icons.help_outline,
        tooltip: copy.workspaceHelpLabel,
        onPressed: controller.open,
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  final String number;
  final String text;

  const _HelpStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.accentSoft,
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 20,
            height: 20,
            child: Center(
              child: Text(
                number,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: tokens.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: tokens.textMuted,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class BulkProjectActionDialog extends StatefulWidget {
  final ProjectStatus status;
  final int count;
  final bool permanent;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const BulkProjectActionDialog({
    required this.status,
    required this.count,
    required this.permanent,
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  @override
  State<BulkProjectActionDialog> createState() =>
      _BulkProjectActionDialogState();
}

class _BulkProjectActionDialogState extends State<BulkProjectActionDialog> {
  late final TextEditingController _confirmationController;

  bool get _canConfirm =>
      !widget.permanent ||
      _confirmationController.text.trim().toUpperCase() ==
          CreativeStudioLocalizations.of(context).homeDeleteConfirmationWord;

  @override
  void initState() {
    super.initState();
    _confirmationController = TextEditingController();
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight =
        (AppResponsive.dialogHeight(context, preferred: 560) - keyboardInset)
            .clamp(0.0, 560.0)
            .toDouble();
    return UiDialog(
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 460,
        maxHeight: maxHeight,
      ),
      semanticsLabel: widget.permanent
          ? CreativeStudioLocalizations.of(
              context,
            ).homeConfirmEmptyTrashSemanticsLabel
          : CreativeStudioLocalizations.of(
              context,
            ).homeConfirmMoveAllToTrashSemanticsLabel,
      builder: (context, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Builder(
              builder: (context) {
                final tokens = context.appTokens;
                final copy = CreativeStudioLocalizations.of(context);
                final title = widget.permanent
                    ? copy.homeDeleteAllPermanentlyTitle
                    : copy.homeMoveAllToTrashTitle;
                final description = widget.permanent
                    ? copy.homeDeleteAllPermanentlyDescription(widget.count)
                    : copy.homeMoveAllToTrashDescription(
                        widget.count,
                        _statusLabel(widget.status),
                      );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.accentSoft,
                            borderRadius: BorderRadius.circular(
                              tokens.controlRadius,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: Icon(
                              widget.permanent
                                  ? Icons.delete_forever_outlined
                                  : Icons.delete_outline,
                              color: tokens.danger,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(title, style: style.titleTextStyle),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: tokens.textMuted,
                        height: 1.4,
                      ),
                    ),
                    if (widget.permanent) ...[
                      const SizedBox(height: AppSpacing.lg),
                      UiTextField(
                        key: const ValueKey('bulk-delete-confirmation'),
                        controller: _confirmationController,
                        label: copy.homeDeleteConfirmationLabel(
                          copy.homeDeleteConfirmationWord,
                        ),
                        hint: copy.homeDeleteConfirmationHint,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        UiButton(
                          onPressed: widget.onCancel,
                          variant: UiButtonVariant.ghost,
                          child: Text(copy.cancel.toUpperCase()),
                        ),
                        UiButton(
                          onPressed: _canConfirm ? widget.onConfirm : null,
                          variant: UiButtonVariant.destructive,
                          prefix: Icon(
                            widget.permanent
                                ? Icons.delete_forever_outlined
                                : Icons.delete_outline,
                          ),
                          child: Text(
                            widget.permanent
                                ? copy.homeDeleteAllPermanentlyAction
                                : copy.homeMoveAllToTrashConfirmAction,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(ProjectStatus status) {
    final copy = CreativeStudioLocalizations.of(context);
    return switch (status) {
      ProjectStatus.active => copy.homeStatusActive.toLowerCase(),
      ProjectStatus.archived => copy.homeStatusArchived.toLowerCase(),
      ProjectStatus.trashed => copy.homeStatusTrash.toLowerCase(),
    };
  }
}

class ProjectStatusTabLabel extends StatelessWidget {
  final String label;
  final int count;
  final bool compact;

  const ProjectStatusTabLabel({
    required this.label,
    required this.count,
    required this.compact,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: CreativeStudioLocalizations.of(
      context,
    ).homeStatusSemanticsLabel(label, count),
    child: compact
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: AppSpacing.sm),
              UiBadge('$count', variant: UiBadgeVariant.secondary),
            ],
          ),
  );
}

class DeleteProjectDialog extends StatelessWidget {
  final LocalProjectMetadata project;
  final bool permanent;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const DeleteProjectDialog({
    required this.project,
    required this.permanent,
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight =
        (AppResponsive.dialogHeight(context, preferred: 520) - keyboardInset)
            .clamp(0.0, 520.0)
            .toDouble();
    return UiDialog(
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 440,
        maxHeight: maxHeight,
      ),
      semanticsLabel: permanent
          ? CreativeStudioLocalizations.of(
              context,
            ).homeConfirmPermanentDocumentDeleteSemanticsLabel
          : CreativeStudioLocalizations.of(
              context,
            ).homeConfirmMoveDocumentToTrashSemanticsLabel,
      builder: (context, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Builder(
              builder: (context) {
                final tokens = context.appTokens;
                final copy = CreativeStudioLocalizations.of(context);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.accentSoft,
                            borderRadius: BorderRadius.circular(
                              tokens.controlRadius,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: Icon(
                              permanent
                                  ? Icons.delete_forever_outlined
                                  : Icons.delete_outline,
                              color: tokens.danger,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            permanent
                                ? copy.homeDeleteDocumentPermanentlyTitle
                                : copy.homeMoveDocumentToTrashTitle,
                            style: style.titleTextStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      '“${project.name}”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      permanent
                          ? copy.homeDeleteDocumentPermanentlyDescription
                          : copy.homeMoveDocumentToTrashDescription,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cancelButton = UiButton(
                          onPressed: onCancel,
                          variant: UiButtonVariant.ghost,
                          child: Text(copy.cancel.toUpperCase()),
                        );
                        final confirmButton = UiButton(
                          onPressed: onConfirm,
                          variant: UiButtonVariant.destructive,
                          prefix: Icon(
                            permanent
                                ? Icons.delete_forever_outlined
                                : Icons.delete_outline,
                          ),
                          child: Text(
                            permanent
                                ? copy.homeDeleteDocumentPermanentlyAction
                                : copy.homeMoveDocumentToTrashAction,
                          ),
                        );
                        if (constraints.maxWidth < 460) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              cancelButton,
                              const SizedBox(height: AppSpacing.sm),
                              confirmButton,
                            ],
                          );
                        }
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            cancelButton,
                            const SizedBox(width: AppSpacing.sm),
                            confirmButton,
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
