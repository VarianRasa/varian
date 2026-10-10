import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/domain/canvas_precision.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/utils/auto_layout_engine.dart';

CanvasNode frameNode(
  String id, {
  double x = 0,
  double y = 0,
  double width = 400,
  double height = 240,
  FramePayload? payload,
  String? parentId,
}) => CanvasNode(
  id: id,
  type: NodeType.frame,
  x: x,
  y: y,
  width: width,
  height: height,
  parentId: parentId,
  payload: payload ?? FramePayload(),
);

CanvasNode rectangleNode(
  String id, {
  double x = 0,
  double y = 0,
  double width = 80,
  double height = 40,
  String? parentId,
}) => CanvasNode(
  id: id,
  type: NodeType.rectangle,
  x: x,
  y: y,
  width: width,
  height: height,
  parentId: parentId,
  payload: ShapePayload(),
);

void main() {
  test('spacing presets expose stable editor values', () {
    expect(CanvasSpacingPreset.none.value, 0);
    expect(CanvasSpacingPreset.tight.value, 8);
    expect(CanvasSpacingPreset.compact.value, 12);
    expect(CanvasSpacingPreset.regular.value, 16);
    expect(CanvasSpacingPreset.relaxed.value, 24);
    expect(CanvasSpacingPreset.relaxed.label, 'Relaxed');
  });

  test('presets place children deterministically', () {
    final frame = frameNode(
      'frame',
      payload: FramePayload(paddingLeft: 10, paddingTop: 20),
    );
    final children = [
      rectangleNode('a', parentId: frame.id),
      rectangleNode('b', parentId: frame.id),
      rectangleNode('c', parentId: frame.id),
    ];

    final horizontal = AutoLayoutEngine.applyPreset(
      frameNode: frame,
      children: children,
      preset: CanvasLayoutPreset.horizontal,
    );
    expect(
      horizontal.framePayload.layoutDirection,
      AutoLayoutDirection.horizontal,
    );
    expect(horizontal.children.map((node) => node.x), [10, 106, 202]);
    expect(horizontal.children.every((node) => node.y == 20), isTrue);

    final vertical = AutoLayoutEngine.applyPreset(
      frameNode: frame,
      children: children,
      preset: CanvasLayoutPreset.vertical,
    );
    expect(vertical.framePayload.layoutDirection, AutoLayoutDirection.vertical);
    expect(vertical.children.map((node) => node.y), [20, 76, 132]);

    final grid = AutoLayoutEngine.applyPreset(
      frameNode: frame,
      children: children,
      preset: CanvasLayoutPreset.grid,
    );
    expect(grid.framePayload.layoutDirection, AutoLayoutDirection.none);
    expect(grid.children.map((node) => node.id), ['a', 'b', 'c']);
    expect(grid.children.every((node) => node.x >= 10 && node.y >= 20), isTrue);
  });

  test('nested layout reflow is one undoable command', () {
    final outer = frameNode(
      'outer',
      width: 500,
      height: 300,
      payload: FramePayload(
        layoutDirection: AutoLayoutDirection.horizontal,
        itemSpacing: 20,
        paddingLeft: 10,
        paddingTop: 10,
      ),
    );
    final inner = frameNode(
      'inner',
      x: 300,
      y: 160,
      width: 180,
      height: 150,
      parentId: outer.id,
      payload: FramePayload(
        layoutDirection: AutoLayoutDirection.vertical,
        itemSpacing: 8,
        paddingLeft: 6,
        paddingTop: 7,
      ),
    );
    final first = rectangleNode('first', x: 20, y: 100, parentId: inner.id);
    final second = rectangleNode('second', x: 30, y: 200, parentId: inner.id);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final nodes = container.read(documentNodesProvider.notifier);
    nodes.setNodes([outer, inner, first, second]);
    final historyBefore = container.read(historyProvider).undoStack.length;
    nodes.updateFrameLayout(
      outer.id,
      (outer.payload as FramePayload).copyWith(itemSpacing: 30),
    );

    final updated = container.read(documentNodesProvider);
    final updatedInner = updated.firstWhere((node) => node.id == inner.id);
    final updatedFirst = updated.firstWhere((node) => node.id == first.id);
    final updatedSecond = updated.firstWhere((node) => node.id == second.id);
    expect(updatedInner.x, 10);
    expect(updatedInner.y, 10);
    expect(updatedFirst.x, 16);
    expect(updatedFirst.y, 17);
    expect(updatedSecond.x, 16);
    expect(updatedSecond.y, 65);
    expect(container.read(historyProvider).undoStack.length, historyBefore + 1);

    nodes.undo();
    final restored = container.read(documentNodesProvider);
    expect(restored.firstWhere((node) => node.id == inner.id).x, inner.x);
    expect(restored.firstWhere((node) => node.id == first.id).y, first.y);
    expect(restored.firstWhere((node) => node.id == second.id).y, second.y);
  });
}
