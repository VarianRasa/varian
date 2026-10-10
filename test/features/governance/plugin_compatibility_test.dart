import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/governance/domain/plugin_compatibility.dart';

void main() {
  test('round trips explicit plugin capabilities and sandbox limits', () {
    const manifest = PluginManifest(
      id: 'asset-panel',
      name: 'Asset Panel',
      version: '1.2.0',
      apiVersion: '1.0',
      permissions: [PluginPermission.readDocument, PluginPermission.storage],
      capabilities: [
        PluginCapability.document,
        PluginCapability.storage,
        PluginCapability.ui,
      ],
      uiExtensionPoints: ['panel'],
      sandboxLimits: PluginSandboxLimits(maxStorageBytes: 2048),
    );
    final restored = PluginManifest.fromJson(manifest.toJson());

    expect(restored.apiVersion, '1.0');
    expect(restored.supports(PluginCapability.storage), isTrue);
    expect(restored.sandboxLimits.maxStorageBytes, 2048);
    expect(PluginCompatibilityKit.evaluate(restored).compatible, isTrue);
  });

  test('rejects capability escalation and incompatible API versions', () {
    const manifest = PluginManifest(
      id: 'network-tool',
      name: 'Network Tool',
      version: '1.0.0',
      apiVersion: '2.0',
      permissions: [],
      capabilities: [PluginCapability.network],
    );
    final result = PluginCompatibilityKit.evaluate(manifest);

    expect(result.compatible, isFalse);
    expect(
      result.errors,
      contains('Network capability requires the network permission.'),
    );
    expect(
      result.errors.singleWhere((error) => error.contains('major 2.0')),
      isNotEmpty,
    );
  });

  test('compatibility kit examples remain valid', () {
    expect(
      PluginCompatibilityKit.exampleManifests()
          .map(PluginCompatibilityKit.evaluate)
          .every((result) => result.compatible),
      isTrue,
    );
  });

  test('plugin command gate enforces declared sandbox rate limit', () {
    var now = DateTime.utc(2026, 9, 13);
    const manifest = PluginManifest(
      id: 'limited-plugin',
      name: 'Limited Plugin',
      version: '1.0.0',
      permissions: [PluginPermission.writeNodes],
      capabilities: [PluginCapability.nodes],
      sandboxLimits: PluginSandboxLimits(maxCommandsPerMinute: 2),
    );
    final gate = PluginCommandGate(manifest.createSandbox(), clock: () => now);
    const command = PluginCommand(type: PluginCommandType.createNode);

    expect(gate.admit(command), isTrue);
    expect(gate.admit(command), isTrue);
    expect(gate.admit(command), isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(gate.admit(command), isTrue);
  });
}
