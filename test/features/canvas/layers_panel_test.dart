import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../test_app.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/layers_panel.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';

void main() {
  testWidgets('object actions are available from the overflow menu', (
    tester,
  ) async {
    final node = CanvasNode(
      id: 'node-1',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      name: 'A long object name',
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const Scaffold(
            body: SizedBox(width: 250, height: 240, child: LayersPanel()),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(LayersPanel)), const Size(250, 240));
    final dividers = tester.widgetList<Divider>(find.byType(Divider));
    expect(dividers, hasLength(2));
    expect(
      dividers.every((divider) => divider.height == AppBorder.thin),
      isTrue,
    );

    expect(find.byTooltip('Object actions'), findsOneWidget);
    expect(find.text('A long object name'), findsOneWidget);

    Future<void> openMenu() async {
      await tester.tap(find.byTooltip('Object actions'));
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Lock'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(container.read(documentNodesProvider).single.visible, isFalse);

    await openMenu();
    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();
    expect(container.read(documentNodesProvider).single.locked, isTrue);

    await openMenu();
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(container.read(documentNodesProvider).single.locked, isFalse);

    await openMenu();
    final deleteAction = find.text('Delete');
    for (
      var attempt = 0;
      attempt < 8 && deleteAction.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -100));
      await tester.pumpAndSettle();
    }
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();
    expect(container.read(documentNodesProvider), isEmpty);
    expect(container.read(selectionProvider), isEmpty);
  });

  testWidgets('layer row actions remain inside a compact panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final node = CanvasNode(
      id: 'compact-layer',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      name: 'Compact layer',
      payload: ShapePayload(),
    );
    final child = CanvasNode(
      id: 'compact-child',
      type: NodeType.rectangle,
      x: 4,
      y: 4,
      width: 24,
      height: 24,
      parentId: node.id,
      name: 'Nested layer',
      payload: ShapePayload(),
    );
    final secondRootNode = CanvasNode(
      id: 'compact-root-2',
      type: NodeType.rectangle,
      x: 140,
      y: 0,
      width: 24,
      height: 24,
      name: 'Second root',
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([
      node,
      child,
      secondRootNode,
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const Scaffold(
            body: SizedBox(width: 250, height: 568, child: LayersPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nested layer'), findsOneWidget);
    final secondRoot = find.text('Second root');
    expect(secondRoot, findsOneWidget);
    expect(tester.getTopLeft(secondRoot).dy, greaterThan(130));
    final collapseAction = find.byTooltip('Collapse layer');
    final collapseRect = tester.getRect(collapseAction);
    expect(
      collapseRect.width,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(
      collapseRect.height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    await tester.tapAt(Offset(collapseRect.right - 1, collapseRect.bottom - 1));
    await tester.pumpAndSettle();
    expect(find.text('Nested layer'), findsNothing);

    final focusAction = find.byTooltip('Focus on canvas').first;
    final actionRect = tester.getRect(focusAction);
    expect(
      actionRect.width,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(
      actionRect.height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(actionRect.right, lessThanOrEqualTo(250));
    expect(tester.takeException(), isNull);

    await tester.tapAt(Offset(actionRect.right - 1, actionRect.bottom - 1));
    await tester.pumpAndSettle();
    expect(container.read(selectionProvider), {'compact-layer'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('layer labels support keyboard selection and semantics', (
    tester,
  ) async {
    final nodes = [
      CanvasNode(
        id: 'node-a',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 120,
        height: 80,
        name: 'First layer',
        payload: ShapePayload(),
      ),
      CanvasNode(
        id: 'node-b',
        type: NodeType.rectangle,
        x: 140,
        y: 0,
        width: 120,
        height: 80,
        name: 'Second layer',
        payload: ShapePayload(),
      ),
    ];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes(nodes);
    container.read(selectionProvider.notifier).select('node-b');

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const Scaffold(
            body: SizedBox(width: 320, height: 300, child: LayersPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstLayer = find.byKey(const ValueKey('layer-selection-node-a'));
    final secondLayer = find.byKey(const ValueKey('layer-selection-node-b'));
    expect(
      tester.getSemantics(secondLayer).flagsCollection.isSelected ==
          ui.Tristate.isTrue,
      isTrue,
    );
    final initialSemantics = tester.getSemantics(firstLayer);
    expect(initialSemantics.flagsCollection.isButton, isTrue);
    expect(
      initialSemantics.flagsCollection.isSelected == ui.Tristate.isFalse,
      isTrue,
    );
    expect(
      Focus.of(
        tester.element(find.byType(MergeSemantics).first),
      ).hasPrimaryFocus,
      isFalse,
    );
    final firstRowFocus = Focus.of(
      tester.element(find.byType(MergeSemantics).first),
    );
    firstRowFocus.requestFocus();
    await tester.pump();
    expect(firstRowFocus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(selectionProvider), {'node-a'});
    expect(
      tester.getSemantics(firstLayer).flagsCollection.isSelected ==
          ui.Tristate.isTrue,
      isTrue,
    );
    expect(
      tester.getSemantics(secondLayer).flagsCollection.isSelected ==
          ui.Tristate.isFalse,
      isTrue,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('single-layer rename updates only the selected node', (
    tester,
  ) async {
    final node = CanvasNode(
      id: 'single-rename-node',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      name: 'Original name',
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const Scaffold(
            body: SizedBox(width: 320, height: 568, child: LayersPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Object actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Rename layer'), findsOneWidget);
    final renameField = find.byKey(const ValueKey('rename-layer-field'));
    expect(renameField, findsOneWidget);
    await tester.enterText(renameField, 'Updated name');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updatedNodes = container.read(documentNodesProvider);
    expect(updatedNodes, hasLength(1));
    expect(updatedNodes.single.id, node.id);
    expect(updatedNodes.single.name, 'Updated name');
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection actions batch rename and lock selected layers', (
    tester,
  ) async {
    final nodes = [
      CanvasNode(
        id: 'node-a',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 120,
        height: 80,
        zIndex: 1,
        payload: ShapePayload(),
      ),
      CanvasNode(
        id: 'node-b',
        type: NodeType.rectangle,
        x: 140,
        y: 0,
        width: 120,
        height: 80,
        zIndex: 0,
        payload: ShapePayload(),
      ),
    ];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes(nodes);
    container.read(selectionProvider.notifier).selectAll(['node-a', 'node-b']);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          const Scaffold(
            body: SizedBox(width: 320, height: 300, child: LayersPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selection actions'));
    await tester.pumpAndSettle();
    expect(find.text('Rename selected'), findsOneWidget);
    await tester.tap(find.text('Rename selected'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bulk-rename-pattern')),
      'Card {index:02}',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(container.read(documentNodesProvider).map((node) => node.name), [
      'Card 01',
      'Card 02',
    ]);

    await tester.tap(find.byTooltip('Selection actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock selected'));
    await tester.pumpAndSettle();
    expect(
      container.read(documentNodesProvider).every((node) => node.locked),
      isTrue,
    );
  });
}
