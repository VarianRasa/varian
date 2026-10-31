import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';

import '../domain/meeting_errors.dart';
import '../domain/meeting_models.dart';
import 'meeting_media_credentials.dart';
import 'meeting_media_port.dart';

/// Media adapter that keeps all LiveKit objects behind [MeetingMediaPort].
final class LiveKitMeetingMedia implements MeetingMediaPort {
  LiveKitMeetingMedia({MeetingMediaProviderFactory? providerFactory})
    : _providerFactory = providerFactory ?? LiveKitMeetingMediaProvider.new;

  final MeetingMediaProviderFactory _providerFactory;
  final StreamController<MeetingMediaEvent> _events =
      StreamController<MeetingMediaEvent>.broadcast(sync: true);
  MeetingMediaProvider? _provider;
  StreamSubscription<MeetingMediaProviderEvent>? _providerSubscription;
  bool _disposed = false;
  bool _connected = false;
  bool _disconnecting = false;
  MeetingStatus? _lastStatus;

  @override
  Stream<MeetingMediaEvent> get events => _events.stream;

  @override
  bool get canPublish => _provider?.canPublish ?? false;

  @override
  String? get localIdentity => _provider?.localIdentity;

  @override
  Widget? buildVideoSurface(MeetingVideoSurface surface) =>
      _provider?.buildVideoSurface(surface);
  @override
  Future<void> connect({required MeetingMediaCredentials credentials}) async {
    _ensureUsable();
    await credentials.use<void>(({
      required String serverUrl,
      required String token,
    }) async {
      _validateServerUrl(serverUrl);
      if (token.trim().isEmpty) throw ArgumentError.value(token, 'token');
      if (_provider != null) return;

      final provider = _providerFactory();
      _provider = provider;
      _providerSubscription = provider.events.listen(
        _handleProviderEvent,
        onError: (_) => _emitError(),
      );
      try {
        await provider.connect(serverUrl: serverUrl, token: token);
        _connected = true;
        _emitConnection(MeetingStatus.connected);
      } catch (_) {
        await _cleanupProvider();
        _emitError();
        throw const MeetingMediaException(MeetingErrorCode.providerUnavailable);
      }
    });
  }

  @override
  Future<void> updateToken({
    required MeetingMediaCredentials credentials,
  }) async {
    _ensureUsable();
    final provider = _provider;
    if (!_connected || provider == null) return;
    try {
      await credentials.useToken(provider.updateToken);
    } catch (_) {
      _emitError();
      rethrow;
    }
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) => _setLocalMedia(
    (provider) => provider.setMicrophoneEnabled(enabled),
    (event) => event.copyWith(microphoneEnabled: enabled),
  );

  @override
  Future<void> setCameraEnabled(bool enabled) => _setLocalMedia(
    (provider) => provider.setCameraEnabled(enabled),
    (event) => event.copyWith(cameraEnabled: enabled),
  );

  @override
  Future<void> setScreenShareEnabled(bool enabled) => _setLocalMedia(
    (provider) => provider.setScreenShareEnabled(enabled),
    (event) => event.copyWith(screenShareEnabled: enabled),
  );

  Future<void> _setLocalMedia(
    Future<void> Function(MeetingMediaProvider provider) operation,
    MeetingMediaEvent Function(MeetingMediaEvent event) update,
  ) async {
    _ensureUsable();
    final provider = _provider;
    if (!_connected || provider == null) return;
    if (!provider.canPublish) {
      _emitError(MeetingErrorCode.authorizationError);
      return;
    }
    try {
      await operation(provider);
      final current = MeetingMediaEvent.localMediaChanged();
      _events.add(update(current));
    } catch (_) {
      _emitError();
    }
  }

