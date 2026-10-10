import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/domain/canvas_precision.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';

void main() {
  test(
    'left-right and top-bottom constraints preserve margins when a frame grows',
    () {
      final child = CanvasNode(
        id: 'child',
        type: NodeType.rectangle,
        x: 40,
        y: 30,
        width: 120,
        height: 80,
        constraints: const CanvasNodeConstraints(
          horizontal: CanvasHorizontalConstraint.leftRight,
          vertical: CanvasVerticalConstraint.topBottom,
        ),
        payload: ShapePayload(),
      );

      final resolved = CanvasConstraintEngine.resolve(
        child,
        oldParent: const Rect.fromLTWH(0, 0, 400, 300),
        newParent: const Rect.fromLTWH(0, 0, 800, 600),
      );

      expect(resolved.x, 40);
      expect(resolved.y, 30);
      expect(resolved.width, 520);
      expect(resolved.height, 380);
    },
  );

  test('scale constraints scale position and size proportionally', () {
    final child = CanvasNode(
      id: 'scaled',
      type: NodeType.rectangle,
      x: 100,
      y: 75,
      width: 200,
      height: 120,
      constraints: const CanvasNodeConstraints(
        horizontal: CanvasHorizontalConstraint.scale,
        vertical: CanvasVerticalConstraint.scale,
      ),
      payload: ShapePayload(),
    );

    final resolved = CanvasConstraintEngine.resolve(
      child,
      oldParent: const Rect.fromLTWH(0, 0, 400, 300),
      newParent: const Rect.fromLTWH(0, 0, 800, 600),
    );

    expect(resolved.x, 200);
    expect(resolved.y, 150);
    expect(resolved.width, 400);
    expect(resolved.height, 240);
  });

  test('node constraints survive document JSON round trip', () {
    final node = CanvasNode(
      id: 'persisted',
      type: NodeType.rectangle,
      x: 10,
      y: 20,
      width: 50,
      height: 40,
      constraints: const CanvasNodeConstraints(
        horizontal: CanvasHorizontalConstraint.center,
        vertical: CanvasVerticalConstraint.bottom,
      ),
      payload: ShapePayload(),
    );

    final restored = CanvasNode.fromJson(node.toJson());

    expect(restored.constraints?.horizontal, CanvasHorizontalConstraint.center);
    expect(restored.constraints?.vertical, CanvasVerticalConstraint.bottom);
  });

  test('frame resize propagates constraints and remains undoable', () {
    final frame = CanvasNode(
      id: 'frame',
      type: NodeType.frame,
      x: 0,
      y: 0,
      width: 400,
      height: 300,
      payload: FramePayload(),
    );
    final child = CanvasNode(
      id: 'child',
      type: NodeType.rectangle,
      x: 40,
      y: 30,
      width: 120,
      height: 80,
      parentId: frame.id,
      constraints: const CanvasNodeConstraints(
        horizontal: CanvasHorizontalConstraint.leftRight,
        vertical: CanvasVerticalConstraint.topBottom,
      ),
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(documentNodesProvider.notifier);
    notifier.setNodes([frame, child]);

    notifier.updateNode(frame.copyWith(width: 800, height: 600));

    final resized = container
        .read(documentNodesProvider)
        .firstWhere((node) => node.id == child.id);
    expect(resized.x, 40);
    expect(resized.y, 30);
    expect(resized.width, 520);
    expect(resized.height, 380);

    notifier.undo();
    final restored = container
        .read(documentNodesProvider)
        .firstWhere((node) => node.id == child.id);
    expect(restored.x, child.x);
    expect(restored.y, child.y);
    expect(restored.width, child.width);
    expect(restored.height, child.height);

    notifier.redo();
    final redone = container
        .read(documentNodesProvider)
        .firstWhere((node) => node.id == child.id);
    expect(redone.width, 520);
    expect(redone.height, 380);
  });
}
