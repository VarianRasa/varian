import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remote/supabase_app_config.dart';

/// Safe lifecycle states for optional cloud startup.
enum SupabaseBootstrapStatus {
  deferred,
  initializing,
  ready,
  unavailable,
  notConfigured,
}

class SupabaseBootstrapState {
  final SupabaseBootstrapStatus status;
  final String? diagnostic;

  const SupabaseBootstrapState({
    this.status = SupabaseBootstrapStatus.deferred,
    this.diagnostic,
  });

  bool get isReady => status == SupabaseBootstrapStatus.ready;

  bool get canRetry =>
      status == SupabaseBootstrapStatus.unavailable ||
      status == SupabaseBootstrapStatus.notConfigured;

  bool get canAttempt =>
      status == SupabaseBootstrapStatus.deferred ||
      status == SupabaseBootstrapStatus.initializing ||
      status == SupabaseBootstrapStatus.ready;
}

/// Initializes Supabase once, after the local first frame or when cloud/auth
/// work explicitly requests it. Failures remain visible but never block local
/// project actions.
class SupabaseBootstrapController extends ChangeNotifier {
  /// Optional deterministic initializer used by fault-injection tests and
  /// embedders that own the Supabase boundary. Production uses the built-in
  /// configuration path below.
  final Future<void> Function()? _initializeOverride;

  SupabaseBootstrapController({Future<void> Function()? initialize})
    : _initializeOverride = initialize;

  SupabaseBootstrapState _state = const SupabaseBootstrapState();
  Future<void>? _initialization;
  bool _deferredPending = false;
  bool _deferredCancelled = false;
  int _generation = 0;
  bool _disposed = false;

  SupabaseBootstrapState get state => _state;

  Future<void> get ready => _initialization ?? Future<void>.value();

  Future<void> beginAfterFirstFrame({
    Duration quietPeriod = const Duration(seconds: 1),
  }) {
    final existing = _initialization;
    if (existing != null) return existing;
    _deferredPending = true;
    _deferredCancelled = false;
    final generation = ++_generation;
    final future = _initializeAfterFirstFrame(quietPeriod, generation);
    _initialization = future;
    return future;
  }

