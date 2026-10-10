import 'package:varian/app/accessibility_runtime.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mix/mix.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/main.dart';
import '../test_app.dart';

void main() {
  group('AppTokens', () {
    test('light and dark themes expose distinct neumorphic surfaces', () {
      final light = AppTheme.lightTheme.extension<AppTokens>()!;
      final dark = AppTheme.darkTheme.extension<AppTokens>()!;

      expect(light.canvas, isNot(dark.canvas));
      expect(light.panel, isNot(dark.panel));
      expect(light.raisedShadow, isNot(dark.raisedShadow));
      expect(light.pressedShadow, isNot(dark.pressedShadow));
    });

    test('semantic statuses remain distinguishable from each other', () {
      final light = AppTheme.lightTheme.extension<AppTokens>()!;
      final dark = AppTheme.darkTheme.extension<AppTokens>()!;

      expect(light.success, isNot(light.warning));
      expect(light.warning, isNot(light.danger));
      expect(dark.success, isNot(dark.warning));
      expect(dark.warning, isNot(dark.danger));
    });

    test('Mix provides styles for reusable surfaces and controls', () {
      expect(AppStyles.surface, isNotNull);
      expect(AppStyles.control, isNotNull);
      expect(AppStyles.pressedControl, isNotNull);
    });
    testWidgets(
      'semantic badges map status colors to readable tinted surfaces',
      (tester) async {
        await tester.pumpWidget(
          testApp(
            const Scaffold(
              body: Wrap(
                children: [
                  UiBadge('Ready', variant: UiBadgeVariant.success),
                  UiBadge('Degraded', variant: UiBadgeVariant.warning),
                ],
              ),
            ),
            data: AppTheme.lightTheme,
          ),
        );

        final successBox = find
            .ancestor(of: find.text('Ready'), matching: find.byType(Box))
            .first;
        final warningBox = find
            .ancestor(of: find.text('Degraded'), matching: find.byType(Box))
            .first;
        BoxDecoration decorationFor(Finder box) =>
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: box,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;

        expect(
          decorationFor(successBox).color,
          Color.alphaBlend(
            AppTokens.light.success.withValues(alpha: 0.12),
            AppTokens.light.panel,
          ),
        );
        expect(
          decorationFor(warningBox).color,
          Color.alphaBlend(
            AppTokens.light.warning.withValues(alpha: 0.12),
            AppTokens.light.panel,
          ),
        );
        expect(
          decorationFor(successBox).color,
          isNot(decorationFor(warningBox).color),
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('badge overflow keeps its full accessible label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        testApp(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(160, 320),
              textScaler: TextScaler.linear(2),
            ),
            child: const Scaffold(
              body: SizedBox(
                width: 120,
                child: UiBadge(
                  'SIMULATION MODE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          data: AppTheme.darkTheme,
        ),
      );

      final badgeText = tester.widget<Text>(find.text('SIMULATION MODE'));
      expect(badgeText.maxLines, 1);
      expect(badgeText.overflow, TextOverflow.ellipsis);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'SIMULATION MODE',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
    testWidgets('status callout stacks its action at narrow widths', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          Center(
            child: SizedBox(
              width: 320,
              child: UiAlert(
                title: 'Connection unavailable',
                description: 'Try again after checking the network.',
                icon: Icons.wifi_off_outlined,
                variant: UiAlertVariant.destructive,
                trailing: UiButton(
                  onPressed: () {},
                  child: const Text('Retry'),
                ),
              ),
            ),
          ),
          data: AppTheme.lightTheme,
        ),
      );

      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('section header reflows its action at 360 pixels', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<(Rect, Rect)> geometryAt(double width) async {
        tester.view.physicalSize = Size(width, 640);
        await tester.pumpWidget(
          testApp(
            const UiSectionHeader(
              title: 'LIBRARY',
              trailing: SizedBox(
                key: ValueKey('section-action'),
                width: 80,
                height: 20,
              ),
            ),
          ),
        );
        return (
          tester.getRect(find.text('LIBRARY')),
          tester.getRect(find.byKey(const ValueKey('section-action'))),
        );
      }

      final compact = await geometryAt(359);
      expect(compact.$2.top, greaterThan(compact.$1.bottom));

      final inline = await geometryAt(360);
      expect(
        inline.$2.center.dy,
        closeTo(inline.$1.center.dy, AppSpacing.xs + AppSpacing.xxs),
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('status alert reflows its action at 360 pixels', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<(Rect, Rect)> geometryAt(double width) async {
        tester.view.physicalSize = Size(width, 640);
        await tester.pumpWidget(
          testApp(
            const UiAlert(
              title: 'Connection unavailable',
              description: 'Restore a network connection to continue.',
              icon: Icons.wifi_off_outlined,
              variant: UiAlertVariant.info,
              trailing: SizedBox(
                key: ValueKey('alert-action'),
                width: 80,
                height: 20,
              ),
            ),
          ),
        );
        return (
          tester.getRect(
            find.text('Restore a network connection to continue.'),
          ),
          tester.getRect(find.byKey(const ValueKey('alert-action'))),
        );
      }

      final compact = await geometryAt(359);
      expect(compact.$2.top, greaterThan(compact.$1.bottom));

      final inline = await geometryAt(360);
      expect(inline.$2.top, lessThan(inline.$1.bottom));
      expect(tester.takeException(), isNull);
    });

    test('shared dimensions keep surfaces and controls compact', () {
      expect(AppSpacing.page, 16);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 12);
      expect(AppTokens.light.spacing, 8);
      expect(AppTypography.compactScale, 0.9);
      expect(AppRadius.panel, 10);
      expect(AppRadius.control, 6);
      expect(AppControlSize.extraSmall, 28);
      expect(AppControlSize.compact, 32);
      expect(AppControlSize.regular, 36);
      expect(AppControlSize.input, 40);
      expect(AppControlSize.touch, 40);
      expect(AppControlSize.minimumHitTarget, 44);
      expect(AppElevation.panelOffset, 2);
      expect(AppElevation.panelBlur, 6);
    });

    testWidgets('reduced motion removes shared tab transition duration', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: UiTabs(
              index: 0,
              onChanged: (_) {},
              tabs: const [
                UiTabEntry(label: Text('First'), child: Text('First body')),
                UiTabEntry(label: Text('Second'), child: Text('Second body')),
              ],
            ),
          ),
          data: AppTheme.lightTheme,
        ),
      );

      final switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(switcher.duration, Duration.zero);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'shared tab transition keeps its standard duration by default',
      (tester) async {
        await tester.pumpWidget(
          testApp(
            const UiTabs(
              index: 0,
              onChanged: _ignoreIndex,
              tabs: [
                UiTabEntry(label: Text('First'), child: Text('First body')),
                UiTabEntry(label: Text('Second'), child: Text('Second body')),
              ],
            ),
            data: AppTheme.lightTheme,
          ),
        );

        final switcher = tester.widget<AnimatedSwitcher>(
          find.byType(AnimatedSwitcher),
        );
        expect(switcher.duration, AppMotion.standard);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('showUiDialog uses the shared dialog radius token', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () => showUiDialog<void>(
                  context: context,
                  builder: (_) => const Text('Dialog fixture'),
                ),
                child: const Text('Open dialog'),
              ),
            ),
            data: AppTheme.lightTheme,
          ),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      final shape = dialog.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(AppRadius.dialog));
      expect(tester.takeException(), isNull);
    });

    test('Material fallback keeps compact visuals and padded hit targets', () {
      final theme = AppTheme.lightTheme;

      expect(theme.visualDensity, VisualDensity.compact);
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.cardTheme.elevation, 0);
      expect(
        theme.filledButtonTheme.style?.minimumSize?.resolve({})?.height,
        AppControlSize.regular,
      );
    });
    test('Material 3 icon buttons use the compact control size', () {
      expect(AppTheme.lightTheme.useMaterial3, isTrue);
      expect(AppTheme.darkTheme.useMaterial3, isTrue);

      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        final size = theme.iconButtonTheme.style!.minimumSize!.resolve({})!;
        expect(size.width, AppControlSize.compact);
        expect(size.height, AppControlSize.compact);
      }
    });

    test('text fields follow the shadcn input dimensions and theme', () {
      final inputTheme = AppTheme.lightTheme.inputDecorationTheme;
      final focusedBorder = inputTheme.focusedBorder as OutlineInputBorder;
      final prefixConstraints = inputTheme.prefixIconConstraints!;

      expect(inputTheme.isDense, isTrue);
      expect(inputTheme.constraints?.minHeight, AppControlSize.input);
      expect(
        inputTheme.contentPadding,
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      );
      expect(prefixConstraints.minHeight, AppControlSize.input);
      expect(inputTheme.fillColor, AppTokens.light.panel);
      expect(focusedBorder.borderSide.color, AppTokens.light.accent);
      expect(focusedBorder.borderSide.width, AppBorder.focus);
      expect(
        focusedBorder.borderRadius.topLeft,
        const Radius.circular(AppRadius.control),
      );
      expect(inputTheme.errorBorder, isA<OutlineInputBorder>());
    });

    test('popup and anchored menus share a compact elevated surface', () {
      final theme = AppTheme.lightTheme;
      final popupTheme = theme.popupMenuTheme;
      final menuStyle = theme.menuTheme.style!;
      final menuButtonStyle = theme.menuButtonTheme.style!;

      expect(popupTheme.color, AppTokens.light.panelElevated);
      expect(popupTheme.elevation, 2);
      expect(popupTheme.surfaceTintColor, Colors.transparent);
      expect(
        popupTheme.menuPadding,
        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      );
      expect(
        (popupTheme.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(AppRadius.panel),
      );
      expect(
        menuStyle.backgroundColor?.resolve({}),
        AppTokens.light.panelElevated,
      );
      expect(menuStyle.surfaceTintColor?.resolve({}), Colors.transparent);
      expect(menuStyle.elevation?.resolve({}), 2);
      expect(
        menuStyle.padding?.resolve({}),
        const EdgeInsets.all(AppSpacing.xs),
      );
      expect(
        menuButtonStyle.minimumSize?.resolve({})?.height,
        AppControlSize.regular,
      );
    });
    test('Material 3 chrome uses explicit one-pixel semantic borders', () {
      expect(AppTheme.lightTheme.useMaterial3, isTrue);
      expect(AppTheme.darkTheme.useMaterial3, isTrue);

      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        expect(
          (theme.dialogTheme.shape! as RoundedRectangleBorder).side.width,
          AppBorder.thin,
        );
        expect(
          (theme.cardTheme.shape! as RoundedRectangleBorder).side.width,
          AppBorder.thin,
        );
        expect(
          (theme.popupMenuTheme.shape! as RoundedRectangleBorder).side.width,
          AppBorder.thin,
        );
        expect(theme.menuTheme.style!.side!.resolve({})!.width, AppBorder.thin);
        expect(
          theme.dropdownMenuTheme.menuStyle!.side!.resolve({})!.width,
          AppBorder.thin,
        );

        final input = theme.inputDecorationTheme;
        for (final border in [
          input.border! as OutlineInputBorder,
          input.enabledBorder! as OutlineInputBorder,
          input.errorBorder! as OutlineInputBorder,
        ]) {
          expect(border.borderSide.width, AppBorder.thin);
        }
        for (final border in [
          input.focusedBorder! as OutlineInputBorder,
          input.focusedErrorBorder! as OutlineInputBorder,
        ]) {
          expect(border.borderSide.width, AppBorder.focus);
        }
      }
    });
    test('Material color roles resolve to the active app token palette', () {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        final tokens = theme.appTokens;
        final colors = theme.colorScheme;
        expect(colors.primary, tokens.accent);
        expect(colors.onPrimary, tokens.accentForeground);
        expect(colors.secondary, tokens.accentSoft);
        expect(colors.onSecondary, tokens.text);
        expect(colors.surface, tokens.canvas);
        expect(colors.onSurface, tokens.text);
        expect(colors.error, tokens.danger);
        expect(colors.onError, tokens.accentForeground);
        expect(colors.outline, tokens.panelBorder);
        expect(theme.scaffoldBackgroundColor, tokens.canvas);
        expect(theme.cardColor, tokens.panel);
        expect(theme.dividerColor, tokens.panelBorder);
        expect(theme.inputDecorationTheme.fillColor, tokens.panel);
      }
    });
    testWidgets('shared page app bar draws the semantic thin bottom border', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const UiPageScaffold(title: Text('Page'), child: SizedBox.shrink()),
          data: AppTheme.darkTheme,
        ),
      );

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect((appBar.shape! as Border).bottom.width, AppBorder.thin);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('mobile pages use compact outer spacing', (tester) async {
    const paddingKey = ValueKey('responsive-page-padding');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) => Padding(
              key: paddingKey,
              padding: AppResponsive.pagePadding(context),
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<Padding>(find.byKey(paddingKey)).padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
    );
  });

  testWidgets('buttons use the shadcn compact height scale', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Wrap(
            children: [
              for (final size in UiButtonSize.values)
                UiButton(
                  key: ValueKey('button-${size.name}'),
                  onPressed: () => presses++,
                  size: size,
                  child: const Text('Save'),
                ),
            ],
          ),
        ),
      ),
    );

    expect(
      [
        for (final size in UiButtonSize.values)
          tester.getSize(find.byKey(ValueKey('button-${size.name}'))).height,
      ],
      [44, 44, 44, 44],
    );
    expect(
      [
        for (final size in UiButtonSize.values)
          tester
              .getSize(
                find.descendant(
                  of: find.byKey(ValueKey('button-${size.name}')),
                  matching: find.byType(Box),
                ),
              )
              .height,
      ],
      [28, 32, 36, 40],
    );

    final compactButton = find.byKey(const ValueKey('button-xs'));
    final compactButtonSize = tester.getSize(compactButton);
    await tester.tapAt(
      tester.getTopLeft(compactButton) + Offset(compactButtonSize.width / 2, 1),
    );
    expect(presses, 1);

    final iconButtons = find.byWidgetPredicate(
      (widget) => widget is UiIconButton,
    );
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Wrap(
            children: [
              for (final size in UiButtonSize.values)
                UiIconButton(
                  key: ValueKey('icon-button-${size.name}'),
                  icon: Icons.add,
                  tooltip: 'Icon action ${size.name}',
                  size: size,
                  onPressed: () {},
                ),
            ],
          ),
        ),
        data: AppTheme.lightTheme,
      ),
    );
    expect(iconButtons, findsNWidgets(UiButtonSize.values.length));
    for (final size in UiButtonSize.values) {
      final rect = tester.getRect(
        find.byKey(ValueKey('icon-button-${size.name}')),
      );
      expect(rect.width, greaterThanOrEqualTo(AppControlSize.minimumHitTarget));
      expect(
        rect.height,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
    }
  });

  testWidgets('icon buttons expose selected toggle state', (tester) async {
    final semantics = tester.ensureSemantics();
    var selected = true;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => UiIconButton(
              icon: Icons.layers_outlined,
              tooltip: 'Hide layers',
              selected: selected,
              onPressed: () => setState(() => selected = !selected),
            ),
          ),
        ),
        data: AppTheme.lightTheme,
      ),
    );

    final toggle = find.bySemanticsLabel('Hide layers');
    expect(
      tester.getSemantics(toggle).flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );
    await tester.tap(toggle);
    await tester.pump();
    expect(
      tester.getSemantics(toggle).flagsCollection.isSelected,
      ui.Tristate.isFalse,
    );
    semantics.dispose();
  });
  testWidgets('disabled shared buttons expose no tap handler', (tester) async {
    const buttonKey = ValueKey('disabled-action');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: UiButton(
            key: buttonKey,
            onPressed: null,
            semanticsLabel: 'Unavailable action',
            child: const Text('Unavailable'),
          ),
        ),
      ),
    );

    final button = find.byKey(buttonKey);
    expect(
      tester
          .widget<InkWell>(
            find.descendant(of: button, matching: find.byType(InkWell)),
          )
          .onTap,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('app-owned surface renders with the Mix scope', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: UiSurface(child: Text('Styled surface'))),
      ),
    );

    expect(find.text('Styled surface'), findsOneWidget);
    expect(find.byType(Box), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs use a recessed rail and raised selected indicator', (
    tester,
  ) async {
    var selectedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: UiTabs(
            index: 0,
            onChanged: (index) => selectedIndex = index,
            tabs: const [
              UiTabEntry(label: Text('Overview'), child: Text('Overview body')),
              UiTabEntry(label: Text('Activity'), child: Text('Activity body')),
            ],
          ),
        ),
      ),
    );

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    final indicator = tabBar.indicator as BoxDecoration;
    expect(tabBar.dividerColor, Colors.transparent);
    expect(indicator.boxShadow, hasLength(2));
    expect(find.byType(Box), findsWidgets);
    expect(find.text('Overview body'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    expect(selectedIndex, 1);
  });

  testWidgets('controlled tabs synchronize when the parent changes index', (
    tester,
  ) async {
    var selectedIndex = 0;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: const ValueKey('select-second-tab-externally'),
                  onPressed: () => setState(() => selectedIndex = 1),
                  child: const Text('Select second externally'),
                ),
                UiTabs(
                  index: selectedIndex,
                  onChanged: (index) => setState(() => selectedIndex = index),
                  tabs: const [
                    UiTabEntry(label: Text('First'), child: Text('First body')),
                    UiTabEntry(
                      label: Text('Second'),
                      child: Text('Second body'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        data: AppTheme.lightTheme,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('select-second-tab-externally')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Second body'), findsOneWidget);
    final tabController = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    expect(tabController.index, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status toasts choose text colors with readable contrast', (
    tester,
  ) async {
    const variants = [
      UiToastVariant.success,
      UiToastVariant.warning,
      UiToastVariant.error,
    ];
    final themes = [AppTheme.lightTheme, AppTheme.darkTheme];

    for (final theme in themes) {
      final tokens = theme.appTokens;
      for (final variant in variants) {
        await tester.pumpWidget(
          testApp(
            Scaffold(
              body: Builder(
                builder: (context) => UiButton(
                  onPressed: () =>
                      showUiToast(context, 'Status message', variant: variant),
                  child: const Text('Show status'),
                ),
              ),
            ),
            data: theme,
          ),
        );
        await tester.tap(find.text('Show status'));
        await tester.pumpAndSettle();

        final toast = tester.widget<SnackBar>(find.byType(SnackBar));
        final content = toast.content as Text;
        final background = switch (variant) {
          UiToastVariant.success => tokens.success,
          UiToastVariant.warning => tokens.warning,
          UiToastVariant.error => tokens.danger,
          UiToastVariant.info => tokens.panelElevated,
        };
        final foreground = content.style!.color!;
        final lighter =
            foreground.computeLuminance() > background.computeLuminance();
        final contrast =
            (lighter
                ? foreground.computeLuminance() + 0.05
                : background.computeLuminance() + 0.05) /
            (lighter
                ? background.computeLuminance() + 0.05
                : foreground.computeLuminance() + 0.05);

        expect(toast.backgroundColor, background);
        expect(contrast, greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('action menus align selection, destructive, and separators', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: UiMenuButton<String>(
              tooltip: 'More actions',
              icon: Icons.more_horiz,
              items: const [
                UiMenuAction<String>(
                  value: 'current',
                  label: 'Current item',
                  icon: Icons.check_circle_outline,
                  selected: true,
                ),
                UiMenuAction<String>(
                  value: 'remove',
                  label: 'Remove item',
                  icon: Icons.delete_outline,
                  destructive: true,
                  separatorBefore: true,
                ),
              ],
              onSelected: _ignoreValue,
            ),
          ),
        ),
        data: AppTheme.lightTheme,
      ),
    );

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();

    expect(find.text('Current item'), findsOneWidget);
    expect(find.text('Remove item'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    expect(
      tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .map((item) => item.height),
      everyElement(AppControlSize.minimumHitTarget),
    );
    final menu = tester.widget<PopupMenuButton<String>>(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton<String>),
    );
    expect(menu.position, PopupMenuPosition.under);
    expect(tester.takeException(), isNull);
  });

  testWidgets('select menus use the shared raised surface and update value', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: UiSelect<String>(
              key: const ValueKey('project-visibility-select'),
              items: const {'Private': 'private', 'Workspace': 'workspace'},
              value: selected,
              label: 'Visibility',
              hint: 'Choose visibility',
              onChanged: (value) => selected = value,
            ),
          ),
        ),
        data: AppTheme.lightTheme,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('project-visibility-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace').last);
    await tester.pumpAndSettle();
    expect(selected, 'workspace');
    expect(find.text('Workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text fields use the neumorphic 40px shadcn input target', (
    tester,
  ) async {
    const fieldKey = ValueKey('input-height-regression');
    await tester.pumpWidget(
      testApp(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: UiTextField(
              key: fieldKey,
              hint: 'Enter a value',
              prefix: Icon(Icons.search),
            ),
          ),
        ),
        data: AppTheme.lightTheme,
      ),
    );

    final field = find.byKey(fieldKey);
    expect(
      tester.getSize(field).height,
      greaterThanOrEqualTo(AppControlSize.input),
    );
    expect(
      tester.getSize(find.byType(InputDecorator).first).height,
      greaterThanOrEqualTo(AppControlSize.input),
    );
    expect(find.byType(Box), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app-owned loading state renders with the Mix scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: UiLoadingState()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('surface custom colors, radius, and border resolve in Mix', (
    tester,
  ) async {
    const customColor = Color(0xFF123456);
    const customRadius = BorderRadius.all(Radius.circular(20));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: UiSurface(
            color: customColor,
            borderRadius: customRadius,
            child: Text('Custom surface'),
          ),
        ),
      ),
    );

    final decoration = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(Box),
        matching: find.byType(DecoratedBox),
      ),
    );
    final boxDecoration = decoration.decoration as BoxDecoration;
    expect(find.text('Custom surface'), findsOneWidget);
    expect(boxDecoration.color, customColor);
    expect(boxDecoration.borderRadius, customRadius);
    expect(boxDecoration.border, isNotNull);
    expect(boxDecoration.boxShadow, hasLength(2));
    expect(boxDecoration.boxShadow!.map((shadow) => shadow.offset), [
      const Offset(2, 2),
      const Offset(-2, -2),
    ]);
    expect(boxDecoration.boxShadow!.map((shadow) => shadow.blurRadius), [6, 6]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('application root composes platform and app text scales', (
    tester,
  ) async {
    const settings = AccessibilitySettings(
      largerText: true,
      textScaleFactor: 1.3,
    );
    final runtime = AccessibilityRuntimeProfile.fromSettings(settings);
    const platformScaler = TextScaler.linear(1.5);

    expect(runtime.textScaler(platformScaler).scale(10), closeTo(17.55, 0.001));

    await tester.pumpWidget(const ProviderScope(child: CreativeCanvasApp()));
    expect(find.byType(CreativeCanvasApp), findsOneWidget);
    expect(find.byType(MixScope), findsWidgets);
    final scaler = tester
        .widgetList<MediaQuery>(find.byType(MediaQuery))
        .map((query) => query.data.textScaler)
        .whereType<AppAccessibilityTextScaler>()
        .first;
    expect(scaler.scale(10), closeTo(9, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('select renders with shared theme tokens', (tester) async {
    await tester.pumpWidget(
      testApp(
        const UiSelect<String>(
          items: {'Text': 'text'},
          value: 'text',
          onChanged: _ignoreValue,
          hint: 'Select an item',
        ),
        data: AppTheme.lightTheme,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('UiSlider exposes its app-provided semantics label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        const Scaffold(
          body: UiSlider(
            value: 0.5,
            onChanged: null,
            semanticsLabel: 'Video volume',
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Video volume'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('date picker clamps an initial date to its bounds', (
    tester,
  ) async {
    DateTime? selected;
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => UiButton(
            key: const ValueKey('open-date-picker-button'),
            onPressed: () async {
              selected = await showUiDatePicker(
                context: context,
                initialDate: DateTime(2030, 1, 1),
                firstDate: DateTime(2020, 1, 1),
                lastDate: DateTime(2025, 12, 31),
              );
            },
            child: const Text('Open date picker'),
          ),
        ),
        data: AppTheme.lightTheme,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-date-picker-button')));
    await tester.pumpAndSettle();
    expect(find.text('Select date'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2025, 12, 31));
  });
}

void _ignoreValue(String? value) {}

void _ignoreIndex(int index) {}
