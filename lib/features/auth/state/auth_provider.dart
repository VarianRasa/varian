import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/supabase_bootstrap.dart';
import '../../../data/local/account_scoped_local_storage.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/remote/backend_config.dart';
import '../../../data/remote/supabase_app_config.dart';
import '../../../data/remote/supabase_service.dart';
import '../../canvas/state/autosave_controller.dart';
import '../../collaboration/state/collaboration_session_provider.dart';
import '../../meeting/state/meeting_controller.dart';
import '../../home/state/home_provider.dart';
import 'auth_recovery.dart';

final authUserProvider = StreamProvider<User?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return Stream<User?>.value(null);
  return (() async* {
    var previousUserId =
        client.auth.currentSession?.user.id ?? client.auth.currentUser?.id;
    var transitionGeneration = 0;
    yield client.auth.currentSession?.user ?? client.auth.currentUser;
    yield* client.auth.onAuthStateChange
        .map((change) {
          final nextUser = change.session?.user;
          final nextUserId = nextUser?.id;
          final previousAccountId = previousUserId;
          if (previousAccountId != null && previousAccountId != nextUserId) {
            final generation = ++transitionGeneration;
            unawaited(
              _cleanUpAccountTransition(
                ref,
                generation: generation,
                transitionGeneration: () => transitionGeneration,
                previousAccountId: previousAccountId,
              ),
            );
          }
          // Publish the new auth state before cleanup. Protected routes and
          // account controls must gate the new session immediately.
          previousUserId = nextUserId;
          return nextUser;
        })
        .handleError((_) {});
  })();
});

Future<void> _cleanUpAccountTransition(
  Ref ref, {
  required int generation,
  required int Function() transitionGeneration,
  required String previousAccountId,
}) async {
  try {
    // The outgoing account's local durable state must be fenced before account
    // cleanup or provider invalidation can discard the live autosave owner.
    final autosave = ref.read(autosaveControllerProvider);
    try {
      await autosave.flushDurable();
    } catch (error) {
      debugPrint('[Auth] Outgoing project durable flush failed: $error');
    }
    if (generation != transitionGeneration()) return;

    await discardActiveCollaborationCloudState(
      expectedAccountId: previousAccountId,
    );
    await clearAccountScopedAuthState(
      discardControllers: false,
      expectedAccountId: previousAccountId,
    );
    if (generation != transitionGeneration()) return;
    await invalidateAccountScopedProviders(ref);
  } catch (_) {
    // Auth publication remains authoritative even when cleanup is degraded.
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService.lazy(
    () => ref.read(supabaseClientProvider),
    bootstrap: defaultSupabaseBootstrap,
    flushDurable: () async {
      try {
        await ref.read(autosaveControllerProvider).flushDurable();
      } catch (error) {
        debugPrint('[Auth] Sign-out durable flush failed: $error');
      }
    },
  );
});

final authCallbackCoordinatorProvider =
    StateNotifierProvider<AuthCallbackCoordinator, AuthCallbackSnapshot>((ref) {
      final coordinator = AuthCallbackCoordinator(
        () => ref.read(supabaseClientProvider),
        ensureReady: () => defaultSupabaseBootstrap.ensureReady(explicit: true),
      );
      unawaited(coordinator.start());
      return coordinator;
    });

class AuthService {
  final SupabaseClient? _client;
  final SupabaseClient? Function()? _clientProvider;
  final SupabaseBootstrapController? _bootstrap;
  final Future<void> Function()? _flushDurable;

  const AuthService(this._client, {this._bootstrap, this._flushDurable})
    : _clientProvider = null;

  const AuthService.lazy(
    this._clientProvider, {
    this._bootstrap,
    this._flushDurable,
  }) : _client = null;

  SupabaseClient? get _currentClient => _clientProvider?.call() ?? _client;

  User? get currentUser => _currentClient?.auth.currentUser;

  bool get isConfigured => _currentClient != null;

  bool get canAttempt =>
      isConfigured ||
      _bootstrap?.state.status == SupabaseBootstrapStatus.deferred ||
      _bootstrap?.state.status == SupabaseBootstrapStatus.initializing;

