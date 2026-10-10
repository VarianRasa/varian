import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import '../../../../domain/models/node_payload.dart';

class AnnotationPinEditorDialog extends StatefulWidget {
  final ImageAnnotationPin pin;
  final int pinIndex;
  final ValueChanged<ImageAnnotationPin> onSave;
  final VoidCallback onDelete;

  const AnnotationPinEditorDialog({
    super.key,
    required this.pin,
    required this.pinIndex,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<AnnotationPinEditorDialog> createState() =>
      _AnnotationPinEditorDialogState();
}

class _AnnotationPinEditorDialogState extends State<AnnotationPinEditorDialog> {
  late TextEditingController _textController;
  late TextEditingController _authorController;
  late AnnotationPinStatus _status;
  late Color _color;
  late bool _isResolved;

  static const List<Color> _presetColors = [
    Color(0xFFEC4899), // Pink
    Color(0xFFEF4444), // Red
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Emerald
    Color(0xFF3B82F6), // Blue
    Color(0xFF8B5CF6), // Purple
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.pin.text);
    _authorController = TextEditingController(text: widget.pin.author);
    _status = widget.pin.status;
    _color = widget.pin.color;
    _isResolved = widget.pin.isResolved;
  }

  @override
  void dispose() {
    _textController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  void _submit() {
    final updated = widget.pin.copyWith(
      text: _textController.text.trim(),
      author: _authorController.text.trim().isEmpty
          ? 'Anonymous'
          : _authorController.text.trim(),
      status: _status,
      color: _color,
      isResolved: _isResolved,
      createdAt: widget.pin.createdAt ?? DateTime.now(),
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final compact = AppResponsive.isNarrow(context);
    final width = AppResponsive.dialogWidth(context, preferred: 440);
    final height = AppResponsive.dialogHeight(context, preferred: 640);
    final timeFormatted = widget.pin.createdAt != null
        ? '${widget.pin.createdAt!.day.toString().padLeft(2, '0')}/${widget.pin.createdAt!.month.toString().padLeft(2, '0')}/${widget.pin.createdAt!.year} ${widget.pin.createdAt!.hour.toString().padLeft(2, '0')}:${widget.pin.createdAt!.minute.toString().padLeft(2, '0')}'
        : 'Just now';

    return UiDialog(
      semanticsLabel: 'Edit annotation pin',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 440,
        maxHeight: 640,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        height: height,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: tokens.panel,
            borderRadius: BorderRadius.circular(AppRadius.dialog),
            border: Border.all(
              color: tokens.panelBorder,
              width: AppBorder.thin,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                key: const ValueKey('annotation-pin-editor-header'),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tokens.panelBorder,
                      width: AppBorder.thin,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _isResolved ? tokens.success : _color,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _isResolved ? '✓' : '${widget.pinIndex + 1}',
                        style: TextStyle(
                          color: tokens.handle,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Annotation Pin #${widget.pinIndex + 1}',
                        style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          color: tokens.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    UiIconButton(
                      icon: Icons.close,
                      tooltip: 'Close',
                      size: UiButtonSize.sm,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Existing editor fields
                      _buildEditorFields(tokens, timeFormatted, compact),
                    ],
                  ),
                ),
              ),
              _buildFooter(tokens, compact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorFields(
    AppTokens tokens,
    String timeFormatted,
    bool compact,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Comment / Note',
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: tokens.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      UiTextField(
        controller: _textController,
        hint: 'Add feedback or note...',
        minLines: 3,
        maxLines: 3,
      ),
      const SizedBox(height: AppSpacing.md),
      if (compact)
        Column(
          children: [
            _buildAuthorField(tokens),
            const SizedBox(height: AppSpacing.md),
            _buildStatusField(tokens),
          ],
        )
      else
        Row(
          children: [
            Expanded(child: _buildAuthorField(tokens)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _buildStatusField(tokens)),
          ],
        ),
      const SizedBox(height: AppSpacing.md),
      Text(
        'Marker Color',
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: tokens.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final color in _presetColors) _buildColorChoice(tokens, color),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Container(
        key: const ValueKey('annotation-pin-status-control'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: tokens.panelElevated,
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  _isResolved
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: _isResolved ? tokens.success : tokens.textMuted,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  _isResolved ? 'Resolved' : 'Mark as Resolved',
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: _isResolved ? tokens.success : tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            UiSwitch(
              value: _isResolved,
              onChange: (value) => setState(() => _isResolved = value),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Created: $timeFormatted',
        style: Theme.of(
          context,
        ).textTheme.labelSmall!.copyWith(color: tokens.textMuted, fontSize: 10),
      ),
    ],
  );

  Widget _buildAuthorField(AppTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Author',
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: tokens.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
      UiTextField(controller: _authorController, hint: 'Name or Handle'),
    ],
  );

  Widget _buildStatusField(AppTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Status',
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: tokens.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
      UiSelect<AnnotationPinStatus>(
        items: {
          for (final status in AnnotationPinStatus.values)
            status.name.toUpperCase(): status,
        },
        value: _status,
        label: 'STATUS',
        onChanged: (value) {
          if (value != null) setState(() => _status = value);
        },
      ),
    ],
  );

  Widget _buildColorChoice(AppTokens tokens, Color color) {
    final selected = _color.toARGB32() == color.toARGB32();
    final colorName = switch (color.toARGB32()) {
      0xFFEC4899 => 'Pink',
      0xFFEF4444 => 'Red',
      0xFFF59E0B => 'Amber',
      0xFF10B981 => 'Emerald',
      0xFF3B82F6 => 'Blue',
      0xFF8B5CF6 => 'Purple',
      _ => 'Custom',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: 'Marker color $colorName',
      child: FocusableActionDetector(
        shortcuts: <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              setState(() => _color = color);
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: ValueKey('annotation-pin-color-${colorName.toLowerCase()}'),
          onTap: () => setState(() => _color = color),
          child: ExcludeSemantics(
            child: Container(
              width: AppControlSize.compact,
              height: AppControlSize.compact,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? tokens.handle : Colors.transparent,
                  width: AppBorder.focus,
                ),
              ),
              child: selected
                  ? Icon(Icons.check, size: 14, color: tokens.handle)
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(AppTokens tokens, bool compact) => Container(
    key: const ValueKey('annotation-pin-editor-footer'),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
      ),
    ),
    child: compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiButton(
                onPressed: () {
                  widget.onDelete();
                  Navigator.of(context).pop();
                },
                variant: UiButtonVariant.destructive,
                prefix: const Icon(Icons.delete_outline, size: 16),
                child: const Text('Delete Pin'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    onPressed: () => Navigator.of(context).pop(),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    onPressed: _submit,
                    variant: UiButtonVariant.primary,
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              UiButton(
                onPressed: () {
                  widget.onDelete();
                  Navigator.of(context).pop();
                },
                variant: UiButtonVariant.destructive,
                prefix: const Icon(Icons.delete_outline, size: 16),
                child: const Text('Delete Pin'),
              ),
              Row(
                children: [
                  UiButton(
                    onPressed: () => Navigator.of(context).pop(),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    onPressed: _submit,
                    variant: UiButtonVariant.primary,
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ],
          ),
  );
}
