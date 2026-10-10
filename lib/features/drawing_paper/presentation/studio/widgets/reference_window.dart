import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

class _MoveReferenceWindowIntent extends Intent {
  const _MoveReferenceWindowIntent(this.offset);

  final Offset offset;
}

class ReferenceWindowView extends ConsumerStatefulWidget {
  final DrawingPaperPayload initialPayload;

  const ReferenceWindowView({super.key, required this.initialPayload});

  @override
  ConsumerState<ReferenceWindowView> createState() =>
      _ReferenceWindowViewState();
}

class _ReferenceWindowViewState extends ConsumerState<ReferenceWindowView> {
  static const double _keyboardMoveStep = 10;
  final double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(drawingStudioProviderFamily(widget.initialPayload));
    final notifier = ref.read(
      drawingStudioProviderFamily(widget.initialPayload).notifier,
    );
    final refCfg = state.payload.referenceConfig;
    final tokens = context.appTokens;

    if (!refCfg.visible) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = refCfg.width.clamp(0.0, constraints.maxWidth).toDouble();
        final height = refCfg.height
            .clamp(0.0, constraints.maxHeight)
            .toDouble();
        final maxX = constraints.maxWidth - width;
        final maxY = constraints.maxHeight - height;
        final position = Offset(
          refCfg.x.clamp(0.0, maxX).toDouble(),
          refCfg.y.clamp(0.0, maxY).toDouble(),
        );

        void moveBy(Offset delta) {
          final latest = ref
              .read(drawingStudioProviderFamily(widget.initialPayload))
              .payload
              .referenceConfig;
          final currentX = latest.x.clamp(0.0, maxX).toDouble();
          final currentY = latest.y.clamp(0.0, maxY).toDouble();
          notifier.updateReferenceConfig(
            latest.copyWith(
              x: (currentX + delta.dx).clamp(0.0, maxX).toDouble(),
              y: (currentY + delta.dy).clamp(0.0, maxY).toDouble(),
            ),
          );
        }

        return SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: position.dx,
                top: position.dy,
                child: GestureDetector(
                  onPanUpdate: (details) => moveBy(details.delta),
                  child: UiSurface(
                    key: const ValueKey('drawing-reference-window'),
                    padding: EdgeInsets.zero,
                    bordered: false,
                    borderRadius: BorderRadius.circular(tokens.controlRadius),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Column(
                        children: [
                          FocusableActionDetector(
                            shortcuts: {
                              SingleActivator(
                                LogicalKeyboardKey.arrowLeft,
                              ): const _MoveReferenceWindowIntent(
                                Offset(-_keyboardMoveStep, 0),
                              ),
                              SingleActivator(
                                LogicalKeyboardKey.arrowRight,
                              ): const _MoveReferenceWindowIntent(
                                Offset(_keyboardMoveStep, 0),
                              ),
                              SingleActivator(
                                LogicalKeyboardKey.arrowUp,
                              ): const _MoveReferenceWindowIntent(
                                Offset(0, -_keyboardMoveStep),
                              ),
                              SingleActivator(
                                LogicalKeyboardKey.arrowDown,
                              ): const _MoveReferenceWindowIntent(
                                Offset(0, _keyboardMoveStep),
                              ),
                            },
                            actions: <Type, Action<Intent>>{
                              _MoveReferenceWindowIntent:
                                  CallbackAction<_MoveReferenceWindowIntent>(
                                    onInvoke: (intent) {
                                      moveBy(intent.offset);
                                      return intent;
                                    },
                                  ),
                            },
                            child: Semantics(
                              container: true,
                              label:
                                  'Reference window. Use arrow keys to move.',
                              focusable: true,
                              child: Container(
                                key: const ValueKey(
                                  'drawing-reference-window-drag-handle',
                                ),
                                height: AppControlSize.minimumHitTarget,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.panelElevated,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(tokens.controlRadius),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.picture_in_picture_alt,
                                      size: 14,
                                      color: tokens.info,
                                    ),
                                    const SizedBox(
                                      width: AppSpacing.xs + AppSpacing.xxs,
                                    ),
                                    Expanded(
                                      child: Text(
                                        'REFERENCE (PIP)',
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall!
                                            .copyWith(
                                              color: tokens.text,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: .5,
                                            ),
                                      ),
                                    ),
                                    const Spacer(),
                                    UiIconButton(
                                      icon: Icons.close,
                                      tooltip: 'Close reference window',
                                      size: UiButtonSize.sm,
                                      onPressed: () =>
                                          notifier.updateReferenceConfig(
                                            refCfg.copyWith(visible: false),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ColoredBox(
                              color: tokens.canvas,
                              child: Center(
                                child: Text(
                                  'Sample Reference\\n(Scale: ${_scale.toStringAsFixed(1)}x)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
