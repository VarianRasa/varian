import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/governance/state/accessibility_settings_provider.dart';
import 'package:varian/features/settings/data/settings_repository.dart';

void main() {
  Future<AccessibilitySettingsNotifier> createNotifier({
    Map<String, Object> initialValues = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initialValues);
    final preferences = await SharedPreferences.getInstance();
    return AccessibilitySettingsNotifier(
      SettingsRepository(preferences: preferences),
    );
  }

  test('early update wins over a delayed persisted load', () async {
    final notifier = await createNotifier(
      initialValues: {
        'cfg_accessibility_settings': '{"reducedMotion":true,"locale":"id"}',
      },
    );
    addTearDown(notifier.dispose);

    await notifier.update(
      const AccessibilitySettings(highContrast: true, locale: 'en'),
    );
    await notifier.ready;

    expect(notifier.state.highContrast, isTrue);
    expect(notifier.state.reducedMotion, isFalse);
    expect(notifier.state.locale, 'en');
  });

  test('concurrent updates serialize and keep the latest value', () async {
    final notifier = await createNotifier();
    addTearDown(notifier.dispose);

    final first = notifier.update(
      const AccessibilitySettings(highContrast: true),
    );
    final second = notifier.update(const AccessibilitySettings(forceRtl: true));
    await Future.wait([first, second]);

    expect(notifier.state.highContrast, isFalse);
    expect(notifier.state.forceRtl, isTrue);
    await notifier.ready;
  });

  test('malformed persisted JSON falls back and readiness completes', () async {
    final notifier = await createNotifier(
      initialValues: {'settings:device:runtime:accessibility': '{malformed'},
    );
    addTearDown(notifier.dispose);

    await notifier.ready;

    expect(notifier.isReady, isTrue);
    expect(notifier.state.reducedMotion, isFalse);
    expect(notifier.state.highContrast, isFalse);
    expect(notifier.state.forceRtl, isFalse);
    expect(notifier.state.locale, 'en');
    expect(notifier.state.textScaleFactor, 1.0);
  });

  test('normalizes values before exposing and persisting them', () async {
    final notifier = await createNotifier();
    addTearDown(notifier.dispose);

    await notifier.update(
      const AccessibilitySettings(locale: '  ar-SA  ', textScaleFactor: 99),
    );

    expect(notifier.state.locale, 'ar-SA');
    expect(notifier.state.textScaleFactor, 2.0);
  });
}
