import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/responsive.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../../../domain/models/node.dart';
import '../../../../domain/models/node_payload.dart';
import '../../utils/brush_path_smoother.dart';

class SketchCardEditorDialog extends StatefulWidget {
  final CanvasNode node;
  final ValueChanged<SketchCardPayload> onSave;

  const SketchCardEditorDialog({
    super.key,
    required this.node,
    required this.onSave,
  });

  @override
  State<SketchCardEditorDialog> createState() => _SketchCardEditorDialogState();
}

class _SketchCardEditorDialogState extends State<SketchCardEditorDialog> {
  late String _title;
  late List<List<Offset>> _strokes;
  late Color _strokeColor;
  late double _strokeWidth;
  late Color _backgroundColor;
  late String _cardPattern;
  late bool _smoothCurves;
  bool _isEraser = false;
  late TextEditingController _titleController;

  final List<List<List<Offset>>> _undoStack = [];

  final List<Color> _palette = const [
    Color(0xFFF59E0B), // Amber (default)
    Color(0xFFEF4444), // Red
    Color(0xFF10B981), // Emerald
    Color(0xFF3B82F6), // Blue
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFFF3F4F6), // White/Light
    Color(0xFF94A3B8), // Slate
  ];
  static const List<String> _paletteNames = [
    'Amber',
    'Red',
    'Emerald',
    'Blue',
    'Purple',
    'Pink',
    'White',
    'Slate',
  ];
  late final _paletteFocusNodes = List.generate(
    _palette.length,
    (_) => FocusNode(),
  );
  int? _focusedColorIndex;

  KeyEventResult _onPaletteKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.space)) {
      return KeyEventResult.ignored;
    }
    setState(() => _strokeColor = _palette[index]);
    return KeyEventResult.handled;
  }

  Widget _buildColorSwatch(int index, AppTokens tokens) {
    final color = _palette[index];
    final isSelected = _strokeColor == color;
    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      label: 'Stroke color ${_paletteNames[index]}',
      onTap: () => setState(() => _strokeColor = color),
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _paletteFocusNodes[index],
          onFocusChange: (focused) {
            if (_focusedColorIndex != (focused ? index : null)) {
              setState(() => _focusedColorIndex = focused ? index : null);
            }
          },
          onKeyEvent: (node, event) => _onPaletteKey(index, event),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: () => setState(() => _strokeColor = color),
            child: SizedBox(
              key: ValueKey('sketch-card-stroke-color-${_paletteNames[index]}'),
              width: AppControlSize.minimumHitTarget,
              height: AppControlSize.minimumHitTarget,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected || _focusedColorIndex == index
                          ? tokens.handle
                          : Colors.transparent,
                      width: AppBorder.focus,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final p = widget.node.payload is SketchCardPayload
        ? widget.node.payload as SketchCardPayload
        : SketchCardPayload();
    _title = p.title;
    _strokes = p.strokes.map((s) => List<Offset>.from(s)).toList();
    _strokeColor = p.strokeColor;
    _strokeWidth = p.strokeWidth;
    _backgroundColor = p.backgroundColor;
    _cardPattern = p.cardPattern;
    _smoothCurves = p.smoothCurves;
    _titleController = TextEditingController(text: _title);
  }

  @override
  void dispose() {
    for (final focusNode in _paletteFocusNodes) {
      focusNode.dispose();
    }
    _titleController.dispose();
    super.dispose();
  }

  void _saveSnapshotForUndo() {
    _undoStack.add(_strokes.map((s) => List<Offset>.from(s)).toList());
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      setState(() {
        _strokes = _undoStack.removeLast();
      });
    } else if (_strokes.isNotEmpty) {
      setState(() {
        _strokes.removeLast();
      });
    }
  }

  void _clear() {
    if (_strokes.isEmpty) return;
    _saveSnapshotForUndo();
    setState(() {
      _strokes.clear();
    });
  }

  void _handlePanStart(DragStartDetails details, BoxConstraints constraints) {
    _saveSnapshotForUndo();
    final local = _toNormalizedPos(details.localPosition, constraints);
    setState(() {
      if (_isEraser) {
        _eraseNear(local);
      } else {
        _strokes.add([local]);
      }
    });
  }

  void _handlePanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final local = _toNormalizedPos(details.localPosition, constraints);
    setState(() {
      if (_isEraser) {
        _eraseNear(local);
      } else {
        if (_strokes.isNotEmpty) {
          _strokes.last.add(local);
        }
      }
    });
  }

  Offset _toNormalizedPos(Offset local, BoxConstraints constraints) {
    final cardW = widget.node.width;
    final cardH = widget.node.height;
    final padW = constraints.maxWidth;
    final padH = constraints.maxHeight;
    if (padW <= 0 || padH <= 0 || cardW <= 0 || cardH <= 0) return local;

    // Scale aspect ratio mapping: fit card coordinate space inside dialog drawing pad
    final scale = (padW / cardW < padH / cardH) ? padW / cardW : padH / cardH;
    final originX = (padW - cardW * scale) / 2.0;
    final originY = (padH - cardH * scale) / 2.0;

    final normX = ((local.dx - originX) / scale).clamp(0.0, cardW);
    final normY = ((local.dy - originY) / scale).clamp(0.0, cardH);
    return Offset(normX, normY);
  }

  void _eraseNear(Offset target) {
    const threshold = 18.0;
    _strokes.removeWhere((stroke) {
      return stroke.any((pt) => (pt - target).distance <= threshold);
    });
  }

  void _apply() {
    widget.onSave(
      SketchCardPayload(
        title: _title,
        strokes: _strokes,
        strokeColor: _strokeColor,
        strokeWidth: _strokeWidth,
        backgroundColor: _backgroundColor,
        cardPattern: _cardPattern,
        smoothCurves: _smoothCurves,
      ),
    );
    Navigator.of(context).pop();
  }

  Widget _buildHeader(bool compact) {
    final title = UiTextField(
      controller: _titleController,
      hint: 'Sketch Title...',
      onChanged: (value) =>
          _title = value.trim().isEmpty ? 'Quick Sketch' : value,
    );
    final actions = [
      UiIconButton(
        icon: Icons.undo,
        tooltip: 'Undo',
        onPressed: _strokes.isNotEmpty || _undoStack.isNotEmpty ? _undo : null,
      ),
      UiIconButton(
        icon: Icons.delete_sweep_outlined,
        tooltip: 'Clear canvas',
        onPressed: _strokes.isNotEmpty ? _clear : null,
      ),
      UiButton(
        onPressed: _apply,
        variant: UiButtonVariant.primary,
        size: UiButtonSize.sm,
        prefix: const Icon(Icons.check, size: 16),
        child: const Text('Apply'),
      ),
    ];
    final close = UiIconButton(
      icon: Icons.close,
      tooltip: 'Close sketch editor',
      onPressed: () => Navigator.of(context).pop(),
    );
    return DecoratedBox(
      key: const ValueKey('sketch-card-editor-header'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.appTokens.panelBorder,
            width: AppBorder.thin,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.gesture_outlined,
                        color: context.appTokens.accent,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: title),
                      close,
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: actions,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Icon(
                    Icons.gesture_outlined,
                    color: context.appTokens.accent,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: title),
                  ...actions,
                  const SizedBox(width: AppSpacing.sm),
                  close,
                ],
              ),
      ),
    );
  }

  Widget _buildControls() {
    final tokens = context.appTokens;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(
                child: UiButton(
                  onPressed: () => setState(() => _isEraser = false),
                  variant: !_isEraser
                      ? UiButtonVariant.primary
                      : UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  child: const Text('Pen'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Expanded(
                child: UiButton(
                  onPressed: () => setState(() => _isEraser = true),
                  variant: _isEraser
                      ? UiButtonVariant.destructive
                      : UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  child: const Text('Eraser'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Thickness: ${_strokeWidth.toStringAsFixed(1)}px',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
          ),
          UiSlider(
            value: _strokeWidth / 8,
            onChanged: (value) =>
                setState(() => _strokeWidth = (value * 8).clamp(1.0, 8.0)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Color',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs + AppSpacing.xxs,
            runSpacing: AppSpacing.xs + AppSpacing.xxs,
            children: [
              for (var index = 0; index < _palette.length; index++)
                _buildColorSwatch(index, tokens),
            ],
          ),
          const SizedBox(
            height: AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
          ),
          UiSelect<String>(
            items: const {
              'None (Blank)': 'none',
              'Dots Grid': 'dots',
              'Square Grid': 'grid',
            },
            value: _cardPattern,
            label: 'Pattern',
            onChanged: (value) {
              if (value != null) setState(() => _cardPattern = value);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          UiSwitch(
            label: const Text('Smooth stroke'),
            value: _smoothCurves,
            onChange: (value) => setState(() => _smoothCurves = value),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas() => Padding(
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: _backgroundColor,
          child: GestureDetector(
            onPanStart: (details) => _handlePanStart(details, constraints),
            onPanUpdate: (details) => _handlePanUpdate(details, constraints),
            child: CustomPaint(
              size: Size.infinite,
              painter: _SketchCardPadPainter(
                strokes: _strokes,
                strokeColor: _strokeColor,
                strokeWidth: _strokeWidth,
                cardPattern: _cardPattern,
                smoothCurves: _smoothCurves,
                cardWidth: widget.node.width,
                cardHeight: widget.node.height,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final compact = AppResponsive.isNarrow(context);
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 900);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 700);
    return UiDialog(
      semanticsLabel: 'Sketch card editor',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      builder: (context, style) => SizedBox(
        width: maxWidth,
        height: maxHeight,
        child: UiSurface(
          padding: EdgeInsets.zero,
          color: tokens.panel,
          child: Column(
            children: [
              _buildHeader(compact),
              Expanded(
                child: compact
                    ? Column(
                        children: [
                          SizedBox(height: 180, child: _buildControls()),
                          Expanded(child: _buildCanvas()),
                        ],
                      )
                    : Row(
                        children: [
                          SizedBox(width: 180, child: _buildControls()),
                          Expanded(child: _buildCanvas()),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SketchCardPadPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color strokeColor;
  final double strokeWidth;
  final String cardPattern;
  final bool smoothCurves;
  final double cardWidth;
  final double cardHeight;

  _SketchCardPadPainter({
    required this.strokes,
    required this.strokeColor,
    required this.strokeWidth,
    required this.cardPattern,
    required this.smoothCurves,
    required this.cardWidth,
    required this.cardHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cardWidth <= 0 || cardHeight <= 0) return;

    final scale = (size.width / cardWidth < size.height / cardHeight)
        ? size.width / cardWidth
        : size.height / cardHeight;
    final originX = (size.width - cardWidth * scale) / 2.0;
    final originY = (size.height - cardHeight * scale) / 2.0;

    canvas.save();
    canvas.translate(originX, originY);
    canvas.scale(scale, scale);

    final cardRect = Rect.fromLTWH(0, 0, cardWidth, cardHeight);
    final cardRRect = RRect.fromRectAndRadius(
      cardRect,
      const Radius.circular(8),
    );
    canvas.clipRRect(cardRRect);

    // Pattern
    if (cardPattern == 'dots') {
      final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.08);
      const spacing = 16.0;
      for (double x = 16.0; x < cardWidth - 8.0; x += spacing) {
        for (double y = 16.0; y < cardHeight - 8.0; y += spacing) {
          canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
        }
      }
    } else if (cardPattern == 'grid') {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      const spacing = 20.0;
      for (double x = 20.0; x < cardWidth; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, cardHeight), gridPaint);
      }
      for (double y = 20.0; y < cardHeight; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(cardWidth, y), gridPaint);
      }
    }

    // Strokes
    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final Path path;
      if (smoothCurves) {
        path = BrushPathSmoother.buildSmoothPath(stroke);
      } else {
        path = BrushPathSmoother.buildLinearPath(stroke);
      }
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SketchCardPadPainter oldDelegate) => true;
}
