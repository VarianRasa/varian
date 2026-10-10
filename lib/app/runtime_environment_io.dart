import 'dart:io';

const isFlutterTestEnvironment = bool.fromEnvironment('FLUTTER_TEST');

// Platform.environment is intentionally read only by the IO implementation;
// Web builds use runtime_environment_stub.dart and never import dart:io.
bool get isFlutterTestEnvironmentRuntime =>
    isFlutterTestEnvironment ||
    Platform.environment.containsKey('FLUTTER_TEST');
