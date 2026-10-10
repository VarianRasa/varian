import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';

void main() {
  testWidgets('compact icon buttons retain touch targets in grouped rows', (
    tester,
  ) async {
    const labels = [
      'Align Left',
      'Align Center',
      'Align Right',
      'Align Top',
      'Align Middle',
      'Align Bottom',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          data: AppTheme.darkTheme,
          child: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 246.8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        UiIconButton(
                          icon: Icons.align_horizontal_left,
                          tooltip: 'Align Left',
                          onPressed: null,
                        ),
                        UiIconButton(
                          icon: Icons.align_horizontal_center,
                          tooltip: 'Align Center',
                          onPressed: null,
                        ),
                        UiIconButton(
                          icon: Icons.align_horizontal_right,
                          tooltip: 'Align Right',
                          onPressed: null,
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        UiIconButton(
                          icon: Icons.align_vertical_top,
                          tooltip: 'Align Top',
                          onPressed: null,
                        ),
                        UiIconButton(
                          icon: Icons.align_vertical_center,
                          tooltip: 'Align Middle',
                          onPressed: null,
                        ),
                        UiIconButton(
                          icon: Icons.align_vertical_bottom,
                          tooltip: 'Align Bottom',
                          onPressed: null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (final label in labels) {
      final button = find.byWidgetPredicate(
        (widget) => widget is UiIconButton && widget.tooltip == label,
      );
      expect(button, findsOneWidget);
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(AppControlSize.minimumHitTarget));
      expect(
        size.height,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('UiButton does not overflow when a narrow parent constrains it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          data: AppTheme.darkTheme,
          child: const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: ValueKey('button-constraint'),
              width: 104.4,
              height: 50,
              child: UiButton(
                onPressed: null,
                prefix: Icon(Icons.upload_outlined, size: 16),
                child: Text('Upload asset'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
  testWidgets('compact page actions remain reachable with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var firstActionCount = 0;
    var secondActionCount = 0;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 480),
          devicePixelRatio: 1,
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: UiPageScaffold(
              title: const Text('Page'),
              actions: [
                UiButton(
                  onPressed: () => firstActionCount++,
                  child: const Text('First action'),
                ),
                UiButton(
                  onPressed: () => secondActionCount++,
                  child: const Text('Second action'),
                ),
              ],
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final rail = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(SingleChildScrollView),
    );
    expect(rail, findsOneWidget);
    final railRect = tester.getRect(rail);

    final firstAction = find.text('First action');
    final firstActionRect = tester.getRect(firstAction);
    final firstVisiblePoint = Offset(
      railRect.left + AppSpacing.xxs,
      firstActionRect.center.dy,
    );
    expect(railRect.contains(firstVisiblePoint), isTrue);
    await tester.tapAt(firstVisiblePoint);
    await tester.pump();

    await tester.drag(rail, const Offset(-600, 0));
    await tester.pumpAndSettle();

    final secondAction = find.text('Second action');
    final secondActionRect = tester.getRect(secondAction);
    final visibleSecondLeft = math.max(secondActionRect.left, railRect.left);
    final visibleSecondRight = math.min(secondActionRect.right, railRect.right);
    expect(visibleSecondRight, greaterThan(visibleSecondLeft));
    await tester.tapAt(
      Offset(
        (visibleSecondLeft + visibleSecondRight) / 2,
        secondActionRect.center.dy,
      ),
    );
    await tester.pump();

    expect(firstActionCount, 1);
    expect(secondActionCount, 1);
    expect(tester.takeException(), isNull);
  });
}