  Future<void> _initializeAfterFirstFrame(
    Duration quietPeriod,
    int generation,
  ) async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (quietPeriod > Duration.zero) {
        await Future<void>.delayed(quietPeriod);
      }
      if (_deferredCancelled || generation != _generation) return;
      await _initialize(generation: generation);
    } finally {
      if (generation == _generation) _deferredPending = false;
    }
  }

  Future<void> ensureReady({bool explicit = false}) {
    final existing = _initialization;
    if (_state.status == SupabaseBootstrapStatus.initializing &&
        existing != null) {
      return existing;
    }
    final canRestart =
        _state.status == SupabaseBootstrapStatus.unavailable ||
        _state.status == SupabaseBootstrapStatus.notConfigured;
    if (explicit && (_deferredPending || canRestart)) {
      _deferredCancelled = true;
      _deferredPending = false;
      _initialization = null;
      final generation = ++_generation;
      final future = _initialize(generation: generation);
      _initialization = future;
      return future;
    }
    if (existing != null) return existing;
    final generation = ++_generation;
    final future = _initialize(generation: generation);
    _initialization = future;
    return future;
  }

  Future<void> retry() async {
    if (_state.status == SupabaseBootstrapStatus.initializing) {
      return ensureReady();
    }
    _initialization = null;
    _deferredPending = false;
    _deferredCancelled = false;
    _setState(const SupabaseBootstrapState());
    await ensureReady(explicit: true);
  }

  /// Lets a backend settings action publish the result of an explicit config
  /// initialization without starting a second concurrent initialization.
  void markReady() {
    _deferredCancelled = true;
    _deferredPending = false;
    _generation++;
    _initialization ??= Future<void>.value();
    _setState(
      const SupabaseBootstrapState(status: SupabaseBootstrapStatus.ready),
    );
  }

  void markUnavailable({String? diagnostic}) {
    // Keep manually supplied diagnostics bounded to known-safe text. Provider
    // exceptions can contain URLs, headers, or callback credentials.
    final safeDiagnostic = switch (diagnostic) {
      'Cloud authentication is not configured for this build.' => diagnostic,
      'Cloud services are unavailable right now.' => diagnostic,
      _ =>
        diagnostic == null ? null : 'Cloud services are unavailable right now.',
    };
    _setState(
      SupabaseBootstrapState(
        status: SupabaseBootstrapStatus.unavailable,
        diagnostic: safeDiagnostic,
      ),
    );
  }

  /// Resolves the effective public Supabase configuration without allowing a
  /// blank saved field to erase a valid compiled default. Runtime settings are
  /// intentionally considered only for debug/runtime-configurable builds.
  static ({String url, String publishableKey}) resolveConfiguration({
    required String compiledUrl,
    required String compiledPublishableKey,
    required String savedUrl,
    required String savedPublishableKey,
    required bool useSavedConfiguration,
  }) {
    final normalizedCompiledUrl = compiledUrl.trim();
    final normalizedCompiledKey = compiledPublishableKey.trim();
    final normalizedSavedUrl = savedUrl.trim();
    final normalizedSavedKey = savedPublishableKey.trim();
    return (
      url: useSavedConfiguration && normalizedSavedUrl.isNotEmpty
          ? normalizedSavedUrl
          : normalizedCompiledUrl,
      publishableKey: useSavedConfiguration && normalizedSavedKey.isNotEmpty
          ? normalizedSavedKey
          : normalizedCompiledKey,
    );
  }

  Future<void> _initialize({required int generation}) async {
    if (generation != _generation) return;
    _setState(
      const SupabaseBootstrapState(
        status: SupabaseBootstrapStatus.initializing,
      ),
    );
    try {
      final initializeOverride = _initializeOverride;
      if (initializeOverride != null) {
        await initializeOverride();
        if (generation != _generation) return;
        _setState(
          const SupabaseBootstrapState(status: SupabaseBootstrapStatus.ready),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('cfg_supabase_url') ?? '';
      final savedKey = prefs.getString('cfg_supabase_anon_key') ?? '';
      const useSavedSupabaseConfig =
          kDebugMode || SupabaseAppConfig.allowRuntimeConfiguration;
      final resolved = resolveConfiguration(
        compiledUrl: SupabaseAppConfig.url,
        compiledPublishableKey: SupabaseAppConfig.publishableKey,
        savedUrl: savedUrl,
        savedPublishableKey: savedKey,
        useSavedConfiguration: useSavedSupabaseConfig,
      );
      final url = resolved.url;
      final publishableKey = resolved.publishableKey;

      if (url.isEmpty || publishableKey.isEmpty) {
        if (generation != _generation) return;
        _setState(
          const SupabaseBootstrapState(
            status: SupabaseBootstrapStatus.notConfigured,
            diagnostic:
                'Cloud authentication is not configured for this build.',
          ),
        );
        return;
      }

      await Supabase.initialize(
        url: url,
        publishableKey: publishableKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          detectSessionInUri: false,
        ),
      );
      if (generation != _generation) return;
      _setState(
        const SupabaseBootstrapState(status: SupabaseBootstrapStatus.ready),
      );
    } catch (_) {
      if (generation != _generation) return;
      // Deliberately omit the provider exception and all URL/config values.
      _setState(
        const SupabaseBootstrapState(
          status: SupabaseBootstrapStatus.unavailable,
          diagnostic: 'Cloud services are unavailable right now.',
        ),
      );
    }
  }

  void _setState(SupabaseBootstrapState next) {
    if (_disposed ||
        (_state.status == next.status &&
            _state.diagnostic == next.diagnostic)) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final defaultSupabaseBootstrap = SupabaseBootstrapController();
