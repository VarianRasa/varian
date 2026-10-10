import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import '../domain/settings_models.dart';

export '../data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

final settingsReadinessProvider = FutureProvider<void>((ref) async {
  await ref
      .read(settingsRepositoryProvider)
      .read<SettingsScope>(
        scope: SettingsScope.device,
        subjectId: 'runtime',
        fallback: SettingsScope.device,
        codec: const JsonSettingsCodec<SettingsScope>(
          encode: _encodeScope,
          decode: _decodeScope,
        ),
        setting: 'readiness',
      );
});

final settingsReadinessStateProvider = Provider<AsyncValue<void>>((ref) {
  return ref.watch(settingsReadinessProvider);
});

final settingsReadyProvider = Provider<bool>((ref) {
  return ref.watch(settingsReadinessProvider).hasValue;
});

final settingsReadinessErrorProvider = Provider<Object?>((ref) {
  return ref.watch(settingsReadinessProvider).error;
});

Object _encodeScope(SettingsScope scope) => scope.name;

SettingsScope _decodeScope(Object? raw) => SettingsScope.values.firstWhere(
  (scope) => scope.name == raw?.toString(),
  orElse: () => SettingsScope.device,
);
