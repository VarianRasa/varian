import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/responsive.dart';
import '../../app/widgets/ui_primitives.dart';
import 'domain/storyboard_timeline.dart';

class PresentationTimelineDialog extends StatefulWidget {
  final PresentationTimeline initialTimeline;

  const PresentationTimelineDialog({super.key, required this.initialTimeline});

  @override
  State<PresentationTimelineDialog> createState() =>
      _PresentationTimelineDialogState();
}

class _PresentationTimelineDialogState
    extends State<PresentationTimelineDialog> {
  late List<StoryboardShot> _shots;

  @override
  void initState() {
    super.initState();
    _shots = [...widget.initialTimeline.shots];
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 680);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 520);
    return UiDialog(
      semanticsLabel: 'Storyboard timeline',
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
                      'Storyboard timeline',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close storyboard timeline',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: _shots.isEmpty
                    ? const Center(child: Text('No storyboard shots yet.'))
                    : ReorderableListView.builder(
                        itemCount: _shots.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final shot = _shots.removeAt(oldIndex);
                            _shots.insert(newIndex, shot);
                          });
                        },
                        itemBuilder: (context, index) {
                          final shot = _shots[index];
                          final tokens = context.appTokens;
                          return UiSurface(
                            key: ValueKey(shot.id),
                            color: tokens.panelElevated,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                leading: Icon(
                                  Icons.drag_handle,
                                  color: tokens.textMuted,
                                ),
                                title: Text(
                                  shot.title,
                                  style: TextStyle(color: tokens.text),
                                ),
                                subtitle: Text(
                                  '${shot.frameId} · ${shot.duration.inSeconds}s · ${shot.status.name}',
                                  style: TextStyle(color: tokens.textMuted),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right,
                                  color: tokens.textMuted,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    onPressed: () => Navigator.of(dialogContext).pop(
                      PresentationTimeline(
                        shots: _shots,
                        tracks: widget.initialTimeline.tracks,
                      ),
                    ),
                    prefix: const Icon(Icons.check, size: 16),
                    child: const Text('Apply order'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
