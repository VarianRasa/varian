import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/video_artifact_store.dart';
import 'package:varian/features/ai/data/video_provider.dart';

const _minimalPngBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];

const _validPngBytes = <int>[
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

AIJob _videoJob({AICreativeParams? creativeParams}) {
  final now = DateTime(2026, 8, 24);
  return AIJob(
    id: 'video-job',
    projectId: 'project',
    capability: AICapability.imageToVideo,
    prompt: 'animate the facade',
    creativeParams: creativeParams,
    status: AIJobStatus.processing,
    createdAt: now,
    updatedAt: now,
  );
}

String _testVideoKey() =>
    String.fromCharCodes(const [118, 105, 100, 101, 111, 45, 107, 101, 121]);

BackendConfig _videoConfig({String? baseUrl}) => BackendConfig(
  videoApiKey: _testVideoKey(),
  videoApiBaseUrl: baseUrl ?? '',
  videoModel: 'video-model',
);

class _FakeVideoProvider implements VideoProviderClient {
  final List<VideoProviderJob> polls;
  final Uint8List content;
  int pollCount = 0;
  int createCount = 0;

  _FakeVideoProvider({required this.polls, required this.content});

  @override
  Future<VideoProviderJob> createImageToVideo({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String prompt,
    required String duration,
    required String aspectRatio,
  }) async {
    createCount++;
    expect(imageBytes, _minimalPng());
    expect(imageMimeType, 'image/png');
    expect(prompt, 'animate the facade');
    expect(duration, '4');
    expect(aspectRatio, '16:9');
    return const VideoProviderJob(requestId: 'v1', status: 'queued');
  }

  @override
  Future<VideoProviderJob> poll(String requestId) async {
    final index = pollCount < polls.length ? pollCount : polls.length - 1;
    pollCount++;
    return polls[index];
  }

  @override
  Future<Uint8List> downloadContent(String requestId) async => content;

  @override
  Future<(bool, String?)> testConnection() async => (true, null);
}

Uint8List _minimalPng() => Uint8List.fromList(_minimalPngBytes);

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
    expect(projectId, 'project');
    expect(path, 'project-1/library/source.png');
    expect(bytes.length, lessThanOrEqualTo(maxBytes));
    return Uint8List.fromList(bytes);
  }
}