  @override
  Future<void> disconnect() async {
    if (_disposed || _disconnecting) return;
    _disconnecting = true;
    try {
      await _cleanupProvider();
      if (_lastStatus != MeetingStatus.ended) {
        _emitConnection(MeetingStatus.ended);
      }
    } finally {
      _disconnecting = false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _cleanupProvider();
    await _events.close();
  }

  void _handleProviderEvent(MeetingMediaProviderEvent event) {
    if (_disposed || _disconnecting) return;
    switch (event.type) {
      case MeetingMediaProviderEventType.connected:
      case MeetingMediaProviderEventType.reconnected:
        _connected = true;
        _emitConnection(MeetingStatus.connected);
      case MeetingMediaProviderEventType.reconnecting:
        _emitConnection(MeetingStatus.reconnecting);
      case MeetingMediaProviderEventType.disconnected:
        _connected = false;
        _emitConnection(MeetingStatus.ended);
        unawaited(_cleanupProvider());
      case MeetingMediaProviderEventType.participantJoined:
        final identity = event.identity;
        if (identity != null && identity.isNotEmpty) {
          _events.add(MeetingMediaEvent.participantJoined(_participant(event)));
        }
      case MeetingMediaProviderEventType.participantLeft:
        final identity = event.identity;
        if (identity != null && identity.isNotEmpty) {
          _events.add(MeetingMediaEvent.participantLeft(identity));
        }
      case MeetingMediaProviderEventType.trackSubscribed:
        _trackEvent(event, subscribed: true);
      case MeetingMediaProviderEventType.trackUnsubscribed:
        _trackEvent(event, subscribed: false);
      case MeetingMediaProviderEventType.participantStateChanged:
        final identity = event.identity;
        if (identity == null || identity.isEmpty) return;
        if (event.isLocal) {
          _events.add(
            MeetingMediaEvent.localMediaChanged(
              microphoneEnabled: event.microphoneEnabled,
              cameraEnabled: event.cameraEnabled,
              screenShareEnabled: event.screenShareEnabled,
            ),
          );
        } else {
          _events.add(MeetingMediaEvent.participantJoined(_participant(event)));
        }
      case MeetingMediaProviderEventType.activeSpeakerChanged:
        final identity = event.identity;
        if (identity != null && identity.isNotEmpty) {
          _events.add(
            MeetingMediaEvent.activeSpeakerChanged(
              identity: identity,
              isSpeaking: event.isSpeaking,
            ),
          );
        }
      case MeetingMediaProviderEventType.tokenRefreshRequested:
        _events.add(MeetingMediaEvent.tokenRefreshRequested());
      case MeetingMediaProviderEventType.error:
        _emitError(event.errorCode);
    }
  }

  void _trackEvent(
    MeetingMediaProviderEvent event, {
    required bool subscribed,
  }) {
    final identity = event.identity;
    final kind = event.trackKind;
    if (identity == null || identity.isEmpty || kind == null || kind.isEmpty) {
      return;
    }
    _events.add(
      subscribed
          ? MeetingMediaEvent.trackSubscribed(
              identity: identity,
              trackKind: kind,
            )
          : MeetingMediaEvent.trackUnsubscribed(
              identity: identity,
              trackKind: kind,
            ),
    );
  }

  MeetingParticipant _participant(MeetingMediaProviderEvent event) =>
      MeetingParticipant(
        identity: event.identity ?? '',
        displayName: event.displayName ?? '',
        role: event.role,
        isLocal: event.isLocal,
        microphoneEnabled: event.microphoneEnabled,
        cameraEnabled: event.cameraEnabled,
        screenShareEnabled: event.screenShareEnabled,
        isSpeaking: event.isSpeaking,
      );

  void _emitConnection(MeetingStatus status) {
    if (_lastStatus == status || _disposed) return;
    _lastStatus = status;
    _events.add(MeetingMediaEvent.connectionChanged(status));
  }

  void _emitError([
    MeetingErrorCode code = MeetingErrorCode.providerUnavailable,
  ]) {
    if (!_disposed) {
      _events.add(MeetingMediaEvent.providerError(errorCode: code));
    }
  }

  Future<void> _cleanupProvider() async {
    final subscription = _providerSubscription;
    _providerSubscription = null;
    await subscription?.cancel();
    final provider = _provider;
    _provider = null;
    _connected = false;
    if (provider != null) {
      try {
        await provider.disconnect();
      } catch (_) {}
      try {
        await provider.dispose();
      } catch (_) {}
    }
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('meeting media is disposed');
  }

  static void _validateServerUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'wss' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(value, 'serverUrl');
    }
  }
}

/// LiveKit 2.13.0 provider implementation.
final class LiveKitMeetingMediaProvider implements MeetingMediaProvider {
  final StreamController<MeetingMediaProviderEvent> _events =
      StreamController<MeetingMediaProviderEvent>.broadcast(sync: true);
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Set<String> _speakers = <String>{};
  bool _disposed = false;

  @override
  Stream<MeetingMediaProviderEvent> get events => _events.stream;

  @override
  bool get canPublish =>
      _room?.localParticipant?.permissions.canPublish ?? false;

  @override
  String? get localIdentity => _room?.localParticipant?.identity;

