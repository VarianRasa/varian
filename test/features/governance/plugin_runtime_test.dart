import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/governance/domain/plugin_registry.dart';
import 'package:varian/features/governance/domain/plugin_runtime.dart';

void main() {
  final now = DateTime.utc(2026, 9, 14);

  PluginRegistry registry({
    PluginSandboxLimits limits = const PluginSandboxLimits(),
  }) {
    final registry = PluginRegistry(clock: () => now);
    registry.register(
      PluginManifest(
        id: 'runtime.test',
        name: 'Runtime test',
        version: '1.0.0',
        permissions: const [PluginPermission.writeNodes],
        sandboxLimits: limits,
      ),
    );
    registry.approve(
      'runtime.test',
      permissions: const {PluginPermission.writeNodes},
    );
    registry.enable('runtime.test');
    return registry;
  }

  test(
    'executes an admitted command through the bounded runtime host',
    () async {
      final host = PluginRuntimeHost(registry());
      final result = await host.execute(
        'runtime.test',
        const PluginCommand(type: PluginCommandType.createNode),
        handler: (context) async {
          expect(context.manifest.id, 'runtime.test');
          return {'created': true};
        },
      );

      expect(result.status, PluginExecutionStatus.completed);
      expect(result.payload['created'], isTrue);
    },
  );

  test('denies command without registration permission', () async {
    final host = PluginRuntimeHost(registry());
    final result = await host.execute(
      'runtime.test',
      const PluginCommand(type: PluginCommandType.exportDocument),
      handler: (_) => {'unexpected': true},
    );

    expect(result.status, PluginExecutionStatus.denied);
  });

  test('stops a plugin that exceeds its execution budget', () async {
    final host = PluginRuntimeHost(
      registry(limits: const PluginSandboxLimits(maxExecutionMillis: 5)),
    );
    final result = await host.execute(
      'runtime.test',
      const PluginCommand(type: PluginCommandType.createNode),
      handler: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return const {};
      },
    );

    expect(result.status, PluginExecutionStatus.timedOut);
  });

  test('signals cancellation to a cooperative plugin handler', () async {
    final cancellationObserved = Completer<void>();
    final host = PluginRuntimeHost(
      registry(limits: const PluginSandboxLimits(maxExecutionMillis: 5)),
    );
    final result = await host.execute(
      'runtime.test',
      const PluginCommand(type: PluginCommandType.createNode),
      handler: (context) async {
        while (!context.cancellation.isCancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        if (!cancellationObserved.isCompleted) cancellationObserved.complete();
        return const {};
      },
    );

    expect(result.status, PluginExecutionStatus.timedOut);
    await cancellationObserved.future.timeout(const Duration(seconds: 1));
  });
}
