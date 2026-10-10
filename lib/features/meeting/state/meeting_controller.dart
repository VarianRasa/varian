import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/remote/supabase_service.dart';
import '../data/livekit_meeting_media.dart';
import '../data/meeting_configuration.dart';
import '../data/meeting_media_port.dart';
import '../data/meeting_repository.dart';
import '../domain/meeting_errors.dart';
import '../domain/meeting_models.dart';

final meetingConfigurationProvider = Provider<MeetingConfiguration>((ref) {
  return MeetingConfiguration.fromEnvironment();
});

final meetingRepositoryProvider = Provider.family<MeetingRepository, String>(
  (ref, _) => MeetingRepository(ref.watch(supabaseClientProvider)),
);

final meetingMediaPortProvider = Provider.family<MeetingMediaPort, String>(
  (ref, _) => LiveKitMeetingMedia(),
);

final meetingControllerProvider = StateNotifierProvider.autoDispose
    .family<MeetingController, MeetingState, String>((ref, projectId) {
      final controller = MeetingController(
        projectId: projectId,
        repository: ref.watch(meetingRepositoryProvider(projectId)),
        media: ref.read(meetingMediaPortProvider(projectId)),
        configuration: ref.read(meetingConfigurationProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

class MeetingControllerException implements Exception {
  const MeetingControllerException(this.code);

  final MeetingErrorCode code;
  String get message => MeetingErrorMessage.forCode(code);

  @override
  String toString() => 'MeetingControllerException: $message';
}

class MeetingController extends StateNotifier<MeetingState> {
  MeetingController({
    required String projectId,
    required this._repository,
    required this._media,
    MeetingConfiguration? configuration,
  }) : _configuration = configuration ?? MeetingConfiguration.fromEnvironment(),
       super(MeetingState.initial(projectId: projectId.trim())) {
    _bindMediaEvents();
  }

  final MeetingRepository _repository;
  final MeetingMediaPort _media;
  final MeetingConfiguration _configuration;
  StreamSubscription<MeetingMediaEvent>? _mediaSubscription;
  StreamSubscription<MeetingSession>? _sessionSubscription;
  Future<MeetingSession>? _startFuture;
  final Map<String, Future<void>> _joinFutures = <String, Future<void>>{};
  int _generation = 0;
  bool _disposed = false;
  bool _cleaning = false;
  int? _cleaningGeneration;
  bool _leaving = false;
  bool _terminalized = false;
  bool _suppressMediaEvents = false;
  bool _canPublish = false;
  String? _localIdentity;
  bool _tokenRefreshInFlight = false;
  int? _tokenRefreshGeneration;
  int _reconnectAttempts = 0;
  Stopwatch? _joinStopwatch;
  bool _mediaCleaned = false;
  Future<void>? _cleanupFuture;
  Future<void>? _terminalFuture;
  Future<void>? _leaveFuture;
  Future<void>? _endFuture;
  String? _pendingMeetingId;
  final Map<String, Future<void>> _removeFutures = {};

  void _bindMediaEvents() {
    if (_mediaSubscription != null || _disposed) return;
    _mediaSubscription = _media.events.listen(
      _handleMediaEvent,
      onError: (_, _) => _handleProviderError(),
    );
  }

  @override
  MeetingState get state => super.state;

  Future<MeetingSession> startMeeting({int maxParticipants = 8}) {
    if (_startFuture != null) return _startFuture!;
    if (_disposed) {
      return Future.error(
        const MeetingControllerException(MeetingErrorCode.unavailable),
      );
    }
    if (_activeSession != null) return Future.value(_activeSession!);
    final operation = _performStart(maxParticipants);
    _startFuture = operation;
    operation.then<void>(
      (_) {
        if (identical(_startFuture, operation)) {
          _startFuture = null;
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_startFuture, operation)) {
          _startFuture = null;
        }
      },
    );
    return operation;
  }

  Future<void> join({required String meetingId}) {
    final key = meetingId.trim().toLowerCase();
    final existing = _joinFutures[key];
    if (existing != null) return existing;
    if (_disposed) {
      return Future.error(
        const MeetingControllerException(MeetingErrorCode.unavailable),
      );
    }
    final operation = _performJoin(meetingId);
    _joinFutures[key] = operation;
    operation.then<void>(
      (_) {
        if (identical(_joinFutures[key], operation)) {
          _joinFutures.remove(key);
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_joinFutures[key], operation)) {
          _joinFutures.remove(key);
        }
      },
    );
    return operation;
  }

  Future<void> toggleMicrophone() => _toggle(
    state.localMicrophoneEnabled,
    _media.setMicrophoneEnabled,
    (value) => state.copyWith(localMicrophoneEnabled: value),
  );

  Future<void> toggleCamera() => _toggle(
    state.localCameraEnabled,
    _media.setCameraEnabled,
    (value) => state.copyWith(localCameraEnabled: value),
  );

  Future<void> toggleScreenShare() => _toggle(
    state.localScreenShareEnabled,
    _media.setScreenShareEnabled,
    (value) => state.copyWith(localScreenShareEnabled: value),
  );

  Future<void> leave() {
    final existing = _leaveFuture;
    if (existing != null) return existing;
    final terminal = _terminalFuture;
    final operation = terminal == null
        ? _performLeave()
        : terminal.then<void>((_) => _performLeave());
    _leaveFuture = operation;
    operation.whenComplete(() {
      if (identical(_leaveFuture, operation)) _leaveFuture = null;
    });
    return operation;
  }

  Future<void> _performLeave() async {
    if (_disposed || _leaving) return;
    _leaving = true;
    state = state.copyWith(actionInFlight: true);
    final generation = ++_generation;
    _cleaning = false;
    _cleaningGeneration = null;
    _startFuture = null;
    _joinFutures.clear();
    _endFuture = null;
    _removeFutures.clear();
    _pendingMeetingId = null;
    _tokenRefreshGeneration = null;
    _tokenRefreshInFlight = false;
    try {
      await _cancelSessionSubscription();
      await _disconnectIntentionally();
      if (!_isCurrent(generation)) return;
      state = MeetingState.initial(projectId: state.projectId);
      _terminalized = false;
      _localIdentity = null;
      _canPublish = false;
    } finally {
      _leaving = false;
    }
  }

  Future<void> handleExternalTermination(MeetingTerminationReason reason) {
    if (_disposed) return Future<void>.value();
    final existing = _terminalFuture;
    if (existing != null) return existing;
    if (_terminalized || _cleaning) return Future<void>.value();
    if (state.meetingId == null && _pendingMeetingId == null) {
      return Future<void>.value();
    }
    final code = _codeForTermination(reason);
    return _terminal(code, reason: reason);
  }

  Future<void> endForEveryone({String reason = 'host_ended'}) {
    final existing = _endFuture;
    if (existing != null) return existing;
    final operation = _performEndForEveryone(reason);
    _endFuture = operation;
    operation.whenComplete(() {
      if (identical(_endFuture, operation)) _endFuture = null;
    });
    return operation;
  }

  Future<void> _performEndForEveryone(String reason) async {
    if (_leaving ||
        _terminalized ||
        _cleaning ||
        state.actionInFlight ||
        !_ensureReady() ||
        !state.isHost ||
        state.meetingId == null ||
        (state.status != MeetingStatus.connected &&
            state.status != MeetingStatus.reconnecting)) {
      return;
    }
    final generation = _generation;
    final meetingId = state.meetingId!;
    state = state.copyWith(actionInFlight: true);
    try {
      final ended = await _repository.endMeeting(
        meetingId: meetingId,
        reason: reason,
      );
      if (!_isCurrent(generation) || state.meetingId != meetingId) return;
      final terminationReason =
          ended.endedReason ?? _reasonForEndWireValue(reason);
      await _terminal(
        _codeForTermination(terminationReason),
        reason: terminationReason,
        terminalSession: ended,
      );
    } on MeetingRepositoryException catch (error) {
      if (_isCurrent(generation) && state.meetingId == meetingId) {
        _setError(error.code);
      }
    } catch (_) {
      if (_isCurrent(generation) && state.meetingId == meetingId) {
        _setError(MeetingErrorCode.providerUnavailable);
      }
    } finally {
      if (_isCurrent(generation) && state.meetingId == meetingId) {
        state = state.copyWith(actionInFlight: false);
      }
    }
  }

  Future<void> removeParticipant(String identity) {
    final key = identity.trim().toLowerCase();
    final existing = _removeFutures[key];
    if (existing != null) return existing;
    final operation = _performRemoveParticipant(identity);
    _removeFutures[key] = operation;
    operation.whenComplete(() {
      if (identical(_removeFutures[key], operation)) _removeFutures.remove(key);
    });
    return operation;
  }

  Future<void> _performRemoveParticipant(String identity) async {
    if (_leaving ||
        _terminalized ||
        _cleaning ||
        state.actionInFlight ||
        !_ensureReady() ||
        !state.isHost ||
        state.meetingId == null ||
        (state.status != MeetingStatus.connected &&
            state.status != MeetingStatus.reconnecting)) {
      return;
    }
    final generation = _generation;
    final meetingId = state.meetingId!;
    state = state.copyWith(actionInFlight: true);
    try {
      await _repository.removeParticipant(
        meetingId: meetingId,
        identity: identity,
      );
    } on MeetingRepositoryException catch (error) {
      if (_isCurrent(generation) && state.meetingId == meetingId) {
        _setError(error.code);
      }
    } catch (_) {
      if (_isCurrent(generation) && state.meetingId == meetingId) {
        _setError(MeetingErrorCode.providerUnavailable);
      }
    } finally {
      if (_isCurrent(generation) && state.meetingId == meetingId) {
        state = state.copyWith(actionInFlight: false);
      }
    }
  }

  Future<void> disposeAsync() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _leaving = true;
    ++_generation;
    _cleaning = false;
    _cleaningGeneration = null;
    _startFuture = null;
    _joinFutures.clear();
    _terminalFuture = null;
    _endFuture = null;
    _removeFutures.clear();
    await _cancelSessionSubscription();
    await _cancelMediaSubscription();
    await _cleanupMedia();
    await _media.dispose();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    unawaited(disposeAsync());
    super.dispose();
  }

  MeetingSession? get _activeSession =>
      _leaving ||
          state.session == null ||
          (state.status != MeetingStatus.creating &&
              state.status != MeetingStatus.joining &&
              state.status != MeetingStatus.connected &&
              state.status != MeetingStatus.reconnecting)
      ? null
      : state.session;

  Future<MeetingSession> _performStart(int maxParticipants) async {
    final generation = _generation;
    if (_leaving || _terminalized || _cleaning || !_ensureReady()) {
      throw const MeetingControllerException(MeetingErrorCode.unavailable);
    }
    _pendingMeetingId = '';
    _terminalized = false;
    _bindMediaEvents();
    state = state.copyWith(
      status: MeetingStatus.creating,
      errorCode: null,
      errorMessage: null,
      terminationReason: null,
      canPublish: false,
      isHost: false,
    );
    try {
      final session = await _repository.createMeeting(
        projectId: state.projectId,
        maxParticipants: maxParticipants,
      );
      return await _connectSession(session, generation, MeetingStatus.creating);
    } on MeetingControllerException catch (error) {
      await _abortFailedConnection(generation, error.code);
      rethrow;
    } on MeetingRepositoryException catch (error) {
      await _abortFailedConnection(generation, error.code);
      throw MeetingControllerException(error.code);
    } catch (_) {
      await _abortFailedConnection(
        generation,
        MeetingErrorCode.providerUnavailable,
      );
      throw const MeetingControllerException(
        MeetingErrorCode.providerUnavailable,
      );
    } finally {
      if (_isCurrent(generation)) _pendingMeetingId = null;
    }
  }

  Future<void> _performJoin(String meetingId) async {
    final generation = _generation;
    if (_leaving || _terminalized || _cleaning || !_ensureReady()) {
      throw const MeetingControllerException(MeetingErrorCode.unavailable);
    }
    if (state.session != null && _activeSession != null) {
      throw const MeetingControllerException(MeetingErrorCode.unavailable);
    }
    _pendingMeetingId = meetingId.trim();
    _terminalized = false;
    _bindMediaEvents();
    _joinStopwatch = Stopwatch()..start();
    _logEvent('join_started');
    state = state.copyWith(
      status: MeetingStatus.joining,
      errorCode: null,
      errorMessage: null,
      terminationReason: null,
      canPublish: false,
      isHost: false,
    );
    try {
      final session = await _repository.joinMeeting(meetingId: meetingId);
      await _connectSession(session, generation, MeetingStatus.joining);
    } on MeetingControllerException catch (error) {
      await _abortFailedConnection(generation, error.code);
      rethrow;
    } on MeetingRepositoryException catch (error) {
      await _abortFailedConnection(generation, error.code);
      throw MeetingControllerException(error.code);
    } catch (_) {
      await _abortFailedConnection(
        generation,
        MeetingErrorCode.providerUnavailable,
      );
      throw const MeetingControllerException(
        MeetingErrorCode.providerUnavailable,
      );
    } finally {
      if (_isCurrent(generation)) _pendingMeetingId = null;
    }
  }

  Future<MeetingSession> _connectSession(
    MeetingSession session,
    int generation,
    MeetingStatus connectingStatus,
  ) async {
    if (!_isCurrent(generation) || _terminalized || session.isEnded) {
      throw const MeetingControllerException(MeetingErrorCode.ended);
    }
    state = state.copyWith(
      meetingId: session.id,
      session: session,
      status: connectingStatus,
      isHost: false,
      canPublish: false,
    );
    final credentials = await _repository.requestToken(meetingId: session.id);
    if (!_isCurrent(generation)) {
      throw const MeetingControllerException(MeetingErrorCode.unavailable);
    }
    _localIdentity = credentials.identity;
    await _watchSession(session.id, generation);
    if (!_isCurrent(generation) ||
        _terminalized ||
        state.meetingId != session.id) {
      throw const MeetingControllerException(MeetingErrorCode.unavailable);
    }
    _mediaCleaned = false;
    await _media.connect(credentials: credentials);
    if (!_isCurrent(generation)) {
      await _media.disconnect();
      throw const MeetingControllerException(MeetingErrorCode.unavailable);
    }
    _canPublish = _media.canPublish;
    final isHost =
        credentials.identity.toLowerCase() == session.createdBy.toLowerCase();
    state = state.copyWith(canPublish: _canPublish, isHost: isHost);
    await _applyDefaultLocalState(generation);
    if (!_isCurrent(generation)) {
      throw const MeetingControllerException(MeetingErrorCode.unavailable);
    }
    state = state.copyWith(status: MeetingStatus.connected);
    final elapsedMs = _joinStopwatch?.elapsedMilliseconds;
    _joinStopwatch = null;
    _logEvent('join_completed', elapsedMs: elapsedMs);
    return session;
  }

  Future<void> _applyDefaultLocalState(int generation) async {
    if (!_isCurrent(generation) || !_canPublish) {
      return;
    }
    await _media.setMicrophoneEnabled(false);
    await _media.setCameraEnabled(false);
    await _media.setScreenShareEnabled(false);
  }

  Future<void> _watchSession(String meetingId, int generation) async {
    await _cancelSessionSubscription();
    if (!_isCurrent(generation)) {
      return;
    }
    _sessionSubscription = _repository
        .watchMeeting(meetingId)
        .listen(
          (session) {
            if (_leaving ||
                !_isCurrent(generation) ||
                state.meetingId != meetingId) {
              return;
            }
            state = state.copyWith(session: session);
            if (session.isEnded) {
              unawaited(
                _terminal(
                  _codeForTermination(session.endedReason),
                  reason: session.endedReason,
                  terminalSession: session,
                ),
              );
            }
          },
          onError: (_, _) {
            if (_isCurrent(generation) && state.meetingId == meetingId) {
              unawaited(
                _terminal(
                  MeetingErrorCode.providerUnavailable,
                  reason: MeetingTerminationReason.providerError,
                ),
              );
            }
          },
        );
  }

  Future<void> _toggle(
    bool current,
    Future<void> Function(bool) command,
    MeetingState Function(bool) update,
  ) async {
    if (_leaving ||
        !_ensureReady() ||
        !_canPublish ||
        state.status != MeetingStatus.connected) {
      return;
    }
    final generation = _generation;
    try {
      await command(!current);
      if (_isCurrent(generation) && state.status == MeetingStatus.connected) {
        state = update(!current);
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        _setNonterminalError(MeetingErrorCode.providerUnavailable);
      }
    }
  }

  Future<void> _handleTokenRefresh() async {
    if (_tokenRefreshInFlight) return;
    final generation = _generation;
    final meetingId = state.meetingId;
    if (meetingId == null ||
        _terminalized ||
        (state.status != MeetingStatus.connected &&
            state.status != MeetingStatus.reconnecting)) {
      return;
    }
    _tokenRefreshInFlight = true;
    _tokenRefreshGeneration = generation;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!_isCurrent(generation) ||
            _tokenRefreshGeneration != generation ||
            state.meetingId != meetingId) {
          return;
        }
        try {
          final credentials = await _repository.requestToken(
            meetingId: meetingId,
          );
          await _media.updateToken(credentials: credentials);
          if (_isCurrent(generation) &&
              _tokenRefreshGeneration == generation &&
              state.meetingId == meetingId) {
            state = state.copyWith(errorCode: null, errorMessage: null);
          }
          return;
        } catch (_) {
          if (!_isCurrent(generation) ||
              _tokenRefreshGeneration != generation ||
              state.meetingId != meetingId) {
            return;
          }
          if (attempt == 2) {
            _setNonterminalError(MeetingErrorCode.providerUnavailable);
            return;
          }
          await Future<void>.delayed(Duration(milliseconds: 100 << attempt));
          if (!_isCurrent(generation) ||
              _tokenRefreshGeneration != generation ||
              state.meetingId != meetingId) {
            return;
          }
        }
      }
    } finally {
      if (_tokenRefreshGeneration == generation) {
        _tokenRefreshGeneration = null;
        _tokenRefreshInFlight = false;
      }
    }
  }

  void _handleMediaEvent(MeetingMediaEvent event) {
    if (_disposed ||
        _leaving ||
        _suppressMediaEvents ||
        _terminalized ||
        state.meetingId == null ||
        (state.status != MeetingStatus.creating &&
            state.status != MeetingStatus.joining &&
            state.status != MeetingStatus.connected &&
            state.status != MeetingStatus.reconnecting)) {
      return;
    }
    switch (event.type) {
      case MeetingMediaEventType.connectionChanged:
        _handleConnection(event.status ?? MeetingStatus.error);
      case MeetingMediaEventType.localMediaChanged:
        state = state.copyWith(
          localMicrophoneEnabled: event.microphoneEnabled,
          localCameraEnabled: event.cameraEnabled,
          localScreenShareEnabled: event.screenShareEnabled,
        );
      case MeetingMediaEventType.participantJoined:
        final participant = event.participant;
        if (participant != null && participant.identity.isNotEmpty) {
          state = state.copyWith(
            participants: {
              ...state.participants,
              participant.identity: participant,
            },
          );
        }
      case MeetingMediaEventType.participantLeft:
        final identity = event.participantIdentity;
        if (identity != null) {
          if (_localIdentity != null &&
              identity.toLowerCase() == _localIdentity!.toLowerCase()) {
            unawaited(
              handleExternalTermination(MeetingTerminationReason.removed),
            );
            return;
          }
          final participants = {...state.participants}..remove(identity);
          state = state.copyWith(participants: participants);
        }
      case MeetingMediaEventType.trackSubscribed:
      case MeetingMediaEventType.trackUnsubscribed:
        _updateTrackState(event);
      case MeetingMediaEventType.activeSpeakerChanged:
        _updateSpeaker(event);
      case MeetingMediaEventType.tokenRefreshRequested:
        unawaited(_handleTokenRefresh());
      case MeetingMediaEventType.providerError:
        final errorCode =
            event.errorCode ?? MeetingErrorCode.providerUnavailable;
        final terminalProviderError =
            errorCode == MeetingErrorCode.ended ||
            errorCode == MeetingErrorCode.removed;
        if (state.status == MeetingStatus.connected && !terminalProviderError) {
          _setNonterminalError(errorCode);
        } else {
          unawaited(_terminal(errorCode, reason: _reasonForCode(errorCode)));
        }
    }
  }

  void _handleConnection(MeetingStatus status) {
    if (status == MeetingStatus.reconnecting) {
      _reconnectAttempts++;
      _logEvent('reconnecting', attempt: _reconnectAttempts);
      state = state.copyWith(status: status);
    } else if (status == MeetingStatus.connected) {
      _logEvent('connected', attempt: _reconnectAttempts);
      _reconnectAttempts = 0;
      state = state.copyWith(
        status: status,
        errorCode: null,
        errorMessage: null,
      );
    } else if (status == MeetingStatus.ended || status == MeetingStatus.error) {
      unawaited(
        _terminal(
          status == MeetingStatus.ended
              ? MeetingErrorCode.ended
              : MeetingErrorCode.providerUnavailable,
          reason: status == MeetingStatus.ended
              ? MeetingTerminationReason.ended
              : MeetingTerminationReason.providerError,
        ),
      );
    } else {
      state = state.copyWith(status: status);
    }
  }

  void _updateTrackState(MeetingMediaEvent event) {
    final identity = event.participantIdentity;
    final kind = event.trackKind;
    if (identity == null || kind == null) {
      return;
    }
    final current =
        state.participants[identity] ??
        MeetingParticipant(
          identity: identity,
          displayName: '',
          role: MeetingParticipantRole.viewer,
        );
    final enabled = event.type == MeetingMediaEventType.trackSubscribed;
    final participant = switch (kind) {
      'microphone' || 'audio' => current.copyWith(microphoneEnabled: enabled),
      'camera' || 'video' => current.copyWith(cameraEnabled: enabled),
      'screen_share' ||
      'screen_share_video' ||
      'screen_share_audio' => current.copyWith(screenShareEnabled: enabled),
      _ => current,
    };
    state = state.copyWith(
      participants: {...state.participants, identity: participant},
    );
  }

  void _updateSpeaker(MeetingMediaEvent event) {
    final identity = event.participantIdentity;
    if (identity == null) {
      return;
    }
    final current =
        state.participants[identity] ??
        MeetingParticipant(
          identity: identity,
          displayName: '',
          role: MeetingParticipantRole.viewer,
        );
    state = state.copyWith(
      participants: {
        ...state.participants,
        identity: current.copyWith(isSpeaking: event.isSpeaking ?? false),
      },
    );
  }

  MeetingErrorCode _codeForTermination(MeetingTerminationReason? reason) =>
      switch (reason) {
        MeetingTerminationReason.removed => MeetingErrorCode.removed,
        MeetingTerminationReason.ended => MeetingErrorCode.ended,
        MeetingTerminationReason.roomRevoked ||
        MeetingTerminationReason.expired ||
        MeetingTerminationReason.providerError =>
          MeetingErrorCode.providerUnavailable,
        null => MeetingErrorCode.ended,
      };

  Future<void> _terminal(
    MeetingErrorCode code, {
    MeetingTerminationReason? reason,
    MeetingSession? terminalSession,
  }) {
    if (_disposed) return Future<void>.value();
    final existing = _terminalFuture;
    if (existing != null) return existing;
    if (_terminalized) return Future<void>.value();
    final operation = _performTerminal(
      code,
      reason: reason ?? _reasonForCode(code),
      terminalSession: terminalSession,
    );
    _terminalFuture = operation;
    operation.whenComplete(() {
      if (identical(_terminalFuture, operation)) _terminalFuture = null;
    });
    return operation;
  }

  Future<void> _performTerminal(
    MeetingErrorCode code, {
    required MeetingTerminationReason reason,
    MeetingSession? terminalSession,
  }) async {
    if (_disposed || _terminalized) return;
    _cleaning = true;
    _terminalized = true;
    _pendingMeetingId = null;
    _tokenRefreshGeneration = null;
    _tokenRefreshInFlight = false;
    final terminalGeneration = ++_generation;
    _cleaningGeneration = terminalGeneration;
    _endFuture = null;
    _removeFutures.clear();
    final preservedSession =
        terminalSession ??
        (state.session?.isEnded == true ? state.session : null);
    try {
      await _cancelSessionSubscription();
      await _cancelMediaSubscription();
      await _disconnectIntentionally();
      if (!_disposed && _isCurrent(terminalGeneration)) {
        final ended =
            code == MeetingErrorCode.ended || code == MeetingErrorCode.removed;
        state = state.copyWith(
          meetingId: null,
          session: ended ? preservedSession : null,
          status: ended ? MeetingStatus.ended : MeetingStatus.error,
          participants: const {},
          localMicrophoneEnabled: false,
          localCameraEnabled: false,
          localScreenShareEnabled: false,
          canPublish: false,
          isHost: false,
          actionInFlight: false,
          errorCode: code == MeetingErrorCode.ended ? null : code,
          errorMessage: code == MeetingErrorCode.ended
              ? null
              : MeetingErrorMessage.forCode(code),
          terminationReason: reason,
        );
      }
      _localIdentity = null;
      _canPublish = false;
      _logEvent('terminal', reason: reason.toWire());
    } finally {
      if (_cleaningGeneration == terminalGeneration) {
        _cleaning = false;
        _cleaningGeneration = null;
      }
    }
  }

  MeetingTerminationReason _reasonForEndWireValue(String value) =>
      switch (value) {
        'room_revoked' => MeetingTerminationReason.roomRevoked,
        'expired' => MeetingTerminationReason.expired,
        _ => MeetingTerminationReason.ended,
      };

  MeetingTerminationReason _reasonForCode(MeetingErrorCode code) =>
      switch (code) {
        MeetingErrorCode.ended => MeetingTerminationReason.ended,
        MeetingErrorCode.removed => MeetingTerminationReason.removed,
        _ => MeetingTerminationReason.providerError,
      };

  void _logEvent(String event, {String? reason, int? attempt, int? elapsedMs}) {
    final fields = <String>[
      'event=$event',
      if (reason != null) 'reason=$reason',
      if (attempt != null) 'attempt=$attempt',
      if (elapsedMs != null) 'elapsed_ms=$elapsedMs',
    ];
    developer.log(fields.join(' '), name: 'meeting.lifecycle');
  }

  Future<void> _cancelSessionSubscription() async {
    final subscription = _sessionSubscription;
    _sessionSubscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      // A stale watcher must not block terminal cleanup.
    }
  }

  Future<void> _cancelMediaSubscription() async {
    final subscription = _mediaSubscription;
    _mediaSubscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      // A stale provider stream must not block terminal cleanup.
    }
  }

  Future<void> _disconnectIntentionally() async {
    _suppressMediaEvents = true;
    try {
      await _cleanupMedia();
    } finally {
      _suppressMediaEvents = false;
    }
  }

  Future<void> _cleanupMedia() {
    if (_mediaCleaned) return Future<void>.value();
    final existing = _cleanupFuture;
    if (existing != null) return existing;
    final operation = _performCleanupMedia();
    _cleanupFuture = operation;
    operation.whenComplete(() {
      if (identical(_cleanupFuture, operation)) _cleanupFuture = null;
    });
    return operation;
  }

  Future<void> _performCleanupMedia() async {
    try {
      await _media.disconnect();
    } catch (_) {
      // Cleanup is best effort; provider errors must not resurrect the meeting.
    } finally {
      _mediaCleaned = true;
    }
  }

  bool _ensureReady() {
    if (_disposed ||
        state.projectId.trim().isEmpty ||
        !_configuration.isAvailable) {
      _setError(MeetingErrorCode.unavailable);
      return false;
    }
    return true;
  }

  Future<void> _abortFailedConnection(
    int generation,
    MeetingErrorCode code,
  ) async {
    if (!_isCurrent(generation)) return;
    _suppressMediaEvents = true;
    try {
      await _cancelSessionSubscription();
      await _cleanupMedia();
    } finally {
      _suppressMediaEvents = false;
    }
    _clearFailedConnectionIfCurrent(generation, code);
  }

  void _clearFailedConnectionIfCurrent(int generation, MeetingErrorCode code) {
    if (!_isCurrent(generation)) return;
    state = state.copyWith(
      meetingId: null,
      session: null,
      participants: const {},
      localMicrophoneEnabled: false,
      localCameraEnabled: false,
      localScreenShareEnabled: false,
      status: MeetingStatus.error,
      errorCode: code,
      errorMessage: MeetingErrorMessage.forCode(code),
      actionInFlight: false,
    );
  }

  void _setNonterminalError(MeetingErrorCode code) {
    if (_disposed) return;
    state = state.copyWith(
      errorCode: code,
      errorMessage: MeetingErrorMessage.forCode(code),
    );
  }

  void _setError(MeetingErrorCode code) {
    if (_disposed) {
      return;
    }
    state = state.copyWith(
      status: MeetingStatus.error,
      errorCode: code,
      errorMessage: MeetingErrorMessage.forCode(code),
      actionInFlight: false,
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _handleProviderError() {
    if (_disposed ||
        _leaving ||
        _terminalized ||
        (state.meetingId == null && _pendingMeetingId == null)) {
      return;
    }
    unawaited(
      _terminal(
        MeetingErrorCode.providerUnavailable,
        reason: MeetingTerminationReason.providerError,
      ),
    );
  }
}
