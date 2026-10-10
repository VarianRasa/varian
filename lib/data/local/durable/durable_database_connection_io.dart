import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../../app/runtime_environment.dart';

DatabaseConnection openDurableDatabaseConnection({
  required String name,
  required Uri sqlite3Wasm,
  required Uri driftWorker,
}) {
  if (isFlutterTestEnvironmentRuntime) {
    return DatabaseConnection(NativeDatabase.memory());
  }

  return driftDatabase(
    name: name,
    web: DriftWebOptions(sqlite3Wasm: sqlite3Wasm, driftWorker: driftWorker),
    native: const DriftNativeOptions(shareAcrossIsolates: true),
  );
}
