import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../data/remote/external_url_policy.dart';
import '../../../data/remote/supabase_storage_path_resolver.dart';
import '../../../domain/models/durable_asset_reference.dart';
import '../../ai/data/image_artifact_store.dart';
import '../../ai/data/video_media_validation.dart';
import 'canvas_image_file_loader.dart';

class CanvasImageCache {
  CanvasImageCache({ImageArtifactStore? imageArtifactStore})
    : _imageArtifactStore = imageArtifactStore ?? createImageArtifactStore();

  CanvasImageCache._({ImageArtifactStore? imageArtifactStore})
    : _imageArtifactStore = imageArtifactStore ?? createImageArtifactStore();

  /// Creates a cache whose lifecycle can be tied to one editor surface.
  ///
  /// The process-wide [instance] remains available for lightweight previews,
  /// while editor surfaces should prefer a scoped cache so project/account
  /// switches cannot reuse or complete work into another surface. Tests may
  /// provide an in-memory artifact store to keep hydration deterministic.
  factory CanvasImageCache.scoped({ImageArtifactStore? imageArtifactStore}) =>
      CanvasImageCache._(imageArtifactStore: imageArtifactStore);

  static final CanvasImageCache instance = CanvasImageCache._();

  final Map<String, ui.Image> _cache = {};
  final Map<String, int> _requestTickets = {};
  int _nextRequestTicket = 0;
  final Set<String> _loadingKeys = {};
  final List<VoidCallback> _listeners = [];
  SupabaseStoragePathResolver? _storageResolver;
  String? _projectId;
  String? _expectedUserId;
  int _generation = 0;
  ImageArtifactStore _imageArtifactStore;
  bool _disposed = false;

  int get generation => _generation;

  @visibleForTesting
  int get debugListenerCount => _listeners.length;

  /// Rebinds the cache to the application-owned store without clearing durable
  /// artifact bytes. In-flight loads are invalidated because they may have
  /// captured the previous store identity.
  void configureArtifactStore(ImageArtifactStore store) {
    if (identical(_imageArtifactStore, store)) return;
    _imageArtifactStore = store;
    _generation++;
    _requestTickets.clear();
    _loadingKeys.clear();
    _notifyRepaint();
  }

  void configureStorageResolver({
    required SupabaseStoragePathResolver? resolver,
    required String? projectId,
    String? expectedUserId,
  }) {
    final changed =
        !identical(_storageResolver, resolver) ||
        _projectId != projectId ||
        _expectedUserId != expectedUserId;
    if (changed) {
      _generation++;
      for (final image in _cache.values.toSet()) {
        image.dispose();
      }
      _cache.clear();
      _requestTickets.clear();
      _loadingKeys.clear();
      _notifyRepaint();
    }
    _storageResolver = resolver;
    _projectId = projectId;
    _expectedUserId = expectedUserId;
  }

