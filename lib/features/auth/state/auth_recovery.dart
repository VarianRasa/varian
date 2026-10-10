import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_url_cleanup.dart';

/// The callback categories that can be safely presented to the user.
///
/// Callback credentials are deliberately represented as booleans in
/// [AuthCallback]. The raw URI is used only for the one SDK exchange and is
/// never retained in application state or diagnostics.
enum AuthCallbackKind {
  none,
  signIn,
  passwordRecovery,
  accessDenied,
  expired,
  malformed,
}

class AuthCallback {
  final Uri uri;
  final AuthCallbackKind kind;
  final bool hasCode;
  final bool hasAccessToken;
  final String? safeReturnPath;
  final String? errorCode;
  final String? errorDescription;

  const AuthCallback({
    required this.uri,
    required this.kind,
    required this.hasCode,
    required this.hasAccessToken,
    required this.safeReturnPath,
    required this.errorCode,
    required this.errorDescription,
  });

  bool get isAuthCallback => kind != AuthCallbackKind.none;

  String get message => messageFor('en');

  String messageFor(String languageCode) => messageForKind(kind, languageCode);

  static String messageForKind(AuthCallbackKind kind, String languageCode) {
    final indonesian = languageCode.toLowerCase().startsWith('id');
    switch (kind) {
      case AuthCallbackKind.passwordRecovery:
        return indonesian
            ? 'Tautan pemulihan diterima. Buat kata sandi baru untuk melanjutkan.'
            : 'Recovery link accepted. Set a new password to continue.';
      case AuthCallbackKind.accessDenied:
        return indonesian
            ? 'Tautan masuk ditolak. Minta tautan baru atau coba lagi.'
            : 'This sign-in link was denied. Request a new link or try again.';
      case AuthCallbackKind.expired:
        return indonesian
            ? 'Tautan pemulihan tidak lagi valid. Minta tautan baru.'
            : 'This recovery link is no longer valid. Request a new one.';
      case AuthCallbackKind.malformed:
        return indonesian
            ? 'Tautan masuk tidak valid atau sudah digunakan. Minta tautan baru.'
            : 'This sign-in link is invalid or already used. Request a new link.';
      case AuthCallbackKind.signIn:
      case AuthCallbackKind.none:
        return '';
    }
  }

  @override
  String toString() =>
      'AuthCallback(kind: ${kind.name}, hasCode: $hasCode, '
      'hasAccessToken: $hasAccessToken, safeReturnPath: $safeReturnPath, '
      'errorCode: $errorCode)';
}

/// Parses callback metadata without exposing credentials or full callback URLs.
class AuthCallbackParser {
  const AuthCallbackParser._();

  static const _returnPathKeys = ['returnTo', 'next', 'redirectTo'];
  static const _safeReturnQueryKeys = [
    'projectId',
    'meetingId',
    'section',
    'embed',
    'stage',
    'roomId',
    'role',
  ];

  static AuthCallback parse(Uri uri) {
    final parameters = _parameters(uri);
    final hasCode = _usableCallbackValue(parameters['code']);
    final hasAccessToken = _usableCallbackValue(parameters['access_token']);
    final type = parameters['type']?.trim().toLowerCase();
    final error = parameters['error']?.trim().toLowerCase();
    final errorCode = parameters['error_code']?.trim().toLowerCase();
    final errorDescription = parameters['error_description']?.trim();
    final safeReturnPath = _firstSafeReturnPath(parameters);

    AuthCallbackKind kind;
    if (parameters['encoding_error'] == 'malformed' ||
        parameters['fragment_error'] == 'malformed') {
      kind = AuthCallbackKind.malformed;
    } else if (_isExpired(errorCode, error, errorDescription)) {
      // Provider errors are authoritative even when a callback also contains
      // stale credentials. Never route an expired recovery link to password
      // update just because a code or access token is present.
      kind = AuthCallbackKind.expired;
    } else if (error == 'access_denied' || errorCode == 'access_denied') {
      kind = AuthCallbackKind.accessDenied;
    } else if (_hasProviderError(errorCode, error, errorDescription)) {
      // Unknown provider errors must remain a safe error state rather than
      // being treated as a successful sign-in callback.
      kind = AuthCallbackKind.malformed;
    } else if ((type == 'recovery' || type == 'passwordrecovery') &&
        (hasCode || hasAccessToken)) {
      kind = AuthCallbackKind.passwordRecovery;
    } else if (hasCode || hasAccessToken) {
      kind = type == 'recovery'
          ? AuthCallbackKind.passwordRecovery
          : AuthCallbackKind.signIn;
    } else if (_looksLikeCallback(parameters)) {
      kind = AuthCallbackKind.malformed;
    } else {
      kind = AuthCallbackKind.none;
    }

    return AuthCallback(
      uri: cleanedUri(uri),
      kind: kind,
      hasCode: hasCode,
      hasAccessToken: hasAccessToken,
      safeReturnPath: safeReturnPath,
      errorCode: _safeErrorCode(errorCode ?? error),
      // Descriptions are third-party input and may contain credentials.
      errorDescription: null,
    );
  }

