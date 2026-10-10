import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/widgets/color_picker_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets(
    'compact viewport stacks RGB and HSV and keeps RGB edits active',
    (tester) async {
      tester.view.physicalSize = const Size(390, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Color? changedColor;
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showUiDialog<void>(
                    context: context,
                    builder: (dialogContext) => ColorPickerDialog(
                      dialogContext: dialogContext,
                      dialogLabel: 'Stroke color',
                      title: 'Choose color',
                      currentColor: Colors.black,
                      onColorChanged: (color) => changedColor = color,
                    ),
                  ),
                  child: const Text('Open picker'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      final colorPreview = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            (widget.decoration as BoxDecoration).color == Colors.black,
      );
      expect(colorPreview, findsOneWidget);
      for (final key in [
        const ValueKey('color-picker-selected-swatch'),
        const ValueKey('color-picker-area-frame'),
        const ValueKey('color-picker-channel-frame'),
      ]) {
        final surface = tester.widget<DecoratedBox>(find.byKey(key));
        final border = (surface.decoration as BoxDecoration).border! as Border;
        expect(border.top.width, AppBorder.thin);
        expect(border.top.color, AppTokens.dark.panelBorder);
      }
      final previewSize = find.descendant(
        of: colorPreview,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == AppControlSize.extraSmall &&
              widget.height == AppControlSize.extraSmall,
        ),
      );
      expect(
        tester.getSize(previewSize),
        const Size(AppControlSize.extraSmall, AppControlSize.extraSmall),
      );
      final sliderSemantics = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.slider == true,
      );
      expect(sliderSemantics, findsNWidgets(2));
      final sliderViewport = find.descendant(
        of: sliderSemantics.first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.height == AppControlSize.compact,
        ),
      );
      expect(tester.getSize(sliderViewport).height, AppControlSize.compact);

      final rgb = tester.getRect(find.text('RGB'));
      final hsv = tester.getRect(find.text('HSV'));
      expect(hsv.top, greaterThan(rgb.bottom));

      await tester.enterText(
        find.byKey(const ValueKey('color-picker-r')),
        '64',
      );
      await tester.pump();
      expect(changedColor, const Color(0xFF400000));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide viewport places RGB and HSV beside each other', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showUiDialog<void>(
                  context: context,
                  builder: (dialogContext) => ColorPickerDialog(
                    dialogContext: dialogContext,
                    dialogLabel: 'Stroke color',
                    title: 'Choose color',
                    currentColor: Colors.black,
                    onColorChanged: (_) {},
                  ),
                ),
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    final rgb = tester.getRect(find.text('RGB'));
    final hsv = tester.getRect(find.text('HSV'));
    expect(hsv.left, greaterThan(rgb.right));
    expect(hsv.center.dy, closeTo(rgb.center.dy, 1));
    expect(tester.takeException(), isNull);
  });
}
