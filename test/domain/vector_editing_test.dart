import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/vector_path_payload.dart';

void main() {
  test('flat editor indices update every contour without joining them', () {
    final vector = VectorPathPayload(
      subpaths: [
        [
          const BezierPoint(point: Offset.zero),
          const BezierPoint(point: Offset(10, 0)),
        ],
        [
          const BezierPoint(point: Offset(20, 20)),
          const BezierPoint(point: Offset(30, 20)),
        ],
      ],
      subpathClosed: [false, true],
    );
    expect(vector.points, hasLength(4));
    final edited = List<BezierPoint>.of(vector.points);
    edited[2] = edited[2].copyWith(point: const Offset(22, 23));
    final updated = vector.copyWith(points: edited);
    expect(updated.allSubpaths.map((path) => path.length), [2, 2]);
    expect(updated.allSubpaths.last.first.point, const Offset(22, 23));
    expect(updated.allSubpathClosed, [false, true]);
    expect(vector.allSubpaths.last.first.point, const Offset(20, 20));
    expect(
      VectorPathPayload.fromJson(updated.toJson()).toJson(),
      updated.toJson(),
    );
  });

  test(
    'rejects invalid and excessive stored geometry instead of truncating it',
    () {
      final point = const BezierPoint(point: Offset.zero).toJson();
      expect(
        () => VectorPathPayload.fromJson({
          'points': [
            {...point, 'px': double.infinity},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => VectorPathPayload.fromJson({'points': List.filled(4097, point)}),
        throwsFormatException,
      );
      expect(
        () => VectorPathPayload.fromJson({
          'subpaths': List.filled(257, [point]),
        }),
        throwsFormatException,
      );
    },
  );
}
