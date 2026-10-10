import 'export_presets.dart';

enum ExportCapabilityStatus { supported, unavailable }

class ExportCapability {
  final ExportPresetFormat format;
  final ExportCapabilityStatus status;
  final String reason;
  final bool requiresNativeEncoder;
  final List<String> supportedPlatforms;

  const ExportCapability({
    required this.format,
    required this.status,
    required this.reason,
    this.requiresNativeEncoder = false,
    this.supportedPlatforms = const [],
  });

  bool get isSupported => status == ExportCapabilityStatus.supported;

  Map<String, dynamic> toJson() => {
    'format': format.name,
    'status': status.name,
    'reason': reason,
    'requiresNativeEncoder': requiresNativeEncoder,
    'supportedPlatforms': supportedPlatforms,
  };
}

class ExportCapabilityRegistry {
  ExportCapabilityRegistry._();

  static const video = ExportCapability(
    format: ExportPresetFormat.video,
    status: ExportCapabilityStatus.unavailable,
    reason: 'Video export requires a cancellable native codec worker.',
    requiresNativeEncoder: true,
    supportedPlatforms: ['windows', 'android', 'ios', 'macos', 'linux'],
  );

  static const presentation = ExportCapability(
    format: ExportPresetFormat.presentation,
    status: ExportCapabilityStatus.supported,
    reason: 'Portable presentation contract export is supported.',
  );

  static ExportCapability forFormat(ExportPresetFormat format) =>
      switch (format) {
        ExportPresetFormat.video => video,
        ExportPresetFormat.presentation => presentation,
        _ => ExportCapability(
          format: format,
          status: ExportCapabilityStatus.supported,
          reason: 'Document export is supported.',
        ),
      };
}
