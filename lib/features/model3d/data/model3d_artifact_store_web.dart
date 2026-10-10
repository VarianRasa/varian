import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import '../../../domain/models/durable_asset_reference.dart';
import 'model3d_artifact_store_types.dart';
import 'model3d_validation.dart';

final Map<String, Uint8List> _webModel3DBytes = {};

const _databaseName = 'varian-model3d-artifacts';
const _storeName = 'models';
const _databaseVersion = 1;

Model3DArtifactStore createPlatformModel3DArtifactStore() =>
    WebModel3DArtifactStore();

Future<Model3DArtifact?> hydratePlatformModel3DArtifact(
  String reference,
) async {
  if (validModel3DArtifactReference(reference) == null) return null;
  final store = WebModel3DArtifactStore();
  final bytes = await store._readPersistent(reference);
  if (bytes == null) return null;
  try {
    validateGlbBytes(bytes);
  } catch (_) {
    return null;
  }
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'model/gltf-binary'),
  );
  final url = web.URL.createObjectURL(blob);
  _webModel3DBytes[url] = bytes;
  return Model3DArtifact(
    url: url,
    reference: reference,
    bytes: bytes,
    fileName: 'model.glb',
  );
}

Future<bool> isPlatformModel3DArtifactPathAllowed(String path) async => false;

Future<void> disposePlatformHydratedModel3DArtifact(
  Model3DArtifact artifact,
) async {
  WebModel3DArtifactStore().dispose(artifact);
}

class WebModel3DArtifactStore implements Model3DArtifactStore {
  @override
  Future<Model3DArtifact> save(
    Uint8List bytes, {
    String fileName = 'model.glb',
  }) async {
    validateGlbBytes(bytes);
    final safeName = sanitizeModel3DFileName(fileName);
    final reference = 'varian-model3d://${const Uuid().v4()}';
    await _writePersistent(reference, bytes);
    // The viewer creates one object URL when it hydrates this durable
    // reference. Do not create a second import-time URL that has no owner.
    return Model3DArtifact(
      reference: reference,
      bytes: Uint8List.fromList(bytes),
      fileName: safeName,
    );
  }

  @override
  Future<Model3DArtifact?> hydrate(String reference, {String? fileName}) async {
    final normalized = validModel3DArtifactReference(reference);
    if (normalized == null) return null;
    final bytes = await _readPersistent(normalized);
    if (bytes == null) return null;
    validateGlbBytes(bytes);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'model/gltf-binary'),
    );
    final url = web.URL.createObjectURL(blob);
    _webModel3DBytes[url] = Uint8List.fromList(bytes);
    return Model3DArtifact(
      url: url,
      reference: normalized,
      bytes: Uint8List.fromList(bytes),
      fileName: fileName == null
          ? 'model.glb'
          : sanitizeModel3DFileName(fileName),
    );
  }

  @override
  Future<bool> exists(Model3DArtifact artifact) async {
    final url = artifact.url;
    if (url != null && _webModel3DBytes.containsKey(url)) return true;
    final reference = artifact.reference;
    return reference != null && await _readPersistent(reference) != null;
  }

  @override
  Future<Uint8List?> read(Model3DArtifact artifact) async {
    final url = artifact.url;
    final bytes = url == null ? null : _webModel3DBytes[url];
    if (bytes != null) return Uint8List.fromList(bytes);
    final reference = artifact.reference;
    final persistent = reference == null
        ? null
        : await _readPersistent(reference);
    return persistent == null ? null : Uint8List.fromList(persistent);
  }

  @override
  Future<void> dispose(Model3DArtifact artifact) async {
    final url = artifact.url;
    if (url == null) return;
    _webModel3DBytes.remove(url);
    web.URL.revokeObjectURL(url);
  }

  Future<void> _writePersistent(String reference, Uint8List bytes) async {
    final db = await _openDatabase();
    final transaction = db.transaction(_storeName.toJS, 'readwrite');
    final value = Uint8List.fromList(bytes).buffer.toJS;
    transaction.objectStore(_storeName).put(value, reference.toJS);
    await _waitForTransaction(transaction);
    db.close();
  }

  Future<Uint8List?> _readPersistent(String reference) async {
    final db = await _openDatabase();
    final request = db
        .transaction(_storeName.toJS, 'readonly')
        .objectStore(_storeName)
        .get(reference.toJS);
    final result = await _waitForRequest(request);
    db.close();
    if (result == null || result.isUndefined) return null;
    if (result.isA<JSArrayBuffer>()) {
      return Uint8List.fromList((result as JSArrayBuffer).toDart.asUint8List());
    }
    if (result.isA<JSUint8Array>()) {
      return Uint8List.fromList((result as JSUint8Array).toDart);
    }
    return null;
  }

  Future<web.IDBDatabase> _openDatabase() async {
    final request = web.window.indexedDB.open(_databaseName, _databaseVersion);
    request.onupgradeneeded = ((web.Event event) {
      final database = request.result as web.IDBDatabase;
      if (!database.objectStoreNames.contains(_storeName)) {
        database.createObjectStore(_storeName);
      }
    }).toJS;
    final result = await _waitForRequest(request);
    return result as web.IDBDatabase;
  }

  Future<JSAny?> _waitForRequest(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => completer.complete(
      request.result,
    )).toJS;
    request.onerror = ((web.Event _) => completer.completeError(
      StateError('IndexedDB model artifact request failed.'),
    )).toJS;
    return completer.future;
  }

  Future<void> _waitForTransaction(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
    transaction.onerror = ((web.Event _) => completer.completeError(
      StateError('IndexedDB model artifact transaction failed.'),
    )).toJS;
    transaction.onabort = ((web.Event _) => completer.completeError(
      StateError('IndexedDB model artifact transaction aborted.'),
    )).toJS;
    return completer.future;
  }
}
