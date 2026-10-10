import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/features/canvas/domain/canvas_precision.dart';
import 'package:varian/features/canvas/state/canvas_precision_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('precision state round-trips and clamps invalid values', () {
    const state = CanvasPrecisionState(
      gridPreset: CanvasGridPreset.majorMinor,
      gridSpacing: 48,
      gridSubdivisions: 8,
      snapMode: CanvasSnapMode.guides,
      rulersVisible: true,
      guides: [
        CanvasGuide(
          id: 'guide-a',
          axis: CanvasGuideAxis.vertical,
          position: 240,
          label: 'Content edge',
        ),
      ],
    );

    final restored = CanvasPrecisionState.fromJson(state.toJson());

    expect(restored.gridPreset, CanvasGridPreset.majorMinor);
    expect(restored.gridSpacing, 48);
    expect(restored.gridSubdivisions, 8);
    expect(restored.snapMode, CanvasSnapMode.guides);
    expect(restored.guides.single.label, 'Content edge');
    expect(
      restored.toJson()['schemaVersion'],
      CanvasPrecisionState.schemaVersion,
    );

    final clamped = CanvasPrecisionState.fromJson({
      'gridSpacing': 99999,
      'gridSubdivisions': 99,
    });
    expect(clamped.gridSpacing, 512);
    expect(clamped.gridSubdivisions, 16);
  });

  test('grid and guide snapping compose deterministically', () {
    const state = CanvasPrecisionState(
      gridPreset: CanvasGridPreset.dots,
      gridSpacing: 20,
      snapMode: CanvasSnapMode.all,
      guides: [
        CanvasGuide(
          id: 'guide-a',
          axis: CanvasGuideAxis.vertical,
          position: 80,
        ),
      ],
    );

    expect(
      CanvasPrecisionMath.snapPoint(const Offset(79, 41), state: state),
      const Offset(80, 40),
    );
    expect(
      CanvasPrecisionMath.snapPoint(
        const Offset(79, 41),
        state: state.copyWith(snapMode: CanvasSnapMode.off),
      ),
      const Offset(79, 41),
    );
  });

  test('ruler ticks are ordered and bounded', () {
    final ticks = CanvasPrecisionMath.rulerTicks(
      start: -100,
      end: 500,
      zoom: 1,
    );

    expect(ticks, isNotEmpty);
    expect(ticks.length, lessThanOrEqualTo(1000));
    for (var index = 1; index < ticks.length; index++) {
      expect(
        ticks[index].worldPosition,
        greaterThan(ticks[index - 1].worldPosition),
      );
    }
  });

  test('precision notifier persists project-scoped settings', () async {
    final notifier = CanvasPrecisionNotifier('project-a');
    await notifier.ready;
    notifier.setGridVisible(false);
    notifier.addGuide(
      const CanvasGuide(
        id: 'guide-a',
        axis: CanvasGuideAxis.horizontal,
        position: 120,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final restored = CanvasPrecisionNotifier('project-a');
    await restored.ready;

    expect(restored.state.gridVisible, isFalse);
    expect(restored.state.guides.single.position, 120);
  });
}
