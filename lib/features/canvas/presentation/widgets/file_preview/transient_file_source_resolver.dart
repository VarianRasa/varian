import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../../../data/artifacts/artifact_store_bundle.dart';
import '../../../../../data/remote/external_url_policy.dart';
import '../../../../../data/remote/supabase_storage_path_resolver.dart';
import '../../../../../domain/models/durable_asset_reference.dart';
import '../../../../../domain/models/node_payload.dart';
import '../../../../assets/data/file_artifact_store.dart';
import 'file_preview_source.dart';

const maxTransientFileBytes = 100 * 1024 * 1024;

typedef TransientStorageBytesReader =
    Future<Uint8List?> Function({
      required String projectId,
      required String? storagePath,
      required String? source,
      required String? expectedUserId,
      required int maxBytes,
    });

/// Resolves file/PDF bytes without exposing signed delivery URLs or native
/// paths to preview consumers.
class TransientFileSourceResolver {
  final SupabaseStoragePathResolver? storageResolver;
  final String? projectId;
  final String? expectedUserId;
  final TransientStorageBytesReader? storageReader;
  final http.Client? httpClient;
  final FileArtifactStore? fileArtifactStore;
  final ArtifactStoreBundle? artifactStoreBundle;

  const TransientFileSourceResolver({
    this.storageResolver,
    this.projectId,
    this.expectedUserId,
    this.storageReader,
    this.httpClient,
    this.fileArtifactStore,
    this.artifactStoreBundle,
  });

  Future<Uint8List?> resolveBytes(
    FilePayload payload, {
    int maxBytes = maxTransientFileBytes,
  }) async {
    if (maxBytes <= 0) return null;

    final artifactReference = validFileArtifactReference(
      payload.artifactReference,
    );
    if (artifactReference != null) {
      final store =
          fileArtifactStore ??
          artifactStoreBundle?.fileArtifactStore ??
          createFileArtifactStore();
      final artifact = await store.hydrate(
        artifactReference,
        fileName: payload.fileName,
      );
      if (artifact != null) {
        final bytes = await store.read(artifact);
        await store.dispose(artifact);
        if (bytes != null && bytes.isNotEmpty && bytes.length <= maxBytes) {
          return bytes;
        }
      }
    }

    final inline = _decodeBase64(payload.base64Data, maxBytes: maxBytes);
    if (inline != null &&
        inline.isNotEmpty &&
        _isCompatibleBytes(payload, inline)) {
      return inline;
    }

    final storagePath = payload.storagePath?.trim();
    if (storagePath != null && storagePath.isNotEmpty) {
      final reader = storageReader;
      final activeProjectId = projectId?.trim();
      if (reader != null &&
          activeProjectId != null &&
          activeProjectId.isNotEmpty) {
        final bytes = await reader(
          projectId: activeProjectId,
          storagePath: storagePath,
          source: payload.remoteUrl,
          expectedUserId: expectedUserId,
          maxBytes: maxBytes,
        );
        if (bytes != null &&
            bytes.isNotEmpty &&
            _isCompatibleBytes(payload, bytes)) {
          return bytes;
        }
      } else {
        final resolver = storageResolver;
        if (resolver != null &&
            activeProjectId != null &&
            activeProjectId.isNotEmpty) {
          final bytes = await resolver.readBytes(
            projectId: activeProjectId,
            storagePath: storagePath,
            source: payload.remoteUrl,
            expectedUserId: expectedUserId,
            maxBytes: maxBytes,
          );
          if (bytes != null &&
              bytes.isNotEmpty &&
              _isCompatibleBytes(payload, bytes)) {
            return bytes;
          }
        }
      }
    }

    final localPath = payload.localPath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      try {
        final bytes = await readLocalPreviewBytes(
          localPath,
          maxBytes: maxBytes,
        );
        if (bytes != null &&
            bytes.isNotEmpty &&
            _isCompatibleBytes(payload, bytes)) {
          return bytes;
        }
      } catch (_) {}
    }

    final uri = publicUri(payload.remoteUrl);
    if (uri == null) return null;
    final bytes = await _readPublicBytes(uri, maxBytes: maxBytes);
    return bytes != null && _isCompatibleBytes(payload, bytes) ? bytes : null;
  }

  bool hasSource(FilePayload payload) {
    if (validFileArtifactReference(payload.artifactReference) != null) {
      return true;
    }
    if (payload.storagePath?.trim().isNotEmpty == true) {
      return true;
    }
    if (payload.base64Data?.trim().isNotEmpty == true) {
      return true;
    }
    if (payload.localPath?.trim().isNotEmpty == true) {
      return true;
    }
    return publicUri(payload.remoteUrl) != null;
  }

  Uri? publicUri(String? value) => ExternalUrlPolicy.publicUri(value);

  Future<Uint8List?> _readPublicBytes(Uri uri, {required int maxBytes}) async {
    final client = httpClient ?? http.Client();
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.isRedirect ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        return null;
      }
      if (response.contentLength != null &&
          response.contentLength! > maxBytes) {
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (builder.length + chunk.length > maxBytes) return null;
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    } finally {
      if (httpClient == null) client.close();
    }
  }

  static bool _isCompatibleBytes(FilePayload payload, Uint8List bytes) {
    final extension = payload.fileExtension.trim().toLowerCase();
    if (extension == 'pdf') return _startsWithAscii(bytes, '%PDF-');
    return true;
  }

  static bool _startsWithAscii(Uint8List bytes, String value) {
    if (bytes.length < value.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  static Uint8List? _decodeBase64(String? value, {required int maxBytes}) {
    final encoded = value?.trim();
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final data = encoded.contains(',')
          ? encoded.substring(encoded.indexOf(',') + 1)
          : encoded;
      final bytes = base64Decode(data);
      if (bytes.isEmpty || bytes.length > maxBytes) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }
}

TransientFileSourceResolver resolverForStorage({
  required SupabaseStoragePathResolver resolver,
  required String projectId,
  String? expectedUserId,
  ArtifactStoreBundle? artifactStoreBundle,
}) => TransientFileSourceResolver(
  storageResolver: resolver,
  projectId: projectId,
  expectedUserId: expectedUserId,
  artifactStoreBundle: artifactStoreBundle,
);
