import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/model3d/presentation/model3d_control_button.dart';

void main() {
  testWidgets('3D control keeps a minimum target and activates at its edge', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          data: AppTheme.darkTheme,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Model3DControlButton(
                  key: const ValueKey('model3d-control-orbit-left'),
                  icon: Icons.rotate_left,
                  tooltip: 'Orbit left',
                  onPressed: () => activations++,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final control = find.byKey(const ValueKey('model3d-control-orbit-left'));
    final button = find.descendant(
      of: control,
      matching: find.byType(UiButton),
    );
    expect(
      tester.getSize(button),
      const Size(
        AppControlSize.minimumHitTarget,
        AppControlSize.minimumHitTarget,
      ),
    );
    final icon = find.descendant(
      of: control,
      matching: find.byIcon(Icons.rotate_left),
    );
    expect(tester.getSize(icon), const Size(14, 14));
    await tester.tapAt(tester.getRect(button).bottomRight - const Offset(2, 2));
    await tester.pump();
    expect(activations, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(Focus.of(tester.element(button)).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 2);
    expect(tester.takeException(), isNull);
  });
}
