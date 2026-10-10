import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/capture/domain/capture_canvas_handoff.dart';

void main() {
  test('local capture commits reject collaboration and read-only targets', () {
    expect(
      canAcceptLocalCaptureCanvasHandoff(
        readOnly: false,
        collaborationRoom: false,
        hasCollaborationRole: false,
      ),
      isTrue,
    );
    expect(
      canAcceptLocalCaptureCanvasHandoff(
        readOnly: false,
        collaborationRoom: true,
        hasCollaborationRole: false,
      ),
      isFalse,
    );
    expect(
      canAcceptLocalCaptureCanvasHandoff(
        readOnly: false,
        collaborationRoom: false,
        hasCollaborationRole: true,
      ),
      isFalse,
    );
    expect(
      canAcceptLocalCaptureCanvasHandoff(
        readOnly: true,
        collaborationRoom: false,
        hasCollaborationRole: false,
      ),
      isFalse,
    );
  });

  test('uses a collision-safe identity when a manifest ID is already used', () {
    final id = stableDocumentAssetIdForCapture(
      preferredId: 'node-1',
      occupiedManifestIds: {'node-1'},
      occupiedNodeIds: {'node-1'},
      fallback: 'node-1',
    );

    expect(id, isNot('node-1'));
    expect(id, isNotEmpty);
  });

  test('keeps an unused node identity for a new manifest asset', () {
    expect(
      stableDocumentAssetIdForCapture(
        preferredId: 'node-1',
        occupiedManifestIds: const {},
        occupiedNodeIds: const {},
        fallback: 'node-1',
      ),
      'node-1',
    );
  });

  test('consumes once for the matching project and account', () {
    final handoff = CaptureCanvasHandoff(
      projectId: 'project-1',
      accountId: 'account-1',
      captureId: 'capture-1',
    );

    expect(
      handoff.consume(projectId: 'project-1', accountId: 'account-1'),
      isTrue,
    );
    expect(handoff.isConsumed, isTrue);
    expect(
      handoff.consume(projectId: 'project-1', accountId: 'account-1'),
      isFalse,
    );
  });

  test('mismatch consumes the handoff without making it replayable', () {
    final handoff = CaptureCanvasHandoff(
      projectId: 'project-1',
      accountId: 'account-1',
      captureId: 'capture-1',
    );

    expect(
      handoff.consume(projectId: 'project-2', accountId: 'account-1'),
      isFalse,
    );
    expect(handoff.isConsumed, isTrue);
    expect(
      handoff.consume(projectId: 'project-1', accountId: 'account-1'),
      isFalse,
    );
  });

  test('matches signed-out handoffs only to the same null account', () {
    final handoff = CaptureCanvasHandoff(
      projectId: 'project-1',
      accountId: null,
      captureId: 'capture-1',
    );

    expect(
      handoff.consume(projectId: 'project-1', accountId: 'account-1'),
      isFalse,
    );
    expect(handoff.isConsumed, isTrue);
  });
}
