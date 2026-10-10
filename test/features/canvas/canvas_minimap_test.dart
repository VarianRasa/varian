import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_minimap.dart';

void main() {
  CanvasNode node({String id = 'node'}) => CanvasNode(
    id: id,
    type: NodeType.rectangle,
    x: 100,
    y: 100,
    width: 120,
    height: 80,
    payload: ShapePayload(),
  );

  Widget host({
    required VoidCallback onFit,
    required ValueChanged<Offset> onCenter,
    bool collapsed = false,
    double width = 260,
    double height = 200,
  }) {
    return MaterialApp(
      home: AppThemeScope(
        data: AppTheme.lightTheme,
        child: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: CanvasMinimap(
              nodes: [node()],
              viewport: const Viewport(),
              canvasSize: const Size(800, 600),
              initiallyCollapsed: collapsed,
              onViewportCenterChanged: onCenter,
              onFit: onFit,
              onZoomIn: () {},
              onZoomOut: () {},
              onReset: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders minimap and exposes navigation semantics', (
    tester,
  ) async {
    Offset? center;
    await tester.pumpWidget(
      host(onFit: () {}, onCenter: (value) => center = value),
    );

    expect(find.text('MINIMAP'), findsOneWidget);
    expect(find.byTooltip('Zoom in canvas'), findsOneWidget);
    expect(find.byTooltip('Zoom out canvas'), findsOneWidget);
    final frame = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('canvas-minimap-frame')),
    );
    final frameBorder = (frame.decoration as BoxDecoration).border! as Border;
    expect(frameBorder.top.width, AppBorder.thin);
    expect(frameBorder.top.color, AppTokens.light.panelBorder);

    await tester.tapAt(const Offset(220, 150));
    await tester.pump();
    expect(center, isNotNull);
  });

  testWidgets('fit control calls callback and collapse can expand', (
    tester,
  ) async {
    var fitCalls = 0;
    await tester.pumpWidget(host(onFit: () => fitCalls++, onCenter: (_) {}));

    await tester.tap(find.byTooltip('Fit canvas content'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(fitCalls, 1);

    await tester.tap(find.byTooltip('Collapse minimap'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Expand minimap'), findsOneWidget);
    final collapsedFrame = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('canvas-minimap-collapsed-frame')),
    );
    expect(
      ((collapsedFrame.decoration as BoxDecoration).border! as Border)
          .top
          .width,
      AppBorder.thin,
    );

    await tester.tap(find.byTooltip('Expand minimap'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('MINIMAP'), findsOneWidget);
  });

  testWidgets('dragging viewport reports more than one center', (tester) async {
    final centers = <Offset>[];
    await tester.pumpWidget(host(onFit: () {}, onCenter: centers.add));

    final map = find.text('MINIMAP');
    final rect = tester.getRect(map);
    await tester.dragFrom(rect.center, rect.center + const Offset(20, 10));
    await tester.pump();

    expect(centers.length, greaterThanOrEqualTo(2));
  });
  testWidgets('arrow keys pan minimap by ten percent of viewport', (
    tester,
  ) async {
    final centers = <Offset>[];
    await tester.pumpWidget(host(onFit: () {}, onCenter: centers.add));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(centers, [const Offset(480, 300)]);
  });

  testWidgets('narrow minimap scrolls 44px targets without overflow', (
    tester,
  ) async {
    var fitCalls = 0;
    await tester.pumpWidget(
      host(onFit: () => fitCalls++, onCenter: (_) {}, width: 104, height: 70),
    );

    for (final tooltip in [
      'Zoom out canvas',
      'Zoom in canvas',
      'Fit canvas content',
      'Reset canvas view',
      'Collapse minimap',
    ]) {
      final control = find.byTooltip(tooltip);
      expect(control, findsOneWidget);
      expect(
        tester.getSize(control),
        const Size(
          AppControlSize.minimumHitTarget,
          AppControlSize.minimumHitTarget,
        ),
      );
    }
    final fitControl = find.byTooltip('Fit canvas content');
    await tester.ensureVisible(fitControl);
    await tester.pumpAndSettle();
    await tester.tap(fitControl);
    await tester.pump();
    expect(fitCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimap toolbar hides below its minimum target height', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(onFit: () {}, onCenter: (_) {}, width: 104, height: 43),
    );

    expect(find.byTooltip('Zoom in canvas'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
