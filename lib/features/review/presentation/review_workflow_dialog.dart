import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../domain/review_workflow.dart';
import '../state/review_workflow_provider.dart';

class ReviewWorkflowDialog extends ConsumerStatefulWidget {
  final String projectId;
  final String actorId;
  final bool canEditCanvas;
  final String? selectedNodeId;
  final Future<void> Function()? onPublishPreview;

  const ReviewWorkflowDialog({
    required this.projectId,
    required this.actorId,
    required this.canEditCanvas,
    this.selectedNodeId,
    this.onPublishPreview,
    super.key,
  });

  @override
  ConsumerState<ReviewWorkflowDialog> createState() =>
      _ReviewWorkflowDialogState();
}

class _ReviewWorkflowDialogState extends ConsumerState<ReviewWorkflowDialog> {
  final _reviewersController = TextEditingController();
  final _spotlightNodeController = TextEditingController();
  final _checklistController = TextEditingController();
  final _stepTitleController = TextEditingController();
  final _stepDescriptionController = TextEditingController();
  final _stepNodeController = TextEditingController();
  final _notesFrameController = TextEditingController();
  final _notesController = TextEditingController();
  String? _editingStepId;
  String _spotlightDuration = '15m';
  bool _draftsInitialized = false;

  ReviewWorkflowNotifier get _notifier =>
      ref.read(reviewWorkflowProvider(widget.projectId).notifier);

  @override
  void initState() {
    super.initState();
    _notifier.configure(
      actorId: widget.actorId,
      canEditCanvas: widget.canEditCanvas,
    );
  }