  @override
  Widget? buildVideoSurface(MeetingVideoSurface surface) {
    if (_disposed || surface.identity.trim().isEmpty) return null;
    final Participant<TrackPublication<Track>>? participant = surface.isLocal
        ? _room?.localParticipant
        : _room?.remoteParticipants[surface.identity];
    if (participant == null) return null;
    final source = switch (surface.source) {
      MeetingVideoSource.camera => TrackSource.camera,
      MeetingVideoSource.screenShare => TrackSource.screenShareVideo,
    };
    TrackPublication<Track>? publication;
    for (final candidate in participant.trackPublications.values) {
      if (candidate.source == source) {
        publication = candidate;
        break;
      }
    }
    final track = publication?.track;
    if (publication == null || !publication.subscribed || publication.muted) {
      return null;
    }
    if (track is! VideoTrack) return null;
    return VideoTrackRenderer(
      track,
      key: ValueKey('${surface.identity}:${surface.source.name}'),
      fit: VideoViewFit.cover,
      autoCenter: false,
    );
  }

  @override
  Future<void> connect({
    required String serverUrl,
    required String token,
  }) async {
    if (_disposed) throw StateError('provider is disposed');
    if (_room != null) return;
    final room = Room();
    _room = room;
    final listener = room.createListener();
    _listener = listener;
    listener
      ..on<RoomConnectedEvent>(
        (_) => _emit(
          const MeetingMediaProviderEvent(
            type: MeetingMediaProviderEventType.connected,
          ),
        ),
      )
      ..on<RoomReconnectingEvent>(
        (_) => _emit(
          const MeetingMediaProviderEvent(
            type: MeetingMediaProviderEventType.reconnecting,
          ),
        ),
      )
      ..on<RoomResumingEvent>(
        (_) => _emit(
          const MeetingMediaProviderEvent(
            type: MeetingMediaProviderEventType.reconnecting,
          ),
        ),
      )
      ..on<RoomReconnectedEvent>(
        (_) => _emit(
          const MeetingMediaProviderEvent(
            type: MeetingMediaProviderEventType.reconnected,
          ),
        ),
      )
      ..on<RoomAttemptReconnectEvent>(
        (_) => _emit(
          const MeetingMediaProviderEvent(
            type: MeetingMediaProviderEventType.tokenRefreshRequested,
          ),
        ),
      )
      ..on<RoomDisconnectedEvent>(
        (event) => _emit(_disconnectionEvent(event.reason)),
      )
      ..on<LocalTrackPublishedEvent>(
        (event) => _emit(_stateEvent(event.participant, event.publication)),
      )
      ..on<LocalTrackUnpublishedEvent>(
        (event) => _emit(
          _stateEvent(
            event.participant,
            event.publication,
            unpublishedSource: event.publication.source,
          ),
        ),
      )
      ..on<ParticipantConnectedEvent>(
        (event) => _emit(
          _participantEvent(
            MeetingMediaProviderEventType.participantJoined,
            event.participant,
          ),
        ),
      )
      ..on<ParticipantDisconnectedEvent>(
        (event) => _emit(
          _participantEvent(
            MeetingMediaProviderEventType.participantLeft,
            event.participant,
          ),
        ),
      )
      ..on<TrackSubscribedEvent>(
        (event) => _emit(
          MeetingMediaProviderEvent(
            type: MeetingMediaProviderEventType.trackSubscribed,
            identity: event.participant.identity,
            trackKind: _trackKind(event.publication.source),
          ),
        ),
      )
      ..on<TrackUnsubscribedEvent>(
        (event) => _emit(
          MeetingMediaProviderEvent(
            type: MeetingMediaProviderEventType.trackUnsubscribed,
            identity: event.participant.identity,
            trackKind: _trackKind(event.publication.source),
          ),
        ),
      )
      ..on<TrackMutedEvent>(
        (event) => _emit(_stateEvent(event.participant, event.publication)),
      )
      ..on<TrackUnmutedEvent>(
        (event) => _emit(_stateEvent(event.participant, event.publication)),
      )
      ..on<ActiveSpeakersChangedEvent>(_onSpeakersChanged)
      ..on<TrackSubscriptionExceptionEvent>(
        (_) => _emit(
          const MeetingMediaProviderEvent(
            type: MeetingMediaProviderEventType.error,
          ),
        ),
      )
      ..on<ParticipantPermissionsUpdatedEvent>((event) {
        if (event.participant is LocalParticipant) {
          _emit(_stateEvent(event.participant, null));
        }
      });
    await room.connect(serverUrl, token);
    for (final participant in room.remoteParticipants.values) {
      _emit(
        _participantEvent(
          MeetingMediaProviderEventType.participantJoined,
          participant,
        ),
      );
    }
  }

