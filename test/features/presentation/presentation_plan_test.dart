import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/presentation/domain/presentation_plan.dart';

CanvasNode _frame(String id, double x) => CanvasNode(
  id: id,
  type: NodeType.frame,
  x: x,
  y: 0,
  width: 800,
  height: 600,
  payload: FramePayload(name: id),
);

void main() {
  test('explicit presentation order wins over canvas position', () {
    final document = CanvasDocument(
      projectId: 'presentation',
      nodes: [_frame('first-on-canvas', 0), _frame('second-on-canvas', 1000)],
      metadata: {
        'presentation': {
          'frames': [
            {
              'frameId': 'second-on-canvas',
              'order': 0,
              'durationMs': 2000,
              'transition': 'fade',
              'speakerNotes': 'Explain architecture',
            },
            {'frameId': 'first-on-canvas', 'order': 1},
          ],
        },
      },
      updatedAt: DateTime.utc(2026, 9, 11),
    );
    final plan = PresentationPlan.fromDocument(document);
    expect(plan.resolveFrames(document.nodes).first.id, 'second-on-canvas');
    expect(
      plan.configFor('second-on-canvas')?.speakerNotes,
      'Explain architecture',
    );
  });

  test('hotspot validation and playback seeking are deterministic', () {
    final hotspot = CanvasNode(
      id: 'hotspot',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      payload: MermaidPayload(hotspotTargetFrameId: 'missing-frame'),
    );
    const plan = PresentationPlan(
      frames: [
        PresentationFrameConfig(
          frameId: 'f1',
          order: 0,
          duration: Duration(seconds: 2),
        ),
        PresentationFrameConfig(
          frameId: 'f2',
          order: 1,
          duration: Duration(seconds: 3),
        ),
      ],
    );
    final issues = plan.validateHotspots([_frame('f1', 0), hotspot]);
    expect(issues.single.targetFrameId, 'missing-frame');

    final clock = PresentationPlaybackClock(plan);
    expect(clock.totalDuration, const Duration(seconds: 5));
    clock.seek(const Duration(seconds: 2));
    expect(clock.frameIndexAtPosition, 1);
    clock.seek(const Duration(seconds: 99));
    expect(clock.position, const Duration(seconds: 5));
  });
}
