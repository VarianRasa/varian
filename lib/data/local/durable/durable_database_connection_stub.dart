import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:web/web.dart' as web;

DatabaseConnection openDurableDatabaseConnection({
  required String name,
  required Uri sqlite3Wasm,
  required Uri driftWorker,
}) {
  final baseUri = Uri.parse(web.window.document.baseURI);
  return driftDatabase(
    name: name,
    web: DriftWebOptions(
      sqlite3Wasm: baseUri.resolveUri(sqlite3Wasm),
      driftWorker: baseUri.resolveUri(driftWorker),
    ),
    native: const DriftNativeOptions(shareAcrossIsolates: true),
  );
}
