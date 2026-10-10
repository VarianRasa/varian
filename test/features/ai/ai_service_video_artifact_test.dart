import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/video_artifact_store.dart';
import 'package:varian/features/ai/data/video_provider.dart';

const _minimalJpegBytes = <int>[255, 216, 255];

Uint8List _minimalMp4() => Uint8List.fromList([
  0,
  0,
  0,
  16,
  102,
  116,
  121,
  112,
  105,
  115,
  111,
  109,
  0,
  0,
  0,
  0,
]);

class _FakeProvider implements VideoProviderClient {
  final String status;
  final Uint8List bytes;
  _FakeProvider(this.status, this.bytes);

  @override
  Future<VideoProviderJob> createImageToVideo({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String prompt,
    required String duration,
    required String aspectRatio,
  }) async => VideoProviderJob(requestId: 'v1', status: status);

  @override
  Future<VideoProviderJob> poll(String requestId) async =>
      const VideoProviderJob(requestId: 'v1', status: 'completed');

  @override
  Future<Uint8List> downloadContent(String requestId) async => bytes;

  @override
  Future<(bool, String?)> testConnection() async => (true, null);
}

http.Client _imageClient() => MockClient(
  (request) async => http.Response.bytes(
    _minimalJpegBytes,
    200,
    headers: {'content-type': 'image/jpeg'},
    request: request,
  ),
);

void main() {
  test('does not create a node from an invalid completed artifact', () async {
    final service = AIService(
      BackendConfig(
        videoApiKey: String.fromCharCodes(const [107]),
        videoModel: 'video-model',
      ),
      _imageClient(),
      false,
      _FakeProvider('completed', Uint8List.fromList([1, 2, 3])),
      MemoryVideoArtifactStore(),
      (_) async {},
    );
    final now = DateTime.now();
    final job = AIJob(
      id: 'job',
      projectId: 'project',
      capability: AICapability.imageToVideo,
      prompt: 'animate',
      creativeParams: const AICreativeParams(
        sourceImageUrl: 'https://example.com/source.png',
      ),
      createdAt: now,
      updatedAt: now,
    );

    final result = await service.executeJob(job, const []);
    expect(result.status, AIJobStatus.failed);
  });

  test('stores a valid provider artifact as a local result', () async {
    final service = AIService(
      BackendConfig(
        videoApiKey: String.fromCharCodes(const [107]),
        videoModel: 'video-model',
      ),
      _imageClient(),
      false,
      _FakeProvider('completed', _minimalMp4()),
      MemoryVideoArtifactStore(),
      (_) async {},
    );
    final now = DateTime.now();
    final result = await service.executeJob(
      AIJob(
        id: 'job',
        projectId: 'project',
        capability: AICapability.imageToVideo,
        prompt: 'animate',
        creativeParams: const AICreativeParams(
          sourceImageUrl: 'https://example.com/source.png',
        ),
        createdAt: now,
        updatedAt: now,
      ),
      const [],
    );

    expect(result.status, AIJobStatus.completed);
    expect(result.resultVideoPath, isNull);
    expect(result.resultVideoUrl, isNull);
    expect(result.resultVideoReference, startsWith('varian-video://'));
    expect(result.resultArtifact?.kind, AIArtifactKind.video);
  });
}
