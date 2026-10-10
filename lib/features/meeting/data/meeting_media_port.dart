import 'package:flutter/widgets.dart';

import '../domain/meeting_errors.dart';
import '../domain/meeting_models.dart';
import 'meeting_media_credentials.dart';

class MeetingMediaException implements Exception {
  const MeetingMediaException(this.code);

  final MeetingErrorCode code;

  @override
  String toString() =>
      'MeetingMediaException: ${MeetingErrorMessage.forCode(code)}';
}

/// Provider-independent media contract used by meeting controllers and views.
abstract interface class MeetingMediaPort {
  Stream<MeetingMediaEvent> get events;

  /// Server-authorized capability for publishing local media.
  bool get canPublish;

  /// Provider identity for the local participant, when connected.
  String? get localIdentity => null;

  /// Connects using a short-lived credential owned by the media boundary.
  Future<void> connect({required MeetingMediaCredentials credentials});

  /// Applies a replacement credential to an already connected provider.
  ///
  /// Implementations own the credential and must not expose it through domain
  /// state or events.
  Future<void> updateToken({required MeetingMediaCredentials credentials});

  Future<void> setMicrophoneEnabled(bool enabled);

  Future<void> setCameraEnabled(bool enabled);

  Future<void> setScreenShareEnabled(bool enabled);

  /// Builds a provider-owned video surface when the requested track is ready.
  ///
  /// A null result is an honest fallback signal: the participant is absent,
  /// unsubscribed, or this provider cannot render the requested source.
  Widget? buildVideoSurface(MeetingVideoSurface surface) => null;

  Future<void> disconnect();

  Future<void> dispose();
}

/// Video sources that can be rendered in a meeting participant surface.
enum MeetingVideoSource { camera, screenShare }

/// Immutable provider-neutral description of a video surface request.
final class MeetingVideoSurface {
  const MeetingVideoSurface({
    required this.identity,
    required this.source,
    required this.isLocal,
  });

  final String identity;
  final MeetingVideoSource source;
  final bool isLocal;

  @override
  bool operator ==(Object other) =>
      other is MeetingVideoSurface &&
      other.identity == identity &&
      other.source == source &&
      other.isLocal == isLocal;

  @override
  int get hashCode => Object.hash(identity, source, isLocal);
}

enum MeetingMediaProviderEventType {
  connected,
  reconnecting,
  reconnected,
  disconnected,
  participantJoined,
  participantLeft,
  trackSubscribed,
  trackUnsubscribed,
  participantStateChanged,
  activeSpeakerChanged,
  tokenRefreshRequested,
  error,
}

/// A provider event contains only stable values; SDK objects never cross this seam.
final class MeetingMediaProviderEvent {
  const MeetingMediaProviderEvent({
    required this.type,
    this.identity,
    this.displayName,
    this.role = MeetingParticipantRole.viewer,
    this.isLocal = false,
    this.microphoneEnabled = false,
    this.cameraEnabled = false,
    this.screenShareEnabled = false,
    this.trackKind,
    this.isSpeaking = false,
    this.errorCode = MeetingErrorCode.providerUnavailable,
  });

  final MeetingMediaProviderEventType type;
  final String? identity;
  final String? displayName;
  final MeetingParticipantRole role;
  final bool isLocal;
  final bool microphoneEnabled;
  final bool cameraEnabled;
  final bool screenShareEnabled;
  final String? trackKind;
  final bool isSpeaking;
  final MeetingErrorCode errorCode;
}

/// Narrow seam for deterministic adapter tests and platform-safe provider wiring.
abstract interface class MeetingMediaProvider {
  Stream<MeetingMediaProviderEvent> get events;
  bool get canPublish;
  String? get localIdentity => null;

  Future<void> connect({required String serverUrl, required String token});
  Future<void> updateToken(String token);
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> setScreenShareEnabled(bool enabled);
  Widget? buildVideoSurface(MeetingVideoSurface surface) => null;
  Future<void> disconnect();
  Future<void> dispose();
}

typedef MeetingMediaProviderFactory = MeetingMediaProvider Function();