  /// Builds the short-lived URI that Supabase needs for its callback
  /// exchange. Flutter's hash-router puts callback parameters after the
  /// fragment (`/#/auth?code=...`), while GoTrue expects them in the query.
  /// Only documented auth fields are copied; return paths and arbitrary
  /// callback input never cross the SDK boundary.
  static Uri exchangeUri(Uri uri) {
    const exchangeKeys = {
      'code',
      'access_token',
      'refresh_token',
      'expires_in',
      'token_type',
      'provider_token',
      'provider_refresh_token',
      'type',
      'error',
      'error_code',
      'error_description',
    };
    final parameters = _parameters(uri);
    final exchangeParameters = <String, String>{};
    for (final key in exchangeKeys) {
      final value = parameters[key];
      if (value != null && value.isNotEmpty) {
        exchangeParameters[key] = value;
      }
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: exchangeParameters,
    );
  }

  /// Removes callback credentials and error details while preserving a safe
  /// local return path when one was supplied by the application.
  static Uri cleanedUri(Uri uri) {
    final parameters = _parameters(uri);
    final candidate = _firstSafeReturnPath(parameters);
    final cleaned = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: candidate == null ? const {} : {'returnTo': candidate},
      fragment: '',
    );
    return Uri.parse(_stripEmptySuffix(cleaned.toString()));
  }

  /// GoTrue uses the URL type `recovery` for implicit callbacks and the
  /// AuthChangeEvent name `passwordRecovery` for PKCE callbacks.
  static bool isPasswordRecoveryRedirectType(String? redirectType) {
    final normalized = redirectType?.trim().toLowerCase();
    return normalized == 'recovery' || normalized == 'passwordrecovery';
  }

  static String? _firstSafeReturnPath(Map<String, String> parameters) {
    for (final key in _returnPathKeys) {
      final path = _safeLocalPath(parameters[key]);
      if (path != null) return path;
    }
    return null;
  }

  static bool isAuthCallbackUri(Uri uri) => parse(uri).isAuthCallback;

  static String? safeLocalPath(String? value) => _safeLocalPath(value);

  static Map<String, String> _parameters(Uri uri) {
    final parameters = <String, String>{};
    try {
      parameters.addAll(uri.queryParameters);
    } on FormatException {
      parameters['encoding_error'] = 'malformed';
    } on ArgumentError {
      parameters['encoding_error'] = 'malformed';
    }
    if (_hasMalformedEncoding(uri.query)) {
      parameters['encoding_error'] = 'malformed';
    }
    if (uri.fragment.isEmpty) return parameters;
    final fragmentQuery = _fragmentQuery(uri.fragment);
    if (_hasMalformedEncoding(uri.fragment) ||
        _hasMalformedEncoding(fragmentQuery)) {
      parameters['encoding_error'] = 'malformed';
    }
    try {
      parameters.addAll(Uri.splitQueryString(fragmentQuery));
    } on FormatException {
      // A malformed fragment is still an auth-shaped callback and will be
      // rendered as a safe malformed-link state.
      parameters['fragment_error'] = 'malformed';
    } on ArgumentError {
      parameters['fragment_error'] = 'malformed';
    }
    if (parameters.values.any((value) => value.contains('\uFFFD'))) {
      parameters['encoding_error'] = 'malformed';
    }
    return parameters;
  }

  static String _fragmentQuery(String fragment) {
    final queryStart = fragment.indexOf('?');
    return queryStart < 0 ? fragment : fragment.substring(queryStart + 1);
  }

  static bool _hasMalformedEncoding(String value) {
    for (var index = 0; index < value.length; index++) {
      if (value.codeUnitAt(index) != 0x25) continue;
      if (index + 2 >= value.length ||
          !_isHexDigit(value.codeUnitAt(index + 1)) ||
          !_isHexDigit(value.codeUnitAt(index + 2))) {
        return true;
      }
      index += 2;
    }
    return false;
  }

  static bool _isHexDigit(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);

  static bool _looksLikeCallback(Map<String, String> parameters) =>
      parameters.keys.any(
        (key) =>
            key == 'type' ||
            key == 'error' ||
            key == 'error_code' ||
            key == 'error_description' ||
            key == 'code' ||
            key == 'access_token' ||
            key == 'refresh_token' ||
            key == 'expires_in' ||
            key == 'fragment_error' ||
            key == 'encoding_error',
      );

  static bool _hasProviderError(
    String? errorCode,
    String? error,
    String? description,
  ) => [
    errorCode,
    error,
    description,
  ].any((value) => value?.trim().isNotEmpty == true);

  static bool _isExpired(
    String? errorCode,
    String? error,
    String? description,
  ) {
    final value = [
      errorCode,
      error,
      description,
    ].whereType<String>().join(' ').toLowerCase();
    return value.contains('otp_expired') ||
        value.contains('expired') ||
        value.contains('invalid_grant') ||
        value.contains('link_invalid');
  }

  static String? _safeLocalPath(String? value) {
    final candidate = value?.trim();
    if (candidate == null ||
        candidate.isEmpty ||
        candidate.startsWith('//') ||
        candidate.codeUnits.any((code) => code <= 0x20 || code == 0x7f)) {
      return null;
    }
    final parsed = Uri.tryParse(candidate);
    if (parsed == null ||
        parsed.hasScheme ||
        parsed.hasAuthority ||
        !candidate.startsWith('/') ||
        candidate.startsWith('/\\') ||
        parsed.pathSegments.any(
          (segment) => segment == '..' || segment == '.',
        )) {
      return null;
    }
    final safeQuery = <String, List<String>>{};
    final queryParametersAll = <String, List<String>>{};
    try {
      queryParametersAll.addAll(parsed.queryParametersAll);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    for (final key in _safeReturnQueryKeys) {
      final values = queryParametersAll[key];
      if (values != null && values.isNotEmpty) {
        safeQuery[key] = values;
      }
    }
    return _stripEmptySuffix(
      Uri(
        path: parsed.path,
        queryParameters: safeQuery.map(
          (key, values) => MapEntry(
            key,
            values.length == 1 ? values.single : values.join(','),
          ),
        ),
      ).toString(),
    );
  }

  static String _stripEmptySuffix(String value) {
    var result = value;
    while (result.endsWith('?') || result.endsWith('#')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String? _safeErrorCode(String? value) {
    const allowed = {
      'access_denied',
      'invalid_grant',
      'invalid_request',
      'link_invalid',
      'otp_expired',
      'server_error',
      'temporarily_unavailable',
    };
    return value != null && allowed.contains(value) ? value : null;
  }

  static bool _usableCallbackValue(String? value) {
    final candidate = value?.trim();
    return candidate != null &&
        candidate.isNotEmpty &&
        !candidate.contains('%') &&
        !candidate.contains(RegExp(r'[\u0000-\u001f\u007f\s]'));
  }
}

final passwordResetCooldownProvider = Provider<PasswordResetCooldown>((ref) {
  return PasswordResetCooldown();
});

class PasswordResetCooldown {
  static const _defaultDuration = Duration(seconds: 30);
  static const _maximumDuration = Duration(minutes: 5);

  final Duration duration;
  DateTime? _startedAt;
  late Duration _activeDuration = _safeDuration;

  PasswordResetCooldown({this.duration = _defaultDuration});

  Duration get _safeDuration {
    if (duration <= Duration.zero) return _defaultDuration;
    if (duration > _maximumDuration) return _maximumDuration;
    return duration;
  }

  bool get isActive => remainingAt(DateTime.now()) > Duration.zero;

  Duration remainingAt(DateTime now) {
    final startedAt = _startedAt;
    if (startedAt == null) return Duration.zero;
    final elapsed = now.difference(startedAt);
    final remaining = _activeDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool tryStart({DateTime? now, Duration? retryAfter}) {
    final current = now ?? DateTime.now();
    if (remainingAt(current) > Duration.zero) return false;
    final requested = retryAfter ?? _safeDuration;
    _activeDuration = requested < _safeDuration
        ? _safeDuration
        : requested > _maximumDuration
        ? _maximumDuration
        : requested;
    _startedAt = current;
    return true;
  }

  void clear() {
    _startedAt = null;
    _activeDuration = _safeDuration;
  }
}

class AuthReturnPathStore {
  const AuthReturnPathStore._();

  static const _key = 'auth_return_path';
  static const _ownerKey = 'auth_return_path_owner';
  static const _envelopeVersion = 1;
  static Future<void>? _writeQueue;

  static Future<T> _enqueue<T>(Future<T> Function() operation) async {
    final previous = _writeQueue ?? Future<void>.value();
    final next = previous.then((_) => operation());
    final queued = next.then<void>((_) {}).catchError((_) {});
    _writeQueue = queued;
    try {
      return await next;
    } finally {
      if (identical(_writeQueue, queued)) _writeQueue = null;
    }
  }

  /// Stores a sanitized route and, once known, the account that initiated it.
  /// The path and owner are written as one JSON value so a process interruption
  /// cannot expose an ownerless replacement route. Legacy two-key values are
  /// still read and removed after a successful envelope write.
  static Future<void> save(String? path, {String? ownerAccountId}) {
    return _enqueue(() async {
      final safePath = AuthCallbackParser.safeLocalPath(path);
      final owner = ownerAccountId?.trim();
      final prefs = await SharedPreferences.getInstance();
      if (safePath == null) {
        await prefs.remove(_key);
        await prefs.remove(_ownerKey);
        return;
      }
      await prefs.setString(
        _key,
        jsonEncode({
          'version': _envelopeVersion,
          'path': safePath,
          if (owner != null && owner.isNotEmpty) 'owner': owner,
        }),
      );
      await prefs.remove(_ownerKey);
    });
  }

  static Future<String?> consume({String? accountId}) {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final saved = _read(prefs);
      final normalizedAccountId = accountId?.trim();
      if (saved.owner != null &&
          normalizedAccountId != null &&
          normalizedAccountId != saved.owner) {
        return null;
      }
      await prefs.remove(_key);
      await prefs.remove(_ownerKey);
      return saved.path;
    });
  }

  static Future<void> clear({String? expectedOwner}) {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final saved = _read(prefs);
      final normalizedExpectedOwner = expectedOwner?.trim();
      if (normalizedExpectedOwner != null &&
          normalizedExpectedOwner.isNotEmpty &&
          (saved.owner == null || saved.owner != normalizedExpectedOwner)) {
        // An account-fenced cleanup must never remove an ownerless path that a
        // replacement account may have saved during the switch.
        return;
      }
      await prefs.remove(_key);
      await prefs.remove(_ownerKey);
    });
  }

  /// Clears an explicitly handled route only when it is still the same
  /// sanitized path saved by this auth flow. This prevents a late callback or
  /// sign-out cleanup from deleting a replacement account's newer path.
  static Future<void> clearIfMatches(String? path, {String? expectedOwner}) {
    return _enqueue(() async {
      final safePath = AuthCallbackParser.safeLocalPath(path);
      if (safePath == null) return;
      final prefs = await SharedPreferences.getInstance();
      final saved = _read(prefs);
      if (saved.path != safePath) return;

      final normalizedExpectedOwner = expectedOwner?.trim();
      if (normalizedExpectedOwner != null &&
          normalizedExpectedOwner.isNotEmpty &&
          (saved.owner == null || saved.owner != normalizedExpectedOwner)) {
        return;
      }
      await prefs.remove(_key);
      await prefs.remove(_ownerKey);
    });
  }

  /// Clears an ownerless route only while the Supabase session is absent.
  /// The session is checked before and after reading preferences so a late
  /// sign-out cleanup cannot erase a route saved by a replacement account.
  static Future<void> clearIfUnauthenticated() {
    return _enqueue(() async {
      if (_hasActiveSession()) return;
      final prefs = await SharedPreferences.getInstance();
      if (_hasActiveSession()) return;
      final saved = _read(prefs);
      if (saved.owner != null && saved.owner!.isNotEmpty) return;
      if (_hasActiveSession()) return;
      await prefs.remove(_key);
      await prefs.remove(_ownerKey);
    });
  }

  static bool _hasActiveSession() {
    try {
      final client = Supabase.instance.client;
      return client.auth.currentSession != null ||
          client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  static _AuthReturnPathValue _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['version'] == _envelopeVersion) {
          final path = AuthCallbackParser.safeLocalPath(
            decoded['path'] as String?,
          );
          final owner = decoded['owner'] as String?;
          final normalizedOwner = owner?.trim();
          if (path != null &&
              (normalizedOwner == null || normalizedOwner.isNotEmpty)) {
            return _AuthReturnPathValue(
              path: path,
              owner: normalizedOwner?.isEmpty == true ? null : normalizedOwner,
            );
          }
        }
      } catch (_) {
        // Fall through to the legacy representation and clear on consume.
      }
    }
    return _AuthReturnPathValue(
      path: AuthCallbackParser.safeLocalPath(raw),
      owner: prefs.getString(_ownerKey)?.trim().isNotEmpty == true
          ? prefs.getString(_ownerKey)!.trim()
          : null,
    );
  }
}

