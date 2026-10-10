import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/dialogs/frame_preset_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('frame presets fit a compact viewport and keep close reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          FramePresetDialog(onSelectPreset: (_, _) {}),
          data: AppTheme.darkTheme,
          materialTheme: AppTheme.darkTheme,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    expect(dialog.constraints!.maxHeight, 456);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final closeButton = find.byTooltip('Close frame presets');
    final closeRect = tester.getRect(closeButton);
    expect(closeRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(closeRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(closeRect.top, greaterThanOrEqualTo(dialogRect.top));
    expect(closeRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(find.text('FRAME DEVICE & ARTBOARD PRESETS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
