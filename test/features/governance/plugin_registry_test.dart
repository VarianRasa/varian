import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/governance/domain/plugin_registry.dart';

void main() {
  test('requires explicit permission review before enabling a plugin', () {
    final registry = PluginRegistry(clock: () => DateTime.utc(2026, 9, 14));
    const manifest = PluginManifest(
      id: 'network-exporter',
      name: 'Network Exporter',
      version: '1.0.0',
      permissions: [PluginPermission.export, PluginPermission.network],
      capabilities: [PluginCapability.export, PluginCapability.network],
    );

    final pending = registry.register(manifest);
    expect(pending.state, PluginRegistrationState.pendingReview);
    expect(
      registry.admitCommand(
        manifest.id,
        const PluginCommand(type: PluginCommandType.exportDocument),
      ),
      isFalse,
    );

    final enabled = registry.approve(
      manifest.id,
      permissions: manifest.permissions.toSet(),
    );
    expect(enabled.state, PluginRegistrationState.enabled);
    expect(
      registry.admitCommand(
        manifest.id,
        const PluginCommand(type: PluginCommandType.exportDocument),
      ),
      isTrue,
    );
  });

  test('blocks incompatible manifests and prevents permission escalation', () {
    final registry = PluginRegistry(clock: () => DateTime.utc(2026, 9, 14));
    const manifest = PluginManifest(
      id: 'bad-network',
      name: 'Bad Network',
      version: '1.0.0',
      apiVersion: '2.0',
      permissions: [],
      capabilities: [PluginCapability.network],
    );

    final blocked = registry.register(manifest);
    expect(blocked.state, PluginRegistrationState.blocked);
    expect(() => registry.enable(manifest.id), throwsStateError);
  });

  test('persists registry state and keeps disabled plugins unable to run', () {
    final registry = PluginRegistry(clock: () => DateTime.utc(2026, 9, 14));
    const manifest = PluginManifest(
      id: 'selection-helper',
      name: 'Selection Helper',
      version: '1.0.0',
      permissions: [PluginPermission.readSelection],
      capabilities: [PluginCapability.selection],
    );
    registry.register(manifest);
    registry.approve(manifest.id, permissions: manifest.permissions.toSet());
    registry.disable(manifest.id);

    final restored = PluginRegistry.fromJson(registry.toJson());
    expect(restored.find(manifest.id)?.state, PluginRegistrationState.disabled);
    expect(
      restored.canReadEvent(manifest.id, PluginEventType.selectionChanged),
      isFalse,
    );
    expect(restored.uninstall(manifest.id), isTrue);
    expect(restored.find(manifest.id), isNull);
  });

  test('enforces event, storage, and network sandbox limits', () {
    var now = DateTime.utc(2026, 9, 14);
    final registry = PluginRegistry(clock: () => now);
    const manifest = PluginManifest(
      id: 'bounded-plugin',
      name: 'Bounded Plugin',
      version: '1.0.0',
      permissions: [
        PluginPermission.listenEvents,
        PluginPermission.storage,
        PluginPermission.network,
      ],
      capabilities: [
        PluginCapability.events,
        PluginCapability.storage,
        PluginCapability.network,
      ],
      sandboxLimits: PluginSandboxLimits(
        maxEventSubscriptions: 1,
        maxStorageBytes: 10,
        maxNetworkRequestsPerMinute: 1,
      ),
    );
    registry.register(manifest);
    registry.approve(manifest.id, permissions: manifest.permissions.toSet());

    expect(
      registry.subscribeEvent(manifest.id, PluginEventType.selectionChanged),
      isTrue,
    );
    expect(
      registry.subscribeEvent(manifest.id, PluginEventType.documentChanged),
      isFalse,
    );
    expect(registry.reserveStorage(manifest.id, 8), isTrue);
    expect(registry.reserveStorage(manifest.id, 3), isFalse);
    expect(registry.admitNetworkRequest(manifest.id), isTrue);
    expect(registry.admitNetworkRequest(manifest.id), isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(registry.admitNetworkRequest(manifest.id), isTrue);
  });

  test(
    'rejects unknown permissions instead of granting a fallback permission',
    () {
      expect(
        () => PluginManifest.fromJson({
          'id': 'unknown-permission',
          'name': 'Unknown Permission',
          'version': '1.0.0',
          'permissions': ['readSelection', 'admin'],
        }),
        throwsFormatException,
      );
      expect(
        () => PluginRegistry.fromJson([
          {
            'manifest': {
              'id': 'unknown-approved',
              'name': 'Unknown Approved',
              'version': '1.0.0',
              'permissions': ['readSelection'],
            },
            'state': 'enabled',
            'approvedPermissions': ['admin'],
            'installedAt': '2026-09-14T00:00:00.000Z',
            'updatedAt': '2026-09-14T00:00:00.000Z',
          },
        ]),
        throwsFormatException,
      );
    },
  );

  test('requires exact permission-set approval before re-enabling', () {
    final registry = PluginRegistry(clock: () => DateTime.utc(2026, 9, 14));
    const manifest = PluginManifest(
      id: 'exact-approval',
      name: 'Exact Approval',
      version: '1.0.0',
      permissions: [PluginPermission.readSelection],
    );
    final pending = registry.register(manifest);
    final forged = pending.copyWith(
      state: PluginRegistrationState.disabled,
      approvedPermissions: {PluginPermission.network},
    );
    final restored = PluginRegistry(registrations: [forged]);
    expect(() => restored.enable(manifest.id), throwsStateError);
  });

  test(
    'does not run an enabled registration without exact persisted approval',
    () {
      final registry = PluginRegistry(clock: () => DateTime.utc(2026, 9, 14));
      const manifest = PluginManifest(
        id: 'missing-approval',
        name: 'Missing Approval',
        version: '1.0.0',
        permissions: [PluginPermission.writeNodes],
      );
      final pending = registry.register(manifest);
      final forged = pending.copyWith(state: PluginRegistrationState.enabled);
      final restored = PluginRegistry(registrations: [forged]);
      expect(
        restored.admitCommand(
          manifest.id,
          const PluginCommand(type: PluginCommandType.createNode),
        ),
        isFalse,
      );
    },
  );
}
