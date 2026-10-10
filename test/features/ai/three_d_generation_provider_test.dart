import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/features/ai/data/three_d_generation_provider.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10);

  AIJob job() => AIJob(
    id: 'job-1',
    projectId: 'project-1',
    capability: AICapability.textTo3D,
    prompt: 'A low poly chair',
    status: AIJobStatus.processing,
    createdAt: now,
    updatedAt: now,
  );

  test('creates and polls a 3D job until a GLB artifact is returned', () async {
    final requests = <http.BaseRequest>[];
    var pollCount = 0;
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST' && request.url.path == '/v1/3d/jobs') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['prompt'], 'A low poly chair');
        expect(body['projectId'], 'project-1');
        return http.Response(
          jsonEncode({'jobId': 'provider-job-1', 'status': 'queued'}),
          202,
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/v1/3d/jobs/provider-job-1') {
        pollCount += 1;
        if (pollCount == 1) {
          return http.Response(
            jsonEncode({
              'jobId': 'provider-job-1',
              'status': 'processing',
              'progress': 42,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'jobId': 'provider-job-1',
            'status': 'completed',
            'progress': 100,
            'artifact': {
              'kind': 'model3d',
              'url': 'https://cdn.example.test/chair.glb',
              'reference': 'projects/project-1/models/chair.glb',
              'fileName': 'chair.glb',
              'mimeType': 'model/gltf-binary',
              'byteLength': 4096,
              'provider': 'triposr',
            },
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final provider = HttpThreeDGenerationProvider(
      baseUrl: 'https://worker.example.test/v1',
      client: client,
      pollDelay: (_) async {},
    );

    final artifact = await provider.generate(job: job());

    expect(artifact.kind, AIArtifactKind.model3d);
    expect(artifact.url, isNull);
    expect(artifact.reference, 'projects/project-1/models/chair.glb');
    expect(artifact.fileName, 'chair.glb');
    expect(artifact.byteLength, 4096);
    expect(requests.map((request) => request.method), ['POST', 'GET', 'GET']);
  });

  test('fails closed when the worker returns an invalid artifact', () async {
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({'jobId': 'provider-job-2', 'status': 'queued'}),
          202,
        );
      }
      return http.Response(
        jsonEncode({'jobId': 'provider-job-2', 'status': 'completed'}),
        200,
      );
    });

    final provider = HttpThreeDGenerationProvider(
      baseUrl: 'https://worker.example.test/v1',
      client: client,
      pollDelay: (_) async {},
    );

    await expectLater(
      provider.generate(job: job()),
      throwsA(isA<ThreeDGenerationException>()),
    );
  });

  test('retries a failed job through the retry endpoint', () async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST' &&
          request.url.path == '/v1/3d/jobs/job-1/retry') {
        return http.Response(
          jsonEncode({'jobId': 'provider-job-retry', 'status': 'queued'}),
          202,
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/v1/3d/jobs/provider-job-retry') {
        return http.Response(
          jsonEncode({
            'jobId': 'provider-job-retry',
            'status': 'completed',
            'progress': 100,
            'artifact': {
              'kind': 'model3d',
              'url': 'https://cdn.example.test/retry.glb',
              'reference': 'projects/project-1/models/retry.glb',
              'fileName': 'retry.glb',
              'mimeType': 'model/gltf-binary',
              'byteLength': 2048,
              'provider': 'triposr',
            },
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final provider = HttpThreeDGenerationProvider(
      baseUrl: 'https://worker.example.test/v1',
      client: client,
      pollDelay: (_) async {},
    );

    final artifact = await provider.retry(job: job());

    expect(artifact.fileName, 'retry.glb');
    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'POST /v1/3d/jobs/job-1/retry',
      'GET /v1/3d/jobs/provider-job-retry',
    ]);
  });
}
