import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/settings/data/settings_repository.dart';
import 'package:varian/features/settings/domain/settings_models.dart';

void main() {
  test('preserves envelope metadata and unknown extensions', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SettingsRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    const codec = AccessibilitySettingsCodec();

    final written = await repository.write(
      envelope: SettingsEnvelope<AccessibilitySettings>(
        schemaVersion: 99,
        scope: SettingsScope.user,
        subjectId: 'account-a',
        revision: 0,
        updatedAt: DateTime.utc(2026, 1, 1),
        value: const AccessibilitySettings(locale: 'id'),
        extensions: const {'futureFlag': true},
      ),
      codec: codec,
    );
    final read = await repository.read(
      scope: SettingsScope.user,
      subjectId: 'account-a',
      fallback: const AccessibilitySettings(),
      codec: codec,
    );

    expect(written.schemaVersion, SettingsRepository.schemaVersion);
    expect(read.revision, 1);
    expect(read.value.locale, 'id');
    expect(read.extensions['futureFlag'], true);
  });

  test(
    'rejects stale optimistic revisions without changing settings',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository(
        preferences: await SharedPreferences.getInstance(),
      );
      const codec = AccessibilitySettingsCodec();
      final first = await repository.update<AccessibilitySettings>(
        scope: SettingsScope.device,
        subjectId: 'device-a',
        fallback: const AccessibilitySettings(),
        codec: codec,
        change: (current) => current.copyWith(largerText: true),
      );

      expect(
        () => repository.write(
          envelope: first.copyWith(
            value: first.value.copyWith(highContrast: true),
          ),
          codec: codec,
          expectedRevision: 0,
        ),
        throwsA(isA<SettingsConflictException>()),
      );

      final current = await repository.read(
        scope: SettingsScope.device,
        subjectId: 'device-a',
        fallback: const AccessibilitySettings(),
        codec: codec,
      );
      expect(current.value.largerText, true);
      expect(current.value.highContrast, false);
    },
  );

  test(
    'keeps a last-known-good envelope when the active value is malformed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = SettingsRepository(preferences: preferences);
      const codec = AccessibilitySettingsCodec();

      final first = await repository.update<AccessibilitySettings>(
        scope: SettingsScope.device,
        subjectId: 'device-a',
        fallback: const AccessibilitySettings(),
        codec: codec,
        change: (current) => current.copyWith(highContrast: true),
      );
      await repository.update<AccessibilitySettings>(
        scope: SettingsScope.device,
        subjectId: 'device-a',
        fallback: const AccessibilitySettings(),
        codec: codec,
        change: (current) => current.copyWith(largerText: true),
      );

      final activeKey = repository.key(
        scope: SettingsScope.device,
        subjectId: 'device-a',
      );
      await preferences.setString(activeKey, '{malformed');

      final recovered = await SettingsRepository(preferences: preferences)
          .read<AccessibilitySettings>(
            scope: SettingsScope.device,
            subjectId: 'device-a',
            fallback: const AccessibilitySettings(),
            codec: codec,
          );
      expect(recovered.revision, first.revision);
      expect(recovered.value.highContrast, true);
      expect(recovered.value.largerText, false);
    },
  );

  test('keeps settings isolated by scope, subject, and setting name', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SettingsRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    const codec = AccessibilitySettingsCodec();

    await repository.update<AccessibilitySettings>(
      scope: SettingsScope.user,
      subjectId: 'account-a',
      setting: 'accessibility',
      fallback: const AccessibilitySettings(),
      codec: codec,
      change: (current) => current.copyWith(forceRtl: true),
    );

    final otherAccount = await repository.read<AccessibilitySettings>(
      scope: SettingsScope.user,
      subjectId: 'account-b',
      setting: 'accessibility',
      fallback: const AccessibilitySettings(),
      codec: codec,
    );
    final otherSetting = await repository.read<AccessibilitySettings>(
      scope: SettingsScope.user,
      subjectId: 'account-a',
      setting: 'theme',
      fallback: const AccessibilitySettings(),
      codec: codec,
    );
    expect(otherAccount.value.forceRtl, false);
    expect(otherSetting.value.forceRtl, false);
  });
}