enum AuthCallbackStatus { idle, processing, recovery, signedIn, error }

class AuthCallbackSnapshot {
  final AuthCallbackStatus status;
  final AuthCallbackKind kind;
  final String? message;
  final String? returnPath;
  final int eventId;

  const AuthCallbackSnapshot({
    this.status = AuthCallbackStatus.idle,
    this.kind = AuthCallbackKind.none,
    this.message,
    this.returnPath,
    this.eventId = 0,
  });

  AuthCallbackSnapshot copyWith({
    AuthCallbackStatus? status,
    AuthCallbackKind? kind,
    String? message,
    String? returnPath,
    int? eventId,
    bool clearMessage = false,
    bool clearReturnPath = false,
  }) => AuthCallbackSnapshot(
    status: status ?? this.status,
    kind: kind ?? this.kind,
    message: clearMessage ? null : message ?? this.message,
    returnPath: clearReturnPath ? null : returnPath ?? this.returnPath,
    eventId: eventId ?? this.eventId,
  );
}

/// Owns callback exchange for the app. Supabase URI detection is disabled so
/// this coordinator can clear handled URL parameters and render failures
/// without a duplicate SDK/custom callback race.
class _AuthReturnPathValue {
  final String? path;
  final String? owner;

  const _AuthReturnPathValue({required this.path, required this.owner});
}

