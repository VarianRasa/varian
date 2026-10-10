import 'dart:ui' as ui;
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_surface.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import 'package:varian/features/charts/presentation/chart_node_widget.dart';
import 'package:varian/features/charts/presentation/chart_palette.dart';
import '../../test_app.dart';

void main() {
  testWidgets('creates a selected chart with the chosen type', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeChartTypeProvider.notifier).state = ChartType.radar;
    container.read(activeToolProvider.notifier).setTool(CanvasTool.chart);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const CanvasEditorSurface(
            projectId: 'chart-create-test',
            services: CanvasEditorServices.embedded,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(container.read(activeToolProvider), CanvasTool.chart);
    await tester.tap(find.byKey(const ValueKey('canvas-render-stack')));
    // The canvas also listens for double taps, so single-tap dispatch completes
    // after Flutter's double-tap recognition window.
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(activeToolProvider), CanvasTool.select);
    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    expect(nodes.single.type.name, 'chart');
    expect((nodes.single.payload as ChartPayload).chartType, ChartType.radar);
    expect(find.byType(ChartNodeWidget), findsOneWidget);
    expect(container.read(activeToolProvider), CanvasTool.select);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates a chart by dragging a chart type to the canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          Stack(
            children: [
              const CanvasEditorSurface(
                projectId: 'chart-drop-test',
                services: CanvasEditorServices.embedded,
              ),
              Positioned(
                left: 20,
                top: 20,
                child: Draggable<ChartType>(
                  data: ChartType.scatter,
                  feedback: const SizedBox(width: 40, height: 40),
                  child: Container(
                    key: const ValueKey('chart-drag-source'),
                    width: 60,
                    height: 60,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final source = tester.getRect(
      find.byKey(const ValueKey('chart-drag-source')),
    );
    final target = tester.getRect(
      find.byKey(const ValueKey('diagram-shape-drop-target')),
    );
    await tester.dragFrom(source.center, target.center - source.center);
    await tester.pump(const Duration(milliseconds: 350));

    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    expect((nodes.single.payload as ChartPayload).chartType, ChartType.scatter);
    expect(container.read(activeToolProvider), CanvasTool.select);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart palette tap selects a chart tool and type', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const ChartPalette()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Radar'));
    await tester.pump();

    expect(container.read(activeChartTypeProvider), ChartType.radar);
    expect(container.read(activeToolProvider), CanvasTool.chart);
    expect(tester.takeException(), isNull);
  });
  testWidgets('chart palette labels use semantic theme text sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const ChartPalette())),
    );
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(ChartPalette)));

    final tokens = theme.extension<AppTokens>()!;
    final header = tester.widget<Text>(find.text('CHART TYPES'));
    final instruction = tester.widget<Text>(
      find.text('Drag a chart to the canvas or tap to select it.'),
    );
    expect(
      header.style,
      theme.textTheme.labelSmall!.copyWith(
        color: tokens.textMuted,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
    expect(
      instruction.style,
      theme.textTheme.bodySmall!.copyWith(color: tokens.textMuted),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'chart tiles retain their local layout bounds and chrome tokens',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: testApp(const ChartPalette())),
      );
      await tester.pumpAndSettle();

      final lineTile = find.descendant(
        of: find.byTooltip('Line'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.width == 101 && widget.height == 64,
        ),
      );
      expect(lineTile, findsOneWidget);
      expect(tester.getSize(lineTile), const Size(101, 64));

      final tileSurface = tester.widget<UiSurface>(
        find.descendant(of: lineTile, matching: find.byType(UiSurface)),
      );
      expect(
        tileSurface.padding,
        const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      );
      expect(tileSurface.borderWidth, AppBorder.thin);
      expect(
        tileSurface.borderRadius,
        BorderRadius.circular(AppRadius.control),
      );
      final icon = find.descendant(
        of: lineTile,
        matching: find.byWidgetPredicate(
          (widget) => widget is Icon && widget.size == 22,
        ),
      );
      expect(tester.getSize(icon), const Size(22, 22));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'chart palette drag feedback uses the extra-small control token',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: testApp(const ChartPalette())),
      );
      await tester.pumpAndSettle();

      final tile = find.byTooltip('Line');
      final gesture = await tester.startGesture(tester.getCenter(tile));
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();

      final feedbackIcon = find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.icon == Icons.show_chart &&
            widget.size == AppControlSize.extraSmall,
      );
      expect(feedbackIcon, findsOneWidget);
      expect(tester.getSize(feedbackIcon), const Size(28, 28));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'chart type controls stay draggable, keyboard accessible, and selected',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeChartTypeProvider.notifier).state = ChartType.bar;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(const ChartPalette()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Draggable<ChartType> && widget.data == ChartType.line,
        ),
        findsOneWidget,
      );
      expect(
        tester
                .getSemantics(find.bySemanticsLabel('Bar / Column'))
                .flagsCollection
                .isSelected ==
            ui.Tristate.isTrue,
        isTrue,
      );

      var keyboardActivated = false;
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        if (container.read(activeChartTypeProvider) == ChartType.line) {
          keyboardActivated = true;
          break;
        }
      }
      expect(keyboardActivated, isTrue);
      expect(container.read(activeChartTypeProvider), ChartType.line);
      expect(container.read(activeToolProvider), CanvasTool.chart);
      expect(
        tester
                .getSemantics(find.bySemanticsLabel('Line'))
                .flagsCollection
                .isSelected ==
            ui.Tristate.isTrue,
        isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('toolbar charts category creates the selected chart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const Stack(
            children: [
              CanvasEditorSurface(
                projectId: 'toolbar-chart-create-test',
                services: CanvasEditorServices.embedded,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Charts (Click to open)'));
    await tester.pump();
    expect(find.byTooltip('Line'), findsOneWidget);

    await tester.tap(find.byTooltip('Line'));
    await tester.pump();
    expect(container.read(activeChartTypeProvider), ChartType.line);
    expect(container.read(activeToolProvider), CanvasTool.chart);

    await tester.tap(find.byKey(const ValueKey('canvas-render-stack')));
    await tester.pump(const Duration(milliseconds: 400));

    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    expect(nodes.single.type, NodeType.chart);
    expect((nodes.single.payload as ChartPayload).chartType, ChartType.line);
    expect(container.read(activeToolProvider), CanvasTool.select);
    expect(tester.takeException(), isNull);
  });
}
