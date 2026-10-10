import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/image_artifact_store.dart';
import 'package:varian/features/ai/data/three_d_generation_provider.dart';
import 'package:varian/features/ai/domain/ai_governance.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store_types.dart';
import 'package:varian/features/model3d/data/model3d_import_service.dart';

void main() {
  test(
    '3D job artifact is imported and materialized as a model node',
    () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://worker.example/chair.glb');
        return http.Response.bytes(_minimalGlb(), 200);
      });
      final importer = Model3DImportService(
        artifactStore: MemoryModel3DArtifactStore(),
        httpClient: client,
      );
      final service = AIService(
        const BackendConfig(
          threeDEnabled: true,
          threeDBaseUrl: 'https://worker.example/v1',
          threeDProvider: 'demo',
        ),
        client,
        false,
        null,
        null,
        null,
        null,
        _FakeThreeDProvider(),
        importer,
      );
      final job = AIJob(
        id: 'job-3d',
        projectId: 'project-1',
        capability: AICapability.textTo3D,
        prompt: 'A low poly chair',
        status: AIJobStatus.processing,
        createdAt: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 10),
      );

      final completed = await service.executeJob(job, const []);
      final node = await service.spawnModel3DNodeFromJob(
        completed,
        projectId: 'project-1',
      );

      expect(completed.status, AIJobStatus.completed);
      expect(completed.resultArtifact?.kind, AIArtifactKind.model3d);
      expect(node.type, NodeType.model3d);
      final payload = node.payload as Model3DPayload;
      expect(payload.fileName, 'chair.glb');
      expect(payload.modelPath, isNull);
      expect(payload.modelUrl, isNull);
      expect(payload.artifactReference, isNotNull);
    },
  );

  test(
    'image-only text 3D providers receive a generated reference image',
    () async {
      final provider = _CapturingThreeDProvider();
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/images/generations');
        return http.Response('{"data":[{"b64_json":"aGVsbG8="}]}', 200);
      });
      final service = AIService(
        const BackendConfig(
          openAiApiKey: 'test-key',
          openAiBaseUrl: 'https://ai.example/v1',
          openAiModel: 'chat-model',
          openAiImageModel: 'image-model',
          imageApiMode: ImageApiMode.imagesGenerations,
          threeDEnabled: true,
          threeDBaseUrl: 'https://worker.example/v1',
          threeDProvider: 'trellis',
        ),
        client,
        false,
        null,
        null,
        null,
        null,
        provider,
        null,
      );
      final job = AIJob(
        id: 'job-text-to-3d',
        projectId: 'project-1',
        capability: AICapability.textTo3D,
        prompt: 'A low poly chair',
        creativeParams: const AICreativeParams(threeDProvider: 'trellis'),
        status: AIJobStatus.processing,
        createdAt: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 10),
      );

      final completed = await service.executeJob(job, const []);

      expect(completed.status, AIJobStatus.completed);
      expect(provider.sourceImageBase64, 'data:image/png;base64,aGVsbG8=');
      expect(provider.sourceImageUrl, isNull);
    },
  );

  test(
    'hosted FAL TRELLIS2 text 3D receives a generated reference image',
    () async {
      final provider = _CapturingThreeDProvider();
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/images/generations');
        return http.Response('{"data":[{"b64_json":"aGVsbG8="}]}', 200);
      });
      final service = AIService(
        const BackendConfig(
          openAiApiKey: 'test-key',
          openAiBaseUrl: 'https://ai.example/v1',
          openAiModel: 'chat-model',
          openAiImageModel: 'image-model',
          imageApiMode: ImageApiMode.imagesGenerations,
          threeDEnabled: true,
          threeDBaseUrl: 'https://worker.example/v1',
          threeDProvider: 'fal-trellis2',
        ),
        client,
        false,
        null,
        null,
        null,
        null,
        provider,
        null,
      );
      final job = AIJob(
        id: 'job-fal-text-to-3d',
        projectId: 'project-1',
        capability: AICapability.textTo3D,
        prompt: 'A low poly chair',
        creativeParams: const AICreativeParams(threeDProvider: 'fal-trellis2'),
        status: AIJobStatus.processing,
        createdAt: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 10),
      );

      final completed = await service.executeJob(job, const []);

      expect(completed.status, AIJobStatus.completed);
      expect(provider.sourceImageBase64, 'data:image/png;base64,aGVsbG8=');
      expect(provider.sourceImageUrl, isNull);
    },
  );

  test('image-to-3D resolves artifact-backed canvas image bytes', () async {
    final imageStore = MemoryImageArtifactStore();
    const sourceBytes = <int>[
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      4,
      0,
      0,
      0,
      181,
      28,
      12,
      2,
      0,
      0,
      0,
      11,
      73,
      68,
      65,
      84,
      120,
      218,
      99,
      100,
      248,
      15,
      0,
      1,
      5,
      1,
      1,
      39,
      24,
      227,
      102,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ];
    final stored = await imageStore.save(
      Uint8List.fromList(sourceBytes),
      fileName: 'canvas-source.png',
    );
    final provider = _CapturingThreeDProvider();
    final service = AIService(
      const BackendConfig(
        threeDEnabled: true,
        threeDBaseUrl: 'https://worker.example/v1',
        threeDProvider: 'demo',
      ),
      null,
      false,
      null,
      null,
      null,
      null,
      provider,
      null,
      null,
      null,
      null,
      null,
      imageStore,
    );
    final job = AIJob(
      id: 'job-image-to-3d-artifact',
      projectId: 'project-1',
      capability: AICapability.imageTo3D,
      prompt: 'Make this image into a 3D model',
      creativeParams: AICreativeParams(
        sourceImageArtifactReference: stored.reference,
        sourceImageMimeType: 'image/png',
      ),
      status: AIJobStatus.processing,
      createdAt: DateTime.utc(2026, 9, 10),
      updatedAt: DateTime.utc(2026, 9, 10),
    );

    final completed = await service.executeJob(job, const []);

    expect(completed.status, AIJobStatus.completed);
    expect(
      provider.sourceImageBase64,
      'data:image/png;base64,${base64Encode(sourceBytes)}',
    );
    expect(provider.sourceImageUrl, isNull);
  });

  test('image-to-3D resolves project-storage canvas image bytes', () async {
    const sourceBytes = <int>[
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      4,
      0,
      0,
      0,
      181,
      28,
      12,
      2,
      0,
      0,
      0,
      11,
      73,
      68,
      65,
      84,
      120,
      218,
      99,
      100,
      248,
      15,
      0,
      1,
      5,
      1,
      1,
      39,
      24,
      227,
      102,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ];
    final provider = _CapturingThreeDProvider();
    final storageSync = _StorageBackedSyncService(
      bytes: Uint8List.fromList(sourceBytes),
    );
    final service = AIService(
      const BackendConfig(
        threeDEnabled: true,
        threeDBaseUrl: 'https://worker.example/v1',
        threeDProvider: 'demo',
      ),
      null,
      false,
      null,
      null,
      null,
      null,
      provider,
      null,
      storageSync,
    );
    final job = AIJob(
      id: 'job-image-to-3d-storage',
      projectId: 'project-1',
      capability: AICapability.imageTo3D,
      prompt: 'Make this image into a 3D model',
      creativeParams: const AICreativeParams(
        sourceImageStoragePath: 'project-1/library/source.png',
        sourceImageMimeType: 'image/png',
      ),
      status: AIJobStatus.processing,
      createdAt: DateTime.utc(2026, 9, 10),
      updatedAt: DateTime.utc(2026, 9, 10),
    );

    final completed = await service.executeJob(job, const []);

    expect(
      completed.status,
      AIJobStatus.completed,
      reason: completed.errorMessage,
    );
    expect(
      provider.sourceImageBase64,
      'data:image/png;base64,${base64Encode(sourceBytes)}',
    );
    expect(provider.sourceImageUrl, isNull);
  });

  test(
    '3D retry reauthorizes through governance before calling the provider',
    () async {
      final provider = _RetryingThreeDProvider();
      final service = AIService(
        const BackendConfig(
          threeDEnabled: true,
          threeDBaseUrl: 'https://worker.example/v1',
          threeDProvider: 'demo',
        ),
        null,
        false,
        null,
        null,
        null,
        null,
        provider,
        null,
        null,
        AIGovernanceRuntime(
          policy: const AIGovernancePolicy(
            allowUnknownProviders: false,
            providers: {
              'demo': AIProviderPolicy(provider: 'demo', enabled: true),
            },
          ),
        ),
      );
      final failedJob = AIJob(
        id: 'job-3d-retry',
        projectId: 'project-1',
        capability: AICapability.textTo3D,
        prompt: 'A low poly chair',
        creativeParams: const AICreativeParams(threeDProvider: 'demo'),
        status: AIJobStatus.failed,
        createdAt: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 10),
      );

      final completed = await service.retryJob(failedJob, const []);

      expect(completed.status, AIJobStatus.completed);
      expect(provider.retryCount, 1);
      expect(completed.provenance['governanceAuthorization'], isNotNull);
      expect(completed.provenance['governance'], isNotNull);
    },
  );
}

