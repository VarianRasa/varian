import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/features/canvas/domain/vector_path_editing.dart';

VectorPathPayload rectangle({
  double left = 0,
  double top = 0,
  double size = 100,
}) {
  return VectorPathPayload(
    points: [
      BezierPoint(point: Offset(left, top), type: PointType.corner),
      BezierPoint(point: Offset(left + size, top), type: PointType.corner),
      BezierPoint(
        point: Offset(left + size, top + size),
        type: PointType.corner,
      ),
      BezierPoint(point: Offset(left, top + size), type: PointType.corner),
    ],
  );
}

void main() {
  test('inserts a cubic anchor while preserving segment endpoints', () {
    final source = VectorPathPayload(
      points: [
        const BezierPoint(point: Offset(0, 0), handleOut: Offset(40, 0)),
        const BezierPoint(point: Offset(100, 100), handleIn: Offset(-40, 0)),
      ],
      isClosed: false,
    );

    final edited = VectorPathEditing.insertAnchor(
      source,
      segmentIndex: 0,
      t: 0.5,
    );

    expect(edited.points, hasLength(3));
    expect(edited.points.first.point, const Offset(0, 0));
    expect(edited.points.last.point, const Offset(100, 100));
    expect(edited.points[1].point.dx, closeTo(50, 0.001));
  });

  test('removes an anchor and refuses to destroy the minimum path', () {
    final source = rectangle();
    final edited = VectorPathEditing.removeAnchor(source, pointIndex: 1);

    expect(edited.points, hasLength(3));
    expect(
      () => VectorPathEditing.removeAnchor(edited, pointIndex: 0),
      throwsA(isA<StateError>()),
    );
  });

  test('splits and joins a contour without losing anchors', () {
    final source = rectangle();
    final split = VectorPathEditing.splitSubpath(source, pointIndex: 2);

    expect(split.first.points, hasLength(3));
    expect(split.second.points, hasLength(2));
    final joined = VectorPathEditing.joinSubpaths(
      VectorPathPayload(
        subpaths: [split.first.points, split.second.points],
        subpathClosed: const [false, false],
        isClosed: false,
      ),
      firstSubpathIndex: 0,
      secondSubpathIndex: 1,
      closeResult: true,
    );

    expect(joined.points, hasLength(4));
    expect(joined.isClosed, isTrue);
  });

  test('boolean intersection returns a serializable closed contour', () {
    final result = VectorPathEditing.booleanCombine(
      rectangle(size: 100),
      rectangle(left: 50, top: 50, size: 100),
      VectorBooleanOperation.intersect,
      sampleSpacing: 5,
    );
    final bounds = result.toPath().getBounds();

    expect(result.isClosed, isTrue);
    expect(result.subpaths, isNotEmpty);
    expect(bounds.left, closeTo(50, 1.5));
    expect(bounds.top, closeTo(50, 1.5));
    expect(bounds.width, closeTo(50, 2.0));
    expect(bounds.height, closeTo(50, 2.0));
    expect(VectorPathPayload.fromJson(result.toJson()).subpaths, isNotEmpty);
  });

  test(
    'appearance edits preserve an existing mask unless explicitly cleared',
    () {
      final source = rectangle().copyWith(
        maskNodeId: 'mask-node',
        maskMode: VectorMaskMode.luminance,
      );

      final recolored = VectorPathEditing.setAppearance(
        source,
        fill: const Color(0xFF22C55E),
      );
      expect(recolored.maskNodeId, 'mask-node');
      expect(recolored.maskMode, VectorMaskMode.luminance);

      final cleared = VectorPathEditing.setAppearance(source, maskNodeId: null);
      expect(cleared.maskNodeId, isNull);
    },
  );

  test('appearance effects survive document serialization', () {
    final source = rectangle().copyWith(
      effects: const [
        VectorEffect(
          type: VectorEffectType.outline,
          color: Color(0xFF0EA5E9),
          spread: 3,
        ),
      ],
    );

    final restored = VectorPathPayload.fromJson(source.toJson());

    expect(restored.effects, hasLength(1));
    expect(restored.effects.single.type, VectorEffectType.outline);
    expect(restored.effects.single.color, const Color(0xFF0EA5E9));
    expect(restored.effects.single.spread, 3);
  });
}
