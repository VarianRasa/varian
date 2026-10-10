import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/features/ai/data/video_provider.dart';

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
  16,
]);

const _minimalPngBytes = <int>[
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

Uint8List _minimalPng() => Uint8List.fromList(_minimalPngBytes);

String _testApiKey() =>
    String.fromCharCodes(const [118, 105, 100, 101, 111, 45, 107, 101, 121]);

void main() {
  test('parses queued create response', () {
    final job = VideoProviderJob.fromJson({'id': 'v1', 'status': 'queued'});
    expect(job.requestId, 'v1');
    expect(job.status, 'queued');
  });

  test('rejects an unknown provider status', () {
    expect(
      () => VideoProviderJob.fromJson({'id': 'v1', 'status': 'waiting'}),
      throwsA(isA<VideoProviderException>()),
    );
  });

  test('submits image reference with its media type', () async {
    String? requestMethod;
    Uri? requestUri;
    String? authorization;
    Map<String, String>? fields;
    String? uploadedField;
    String? uploadedMediaType;
    String? uploadedFileName;
    int? uploadedLength;
    final client = MockClient.streaming((request, body) async {
      requestMethod = request.method;
      requestUri = request.url;
      authorization = request.headers['authorization'];
      final multipart = request as http.MultipartRequest;
      fields = Map<String, String>.from(multipart.fields);
      uploadedField = multipart.files.single.field;
      uploadedMediaType = multipart.files.single.contentType.mimeType;
      uploadedFileName = multipart.files.single.filename;
      uploadedLength = multipart.files.single.length;
      await body.toBytes();
      return http.StreamedResponse(
        http.ByteStream.fromBytes(
          utf8.encode(jsonEncode({'id': 'v1', 'status': 'queued'})),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    final job = await provider.createImageToVideo(
      imageBytes: _minimalPng(),
      imageMimeType: 'image/png',
      prompt: 'animate the image',
      duration: '4',
      aspectRatio: '16:9',
    );

    expect(job.requestId, 'v1');
    expect(requestMethod, 'POST');
    expect(requestUri, Uri.parse('https://provider.test/v1/videos'));
    expect(authorization, ['Bearer', _testApiKey()].join(' '));
    expect(fields, {
      'model': 'video-model',
      'prompt': 'animate the image',
      'seconds': '4',
      'size': '1280x720',
    });
    expect(uploadedField, 'input_reference');
    expect(uploadedMediaType, 'image/png');
    expect(uploadedFileName, 'input.png');
    expect(uploadedLength, greaterThan(0));
  });

  test('includes a safe provider error message for HTTP 500', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'server_error',
            'message': 'The selected video model is unavailable.',
          },
        }),
        500,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    expect(
      () => provider.createImageToVideo(
        imageBytes: _minimalPng(),
        imageMimeType: 'image/png',
        prompt: 'animate',
        duration: '4',
        aspectRatio: '16:9',
      ),
      throwsA(
        isA<VideoProviderException>()
            .having((error) => error.code, 'code', 'VIDEO_GENERATION_FAILED')
            .having(
              (error) => error.message,
              'message',
              contains('The selected video model is unavailable.'),
            ),
      ),
    );
  });

  test(
    'extracts a provider request ID from an error response header',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          'Internal Server Error',
          500,
          headers: {
            'content-type': 'text/plain',
            'x-request-id': 'req_header_123',
          },
        ),
      );
      addTearDown(client.close);

      final provider = OpenAiVideosProviderClient(
        baseUrl: 'https://provider.test/v1',
        apiKey: _testApiKey(),
        model: 'video-model',
        client: client,
      );

      try {
        await provider.createImageToVideo(
          imageBytes: _minimalPng(),
          imageMimeType: 'image/png',
          prompt: 'animate',
          duration: '4',
          aspectRatio: '16:9',
        );
        fail('Expected VideoProviderException');
      } on VideoProviderException catch (error) {
        expect(error.providerRequestId, 'req_header_123');
        expect(error.message, contains('Internal Server Error'));
        expect(error.message, contains('req_header_123'));
      }
    },
  );

  test('extracts a top-level provider request ID from an error body', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'request_id': 'req_body_456',
          'error': {'message': 'backend unavailable'},
        }),
        500,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    try {
      await provider.createImageToVideo(
        imageBytes: _minimalPng(),
        imageMimeType: 'image/png',
        prompt: 'animate',
        duration: '4',
        aspectRatio: '16:9',
      );
      fail('Expected VideoProviderException');
    } on VideoProviderException catch (error) {
      expect(error.providerRequestId, 'req_body_456');
      expect(error.message, contains('backend unavailable'));
    }
  });

  test('keeps request ID and safe detail on an HTTP 500 response', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'request_id': 'req_500',
          'error': {'message': 'backend unavailable'},
        }),
        500,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    try {
      await provider.poll('video-1');
      fail('Expected VideoProviderException');
    } on VideoProviderException catch (error) {
      expect(error.code, 'VIDEO_GENERATION_FAILED');
      expect(error.statusCode, 500);
      expect(error.providerRequestId, 'req_500');
      expect(error.message, contains('HTTP 500'));
      expect(error.message, contains('backend unavailable'));
      expect(error.message, isNot(contains(_testApiKey())));
    }
  });

  test('maps provider auth errors without exposing response details', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'error': 'fixture provider detail'}),
        401,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    try {
      await provider.createImageToVideo(
        imageBytes: _minimalPng(),
        imageMimeType: 'image/png',
        prompt: 'animate',
        duration: '4',
        aspectRatio: '16:9',
      );
      fail('Expected VideoProviderException');
    } on VideoProviderException catch (error) {
      expect(error.code, 'VIDEO_AUTH_ERROR');
      expect(error.message, isNot(contains('fixture provider detail')));
      expect(error.message, isNot(contains(_testApiKey())));
    }
  });

  test('tests provider capability without creating a video job', () async {
    final paths = <String>[];
    final methods = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      methods.add(request.method);
      if (request.url.path.endsWith('/videos')) {
        return http.Response('{}', 200);
      }
      return http.Response(
        jsonEncode({'data': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    final result = await provider.testConnection();
    expect(result.$1, isTrue);
    expect(result.$2, contains('model list is empty'));
    expect(paths, ['/v1/videos', '/v1/models']);
    expect(methods, ['GET', 'GET']);
  });

  test('bridge preflight blocks create when videos are unsupported', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add('${request.method} ${request.url.path}');
      return http.Response('not supported', 501);
    });
    addTearDown(client.close);

    var ensureReadyCalls = 0;
    final provider = ComfyUiBridgeVideoProviderClient(
      delegate: OpenAiVideosProviderClient(
        baseUrl: 'http://127.0.0.1:20129/v1',
        apiKey: 'bridge-token',
        model: 'ltx-video-0.9.5-2b-low-vram',
        client: client,
      ),
      ensureReady: () async {
        ensureReadyCalls++;
      },
    );

    await expectLater(
      provider.createImageToVideo(
        imageBytes: _minimalPng(),
        imageMimeType: 'image/png',
        prompt: 'animate',
        duration: '4',
        aspectRatio: '16:9',
      ),
      throwsA(
        isA<VideoProviderException>().having(
          (error) => error.code,
          'code',
          'VIDEO_UNSUPPORTED_PROVIDER',
        ),
      ),
    );
    expect(ensureReadyCalls, 1);
    expect(paths, ['GET /v1/videos']);
  });

  test(
    'reports a configured model missing from the provider model list',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': [
              {'id': 'another-video-model'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      addTearDown(client.close);

      final provider = OpenAiVideosProviderClient(
        baseUrl: 'https://provider.test/v1',
        apiKey: _testApiKey(),
        model: 'video-model',
        client: client,
      );

      final result = await provider.testConnection();
      expect(result.$1, isFalse);
      expect(result.$2, contains('video-model'));
    },
  );

  test(
    'reports malformed model-list responses as a failed connection test',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          'not json',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      addTearDown(client.close);

      final provider = OpenAiVideosProviderClient(
        baseUrl: 'https://provider.test/v1',
        apiKey: _testApiKey(),
        model: 'video-model',
        client: client,
      );

      final result = await provider.testConnection();
      expect(result.$1, isFalse);
      expect(result.$2, contains('malformed'));
    },
  );

  test('maps a provider contract rejection to a configuration error', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'seconds is not supported',
          },
        }),
        422,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    expect(
      () => provider.createImageToVideo(
        imageBytes: _minimalPng(),
        imageMimeType: 'image/png',
        prompt: 'animate',
        duration: '4',
        aspectRatio: '16:9',
      ),
      throwsA(
        isA<VideoProviderException>()
            .having((error) => error.code, 'code', 'VIDEO_CONFIGURATION_ERROR')
            .having(
              (error) => error.message,
              'message',
              contains('seconds is not supported'),
            ),
      ),
    );
  });

  test(
    'maps provider server errors without exposing full response bodies',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'server_error',
              'message': 'backend unavailable',
              'debug': 'do not expose this body',
            },
          }),
          500,
          headers: {'content-type': 'application/json'},
        ),
      );
      addTearDown(client.close);

      final provider = OpenAiVideosProviderClient(
        baseUrl: 'https://provider.test/v1',
        apiKey: _testApiKey(),
        model: 'video-model',
        client: client,
      );

      try {
        await provider.createImageToVideo(
          imageBytes: _minimalPng(),
          imageMimeType: 'image/png',
          prompt: 'animate',
          duration: '4',
          aspectRatio: '16:9',
        );
        fail('Expected VideoProviderException');
      } on VideoProviderException catch (error) {
        expect(error.code, 'VIDEO_GENERATION_FAILED');
        expect(error.message, contains('HTTP 500'));
        expect(error.message, contains('server_error'));
        expect(error.message, contains('backend unavailable'));
        expect(error.message, isNot(contains('do not expose this body')));
      }
    },
  );

  test('polls and downloads using authenticated provider paths', () async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/content')) {
        return http.Response.bytes(
          _minimalMp4(),
          200,
          headers: {'content-type': 'video/mp4'},
        );
      }
      return http.Response(
        jsonEncode({'id': 'job_123', 'status': 'completed'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1/',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    final job = await provider.poll('job_123');
    final content = await provider.downloadContent(job.requestId);

    expect(job.status, 'completed');
    expect(content, _minimalMp4());
    expect(requests.map((request) => request.method), ['GET', 'GET']);
    expect(requests.map((request) => request.url.toString()), [
      'https://provider.test/v1/videos/job_123',
      'https://provider.test/v1/videos/job_123/content',
    ]);
    expect(requests.map((request) => request.headers['authorization']), [
      ['Bearer', _testApiKey()].join(' '),
      ['Bearer', _testApiKey()].join(' '),
    ]);
  });

  test('accepts the British cancelled status spelling', () {
    final job = VideoProviderJob.fromJson({'id': 'v1', 'status': 'cancelled'});

    expect(job.status, 'cancelled');
  });

  test('rejects base URLs containing userinfo', () async {
    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://user@provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    final result = await provider.testConnection();
    expect(result.$1, isFalse);
    expect(result.$2, contains('valid HTTP(S) URL'));
  });

  test(
    'treats a provider without models as reachable but unverified',
    () async {
      var requestCount = 0;
      final client = MockClient((_) async {
        requestCount++;
        return requestCount == 1
            ? http.Response('{}', 200)
            : http.Response('not found', 404);
      });
      addTearDown(client.close);

      final provider = OpenAiVideosProviderClient(
        baseUrl: 'https://provider.test/v1',
        apiKey: _testApiKey(),
        model: 'video-model',
        client: client,
      );

      final result = await provider.testConnection();
      expect(result.$1, isTrue);
      expect(result.$2, contains('unavailable'));
    },
  );

  test('detects an unsupported video route before model discovery', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/videos')) {
        return http.Response('not found', 404);
      }
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 'video-model'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    final result = await provider.testConnection();
    expect(result.$1, isFalse);
    expect(result.$2, contains('does not support'));
    expect(paths, ['/v1/videos']);
  });

  test(
    'maps provider auth and rate-limit failures during connection test',
    () async {
      for (final status in [401, 429, 500]) {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'provider detail'},
            }),
            status,
          ),
        );
        addTearDown(client.close);

        final provider = OpenAiVideosProviderClient(
          baseUrl: 'https://provider.test/v1',
          apiKey: _testApiKey(),
          model: 'video-model',
          client: client,
        );

        final result = await provider.testConnection();
        expect(result.$1, isFalse);
        expect(result.$2, isNot(contains(_testApiKey())));
      }
    },
  );

  test('rejects invalid prompt and aspect before creating a request', () async {
    var requests = 0;
    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );

    expect(
      () => provider.createImageToVideo(
        imageBytes: _minimalPng(),
        imageMimeType: 'image/png',
        prompt: ' ',
        duration: '4',
        aspectRatio: '16:9',
      ),
      throwsA(isA<VideoProviderException>()),
    );
    expect(
      () => provider.createImageToVideo(
        imageBytes: _minimalPng(),
        imageMimeType: 'image/png',
        prompt: 'animate',
        duration: '4',
        aspectRatio: '1:1',
      ),
      throwsA(isA<VideoProviderException>()),
    );
    expect(requests, 0);
  });

  test('rejects invalid source bytes before creating a request', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    expect(
      () => provider.createImageToVideo(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        imageMimeType: 'image/png',
        prompt: 'animate',
        duration: '4',
        aspectRatio: '16:9',
      ),
      throwsA(
        isA<VideoProviderException>()
            .having((error) => error.code, 'code', 'VIDEO_SOURCE_ERROR')
            .having(
              (error) => error.message,
              'message',
              'The selected image bytes are not a valid PNG, JPEG, or WebP image.',
            ),
      ),
    );
    expect(requests, 0);
  });

  test('validates downloaded MP4 content', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(
        _minimalMp4(),
        200,
        headers: {'content-type': 'video/mp4'},
      ),
    );
    addTearDown(client.close);

    final provider = OpenAiVideosProviderClient(
      baseUrl: 'https://provider.test/v1',
      apiKey: _testApiKey(),
      model: 'video-model',
      client: client,
    );

    expect(await provider.downloadContent('v1'), _minimalMp4());
  });

  test('wan create submits correct Gradio payload', () async {
    String? requestBody;
    String? requestPath;
    String? authorization;
    final client = MockClient((request) async {
      requestPath = request.url.toString();
      requestBody = request.body;
      authorization = request.headers['authorization'];
      return http.Response(
        jsonEncode({'event_id': 'evt_123'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final provider = WanGradioVideoProviderClient(
      hfToken: 'hf_example_token',
      client: client,
    );
    final job = await provider.createImageToVideo(
      imageBytes: _minimalPng(),
      imageMimeType: 'image/png',
      prompt: 'animate the facade',
      duration: '4',
      aspectRatio: '16:9',
    );

    expect(job.requestId, 'evt_123');
    expect(job.status, 'queued');
    expect(authorization, 'Bearer hf_example_token');
    expect(requestPath, contains('/gradio_api/call/generate_video'));
    final decoded = jsonDecode(requestBody!) as Map<String, dynamic>;
    final data = decoded['data'] as List;
    expect(data[1], 'animate the facade');
    expect(data[2], 512);
    expect(data[3], 896);
    expect(data[5], 2.0);
    expect(data[6], 1.0);
    expect(data[7], 4);
    expect(data[8], 42);
    expect(data[9], true);
  });

  test('wan BYOK token is not forwarded to a video CDN redirect', () async {
    final authorizationByHost = <String, String?>{};
    final client = MockClient((request) async {
      authorizationByHost[request.url.host] = request.headers['authorization'];
      if (request.url.path.endsWith('/evt_redirect')) {
        return http.Response(
          [
            'event: complete',
            'data: [{"video":{"path":"/tmp/v.mp4","url":"https://custom.hf.space/gradio_api/file=v.mp4"}},42]',
            '',
          ].join('\n'),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      if (request.url.host == 'custom.hf.space') {
        return http.Response(
          '',
          302,
          headers: {'location': 'https://cdn.huggingface.co/video.mp4'},
        );
      }
      return http.Response.bytes(
        _minimalMp4(),
        200,
        headers: {'content-type': 'video/mp4'},
      );
    });
    addTearDown(client.close);

    final provider = WanGradioVideoProviderClient(
      spaceUrl: 'https://custom.hf.space',
      hfToken: 'hf_secret_token',
      client: client,
    );
    await provider.poll('evt_redirect');
    expect(await provider.downloadContent('evt_redirect'), _minimalMp4());

    expect(authorizationByHost['custom.hf.space'], 'Bearer hf_secret_token');
    expect(authorizationByHost['cdn.huggingface.co'], isNull);
  });

  test('wan parses SSE complete event', () async {
    const eventId = 'evt_abc';
    final client = MockClient((request) async {
      return http.Response(
        [
          'event: generating',
          'data: [{"video":null},42]',
          '',
          'event: complete',
          'data: [{"video":{"path":"/tmp/v.mp4","url":"https://multimodalart-wan2-1-fast.hf.space/file=v.mp4"}},42]',
          '',
        ].join('\n'),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    addTearDown(client.close);

    final provider = WanGradioVideoProviderClient(client: client);
    final job = await provider.poll(eventId);

    expect(job.requestId, eventId);
    expect(job.status, 'completed');
    expect(
      job.videoUrl,
      'https://multimodalart-wan2-1-fast.hf.space/file=v.mp4',
    );
  });

  test('wan maps error event to failure', () async {
    final client = MockClient(
      (_) async => http.Response(
        ['event: error', 'data: ["generation failed"]', ''].join('\n'),
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    );
    addTearDown(client.close);

    final provider = WanGradioVideoProviderClient(client: client);
    expect(
      () => provider.poll('evt_err'),
      throwsA(
        isA<VideoProviderException>().having(
          (e) => e.code,
          'code',
          'VIDEO_GENERATION_FAILED',
        ),
      ),
    );
  });

  test('wan maps an empty error event without exposing null', () async {
    final client = MockClient(
      (_) async => http.Response(
        ['event: error', 'data: null', ''].join('\n'),
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    );
    addTearDown(client.close);

    final provider = WanGradioVideoProviderClient(client: client);
    expect(
      () => provider.poll('evt_empty_error'),
      throwsA(
        isA<VideoProviderException>()
            .having((e) => e.code, 'code', 'VIDEO_GENERATION_FAILED')
            .having((e) => e.message, 'message', isNot(contains('null')))
            .having(
              (e) => e.message,
              'message',
              contains('public Space returned no error detail'),
            ),
      ),
    );
  });

  test('wan allows the public GPU runtime window', () {
    final client = MockClient((_) async => http.Response('{}', 200));
    addTearDown(client.close);

    final provider = WanGradioVideoProviderClient(client: client);
    expect(provider.requestTimeout, const Duration(seconds: 120));
  });

  test('wan rejects invalid aspect ratio', () async {
    final provider = WanGradioVideoProviderClient(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(
      () => provider.createImageToVideo(
        imageBytes: _minimalPng(),
        imageMimeType: 'image/png',
        prompt: 'animate',
        duration: '4',
        aspectRatio: '1:1',
      ),
      throwsA(isA<VideoProviderException>()),
    );
  });

  test('wan testConnection checks Gradio info endpoint', () async {
    var requestedPath = '';
    String? authorization;
    final client = MockClient((request) async {
      requestedPath = request.url.toString();
      authorization = request.headers['authorization'];
      return http.Response(
        jsonEncode({
          'named_endpoints': {
            '/generate_video': {'parameters': [], 'returns': []},
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final provider = WanGradioVideoProviderClient(
      hfToken: 'hf_example_token',
      client: client,
    );
    final result = await provider.testConnection();

    expect(result.$1, isTrue);
    expect(requestedPath, contains('/gradio_api/info'));
    expect(authorization, 'Bearer hf_example_token');
  });

  test('wan testConnection fails when generate_video is absent', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'named_endpoints': {'/other': {}},
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);

    final provider = WanGradioVideoProviderClient(client: client);
    final result = await provider.testConnection();

    expect(result.$1, isFalse);
    expect(result.$2, contains('generate_video'));
  });
}
