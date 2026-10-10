import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/charts/data/chart_canvas_interaction.dart';

void main() {
  test('maps axis chart clicks to categories', () {
    final payload = ChartPayload(
      chartType: ChartType.bar,
      categories: const ['A', 'B', 'C'],
    );

    expect(
      ChartCanvasCategoryHitTester.categoryAt(
        payload: payload,
        size: const Size(300, 200),
        localPosition: const Offset(150, 80),
      ),
      'B',
    );
  });

  test('maps radial chart clicks and ignores a doughnut hole', () {
    final payload = ChartPayload(
      chartType: ChartType.doughnut,
      categories: const ['Top', 'Right', 'Bottom', 'Left'],
    );

    expect(
      ChartCanvasCategoryHitTester.categoryAt(
        payload: payload,
        size: const Size(200, 200),
        localPosition: const Offset(100, 30),
      ),
      'Top',
    );
    expect(
      ChartCanvasCategoryHitTester.categoryAt(
        payload: payload,
        size: const Size(200, 200),
        localPosition: const Offset(100, 100),
      ),
      isNull,
    );
  });
}
