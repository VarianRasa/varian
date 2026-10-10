import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/commands/editor_commands.dart';
import 'package:varian/features/canvas/utils/hit_tester.dart';
import 'package:varian/features/canvas/utils/transform_engine.dart';

CanvasNode _node(String id, double x, double y) => CanvasNode(
  id: id,
  type: NodeType.rectangle,
  x: x,
  y: y,
  width: 50,
  height: 50,
  payload: ShapePayload(),
);

void main() {
  test('resize supports aspect lock and preserves the opposite corner', () {
    final resized = CanvasTransformEngine.resizeRect(
      original: const Rect.fromLTWH(10, 20, 100, 50),
      handle: ResizeHandle.topLeft,
      delta: const Offset(20, 10),
      lockAspect: true,
    );

    expect(resized, const Rect.fromLTWH(30, 30, 80, 40));
  });

  test('center resize keeps the original center fixed', () {
    final resized = CanvasTransformEngine.resizeRect(
      original: const Rect.fromLTWH(10, 20, 100, 50),
      handle: ResizeHandle.bottomRight,
      delta: const Offset(20, 10),
      fromCenter: true,
    );

    expect(resized, const Rect.fromLTWH(0, 15, 120, 60));
    expect(resized.center, const Offset(60, 45));
  });

  test('rotates a selection around its shared center', () {
    final rotated = CanvasTransformEngine.rotateSelection([
      _node('a', 0, 25),
      _node('b', 100, 25),
    ], math.pi / 2);

    expect(rotated[0].x, closeTo(50, 0.0001));
    expect(rotated[0].y, closeTo(-25, 0.0001));
    expect(rotated[1].x, closeTo(50, 0.0001));
    expect(rotated[1].y, closeTo(75, 0.0001));
    for (final node in rotated) {
      expect(node.rotation, closeTo(math.pi / 2, 0.0001));
    }
  });

  test('rotation handle follows the node rotation', () {
    final node = _node('rotated', 100, 100);
    final handle = CanvasSelectionGeometry.rotationHandlePosition(
      node.copyWith(rotation: math.pi / 2),
      zoom: 1.0,
    );

    expect(handle.dx, closeTo(174, 0.0001));
    expect(handle.dy, closeTo(125, 0.0001));
  });

  test(
    'replace command restores exact node snapshots through undo and redo',
    () {
      final before = _node('a', 0, 0);
      final after = before.copyWith(x: 10, rotation: math.pi / 2);
      final command = ReplaceNodesCommand(
        label: 'Rotate selection',
        beforeNodes: [before],
        afterNodes: [after],
      );

      expect(command.execute([before]).single.x, 10);
      expect(command.undo([after]).single.x, 0);
      expect(command.name, 'Rotate selection');
    },
  );
}
