import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:uuid/uuid.dart';

import '../../../domain/models/durable_asset_reference.dart';
import 'video_artifact_store_types.dart';

final Map<String, Uint8List> _webVideoBytes = {};

const _databaseName = 'varian-video-artifacts';
const _storeName = 'videos';
const _databaseVersion = 1;

VideoArtifactStore createPlatformVideoArtifactStore() =>
    WebVideoArtifactStore();

Future<VideoArtifact?> hydratePlatformVideoArtifact(String reference) =>
    WebVideoArtifactStore().hydrate(reference);

Future<void> disposePlatformHydratedVideoArtifact(VideoArtifact artifact) =>
    WebVideoArtifactStore().dispose(artifact);

class WebVideoArtifactStore implements VideoArtifactStore {
  @override
  Future<VideoArtifact> save(
    Uint8List bytes, {
    String fileName = 'video.mp4',
  }) async {
    validateVideoArtifactBytes(bytes);
    final safeName = sanitizeVideoFileName(fileName);
    final reference = 'varian-video://${const Uuid().v4()}';
    await _writePersistent(reference, bytes);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'video/mp4'),
    );
    final url = web.URL.createObjectURL(blob);
    _webVideoBytes[url] = Uint8List.fromList(bytes);
    return VideoArtifact(
      url: url,
      reference: reference,
      bytes: Uint8List.fromList(bytes),
      fileName: safeName,
    );
  }

  @override
  Future<VideoArtifact?> hydrate(String reference, {String? fileName}) async {
    final normalized = validVideoArtifactReference(reference);
    if (normalized == null) return null;
    final bytes = await _readPersistent(normalized);
    if (bytes == null || bytes.isEmpty) return null;
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'video/mp4'),
    );
    final url = web.URL.createObjectURL(blob);
    _webVideoBytes[url] = bytes;
    return VideoArtifact(
      url: url,
      reference: normalized,
      bytes: bytes,
      fileName: sanitizeVideoFileName(fileName ?? normalized.split('/').last),
    );
  }

  @override
  Future<bool> exists(VideoArtifact artifact) async {
    final url = artifact.url;
    if (url != null && _webVideoBytes.containsKey(url)) return true;
    final reference = artifact.reference;
    return reference != null && await _readPersistent(reference) != null;
  }

  @override
  Future<Uint8List?> read(VideoArtifact artifact) async {
    final url = artifact.url;
    final bytes = url == null ? null : _webVideoBytes[url];
    if (bytes != null) return Uint8List.fromList(bytes);
    final reference = artifact.reference;
    final persistent = reference == null
        ? null
        : await _readPersistent(reference);
    return persistent == null ? null : Uint8List.fromList(persistent);
  }

  @override
  Future<void> dispose(VideoArtifact artifact) async {
    final url = artifact.url;
    if (url == null) return;
    _webVideoBytes.remove(url);
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
      StateError('IndexedDB video artifact request failed.'),
    )).toJS;
    return completer.future;
  }

  Future<void> _waitForTransaction(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
    transaction.onerror = ((web.Event _) => completer.completeError(
      StateError('IndexedDB video artifact transaction failed.'),
    )).toJS;
    transaction.onabort = ((web.Event _) => completer.completeError(
      StateError('IndexedDB video artifact transaction aborted.'),
    )).toJS;
    return completer.future;
  }
}
