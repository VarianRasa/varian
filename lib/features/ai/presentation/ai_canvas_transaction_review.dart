import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../data/ai_canvas_actions.dart';
import '../domain/ai_canvas_transaction.dart';
import '../state/ai_canvas_transaction_provider.dart';

class AICanvasTransactionReview extends ConsumerWidget {
  final String projectId;

  const AICanvasTransactionReview({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiCanvasTransactionProvider(projectId));
    final tokens = context.appTokens;
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: UiProgressIndicator()),
      );
    }
    final visibleEntries = state.entries
        .where(
          (entry) =>
              entry.isPending ||
              entry.phase == AICanvasTransactionPhase.failed ||
              entry.phase.canUndo,
        )
        .take(5)
        .toList(growable: false);
    if (visibleEntries.isEmpty && state.error == null) {
      return UiSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        color: tokens.panelElevated,
        child: Text(
          'No pending canvas transactions.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: UiAlert(
              title: 'Transaction review issue',
              description: state.error!,
              icon: Icons.error_outline,
              variant: UiAlertVariant.destructive,
            ),
          ),
        for (final entry in visibleEntries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AICanvasTransactionCard(
              entry: entry,
              busy: state.isExecuting,
              onApply: () => ref
                  .read(aiCanvasTransactionProvider(projectId).notifier)
                  .apply(entry.id),
              onInsert: () => ref
                  .read(aiCanvasTransactionProvider(projectId).notifier)
                  .insert(entry.id),
              onReplace: () => ref
                  .read(aiCanvasTransactionProvider(projectId).notifier)
                  .replace(entry.id),
              onReject: () => ref
                  .read(aiCanvasTransactionProvider(projectId).notifier)
                  .reject(entry.id),
              onRetry: () => ref
                  .read(aiCanvasTransactionProvider(projectId).notifier)
                  .retry(entry.id),
              onCancel: () => ref
                  .read(aiCanvasTransactionProvider(projectId).notifier)
                  .cancel(entry.id),
              onUndo: () => ref
                  .read(aiCanvasTransactionProvider(projectId).notifier)
                  .undo(entry.id),
            ),
          ),
      ],
    );
  }
}

class AICanvasTransactionCard extends StatelessWidget {
  final AICanvasTransactionEntry entry;
  final bool busy;
  final VoidCallback? onApply;
  final VoidCallback? onInsert;
  final VoidCallback? onReplace;
  final VoidCallback? onReject;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final VoidCallback? onUndo;

  const AICanvasTransactionCard({
    super.key,
    required this.entry,
    this.busy = false,
    this.onApply,
    this.onInsert,
    this.onReplace,
    this.onReject,
    this.onRetry,
    this.onCancel,
    this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final preview = entry.preview;
    final summary = preview?.text ?? entry.text ?? entry.message ?? '';
    final isFailure = entry.phase == AICanvasTransactionPhase.failed;
    return Semantics(
      container: true,
      label: 'AI canvas action ${entry.action.type.wireName}',
      child: UiSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        color: tokens.panelElevated,
        borderColor: isFailure
            ? tokens.danger.withValues(alpha: 0.5)
            : tokens.panelBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isFailure ? Icons.error_outline : Icons.auto_awesome_outlined,
                  size: 15,
                  color: isFailure ? tokens.danger : tokens.accent,
                ),
                const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                Expanded(
                  child: Text(
                    entry.action.type.wireName,
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: tokens.text,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  entry.phase.label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: isFailure ? tokens.danger : tokens.textMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (summary.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs / 2),
              Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            if (preview != null &&
                (preview.plannedNodes.isNotEmpty ||
                    preview.plannedEdges.isNotEmpty)) ...[
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs / 2),
              Text(
                '${preview.plannedNodes.length} nodes · ${preview.plannedEdges.length} connectors planned',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs + AppSpacing.xxs,
              runSpacing: AppSpacing.xs + AppSpacing.xxs,
              alignment: WrapAlignment.end,
              children: [
                if (entry.canApply) ...[
                  UiButton(
                    size: UiButtonSize.sm,
                    onPressed: busy ? null : onApply,
                    child: const Text('Apply'),
                  ),
                  if (entry.action.isMutation)
                    UiButton(
                      size: UiButtonSize.sm,
                      variant: UiButtonVariant.ghost,
                      onPressed: busy ? null : onInsert,
                      child: const Text('Insert'),
                    ),
                  if (entry.action.isMutation)
                    UiButton(
                      size: UiButtonSize.sm,
                      variant: UiButtonVariant.ghost,
                      onPressed: busy ? null : onReplace,
                      child: const Text('Replace'),
                    ),
                  UiButton(
                    size: UiButtonSize.sm,
                    variant: UiButtonVariant.ghost,
                    onPressed: busy ? null : onReject,
                    child: const Text('Reject'),
                  ),
                ],
                if (entry.phase.canRetry)
                  UiButton(
                    size: UiButtonSize.sm,
                    onPressed: busy ? null : onRetry,
                    prefix: const Icon(Icons.refresh, size: 14),
                    child: const Text('Retry'),
                  ),
                if (entry.canCancel)
                  UiButton(
                    size: UiButtonSize.sm,
                    variant: UiButtonVariant.ghost,
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                if (entry.phase.canUndo)
                  UiButton(
                    size: UiButtonSize.sm,
                    variant: UiButtonVariant.ghost,
                    onPressed: busy ? null : onUndo,
                    prefix: const Icon(Icons.undo, size: 14),
                    child: const Text('Undo'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
