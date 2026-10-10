import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/quick_capture_palette.dart';
import '../../test_app.dart';

void main() {
  testWidgets('quick capture palette fits a compact viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => QuickCapturePalette(onSelected: (_) {}),
              ),
              child: const Text('Open quick capture'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open quick capture'));
    await tester.pumpAndSettle();

    final paletteContext = tester.element(find.byType(QuickCapturePalette));
    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(
      dialog.constraints,
      AppResponsive.dialogConstraints(
        paletteContext,
        maxWidth: 480,
        maxHeight: 520,
      ),
    );
    final dialogBounds = tester.getRect(find.byType(Dialog));
    expect(dialogBounds.left, greaterThanOrEqualTo(0));
    expect(dialogBounds.right, lessThanOrEqualTo(320));
    expect(dialogBounds.top, greaterThanOrEqualTo(0));
    expect(dialogBounds.bottom, lessThanOrEqualTo(480));

    for (final finder in [
      find.text('QUICK CAPTURE'),
      find.byType(TextField),
      find.text('Add text'),
      find.text('↑ ↓ Navigate   Enter Select   Esc Close'),
    ]) {
      final bounds = tester.getRect(finder);
      expect(bounds.left, greaterThanOrEqualTo(dialogBounds.left));
      expect(bounds.right, lessThanOrEqualTo(dialogBounds.right));
      expect(bounds.top, greaterThanOrEqualTo(dialogBounds.top));
      expect(bounds.bottom, lessThanOrEqualTo(dialogBounds.bottom));
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'quick capture commands remain selectable and explain shortcuts',
    (tester) async {
      QuickCaptureAction? selectedAction;

      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => QuickCapturePalette(
                    onSelected: (action) => selectedAction = action,
                  ),
                ),
                child: const Text('Open quick capture'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open quick capture'));
      await tester.pumpAndSettle();

      expect(find.text('Add text'), findsOneWidget);
      final commandLabel = find.text('Add text');
      final theme = Theme.of(tester.element(commandLabel));
      final tokens = theme.extension<AppTokens>()!;
      expect(
        tester.widget<Text>(commandLabel).style,
        theme.textTheme.bodyMedium!.copyWith(
          color: tokens.accentForeground,
          fontWeight: FontWeight.w600,
        ),
      );
      expect(find.text('T'), findsOneWidget);
      expect(
        find.text('↑ ↓ Navigate   Enter Select   Esc Close'),
        findsOneWidget,
      );

      await tester.tap(find.text('Add text'));
      await tester.pumpAndSettle();

      expect(selectedAction, QuickCaptureAction.text);
      expect(tester.takeException(), isNull);
    },
  );
}