  @override
  void didUpdateWidget(covariant ReviewWorkflowDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actorId != widget.actorId ||
        oldWidget.canEditCanvas != widget.canEditCanvas) {
      _notifier.configure(
        actorId: widget.actorId,
        canEditCanvas: widget.canEditCanvas,
      );
    }
  }

  @override
  void dispose() {
    _reviewersController.dispose();
    _spotlightNodeController.dispose();
    _checklistController.dispose();
    _stepTitleController.dispose();
    _stepDescriptionController.dispose();
    _stepNodeController.dispose();
    _notesFrameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _initializeDrafts(ReviewWorkflow workflow) {
    if (_draftsInitialized) return;
    _draftsInitialized = true;
    _reviewersController.text = workflow.reviewerIds.join(', ');
    _spotlightNodeController.text = workflow.spotlightNodeId ?? '';
    _notesFrameController.text = widget.selectedNodeId ?? '';
    if (_notesFrameController.text.isNotEmpty) {
      _notesController.text =
          workflow.speakerNotes[_notesFrameController.text] ?? '';
    }
    final expiresAt = workflow.spotlightExpiresAt;
    if (expiresAt == null) {
      _spotlightDuration = 'forever';
    } else {
      final remaining = expiresAt.difference(DateTime.now().toUtc());
      if (remaining <= const Duration(minutes: 7)) {
        _spotlightDuration = '5m';
      } else if (remaining <= const Duration(minutes: 20)) {
        _spotlightDuration = '15m';
      } else {
        _spotlightDuration = '1h';
      }
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        showUiToast(
          context,
          'Review action failed: $error',
          variant: UiToastVariant.error,
        );
      }
      return false;
    }
  }

  Future<void> _saveReviewers() async {
    final values = _reviewersController.text.split(RegExp(r'[,;\n]+'));
    await _run(() => _notifier.setReviewers(values));
  }

  Future<void> _applySpotlight() async {
    final duration = switch (_spotlightDuration) {
      '5m' => const Duration(minutes: 5),
      '15m' => const Duration(minutes: 15),
      '1h' => const Duration(hours: 1),
      _ => null,
    };
    await _run(
      () => _notifier.setSpotlight(
        _spotlightNodeController.text,
        duration: duration,
      ),
    );
  }

  Future<void> _addChecklistItem() async {
    final label = _checklistController.text.trim();
    if (label.isEmpty) return;
    if (await _run(() => _notifier.addChecklistItem(label)) && mounted) {
      _checklistController.clear();
    }
  }

  void _beginStepEdit(ReviewWalkthroughStep step) {
    setState(() {
      _editingStepId = step.id;
      _stepTitleController.text = step.title;
      _stepDescriptionController.text = step.description;
      _stepNodeController.text = step.nodeId ?? '';
    });
  }

  void _clearStepEditor() {
    _editingStepId = null;
    _stepTitleController.clear();
    _stepDescriptionController.clear();
    _stepNodeController.clear();
  }

  Future<void> _saveWalkthroughStep(ReviewWorkflow workflow) async {
    final title = _stepTitleController.text.trim();
    if (title.isEmpty) return;
    final saved = await _run(
      () => _notifier.upsertWalkthroughStep(
        id: _editingStepId,
        title: title,
        description: _stepDescriptionController.text,
        nodeId: _stepNodeController.text,
        order: _editingStepId == null ? workflow.walkthrough.length : null,
      ),
    );
    if (saved && mounted) setState(_clearStepEditor);
  }

  void _loadSpeakerNote(ReviewWorkflow workflow) {
    final frameId = _notesFrameController.text.trim();
    setState(() {
      _notesController.text = frameId.isEmpty
          ? ''
          : workflow.speakerNotes[frameId] ?? '';
    });
  }

  Future<void> _saveSpeakerNote() async {
    final frameId = _notesFrameController.text.trim();
    if (frameId.isEmpty) return;
    await _run(() => _notifier.setSpeakerNotes(frameId, _notesController.text));
  }

  @override
  Widget build(BuildContext context) {
    final workflowValue = ref.watch(reviewWorkflowProvider(widget.projectId));
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 760);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 700);
    return UiDialog(
      key: const ValueKey('review-workflow-dialog'),
      semanticsLabel: 'Review and handoff workflow',
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
                    child: Text(
                      'Review & Handoff',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close review workflow',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: workflowValue.when(
                  loading: () =>
                      const SizedBox(height: 180, child: UiLoadingState()),
                  error: (error, _) => _buildError(error),
                  data: (workflow) {
                    _initializeDrafts(workflow);
                    return _buildContent(context, workflow);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (widget.onPublishPreview != null)
                    UiButton(
                      key: const ValueKey('review-publish-preview'),
                      onPressed: widget.canEditCanvas
                          ? () => unawaited(_run(widget.onPublishPreview!))
                          : null,
                      prefix: const Icon(Icons.publish_outlined, size: 16),
                      child: const Text('Publish preview'),
                    ),
                  UiButton(
                    key: const ValueKey('review-close'),
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(Object error) => SizedBox(
    height: 180,
    child: Center(
      child: Semantics(
        liveRegion: true,
        child: Text('Review workflow unavailable: $error'),
      ),
    ),
  );

  Widget _buildContent(BuildContext context, ReviewWorkflow workflow) {
    final canReview = workflow.canReview(
      widget.actorId,
      canEditCanvas: widget.canEditCanvas,
    );
    final isReviewer = workflow.isReviewer(widget.actorId);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiAlert(
            title: 'Review workspace',
            description:
                'Coordinate approvals and the final handoff without changing the draft.',
            icon: Icons.rate_review_outlined,
            variant: UiAlertVariant.info,
            trailing: UiBadge(
              key: const ValueKey('review-permission-chip'),
              canReview ? (isReviewer ? 'Reviewer' : 'Editor') : 'View only',
              variant: UiBadgeVariant.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _section(
            title: 'Approval',
            children: [
              UiSelect<ReviewApprovalState>(
                key: const ValueKey('review-approval-state'),
                label: 'Status',
                value: workflow.approvalState,
                items: {
                  for (final value in ReviewApprovalState.values)
                    _approvalLabel(value): value,
                },
                enabled: canReview,
                onChanged: (value) {
                  if (canReview && value != null) {
                    unawaited(_run(() => _notifier.setApprovalState(value)));
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                workflow.updatedBy == null
                    ? 'No review activity yet.'
                    : 'Updated by ${workflow.updatedBy}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _section(
            title: 'Reviewer access',
            children: [
              UiTextField(
                key: const ValueKey('review-reviewers'),
                controller: _reviewersController,
                label: 'Reviewer IDs',
                description: 'Separate IDs with commas or new lines.',
                minLines: 2,
                maxLines: 3,
                enabled: widget.canEditCanvas,
              ),
              const SizedBox(height: AppSpacing.sm),
              UiButton(
                key: const ValueKey('review-save-reviewers'),
                onPressed: widget.canEditCanvas
                    ? () => unawaited(_saveReviewers())
                    : null,
                child: const Text('Save reviewer access'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _section(
            title: 'Spotlight',
            children: [
              UiTextField(
                key: const ValueKey('review-spotlight-node'),
                controller: _spotlightNodeController,
                label: 'Node ID',
                hint: 'Select a node or enter its ID',
                enabled: canReview,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.outline,
                    key: const ValueKey('review-use-selected-node'),
                    onPressed: widget.selectedNodeId == null
                        ? null
                        : () => setState(
                            () => _spotlightNodeController.text =
                                widget.selectedNodeId!,
                          ),
                    child: const Text('Use selected node'),
                  ),
                  UiSelect<String>(
                    key: const ValueKey('review-spotlight-duration'),
                    value: _spotlightDuration,
                    items: const {
                      '5 minutes': '5m',
                      '15 minutes': '15m',
                      '1 hour': '1h',
                      'Until cleared': 'forever',
                    },
                    enabled: canReview,
                    onChanged: (value) {
                      if (canReview && value != null) {
                        setState(() => _spotlightDuration = value);
                      }
                    },
                  ),
                  UiButton(
                    key: const ValueKey('review-apply-spotlight'),
                    onPressed: canReview
                        ? () => unawaited(_applySpotlight())
                        : null,
                    child: const Text('Apply spotlight'),
                  ),
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    key: const ValueKey('review-clear-spotlight'),
                    onPressed: canReview
                        ? () => unawaited(
                            _run(() => _notifier.setSpotlight(null)),
                          )
                        : null,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              if (workflow.isSpotlightActive())
                Text(
                  'Active on ${workflow.spotlightNodeId}.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _section(
            title: 'Handoff checklist',
            children: [
              UiTextField(
                key: const ValueKey('review-checklist-input'),
                controller: _checklistController,
                label: 'Checklist item',
                hint: 'Example: Confirm responsive export',
                enabled: widget.canEditCanvas,
                onSubmitted: widget.canEditCanvas
                    ? (_) => unawaited(_addChecklistItem())
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              UiButton(
                key: const ValueKey('review-add-checklist'),
                onPressed: widget.canEditCanvas
                    ? () => unawaited(_addChecklistItem())
                    : null,
                prefix: const Icon(Icons.add, size: 16),
                child: const Text('Add item'),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (workflow.handoffChecklist.isEmpty)
                Text(
                  'No checklist items yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                for (final item in workflow.handoffChecklist)
                  _checklistRow(item, canReview, widget.canEditCanvas),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _section(
            title: 'Walkthrough',
            children: [
              UiTextField(
                key: const ValueKey('review-step-title'),
                controller: _stepTitleController,
                label: 'Step title',
                enabled: canReview,
              ),
              const SizedBox(height: AppSpacing.sm),
              UiTextField(
                key: const ValueKey('review-step-description'),
                controller: _stepDescriptionController,
                label: 'Description',
                minLines: 2,
                maxLines: 4,
                enabled: canReview,
              ),
              const SizedBox(height: AppSpacing.sm),
              UiTextField(
                key: const ValueKey('review-step-node'),
                controller: _stepNodeController,
                label: 'Node ID (optional)',
                enabled: canReview,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    key: const ValueKey('review-save-step'),
                    onPressed: canReview
                        ? () => unawaited(_saveWalkthroughStep(workflow))
                        : null,
                    child: Text(
                      _editingStepId == null ? 'Add step' : 'Update step',
                    ),
                  ),
                  if (_editingStepId != null)
                    UiButton(
                      key: const ValueKey('review-cancel-step'),
                      variant: UiButtonVariant.ghost,
                      size: UiButtonSize.sm,
                      onPressed: () => setState(_clearStepEditor),
                      child: const Text('Cancel'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (workflow.orderedWalkthrough.isEmpty)
                Text(
                  'No walkthrough steps yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                for (final step in workflow.orderedWalkthrough)
                  _walkthroughRow(step, canReview),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _section(
            title: 'Speaker notes',
            children: [
              UiTextField(
                key: const ValueKey('review-notes-frame'),
                controller: _notesFrameController,
                label: 'Frame or node ID',
                enabled: canReview,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  UiButton(
                    key: const ValueKey('review-notes-use-selected'),
                    variant: UiButtonVariant.ghost,
                    size: UiButtonSize.sm,
                    onPressed: widget.selectedNodeId == null
                        ? null
                        : () {
                            _notesFrameController.text = widget.selectedNodeId!;
                            _loadSpeakerNote(workflow);
                          },
                    child: const Text('Use selected node'),
                  ),
                  UiButton(
                    key: const ValueKey('review-load-note'),
                    variant: UiButtonVariant.ghost,
                    size: UiButtonSize.sm,
                    onPressed: canReview
                        ? () => _loadSpeakerNote(workflow)
                        : null,
                    child: const Text('Load note'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              UiTextField(
                key: const ValueKey('review-speaker-notes'),
                controller: _notesController,
                label: 'Notes',
                minLines: 3,
                maxLines: 6,
                enabled: canReview,
              ),
              const SizedBox(height: AppSpacing.sm),
              UiButton(
                key: const ValueKey('review-save-notes'),
                onPressed: canReview
                    ? () => unawaited(_saveSpeakerNote())
                    : null,
                child: const Text('Save speaker notes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required List<Widget> children}) =>
      UiSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      );

  Widget _checklistRow(
    ReviewChecklistItem item,
    bool canReview,
    bool canEdit,
  ) => Row(
    key: ValueKey('review-checklist-${item.id}'),
    children: [
      UiCheckbox(
        value: item.completed,
        enabled: canReview,
        semanticsLabel: 'Complete ${item.label}',
        onChange: canReview
            ? (_) =>
                  unawaited(_run(() => _notifier.toggleChecklistItem(item.id)))
            : null,
      ),
      Expanded(
        child: Text(
          item.label,
          style: TextStyle(
            decoration: item.completed ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
      if (canEdit)
        UiIconButton(
          key: ValueKey('review-remove-checklist-${item.id}'),
          icon: Icons.delete_outline,
          tooltip: 'Remove checklist item',
          onPressed: () =>
              unawaited(_run(() => _notifier.removeChecklistItem(item.id))),
        ),
    ],
  );

  Widget _walkthroughRow(ReviewWalkthroughStep step, bool canReview) {
    final details = [
      if (step.description.isNotEmpty) step.description,
      if (step.nodeId != null && step.nodeId!.isNotEmpty)
        'Node: ${step.nodeId}',
    ].join('\n');
    final actions = canReview
        ? Wrap(
            spacing: 0,
            children: [
              UiIconButton(
                key: ValueKey('review-edit-step-${step.id}'),
                icon: Icons.edit_outlined,
                tooltip: 'Edit walkthrough step',
                onPressed: () => _beginStepEdit(step),
              ),
              UiIconButton(
                key: ValueKey('review-remove-step-${step.id}'),
                icon: Icons.delete_outline,
                tooltip: 'Remove walkthrough step',
                onPressed: () => unawaited(
                  _run(() => _notifier.removeWalkthroughStep(step.id)),
                ),
              ),
            ],
          )
        : null;

    return UiSurface(
      key: ValueKey('review-walkthrough-${step.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xxs,
        vertical: AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.title),
              if (details.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs - AppSpacing.xxs),
                Text(details, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          );
          if (actions == null) return content;
          if (constraints.maxWidth < 320) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: content),
              const SizedBox(width: AppSpacing.sm),
              actions,
            ],
          );
        },
      ),
    );
  }

  String _approvalLabel(ReviewApprovalState state) => switch (state) {
    ReviewApprovalState.draft => 'Draft',
    ReviewApprovalState.inReview => 'In review',
    ReviewApprovalState.changesRequested => 'Changes requested',
    ReviewApprovalState.approved => 'Approved',
  };
}
