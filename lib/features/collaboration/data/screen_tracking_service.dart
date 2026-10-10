import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../domain/models/collaboration.dart';

typedef ScreenDisplayCapture = Future<MediaStream> Function();
typedef ScreenPeerConnectionFactory =
    Future<RTCPeerConnection> Function(
      Map<String, dynamic> configuration, [
      Map<String, dynamic> constraints,
    ]);

Future<MediaStream> _captureDisplayStream() async {
  if (!kIsWeb) {
    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen],
      );
      final source = sources.firstOrNull;
      if (source != null) {
        return navigator.mediaDevices.getDisplayMedia({
          'video': {
            'deviceId': {'exact': source.id},
          },
          'audio': false,
        });
      }
    } catch (_) {}
  }
  return navigator.mediaDevices.getDisplayMedia({
    'video': true,
    'audio': false,
  });
}

class ScreenTrackingSnapshot {
  final ScreenTrackingStatus status;
  final String? peerUserId;
  final RTCVideoRenderer? renderer;
  final String? errorMessage;

  const ScreenTrackingSnapshot({
    required this.status,
    this.peerUserId,
    this.renderer,
    this.errorMessage,
  });
}

class ScreenTrackingService {
  final Future<void> Function(String peerUserId, Map<String, dynamic> signal)
  onSignal;
  final void Function(ScreenTrackingSnapshot snapshot) onChanged;
  final ScreenDisplayCapture _captureDisplay;
  final ScreenPeerConnectionFactory _createPeerConnection;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RTCVideoRenderer? _renderer;
  String? _peerUserId;
  String? _shareId;
  bool _remoteDescriptionSet = false;
  bool _disposed = false;
  bool _cleaningUp = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  ScreenTrackingService({
    required this.onSignal,
    required this.onChanged,
    ScreenDisplayCapture? captureDisplay,
    ScreenPeerConnectionFactory? createPeerConnection,
  }) : _captureDisplay = captureDisplay ?? _captureDisplayStream,
       _createPeerConnection = createPeerConnection ?? _defaultPeerConnection;

