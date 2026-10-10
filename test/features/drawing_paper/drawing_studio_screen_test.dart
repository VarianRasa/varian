import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_brush_settings_bar.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_left_toolbar.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_top_bar.dart';
import 'package:varian/features/drawing_paper/presentation/studio/drawing_studio_screen.dart';
import 'package:varian/features/drawing_paper/presentation/studio/painters/studio_brush_cursor_painter.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_layer_panel.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_color_panel.dart';

import '../../test_app.dart';

DrawingPaperPayload _payload({List<DrawingLayer>? layers}) =>
    DrawingPaperPayload(
      presetName: 'Test Paper',
      pixelWidth: 240,
      pixelHeight: 180,
      layers: layers,
    );

Future<ProviderContainer> _pumpStudio(
  WidgetTester tester,
  DrawingPaperPayload payload, {
  ValueChanged<DrawingPaperPayload>? onSave,
  Size size = const Size(1200, 900),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: testApp(
        DrawingStudioScreen(
          initialPayload: payload,
          onSaveAndExit: onSave ?? (_) {},
        ),
        data: theme,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(DrawingStudioScreen)),
  );
}

Offset _paperToScreen(
  Rect canvasRect,
  DrawingPaperPayload payload,
  DrawingStudioState state,
  Offset paperPoint,
) {
  return canvasRect.center +
      (paperPoint - payload.pixelSize.center(Offset.zero)) * state.viewZoom +
      state.viewPan;
}

BorderSide _bottomChromeBorder(WidgetTester tester, Finder ancestor) {
  final borderedBoxes = tester
      .widgetList<DecoratedBox>(
        find.descendant(of: ancestor, matching: find.byType(DecoratedBox)),
      )
      .where((box) {
        final decoration = box.decoration;
        return decoration is BoxDecoration &&
            decoration.border is Border &&
            (decoration.border! as Border).bottom.width > 0;
      });
  expect(borderedBoxes, isNotEmpty);
  return ((borderedBoxes.first.decoration as BoxDecoration).border! as Border)
      .bottom;
}

