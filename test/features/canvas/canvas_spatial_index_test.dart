import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/utils/canvas_spatial_index.dart';

void main() {
  test('queries intersecting nodes across negative and positive cells', () {
    final nodes = [
      CanvasNode(
        id: 'left',
        type: NodeType.rectangle,
        x: -700,
        y: -100,
        width: 120,
        height: 80,
        payload: ShapePayload(),
      ),
      CanvasNode(
        id: 'center',
        type: NodeType.rectangle,
        x: 80,
        y: 80,
        width: 120,
        height: 80,
        payload: ShapePayload(),
      ),
      CanvasNode(
        id: 'far',
        type: NodeType.rectangle,
        x: 2400,
        y: 2400,
        width: 120,
        height: 80,
        payload: ShapePayload(),
      ),
    ];
    final index = CanvasSpatialIndex.build(nodes, cellSize: 256);

    expect(
      index.query(const Rect.fromLTWH(-800, -200, 300, 300)).map((n) => n.id),
      contains('left'),
    );
    expect(
      index.query(const Rect.fromLTWH(0, 0, 400, 400)).map((n) => n.id),
      contains('center'),
    );
    expect(
      index.query(const Rect.fromLTWH(0, 0, 400, 400)).map((n) => n.id),
      isNot(contains('far')),
    );
  });

  test('keeps very large nodes queryable without filling every cell', () {
    final node = CanvasNode(
      id: 'large',
      type: NodeType.frame,
      x: -5000,
      y: -5000,
      width: 10000,
      height: 10000,
      payload: FramePayload(),
    );
    final index = CanvasSpatialIndex.build([node], cellSize: 100);

    expect(index.query(const Rect.fromLTWH(4200, 4200, 100, 100)), [node]);
  });
}
