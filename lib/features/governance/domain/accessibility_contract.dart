import '../../../domain/models/workspace_governance.dart';

class AccessibilityProfile {
  final AccessibilitySettings settings;

  const AccessibilityProfile({this.settings = const AccessibilitySettings()});

  bool get usesRtl =>
      settings.forceRtl || settings.locale.toLowerCase().startsWith('ar');

  AccessibilitySettings normalized() => settings.copyWith(
    locale: settings.locale.trim().isEmpty ? 'en' : settings.locale.trim(),
    textScaleFactor: settings.textScaleFactor.clamp(0.8, 2.0),
  );
}

class TouchTargetAuditItem {
  final String id;
  final double width;
  final double height;
  final bool interactive;

  const TouchTargetAuditItem({
    required this.id,
    required this.width,
    required this.height,
    this.interactive = true,
  });

  bool meetsMinimum(double minimum) =>
      !interactive || (width >= minimum && height >= minimum);
}

class TouchTargetAuditReport {
  final double minimumSize;
  final List<TouchTargetAuditItem> items;

  const TouchTargetAuditReport({this.minimumSize = 44, this.items = const []});

  List<TouchTargetAuditItem> get violations => items
      .where((item) => !item.meetsMinimum(minimumSize))
      .toList(growable: false);

  bool get passes => violations.isEmpty;
}
