import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/capture/domain/capture_canvas_handoff.dart';

void main() {
  test('local capture handoffs accept only editable local targets', () {
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
        readOnly: true,
        collaborationRoom: false,
        hasCollaborationRole: false,
      ),
      isFalse,
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
  });
}
