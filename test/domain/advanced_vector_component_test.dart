import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/vector_path_payload.dart';

void main() {
  group('Milestone 6: Advanced Vector & Component Engine Tests', () {
    test(
      'VectorPathPayload Bezier points serialization and advanced styling',
      () {
        final vectorNode = CanvasNode(
          id: 'vector_1',
          type: NodeType.vectorPath,
          x: 50,
          y: 50,
          width: 100,
          height: 100,
          payload: VectorPathPayload(
            points: const [
              BezierPoint(
                point: Offset(0, 0),
                handleOut: Offset(10, 20),
                type: PointType.mirrored,
              ),
              BezierPoint(
                point: Offset(50, 50),
                handleIn: Offset(-10, -20),
                type: PointType.corner,
              ),
            ],
            isClosed: false,
            strokeWidth: 4.0,
            strokeCap: VectorStrokeCap.square,
            strokeJoin: VectorStrokeJoin.miter,
            dashPattern: const [8.0, 6.0],
            isGradientFill: true,
          ),
        );

        final json = vectorNode.toJson();
        final restored = CanvasNode.fromJson(json);

        expect(restored.type, NodeType.vectorPath);
        final payload = restored.payload as VectorPathPayload;
        expect(payload.points.length, 2);
        expect(payload.points.first.handleOut, const Offset(10, 20));
        expect(payload.points.first.type, PointType.mirrored);
        expect(payload.points.last.type, PointType.corner);
        expect(payload.isClosed, false);
        expect(payload.strokeWidth, 4.0);
        expect(payload.strokeCap, VectorStrokeCap.square);
        expect(payload.strokeJoin, VectorStrokeJoin.miter);
        expect(payload.dashPattern, [8.0, 6.0]);
        expect(payload.isGradientFill, true);
      },
    );

    test('ComponentPayload master and overrides', () {
      final compNode = CanvasNode(
        id: 'comp_1',
        type: NodeType.component,
        x: 100,
        y: 100,
        width: 160,
        height: 80,
        payload: ComponentPayload(
          masterComponentId: 'master_1',
          componentName: 'Header Card',
          isMaster: true,
          overrides: {'title': 'Custom Text'},
        ),
      );

      final json = compNode.toJson();
      final restored = CanvasNode.fromJson(json);

      expect(restored.type, NodeType.component);
      final payload = restored.payload as ComponentPayload;
      expect(payload.componentName, 'Header Card');
      expect(payload.isMaster, true);
      expect(payload.overrides['title'], 'Custom Text');
    });
  });
}
