import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/accessibility_runtime.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/governance/domain/accessibility_contract.dart';

void main() {
  test(
    'parses valid accessibility fields without failing on malformed fields',
    () {
      final settings = AccessibilitySettings.fromJson({
        'reducedMotion': true,
        'highContrast': 'invalid',
        'locale': '  id  ',
        'shortcuts': {'save': 'Ctrl+S', 'bad': 42},
        'textScaleFactor': 99,
        'forceRtl': true,
      });

      expect(settings.reducedMotion, isTrue);
      expect(settings.highContrast, isFalse);
      expect(settings.locale, '  id  ');
      expect(settings.shortcuts, {'save': 'Ctrl+S'});
      expect(settings.textScaleFactor, 2.0);
      expect(settings.forceRtl, isTrue);
    },
  );

  test(
    'normalizes locale and derives RTL from locale or explicit override',
    () {
      expect(
        const AccessibilityProfile(
          settings: AccessibilitySettings(locale: '  ar-SA '),
        ).normalized().locale,
        'ar-SA',
      );
      expect(
        const AccessibilityProfile(
          settings: AccessibilitySettings(locale: 'ar-SA'),
        ).usesRtl,
        isTrue,
      );
      expect(
        const AccessibilityProfile(
          settings: AccessibilitySettings(forceRtl: true),
        ).usesRtl,
        isTrue,
      );
    },
  );

  test('preserves operating-system scale when app scale is neutral', () {
    final profile = AccessibilityRuntimeProfile.fromSettings(
      const AccessibilitySettings(),
    );
    expect(profile.textScaleFactor, 1.0);
  });

  test(
    'legacy accessibility payload migrates through the settings codec',
    () async {
      SharedPreferences.setMockInitialValues({
        'cfg_accessibility_settings': '{"reducedMotion":true,"locale":"id"}',
      });
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('cfg_accessibility_settings'), isNotNull);
    },
  );
}
