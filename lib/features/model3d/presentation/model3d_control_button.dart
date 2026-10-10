import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';

class Model3DControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const Model3DControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AppControlSize.minimumHitTarget,
    height: AppControlSize.minimumHitTarget,
    child: FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onPressed();
            return null;
          },
        ),
      },
      child: UiIconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
        size: UiButtonSize.xs,
        iconSize: 14,
      ),
    ),
  );
}
