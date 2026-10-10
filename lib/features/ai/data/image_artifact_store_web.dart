import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import 'image_artifact_store_types.dart';

final Map<String, Uint8List> _webImageBytes = {};

const _databaseName = 'varian-image-artifacts';
const _storeName = 'images';
const _databaseVersion = 1;

ImageArtifactStore createPlatformImageArtifactStore() =>
    WebImageArtifactStore();

Future<ImageArtifact?> hydratePlatformImageArtifact(String reference) =>
    WebImageArtifactStore().hydrate(reference);

Future<void> disposePlatformHydratedImageArtifact(ImageArtifact artifact) =>
    WebImageArtifactStore().dispose(artifact);

class WebImageArtifactStore implements ImageArtifactStore {
  @override
  Future<ImageArtifact> save(
    Uint8List bytes, {
    String fileName = 'image.png',
  }) async {
    validateImageArtifactBytes(bytes);
    final reference = 'varian-image://${const Uuid().v4()}';
    await _writePersistent(reference, bytes);
    return ImageArtifact(
      reference: reference,
      bytes: Uint8List.fromList(bytes),
      fileName: sanitizeImageArtifactFileName(fileName),
    );
  }

  @override
  Future<ImageArtifact?> hydrate(String reference, {String? fileName}) async {
    if (!_isImageReference(reference)) return null;
    final bytes = await _readPersistent(reference);
    if (bytes == null) return null;
    try {
      validateImageArtifactBytes(bytes);
    } catch (_) {
      return null;
    }
    final url = _createObjectUrl(bytes);
    _webImageBytes[url] = Uint8List.fromList(bytes);
    return ImageArtifact(
      url: url,
      reference: reference,
      bytes: bytes,
      fileName: fileName ?? _fileNameForBytes(bytes),
    );
  }

  @override
  Future<bool> exists(ImageArtifact artifact) async {
    final url = artifact.url;
    if (url != null && _webImageBytes.containsKey(url)) return true;
    final reference = artifact.reference;
    return reference != null && await _readPersistent(reference) != null;
  }

  @override
  Future<Uint8List?> read(ImageArtifact artifact) async {
    final url = artifact.url;
    final bytes = url == null ? null : _webImageBytes[url];
    if (bytes != null) return Uint8List.fromList(bytes);
    final reference = artifact.reference;
    if (reference == null) return null;
    final persistent = await _readPersistent(reference);
    return persistent == null ? null : Uint8List.fromList(persistent);
  }

  @override
  Future<void> dispose(ImageArtifact artifact) async {
    final url = artifact.url;
    if (url == null || !_webImageBytes.containsKey(url)) return;
    _webImageBytes.remove(url);
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
    if (!_isImageReference(reference)) return null;
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
    final result = await _waitForRequest(request);
    return result as web.IDBDatabase;
  }

  Future<JSAny?> _waitForRequest(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(StateError('IndexedDB image request failed.'));
    }).toJS;
    return completer.future;
  }

  Future<void> _waitForTransaction(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
    transaction.onerror = ((web.Event _) {
      completer.completeError(
        StateError('IndexedDB image transaction failed.'),
      );
    }).toJS;
    transaction.onabort = ((web.Event _) {
      completer.completeError(
        StateError('IndexedDB image transaction aborted.'),
      );
    }).toJS;
    return completer.future;
  }
}

bool _isImageReference(String reference) {
  final uri = Uri.tryParse(reference.trim());
  return uri != null &&
      uri.scheme == 'varian-image' &&
      uri.host.isNotEmpty &&
      uri.path.isEmpty &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$').hasMatch(uri.host);
}

String _createObjectUrl(Uint8List bytes) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: _mimeTypeForBytes(bytes)),
  );
  return web.URL.createObjectURL(blob);
}

String _mimeTypeForBytes(Uint8List bytes) {
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    return 'image/jpeg';
  }
  return 'image/png';
}

String _fileNameForBytes(Uint8List bytes) {
  final mime = _mimeTypeForBytes(bytes);
  return mime == 'image/webp'
      ? 'generated-image.webp'
      : mime == 'image/jpeg'
      ? 'generated-image.jpg'
      : 'generated-image.png';
}
