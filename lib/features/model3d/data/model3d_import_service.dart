import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../data/remote/external_url_policy.dart';
import '../../../data/remote/supabase_service.dart';
import 'model3d_artifact_store.dart';
import 'model3d_validation.dart';

class Model3DImportResult {
  final String fileName;
  final int byteLength;
  final Model3DArtifact artifact;
  final String? storagePath;

  const Model3DImportResult({
    required this.fileName,
    required this.byteLength,
    required this.artifact,
    this.storagePath,
  });
}

class Model3DImportService {
  final Model3DArtifactStore artifactStore;
  final SupabaseSyncService? syncService;
  final http.Client? httpClient;

  Model3DImportService({
    Model3DArtifactStore? artifactStore,
    this.syncService,
    this.httpClient,
  }) : artifactStore = artifactStore ?? createModel3DArtifactStore();

  Future<Model3DImportResult> importBytes(
    Uint8List bytes, {
    required String fileName,
    String? projectId,
  }) {
    final initiatingUserId = syncService?.currentUserId;
    return _importBytes(
      bytes,
      fileName: fileName,
      projectId: projectId,
      expectedUserId: initiatingUserId,
    );
  }

  Future<Model3DImportResult> _importBytes(
    Uint8List bytes, {
    required String fileName,
    String? projectId,
    required String? expectedUserId,
  }) async {
    if (!fileName.trim().toLowerCase().endsWith('.glb')) {
      throw const Model3DValidationException(
        'Only .glb files can be added as 3D models.',
      );
    }
    validateGlbBytes(bytes);
    final safeName = sanitizeModel3DFileName(fileName);
    final artifact = await artifactStore.save(bytes, fileName: safeName);
    final service = syncService;
    final safeProjectId = projectId?.trim();
    final cloudProjectId =
        safeProjectId != null &&
            safeProjectId == projectId &&
            RegExp(
              r'^[A-Za-z0-9_-][A-Za-z0-9._-]{0,119}$',
            ).hasMatch(safeProjectId) &&
            !safeProjectId.endsWith('.')
        ? safeProjectId
        : null;
    var cloudUploadAuthorized = false;
    if (service?.isConfigured == true &&
        cloudProjectId != null &&
        expectedUserId != null &&
        expectedUserId.isNotEmpty &&
        service?.currentUserId == expectedUserId) {
      try {
        await service!.verifyProjectOwnership(
          cloudProjectId,
          expectedUserId: expectedUserId,
        );
        cloudUploadAuthorized = service.currentUserId == expectedUserId;
      } catch (_) {
        // Cloud ownership failures do not block the durable local import.
      }
    }
    String? storagePath;
    if (cloudUploadAuthorized && service != null && expectedUserId != null) {
      try {
        storagePath = await service.uploadAssetForProjectEditor(
          bucket: 'assets',
          path: '$cloudProjectId/generated-models3d/${const Uuid().v4()}.glb',
          bytes: bytes,
          contentType: 'model/gltf-binary',
          expectedUserId: expectedUserId,
        );
        if (service.currentUserId != expectedUserId) storagePath = null;
      } catch (_) {
        // Local storage is the source of truth for an imported model.
      }
    }
    return Model3DImportResult(
      fileName: safeName,
      byteLength: bytes.length,
      artifact: artifact,
      storagePath: storagePath,
    );
  }

  Future<Model3DImportResult> importRemoteUrl(
    String url, {
    required String fileName,
    String? projectId,
    http.Client? client,
  }) async {
    final initiatingUserId = syncService?.currentUserId;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !_isAllowedModelUrl(uri)) {
      throw const Model3DValidationException(
        'The generated model URL is not safe to fetch.',
      );
    }
    final requestClient = client ?? httpClient ?? http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Accept'] = 'model/gltf-binary,application/octet-stream';
      final streamed = await requestClient
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (streamed.isRedirect ||
          streamed.statusCode == 301 ||
          streamed.statusCode == 302 ||
          streamed.statusCode == 303 ||
          streamed.statusCode == 307 ||
          streamed.statusCode == 308) {
        throw const Model3DValidationException(
          'The generated model URL redirected and was rejected.',
        );
      }
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw Model3DValidationException(
          'The generated model could not be downloaded (HTTP ${streamed.statusCode}).',
        );
      }
      final contentLength = streamed.contentLength;
      if (contentLength != null && contentLength > 64 * 1024 * 1024) {
        throw const Model3DValidationException(
          'The generated model is larger than the 64 MB limit.',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        if (builder.length + chunk.length > 64 * 1024 * 1024) {
          throw const Model3DValidationException(
            'The generated model is larger than the 64 MB limit.',
          );
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        throw const Model3DValidationException(
          'The generated model response was empty.',
        );
      }
      validateGlbBytes(bytes);
      return _importBytes(
        bytes,
        fileName: fileName,
        projectId: projectId,
        expectedUserId: initiatingUserId,
      );
    } on Model3DValidationException {
      rethrow;
    } on http.ClientException {
      throw const Model3DValidationException(
        'The generated model worker is unreachable.',
      );
    } finally {
      if (client == null && httpClient == null) requestClient.close();
    }
  }

  bool _isAllowedModelUrl(Uri uri) {
    if (uri.scheme == 'http') {
      final host = uri.host.toLowerCase();
      return host == 'localhost' || host == '127.0.0.1' || host == '::1';
    }
    return ExternalUrlPolicy.publicUri(uri.toString()) != null;
  }
}
