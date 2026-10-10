import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../../domain/models/durable_asset_reference.dart';
import 'file_artifact_store_types.dart';

final Map<String, Uint8List> _webFileBytes = {};

const _databaseName = 'varian-file-artifacts';
const _storeName = 'files';
const _databaseVersion = 1;

FileArtifactStore createPlatformFileArtifactStore() => WebFileArtifactStore();

class WebFileArtifactStore implements FileArtifactStore {
  @override
  Future<FileArtifact> save(
    Uint8List bytes, {
    String fileName = 'document.bin',
  }) async {
    validateFileArtifactBytes(bytes, fileName: fileName);
    final reference = newFileArtifactReference();
    await _writePersistent(reference, bytes);
    return FileArtifact(
      reference: reference,
      bytes: Uint8List.fromList(bytes),
      fileName: sanitizeFileArtifactName(fileName),
    );
  }

  @override
  Future<FileArtifact?> hydrate(String reference, {String? fileName}) async {
    if (durableOpaqueArtifactReference(reference, 'varian-file') == null) {
      return null;
    }
    final bytes = await _readPersistent(reference);
    if (bytes == null || bytes.isEmpty) return null;
    final url = _createObjectUrl(bytes);
    _webFileBytes[url] = Uint8List.fromList(bytes);
    return FileArtifact(
      url: url,
      reference: reference,
      bytes: bytes,
      fileName: sanitizeFileArtifactName(fileName ?? 'document.bin'),
    );
  }

  @override
  Future<bool> exists(FileArtifact artifact) async {
    final url = artifact.url;
    if (url != null && _webFileBytes.containsKey(url)) return true;
    final reference = artifact.reference;
    return reference != null && await _readPersistent(reference) != null;
  }

  @override
  Future<Uint8List?> read(FileArtifact artifact) async {
    final url = artifact.url;
    final bytes = url == null ? null : _webFileBytes[url];
    if (bytes != null) return Uint8List.fromList(bytes);
    final reference = artifact.reference;
    final persistent = reference == null
        ? null
        : await _readPersistent(reference);
    return persistent == null ? null : Uint8List.fromList(persistent);
  }

  @override
  Future<void> dispose(FileArtifact artifact) async {
    final url = artifact.url;
    if (url == null) return;
    _webFileBytes.remove(url);
    web.URL.revokeObjectURL(url);
  }

  Future<void> _writePersistent(String reference, Uint8List bytes) async {
    final db = await _openDatabase();
    final transaction = db.transaction(_storeName.toJS, 'readwrite');
    transaction.objectStore(_storeName).put(bytes.buffer.toJS, reference.toJS);
    await _waitForTransaction(transaction);
    db.close();
  }

  Future<Uint8List?> _readPersistent(String reference) async {
    if (durableOpaqueArtifactReference(reference, 'varian-file') == null) {
      return null;
    }
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
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      if (!database.objectStoreNames.contains(_storeName)) {
        database.createObjectStore(_storeName);
      }
    }).toJS;
    return await _waitForRequest(request) as web.IDBDatabase;
  }

  Future<JSAny?> _waitForRequest(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => completer.complete(
      request.result,
    )).toJS;
    request.onerror = ((web.Event _) => completer.completeError(
      StateError('IndexedDB file artifact request failed.'),
    )).toJS;
    return completer.future;
  }

  Future<void> _waitForTransaction(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
    transaction.onerror = ((web.Event _) => completer.completeError(
      StateError('IndexedDB file artifact transaction failed.'),
    )).toJS;
    transaction.onabort = ((web.Event _) => completer.completeError(
      StateError('IndexedDB file artifact transaction aborted.'),
    )).toJS;
    return completer.future;
  }

  String _createObjectUrl(Uint8List bytes) {
    final blob = web.Blob([bytes.toJS].toJS);
    return web.URL.createObjectURL(blob);
  }
}
