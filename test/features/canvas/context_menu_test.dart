import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/canvas_screen.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';
import 'package:varian/features/media/map_location_preview.dart';
import '../../test_app.dart';

void main() {
  group('Context Menu Actions & Node Operations Tests', () {
    test(
      'Duplicate, lock, visibility, and z-index reordering work accurately in provider',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final node1 = CanvasNode(
          id: 'node_1',
          type: NodeType.rectangle,
          x: 10,
          y: 10,
          width: 100,
          height: 100,
          zIndex: 0,
          payload: ShapePayload(),
        );

        final node2 = CanvasNode(
          id: 'node_2',
          type: NodeType.text,
          x: 50,
          y: 50,
          width: 120,
          height: 40,
          zIndex: 1,
          payload: TextPayload(text: 'Initial Text'),
        );

        container.read(selectionProvider.notifier).select('stale-node');
        container.read(documentNodesProvider.notifier).setNodes([node1, node2]);
        expect(container.read(selectionProvider), isEmpty);

        // Test Duplicate
        final newIds = container
            .read(documentNodesProvider.notifier)
            .duplicateNodes(['node_1']);
        expect(newIds.length, 1);
        final currentNodes = container.read(documentNodesProvider);
        expect(currentNodes.length, 3);
        final duplicatedNode = currentNodes.firstWhere(
          (n) => n.id == newIds.first,
        );
        expect(duplicatedNode.x, 30.0);
        expect(duplicatedNode.y, 30.0);

        // Test Toggle Lock
        container.read(documentNodesProvider.notifier).toggleLock(['node_1']);
        expect(
          container
              .read(documentNodesProvider)
              .firstWhere((n) => n.id == 'node_1')
              .locked,
          isTrue,
        );

        // Test Toggle Visibility
        container.read(documentNodesProvider.notifier).toggleVisibility([
          'node_1',
        ]);
        expect(
          container
              .read(documentNodesProvider)
              .firstWhere((n) => n.id == 'node_1')
              .visible,
          isFalse,
        );

        // Test Send to Back / Bring to Front
        container.read(documentNodesProvider.notifier).bringToFront('node_1');
        expect(container.read(documentNodesProvider).last.id, 'node_1');
      },
    );

    testWidgets('keeps the context menu mounted while its popover hides', (
      tester,
    ) async {
      await tester.pumpWidget(testApp(const Scaffold(body: SizedBox.expand())));
      await tester.pump();

      final context = tester.element(find.byType(Scaffold));
      final menuFuture = showUiContextMenu<String>(
        context: context,
        position: const Offset(40, 40),
        semanticsLabel: 'Canvas context menu',
        items: [
          const UiMenuAction<String>(
            value: 'duplicate',
            label: 'Duplicate',
            icon: Icons.copy,
          ),
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('Duplicate'), findsOneWidget);
      await tester.tap(find.text('Duplicate'));
      await tester.pump();

      expect(find.text('Duplicate'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Duplicate'), findsNothing);
      expect(await menuFuture, 'duplicate');

      final dismissedMenuFuture = showUiContextMenu<String>(
        context: context,
        position: const Offset(40, 40),
        semanticsLabel: 'Canvas context menu',
        items: [
          const UiMenuAction<String>(
            value: 'duplicate',
            label: 'Duplicate',
            icon: Icons.copy,
          ),
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(300, 300));
      await tester.pump();
      expect(find.text('Duplicate'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Duplicate'), findsNothing);
      expect(await dismissedMenuFuture, isNull);
    });

    test('z-order actions use visual order when state list is unsorted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final back = CanvasNode(
        id: 'back',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        zIndex: 0,
        payload: ShapePayload(),
      );
      final middle = CanvasNode(
        id: 'middle',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        zIndex: 1,
        payload: ShapePayload(),
      );
      final front = CanvasNode(
        id: 'front',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        zIndex: 2,
        payload: ShapePayload(),
      );

      // The persisted list order can differ from the visual z-order.
      container.read(documentNodesProvider.notifier).setNodes([
        front,
        back,
        middle,
      ]);

      List<String> visualOrder() {
        final ordered = container.read(documentNodesProvider).toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
        return ordered.map((node) => node.id).toList();
      }

      expect(visualOrder(), ['back', 'middle', 'front']);

      container.read(documentNodesProvider.notifier).sendBackward('front');
      expect(visualOrder(), ['back', 'front', 'middle']);

      container.read(documentNodesProvider.notifier).bringForward('front');
      expect(visualOrder(), ['back', 'middle', 'front']);

      container.read(documentNodesProvider.notifier).sendToBack('front');
      expect(visualOrder(), ['front', 'back', 'middle']);

      container.read(documentNodesProvider.notifier).bringToFront('front');
      expect(visualOrder(), ['back', 'middle', 'front']);
    });

    testWidgets('renders live nodes in the same z-order as the canvas', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            const CanvasScreen(
              projectId: 'z-order-render-test',
              readOnly: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CanvasScreen)),
      );
      final shape = CanvasNode(
        id: 'shape-front',
        type: NodeType.rectangle,
        x: 80,
        y: 80,
        width: 220,
        height: 160,
        zIndex: 1,
        payload: ShapePayload(),
      );
      final map = CanvasNode(
        id: 'map-back',
        type: NodeType.mapCard,
        x: 120,
        y: 100,
        width: 220,
        height: 160,
        zIndex: 0,
        payload: MapPayload(locationTitle: '', address: ''),
      );
      container.read(documentNodesProvider.notifier).setNodes([shape, map]);
      await tester.pump();

      List<String> layerIds() {
        final stack = tester.widget<Stack>(
          find.byKey(const ValueKey('canvas-render-stack')),
        );
        return stack.children
            .whereType<Positioned>()
            .map((child) => child.key)
            .whereType<ValueKey<String>>()
            .where((key) => key.value.startsWith('canvas-node-layer-'))
            .map((key) => key.value)
            .toList();
      }

      expect(layerIds(), [
        'canvas-node-layer-map-back',
        'canvas-node-layer-shape-front',
      ]);
      expect(find.byType(MapLocationPreview), findsOneWidget);

      container.read(documentNodesProvider.notifier).bringToFront('map-back');
      await tester.pump();

      expect(layerIds(), [
        'canvas-node-layer-shape-front',
        'canvas-node-layer-map-back',
      ]);
    });
  });
}
