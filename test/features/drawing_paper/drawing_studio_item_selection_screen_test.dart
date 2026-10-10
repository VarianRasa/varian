import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/presentation/studio/drawing_studio_screen.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

import '../../test_app.dart';

DrawingPaperPayload _selectionPayload() => DrawingPaperPayload(
  presetName: 'Selection Test',
  pixelWidth: 240,
  pixelHeight: 180,
  layers: const [
    DrawingLayer(
      id: 'layer-1',
      name: 'Layer',
      shapes: [
        VectorShapeObject(
          id: 'shape-1',
          kind: ShapeKind.rectangle,
          points: [Offset(30, 30), Offset(70, 70)],
          strokeWidth: 2,
        ),
        VectorShapeObject(
          id: 'shape-2',
          kind: ShapeKind.rectangle,
          points: [Offset(100, 30), Offset(140, 70)],
          strokeWidth: 2,
        ),
      ],
    ),
  ],
);

Future<ProviderContainer> _pumpSelectionStudio(
  WidgetTester tester,
  DrawingPaperPayload payload,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: testApp(
        DrawingStudioScreen(initialPayload: payload, onSaveAndExit: (_) {}),
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

Offset _workspaceToScreen(
  Rect canvasRect,
  DrawingStudioState state,
  Offset workspaceCenter,
  Offset workspacePoint,
) {
  return canvasRect.center +
      (workspacePoint - workspaceCenter) * state.viewZoom +
      state.viewPan;
}

void main() {
  testWidgets('activates Select Items and moves a clicked object', (
    tester,
  ) async {
    final payload = _selectionPayload();
    final container = await _pumpSelectionStudio(tester, payload);
    final canvas = find.byKey(const ValueKey('drawing-studio-canvas'));
    final canvasRect = tester.getRect(canvas);

    await tester.tap(find.byIcon(Icons.near_me_outlined));
    await tester.pump(const Duration(milliseconds: 200));
    var state = container.read(drawingStudioProviderFamily(payload));
    expect(state.activeTool, StudioTool.itemSelection);

    final start = _paperToScreen(
      canvasRect,
      payload,
      state,
      const Offset(50, 50),
    );
    await tester.tapAt(start);
    await tester.pump();
    state = container.read(drawingStudioProviderFamily(payload));
    expect(state.selectedItems.single.objectId, 'shape-1');

    await tester.dragFrom(start, const Offset(40, 20));
    await tester.pump();
    final moved = container
        .read(drawingStudioProviderFamily(payload))
        .payload
        .layers
        .single
        .shapes
        .first;
    expect(moved.points.first, const Offset(40, 35));
    expect(moved.points.last, const Offset(80, 75));
  });

  testWidgets('shift-click and marquee select multiple objects', (
    tester,
  ) async {
    final payload = _selectionPayload();
    final container = await _pumpSelectionStudio(tester, payload);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );
    await tester.tap(find.byIcon(Icons.near_me_outlined));
    await tester.pump(const Duration(milliseconds: 200));
    var state = container.read(drawingStudioProviderFamily(payload));

    final first = _paperToScreen(
      canvasRect,
      payload,
      state,
      const Offset(50, 50),
    );
    final second = _paperToScreen(
      canvasRect,
      payload,
      state,
      const Offset(120, 50),
    );
    await tester.tapAt(first);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(second);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    state = container.read(drawingStudioProviderFamily(payload));
    expect(
      state.selectedItems.map((item) => item.objectId),
      containsAll(['shape-1', 'shape-2']),
    );

    final marqueeStart = _paperToScreen(
      canvasRect,
      payload,
      state,
      const Offset(20, 20),
    );
    final marqueeEnd = _paperToScreen(
      canvasRect,
      payload,
      state,
      const Offset(150, 80),
    );
    await tester.dragFrom(marqueeStart, marqueeEnd - marqueeStart);
    await tester.pump();
    state = container.read(drawingStudioProviderFamily(payload));
    expect(state.selectedItems, hasLength(2));
  });

  testWidgets('V and delete shortcuts control item selection', (tester) async {
    final payload = _selectionPayload();
    final container = await _pumpSelectionStudio(tester, payload);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );
    final state = container.read(drawingStudioProviderFamily(payload));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(
      container.read(drawingStudioProviderFamily(payload)).activeTool,
      StudioTool.itemSelection,
    );

    final point = _paperToScreen(
      canvasRect,
      payload,
      container.read(drawingStudioProviderFamily(payload)),
      const Offset(50, 50),
    );
    await tester.tapAt(point);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(
      container
          .read(drawingStudioProviderFamily(payload))
          .payload
          .layers
          .single
          .shapes,
      hasLength(1),
    );
    // Keep the initial state read above from becoming a fixture dependency.
    expect(state.payload.layers.single.shapes, hasLength(2));
  });

  testWidgets('resize and rotate handles transform the selected object', (
    tester,
  ) async {
    final payload = _selectionPayload();
    final container = await _pumpSelectionStudio(tester, payload);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );
    await tester.tap(find.byIcon(Icons.near_me_outlined));
    await tester.pump(const Duration(milliseconds: 200));
    var state = container.read(drawingStudioProviderFamily(payload));

    final objectPoint = _paperToScreen(
      canvasRect,
      payload,
      state,
      const Offset(50, 50),
    );
    await tester.tapAt(objectPoint);
    await tester.pump();
    state = container.read(drawingStudioProviderFamily(payload));

    final bottomRightHandle = _paperToScreen(
      canvasRect,
      payload,
      state,
      const Offset(70, 70),
    );
    await tester.dragFrom(bottomRightHandle, const Offset(40, 20));
    await tester.pump();
    var shape = container
        .read(drawingStudioProviderFamily(payload))
        .payload
        .layers
        .single
        .shapes
        .first;
    expect(shape.points.last.dx, greaterThan(70));
    expect(shape.points.last.dy, greaterThan(70));

    state = container.read(drawingStudioProviderFamily(payload));
    final selectedBounds = container
        .read(drawingStudioProviderFamily(payload).notifier)
        .selectedItemsBounds!;
    final rotationHandle = _paperToScreen(
      canvasRect,
      payload,
      state,
      Offset(
        selectedBounds.center.dx,
        selectedBounds.top - 28 / state.viewZoom,
      ),
    );
    await tester.dragFrom(rotationHandle, const Offset(80, 40));
    await tester.pump();
    shape = container
        .read(drawingStudioProviderFamily(payload))
        .payload
        .layers
        .single
        .shapes
        .first;
    expect(shape.rotation, isNot(0.0));
  });

  testWidgets('keyboard clipboard commands duplicate, undo, and paste items', (
    tester,
  ) async {
    final payload = _selectionPayload();
    final container = await _pumpSelectionStudio(tester, payload);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();
    final point = _paperToScreen(
      canvasRect,
      payload,
      container.read(drawingStudioProviderFamily(payload)),
      const Offset(50, 50),
    );
    await tester.tapAt(point);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      container.read(drawingStudioProviderFamily(payload)).itemClipboard,
      isNotEmpty,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      container
          .read(drawingStudioProviderFamily(payload))
          .payload
          .layers
          .single
          .shapes,
      hasLength(3),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      container
          .read(drawingStudioProviderFamily(payload))
          .payload
          .layers
          .single
          .shapes,
      hasLength(2),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      container
          .read(drawingStudioProviderFamily(payload))
          .payload
          .layers
          .single
          .shapes,
      hasLength(3),
    );
  });

  testWidgets('switching pages clears selection and keeps page-local content', (
    tester,
  ) async {
    final pagePayload = _selectionPayload().copyWith(
      presetName: 'Second Page',
      studioPages: const [],
    );
    final payload = _selectionPayload().copyWith(
      studioPages: [
        DrawingPaperPage(
          id: 'page-2',
          position: const Offset(260, 0),
          payload: pagePayload,
        ),
      ],
    );
    final container = await _pumpSelectionStudio(tester, payload);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('drawing-studio-canvas')),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();
    final rootState = container.read(drawingStudioProviderFamily(payload));
    final rootPoint = _workspaceToScreen(
      canvasRect,
      rootState,
      const Offset(250, 90),
      const Offset(50, 50),
    );
    await tester.tapAt(rootPoint);
    await tester.pump();
    expect(
      container.read(drawingStudioProviderFamily(payload)).selectedItems,
      isNotEmpty,
    );

    final switchedState = container.read(drawingStudioProviderFamily(payload));
    await tester.tapAt(
      _workspaceToScreen(
        canvasRect,
        switchedState,
        const Offset(250, 90),
        const Offset(270, 10),
      ),
    );
    await tester.pump();
    final pageState = container.read(drawingStudioProviderFamily(payload));
    expect(pageState.selectedItems, isEmpty);
    expect(pageState.payload.presetName, 'Second Page');
    expect(pageState.payload.layers.single.shapes, hasLength(2));
  });
}
