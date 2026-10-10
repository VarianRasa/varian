import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/domain/text_on_path.dart';

void main() {
  test('places glyphs along a path with predictable alignment', () {
    final path = Path()
      ..moveTo(0, 20)
      ..lineTo(200, 20);
    final placements = TextOnPathLayout.layout(
      text: 'AB',
      path: path,
      style: const TextStyle(fontSize: 20),
      alignment: TextPathAlignment.center,
    );

    expect(placements, hasLength(2));
    expect(placements[0].position.dy, closeTo(20, 0.01));
    expect(placements[1].position.dy, closeTo(20, 0.01));
    expect(placements[0].position.dx, lessThan(placements[1].position.dx));
  });

  test('reversed layout rotates glyphs to follow the opposite direction', () {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(100, 0);
    final placements = TextOnPathLayout.layout(
      text: 'A',
      path: path,
      style: const TextStyle(fontSize: 12),
      reversed: true,
    );

    expect(placements, hasLength(1));
    expect(placements.single.angle, closeTo(3.141592653589793, 0.01));
  });
}
