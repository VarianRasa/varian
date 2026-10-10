import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/collaboration/data/screen_tracking_service.dart';

void main() {
  test(
    'screen capture failure becomes a recoverable user-facing error',
    () async {
      final snapshots = <ScreenTrackingSnapshot>[];
      final service = ScreenTrackingService(
        onSignal: (_, _) async {},
        onChanged: snapshots.add,
        captureDisplay: () =>
            Future<MediaStream>.error(StateError('permission denied')),
      );
      addTearDown(service.dispose);

      await expectLater(
        service.startSharing(peerUserId: 'peer', shareId: 'share'),
        throwsA(isA<StateError>()),
      );

      expect(snapshots.map((snapshot) => snapshot.status), [
        ScreenTrackingStatus.awaitingConsent,
        ScreenTrackingStatus.error,
      ]);
      expect(snapshots.last.peerUserId, isNull);
      expect(snapshots.last.renderer, isNull);
      expect(snapshots.last.errorMessage, contains('permission denied'));
    },
  );

  test(
    'viewer connection failure becomes a recoverable user-facing error',
    () async {
      final snapshots = <ScreenTrackingSnapshot>[];
      final service = ScreenTrackingService(
        onSignal: (_, _) async {},
        onChanged: snapshots.add,
        createPeerConnection: (_, [_ = const <String, dynamic>{}]) =>
            Future<RTCPeerConnection>.error(StateError('TURN unavailable')),
      );
      addTearDown(service.dispose);

      await service.prepareViewer(peerUserId: 'peer', shareId: 'share');

      expect(snapshots, hasLength(1));
      expect(snapshots.single.status, ScreenTrackingStatus.error);
      expect(snapshots.single.peerUserId, isNull);
      expect(snapshots.single.renderer, isNull);
      expect(snapshots.single.errorMessage, contains('TURN unavailable'));
    },
  );
}
