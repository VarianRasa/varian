import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/state/auth_provider.dart';
import '../features/settings/state/settings_controller.dart';
import '../features/settings/domain/settings_models.dart';

ThemeMode nextThemeMode(ThemeMode mode) => switch (mode) {
  ThemeMode.system => ThemeMode.light,
  ThemeMode.light => ThemeMode.dark,
  ThemeMode.dark => ThemeMode.system,
};

String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

const _legacyThemeModeKey = 'app_theme_mode';
const _themeSubject = 'runtime';

String _themeSubjectFor(User? user) =>
    user?.id.trim().isNotEmpty == true ? user!.id.trim() : _themeSubject;

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  final user = ref.watch(authUserProvider).asData?.value;
  return ThemeModeNotifier(
    ref.watch(settingsRepositoryProvider),
    subjectId: _themeSubjectFor(user),
  );
});

final themeModeAccountKeyProvider = Provider<String>((ref) {
  final user = ref.watch(authUserProvider).asData?.value;
  return _themeSubjectFor(user);
});

final themeModeForSubjectProvider = Provider.family<ThemeModeNotifier, String>(
  (ref, subjectId) => ThemeModeNotifier(
    ref.watch(settingsRepositoryProvider),
    subjectId: subjectId,
  ),
);

final class ThemeModeCodec extends JsonSettingsCodec<ThemeMode> {
  const ThemeModeCodec() : super(encode: _encode, decode: _decode);

  static Object? _encode(ThemeMode mode) => mode.name;

  static ThemeMode _decode(Object? raw) => ThemeMode.values.firstWhere(
    (mode) => mode.name == raw?.toString(),
    orElse: () => ThemeMode.system,
  );
}

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._repository, {required this.subjectId})
    : super(ThemeMode.system) {
    ready = _load();
  }

  final SettingsRepository _repository;
  final String subjectId;
  late final Future<void> ready;
  bool _userChanged = false;
  Future<void> _writeQueue = Future<void>.value();

  Future<void> _load() async {
    try {
      final envelope = await _repository.readWithLegacyJson(
        scope: subjectId == _themeSubject
            ? SettingsScope.device
            : SettingsScope.user,
        subjectId: subjectId,
        fallback: ThemeMode.system,
        codec: const ThemeModeCodec(),
        legacyKey: subjectId == _themeSubject ? _legacyThemeModeKey : '',
        setting: 'theme',
      );
      if (mounted && !_userChanged) state = envelope.value;
    } catch (error) {
      debugPrint('[Theme] Could not load theme mode: $error');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    final previous = state;
    _userChanged = true;
    state = mode;
    final operation = _writeQueue.then((_) async {
      try {
        await ready;
        await _repository.update<ThemeMode>(
          scope: subjectId == _themeSubject
              ? SettingsScope.device
              : SettingsScope.user,
          subjectId: subjectId,
          fallback: previous,
          codec: const ThemeModeCodec(),
          change: (_) => mode,
          setting: 'theme',
        );
      } catch (error) {
        if (mounted && state == mode) state = previous;
        debugPrint('[Theme] Could not save theme mode: $error');
      }
    });
    _writeQueue = operation.catchError((_) {});
    await operation;
  }
}