class _FakeThreeDProvider implements ThreeDGenerationProvider {
  @override
  Future<AIArtifact> generate({
    required AIJob job,
    String? sourceImageBase64,
    String? sourceImageUrl,
  }) async => AIArtifact(
    kind: AIArtifactKind.model3d,
    reference: 'varian-model3d://fixture-12345678',
    bytes: _minimalGlb(),
    fileName: 'chair.glb',
    mimeType: 'model/gltf-binary',
    byteLength: 24,
    provider: 'demo',
  );

  @override
  Future<(bool, String?)> testConnection() async => (true, null);
}

class _CapturingThreeDProvider implements ThreeDGenerationProvider {
  String? sourceImageBase64;
  String? sourceImageUrl;

  @override
  Future<AIArtifact> generate({
    required AIJob job,
    String? sourceImageBase64,
    String? sourceImageUrl,
  }) async {
    this.sourceImageBase64 = sourceImageBase64;
    this.sourceImageUrl = sourceImageUrl;
    return AIArtifact(
      kind: AIArtifactKind.model3d,
      reference: 'varian-model3d://fixture-22345678',
      bytes: _minimalGlb(),
      fileName: 'chair.glb',
      mimeType: 'model/gltf-binary',
      byteLength: 24,
      provider: 'trellis',
    );
  }

