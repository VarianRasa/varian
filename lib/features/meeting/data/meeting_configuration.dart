/// Client-safe settings for the optional video meeting provider.
///
/// Provider credentials and meeting tokens are intentionally not part of this
/// configuration. Tokens are issued by the server when the meeting feature is
/// enabled.
class MeetingConfiguration {
  static const featureFlagEnvironmentKey = 'VIDEO_MEETING_ENABLED';
  static const providerUrlEnvironmentKey = 'LIVEKIT_URL';
  static const participantLimitEnvironmentKey =
      'VIDEO_MEETING_MAX_PARTICIPANTS';

  static const minParticipants = 2;
  static const maxParticipantsLimit = 8;
  static const defaultMaxParticipants = maxParticipantsLimit;

  final bool isEnabled;
  final String serverUrl;
  final int maxParticipants;

  MeetingConfiguration({
    required this.isEnabled,
    required String serverUrl,
    required int maxParticipants,
  }) : serverUrl = serverUrl.trim(),
       maxParticipants = _normalizeParticipantLimit(maxParticipants);

  /// Reads compile-time configuration unless [environment] is provided.
  ///
  /// The optional map is a client-safe override for callers that need to
  /// evaluate configuration values without compile-time defines.
  factory MeetingConfiguration.fromEnvironment({
    Map<String, String>? environment,
  }) {
    final enabled = environment == null
        ? const String.fromEnvironment(
            featureFlagEnvironmentKey,
            defaultValue: 'false',
          )
        : environment[featureFlagEnvironmentKey] ?? 'false';
    final providerUrl = environment == null
        ? const String.fromEnvironment(
            providerUrlEnvironmentKey,
            defaultValue: '',
          )
        : environment[providerUrlEnvironmentKey] ?? '';
    final participantLimit = environment == null
        ? const String.fromEnvironment(
            participantLimitEnvironmentKey,
            defaultValue: '8',
          )
        : environment[participantLimitEnvironmentKey] ??
              '$defaultMaxParticipants';

    return MeetingConfiguration(
      isEnabled: _parseEnabled(enabled),
      serverUrl: providerUrl,
      maxParticipants:
          int.tryParse(participantLimit.trim()) ?? defaultMaxParticipants,
    );
  }

  /// Whether the client has both the rollout flag and a provider endpoint.
  bool get isAvailable => isEnabled && serverUrl.isNotEmpty;

  static bool _parseEnabled(String value) =>
      value.trim().toLowerCase() == 'true';

  static int _normalizeParticipantLimit(int value) =>
      value >= minParticipants && value <= maxParticipantsLimit
      ? value
      : defaultMaxParticipants;
}