void main() {
  test('polls direct provider and stores the completed MP4 artifact', () async {
    final provider = _FakeVideoProvider(
      polls: const [VideoProviderJob(requestId: 'v1', status: 'completed')],
      content: _minimalMp4(),
    );
    final store = MemoryVideoArtifactStore();

    final result =
        await AIService(
          _videoConfig(baseUrl: 'https://provider.test/v1'),
          null,
          false,
          provider,
          store,
          (_) async {},
        ).executeJob(
          _videoJob(
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_minimalPngBytes),
            ),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed);
    expect(result.isSimulated, isFalse);
    expect(result.resultAssetUrl, isNull);
    expect(result.resultVideoPath, isNull);
    expect(result.resultVideoUrl, isNull);
    expect(result.resultVideoReference, startsWith('varian-video://'));
    expect(provider.pollCount, 1);
  });

  test('Wan BYOK generation stores the video artifact for the canvas', () async {
    final paths = <String>[];
    final authorizationByPath = <String, String?>{};
    final client = MockClient((request) async {
      paths.add(request.url.path);
      authorizationByPath[request.url.path] = request.headers['authorization'];
      if (request.url.path == '/gradio_api/call/generate_video') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final data = payload['data'] as List;
        expect(data[1], 'animate the facade');
        expect(data[2], 512);
        expect(data[3], 896);
        return http.Response(
          jsonEncode({'event_id': 'wan-job'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/gradio_api/call/generate_video/wan-job') {
        return http.Response(
          [
            'event: complete',
            'data: [{"video":{"path":"/tmp/v.mp4","url":"https://custom.hf.space/gradio_api/file=video.mp4"}},42]',
            '',
          ].join('\n'),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      if (request.url.path == '/gradio_api/file=video.mp4') {
        return http.Response.bytes(
          _minimalMp4(),
          200,
          headers: {'content-type': 'video/mp4'},
        );
      }
      return http.Response('unexpected request', 500);
    });
    addTearDown(client.close);
    final store = MemoryVideoArtifactStore();

    final result =
        await AIService(
          const BackendConfig(
            wanHfSpaceUrl: 'https://custom.hf.space',
            wanHfToken: 'hf_video_token',
            videoProviderMode: VideoProviderMode.wanGradio,
          ),
          client,
          false,
          null,
          store,
          (_) async {},
        ).executeJob(
          _videoJob(
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_validPngBytes),
            ),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed);
    expect(result.resultVideoReference, startsWith('varian-video://'));
    expect(result.resultArtifact?.kind, AIArtifactKind.video);
    expect(paths, [
      '/gradio_api/call/generate_video',
      '/gradio_api/call/generate_video/wan-job',
      '/gradio_api/file=video.mp4',
    ]);
    expect(
      authorizationByPath['/gradio_api/call/generate_video'],
      'Bearer hf_video_token',
    );
    expect(
      authorizationByPath['/gradio_api/call/generate_video/wan-job'],
      'Bearer hf_video_token',
    );
  });

  test('reports unsupported primary without sending to public Wan', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return http.Response('not found', 404);
    });
    addTearDown(client.close);

    final result =
        await AIService(
          _videoConfig(baseUrl: 'https://provider.test/v1'),
          client,
          false,
          null,
          MemoryVideoArtifactStore(),
          (_) async {},
        ).executeJob(
          _videoJob(
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_validPngBytes),
            ),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.failed);
    expect(result.errorMessage, contains('does not support'));
    expect(paths, ['/v1/videos']);
  });

  test('keeps a supported primary provider on the primary path', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path == '/v1/videos') {
        if (request.method == 'GET') return http.Response('{}', 200);
        return http.Response(
          jsonEncode({'id': 'primary-job', 'status': 'queued'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/v1/videos/primary-job') {
        return http.Response(
          jsonEncode({'id': 'primary-job', 'status': 'completed'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/v1/videos/primary-job/content') {
        return http.Response.bytes(
          _minimalMp4(),
          200,
          headers: {'content-type': 'video/mp4'},
        );
      }
      return http.Response('unexpected request', 500);
    });
    addTearDown(client.close);

    final result =
        await AIService(
          _videoConfig(baseUrl: 'https://provider.test/v1'),
          client,
          false,
          null,
          MemoryVideoArtifactStore(),
          (_) async {},
        ).executeJob(
          _videoJob(
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_validPngBytes),
            ),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed);
    expect(paths, [
      '/v1/videos',
      '/v1/videos',
      '/v1/videos/primary-job',
      '/v1/videos/primary-job/content',
    ]);
  });

  test(
    'does not start Wan after the primary create returns HTTP 500',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/v1/videos' && request.method == 'GET') {
          return http.Response('{}', 200);
        }
        if (request.url.path == '/v1/videos' && request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'error': {'message': 'backend unavailable'},
            }),
            500,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('unexpected request', 500);
      });
      addTearDown(client.close);

      final result =
          await AIService(
            _videoConfig(baseUrl: 'https://provider.test/v1'),
            client,
            false,
            null,
            MemoryVideoArtifactStore(),
            (_) async {},
          ).executeJob(
            _videoJob(
              creativeParams: AICreativeParams(
                sourceImageBase64: base64Encode(_validPngBytes),
              ),
            ),
            const [],
          );

      expect(result.status, AIJobStatus.failed);
      expect(result.errorMessage, contains('HTTP 500'));
      expect(requests, ['GET /v1/videos', 'POST /v1/videos']);
    },
  );

  test('resolves private storage image paths for video generation', () async {
    final storageSync = _StorageBackedSyncService(bytes: _minimalPng());
    final provider = _FakeVideoProvider(
      polls: const [VideoProviderJob(requestId: 'v1', status: 'completed')],
      content: _minimalMp4(),
    );
    final result =
        await AIService(
          _videoConfig(),
          null,
          false,
          provider,
          MemoryVideoArtifactStore(),
          (_) async {},
          null,
          null,
          null,
          storageSync,
        ).executeJob(
          _videoJob(
            creativeParams: const AICreativeParams(
              sourceImageStoragePath: 'project-1/library/source.png',
              sourceImageMimeType: 'image/png',
            ),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
    expect(provider.createCount, 1);
  });

  test('rejects decoded non-image base64 before provider submission', () async {
    final provider = _FakeVideoProvider(
      polls: const [VideoProviderJob(requestId: 'v1', status: 'completed')],
      content: _minimalMp4(),
    );

    final result =
        await AIService(
          _videoConfig(),
          null,
          false,
          provider,
          MemoryVideoArtifactStore(),
          (_) async {},
        ).executeJob(
          _videoJob(
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(const [1, 2, 3]),
            ),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.failed);
    expect(
      result.errorMessage,
      'The selected image bytes are not a valid PNG, JPEG, or WebP image.',
    );
    expect(provider.createCount, 0);
  });

  test('rejects malformed base64 before provider submission', () async {
    final provider = _FakeVideoProvider(
      polls: const [VideoProviderJob(requestId: 'v1', status: 'completed')],
      content: _minimalMp4(),
    );

    final result =
        await AIService(
          _videoConfig(),
          null,
          false,
          provider,
          MemoryVideoArtifactStore(),
          (_) async {},
        ).executeJob(
          _videoJob(
            creativeParams: const AICreativeParams(sourceImageBase64: '%%%'),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.failed);
    expect(result.errorMessage, 'The selected image base64 is invalid.');
    expect(provider.createCount, 0);
  });

  test(
    'rejects invalid downloaded image bytes before provider submission',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      addTearDown(client.close);
      final provider = _FakeVideoProvider(
        polls: const [VideoProviderJob(requestId: 'v1', status: 'completed')],
        content: _minimalMp4(),
      );

      final result =
          await AIService(
            _videoConfig(),
            client,
            false,
            provider,
            MemoryVideoArtifactStore(),
            (_) async {},
          ).executeJob(
            _videoJob(
              creativeParams: const AICreativeParams(
                sourceImageUrl: 'https://example.com/image.png',
              ),
            ),
            const [],
          );

      expect(result.status, AIJobStatus.failed);
      expect(
        result.errorMessage,
        'The selected image bytes are not a valid PNG, JPEG, or WebP image.',
      );
      expect(requests, 1);
      expect(provider.createCount, 0);
    },
  );

  test('redacts provider URLs and credentials from failures', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {
            'message':
                'download https://cdn.example.test/out.mp4?token=secret '
                'with bearer secret-token',
          },
        }),
        500,
      );
    });
    addTearDown(client.close);

    final result =
        await AIService(
          _videoConfig(baseUrl: 'https://provider.test/v1'),
          client,
          false,
          null,
          MemoryVideoArtifactStore(),
          (_) async {},
        ).executeJob(
          _videoJob(
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_minimalPngBytes),
            ),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.failed);
    expect(result.errorMessage, isNot(contains('token=secret')));
    expect(result.errorMessage, isNot(contains('secret-token')));
    expect(result.errorMessage, contains('[redacted URL]'));
  });

  test('returns a safe failure when the provider is not configured', () async {
    final provider = _FakeVideoProvider(
      polls: const [
        VideoProviderJob(
          requestId: 'v1',
          status: 'failed',
          errorMessage: 'Provider rejected the source image.',
        ),
      ],
      content: _minimalMp4(),
    );

    final result =
        await AIService(
          _videoConfig(),
          null,
          false,
          provider,
          MemoryVideoArtifactStore(),
          (_) async {},
        ).executeJob(
          _videoJob(
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_minimalPngBytes),
            ),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.failed);
    expect(result.errorMessage, contains('Provider rejected the source image'));
  });

  test('stops after the bounded polling window', () async {
    final provider = _FakeVideoProvider(
      polls: const [VideoProviderJob(requestId: 'v1', status: 'queued')],
      content: _minimalMp4(),
    );

    final result =
        await AIService(
          _videoConfig(),
          null,
          false,
          provider,
          MemoryVideoArtifactStore(),
          (_) async {},
        ).executeJob(
          _videoJob(
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_minimalPngBytes),
            ),
          ),
          const [],
        );

    expect(result.status, AIJobStatus.failed);
    expect(result.errorMessage, contains('timed out'));
    expect(provider.pollCount, 150);
  });
}