  Future<void> signIn({required String email, required String password}) async {
    final client = await _requireClient();
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<bool> signUp({required String email, required String password}) async {
    final client = await _requireClient();
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
    );
    return response.session != null;
  }

  Future<void> sendPasswordReset(String email) async {
    final client = await _requireClient();
    await client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: SupabaseAppConfig.oauthRedirectUrl,
    );
  }

  Future<void> updatePassword(String password) async {
    final client = await _requireClient();
    await client.auth.updateUser(UserAttributes(password: password));
  }

  Future<bool> signInWithGoogle() async {
    final client = await _requireClient();
    return client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: SupabaseAppConfig.oauthRedirectUrl,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  static String friendlyError(Object error) {
    final message = error is AuthException
        ? error.message.toLowerCase()
        : error.toString().toLowerCase();
    if (message.contains('invalid login credentials') ||
        message.contains('invalid credentials')) {
      return 'Incorrect email or password.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirm your email address before signing in.';
    }
    if (message.contains('user already registered') ||
        message.contains('already been registered')) {
      return 'That email is already registered. Sign in instead.';
    }
    if (message.contains('rate limit') ||
        message.contains('too many') ||
        message.contains('for security purposes') ||
        message.contains('only request') ||
        message.contains('429')) {
      return 'Too many attempts. Try again in a moment.';
    }
    if (message.contains('expired') ||
        message.contains('invalid link') ||
        message.contains('link_invalid') ||
        message.contains('invalid grant')) {
      return 'This link is expired or invalid. Request a new one.';
    }
    if (message.contains('access denied') ||
        message.contains('access_denied')) {
      return 'This sign-in link was denied. Request a new one or try again.';
    }
    if (message.contains('authentication is unavailable') ||
        message.contains('cloud backend is not configured') ||
        message.contains('cloud services are unavailable')) {
      return 'Authentication is unavailable right now. Local projects remain available.';
    }
    if (message.contains('password should be at least') ||
        message.contains('password')) {
      return 'The password does not meet the requirements.';
    }
    if (message.contains('network') || message.contains('connection')) {
      return 'Connection problem. Check your internet and try again.';
    }
    return 'Authentication failed. Check your details and try again.';
  }

  static Duration? retryAfter(Object error) {
    final message = error is AuthException ? error.message : error.toString();
    final match = RegExp(
      r'(?:after|in)\s+(\d+)\s*(?:seconds?|secs?)',
      caseSensitive: false,
    ).firstMatch(message);
    final seconds = int.tryParse(match?.group(1) ?? '');
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds.clamp(30, 300).toInt());
  }

  static String friendlyErrorFor(Object error, String languageCode) {
    final english = friendlyError(error);
    if (!languageCode.toLowerCase().startsWith('id')) return english;
    return switch (english) {
      'Incorrect email or password.' => 'Email atau kata sandi salah.',
      'Confirm your email address before signing in.' =>
        'Konfirmasi alamat email sebelum masuk.',
      'That email is already registered. Sign in instead.' =>
        'Email tersebut sudah terdaftar. Silakan masuk.',
      'The password does not meet the requirements.' =>
        'Kata sandi tidak memenuhi persyaratan.',
      'Too many attempts. Try again in a moment.' =>
        'Terlalu banyak percobaan. Coba lagi sebentar.',
      'This sign-in link was denied. Request a new one or try again.' =>
        'Tautan masuk ditolak. Minta tautan baru atau coba lagi.',
      'Authentication is unavailable right now. Local projects remain available.' =>
        'Autentikasi sedang tidak tersedia. Proyek lokal tetap dapat digunakan.',
      'Connection problem. Check your internet and try again.' =>
        'Masalah koneksi. Periksa internet lalu coba lagi.',
      'This link is expired or invalid. Request a new one.' =>
        'Tautan ini kedaluwarsa atau tidak valid. Minta tautan baru.',
      _ => 'Autentikasi gagal. Periksa data Anda lalu coba lagi.',
    };
  }

  Future<void> signOut() async {
    final client = _currentClient;
    final outgoingAccountId =
        client?.auth.currentUser?.id ??
        client?.auth.currentSession?.user.id ??
        _currentSupabaseAccountId();
    // Clear any route saved by the outgoing flow before a replacement account
    // can publish a session. Owner matching preserves a path created later by
    // the replacement account. An anonymous flow is fenced by the scoped
    // cleanup below instead of clearing an active replacement path.
    if (outgoingAccountId != null) {
      await AuthReturnPathStore.clear(expectedOwner: outgoingAccountId);
    }
    await _flushDurable?.call();
    if (client == null) {
      await clearAccountScopedAuthState(expectedAccountId: outgoingAccountId);
      return;
    }
    try {
      await client.auth.signOut();
    } finally {
      // The auth stream may publish a replacement account before this remote
      // sign-out future completes. Fence cleanup to the outgoing account so a
      // late completion cannot erase the replacement account's state.
      await clearAccountScopedAuthState(expectedAccountId: outgoingAccountId);
    }
  }

  Future<SupabaseClient> _requireClient() async {
    var client = _currentClient;
    if (client == null && _bootstrap != null) {
      await _bootstrap.ensureReady(explicit: true);
      client = _currentClient;
    }
    if (client == null) {
      throw const AuthException('Authentication is unavailable right now.');
    }
    return client;
  }
}

