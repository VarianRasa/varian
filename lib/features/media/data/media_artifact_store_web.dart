import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web/web.dart' as web;
import 'package:varian/domain/models/media_timeline.dart';

import 'media_artifact_store_types.dart';

final Map<String, Uint8List> _webMediaBytes = {};

const _databaseName = 'varian-media-artifacts';
const _storeName = 'media';
const _databaseVersion = 1;

MediaArtifactStore createPlatformMediaArtifactStore() =>
    WebMediaArtifactStore();

Future<MediaArtifact?> hydratePlatformMediaArtifact(
  String reference, {
  MediaArtifactKind? kind,
  String? mimeType,
  String? checksum,
  String? fileName,
}) => WebMediaArtifactStore().hydrate(
  reference,
  kind: kind,
  mimeType: mimeType,
  checksum: checksum,
  fileName: fileName,
);

Future<Uint8List?> readPlatformMediaArtifactReference(String reference) async {
  final store = WebMediaArtifactStore();
  final artifact = await store.hydrate(reference);
  if (artifact == null) return null;
  try {
    return await store.read(artifact);
  } finally {
    await store.dispose(artifact);
  }
}

Future<void> disposePlatformHydratedMediaArtifact(MediaArtifact artifact) =>
    WebMediaArtifactStore().dispose(artifact);

class WebMediaArtifactStore implements MediaArtifactStore {
  @override
  Future<MediaArtifact> save(
    Uint8List bytes, {
    required MediaArtifactKind kind,
    required String mimeType,
    required String checksum,
    required String fileName,
    MediaStoragePolicy storagePolicy = MediaStoragePolicy.cache,
  }) async {
    validateMediaArtifactBytes(bytes);
    final actualChecksum = mediaArtifactChecksum(bytes);
    final normalizedChecksum = checksum.trim().isEmpty
        ? actualChecksum
        : checksum.trim();
    if (normalizedChecksum != actualChecksum) {
      throw const MediaArtifactStoreException(
        'Media artifact checksum does not match its bytes.',
      );
    }
    final reference = mediaArtifactReference(
      storagePolicy,
      normalizedChecksum,
      kind,
    );
    await _writePersistent(reference, bytes);
    final url = _createObjectUrl(bytes, mimeType);
    _webMediaBytes[url] = Uint8List.fromList(bytes);
    return MediaArtifact(
      kind: kind,
      url: url,
      reference: reference,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      checksum: normalizedChecksum,
    );
  }

  @override
  Future<bool> exists(MediaArtifact artifact) async {
    final bytes = await read(artifact);
    return bytes != null;
  }

  @override
  Future<Uint8List?> read(MediaArtifact artifact) async {
    final url = artifact.url;
    final bytes = url == null ? null : _webMediaBytes[url];
    if (bytes != null) {
      final copy = Uint8List.fromList(bytes);
      return _matchesIntegrity(copy, artifact) ? copy : null;
    }
    final reference = artifact.reference;
    if (reference == null) return null;
    final persistent = await _readPersistent(reference);
    if (persistent == null || persistent.length > maxMediaArtifactBytes) {
      return null;
    }
    final copy = Uint8List.fromList(persistent);
    return _matchesIntegrity(copy, artifact) ? copy : null;
  }

  @override
  Future<MediaArtifact?> hydrate(
    String reference, {
    MediaArtifactKind? kind,
    String? mimeType,
    String? checksum,
    String? fileName,
  }) async {
    final normalizedReference = normalizeMediaArtifactReference(reference);
    if (normalizedReference == null) return null;
    final policy = mediaStoragePolicyFromReference(normalizedReference);
    if (policy == null) return null;
    final resolvedKind =
        kind ?? mediaArtifactKindFromReference(normalizedReference);
    final resolvedChecksum =
        checksum ?? mediaArtifactChecksumFromReference(normalizedReference);
    if (resolvedKind == null || resolvedChecksum == null) return null;
    final bytes = await _readPersistent(normalizedReference);
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > maxMediaArtifactBytes ||
        sha256.convert(bytes).toString() != resolvedChecksum) {
      return null;
    }
    final resolvedMime = mimeType ?? _mimeTypeForKind(resolvedKind);
    final url = _createObjectUrl(bytes, resolvedMime);
    _webMediaBytes[url] = Uint8List.fromList(bytes);
    return MediaArtifact(
      kind: resolvedKind,
      url: url,
      reference: normalizedReference,
      mimeType: resolvedMime,
      sizeBytes: bytes.length,
      checksum: resolvedChecksum,
    );
  }

  @override
  Future<void> dispose(MediaArtifact artifact) async {
    final url = artifact.url;
    if (url != null) {
      _webMediaBytes.remove(url);
      web.URL.revokeObjectURL(url);
    }
    if (mediaStoragePolicyFromReference(artifact.reference ?? '') !=
        MediaStoragePolicy.ephemeral) {
      return;
    }
    final reference = artifact.reference;
    if (reference == null) return;
    final db = await _openDatabase();
    final transaction = db.transaction(_storeName.toJS, 'readwrite');
    transaction.objectStore(_storeName).delete(reference.toJS);
    await _waitForTransaction(transaction);
    db.close();
  }

  bool _matchesIntegrity(Uint8List bytes, MediaArtifact artifact) {
    if (bytes.isEmpty || bytes.length > maxMediaArtifactBytes) return false;
    final declaredSize = artifact.sizeBytes;
    if (declaredSize != null && declaredSize != bytes.length) return false;
    final checksum = artifact.checksum?.trim();
    return checksum == null ||
        checksum.isEmpty ||
        sha256.convert(bytes).toString() == checksum;
  }

  String _createObjectUrl(Uint8List bytes, String mimeType) {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    return web.URL.createObjectURL(blob);
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
      StateError('IndexedDB media artifact request failed.'),
    )).toJS;
    return completer.future;
  }

  Future<void> _waitForTransaction(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
    transaction.onerror = ((web.Event _) => completer.completeError(
      StateError('IndexedDB media artifact transaction failed.'),
    )).toJS;
    transaction.onabort = ((web.Event _) => completer.completeError(
      StateError('IndexedDB media artifact transaction aborted.'),
    )).toJS;
    return completer.future;
  }

  String _mimeTypeForKind(MediaArtifactKind kind) => switch (kind) {
    MediaArtifactKind.thumbnail => 'image/svg+xml',
    MediaArtifactKind.waveform => 'application/json',
    _ => 'application/octet-stream',
  };
}
