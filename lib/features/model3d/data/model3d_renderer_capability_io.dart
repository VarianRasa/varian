import 'dart:ffi' as ffi;
import 'dart:io';

/// Checks the native libraries that flutter_angle loads on Android before the
/// Dart widget asks three_js to create a texture.
///
/// flutter_angle currently packages these libraries for arm64-v8a only. A
/// x86_64 emulator therefore cannot create an ANGLE surface, and the caller
/// must render its explicit metadata fallback instead of leaving a spinner
/// mounted after the plugin's asynchronous initialization failure.
bool nativeModel3DRendererAvailable() {
  if (!Platform.isAndroid) return true;

  try {
    ffi.DynamicLibrary.open('libEGL_angle.so');
    ffi.DynamicLibrary.open('libGLESv2_angle.so');
    ffi.DynamicLibrary.open('libangle_android_graphic_jni.so');
    return true;
  } on Object {
    return false;
  }
}
