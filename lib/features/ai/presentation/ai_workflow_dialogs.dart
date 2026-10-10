import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../domain/ai_workflow_contract.dart';

class AIMaskEditorDialog extends StatefulWidget {
  final AIMaskDocument initialMask;

  const AIMaskEditorDialog({super.key, required this.initialMask});

  @override
  State<AIMaskEditorDialog> createState() => _AIMaskEditorDialogState();
}

class _AIMaskEditorDialogState extends State<AIMaskEditorDialog> {
  late AIMaskDocument _mask;
  AIMaskOperation _operation = AIMaskOperation.inpaint;
  bool _erase = false;
  List<Offset> _activePoints = const [];

  @override
  void initState() {
    super.initState();
    _mask = widget.initialMask;
    _operation = _mask.operation;
  }

  void _finishStroke() {
    if (_activePoints.isEmpty) return;
    setState(() {
      _mask = _mask
          .copyWith(operation: _operation)
          .addStroke(
            AIMaskStroke(points: _activePoints, width: 28, erase: _erase),
          );
      _activePoints = const [];
    });
  }

  KeyEventResult _handleCanvasKeyEvent(
    FocusNode node,
    KeyEvent event,
    Size size,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _finishStroke();
      return KeyEventResult.handled;
    }
    final offset = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => const Offset(-12, 0),
      LogicalKeyboardKey.arrowRight => const Offset(12, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -12),
      LogicalKeyboardKey.arrowDown => const Offset(0, 12),
      _ => null,
    };
    if (offset == null) return KeyEventResult.ignored;
    setState(() {
      final current = _activePoints.isEmpty
          ? Offset(size.width / 2, size.height / 2)
          : _activePoints.last;
      final next = Offset(
        (current.dx + offset.dx).clamp(0.0, size.width).toDouble(),
        (current.dy + offset.dy).clamp(0.0, size.height).toDouble(),
      );
      _activePoints = [..._activePoints, next];
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final compact = AppResponsive.isNarrow(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).vertical;
    final maxHeight =
        (AppResponsive.dialogHeight(context, preferred: 620) - keyboardInset)
            .clamp(0.0, 620.0)
            .toDouble();
    final canvasHeight = (maxHeight * 0.38)
        .clamp(96.0, compact ? 200.0 : 280.0)
        .toDouble();
    return UiDialog(
      semanticsLabel: 'AI mask editor',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 560,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('AI MASK / BRUSH EDITOR', style: style.titleTextStyle),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Text(
                  'Paint the affected area, then choose whether the mask is used for inpaint, outpaint, object, or background operations.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                if (compact)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      UiSelect<AIMaskOperation>(
                        label: 'Operation',
                        value: _operation,
                        items: {
                          for (final operation in AIMaskOperation.values)
                            operation.name: operation,
                        },
                        onChanged: (value) {
                          if (value != null) setState(() => _operation = value);
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          UiButton(
                            variant: _erase
                                ? UiButtonVariant.primary
                                : UiButtonVariant.ghost,
                            semanticsLabel: _erase
                                ? 'Switch to painting mask strokes'
                                : 'Switch to erasing mask strokes',
                            prefix: const Icon(
                              Icons.auto_fix_high_outlined,
                              size: 16,
                            ),
                            onPressed: () => setState(() => _erase = !_erase),
                            child: Text(_erase ? 'Erase' : 'Paint'),
                          ),
                          UiIconButton(
                            icon: Icons.undo,
                            tooltip: 'Undo mask stroke',
                            onPressed: _mask.strokes.isEmpty
                                ? null
                                : () => setState(() => _mask = _mask.undo()),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: UiSelect<AIMaskOperation>(
                          label: 'Operation',
                          value: _operation,
                          items: {
                            for (final operation in AIMaskOperation.values)
                              operation.name: operation,
                          },
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _operation = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      UiButton(
                        variant: _erase
                            ? UiButtonVariant.primary
                            : UiButtonVariant.ghost,
                        semanticsLabel: _erase
                            ? 'Switch to painting mask strokes'
                            : 'Switch to erasing mask strokes',
                        prefix: const Icon(
                          Icons.auto_fix_high_outlined,
                          size: 16,
                        ),
                        onPressed: () => setState(() => _erase = !_erase),
                        child: Text(_erase ? 'Erase' : 'Paint'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      UiIconButton(
                        icon: Icons.undo,
                        tooltip: 'Undo mask stroke',
                        onPressed: _mask.strokes.isEmpty
                            ? null
                            : () => setState(() => _mask = _mask.undo()),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                SizedBox(
                  height: canvasHeight,
                  child: UiSurface(
                    padding: EdgeInsets.zero,
                    color: tokens.panelElevated,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Focus(
                        onKeyEvent: (node, event) => _handleCanvasKeyEvent(
                          node,
                          event,
                          Size(constraints.maxWidth, constraints.maxHeight),
                        ),
                        child: Semantics(
                          label: 'Mask drawing area',
                          hint:
                              'Focus this area and use the arrow keys to paint. Press Enter to finish a stroke.',
                          focusable: true,
                          child: GestureDetector(
                            onPanStart: (details) => setState(
                              () => _activePoints = [details.localPosition],
                            ),
                            onPanUpdate: (details) => setState(
                              () => _activePoints = [
                                ..._activePoints,
                                details.localPosition,
                              ],
                            ),
                            onPanEnd: (_) => _finishStroke(),
                            child: CustomPaint(
                              painter: _AIMaskPainter(
                                strokes: _mask.strokes,
                                activePoints: _activePoints,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    UiButton(
                      variant: UiButtonVariant.ghost,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    UiButton(
                      onPressed: () => Navigator.of(dialogContext).pop(_mask),
                      prefix: const Icon(Icons.check, size: 16),
                      child: Text('Use ${_mask.strokes.length} strokes'),
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

class _AIMaskPainter extends CustomPainter {
  final List<AIMaskStroke> strokes;
  final List<Offset> activePoints;

  const _AIMaskPainter({required this.strokes, required this.activePoints});

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFF111827);
    canvas.drawRect(Offset.zero & size, background);
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke.points, stroke.width, stroke.erase);
    }
    _drawStroke(canvas, activePoints, 28, false);
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawStroke(
    Canvas canvas,
    List<Offset> points,
    double width,
    bool erase,
  ) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = erase
          ? Colors.white.withValues(alpha: 0.32)
          : AppTheme.braunOrange.withValues(alpha: 0.68)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (points.length == 1) {
      canvas.drawCircle(points.single, width / 2, paint);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AIMaskPainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.activePoints != activePoints;
}

class AIWorkflowReviewDialog extends StatefulWidget {
  final AIVariantSet initialVariants;
  final AIProviderHealth? providerHealth;
  final AIQuotaSnapshot? quota;
  final AIProvenanceNotice? provenance;

  const AIWorkflowReviewDialog({
    super.key,
    required this.initialVariants,
    this.providerHealth,
    this.quota,
    this.provenance,
  });

  @override
  State<AIWorkflowReviewDialog> createState() => _AIWorkflowReviewDialogState();
}

class _AIWorkflowReviewDialogState extends State<AIWorkflowReviewDialog> {
  late AIVariantSet _variants;

  @override
  void initState() {
    super.initState();
    _variants = widget.initialVariants;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final compareCount = _variants.compareSelection.length;
    final compact = AppResponsive.isNarrow(context);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 720);
    return UiDialog(
      semanticsLabel: 'AI output review',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 640,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('AI OUTPUT REVIEW', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.sm),
              if (widget.providerHealth != null)
                Text(
                  'Provider: ${widget.providerHealth!.provider} · ${widget.providerHealth!.status.name}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                ),
              if (widget.quota != null)
                Text(
                  'Quota: ${widget.quota!.remaining} ${widget.quota!.unit} remaining',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                ),
              if (widget.provenance != null) ...[
                const SizedBox(height: AppSpacing.xs),
                UiAlert(
                  title: 'Output provenance',
                  description: widget.provenance!.disclosure,
                  icon: Icons.info_outline,
                  variant: UiAlertVariant.warning,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      for (final variant in _variants.variants)
                        SizedBox(
                          width: compact ? double.infinity : 190,
                          child: UiSurface(
                            color: variant.selectedForCompare
                                ? tokens.accentSoft
                                : tokens.panelElevated,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Variant ${variant.index + 1}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  variant.artifactReference ??
                                      'No artifact reference',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Wrap(
                                  spacing: AppSpacing.xs,
                                  runSpacing: AppSpacing.xs,
                                  children: [
                                    UiIconButton(
                                      icon: variant.favorite
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      tooltip: 'Toggle favorite',
                                      selected: variant.favorite,
                                      onPressed: () => setState(
                                        () => _variants = _variants
                                            .toggleFavorite(variant.id),
                                      ),
                                    ),
                                    UiButton(
                                      variant: variant.selectedForCompare
                                          ? UiButtonVariant.primary
                                          : UiButtonVariant.ghost,
                                      onPressed: () => setState(
                                        () => _variants = _variants
                                            .toggleCompare(variant.id),
                                      ),
                                      child: Text(
                                        variant.selectedForCompare
                                            ? 'Compared'
                                            : 'Compare',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '$compareCount of 2 compare slots used',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(_variants),
                    child: const Text('Close'),
                  ),
                  UiButton(
                    onPressed: compareCount == 2
                        ? () => Navigator.of(dialogContext).pop(_variants)
                        : null,
                    prefix: const Icon(Icons.compare_arrows, size: 16),
                    child: const Text('Use comparison'),
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