  @override
  Future<void> updateToken(String token) async {
    if (_disposed) throw StateError('provider is disposed');
    if (token.trim().isEmpty) throw ArgumentError.value(token, 'token');
    final room = _room;
    if (room == null) return;
    // LiveKit 2.13 has no Room-level replacement method. Its Engine keeps the
    // token used by the next resume/full reconnect; keep that SDK detail here.
    // ignore: invalid_use_of_internal_member
    room.engine.token = token;
  }

  MeetingMediaProviderEvent _disconnectionEvent(DisconnectReason? reason) {
    final code = switch (reason) {
      DisconnectReason.participantRemoved => MeetingErrorCode.removed,
      DisconnectReason.roomDeleted ||
      DisconnectReason.roomClosed => MeetingErrorCode.ended,
      _ => MeetingErrorCode.providerUnavailable,
    };
    return MeetingMediaProviderEvent(
      type: code == MeetingErrorCode.providerUnavailable
          ? MeetingMediaProviderEventType.disconnected
          : MeetingMediaProviderEventType.error,
      errorCode: code,
    );
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null) throw StateError('provider is not connected');
    await participant.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null) throw StateError('provider is not connected');
    await participant.setCameraEnabled(enabled);
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null) throw StateError('provider is not connected');
    await participant.setScreenShareEnabled(enabled);
  }

  @override
  Future<void> disconnect() async {
    await _room?.disconnect();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _listener?.dispose();
    _listener = null;
    await _room?.dispose();
    _room = null;
    await _events.close();
  }

  MeetingMediaProviderEvent _participantEvent(
    MeetingMediaProviderEventType type,
    Participant participant,
  ) {
    return MeetingMediaProviderEvent(
      type: type,
      identity: participant.identity,
      displayName: participant.name,
      role: participant.permissions.canPublish
          ? MeetingParticipantRole.publisher
          : MeetingParticipantRole.viewer,
      isLocal: participant is LocalParticipant,
      microphoneEnabled: _enabled(participant, TrackSource.microphone),
      cameraEnabled: _enabled(participant, TrackSource.camera),
      screenShareEnabled: _enabled(participant, TrackSource.screenShareVideo),
      isSpeaking: participant.isSpeaking,
    );
  }

  MeetingMediaProviderEvent _stateEvent(
    Participant participant,
    TrackPublication? changed, {
    TrackSource? unpublishedSource,
  }) {
    return MeetingMediaProviderEvent(
      type: MeetingMediaProviderEventType.participantStateChanged,
      identity: participant.identity,
      displayName: participant.name,
      role: participant.permissions.canPublish
          ? MeetingParticipantRole.publisher
          : MeetingParticipantRole.viewer,
      isLocal: participant is LocalParticipant,
      microphoneEnabled: _enabled(
        participant,
        TrackSource.microphone,
        disabledSource: unpublishedSource,
      ),
      cameraEnabled: _enabled(
        participant,
        TrackSource.camera,
        disabledSource: unpublishedSource,
      ),
      screenShareEnabled: _enabled(
        participant,
        TrackSource.screenShareVideo,
        disabledSource: unpublishedSource,
      ),
      isSpeaking: participant.isSpeaking,
    );
  }

  void _onSpeakersChanged(ActiveSpeakersChangedEvent event) {
    final current = event.speakers
        .map((participant) => participant.identity)
        .toSet();
    for (final participant in event.speakers) {
      _emit(
        MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.activeSpeakerChanged,
          identity: participant.identity,
          isSpeaking: true,
        ),
      );
    }
    for (final identity in _speakers.difference(current)) {
      _emit(
        MeetingMediaProviderEvent(
          type: MeetingMediaProviderEventType.activeSpeakerChanged,
          identity: identity,
          isSpeaking: false,
        ),
      );
    }
    _speakers = current;
  }

  bool _enabled(
    Participant participant,
    TrackSource source, {
    TrackSource? disabledSource,
  }) =>
      source != disabledSource &&
      participant.trackPublications.values.any(
        (publication) => publication.source == source && !publication.muted,
      );

  String _trackKind(TrackSource source) => switch (source) {
    TrackSource.microphone => 'microphone',
    TrackSource.camera => 'camera',
    TrackSource.screenShareVideo ||
    TrackSource.screenShareAudio => 'screen_share',
    TrackSource.unknown => 'unknown',
  };

  void _emit(MeetingMediaProviderEvent event) {
    if (!_disposed) _events.add(event);
  }
}