class AuthCallbackCoordinator extends StateNotifier<AuthCallbackSnapshot> {
  final SupabaseClient? Function() _clientProvider;
  final Future<void> Function()? _ensureReady;
  StreamSubscription<Uri>? _linkSubscription;
  final Set<String> _handledCallbackKeys = <String>{};
  bool _started = false;
  bool _processing = false;
  int _eventSequence = 0;

  int _nextEventId() => ++_eventSequence;

  AuthCallbackCoordinator(this._clientProvider, {this._ensureReady})
    : super(const AuthCallbackSnapshot());

  Future<void> start({bool force = false}) async {
    if (_started && !force) return;
    if (force) {
      await _linkSubscription?.cancel();
      _linkSubscription = null;
    }
    _started = true;

    if (kIsWeb) {
      await handle(currentAuthUri());
      return;
    }

    final appLinks = AppLinks();
    _linkSubscription = appLinks.uriLinkStream.listen((uri) {
      unawaited(handle(uri));
    });
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) await handle(initialUri);
    } catch (_) {
      // A platform without an initial URI remains usable for local work.
    }
  }

  Future<void> handle(Uri uri) async {
    final callback = AuthCallbackParser.parse(uri);
    if (!callback.isAuthCallback || _processing) return;
    final callbackKey = _callbackKey(uri);
    if (_handledCallbackKeys.contains(callbackKey)) {
      await clearHandledAuthUrl();
      state = AuthCallbackSnapshot(
        status: AuthCallbackStatus.error,
        kind: AuthCallbackKind.malformed,
        message:
            'This sign-in link is invalid or already used. Request a new link.',
        eventId: _nextEventId(),
      );
      return;
    }
    _rememberCallback(callbackKey);

    _processing = true;
    state = AuthCallbackSnapshot(
      status: AuthCallbackStatus.processing,
      kind: callback.kind,
      eventId: _nextEventId(),
    );
    try {
      if (callback.kind == AuthCallbackKind.accessDenied ||
          callback.kind == AuthCallbackKind.expired ||
          callback.kind == AuthCallbackKind.malformed) {
        await clearHandledAuthUrl();
        state = AuthCallbackSnapshot(
          status: AuthCallbackStatus.error,
          kind: callback.kind,
          message: callback.message,
          eventId: _nextEventId(),
        );
        return;
      }

      var client = _clientProvider();
      final ensureReady = _ensureReady;
      if (client == null && ensureReady != null) {
        await ensureReady();
        client = _clientProvider();
      }
      if (client == null) {
        await clearHandledAuthUrl();
        state = AuthCallbackSnapshot(
          status: AuthCallbackStatus.error,
          kind: AuthCallbackKind.malformed,
          message:
              'Cloud authentication is unavailable. Local projects remain available.',
          eventId: _nextEventId(),
        );
        return;
      }

      final response = await client.auth.getSessionFromUrl(
        AuthCallbackParser.exchangeUri(uri),
      );
      await clearHandledAuthUrl();
      final accountId = response.session.user.id;
      final isRecovery =
          callback.kind == AuthCallbackKind.passwordRecovery ||
          AuthCallbackParser.isPasswordRecoveryRedirectType(
            response.redirectType,
          );
      if (isRecovery) {
        if (callback.safeReturnPath != null) {
          await AuthReturnPathStore.save(
            callback.safeReturnPath,
            ownerAccountId: accountId,
          );
        }
        state = AuthCallbackSnapshot(
          status: AuthCallbackStatus.recovery,
          kind: AuthCallbackKind.passwordRecovery,
          message: callback.message,
          eventId: _nextEventId(),
        );
      } else {
        state = AuthCallbackSnapshot(
          status: AuthCallbackStatus.signedIn,
          kind: AuthCallbackKind.signIn,
          returnPath:
              await AuthReturnPathStore.consume(accountId: accountId) ??
              callback.safeReturnPath,
          eventId: _nextEventId(),
        );
      }
    } on AuthException catch (error) {
      await clearHandledAuthUrl();
      final kind = _kindForAuthError(error);
      state = AuthCallbackSnapshot(
        status: AuthCallbackStatus.error,
        kind: kind,
        message: AuthCallback(
          uri: AuthCallbackParser.cleanedUri(uri),
          kind: kind,
          hasCode: callback.hasCode,
          hasAccessToken: callback.hasAccessToken,
          safeReturnPath: callback.safeReturnPath,
          errorCode: null,
          errorDescription: null,
        ).message,
        eventId: _nextEventId(),
      );
    } catch (_) {
      await clearHandledAuthUrl();
      state = AuthCallbackSnapshot(
        status: AuthCallbackStatus.error,
        kind: AuthCallbackKind.malformed,
        message: 'This sign-in link could not be verified. Request a new one.',
        eventId: _nextEventId(),
      );
    } finally {
      _processing = false;
    }
  }

  void dismiss() {
    if (state.status == AuthCallbackStatus.idle) return;
    state = const AuthCallbackSnapshot();
  }

  String _callbackKey(Uri uri) =>
      sha256.convert(utf8.encode(uri.toString())).toString();

  void _rememberCallback(String key) {
    if (_handledCallbackKeys.length >= 32) {
      _handledCallbackKeys.remove(_handledCallbackKeys.first);
    }
    _handledCallbackKeys.add(key);
  }

  static AuthCallbackKind _kindForAuthError(AuthException error) {
    final code = '${error.code ?? ''} ${error.statusCode ?? ''}'.toLowerCase();
    final message = error.message.toLowerCase();
    if (code.contains('access_denied') || message.contains('access denied')) {
      return AuthCallbackKind.accessDenied;
    }
    if (code.contains('otp_expired') ||
        code.contains('expired') ||
        message.contains('expired') ||
        message.contains('invalid grant')) {
      return AuthCallbackKind.expired;
    }
    return AuthCallbackKind.malformed;
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }
}

Future<void> clearHandledAuthUrl() => clearHandledAuthUrlPlatform();
