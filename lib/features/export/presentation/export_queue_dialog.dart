import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../export_queue.dart';

class ExportQueueDialog extends StatelessWidget {
  final ExportQueue queue;

  const ExportQueueDialog({required this.queue, super.key});

  @override
  Widget build(BuildContext context) {
    final width = AppResponsive.dialogWidth(context, preferred: 620);
    final height = AppResponsive.dialogHeight(context, preferred: 520);
    return UiDialog(
      semanticsLabel: 'Export queue',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 620,
        maxHeight: 520,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        height: height,
        child: AnimatedBuilder(
          animation: queue,
          builder: (context, _) => Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('EXPORT QUEUE', style: style.titleTextStyle),
                    ),
                    UiIconButton(
                      icon: Icons.close,
                      tooltip: 'Close export queue',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('${queue.jobs.length} job(s) tracked'),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                Expanded(
                  child: queue.jobs.isEmpty
                      ? const Center(child: Text('No export jobs yet.'))
                      : ListView.separated(
                          itemCount: queue.jobs.length,
                          separatorBuilder: (_, _) => Divider(
                            height: AppBorder.thin,
                            color: context.appTokens.panelBorder,
                          ),
                          itemBuilder: (context, index) => _ExportQueueJobTile(
                            queue: queue,
                            job: queue.jobs[index],
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    UiButton(
                      onPressed: queue.jobs.any((job) => job.isTerminal)
                          ? queue.clearTerminal
                          : null,
                      variant: UiButtonVariant.ghost,
                      child: const Text('Clear finished'),
                    ),
                    UiButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportQueueJobTile extends StatelessWidget {
  final ExportQueue queue;
  final ExportQueueJob job;

  const _ExportQueueJobTile({required this.queue, required this.job});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.preset.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                liveRegion: true,
                child: Text(
                  '${job.id} • ${_statusLabel(job.status)}${job.error == null ? '' : ' • ${job.error}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.appTokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (job.status == ExportQueueJobStatus.queued ||
            job.status == ExportQueueJobStatus.running)
          UiIconButton(
            icon: Icons.close,
            tooltip: 'Cancel ${job.preset.label}',
            onPressed: () => queue.cancel(job.id),
          ),
        if (job.status == ExportQueueJobStatus.failed ||
            job.status == ExportQueueJobStatus.canceled)
          UiButton(
            onPressed: () => queue.retry(job.id),
            variant: UiButtonVariant.ghost,
            size: UiButtonSize.sm,
            prefix: const Icon(Icons.refresh, size: 15),
            child: const Text('Retry'),
          ),
      ],
    ),
  );
}

String _statusLabel(ExportQueueJobStatus status) => switch (status) {
  ExportQueueJobStatus.queued => 'queued',
  ExportQueueJobStatus.running => 'running',
  ExportQueueJobStatus.completed => 'completed',
  ExportQueueJobStatus.failed => 'failed',
  ExportQueueJobStatus.canceled => 'canceled',
};
