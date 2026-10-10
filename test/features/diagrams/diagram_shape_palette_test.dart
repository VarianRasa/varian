import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';
import 'package:varian/features/diagrams/presentation/diagram_shape_palette.dart';
import '../../test_app.dart';

void main() {
  testWidgets('searches shapes and activates the selected native shape', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const DiagramShapePalette()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DIAGRAM SHAPES'), findsOneWidget);
    expect(find.text('Rectangle'), findsOneWidget);
    expect(find.text('Hexagon'), findsOneWidget);

    final search = find.byWidgetPredicate(
      (widget) => widget is UiTextField && widget.label == 'Search shapes',
    );
    await tester.enterText(search, 'hexagon');
    await tester.pump();

    expect(find.text('Hexagon'), findsOneWidget);
    expect(find.text('Rectangle'), findsNothing);
    expect(find.bySemanticsLabel('Hexagon'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Hexagon'));
    await tester.pump();

    expect(container.read(activeToolProvider), CanvasTool.diagramShape);
    expect(container.read(activeDiagramShapeProvider).id, 'hexagon');
    expect(tester.takeException(), isNull);
  });

  testWidgets('marks shape selection and keeps controls touch sized', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const DiagramShapePalette()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Hexagon'));
    await tester.pump();

    expect(
      tester
              .getSemantics(find.bySemanticsLabel('Hexagon'))
              .flagsCollection
              .isSelected ==
          ui.Tristate.isTrue,
      isTrue,
    );
    final button = find
        .ancestor(of: find.text('Hexagon'), matching: find.byType(UiButton))
        .first;
    expect(
      tester.getSize(button).height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    semantics.dispose();
  });

  testWidgets('filters the palette by category', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const DiagramShapePalette())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('UML').last);
    await tester.pump();

    expect(find.text('UML class'), findsOneWidget);
    expect(find.text('Rectangle'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes each native shape as a draggable item', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const DiagramShapePalette())),
    );
    await tester.pumpAndSettle();

    final hexagonDrag = find.byWidgetPredicate(
      (widget) =>
          widget is Draggable<DiagramShapeDefinition> &&
          widget.data?.id == 'hexagon',
    );
    expect(hexagonDrag, findsOneWidget);
    expect(find.bySemanticsLabel('Hexagon'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('diagram palette header uses the shared section text role', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const DiagramShapePalette())),
    );
    await tester.pumpAndSettle();

    final header = find.text('DIAGRAM SHAPES');
    final theme = Theme.of(tester.element(header));
    final tokens = theme.extension<AppTokens>()!;
    expect(
      tester.widget<Text>(header).style,
      theme.textTheme.labelSmall!.copyWith(
        color: tokens.textMuted,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty-state copy follows the Material body-medium role', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const DiagramShapePalette())),
    );
    await tester.pumpAndSettle();

    final search = find.byWidgetPredicate(
      (widget) => widget is UiTextField && widget.label == 'Search shapes',
    );
    await tester.enterText(search, 'no-matching-shape');
    await tester.pump();

    final emptyState = find.text('No diagram shapes found.');
    final theme = Theme.of(tester.element(emptyState));
    final tokens = theme.extension<AppTokens>()!;
    expect(
      tester.widget<Text>(emptyState).style,
      theme.textTheme.bodyMedium!.copyWith(color: tokens.textMuted),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('reflows the palette in a compact viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: testApp(const DiagramShapePalette())),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Search shapes'), findsOneWidget);
    expect(find.bySemanticsLabel('Hexagon'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'palette and shape controls stay within compact and wide bounds',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      Future<void> verifyBounds(Size viewport, double expectedWidth) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: testApp(const Center(child: DiagramShapePalette())),
          ),
        );
        await tester.pumpAndSettle();

        final palette = find
            .byWidgetPredicate(
              (widget) => widget is SizedBox && widget.width == expectedWidth,
            )
            .first;
        final panel = tester.getRect(palette);
        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(viewport.width));
        final shapeList = find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.vertical,
        );
        expect(shapeList, findsOneWidget);
        final shapeListBounds = tester.getRect(shapeList);
        expect(shapeListBounds.left, greaterThanOrEqualTo(panel.left));
        expect(shapeListBounds.top, greaterThanOrEqualTo(panel.top));
        expect(shapeListBounds.right, lessThanOrEqualTo(panel.right));
        expect(shapeListBounds.bottom, lessThanOrEqualTo(panel.bottom));
        expect(panel.width, expectedWidth);
        final shape = find
            .ancestor(of: find.text('Hexagon'), matching: find.byType(UiButton))
            .first;
        final shapeRect = tester.getRect(shape);
        expect(shapeRect.left, greaterThanOrEqualTo(panel.left));
        expect(shapeRect.right, lessThanOrEqualTo(panel.right));
        expect(shapeRect.top, greaterThanOrEqualTo(panel.top));
        expect(shapeRect.bottom, lessThanOrEqualTo(panel.bottom));
        expect(tester.takeException(), isNull);
      }

      addTearDown(tester.view.reset);
      await verifyBounds(const Size(320, 480), 224);
      await verifyBounds(const Size(1200, 900), 330);
    },
  );
}
