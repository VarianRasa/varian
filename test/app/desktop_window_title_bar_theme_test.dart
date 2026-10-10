import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/desktop_window_title_bar.dart';

import '../test_app.dart';

void main() {
  testWidgets(
    'Windows close hover tints the actual frame surface in both themes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;

      try {
        for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
          await tester.pumpWidget(
            testApp(
              const DesktopWindowTitleBar(child: SizedBox.expand()),
              data: theme,
              materialTheme: theme,
            ),
          );
          await tester.pumpAndSettle();

          final closeButtonFinder = find.byKey(const ValueKey('window-close'));
          final closeButton = tester.widget<IconButton>(closeButtonFinder);
          final tokens = theme.appTokens;
          final hoverColor = Color.alphaBlend(
            tokens.danger.withValues(alpha: 0.12),
            theme.brightness == Brightness.dark ? tokens.canvas : tokens.panel,
          );

          expect(closeButton.hoverColor, hoverColor);
          expect(tester.getSize(closeButtonFinder), const Size(42, 36));

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
            buttons: 0,
          );
          await mouse.addPointer(location: const Offset(0, 300));
          await tester.pump();
          await mouse.moveTo(tester.getCenter(closeButtonFinder));
          await tester.pump(const Duration(milliseconds: 60));

          final closeInkWell = tester.widget<InkWell>(
            find.descendant(
              of: closeButtonFinder,
              matching: find.byType(InkWell),
            ),
          );
          expect(
            closeInkWell.statesController!.value,
            contains(WidgetState.hovered),
          );
          expect(
            closeInkWell.overlayColor?.resolve({WidgetState.hovered}),
            hoverColor,
          );
          expect(tester.takeException(), isNull);

          await mouse.removePointer();
          await tester.pump();
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  testWidgets('window frame surface uses the active AppTokens extension', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    try {
      const customCanvas = Color(0xFF123456);
      final customTokens = AppTokens.dark.copyWith(canvas: customCanvas);
      final theme = AppTheme.darkTheme.copyWith(extensions: [customTokens]);

      await tester.pumpWidget(
        testApp(
          const DesktopWindowTitleBar(child: SizedBox.expand()),
          data: theme,
          materialTheme: theme,
        ),
      );

      final titleBar = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('desktop-window-title-bar')),
      );
      final decoration = titleBar.decoration as BoxDecoration;
      expect((decoration.border! as Border).bottom.width, AppBorder.thin);
      expect(decoration.color, customCanvas);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  });
  testWidgets('desktop brand gap uses the equivalent spacing token', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        testApp(const DesktopWindowTitleBar(child: SizedBox.expand())),
      );
      final gap = tester.widget<SizedBox>(
        find.byKey(const ValueKey('desktop-window-brand-gap')),
      );
      expect(gap.width, AppSpacing.xs + AppSpacing.xxs / 2);
      expect(gap.width, 5);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