  void addListener(VoidCallback listener) {
    if (_disposed || _listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyRepaint() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  ui.Image? getImage(String? key) {
    final canonicalKey = _canonicalKey(key);
    if (canonicalKey == null) return null;
    return _cache[canonicalKey];
  }

  /// Converts a render source into a non-secret cache identity.
  ///
  /// Query-bearing HTTP(S) URLs are transient delivery credentials in common
  /// Storage implementations. They are deliberately not cacheable, while a
  /// project-scoped Storage path is reduced to its stable bucket/path key.
  String? _canonicalKey(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if (validImageArtifactReference(value) case final reference?) {
      return 'artifact:$reference';
    }
    if (value.startsWith('storage:')) {
      return value.contains('?') || value.contains('#') ? null : value;
    }
    if (value.startsWith('url:')) {
      final publicUri = ExternalUrlPolicy.publicUri(value.substring(4));
      return publicUri == null ? null : 'url:${publicUri.toString()}';
    }
    if (value.startsWith('source:') || value.startsWith('local:')) {
      final fixture = value.substring(value.indexOf(':') + 1);
      return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(fixture)
          ? value
          : null;
    }
    if (value.startsWith('raster://')) {
      final rasterReference = value.substring('raster://'.length);
      return rasterReference.isNotEmpty &&
              rasterReference.length <= 256 &&
              !rasterReference.contains('?') &&
              !rasterReference.contains('#') &&
              !rasterReference.contains(' ') &&
              !rasterReference.contains('\\')
          ? value
          : null;
    }

    final resolver = _storageResolver;
    final projectId = _projectId;
    if (resolver != null && projectId != null && projectId.isNotEmpty) {
      final reference = resolver.parseReference(
        path: value,
        projectId: projectId,
      );
      if (reference != null) return 'storage:${reference.cacheKey}';
    }

    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
        // Query-bearing URLs are runtime-only and must not be cached. They may
        // contain signed delivery credentials.
        return null;
      }
      final publicUri = ExternalUrlPolicy.publicUri(value);
      return publicUri == null ? null : 'url:${publicUri.toString()}';
    }
    // Do not turn arbitrary runtime values into durable cache identities. The
    // only non-Storage sources accepted here are short fixture keys used by
    // canvas tests and transient renderers.
    if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(value)) {
      return 'source:$value';
    }
    return null;
  }

  Future<Uint8List?> loadImageBytes({
    String? storagePath,
    String? localPath,
    String? url,
    String? imageArtifactReference,
  }) async {
    final normalizedArtifactReference = validImageArtifactReference(
      imageArtifactReference?.trim(),
    );
    if (normalizedArtifactReference != null) {
      final artifact = await _imageArtifactStore.hydrate(
        normalizedArtifactReference,
      );
      if (artifact != null) {
        final bytes = await _imageArtifactStore.read(artifact);
        await _imageArtifactStore.dispose(artifact);
        if (bytes != null && bytes.isNotEmpty && isValidImageBytes(bytes)) {
          return bytes;
        }
      }
    }
    final normalizedStoragePath = storagePath?.trim();
    final normalizedLocalPath = localPath?.trim();
    final normalizedUrl = url?.trim();

    try {
      final resolver = _storageResolver;
      final projectId = _projectId;
      if (resolver != null && projectId != null && projectId.isNotEmpty) {
        final privateBytes = await resolver.readBytes(
          projectId: projectId,
          source: normalizedUrl,
          storagePath: normalizedStoragePath,
          expectedUserId: _expectedUserId,
          maxBytes: 50 * 1024 * 1024,
        );
        if (privateBytes != null &&
            privateBytes.isNotEmpty &&
            isValidImageBytes(privateBytes)) {
          return privateBytes;
        }
      }

      if (!kIsWeb &&
          normalizedLocalPath != null &&
          normalizedLocalPath.isNotEmpty) {
        final localBytes = await readCanvasImageFileBytes(normalizedLocalPath);
        if (localBytes != null &&
            localBytes.isNotEmpty &&
            isValidImageBytes(localBytes)) {
          return localBytes;
        }
      }

      if (normalizedUrl != null && normalizedUrl.startsWith('data:image')) {
        final commaIndex = normalizedUrl.indexOf(',');
        if (commaIndex == -1) return null;
        final bytes = base64Decode(normalizedUrl.substring(commaIndex + 1));
        return bytes.isEmpty || !isValidImageBytes(bytes) ? null : bytes;
      }

      if (normalizedUrl != null && normalizedUrl.isNotEmpty) {
        final uri = ExternalUrlPolicy.publicUri(normalizedUrl);
        if (uri != null) {
          final client = http.Client();
          try {
            final request = http.Request('GET', uri)..followRedirects = false;
            final response = await client
                .send(request)
                .timeout(const Duration(seconds: 20));
            if (response.isRedirect ||
                response.statusCode == 301 ||
                response.statusCode == 302 ||
                response.statusCode == 303 ||
                response.statusCode == 307 ||
                response.statusCode == 308 ||
                response.statusCode < 200 ||
                response.statusCode >= 300) {
              return null;
            }
            final contentLength = response.contentLength;
            if (contentLength != null && contentLength > 50 * 1024 * 1024) {
              return null;
            }
            final contentType = response.headers['content-type']
                ?.split(';')
                .first
                .trim()
                .toLowerCase();
            if (contentType == null || !contentType.startsWith('image/')) {
              return null;
            }
            final builder = BytesBuilder(copy: false);
            await for (final chunk in response.stream) {
              if (builder.length + chunk.length > 50 * 1024 * 1024) {
                return null;
              }
              builder.add(chunk);
            }
            final bytes = builder.takeBytes();
            if (bytes.isNotEmpty && isValidImageBytes(bytes)) return bytes;
          } finally {
            client.close();
          }
        }
      }
    } catch (_) {
      debugPrint('[CanvasImageCache] Image byte read failed.');
    }

    return null;
  }

  void cacheImage(String key, ui.Image image) {
    final canonicalKey = _canonicalKey(key);
    if (canonicalKey == null) {
      image.dispose();
      return;
    }
    _cacheCanonicalImage(canonicalKey, image);
  }

  void _cacheCanonicalImage(String canonicalKey, ui.Image image) {
    if (_disposed) {
      image.dispose();
      return;
    }
    final previous = _cache[canonicalKey];
    _cache[canonicalKey] = image;
    if (previous != null && !identical(previous, image)) previous.dispose();
    _notifyRepaint();
  }

  /// Decode bytes into [ui.Image] and cache the result immediately.
  Future<ui.Image?> decodeAndCacheBytes(String key, Uint8List bytes) async {
    if (_disposed) return null;
    final generation = _generation;
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;
      if (_disposed || generation != _generation) {
        image.dispose();
        return null;
      }
      final canonicalKey = _canonicalKey(key);
      if (canonicalKey == null) {
        image.dispose();
        return null;
      }
      final previous = _cache[canonicalKey];
      _cache[canonicalKey] = image;
      if (previous != null && !identical(previous, image)) previous.dispose();
      _notifyRepaint();
      return image;
    } catch (_) {
      debugPrint('[CanvasImageCache] Image decode failed.');
      return null;
    } finally {
      codec?.dispose();
    }
  }

  /// Request loading and decoding for an artifact, private Storage source, or
  /// explicitly bounded compatibility source.
  void requestImage({
    String? storagePath,
    String? localPath,
    String? url,
    String? imageArtifactReference,
  }) {
    if (_disposed) return;
    final normalizedArtifactReference = validImageArtifactReference(
      imageArtifactReference?.trim(),
    );
    final normalizedStoragePath = storagePath?.trim();
    final normalizedLocalPath = localPath?.trim();
    final normalizedUrl = url?.trim();
    final sourceKey =
        normalizedArtifactReference ??
        (normalizedStoragePath != null && normalizedStoragePath.isNotEmpty
            ? normalizedStoragePath
            : normalizedLocalPath != null && normalizedLocalPath.isNotEmpty
            ? normalizedLocalPath
            : normalizedUrl);
    final key = _canonicalKey(sourceKey);
    if (key == null) return;
    if (_cache.containsKey(key) || _loadingKeys.contains(key)) return;

    final requestGeneration = _generation;
    final requestTicket = ++_nextRequestTicket;
    _requestTickets[key] = requestTicket;
    _loadingKeys.add(key);
    _decodeSource(
          storagePath: normalizedStoragePath,
          localPath: normalizedLocalPath,
          url: normalizedUrl,
          imageArtifactReference: normalizedArtifactReference,
        )
        .then((image) {
          final currentTicket = _requestTickets[key];
          if (currentTicket == requestTicket) _loadingKeys.remove(key);
          if (_disposed ||
              requestGeneration != _generation ||
              currentTicket != requestTicket) {
            image?.dispose();
            return;
          }
          if (image == null) return;
          _cacheCanonicalImage(key, image);
        })
        .catchError((_) {
          if (_requestTickets[key] == requestTicket) {
            _loadingKeys.remove(key);
          }
          // Do not log source values: they may contain transient credentials.
          debugPrint('[CanvasImageCache] Image load failed.');
        });
  }

  Future<ui.Image?> _decodeSource({
    String? storagePath,
    String? localPath,
    String? url,
    String? imageArtifactReference,
  }) async {
    try {
      final bytes = await loadImageBytes(
        storagePath: storagePath,
        localPath: localPath,
        url: url,
        imageArtifactReference: imageArtifactReference,
      );
      if (bytes == null || bytes.isEmpty) return null;

      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frameInfo = await codec.getNextFrame();
        return frameInfo.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      debugPrint('[CanvasImageCache] Image decode failed.');
      return null;
    }
  }

  void clear() {
    if (_disposed) return;
    _generation++;
    _requestTickets.clear();
    for (final image in _cache.values.toSet()) {
      image.dispose();
    }
    _cache.clear();
    _loadingKeys.clear();
    _notifyRepaint();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    for (final image in _cache.values.toSet()) {
      image.dispose();
    }
    _cache.clear();
    _requestTickets.clear();
    _loadingKeys.clear();
    _listeners.clear();
  }
}
