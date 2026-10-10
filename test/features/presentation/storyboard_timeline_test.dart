import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/presentation/domain/storyboard_timeline.dart';

void main() {
  test('timeline calculates duration and reorders shots', () {
    const timeline = PresentationTimeline(
      shots: [
        StoryboardShot(
          id: 'a',
          title: 'A',
          frameId: 'frame-a',
          duration: Duration(seconds: 2),
        ),
        StoryboardShot(
          id: 'b',
          title: 'B',
          frameId: 'frame-b',
          duration: Duration(seconds: 3),
        ),
      ],
    );

    final reordered = timeline.reorderShots(const ['b', 'a']);
    expect(timeline.totalDuration, const Duration(seconds: 5));
    expect(reordered.shots.first.id, 'b');
  });

  test('timeline track interpolates between keyframes', () {
    const track = TimelineTrack(
      id: 'opacity',
      targetNodeId: 'node-1',
      property: 'opacity',
      keyframes: [
        TimelineKeyframe(offset: Duration.zero, value: 0),
        TimelineKeyframe(offset: Duration(seconds: 2), value: 1),
      ],
    );

    expect(track.valueAt(const Duration(seconds: 1)), closeTo(0.5, 0.001));
  });
}
