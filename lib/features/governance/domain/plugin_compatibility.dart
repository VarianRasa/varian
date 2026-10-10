import '../../../domain/models/workspace_governance.dart';

class PluginCompatibilityResult {
  final bool compatible;
  final List<String> errors;
  final List<String> warnings;

  const PluginCompatibilityResult({
    required this.compatible,
    this.errors = const [],
    this.warnings = const [],
  });
}

class PluginCompatibilityKit {
  PluginCompatibilityKit._();

  static const currentApiVersion = '1.0';

  static PluginCompatibilityResult evaluate(PluginManifest manifest) {
    final errors = [...manifest.validate()];
    final warnings = <String>[];
    final requestedMajor = int.tryParse(manifest.apiVersion.split('.').first);
    final currentMajor = int.parse(currentApiVersion.split('.').first);
    if (requestedMajor != null && requestedMajor != currentMajor) {
      errors.add(
        'Plugin API major ${manifest.apiVersion} is incompatible with $currentApiVersion.',
      );
    }
    if (manifest.capabilities.isEmpty) {
      warnings.add(
        'Plugin uses permission-derived capabilities; declare capabilities explicitly.',
      );
    }
    if (manifest.uiExtensionPoints.isNotEmpty &&
        !manifest.supports(PluginCapability.ui)) {
      errors.add('UI extension points require the ui capability.');
    }
    return PluginCompatibilityResult(
      compatible: errors.isEmpty,
      errors: List.unmodifiable(errors),
      warnings: List.unmodifiable(warnings),
    );
  }

  static List<PluginManifest> exampleManifests() => [
    const PluginManifest(
      id: 'selection-helper',
      name: 'Selection Helper',
      version: '1.0.0',
      apiVersion: currentApiVersion,
      permissions: [PluginPermission.readSelection],
      capabilities: [PluginCapability.selection],
    ),
    const PluginManifest(
      id: 'export-panel',
      name: 'Export Panel',
      version: '1.0.0',
      apiVersion: currentApiVersion,
      permissions: [PluginPermission.export],
      capabilities: [PluginCapability.export, PluginCapability.ui],
      uiExtensionPoints: ['panel'],
    ),
  ];
}

class PluginCommandGate {
  final PluginSandbox sandbox;
  final DateTime Function() clock;
  int _commandsInWindow = 0;
  DateTime _windowStarted;

  PluginCommandGate(this.sandbox, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now,
      _windowStarted = (clock ?? DateTime.now)().toUtc();

  bool admit(PluginCommand command) {
    if (!sandbox.canRun(command)) return false;
    final now = clock().toUtc();
    if (now.difference(_windowStarted) >= const Duration(minutes: 1)) {
      _windowStarted = now;
      _commandsInWindow = 0;
    }
    if (_commandsInWindow >=
        sandbox.manifest.sandboxLimits.maxCommandsPerMinute) {
      return false;
    }
    _commandsInWindow++;
    return true;
  }
}
