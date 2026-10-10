/// Short-lived media access returned by the authenticated meeting boundary.
///
/// The raw provider token and server URL remain private to this data/media
/// boundary. Pass this object to [MeetingMediaPort] instead of copying token
/// fields into controller state or domain models.
final class MeetingMediaCredentials {
  const MeetingMediaCredentials._(
    this._token,
    this._serverUrl, {
    required this.expiresAt,
    required this.identity,
  });

  factory MeetingMediaCredentials.fromProviderValues({
    required String token,
    required String serverUrl,
    required DateTime expiresAt,
    required String identity,
  }) => MeetingMediaCredentials._(
    token,
    serverUrl,
    expiresAt: expiresAt,
    identity: identity,
  );

  final String _token;
  final String _serverUrl;
  final DateTime expiresAt;
  final String identity;

  /// Runs provider work without exposing credential fields to callers.
  Future<T> use<T>(
    Future<T> Function({required String serverUrl, required String token})
    operation,
  ) => operation(serverUrl: _serverUrl, token: _token);

  Future<T> useToken<T>(Future<T> Function(String token) operation) =>
      operation(_token);
}