Future<void> clearAccountScopedAuthState({
  bool discardControllers = true,
  String? expectedAccountId,
}) async {
  if (discardControllers) {
    await discardActiveCollaborationCloudState(
      expectedAccountId: expectedAccountId,
    );
  }
  clearWebBackendConfigSession();
  bool shouldClearUnscopedState() {
    // Unscoped cleanup is allowed only while the app is unauthenticated.
    // Each storage operation rechecks this fence around its own read/write.
    return _currentSupabaseAccountId() == null;
  }

  final shouldClear = expectedAccountId == null
      ? shouldClearUnscopedState
      : null;

  await Future.wait([
    _clearSafely(() async {
      if (shouldClear != null && !shouldClear()) return;
      await CollaborationRoomCache.clearAll(
        expectedAccountId: expectedAccountId,
      );
    }),
    _clearSafely(
      () => LocalStorageService().clearAccountScopedCollaborationMetadata(
        expectedAccountId: expectedAccountId,
        shouldClear: shouldClear,
      ),
    ),
    _clearSafely(
      () => LocalStorageService().clearAllAccountScopedCollaborationQueues(
        expectedAccountId: expectedAccountId,
        shouldClear: shouldClear,
      ),
    ),
    _clearSafely(
      () => clearAccountScopedBackendConfig(
        expectedAccountId: expectedAccountId,
        shouldClear: shouldClear,
      ),
    ),
    _clearSafely(() async {
      if (shouldClear != null && !shouldClear()) return;
      if (expectedAccountId == null) {
        await AuthReturnPathStore.clearIfUnauthenticated();
      } else {
        await AuthReturnPathStore.clear(expectedOwner: expectedAccountId);
      }
    }),
  ]);
}

String? _currentSupabaseAccountId() {
  try {
    final client = Supabase.instance.client;
    return client.auth.currentUser?.id ?? client.auth.currentSession?.user.id;
  } catch (_) {
    return null;
  }
}

Future<void> _clearSafely(Future<void> Function() operation) async {
  try {
    await operation();
  } catch (_) {
    // A local cleanup failure must not leave the signed-out shell blocked.
  }
}

Future<void> invalidateAccountScopedProviders(Ref ref) async {
  ref.invalidate(backendConfigProvider);
  ref.invalidate(supabaseSyncServiceProvider);
  ref.invalidate(autosaveControllerProvider);
  ref.invalidate(collaborationSessionProvider);
  ref.invalidate(meetingControllerProvider);
  ref.invalidate(homeProjectsProvider);
  await ref.read(homeProjectsProvider.notifier).loadProjects();
}

/// Keep provider invalidation deterministic after a deferred bootstrap.
void invalidateAuthProviders(WidgetRef ref) {
  ref.invalidate(supabaseClientProvider);
  ref.invalidate(authUserProvider);
}
