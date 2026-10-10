import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/workspace_governance.dart';
import '../../settings/domain/settings_models.dart';
import '../../settings/state/settings_controller.dart';
import '../domain/accessibility_contract.dart';

const _legacyAccessibilityKey = 'cfg_accessibility_settings';
const _accessibilitySubject = 'runtime';

final accessibilitySettingsProvider =
    StateNotifierProvider<AccessibilitySettingsNotifier, AccessibilitySettings>(
      (ref) {
        final repository = ref.watch(settingsRepositoryProvider);
        return AccessibilitySettingsNotifier(repository);
      },
    );

final accessibilitySettingsReadyProvider = FutureProvider<void>((ref) async {
  await ref.read(accessibilitySettingsProvider.notifier).ready;
});

class AccessibilitySettingsNotifier
    extends StateNotifier<AccessibilitySettings> {
  AccessibilitySettingsNotifier(this._repository)
    : super(const AccessibilitySettings()) {
    ready = _load();
  }

  final SettingsRepository _repository;
  int _revision = 0;
  bool _ready = false;
  bool _userChanged = false;
  Future<void> _writeQueue = Future<void>.value();
  late final Future<void> ready;

  Future<void> _load() async {
    try {
      final envelope = await _repository.readWithLegacyJson(
        scope: SettingsScope.device,
        subjectId: _accessibilitySubject,
        fallback: const AccessibilitySettings(),
        codec: const AccessibilitySettingsCodec(),
        legacyKey: _legacyAccessibilityKey,
        setting: 'accessibility',
      );
      _revision = envelope.revision;
      if (!mounted || _userChanged) return;
      state = AccessibilityProfile(settings: envelope.value).normalized();
    } catch (error) {
      debugPrint('[Accessibility] Could not load saved settings: $error');
    } finally {
      _ready = true;
    }
  }

  Future<void> update(AccessibilitySettings settings) async {
    final normalized = AccessibilityProfile(settings: settings).normalized();
    final previous = state;
    _userChanged = true;
    state = normalized;
    final operation = _writeQueue.then((_) async {
      try {
        await ready;
        final envelope = await _repository.write(
          envelope: SettingsEnvelope<AccessibilitySettings>(
            schemaVersion: SettingsRepository.schemaVersion,
            scope: SettingsScope.device,
            subjectId: _accessibilitySubject,
            revision: _revision,
            updatedAt: DateTime.now().toUtc(),
            value: normalized,
          ),
          codec: const AccessibilitySettingsCodec(),
          expectedRevision: _revision,
          setting: 'accessibility',
        );
        _revision = envelope.revision;
      } catch (error) {
        if (mounted) state = previous;
        debugPrint('[Accessibility] Could not save settings: $error');
      }
    });
    _writeQueue = operation.catchError((_) {});
    await operation;
  }

  /// Exposed for readiness-aware screens and diagnostics without making the
  /// provider's async initialization part of the app-wide settings authority.
  bool get isReady => _ready;
}
