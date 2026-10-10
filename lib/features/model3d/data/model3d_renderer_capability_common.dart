/// Returns the user-facing recovery message for an unavailable 3D renderer.
///
/// The project library and document metadata remain usable when this capability
/// is missing. Keep this message explicit so a native renderer failure never
/// leaves a loading surface without a recovery action.
String? model3DRendererFallbackMessage({
  required bool isAndroid,
  required bool nativeRendererAvailable,
}) {
  if (!isAndroid || nativeRendererAvailable) return null;
  return 'Android native renderer is unavailable on this device. The project library remains usable. Retry preview when a supported renderer is available.';
}

/// Avoids constructing three_js on known unsupported Android emulator/runtime
/// surfaces. The platform probe is deliberately injected so unit/widget tests
/// can verify the fallback without loading native renderer libraries.
bool shouldSkipModel3DRenderer({
  required bool isAndroid,
  required bool nativeRendererAvailable,
}) => isAndroid && !nativeRendererAvailable;