void main() {
  testWidgets('keeps Focus Studio top bar usable at mobile width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          DrawingStudioScreen(
            initialPayload: _payload(),
            onSaveAndExit: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Back to Infinite Canvas'), findsOneWidget);
    expect(find.byTooltip('Export Paper'), findsOneWidget);
    final compactDividers = tester.widgetList<VerticalDivider>(
      find.descendant(
        of: find.byType(StudioTopBar),
        matching: find.byType(VerticalDivider),
      ),
    );
    expect(compactDividers, hasLength(4));
    expect(
      compactDividers.every((divider) => divider.thickness == AppBorder.thin),
      isTrue,
    );
    await tester.tap(find.byTooltip('Open studio panels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Layers').last);
    await tester.pumpAndSettle();
    final compactPanelDivider = tester.widget<Divider>(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.byType(Divider),
      ),
    );
    expect(compactPanelDivider.thickness, AppBorder.thin);
    final compactPanelDialog = tester.widget<Dialog>(find.byType(Dialog).last);
    expect(
      (compactPanelDialog.shape! as RoundedRectangleBorder).side.width,
      AppBorder.thin,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps Focus Studio chrome usable on a short narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          DrawingStudioScreen(
            initialPayload: _payload(),
            onSaveAndExit: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.byType(UiPageScaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('studio side panels follow the shared medium breakpoint', (
    tester,
  ) async {
    Future<void> verifyLayout(Size viewport, {required bool wide}) async {
      final payload = _payload();
      await _pumpStudio(tester, payload, size: viewport);

      final topBar = tester.getRect(find.byType(StudioTopBar));
      final brushBar = tester.getRect(find.byType(StudioBrushSettingsBar));
      final leftToolbar = tester.getRect(find.byType(StudioLeftToolbar));
      expect(topBar.width, viewport.width);
      expect(topBar.height, wide ? 48 : 96);
      expect(brushBar.width, viewport.width);
      expect(brushBar.top, topBar.bottom);
      expect(leftToolbar.top, brushBar.bottom);
      expect(leftToolbar.width, 52);
      expect(leftToolbar.right, lessThanOrEqualTo(viewport.width));
      expect(leftToolbar.bottom, lessThanOrEqualTo(viewport.height));
      expect(
        find.byType(StudioColorPanel),
        wide ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(StudioLayerPanel),
        wide ? findsOneWidget : findsNothing,
      );
      if (wide) {
        for (final panel in [
          find.byType(StudioColorPanel),
          find.byType(StudioLayerPanel),
        ]) {
          final rect = tester.getRect(panel);
          expect(rect.left, greaterThanOrEqualTo(leftToolbar.right));
          expect(rect.right, lessThanOrEqualTo(viewport.width));
          expect(rect.bottom, lessThanOrEqualTo(viewport.height));
        }
      }
      expect(tester.takeException(), isNull);
    }

    await verifyLayout(const Size(839, 844), wide: false);
    await verifyLayout(const Size(840, 844), wide: true);
  });

  testWidgets('Focus Studio tools retain minimum hit targets in the rail', (
    tester,
  ) async {
    final payload = _payload();
    final container = await _pumpStudio(
      tester,
      payload,
      size: const Size(320, 568),
    );

    final rail = find.byType(StudioLeftToolbar);
    final railBounds = tester.getRect(rail);
    final buttons = find.descendant(of: rail, matching: find.byType(UiButton));
    expect(buttons, findsNWidgets(9));
    for (final button in buttons.evaluate()) {
      final finder = find.byWidget(button.widget);
      final bounds = tester.getRect(finder);
      expect(
        bounds.width,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
      expect(
        bounds.height,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
      expect(bounds.left, greaterThanOrEqualTo(railBounds.left));
      expect(bounds.right, lessThanOrEqualTo(railBounds.right));
    }
    final activateBrush = find.ancestor(
      of: find.byTooltip('Pen & Brushes (B)'),
      matching: find.byType(UiIconButton),
    );
    await tester.tapAt(
      tester.getRect(activateBrush).bottomRight - const Offset(2, 2),
    );
    await tester.pump();
    expect(
      container.read(drawingStudioProviderFamily(payload)).activeTool,
      StudioTool.brush,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the shared studio toolbar surface', (tester) async {
    await _pumpStudio(tester, _payload());

    expect(find.text('Back to Infinite Canvas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounds the studio toolbar with the shared viewport width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          DrawingStudioScreen(
            initialPayload: _payload(),
            onSaveAndExit: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final toolbar = find.byType(StudioTopBar);
    expect(toolbar, findsOneWidget);
    expect(tester.getRect(toolbar).width, 390);
    expect(tester.takeException(), isNull);
  });

  testWidgets('studio chrome separators and frames use thin borders', (
    tester,
  ) async {
    await _pumpStudio(tester, _payload());

    final leftToolbar = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(StudioLeftToolbar),
            matching: find.byType(Container),
          )
          .first,
    );
    final leftToolbarBorder =
        (leftToolbar.decoration! as BoxDecoration).border! as Border;
    expect(leftToolbarBorder.right.width, AppBorder.thin);
    final layerPanel = find.byType(StudioLayerPanel);
    final layerFrame = tester.widget<Container>(
      find.byKey(const ValueKey('drawing-studio-layer-panel-frame')),
    );
    expect(
      ((layerFrame.decoration! as BoxDecoration).border! as Border).left.width,
      AppBorder.thin,
    );
    expect(_bottomChromeBorder(tester, layerPanel).width, AppBorder.thin);

    final toolbarDividers = tester.widgetList<Divider>(
      find.descendant(
        of: find.byType(StudioLeftToolbar),
        matching: find.byType(Divider),
      ),
    );
    expect(toolbarDividers, hasLength(2));
    expect(
      toolbarDividers.every((divider) => divider.thickness == AppBorder.thin),
      isTrue,
    );

    final brushBarBorder = _bottomChromeBorder(
      tester,
      find.byType(StudioBrushSettingsBar),
    );
    expect(brushBarBorder.width, AppBorder.thin);
    final brushSeparators = tester.widgetList<VerticalDivider>(
      find.descendant(
        of: find.byType(StudioBrushSettingsBar),
        matching: find.byType(VerticalDivider),
      ),
    );
    expect(brushSeparators, hasLength(1));
    expect(brushSeparators.single.thickness, AppBorder.thin);

    final topBarBorder = _bottomChromeBorder(tester, find.byType(StudioTopBar));
    expect(topBarBorder.width, AppBorder.thin);
    final topBarDividers = tester.widgetList<VerticalDivider>(
      find.descendant(
        of: find.byType(StudioTopBar),
        matching: find.byType(VerticalDivider),
      ),
    );
    expect(topBarDividers, hasLength(3));
    expect(
      topBarDividers.every((divider) => divider.thickness == AppBorder.thin),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a custom cursor for Focus Studio drawing tools', (
    tester,
  ) async {
    final payload = _payload();
    await _pumpStudio(tester, payload);

    final pointerSurface = tester.widget<MouseRegion>(
      find.byKey(const ValueKey('drawing-studio-pointer-surface')),
    );
    expect(pointerSurface.cursor, SystemMouseCursors.none);

    final cursorFinder = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is StudioBrushCursorPainter,
    );
    expect(cursorFinder, findsOneWidget);
    expect(
      (tester.widget<CustomPaint>(cursorFinder).painter
              as StudioBrushCursorPainter)
          .position,
      isNull,
    );

    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: 0,
    );
    await mouse.addPointer(location: canvasRect.center);
    await mouse.moveTo(canvasRect.center + const Offset(1, 1));
    await tester.pump();
    expect(
      (tester.widget<CustomPaint>(cursorFinder).painter
              as StudioBrushCursorPainter)
          .position,
      isNotNull,
    );
    await mouse.removePointer();
  });

  testWidgets('creates and commits inline text objects', (tester) async {
    final payload = _payload();
    final container = await _pumpStudio(tester, payload);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );

    await tester.tap(find.byIcon(Icons.title));
    await tester.pump(const Duration(milliseconds: 200));
    final state = container.read(drawingStudioProviderFamily(payload));
    expect(state.activeTool, StudioTool.text);
    await tester.tapAt(
      _paperToScreen(canvasRect, payload, state, const Offset(120, 90)),
    );
    await tester.pump();
    final editor = find.byKey(
      const ValueKey('drawing-studio-inline-text-editor'),
    );
    expect(editor, findsOneWidget);

    await tester.enterText(editor, 'Lettering');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final updatedState = container.read(drawingStudioProviderFamily(payload));
    expect(updatedState.payload.layers.single.texts.single.text, 'Lettering');
  });
  for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
    testWidgets(
      'inline text editor uses the ${theme.brightness.name} theme on compact screens',
      (tester) async {
        final payload = _payload();
        final tokens = theme.extension<AppTokens>()!;
        final container = await _pumpStudio(
          tester,
          payload,
          size: const Size(320, 568),
          theme: theme,
        );
        container
            .read(drawingStudioProviderFamily(payload).notifier)
            .setTool(StudioTool.text);
        await tester.pump();

        final canvasRect = tester.getRect(
          find.byKey(const ValueKey('drawing-studio-canvas')),
        );
        final state = container.read(drawingStudioProviderFamily(payload));
        await tester.tapAt(
          _paperToScreen(canvasRect, payload, state, const Offset(120, 90)),
        );
        await tester.pump();

        final editor = tester.widget<TextField>(
          find.byKey(const ValueKey('drawing-studio-inline-text-editor')),
        );
        expect(editor.decoration?.fillColor, tokens.panel);
        expect(
          editor.decoration?.contentPadding,
          const EdgeInsets.all(AppSpacing.md),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('escape cancels a new inline text object', (tester) async {
    final payload = _payload();
    final container = await _pumpStudio(tester, payload);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );

    await tester.tap(find.byIcon(Icons.title));
    await tester.pump(const Duration(milliseconds: 200));
    final state = container.read(drawingStudioProviderFamily(payload));
    expect(state.activeTool, StudioTool.text);
    await tester.tapAt(
      _paperToScreen(canvasRect, payload, state, const Offset(120, 90)),
    );
    await tester.pump();
    final editor = find.byKey(
      const ValueKey('drawing-studio-inline-text-editor'),
    );
    await tester.enterText(editor, 'Discarded');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final updatedState = container.read(drawingStudioProviderFamily(payload));
    expect(updatedState.payload.layers.single.texts, isEmpty);
    expect(editor, findsNothing);
  });

  testWidgets('creates and edits a speech balloon', (tester) async {
    final payload = _payload();
    final container = await _pumpStudio(tester, payload);
    final canvasFinder = find.byKey(const ValueKey('drawing-studio-canvas'));
    final canvasRect = tester.getRect(canvasFinder);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      container.read(drawingStudioProviderFamily(payload)).activeTool,
      StudioTool.speechBalloon,
    );
    final dragStart = canvasRect.center - const Offset(40, 25);
    await tester.dragFrom(dragStart, dragStart + const Offset(80, 50));
    await tester.pump();

    var state = container.read(drawingStudioProviderFamily(payload));
    final balloon = state.payload.mangaStructure!.balloons.single;
    final balloonCenter = _paperToScreen(
      canvasRect,
      payload,
      state,
      balloon.position +
          Offset(balloon.size.width / 2, balloon.size.height / 2),
    );
    await tester.tapAt(balloonCenter);
    await tester.pump();
    final editor = find.byKey(
      const ValueKey('drawing-studio-inline-balloon-editor'),
    );
    expect(editor, findsOneWidget);

    await tester.enterText(editor, 'Hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    state = container.read(drawingStudioProviderFamily(payload));
    expect(state.payload.mangaStructure!.balloons.single.text, 'Hello');
  });

  testWidgets('routes bucket fill and eyedropper toolbar actions', (
    tester,
  ) async {
    final payload = _payload();
    final container = await _pumpStudio(tester, payload);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );
    final notifier = container.read(
      drawingStudioProviderFamily(payload).notifier,
    );

    await tester.tap(find.byIcon(Icons.format_color_fill_outlined));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      container.read(drawingStudioProviderFamily(payload)).activeTool,
      StudioTool.bucketFill,
    );

    notifier.addStrokeToActiveLayer(
      const DrawingStroke(
        id: 'stroke_1',
        brush: StudioBrushCategory.gPen,
        color: Colors.red,
        size: 18,
        opacity: 1,
        points: [
          DrawingStrokePoint(x: 100, y: 90),
          DrawingStrokePoint(x: 140, y: 90),
        ],
      ),
    );
    await tester.pump();
    var state = container.read(drawingStudioProviderFamily(payload));
    expect(
      state.rasterSurface!.sample(const Offset(120, 90)).toARGB32(),
      Colors.red.toARGB32(),
    );
    await tester.tap(find.byIcon(Icons.colorize_outlined));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tapAt(
      _paperToScreen(canvasRect, payload, state, const Offset(120, 90)),
    );
    await tester.pump();

    state = container.read(drawingStudioProviderFamily(payload));
    expect(state.primaryColor.toARGB32(), Colors.red.toARGB32());
    expect(state.activeTool, StudioTool.brush);
  });

  testWidgets('joins embedded Focus Studio pages without seam controls', (
    tester,
  ) async {
    final payload = _payload();
    DrawingPaperPayload? saved;
    final container = await _pumpStudio(
      tester,
      payload,
      onSave: (updated) => saved = updated,
    );
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );

    final addButtons = find.byTooltip('Add same-size paper');
    expect(addButtons, findsNWidgets(4));
    await tester.tap(addButtons.first);
    await tester.pump();

    final updatedAddButtons = find.byTooltip('Add same-size paper');
    expect(updatedAddButtons, findsNWidgets(4));
    final state = container.read(drawingStudioProviderFamily(payload));
    const workspaceCenter = Offset(240, 90);
    const workspaceAnchors = [
      Offset(496, 90),
      Offset(-16, 90),
      Offset(240, -16),
      Offset(240, 196),
    ];
    for (var i = 0; i < workspaceAnchors.length; i++) {
      final expected =
          canvasRect.center +
          (workspaceAnchors[i] - workspaceCenter) * state.viewZoom +
          state.viewPan;
      final actual = tester.getCenter(updatedAddButtons.at(i));
      expect(actual.dx, closeTo(expected.dx, 0.01));
      expect(actual.dy, closeTo(expected.dy, 0.01));
    }
    expect(state.payload.presetName, payload.presetName);
    expect(state.payload.pixelSize, payload.pixelSize);
    expect(state.payload.rasterDocumentId, isNot(payload.rasterDocumentId));

    container
        .read(drawingStudioProviderFamily(payload).notifier)
        .addStrokeToActiveLayer(
          const DrawingStroke(
            id: 'embedded-stroke',
            brush: StudioBrushCategory.gPen,
            color: Colors.red,
            size: 8,
            opacity: 1,
            points: [
              DrawingStrokePoint(x: 10, y: 10),
              DrawingStrokePoint(x: 20, y: 10),
            ],
          ),
        );
    await tester.pump();

    await tester.tap(find.text('Back to Infinite Canvas'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.studioPages, hasLength(1));
    final embedded = saved!.studioPages.single;
    expect(embedded.position, const Offset(240, 0));
    expect(embedded.payload.pixelSize, payload.pixelSize);
    expect(embedded.payload.layers.single.strokes, hasLength(1));
    expect(embedded.payload.layers.single.strokes.single.id, 'embedded-stroke');
  });

  testWidgets('focuses an embedded page and applies the first gesture', (
    tester,
  ) async {
    final rootPayload = _payload().copyWith(rasterDocumentId: 'root-page');
    final childPayload = _payload().copyWith(rasterDocumentId: 'child-page');
    final payload = rootPayload.copyWith(
      studioPages: [
        DrawingPaperPage(
          id: 'child-page',
          position: const Offset(240, 0),
          payload: childPayload,
        ),
      ],
    );
    final container = await _pumpStudio(tester, payload);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );
    final state = container.read(drawingStudioProviderFamily(payload));

    const workspaceCenter = Offset(240, 90);
    final childPoint =
        canvasRect.center +
        ((const Offset(240, 0) + const Offset(120, 90)) - workspaceCenter) *
            state.viewZoom +
        state.viewPan;
    await tester.dragFrom(childPoint, const Offset(80, 0));
    await tester.pump();

    final childState = container.read(drawingStudioProviderFamily(payload));
    expect(childState.payload.rasterDocumentId, 'child-page');
    expect(childState.payload.layers.single.strokes, hasLength(1));
  });

  testWidgets('adds from an inactive page using that page as the source', (
    tester,
  ) async {
    final payload = _payload();
    DrawingPaperPayload? saved;
    await _pumpStudio(tester, payload, onSave: (updated) => saved = updated);

    await tester.tap(find.byTooltip('Add same-size paper').first);
    await tester.pump();
    final controls = find.byTooltip('Add same-size paper');
    await tester.tap(controls.at(1));
    await tester.pump();

    await tester.tap(find.text('Back to Infinite Canvas'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.studioPages, hasLength(2));
    expect(saved!.studioPages.last.position, const Offset(-240, 0));
  });

  testWidgets('layer visibility action mutates its own row', (tester) async {
    final payload = _payload(
      layers: const [
        DrawingLayer(id: 'top', name: 'Top'),
        DrawingLayer(id: 'bottom', name: 'Bottom'),
      ],
    );
    final container = await _pumpStudio(tester, payload);

    final visibilityButtons = find.byTooltip('Hide layer');
    expect(visibilityButtons, findsNWidgets(2));
    await tester.tap(visibilityButtons.at(1));
    await tester.pump(const Duration(milliseconds: 200));

    final state = container.read(drawingStudioProviderFamily(payload));
    expect(state.payload.layers[0].visible, isTrue);
    expect(state.payload.layers[1].visible, isFalse);
  });

  testWidgets('keyboard activates the focused layer without changing others', (
    tester,
  ) async {
    final payload = _payload(
      layers: const [
        DrawingLayer(id: 'top', name: 'Top'),
        DrawingLayer(id: 'bottom', name: 'Bottom'),
      ],
    );
    await _pumpStudio(tester, payload);
    final top = find.bySemanticsLabel('Layer Top');
    final bottom = find.bySemanticsLabel('Layer Bottom');
    expect(top, findsOneWidget);
    expect(bottom, findsOneWidget);

    final semantics = tester.ensureSemantics();
    expect(tester.getSemantics(top).flagsCollection.isButton, isTrue);
    expect(
      tester.getSemantics(top).flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );
    expect(
      tester.getSemantics(bottom).flagsCollection.isSelected,
      ui.Tristate.isFalse,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DrawingStudioScreen)),
    );
    final focusNode = Focus.of(
      tester.element(find.byKey(const ValueKey('drawing-layer-row-bottom'))),
    );
    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      container.read(drawingStudioProviderFamily(payload)).activeLayerIndex,
      1,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
