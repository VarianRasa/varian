import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';

void main() {
  testWidgets('sidebar toggle icon paints each side and expanded state', (
    tester,
  ) async {
    const configurations = [
      (SidebarPanelSide.left, true),
      (SidebarPanelSide.left, false),
      (SidebarPanelSide.right, true),
      (SidebarPanelSide.right, false),
    ];
    final painters = <SidebarPanelTogglePainter>[];

    for (final (side, expanded) in configurations) {
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: Scaffold(
              body: Center(
                child: UiIconButton(
                  icon: Icons.layers_outlined,
                  iconWidget: SidebarPanelToggleIcon(
                    side: side,
                    expanded: expanded,
                  ),
                  tooltip: 'Toggle panel',
                  selected: expanded,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final painter = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(SidebarPanelToggleIcon),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(painter.size, const Size.square(16));
      expect(painter.painter, isA<SidebarPanelTogglePainter>());
      final config = painter.painter! as SidebarPanelTogglePainter;
      expect(config.side, side);
      expect(config.expanded, expanded);
      painters.add(config);
      final buttonSemantics = tester.getSemantics(
        find
            .ancestor(
              of: find.byType(SidebarPanelToggleIcon),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(buttonSemantics.flagsCollection.isButton, isTrue);
      expect(
        buttonSemantics.flagsCollection.isSelected,
        expanded ? ui.Tristate.isTrue : ui.Tristate.isFalse,
      );
      expect(buttonSemantics.label, 'Toggle panel');
      expect(tester.takeException(), isNull);
    }

    expect(painters.toSet(), hasLength(4));
  });

  testWidgets('workspace sidebar icon preserves its identifying cue', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          data: AppTheme.darkTheme,
          child: Scaffold(
            body: UiIconButton(
              key: const ValueKey('workspace-sidebar-toggle'),
              icon: Icons.folder_open_outlined,
              iconWidget: const SidebarPanelToggleIcon(
                side: SidebarPanelSide.left,
                expanded: true,
                cue: Icons.workspaces_outlined,
              ),
              tooltip: 'Hide Workspace panel',
              selected: true,
              onPressed: () => presses++,
            ),
          ),
        ),
      ),
    );

    final icon = tester.widget<SidebarPanelToggleIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('workspace-sidebar-toggle')),
        matching: find.byType(SidebarPanelToggleIcon),
      ),
    );
    expect(icon.side, SidebarPanelSide.left);
    expect(icon.expanded, isTrue);
    expect(icon.cue, Icons.workspaces_outlined);
    expect(
      find.descendant(
        of: find.byType(SidebarPanelToggleIcon),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.workspaces_outlined), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find
                .ancestor(
                  of: find.byType(SidebarPanelToggleIcon),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('workspace-sidebar-toggle')));
    expect(presses, 1);
    expect(find.byTooltip('Hide Workspace panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
