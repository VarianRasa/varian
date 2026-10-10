import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'capture_asset_store_types.dart';

const _databaseName = 'varian-capture-assets';
const _storeName = 'captures';
const _databaseVersion = 1;

CaptureAssetStore createPlatformCaptureAssetStore() => WebCaptureAssetStore();

class WebCaptureAssetStore implements CaptureAssetStore {
  @override
  Future<String> save(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    validateCaptureAssetBytes(bytes);
    final reference = newCaptureAssetReference();
    final database = await _openDatabase();
    try {
      final transaction = database.transaction(_storeName.toJS, 'readwrite');
      transaction
          .objectStore(_storeName)
          .put(bytes.buffer.toJS, reference.toJS);
      await _waitForTransaction(transaction);
      return reference;
    } finally {
      database.close();
    }
  }

  @override
  Future<Uint8List?> read(String reference) async {
    if (!_isReference(reference)) return null;
    final database = await _openDatabase();
    try {
      final request = database
          .transaction(_storeName.toJS, 'readonly')
          .objectStore(_storeName)
          .get(reference.toJS);
      final result = await _waitForRequest(request);
      if (result == null || result.isUndefined) return null;
      if (result.isA<JSArrayBuffer>()) {
        return Uint8List.fromList(
          (result as JSArrayBuffer).toDart.asUint8List(),
        );
      }
      if (result.isA<JSUint8Array>()) {
        return Uint8List.fromList((result as JSUint8Array).toDart);
      }
      return null;
    } finally {
      database.close();
    }
  }

  @override
  Future<bool> exists(String reference) async => await read(reference) != null;

  @override
  Future<void> delete(String reference) async {
    if (!_isReference(reference)) return;
    final database = await _openDatabase();
    try {
      final transaction = database.transaction(_storeName.toJS, 'readwrite');
      transaction.objectStore(_storeName).delete(reference.toJS);
      await _waitForTransaction(transaction);
    } finally {
      database.close();
    }
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
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(
        const CaptureAssetStoreException('Capture asset storage failed.'),
      );
    }).toJS;
    return completer.future;
  }

  Future<void> _waitForTransaction(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
    transaction.onerror = ((web.Event _) {
      completer.completeError(
        const CaptureAssetStoreException('Capture asset storage failed.'),
      );
    }).toJS;
    transaction.onabort = ((web.Event _) {
      completer.completeError(
        const CaptureAssetStoreException(
          'Capture asset storage was interrupted.',
        ),
      );
    }).toJS;
    return completer.future;
  }
}

bool _isReference(String reference) => isCaptureAssetReference(reference);
