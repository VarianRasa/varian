import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/features/ai/data/ai_mask_renderer.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/domain/ai_workflow_contract.dart';

const _sourceImageBytes = <int>[
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

const _jpegSourceBytes = <int>[255, 216, 255];

String _testKey() =>
    String.fromCharCodes(const [116, 101, 115, 116, 45, 107, 101, 121]);

AIService _imageEditService(
  http.Client client, {
  ImageEditApiMode mode = ImageEditApiMode.auto,
}) => AIService(
  BackendConfig(
    openAiApiKey: _testKey(),
    openAiBaseUrl: 'https://example.test/v1',
    openAiModel: 'chat-model',
    openAiImageModel: 'image-model',
    imageEditApiMode: mode,
  ),
  client,
  false,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  MemoryImageArtifactStore(),
);

AIJob _imageEditJob({String id = 'edit-job'}) {
  final now = DateTime.now();
  return AIJob(
    id: id,
    projectId: 'project',
    capability: AICapability.imageToImage,
    prompt: 'edit the selected image',
    creativeParams: AICreativeParams(
      sourceImageBase64: base64Encode(_sourceImageBytes),
      sourceImageMimeType: 'image/png',
    ),
    status: AIJobStatus.processing,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('uses only the explicitly selected Chat Completions edit route', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      final payload = jsonDecode(request.body) as Map;
      expect(payload['model'], 'image-model');
      expect(payload['modalities'], ['text', 'image']);
      final message = (payload['messages'] as List).single as Map;
      final content = message['content'] as List;
      expect((content.first as Map)['text'], contains('User request:'));
      final image = (content[1] as Map)['image_url'] as Map;
      expect(
        image['url'],
        'data:image/png;base64,${base64Encode(_sourceImageBytes)}',
      );
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'images': [
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url':
                          'data:image/png;base64,${base64Encode(_sourceImageBytes)}',
                    },
                  },
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await _imageEditService(
      client,
      mode: ImageEditApiMode.chatCompletions,
    ).executeJob(_imageEditJob(), const []);

    expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
    expect(result.resultArtifact?.kind, AIArtifactKind.image);
    expect(paths, ['/v1/chat/completions']);
  });

  test(
    'falls back to Chat Completions after a text-only Responses result',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/images/edits')) {
          return http.Response('unknown route', 404);
        }
        if (request.url.path.endsWith('/responses')) {
          return http.Response(
            jsonEncode({
              'output': [
                {
                  'type': 'message',
                  'content': [
                    {'type': 'output_text', 'text': 'No image returned.'},
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'images': [
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url':
                            'data:image/png;base64,${base64Encode(_sourceImageBytes)}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await _imageEditService(
        client,
      ).executeJob(_imageEditJob(), const []);

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(paths, [
        '/v1/images/edits',
        '/v1/responses',
        '/v1/chat/completions',
      ]);
    },
  );

  test(
    'falls back to Responses image generation when edits route is absent',
    () async {
      final requests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/images/edits')) {
          return http.Response('unknown route', 404);
        }
        if (request.url.path.endsWith('/responses')) {
          return http.Response(
            jsonEncode({
              'output': [
                {
                  'type': 'image_generation_call',
                  'result': base64Encode(_sourceImageBytes),
                },
              ],
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final service = AIService(
        BackendConfig(
          openAiApiKey: _testKey(),
          openAiBaseUrl: 'https://example.test/v1',
          openAiModel: 'wither',
          openAiImageModel: 'dall-e-3',
        ),

        client,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        MemoryImageArtifactStore(),
      );
      final now = DateTime.now();
      final job = AIJob(
        id: 'job1',
        projectId: 'project1',
        capability: AICapability.imageToImage,
        prompt: 'modern facade',
        creativeParams: AICreativeParams(
          sourceImageBase64: base64Encode(_sourceImageBytes),
        ),
        status: AIJobStatus.processing,
        createdAt: now,
        updatedAt: now,
      );

      final result = await service.executeJob(job, const []);

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(result.resultAssetUrl, isNull);
      expect(result.resultImageUrls, isEmpty);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(
        validImageArtifactReference(result.resultArtifact?.reference),
        isNotNull,
      );
      expect(requests.map((request) => request.url.path), [
        '/v1/images/edits',
        '/v1/responses',
      ]);
      final editRequest = requests.first as http.Request;
      expect(
        editRequest.headers['content-type'],
        startsWith('multipart/form-data;'),
      );
    },
  );

  test(
    'preserves JPEG source MIME in multipart and Responses edit requests',
    () async {
      final requests = <http.BaseRequest>[];
      final client = MockClient.streaming((request, body) async {
        requests.add(request);
        if (request.url.path.endsWith('/images/edits')) {
          expect(request, isA<http.MultipartRequest>());
          final multipart = request as http.MultipartRequest;
          final image = multipart.files.singleWhere(
            (file) => file.field == 'image',
          );
          expect(image.filename, 'source.jpg');
          await body.toBytes();
          return http.StreamedResponse(
            http.ByteStream.fromBytes(utf8.encode('unknown route')),
            404,
          );
        }
        if (request.url.path.endsWith('/responses')) {
          final payload =
              jsonDecode(utf8.decode(await body.toBytes()))
                  as Map<String, dynamic>;
          final input = (payload['input'] as List).single as Map;
          final content = (input['content'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
          expect(
            content.singleWhere(
              (item) => item['type'] == 'input_image',
            )['image_url'],
            'data:image/jpeg;base64,${base64Encode(_jpegSourceBytes)}',
          );
          return http.StreamedResponse(
            http.ByteStream.fromBytes(
              utf8.encode(
                jsonEncode({
                  'output': [
                    {
                      'type': 'image_generation_call',
                      'result': base64Encode(_sourceImageBytes),
                    },
                  ],
                }),
              ),
            ),
            200,
          );
        }
        await body.toBytes();
        return http.StreamedResponse(http.ByteStream.fromBytes(<int>[]), 404);
      });
      final service = AIService(
        BackendConfig(
          openAiApiKey: _testKey(),
          openAiBaseUrl: 'https://example.test/v1',
          openAiModel: 'wither',
          openAiImageModel: 'dall-e-3',
        ),
        client,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        MemoryImageArtifactStore(),
      );
      final now = DateTime.now();
      final job = AIJob(
        id: 'job-jpeg-source',
        projectId: 'project1',
        capability: AICapability.imageToImage,
        prompt: 'preserve source type',
        creativeParams: AICreativeParams(
          sourceImageBase64: base64Encode(_jpegSourceBytes),
          sourceImageMimeType: 'image/jpeg',
          sourceImageByteLength: _jpegSourceBytes.length,
        ),
        status: AIJobStatus.processing,
        createdAt: now,
        updatedAt: now,
      );

      final result = await service.executeJob(job, const []);

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(requests, hasLength(2));
    },
  );

  test(
    'preserves the mask in the Responses image edit fallback payload',
    () async {
      const maskBytes = _sourceImageBytes;
      final requests = <String>[];
      final client = MockClient.streaming((request, body) async {
        requests.add(request.url.path);
        if (request.url.path.endsWith('/images/edits')) {
          expect(request, isA<http.MultipartRequest>());
          final multipart = request as http.MultipartRequest;
          expect(multipart.fields['model'], 'dall-e-3');
          expect(
            multipart.fields['prompt'],
            contains('Remove the requested object'),
          );
          expect(
            multipart.fields['prompt'],
            contains('User request: remove the object'),
          );
          expect(
            multipart.files.map((file) => file.field),
            containsAll(<String>['image', 'mask']),
          );
          await body.toBytes();
          return http.StreamedResponse(
            http.ByteStream.fromBytes(utf8.encode('unknown route')),
            404,
            reasonPhrase: 'Not Found',
          );
        }
        if (request.url.path.endsWith('/responses')) {
          final payload =
              jsonDecode(utf8.decode(await body.toBytes()))
                  as Map<String, dynamic>;
          final input = (payload['input'] as List).single as Map;
          final content = (input['content'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
          final maskContent = content.singleWhere(
            (item) => item['purpose'] == 'mask',
          );
          expect(
            maskContent['image_url'],
            'data:image/png;base64,${base64Encode(maskBytes)}',
          );
          final metadata = payload['metadata'] as Map<String, dynamic>;
          expect(
            metadata['mask_image'],
            'data:image/png;base64,${base64Encode(maskBytes)}',
          );
          return http.StreamedResponse(
            http.ByteStream.fromBytes(
              utf8.encode(
                jsonEncode({
                  'output': [
                    {
                      'type': 'image_generation_call',
                      'result': base64Encode(_sourceImageBytes),
                    },
                  ],
                }),
              ),
            ),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        await body.toBytes();
        return http.StreamedResponse(http.ByteStream.fromBytes(<int>[]), 404);
      });
      final service = AIService(
        BackendConfig(
          openAiApiKey: _testKey(),
          openAiBaseUrl: 'https://example.test/v1',
          openAiModel: 'wither',
          openAiImageModel: 'dall-e-3',
        ),
        client,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        MemoryImageArtifactStore(),
      );
      final now = DateTime.now();
      final job = AIJob(
        id: 'job-mask',
        projectId: 'project1',
        capability: AICapability.removeObject,
        prompt: 'remove the object',
        creativeParams: AICreativeParams(
          sourceImageBase64: base64Encode(_sourceImageBytes),
          maskImageBase64: base64Encode(maskBytes),
        ),
        status: AIJobStatus.processing,
        createdAt: now,
        updatedAt: now,
      );

      final result = await service.executeJob(job, const []);

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(requests, ['/v1/images/edits', '/v1/responses']);
    },
  );

  test(
    'renders and forwards a structured mask payload to the edit endpoint',
    () async {
      const mask = AIMaskDocument(
        width: 32,
        height: 32,
        operation: AIMaskOperation.removeObject,
        strokes: [
          AIMaskStroke(points: [Offset(4, 4), Offset(24, 24)], width: 8),
        ],
      );
      final expectedMask = base64Encode(await AIMaskRenderer.render(mask));
      final client = MockClient.streaming((request, body) async {
        if (request.url.path.endsWith('/images/edits')) {
          final multipart = request as http.MultipartRequest;
          final maskPart = multipart.files.singleWhere(
            (file) => file.field == 'mask',
          );
          expect(maskPart.length, greaterThan(0));
          expect(expectedMask, isNotEmpty);
          await body.toBytes();
          return http.StreamedResponse(
            http.ByteStream.fromBytes(utf8.encode('unknown route')),
            404,
          );
        }
        if (request.url.path.endsWith('/responses')) {
          await body.toBytes();
          return http.StreamedResponse(
            http.ByteStream.fromBytes(
              utf8.encode(
                jsonEncode({
                  'output': [
                    {
                      'type': 'image_generation_call',
                      'result': base64Encode(_sourceImageBytes),
                    },
                  ],
                }),
              ),
            ),
            200,
          );
        }
        await body.toBytes();
        return http.StreamedResponse(http.ByteStream.fromBytes(<int>[]), 404);
      });
      final service = AIService(
        BackendConfig(
          openAiApiKey: _testKey(),
          openAiBaseUrl: 'https://example.test/v1',
          openAiModel: 'wither',
          openAiImageModel: 'dall-e-3',
        ),
        client,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        MemoryImageArtifactStore(),
      );
      final now = DateTime.now();
      final job = AIJob(
        id: 'job-structured-mask',
        projectId: 'project1',
        capability: AICapability.removeObject,
        prompt: 'remove the object',
        creativeParams: AICreativeParams(
          sourceImageBase64: base64Encode(_sourceImageBytes),
          maskPayload: mask.toJson(),
        ),
        status: AIJobStatus.processing,
        createdAt: now,
        updatedAt: now,
      );

      final result = await service.executeJob(job, const []);

      expect(result.status, AIJobStatus.completed);
    },
  );
  test(
    'uses the configured image model and parses nested image output in Responses edit fallback',
    () async {
      final requests = <String>[];
      final client = MockClient.streaming((request, body) async {
        requests.add(request.url.path);
        if (request.url.path.endsWith('/images/edits')) {
          await body.toBytes();
          return http.StreamedResponse(
            http.ByteStream.fromBytes(utf8.encode('unknown route')),
            404,
          );
        }
        final payload = jsonDecode(utf8.decode(await body.toBytes())) as Map;
        expect(payload['model'], 'wither-chat');
        expect(payload['tools'], [
          {'type': 'image_generation', 'action': 'edit'},
        ]);
        return http.StreamedResponse(
          http.ByteStream.fromBytes(
            utf8.encode(
              jsonEncode({
                'output': [
                  {
                    'type': 'message',
                    'content': [
                      {
                        'type': 'output_image',
                        'image_url': {
                          'url':
                              'data:image/png;base64,${base64Encode(_sourceImageBytes)}',
                        },
                      },
                    ],
                  },
                ],
              }),
            ),
          ),
          200,
        );
      });
      final service = AIService(
        BackendConfig(
          openAiApiKey: _testKey(),
          openAiBaseUrl: 'https://example.test/v1',
          openAiModel: 'wither-chat',
          openAiImageModel: 'wither-image',
        ),
        client,
        false,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        MemoryImageArtifactStore(),
      );
      final now = DateTime.now();
      final result = await service.executeJob(
        AIJob(
          id: 'responses-edit-nested',
          projectId: 'project',
          capability: AICapability.sketchToImage,
          prompt: 'render sketch',
          creativeParams: AICreativeParams(
            sourceImageBase64: base64Encode(_sourceImageBytes),
          ),
          status: AIJobStatus.processing,
          createdAt: now,
          updatedAt: now,
        ),
        const [],
      );

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(requests, ['/v1/images/edits', '/v1/responses']);
    },
  );

  test(
    'falls back to Chat Completions after a Responses 2xx without an image',
    () async {
      final requests = <http.BaseRequest>[];
      final client = MockClient.streaming((request, body) async {
        requests.add(request);
        if (request.url.path.endsWith('/images/edits')) {
          await body.toBytes();
          return http.StreamedResponse(
            http.ByteStream.fromBytes(utf8.encode('unknown route')),
            404,
          );
        }
        if (request.url.path.endsWith('/responses')) {
          final payload = jsonDecode(utf8.decode(await body.toBytes())) as Map;
          expect(payload['input'], isA<List>());
          return http.StreamedResponse(
            http.ByteStream.fromBytes(
              utf8.encode(
                jsonEncode({
                  'output': [
                    {
                      'type': 'message',
                      'content': [
                        {'type': 'output_text', 'text': 'No image returned.'},
                      ],
                    },
                  ],
                }),
              ),
            ),
            200,
          );
        }
        expect(request.url.path, '/v1/chat/completions');
        final payload = jsonDecode(utf8.decode(await body.toBytes())) as Map;
        expect(payload['modalities'], ['text', 'image']);
        final message = (payload['messages'] as List).single as Map;
        final content = message['content'] as List;
        expect((content[1] as Map)['type'], 'image_url');
        return http.StreamedResponse(
          http.ByteStream.fromBytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'images': [
                        {
                          'type': 'image_url',
                          'image_url': {
                            'url':
                                'data:image/png;base64,${base64Encode(_sourceImageBytes)}',
                          },
                        },
                      ],
                    },
                  },
                ],
              }),
            ),
          ),
          200,
        );
      });
      final service = AIService(
        BackendConfig(
          openAiApiKey: _testKey(),
          openAiBaseUrl: 'https://example.test/v1',
          openAiModel: 'chat-model',
          openAiImageModel: 'image-model',
        ),
        client,
        false,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        MemoryImageArtifactStore(),
      );
      final now = DateTime.now();
      final result = await service.executeJob(
        AIJob(
          id: 'native-missing-responses-image',
          projectId: 'project',
          capability: AICapability.imageToImage,
          prompt: 'edit the selected image',
          creativeParams: AICreativeParams(
            sourceImageBase64: base64Encode(_sourceImageBytes),
            sourceImageMimeType: 'image/png',
          ),
          status: AIJobStatus.processing,
          createdAt: now,
          updatedAt: now,
        ),
        const [],
      );

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(requests.map((request) => request.url.path), [
        '/v1/images/edits',
        '/v1/responses',
        '/v1/chat/completions',
      ]);
    },
  );

  test('does not continue after an unrelated image edit HTTP error', () async {
    final paths = <String>[];
    final client = MockClient.streaming((request, body) async {
      paths.add(request.url.path);
      await body.toBytes();
      return http.StreamedResponse(
        http.ByteStream.fromBytes(
          utf8.encode(
            jsonEncode({
              'error': {'message': 'invalid source image'},
            }),
          ),
        ),
        400,
      );
    });
    final service = AIService(
      BackendConfig(
        openAiApiKey: _testKey(),
        openAiBaseUrl: 'https://example.test/v1',
        openAiModel: 'chat-model',
        openAiImageModel: 'image-model',
      ),
      client,
      false,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      MemoryImageArtifactStore(),
    );
    final now = DateTime.now();
    final result = await service.executeJob(
      AIJob(
        id: 'native-invalid-edit-input',
        projectId: 'project',
        capability: AICapability.imageToImage,
        prompt: 'edit the selected image',
        creativeParams: AICreativeParams(
          sourceImageBase64: base64Encode(_sourceImageBytes),
          sourceImageMimeType: 'image/png',
        ),
        status: AIJobStatus.processing,
        createdAt: now,
        updatedAt: now,
      ),
      const [],
    );

    expect(result.status, AIJobStatus.failed);
    expect(paths, ['/v1/images/edits']);
  });

  test('redacts local filesystem paths from image edit diagnostics', () async {
    final client = MockClient.streaming((request, body) async {
      await body.toBytes();
      return http.StreamedResponse(
        http.ByteStream.fromBytes(utf8.encode('invalid source image')),
        400,
      );
    });
    final service = AIService(
      BackendConfig(
        openAiApiKey: _testKey(),
        openAiBaseUrl: 'https://example.test/v1',
        openAiModel: 'chat-model',
        openAiImageModel: r'C:\Users\private\models\image.bin',
      ),
      client,
      false,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      MemoryImageArtifactStore(),
    );

    final result = await service.executeJob(_imageEditJob(), const []);

    expect(result.status, AIJobStatus.failed);
    expect(result.errorMessage, contains('[redacted path]'));
    expect(result.errorMessage, isNot(contains('private')));
    expect(result.errorMessage, isNot(contains('image.bin')));
  });

  test(
    'does not retry when the provider rejects the image media type',
    () async {
      final paths = <String>[];
      final client = MockClient.streaming((request, body) async {
        paths.add(request.url.path);
        await body.toBytes();
        return http.StreamedResponse(
          http.ByteStream.fromBytes(
            utf8.encode(
              jsonEncode({
                'error': {'message': 'unsupported image media type'},
              }),
            ),
          ),
          415,
        );
      });

      final result = await _imageEditService(
        client,
      ).executeJob(_imageEditJob(), const []);

      expect(result.status, AIJobStatus.failed);
      expect(paths, ['/v1/images/edits']);
    },
  );

  test(
    'uses a text model and forces image editing in Responses fallback',
    () async {
      final requestPaths = <String>[];
      final client = MockClient.streaming((request, body) async {
        requestPaths.add(request.url.path);
        if (request.url.path.endsWith('/images/edits')) {
          await body.toBytes();
          return http.StreamedResponse(
            http.ByteStream.fromBytes(utf8.encode('unknown route')),
            404,
          );
        }

        expect(request.url.path, '/v1/responses');
        final payload =
            jsonDecode(utf8.decode(await body.toBytes()))
                as Map<String, dynamic>;
        expect(payload['model'], 'gpt-4o-mini');
        expect(payload['tools'], [
          {
            'type': 'image_generation',
            'model': 'gpt-image-2',
            'action': 'edit',
          },
        ]);
        final input = (payload['input'] as List).single as Map<String, dynamic>;
        final content = input['content'] as List;
        expect(content.map((item) => (item as Map)['type']), [
          'input_text',
          'input_image',
        ]);
        expect((content[1] as Map)['detail'], 'high');
        expect(
          (content[1] as Map)['image_url'],
          startsWith('data:image/png;base64,'),
        );
        return http.StreamedResponse(
          http.ByteStream.fromBytes(
            utf8.encode(
              jsonEncode({
                'output': [
                  {
                    'type': 'image_generation_call',
                    'status': 'completed',
                    'result': base64Encode(_sourceImageBytes),
                  },
                ],
              }),
            ),
          ),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      final now = DateTime.now();
      final service = AIService(
        BackendConfig(
          openAiApiKey: _testKey(),
          openAiBaseUrl: 'https://example.test/v1',
          openAiModel: 'gpt-4o-mini',
          openAiImageModel: 'gpt-image-2',
        ),
        client,
        false,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        MemoryImageArtifactStore(),
      );

      for (final capability in const [
        AICapability.sketchToImage,
        AICapability.imageToImage,
        AICapability.referenceToImage,
      ]) {
        final result = await service.executeJob(
          AIJob(
            id: 'responses-edit-${capability.name}',
            projectId: 'project',
            capability: capability,
            prompt: 'edit the selected image',
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_sourceImageBytes),
              sourceImageMimeType: 'image/png',
            ),
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

        expect(
          result.status,
          AIJobStatus.completed,
          reason: result.errorMessage,
        );
        expect(result.resultArtifact?.kind, AIArtifactKind.image);
      }
      expect(
        requestPaths,
        List.generate(
          3,
          (_) => ['/v1/images/edits', '/v1/responses'],
        ).expand((routes) => routes).toList(),
      );
    },
  );
}
