import 'dart:async';

import '../../../domain/models/workspace_governance.dart';
import 'plugin_registry.dart';

enum PluginExecutionStatus { completed, denied, timedOut, failed }

class PluginExecutionCancelled implements Exception {
  const PluginExecutionCancelled();

  @override
  String toString() => 'Plugin execution was cancelled.';
}

class PluginExecutionCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const PluginExecutionCancelled();
  }
}

class PluginExecutionResult {
  final PluginExecutionStatus status;
  final Map<String, dynamic> payload;
  final String? error;
  final Duration elapsed;

  const PluginExecutionResult({
    required this.status,
    this.payload = const {},
    this.error,
    this.elapsed = Duration.zero,
  });

  bool get succeeded => status == PluginExecutionStatus.completed;
}

class PluginRuntimeContext {
  final String pluginId;
  final PluginManifest manifest;
  final PluginRegistry registry;
  final PluginExecutionCancellation cancellation;

  PluginRuntimeContext({
    required this.pluginId,
    required this.manifest,
    required this.registry,
    PluginExecutionCancellation? cancellation,
  }) : cancellation = cancellation ?? PluginExecutionCancellation();

  bool reserveStorage(int bytes) {
    cancellation.throwIfCancelled();
    return registry.reserveStorage(pluginId, bytes);
  }

  bool admitNetworkRequest() {
    cancellation.throwIfCancelled();
    return registry.admitNetworkRequest(pluginId);
  }

  bool subscribeEvent(PluginEventType event) {
    cancellation.throwIfCancelled();
    return registry.subscribeEvent(pluginId, event);
  }

  bool canReadEvent(PluginEventType event) {
    cancellation.throwIfCancelled();
    return registry.canReadEvent(pluginId, event);
  }

  void throwIfCancelled() => cancellation.throwIfCancelled();
}

typedef PluginCommandHandler =
    FutureOr<Map<String, dynamic>> Function(PluginRuntimeContext context);

class PluginRuntimeHost {
  final PluginRegistry registry;
  final DateTime Function() clock;

  PluginRuntimeHost(this.registry, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  Future<PluginExecutionResult> execute(
    String pluginId,
    PluginCommand command, {
    required PluginCommandHandler handler,
  }) async {
    final startedAt = clock().toUtc();
    final registration = registry.find(pluginId);
    if (registration == null || !registry.admitCommand(pluginId, command)) {
      return PluginExecutionResult(
        status: PluginExecutionStatus.denied,
        error: 'Plugin is not enabled or command permission is missing.',
        elapsed: clock().toUtc().difference(startedAt),
      );
    }

    final timeout = Duration(
      milliseconds: registration.manifest.sandboxLimits.maxExecutionMillis,
    );
    final cancellation = PluginExecutionCancellation();
    final cancellationTimer = Timer(timeout, cancellation.cancel);
    try {
      final payload = await Future<Map<String, dynamic>>.sync(
        () => handler(
          PluginRuntimeContext(
            pluginId: pluginId,
            manifest: registration.manifest,
            registry: registry,
            cancellation: cancellation,
          ),
        ),
      ).timeout(timeout);
      cancellation.throwIfCancelled();
      return PluginExecutionResult(
        status: PluginExecutionStatus.completed,
        payload: Map<String, dynamic>.unmodifiable(payload),
        elapsed: clock().toUtc().difference(startedAt),
      );
    } on TimeoutException {
      cancellation.cancel();
      return PluginExecutionResult(
        status: PluginExecutionStatus.timedOut,
        error: 'Plugin execution exceeded ${timeout.inMilliseconds} ms.',
        elapsed: clock().toUtc().difference(startedAt),
      );
    } on PluginExecutionCancelled {
      // A cooperative handler may observe the cancellation timer before the
      // Future.timeout callback wins the race. Both outcomes are the same
      // bounded execution result, not a plugin failure.
      return PluginExecutionResult(
        status: PluginExecutionStatus.timedOut,
        error: 'Plugin execution exceeded ${timeout.inMilliseconds} ms.',
        elapsed: clock().toUtc().difference(startedAt),
      );
    } catch (error) {
      return PluginExecutionResult(
        status: PluginExecutionStatus.failed,
        error: '$error',
        elapsed: clock().toUtc().difference(startedAt),
      );
    } finally {
      cancellationTimer.cancel();
    }
  }
}
