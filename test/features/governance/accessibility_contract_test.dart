import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/accessibility_runtime.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/governance/domain/accessibility_contract.dart';

void main() {
  test(
    'accessibility settings round trip locale, RTL, scale, and color safety',
    () {
      const settings = AccessibilitySettings(
        locale: 'id',
        textScaleFactor: 1.6,
        forceRtl: true,
        colorBlindSafe: true,
      );
      final restored = AccessibilitySettings.fromJson(settings.toJson());

      expect(restored.locale, 'id');
      expect(restored.textScaleFactor, 1.6);
      expect(restored.forceRtl, isTrue);
      expect(restored.colorBlindSafe, isTrue);
      expect(AccessibilityProfile(settings: restored).usesRtl, isTrue);
    },
  );

  test('profile clamps unsafe text scale values', () {
    const profile = AccessibilityProfile(
      settings: AccessibilitySettings(locale: '', textScaleFactor: 4),
    );
    final normalized = profile.normalized();

    expect(normalized.locale, 'en');
    expect(normalized.textScaleFactor, 2.0);
  });

  test('touch target audit reports interactive violations only', () {
    const report = TouchTargetAuditReport(
      items: [
        TouchTargetAuditItem(id: 'toolbar', width: 44, height: 44),
        TouchTargetAuditItem(id: 'icon', width: 24, height: 24),
        TouchTargetAuditItem(
          id: 'label',
          width: 10,
          height: 10,
          interactive: false,
        ),
      ],
    );

    expect(report.passes, isFalse);
    expect(report.violations.map((item) => item.id), ['icon']);
  });

  test(
    'runtime profile applies reduced motion, contrast, navigation, and text settings',
    () {
      const settings = AccessibilitySettings(
        reducedMotion: true,
        highContrast: true,
        keyboardOnly: true,
        largerText: true,
        textScaleFactor: 1.0,
        alwaysShowFocus: false,
      );
      final profile = AccessibilityRuntimeProfile.fromSettings(settings);

      expect(profile.disableAnimations, isTrue);
      expect(profile.highContrast, isTrue);
      expect(profile.accessibleNavigation, isTrue);
      expect(profile.textScaleFactor, 1.2);
      // Keyboard-only navigation requires a visible focus indicator.
      expect(profile.focusHighlight, isTrue);
    },
  );

  test('runtime profile preserves an explicit larger text scale', () {
    const settings = AccessibilitySettings(
      largerText: true,
      textScaleFactor: 1.6,
    );

    expect(
      AccessibilityRuntimeProfile.fromSettings(settings).textScaleFactor,
      1.6,
    );
  });
}
