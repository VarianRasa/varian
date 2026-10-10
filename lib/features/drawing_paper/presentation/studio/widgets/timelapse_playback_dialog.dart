import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

class TimelapsePlaybackDialog extends ConsumerStatefulWidget {
  final DrawingPaperPayload initialPayload;

  const TimelapsePlaybackDialog({super.key, required this.initialPayload});

  @override
  ConsumerState<TimelapsePlaybackDialog> createState() =>
      _TimelapsePlaybackDialogState();
}

class _TimelapsePlaybackDialogState
    extends ConsumerState<TimelapsePlaybackDialog> {
  int _currentFrame = 0;
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(
      drawingStudioProviderFamily(widget.initialPayload).notifier,
    );
    final recorder = notifier.timelapseRecorder;
    final totalFrames = recorder.frameCount;
    final tokens = context.appTokens;
    final width = AppResponsive.dialogWidth(context, preferred: 560);
    final height = AppResponsive.dialogHeight(context, preferred: 380);

    return UiDialog(
      semanticsLabel: 'Drawing time-lapse playback',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 560,
        maxHeight: 380,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    color: tokens.accent,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Drawing Time-lapse Playback',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close time-lapse playback',
                    size: UiButtonSize.sm,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Divider(color: tokens.panelBorder, thickness: AppBorder.thin),
              Expanded(
                child: UiSurface(
                  padding: EdgeInsets.zero,
                  color: tokens.canvas,
                  borderRadius: BorderRadius.circular(tokens.controlRadius),
                  child: Center(
                    child: totalFrames > 0
                        ? Text(
                            'Frame: $_currentFrame / $totalFrames\nAction: ${recorder.frames[_currentFrame.clamp(0, totalFrames - 1)].action}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: tokens.info, fontSize: 12),
                          )
                        : Text(
                            'No timelapse steps recorded yet.',
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(color: tokens.textMuted),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  UiIconButton(
                    icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                    tooltip: _isPlaying ? 'Pause playback' : 'Play playback',
                    variant: UiButtonVariant.ghost,
                    onPressed: totalFrames > 0
                        ? () async {
                            final shouldPlay = !_isPlaying;
                            setState(() => _isPlaying = shouldPlay);
                            if (!shouldPlay) return;

                            while (mounted && _isPlaying) {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 120),
                              );
                              if (!mounted || !_isPlaying) break;
                              setState(() {
                                _currentFrame =
                                    (_currentFrame + 1) % totalFrames;
                              });
                            }
                          }
                        : null,
                  ),
                  Expanded(
                    child: UiSlider(
                      key: const ValueKey('timelapse-frame-slider'),
                      label: 'Time-lapse frame',
                      semanticValueFormatterCallback: (value) {
                        final frame = (value * (totalFrames - 1)).round() + 1;
                        return 'Frame $frame of $totalFrames';
                      },
                      value: totalFrames > 1
                          ? (_currentFrame / (totalFrames - 1)).clamp(0.0, 1.0)
                          : 0.0,
                      divisions: totalFrames > 1 ? totalFrames - 1 : null,
                      onChanged: totalFrames > 0
                          ? (value) => setState(
                              () => _currentFrame = (value * (totalFrames - 1))
                                  .round(),
                            )
                          : null,
                    ),
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
