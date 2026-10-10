import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/domain/vector_path_editing.dart';
import 'package:varian/domain/models/vector_path_payload.dart';

VectorPathPayload _rectanglePayload({double left = 0, double top = 0}) {
  return VectorPathPayload(
    points: [
      BezierPoint(point: Offset(left, top), type: PointType.corner),
      BezierPoint(point: Offset(left + 100, top), type: PointType.corner),
      BezierPoint(point: Offset(left + 100, top + 100), type: PointType.corner),
      BezierPoint(point: Offset(left, top + 100), type: PointType.corner),
    ],
  );
}

CanvasNode _vectorNode(String id, VectorPathPayload payload) {
  return CanvasNode(
    id: id,
    type: NodeType.vectorPath,
    x: 0,
    y: 0,
    width: 100,
    height: 100,
    payload: payload,
  );
}

void main() {
  group('Command History & Undo/Redo Tests', () {
    test('Add node, move node, undo and redo cycle', () {
      final container = ProviderContainer();
      final notifier = container.read(documentNodesProvider.notifier);

      final node = CanvasNode(
        id: 'node_test_1',
        type: NodeType.rectangle,
        x: 50,
        y: 50,
        width: 100,
        height: 100,
        payload: ShapePayload(),
      );

      notifier.addNode(node);
      expect(container.read(documentNodesProvider).length, 1);

      notifier.moveNodes(['node_test_1'], 20, 30);
      expect(container.read(documentNodesProvider).first.x, 70);
      expect(container.read(documentNodesProvider).first.y, 80);

      // Undo Move
      notifier.undo();
      expect(container.read(documentNodesProvider).first.x, 50);
      expect(container.read(documentNodesProvider).first.y, 50);

      // Undo Add
      notifier.undo();
      expect(container.read(documentNodesProvider).isEmpty, true);

      // Redo Add
      notifier.redo();
      expect(container.read(documentNodesProvider).length, 1);

      // Redo Move
      notifier.redo();
      expect(container.read(documentNodesProvider).first.x, 70);
      expect(container.read(documentNodesProvider).first.y, 80);
    });

    test('rotating a frame rotates all descendants around its center', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);
      final frame = CanvasNode(
        id: 'frame',
        type: NodeType.frame,
        x: 100,
        y: 100,
        width: 300,
        height: 200,
        payload: FramePayload(),
      );
      final child = CanvasNode(
        id: 'child',
        type: NodeType.rectangle,
        x: 140,
        y: 130,
        width: 40,
        height: 20,
        parentId: frame.id,
        payload: ShapePayload(),
      );
      final nestedFrame = CanvasNode(
        id: 'nested-frame',
        type: NodeType.frame,
        x: 180,
        y: 160,
        width: 80,
        height: 60,
        parentId: frame.id,
        payload: FramePayload(),
      );
      final nestedChild = CanvasNode(
        id: 'nested-child',
        type: NodeType.rectangle,
        x: 190,
        y: 170,
        width: 20,
        height: 10,
        parentId: nestedFrame.id,
        payload: ShapePayload(),
      );

      notifier.setNodes([frame, child, nestedFrame, nestedChild]);
      notifier.updateNode(frame.copyWith(rotation: math.pi / 2));

      final updated = {
        for (final node in container.read(documentNodesProvider)) node.id: node,
      };
      expect(updated['frame']!.rotation, closeTo(math.pi / 2, 0.0001));
      expect(updated['child']!.x, closeTo(290, 0.0001));
      expect(updated['child']!.y, closeTo(100, 0.0001));
      expect(updated['child']!.rotation, closeTo(math.pi / 2, 0.0001));
      expect(updated['nested-frame']!.x, closeTo(220, 0.0001));
      expect(updated['nested-frame']!.y, closeTo(140, 0.0001));
      expect(updated['nested-frame']!.rotation, closeTo(math.pi / 2, 0.0001));
      expect(updated['nested-child']!.x, closeTo(265, 0.0001));
      expect(updated['nested-child']!.y, closeTo(145, 0.0001));
      expect(updated['nested-child']!.rotation, closeTo(math.pi / 2, 0.0001));

      notifier.undo();
      expect(
        container
            .read(documentNodesProvider)
            .firstWhere((node) => node.id == child.id)
            .x,
        140,
      );
      notifier.redo();
      expect(
        container
            .read(documentNodesProvider)
            .firstWhere((node) => node.id == nestedChild.id)
            .rotation,
        closeTo(math.pi / 2, 0.0001),
      );
    });

    test(
      'deleting nodes removes connected edges and restores them with history',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final nodes = container.read(documentNodesProvider.notifier);
        final edges = container.read(documentEdgesProvider.notifier);

        final source = CanvasNode(
          id: 'source',
          type: NodeType.rectangle,
          x: 0,
          y: 0,
          width: 100,
          height: 80,
          payload: ShapePayload(),
        );
        final target = CanvasNode(
          id: 'target',
          type: NodeType.rectangle,
          x: 180,
          y: 0,
          width: 100,
          height: 80,
          payload: ShapePayload(),
        );
        final edge = CanvasEdge(
          id: 'edge',
          sourceNodeId: source.id,
          targetNodeId: target.id,
        );

        nodes.setNodes([source, target]);
        edges.setEdges([edge]);
        nodes.deleteNodes([source.id]);

        expect(container.read(documentNodesProvider), [target]);
        expect(container.read(documentEdgesProvider), isEmpty);

        nodes.undo();
        expect(container.read(documentNodesProvider), [target, source]);
        expect(container.read(documentEdgesProvider), [edge]);

        nodes.redo();
        expect(container.read(documentNodesProvider), [target]);
        expect(container.read(documentEdgesProvider), isEmpty);

        nodes.undo();
        nodes.deleteEdges([edge.id]);
        expect(container.read(documentEdgesProvider), isEmpty);
        nodes.undo();
        expect(container.read(documentEdgesProvider), [edge]);
        nodes.redo();
        expect(container.read(documentEdgesProvider), isEmpty);
      },
    );

    test('chart payload survives edits, undo/redo, and duplication', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);
      final chart = CanvasNode(
        id: 'chart-history',
        type: NodeType.chart,
        x: 10,
        y: 20,
        width: 320,
        height: 220,
        payload: ChartPayload(
          title: 'Pipeline',
          chartType: ChartType.bar,
          categories: const ['A', 'B'],
          series: [
            ChartSeries(name: 'Count', values: const [2, 4]),
          ],
        ),
      );

      notifier.setNodes([chart]);
      final updated = chart.copyWith(
        payload: (chart.payload as ChartPayload).copyWith(
          title: 'Updated pipeline',
          series: [
            ChartSeries(name: 'Count', values: const [3, 5]),
          ],
        ),
      );
      notifier.updateNode(updated);

      expect(
        (container.read(documentNodesProvider).single.payload as ChartPayload)
            .title,
        'Updated pipeline',
      );
      notifier.undo();
      expect(
        (container.read(documentNodesProvider).single.payload as ChartPayload)
            .title,
        'Pipeline',
      );
      notifier.redo();
      expect(
        (container.read(documentNodesProvider).single.payload as ChartPayload)
            .series
            .single
            .values,
        [3, 5],
      );

      final duplicateId = notifier.duplicateNodes([chart.id]).single;
      final duplicate = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == duplicateId);
      final originalPayload =
          container
                  .read(documentNodesProvider)
                  .firstWhere((node) => node.id == chart.id)
                  .payload
              as ChartPayload;
      final duplicatePayload = duplicate.payload as ChartPayload;
      expect(duplicate.type, NodeType.chart);
      expect(duplicatePayload.title, 'Updated pipeline');
      expect(
        identical(duplicatePayload.series, originalPayload.series),
        isFalse,
      );
      expect(duplicatePayload.series.single.values, [3, 5]);
    });

    test(
      'vector split is one undoable edit and restores the original path',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(documentNodesProvider.notifier);
        final original = _vectorNode('vector-split', _rectanglePayload());

        notifier.setNodes([original]);
        final payload = original.payload as VectorPathPayload;
        final contour = payload.allSubpaths.single;
        final split = VectorPathEditing.splitSubpath(payload, pointIndex: 2);
        final contours = [split.first.points, split.second.points];
        notifier.updateNode(
          original.copyWith(
            payload: payload.copyWith(
              points: contours.expand((path) => path).toList(),
              isClosed: false,
              subpaths: contours,
              subpathClosed: const [false, false],
            ),
          ),
        );

        final edited = container.read(documentNodesProvider).single;
        expect((edited.payload as VectorPathPayload).subpaths, hasLength(2));
        expect((edited.payload as VectorPathPayload).points, hasLength(5));
        expect(container.read(historyProvider).undoStack, hasLength(1));

        notifier.undo();
        expect(container.read(documentNodesProvider), [original]);
        expect(
          (container.read(documentNodesProvider).single.payload
                  as VectorPathPayload)
              .allSubpaths
              .single,
          contour,
        );

        notifier.redo();
        expect(
          (container.read(documentNodesProvider).single.payload
                  as VectorPathPayload)
              .subpaths,
          hasLength(2),
        );
      },
    );

    test('vector join is one undoable edit and restores separate contours', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);
      final first = _rectanglePayload();
      final source = _vectorNode(
        'vector-join',
        VectorPathPayload(
          subpaths: [first.points.sublist(0, 3), first.points.sublist(2)],
          subpathClosed: const [false, false],
          isClosed: false,
        ),
      );

      notifier.setNodes([source]);
      notifier.updateNode(
        source.copyWith(
          payload: VectorPathEditing.joinSubpaths(
            source.payload as VectorPathPayload,
            firstSubpathIndex: 0,
            secondSubpathIndex: 1,
            closeResult: true,
          ),
        ),
      );

      final joined = container.read(documentNodesProvider).single;
      expect((joined.payload as VectorPathPayload).subpaths, hasLength(1));
      expect((joined.payload as VectorPathPayload).isClosed, isTrue);
      expect(container.read(historyProvider).undoStack, hasLength(1));

      notifier.undo();
      expect(container.read(documentNodesProvider), [source]);
      expect(
        (container.read(documentNodesProvider).single.payload
                as VectorPathPayload)
            .subpaths,
        hasLength(2),
      );

      notifier.redo();
      expect(
        (container.read(documentNodesProvider).single.payload
                as VectorPathPayload)
            .subpaths,
        hasLength(1),
      );
    });

    test('vector boolean replace and delete undo as one transaction', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);
      final first = _vectorNode('vector-boolean-first', _rectanglePayload());
      final second = _vectorNode(
        'vector-boolean-second',
        _rectanglePayload(),
      ).copyWith(x: 50, y: 50);

      notifier.setNodes([first, second]);
      final firstPayload = first.payload as VectorPathPayload;
      final secondPayload = second.payload as VectorPathPayload;
      final translated = VectorPathEditing.translate(
        secondPayload,
        Offset(second.x - first.x, second.y - first.y),
      );
      final combined = VectorPathEditing.booleanCombine(
        firstPayload,
        translated,
        VectorBooleanOperation.union,
        sampleSpacing: 5,
      );
      final bounds = combined.toPath().getBounds();
      final normalized = VectorPathEditing.translate(combined, -bounds.topLeft);

      notifier.beginTransaction(name: 'Boolean vector path');
      notifier.updateNode(
        first.copyWith(
          x: first.x + bounds.left,
          y: first.y + bounds.top,
          width: bounds.width,
          height: bounds.height,
          payload: normalized,
        ),
      );
      notifier.deleteNodes([second.id]);
      notifier.commitTransaction();

      expect(container.read(documentNodesProvider), hasLength(1));
      expect(container.read(documentNodesProvider).single.id, first.id);
      expect(container.read(historyProvider).undoStack, hasLength(1));

      notifier.undo();
      expect(container.read(documentNodesProvider), [first, second]);

      notifier.redo();
      expect(container.read(documentNodesProvider), hasLength(1));
      expect(container.read(documentNodesProvider).single.id, first.id);
      expect(
        (container.read(documentNodesProvider).single.payload
                as VectorPathPayload)
            .isClosed,
        isTrue,
      );
    });
  });
}
