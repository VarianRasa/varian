import 'package:flutter/material.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/cloud_project_deletion.dart';

class CloudProjectDeletionConfirmationDialog extends StatelessWidget {
  const CloudProjectDeletionConfirmationDialog({
    required this.projectName,
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  final String projectName;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final copy = CreativeStudioLocalizations.of(context);
    return UiDialog(
      semanticsLabel: copy.homeProjectDeleteFromCloudTitle,
      builder: (context, style) => Padding(
        padding: AppResponsive.dialogPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_outlined, color: context.appTokens.danger),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    copy.homeProjectDeleteFromCloudTitle,
                    style: style.titleTextStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('“$projectName”'),
            const SizedBox(height: AppSpacing.sm),
            Text(copy.homeProjectDeleteFromCloudDescription(projectName)),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                UiButton(
                  onPressed: onCancel,
                  variant: UiButtonVariant.ghost,
                  child: Text(copy.cancel.toUpperCase()),
                ),
                UiButton(
                  onPressed: onConfirm,
                  variant: UiButtonVariant.destructive,
                  prefix: const Icon(Icons.cloud_off_outlined),
                  child: Text(copy.homeProjectDeleteFromCloudConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CloudProjectDeletionStatusDialog extends StatefulWidget {
  const CloudProjectDeletionStatusDialog({
    required this.initialResult,
    required this.loadStatus,
    required this.retry,
    required this.onStatusChanged,
    required this.onCompleted,
    super.key,
  });

  final CloudProjectDeletionResult initialResult;
  final Future<CloudProjectDeletionResult?> Function() loadStatus;
  final Future<void> Function(String jobId) retry;
  final ValueChanged<CloudProjectDeletionResult> onStatusChanged;
  final Future<void> Function() onCompleted;

  @override
  State<CloudProjectDeletionStatusDialog> createState() =>
      _CloudProjectDeletionStatusDialogState();
}

class _CloudProjectDeletionStatusDialogState
    extends State<CloudProjectDeletionStatusDialog> {
  late CloudProjectDeletionResult _result = widget.initialResult;
  bool _working = false;
  String? _error;

  Future<void> _refresh({bool showBusy = true}) async {
    if (_working && showBusy) return;
    if (showBusy) setState(() => _working = true);
    setState(() => _error = null);
    try {
      final result = await widget.loadStatus();
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _error = CreativeStudioLocalizations.of(
            context,
          ).homeProjectCloudDeletionError;
        });
      } else {
        setState(() => _result = result);
        widget.onStatusChanged(result);
        if (result.status == CloudProjectDeletionStatus.complete) {
          await widget.onCompleted();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = CreativeStudioLocalizations.of(
            context,
          ).homeProjectCloudDeletionError;
        });
      }
    } finally {
      if (mounted && showBusy) setState(() => _working = false);
    }
  }

  Future<void> _retry() async {
    final jobId = _result.jobId;
    if (_working ||
        jobId == null ||
        _result.status != CloudProjectDeletionStatus.failed) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.retry(jobId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = CreativeStudioLocalizations.of(
            context,
          ).homeProjectCloudDeletionError;
        });
      }
    }
    if (mounted) await _refresh(showBusy: false);
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final copy = CreativeStudioLocalizations.of(context);
    final statusColor = switch (_result.status) {
      CloudProjectDeletionStatus.failed => Theme.of(context).colorScheme.error,
      CloudProjectDeletionStatus.complete => context.appTokens.accent,
      _ => Theme.of(context).colorScheme.primary,
    };
    return AlertDialog(
      title: Text(copy.homeProjectCloudDeletionTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _result.status == CloudProjectDeletionStatus.failed
                      ? Icons.error_outline
                      : _result.status == CloudProjectDeletionStatus.complete
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_sync_outlined,
                  color: statusColor,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    copy.homeProjectCloudDeletionLabel(_result.status.name),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(copy.homeProjectCloudDeletionMessage(_result.status.name)),
            if (_result.attemptCount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(copy.homeProjectCloudDeletionAttempts(_result.attemptCount)),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_working) ...[
              const SizedBox(height: AppSpacing.md),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => _refresh(),
          child: Text(copy.homeProjectCloudDeletionRefresh),
        ),
        if (_result.status == CloudProjectDeletionStatus.failed &&
            _result.jobId != null)
          FilledButton(
            onPressed: _working ? null : _retry,
            child: Text(copy.homeProjectCloudDeletionRetry),
          ),
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: Text(copy.close),
        ),
      ],
    );
  }
}