  static Future<RTCPeerConnection> _defaultPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) => createPeerConnection(configuration, constraints);

  ScreenTrackingSnapshot _snapshot(
    ScreenTrackingStatus status, {
    String? errorMessage,
  }) => ScreenTrackingSnapshot(
    status: status,
    peerUserId: _peerUserId,
    renderer: _renderer,
    errorMessage: errorMessage,
  );

  Future<void> startSharing({
    required String peerUserId,
    required String shareId,
  }) async {
    _peerUserId = peerUserId;
    _shareId = shareId;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    onChanged(_snapshot(ScreenTrackingStatus.awaitingConsent));
    try {
      _localStream = await _captureDisplay();
      _renderer ??= RTCVideoRenderer();
      await _renderer!.initialize();
      _renderer!.srcObject = _localStream;
      final videoTrack = _localStream?.getVideoTracks().firstOrNull;
      videoTrack?.onEnded = () {
        unawaited(stop());
      };
      await _ensurePeerConnection();
      for (final track
          in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': true,
      });
      await _peerConnection!.setLocalDescription(offer);
      onChanged(_snapshot(ScreenTrackingStatus.sharing));
      await _sendSignal({
        'kind': 'offer',
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (error) {
      await _cleanupPeer();
      onChanged(
        _snapshot(
          ScreenTrackingStatus.error,
          errorMessage: 'Screen sharing could not start: $error',
        ),
      );
      rethrow;
    }
  }

  Future<void> prepareViewer({
    required String peerUserId,
    required String shareId,
  }) async {
    _peerUserId = peerUserId;
    _shareId = shareId;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    try {
      await _ensurePeerConnection();
      onChanged(_snapshot(ScreenTrackingStatus.connecting));
    } catch (error) {
      await _reportError('Screen tracking could not connect: $error');
    }
  }

  Future<void> handleSignal(Map<String, dynamic> signal) async {
    if (_disposed) return;
    final kind = signal['kind']?.toString();
    final shareId = signal['shareId']?.toString();
    if (kind == null || shareId == null || shareId != _shareId) return;
    try {
      await _ensurePeerConnection();
      switch (kind) {
        case 'offer':
          final sdp = signal['sdp']?.toString();
          final type = signal['type']?.toString();
          if (sdp == null || type == null) return;
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(sdp, type),
          );
          _remoteDescriptionSet = true;
          await _flushCandidates();
          final answer = await _peerConnection!.createAnswer({
            'offerToReceiveAudio': false,
            'offerToReceiveVideo': true,
          });
          await _peerConnection!.setLocalDescription(answer);
          onChanged(_snapshot(ScreenTrackingStatus.viewing));
          await _sendSignal({
            'kind': 'answer',
            'sdp': answer.sdp,
            'type': answer.type,
          });
        case 'answer':
          final sdp = signal['sdp']?.toString();
          final type = signal['type']?.toString();
          if (sdp == null || type == null) return;
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(sdp, type),
          );
          _remoteDescriptionSet = true;
          await _flushCandidates();
        case 'candidate':
          final candidate = signal['candidate']?.toString();
          if (candidate == null) return;
          final rawMLineIndex = signal['sdpMLineIndex'];
          final parsed = RTCIceCandidate(
            candidate,
            signal['sdpMid']?.toString(),
            rawMLineIndex is num
                ? rawMLineIndex.toInt()
                : int.tryParse(rawMLineIndex?.toString() ?? ''),
          );
          if (_remoteDescriptionSet) {
            await _peerConnection!.addCandidate(parsed);
          } else {
            _pendingCandidates.add(parsed);
          }
      }
    } catch (error) {
      await _reportError('Screen tracking signal failed: $error');
    }
  }

  Future<void> stop() async {
    await _cleanupPeer();
    if (!_disposed) onChanged(_snapshot(ScreenTrackingStatus.stopped));
  }

  Future<void> _ensurePeerConnection() async {
    if (_peerConnection != null) return;
    _peerConnection = await _createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    }, {});
    _peerConnection!.onIceCandidate = (candidate) {
      unawaited(
        _sendSignal({
          'kind': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    };
    _peerConnection!.onTrack = (event) {
      final stream = event.streams.firstOrNull;
      if (stream == null) return;
      unawaited(_attachRemoteStream(stream));
    };
    _peerConnection!.onAddStream = (stream) {
      unawaited(_attachRemoteStream(stream));
    };
    _peerConnection!.onConnectionState = (connectionState) {
      if (connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_reportError('Screen tracking connection closed.'));
      }
    };
  }

  Future<void> _attachRemoteStream(MediaStream stream) async {
    try {
      _renderer ??= RTCVideoRenderer();
      await _renderer!.initialize();
      _renderer!.srcObject = stream;
      onChanged(_snapshot(ScreenTrackingStatus.viewing));
    } catch (error) {
      await _reportError('Screen tracking video failed: $error');
    }
  }

  Future<void> _flushCandidates() async {
    if (!_remoteDescriptionSet || _peerConnection == null) return;
    final candidates = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in candidates) {
      await _peerConnection!.addCandidate(candidate);
    }
  }

  Future<void> _sendSignal(Map<String, dynamic> signal) async {
    final peerUserId = _peerUserId;
    final shareId = _shareId;
    if (peerUserId == null || shareId == null || _disposed) return;
    await onSignal(peerUserId, {...signal, 'shareId': shareId});
  }

  Future<void> _cleanupPeer() async {
    if (_cleaningUp) return;
    _cleaningUp = true;
    final stream = _localStream;
    try {
      _localStream = null;
      for (final track in stream?.getTracks() ?? const <MediaStreamTrack>[]) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await _peerConnection?.close();
        await _peerConnection?.dispose();
      } catch (_) {}
      _peerConnection = null;
      _remoteDescriptionSet = false;
      _pendingCandidates.clear();
      if (_renderer != null) {
        _renderer!.srcObject = null;
        try {
          await _renderer!.dispose();
        } catch (_) {}
        _renderer = null;
      }
      _peerUserId = null;
      _shareId = null;
    } finally {
      _cleaningUp = false;
    }
  }

  Future<void> _reportError(String message) async {
    if (_disposed || _cleaningUp) return;
    await _cleanupPeer();
    if (!_disposed) {
      onChanged(_snapshot(ScreenTrackingStatus.error, errorMessage: message));
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _cleanupPeer();
    await _renderer?.dispose();
    _renderer = null;
  }
}
