import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

import '../../../../app/widgets/ui_primitives.dart';

/// Explicit enable/disable actions for a panel button preference.
class PanelVisibilityToggle extends StatefulWidget {
  final String id;
  final String label;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const PanelVisibilityToggle({
    required this.id,
    required this.label,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  @override
  State<PanelVisibilityToggle> createState() => _PanelVisibilityToggleState();
}

class _PanelVisibilityToggleState extends State<PanelVisibilityToggle> {
  late bool _enabled = widget.enabled;

  @override
  void didUpdateWidget(covariant PanelVisibilityToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _enabled = widget.enabled;
  }

  void _setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    setState(() => _enabled = enabled);
    widget.onChanged(enabled);
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      UiButton(
        key: ValueKey('panel-enable-${widget.id}'),
        size: UiButtonSize.xs,
        variant: _enabled ? UiButtonVariant.primary : UiButtonVariant.outline,
        semanticsLabel: 'Enable ${widget.label} button',
        onPressed: () => _setEnabled(true),
        child: const Text('Enable'),
      ),
      const SizedBox(width: AppSpacing.xs),
      UiButton(
        key: ValueKey('panel-disable-${widget.id}'),
        size: UiButtonSize.xs,
        variant: _enabled ? UiButtonVariant.outline : UiButtonVariant.primary,
        semanticsLabel: 'Disable ${widget.label} button',
        onPressed: () => _setEnabled(false),
        child: const Text('Disable'),
      ),
    ],
  );
}
