import 'package:flutter/material.dart';

import '../../../../app/responsive.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../../../domain/models/vector_path_payload.dart';

enum VectorPathToolAction {
  insertAnchor,
  removeAnchor,
  splitContour,
  joinContours,
  booleanUnion,
  booleanIntersect,
  booleanDifference,
  booleanXor,
}

class VectorPathToolsDialog extends StatelessWidget {
  final VectorPathPayload payload;
  final bool hasBooleanTarget;

  const VectorPathToolsDialog({
    super.key,
    required this.payload,
    required this.hasBooleanTarget,
  });

  @override
  Widget build(BuildContext context) {
    final canRemove = payload.points.length > (payload.isClosed ? 3 : 2);
    final canSplit = payload.points.length >= 3;
    final canJoin = payload.subpaths.length >= 2;
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 460);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 560);
    return UiDialog(
      semanticsLabel: 'Vector path tools',
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
                      'Vector path tools',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close vector path tools',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _actionTile(
                      context,
                      VectorPathToolAction.insertAnchor,
                      Icons.add_circle_outline,
                      'Insert midpoint anchor',
                      'Split the first segment without changing its visible curve.',
                    ),
                    _actionTile(
                      context,
                      VectorPathToolAction.removeAnchor,
                      Icons.remove_circle_outline,
                      'Remove last anchor',
                      'Remove the last safe anchor from this contour.',
                      enabled: canRemove,
                    ),
                    _actionTile(
                      context,
                      VectorPathToolAction.splitContour,
                      Icons.call_split_outlined,
                      'Split contour',
                      'Split the active contour into two editable open contours.',
                      enabled: canSplit,
                    ),
                    _actionTile(
                      context,
                      VectorPathToolAction.joinContours,
                      Icons.call_merge_outlined,
                      'Join first two contours',
                      'Join two contours into one editable path.',
                      enabled: canJoin,
                    ),
                    if (hasBooleanTarget) ...[
                      const Divider(),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        child: Text(
                          'Boolean with the other selected vector',
                          style: Theme.of(context).textTheme.bodyMedium!
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      _actionTile(
                        context,
                        VectorPathToolAction.booleanUnion,
                        Icons.merge_type,
                        'Union',
                        'Combine the selected vector areas.',
                      ),
                      _actionTile(
                        context,
                        VectorPathToolAction.booleanIntersect,
                        Icons.interests_outlined,
                        'Intersect',
                        'Keep only the overlapping area.',
                      ),
                      _actionTile(
                        context,
                        VectorPathToolAction.booleanDifference,
                        Icons.content_cut_outlined,
                        'Subtract',
                        'Subtract the other vector from this one.',
                      ),
                      _actionTile(
                        context,
                        VectorPathToolAction.booleanXor,
                        Icons.join_full_outlined,
                        'Exclude overlap',
                        'Keep non-overlapping areas from both vectors.',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  variant: UiButtonVariant.ghost,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile(
    BuildContext context,
    VectorPathToolAction action,
    IconData icon,
    String title,
    String subtitle, {
    bool enabled = true,
  }) {
    final tokens = context.appTokens;
    return UiSurface(
      color: tokens.panelElevated,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      child: UiButton(
        onPressed: enabled ? () => Navigator.of(context).pop(action) : null,
        variant: UiButtonVariant.ghost,
        mainAxisSize: MainAxisSize.max,
        prefix: Icon(icon),
        child: Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
