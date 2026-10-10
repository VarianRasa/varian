import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../domain/models/workspace_governance.dart';
import 'theme.dart';

@immutable
class AppAccessibilityTextScaler extends TextScaler {
  final TextScaler platformScaler;
  final double accessibilityScale;
  final double compactScale;

  const AppAccessibilityTextScaler({
    required this.platformScaler,
    required this.accessibilityScale,
    required this.compactScale,
  });

  @override
  double scale(double fontSize) =>
      platformScaler.scale(fontSize * accessibilityScale) * compactScale;

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) =>
      other is AppAccessibilityTextScaler &&
      other.platformScaler == platformScaler &&
      other.accessibilityScale == accessibilityScale &&
      other.compactScale == compactScale;

  @override
  int get hashCode =>
      Object.hash(platformScaler, accessibilityScale, compactScale);
}

@immutable
class AccessibilityRuntimeProfile {
  final bool disableAnimations;
  final bool highContrast;
  final bool accessibleNavigation;
  final bool focusHighlight;
  final double textScaleFactor;

  const AccessibilityRuntimeProfile({
    required this.disableAnimations,
    required this.highContrast,
    required this.accessibleNavigation,
    required this.focusHighlight,
    required this.textScaleFactor,
  });

  factory AccessibilityRuntimeProfile.fromSettings(
    AccessibilitySettings settings,
  ) {
    final scale = settings.textScaleFactor.clamp(0.8, 2.0).toDouble();
    return AccessibilityRuntimeProfile(
      disableAnimations: settings.reducedMotion,
      highContrast: settings.highContrast,
      accessibleNavigation: settings.keyboardOnly,
      focusHighlight: settings.alwaysShowFocus || settings.keyboardOnly,
      textScaleFactor: settings.largerText ? math.max(scale, 1.2) : scale,
    );
  }

  TextScaler textScaler(
    TextScaler platformScaler, {
    double compactScale = AppTypography.compactScale,
  }) => AppAccessibilityTextScaler(
    platformScaler: platformScaler,
    accessibilityScale: textScaleFactor,
    compactScale: compactScale,
  );
}
