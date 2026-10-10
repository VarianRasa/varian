import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../snapshot_manager.dart';

/// Displays persisted document versions and delegates all actions to its host.
///
/// This widget intentionally receives [versions] rather than reading or
/// mutating a provider. Hosts can watch [persistedVersionsProvider] and route
/// [onRestore] / [onDelete] through the existing notifier or storage seam.
class RecoveryBrowser extends StatelessWidget {
  final AsyncValue<List<DocumentSnapshotRecord>> versions;
  final FutureOr<void> Function(DocumentSnapshotRecord snapshot)? onRestore;
  final FutureOr<void> Function(DocumentSnapshotRecord snapshot)? onDelete;
  final int maxVersions;
  final String title;

  const RecoveryBrowser({
    required this.versions,
    this.onRestore,
    this.onDelete,
    this.maxVersions = 20,
    this.title = 'Recovery history',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return versions.when(
      loading: () => const _RecoveryState(
        icon: Icons.hourglass_top_rounded,
        title: 'Loading recovery history',
        message: 'Reading saved versions from local storage…',
        progress: true,
      ),
      error: (error, _) => _RecoveryState(
        icon: Icons.error_outline_rounded,
        title: 'Recovery history unavailable',
        message: error.toString(),
        isError: true,
      ),
      data: (records) => _RecoveryData(
        title: title,
        records: records,
        maxVersions: maxVersions,
        onRestore: onRestore,
        onDelete: onDelete,
      ),
    );
  }
}

class _RecoveryState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool progress;
  final bool isError;

  const _RecoveryState({
    required this.icon,
    required this.title,
    required this.message,
    this.progress = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    if (isError) {
      return UiAlert(
        title: title,
        description: message,
        icon: icon,
        variant: UiAlertVariant.destructive,
        liveRegion: true,
      );
    }
    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progress) ...[
            const UiProgressIndicator(
              size: 18,
              semanticsLabel: 'Loading recovery snapshots',
            ),
            const SizedBox(height: AppSpacing.md),
          ] else ...[
            Icon(
              icon,
              size: 32,
              color: isError ? tokens.danger : tokens.textMuted,
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: tokens.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _RecoveryData extends StatelessWidget {
  final String title;
  final List<DocumentSnapshotRecord> records;
  final int maxVersions;
  final FutureOr<void> Function(DocumentSnapshotRecord snapshot)? onRestore;
  final FutureOr<void> Function(DocumentSnapshotRecord snapshot)? onDelete;

  const _RecoveryData({
    required this.title,
    required this.records,
    required this.maxVersions,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const UiEmptyState(
        icon: Icons.restore_rounded,
        title: 'No saved versions',
        message: 'Saved recovery snapshots will appear here.',
      );
    }

    final ordered = records.reversed.toList(growable: false);
    return ConstrainedBox(
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 560,
        maxHeight: 520,
      ),
      child: UiSurface(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${records.length}/$maxVersions saved',
                    semanticsLabel:
                        '${records.length} of $maxVersions recovery versions saved',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: context.appTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: AppBorder.thin),
            Flexible(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: ordered.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: AppBorder.thin),
                itemBuilder: (context, index) => _RecoveryRecordTile(
                  snapshot: ordered[index],
                  onRestore: onRestore,
                  onDelete: onDelete,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryRecordTile extends StatelessWidget {
  final DocumentSnapshotRecord snapshot;
  final FutureOr<void> Function(DocumentSnapshotRecord snapshot)? onRestore;
  final FutureOr<void> Function(DocumentSnapshotRecord snapshot)? onDelete;

  const _RecoveryRecordTile({
    required this.snapshot,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final description = snapshot.description.trim().isEmpty
        ? 'Untitled snapshot'
        : snapshot.description.trim();
    final nodeCount = snapshot.document.nodes.length;
    final edgeCount = snapshot.document.edges.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + AppSpacing.xxs,
        AppSpacing.sm,
        AppSpacing.sm + AppSpacing.xxs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history_rounded, size: 18, color: tokens.textMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${_formatTimestamp(snapshot.timestamp)} · $nodeCount nodes · $edgeCount edges',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          if (onRestore != null)
            UiIconButton(
              icon: Icons.restore_rounded,
              tooltip: 'Restore $description',
              onPressed: () => onRestore!(snapshot),
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
            ),
          if (onDelete != null)
            UiIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete $description',
              onPressed: () => onDelete!(snapshot),
              variant: UiButtonVariant.destructive,
              size: UiButtonSize.sm,
            ),
        ],
      ),
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