  @override
  Future<(bool, String?)> testConnection() async => (true, null);
}

class _StorageBackedSyncService extends SupabaseSyncService {
  final Uint8List bytes;

  _StorageBackedSyncService({required this.bytes}) : super(null);

  @override
  Future<Uint8List?> readPrivateStorageBytes({
    required String projectId,
    required String path,
    String? accountId,
    required int maxBytes,
  }) async {
    expect(projectId, 'project-1');
    expect(path, 'project-1/library/source.png');
    expect(bytes.length, lessThanOrEqualTo(maxBytes));
    return Uint8List.fromList(bytes);
  }
}

class _RetryingThreeDProvider
    implements ThreeDGenerationProvider, ThreeDGenerationRetryProvider {
  int retryCount = 0;

  @override
  Future<AIArtifact> generate({
    required AIJob job,
    String? sourceImageBase64,
    String? sourceImageUrl,
  }) async => _artifact;

  @override
  Future<AIArtifact> retry({
    required AIJob job,
    String? sourceImageBase64,
    String? sourceImageUrl,
  }) async {
    retryCount += 1;
    return _artifact;
  }

  @override
  Future<(bool, String?)> testConnection() async => (true, null);

  static AIArtifact get _artifact => AIArtifact(
    kind: AIArtifactKind.model3d,
    reference: 'varian-model3d://fixture-32345678',
    bytes: _minimalGlb(),
    fileName: 'chair.glb',
    mimeType: 'model/gltf-binary',
    byteLength: 24,
    provider: 'demo',
  );
}

Uint8List _minimalGlb() {
  final bytes = Uint8List(24);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x46546C67, Endian.little);
  data.setUint32(4, 2, Endian.little);
  data.setUint32(8, bytes.length, Endian.little);
  data.setUint32(12, 4, Endian.little);
  data.setUint32(16, 0x4E4F534A, Endian.little);
  bytes.setRange(20, 24, <int>[0x7B, 0x7D, 0x20, 0x20]);
  return bytes;
}
