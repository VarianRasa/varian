import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/domain/canvas_precision.dart';
import 'package:varian/features/canvas/domain/canvas_selection.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/canvas_selection_provider.dart';

CanvasNode node(
  String id, {
  double x = 0,
  double y = 0,
  double width = 100,
  double height = 100,
  int zIndex = 0,
  String? parentId,
  bool visible = true,
  bool locked = false,
  String? name,
}) => CanvasNode(
  id: id,
  type: NodeType.rectangle,
  x: x,
  y: y,
  width: width,
  height: height,
  zIndex: zIndex,
  parentId: parentId,
  visible: visible,
  locked: locked,
  name: name,
  payload: ShapePayload(),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('selection modes resolve direct, deep, and select-through targets', () {
    final nodes = [
      node('frame', zIndex: 1),
      node('child', zIndex: 2, parentId: 'frame'),
      node('overlay', zIndex: 3),
    ];

    expect(
      CanvasSelectionMath.pickAt(
        nodes,
        const Offset(20, 20),
        mode: CanvasSelectionMode.direct,
      )?.id,
      'overlay',
    );
    expect(
      CanvasSelectionMath.pickAt(
        nodes,
        const Offset(20, 20),
        mode: CanvasSelectionMode.deep,
      )?.id,
      'overlay',
    );
    expect(
      CanvasSelectionMath.pickAt(
        nodes,
        const Offset(20, 20),
        mode: CanvasSelectionMode.selectThrough,
        cycleIndex: 1,
      )?.id,
      'child',
    );
  });

  test('ancestor path and isolate scope are cycle-safe', () {
    final nodes = {
      for (final item in [
        node('root'),
        node('middle', parentId: 'root'),
        node('leaf', parentId: 'middle'),
      ])
        item.id: item,
    };

    expect(CanvasSelectionMath.ancestorPath('leaf', nodes), [
      'root',
      'middle',
      'leaf',
    ]);
    expect(CanvasSelectionMath.isInIsolate('leaf', 'middle', nodes), isTrue);
    expect(CanvasSelectionMath.isInIsolate('root', 'middle', nodes), isFalse);
  });

  test('safe delete expands descendants but preserves locked nodes', () {
    final nodes = [
      node('root'),
      node('child', parentId: 'root'),
      node('locked-child', parentId: 'root', locked: true),
      node('grandchild', parentId: 'child'),
    ];

    expect(CanvasSelectionMath.safeDeleteIds(['root'], nodes), {
      'root',
      'child',
      'grandchild',
    });
  });

  test('batch rename supports index, padding, and original name tokens', () {
    final names = CanvasSelectionMath.batchRename([
      node('a', name: 'Alpha'),
      node('b', name: 'Beta'),
    ], 'Card {index:02} {name}');
    expect(names, {'a': 'Card 01 Alpha', 'b': 'Card 02 Beta'});
  });

  test('selection preferences persist per project', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(
      canvasSelectionPreferencesProvider('project-a').notifier,
    );
    notifier.setMode(CanvasSelectionMode.selectThrough);
    notifier.setIsolateNode('frame');
    notifier.setShowHidden(true);
    await Future<void>.delayed(Duration.zero);

    final restored = CanvasSelectionPreferencesNotifier('project-a');
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state.mode, CanvasSelectionMode.selectThrough);
    expect(restored.state.isolateNodeId, 'frame');
    expect(restored.state.showHidden, isTrue);
  });

  test('canvas node layer color survives JSON round trip', () {
    final original = node('colored').copyWith(layerColor: 0xFF60A5FA);
    final restored = CanvasNode.fromJson(original.toJson());
    expect(restored.layerColor, 0xFF60A5FA);
  });

  test('precision layout preset names remain serializable', () {
    for (final preset in CanvasLayoutPreset.values) {
      final state = const CanvasPrecisionState().copyWith(layoutPreset: preset);
      expect(
        CanvasPrecisionState.fromJson(state.toJson()).layoutPreset,
        preset,
      );
    }
  });

  test('bulk lock and visibility changes use one undoable command', () {
    final nodes = [node('a'), node('b')];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(documentNodesProvider.notifier);
    notifier.setNodes(nodes);
    final before = container.read(historyProvider).undoStack.length;

    notifier.toggleLock(['a', 'b']);
    notifier.toggleVisibility(['a', 'b']);

    expect(container.read(historyProvider).undoStack.length, before + 2);
    expect(
      container.read(documentNodesProvider).every((item) => item.locked),
      isTrue,
    );
    expect(
      container.read(documentNodesProvider).every((item) => !item.visible),
      isTrue,
    );

    notifier.undo();
    expect(
      container.read(documentNodesProvider).every((item) => item.visible),
      isTrue,
    );
    notifier.undo();
    expect(
      container.read(documentNodesProvider).every((item) => !item.locked),
      isTrue,
    );
  });
}
