import 'package:flutter/material.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/history/snapshot_manager.dart';
import 'package:varian/features/history/version_diff.dart';
import '../../../domain/models/document.dart';

Future<void> showDocumentVersionDiff(
  BuildContext context, {
  required CanvasDocument current,
  required DocumentSnapshotRecord snapshot,
}) async {
  await showUiDialog<void>(
    context: context,
    builder: (_) => VersionDiffDialog(current: current, snapshot: snapshot),
  );
}

class VersionDiffDialog extends StatelessWidget {
  final CanvasDocument current;
  final DocumentSnapshotRecord snapshot;

  const VersionDiffDialog({
    required this.current,
    required this.snapshot,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final diff = DocumentVersionDiff.compare(snapshot.document, current);
    final summaryLines = diff.summaryLines();
    final width = AppResponsive.dialogWidth(context, preferred: 520);
    final height = AppResponsive.dialogHeight(context, preferred: 460);
    return UiDialog(
      semanticsLabel: 'Version diff',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 520,
        maxHeight: 460,
      ),
      builder: (context, style) => Padding(
        padding: AppResponsive.dialogPadding(context),
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('VERSION DIFF', style: style.titleTextStyle),
                    ),
                    UiBadge(
                      diff.isEmpty
                          ? 'No changes'
                          : '${diff.totalChanges} changes',
                      variant: diff.isEmpty
                          ? UiBadgeVariant.secondary
                          : UiBadgeVariant.primary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Text(
                  snapshot.description.trim().isEmpty
                      ? 'Untitled snapshot'
                      : snapshot.description.trim(),
                  style: style.bodyTextStyle,
                ),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: diff.isEmpty
                      ? const Center(
                          child: Text(
                            'Snapshot and active document are identical.',
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: summaryLines.length,
                          separatorBuilder: (_, _) => const SizedBox(
                            height: AppSpacing.xs + AppSpacing.xxs,
                          ),
                          itemBuilder: (context, index) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.change_history_outlined,
                                size: 15,
                                color: context.appTokens.accent,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(child: Text(summaryLines[index])),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
                Align(
                  alignment: Alignment.centerRight,
                  child: UiButton(
                    onPressed: () => Navigator.of(context).pop(),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
