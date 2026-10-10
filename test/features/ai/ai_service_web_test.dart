import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';

const _fixtureBytes = <int>[
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

String _testKey() =>
    String.fromCharCodes(const [116, 101, 115, 116, 45, 107, 101, 121]);

String _dataUriPrefix(String mimeType) =>
    'data:$mimeType;${['base', '64'].join('')},';

String _dataUri(String mimeType, List<int> bytes) =>
    '${_dataUriPrefix(mimeType)}${base64Encode(bytes)}';

void main() {
  AIJob job({AICapability capability = AICapability.backgroundReplace}) {
    final now = DateTime.now();
    return AIJob(
      id: 'web-job-${capability.name}',
      projectId: 'project',
      capability: capability,
      prompt: capability == AICapability.imageToImage
          ? 'transform selected image'
          : 'replace background',
      creativeParams: AICreativeParams(
        sourceImageBase64: base64Encode(_fixtureBytes),
      ),
      status: AIJobStatus.processing,
      createdAt: now,
      updatedAt: now,
    );
  }

  test(
    'sends browser image-to-image and background edits to Images API',
    () async {
      final paths = <String>[];
      final prompts = <String>[];
      final client = MockClient.streaming((request, body) async {
        paths.add(request.url.path);
        expect(
          request.headers['authorization'],
          ['Bearer', _testKey()].join(' '),
        );
        expect(request, isA<http.MultipartRequest>());
        final multipart = request as http.MultipartRequest;
        expect(multipart.fields['model'], 'wither-image');
        final prompt = multipart.fields['prompt']!;
        prompts.add(prompt);
        expect(multipart.files.map((file) => file.field), contains('image'));
        await body.toBytes();
        return http.StreamedResponse(
          http.ByteStream.fromBytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {'b64_json': base64Encode(_fixtureBytes)},
                ],
              }),
            ),
          ),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      final service = AIService(
        BackendConfig(
          openAiApiKey: _testKey(),
          openAiBaseUrl: 'https://example.test/v1',
          openAiModel: 'wither',
          openAiImageModel: 'wither-image',
          imageApiMode: ImageApiMode.responses,
        ),
        client,
        true,
      );

      for (final capability in const [
        AICapability.imageToImage,
        AICapability.backgroundReplace,
      ]) {
        final result = await service.executeJob(
          job(capability: capability),
          const [],
        );

        expect(
          result.status,
          AIJobStatus.completed,
          reason: '${capability.name}: ${result.errorMessage}',
        );
        expect(result.resultAssetUrl, isNull);
        expect(result.resultImageUrls, isEmpty);
        expect(result.resultArtifact?.kind, AIArtifactKind.image);
        expect(
          validImageArtifactReference(result.resultArtifact?.reference),
          isNotNull,
        );
      }

      expect(paths, ['/v1/images/edits', '/v1/images/edits']);
      expect(prompts[0], contains('User request: transform selected image'));
      expect(prompts[1], contains('User request: replace background'));
    },
  );

  test(
    'proxies remote image sources through Supabase before Web edits',
    () async {
      const sourceUrl = 'https://i.pinimg.com/736x/reference.jpg?width=512';
      final requests = <http.BaseRequest>[];
      final client = MockClient.streaming((request, body) async {
        requests.add(request);
        if (request.url.host == '8.8.8.8') {
          expect(request.method, 'GET');
          expect(request.url.path, '/functions/v1/link-preview');
          expect(request.url.queryParameters['asset'], sourceUrl);
          return http.StreamedResponse(
            http.ByteStream.fromBytes(_fixtureBytes),
            200,
            headers: const {'content-type': 'image/png'},
          );
        }

        expect(request.url.path, '/v1/images/edits');
        final multipart = request as http.MultipartRequest;
        final image = multipart.files.singleWhere(
          (file) => file.field == 'image',
        );
        expect(image.length, greaterThan(0));
        await body.toBytes();
        return http.StreamedResponse(
          http.ByteStream.fromBytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {'b64_json': base64Encode(_fixtureBytes)},
                ],
              }),
            ),
          ),
          200,
        );
      });
      final now = DateTime.now();
      final result =
          await AIService(
            BackendConfig(
              supabaseUrl: 'https://8.8.8.8',
              supabaseAnonKey: 'test-anon-key',
              openAiApiKey: _testKey(),
              openAiBaseUrl: 'https://example.test/v1',
              openAiModel: 'wither-chat',
              openAiImageModel: 'wither-image',
            ),
            client,
            true,
          ).executeJob(
            AIJob(
              id: 'linked-source-edit',
              projectId: 'project',
              capability: AICapability.imageToImage,
              prompt: 'transform this linked image',
              creativeParams: const AICreativeParams(
                sourceImageUrl: sourceUrl,
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
        reason:
            '${result.errorMessage}; paths=${requests.map((request) => request.url.path)}',
      );
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(requests.map((request) => request.url.path), [
        '/functions/v1/link-preview',
        '/v1/images/edits',
      ]);
    },
  );

  test('proxies generated image URLs with query strings on Web', () async {
    const outputUrl = 'https://cdn.example.test/generated.png?token=fixture';
    final requests = <http.BaseRequest>[];
    final client = MockClient.streaming((request, body) async {
      requests.add(request);
      if (request.url.host == '8.8.8.8') {
        expect(request.method, 'GET');
        expect(request.url.queryParameters['asset'], outputUrl);
        return http.StreamedResponse(
          http.ByteStream.fromBytes(_fixtureBytes),
          200,
          headers: const {'content-type': 'image/png'},
        );
      }

      expect(request.url.path, '/v1/images/generations');
      await body.toBytes();
      return http.StreamedResponse(
        http.ByteStream.fromBytes(
          utf8.encode(
            jsonEncode({
              'data': [
                {'url': outputUrl},
              ],
            }),
          ),
        ),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            supabaseUrl: 'https://8.8.8.8',
            supabaseAnonKey: 'test-anon-key',
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'wither-chat',
            openAiImageModel: 'wither-image',
            imageApiMode: ImageApiMode.imagesGenerations,
          ),
          client,
          true,
        ).executeJob(
          AIJob(
            id: 'proxied-output',
            projectId: 'project',
            capability: AICapability.textToImage,
            prompt: 'generate a landscape',
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
    expect(result.resultArtifact?.kind, AIArtifactKind.image);
    expect(requests.map((request) => request.url.path), [
      '/v1/images/generations',
      '/functions/v1/link-preview',
    ]);
  });

  test(
    'falls back to Responses for Web edits when the edit route is unsupported',
    () async {
      final paths = <String>[];
      final client = MockClient.streaming((request, body) async {
        paths.add(request.url.path);
        if (request.url.path == '/v1/images/edits') {
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
                    'type': 'image_generation_call',
                    'result': base64Encode(_fixtureBytes),
                  },
                ],
              }),
            ),
          ),
          200,
        );
      });
      final now = DateTime.now();
      final result =
          await AIService(
            BackendConfig(
              openAiApiKey: _testKey(),
              openAiBaseUrl: 'https://example.test/v1',
              openAiModel: 'wither-chat',
              openAiImageModel: 'wither-image',
            ),
            client,
            true,
          ).executeJob(
            AIJob(
              id: 'chat-image-edit-fallback',
              projectId: 'project',
              capability: AICapability.sketchToImage,
              prompt: 'render the selected sketch as a photo',
              creativeParams: AICreativeParams(
                sourceImageBase64: base64Encode(_fixtureBytes),
              ),
              status: AIJobStatus.processing,
              createdAt: now,
              updatedAt: now,
            ),
            const [],
          );

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(paths, ['/v1/images/edits', '/v1/responses']);
    },
  );

  test(
    'auto generates from the selected sketch after edit routes return no image',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/images/edits')) {
          throw http.ClientException('Failed to fetch');
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
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final userMessage = (payload['messages'] as List).last as Map;
          if (payload['modalities'] is List) {
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'No image returned.'},
                  },
                ],
              }),
              200,
            );
          }
          expect(payload['model'], 'wither-chat');
          expect(userMessage['content'], isA<List>());
          expect(
            jsonEncode(userMessage['content']),
            contains(base64Encode(_fixtureBytes)),
          );
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'A cabin beside pine trees.'},
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/images/generations')) {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['model'], 'wither-image');
          expect(payload['prompt'], contains('make it ultra photo-realistic'));
          expect(payload['prompt'], contains('A cabin beside pine trees.'));
          return http.Response(
            jsonEncode({
              'data': [
                {'b64_json': base64Encode(_fixtureBytes)},
              ],
            }),
            200,
          );
        }
        fail('Unexpected route ${request.url.path}');
      });
      final now = DateTime.now();
      final result =
          await AIService(
            BackendConfig(
              openAiApiKey: _testKey(),
              openAiBaseUrl: 'https://example.test/v1',
              openAiModel: 'wither-chat',
              openAiImageModel: 'wither-image',
              imageApiMode: ImageApiMode.auto,
            ),
            client,
            true,
          ).executeJob(
            AIJob(
              id: 'sketch-auto-generation-fallback',
              projectId: 'project',
              capability: AICapability.sketchToImage,
              prompt: 'make it ultra photo-realistic',
              creativeParams: AICreativeParams(
                sourceImageBase64: base64Encode(_fixtureBytes),
              ),
              status: AIJobStatus.processing,
              createdAt: now,
              updatedAt: now,
            ),
            const [],
          );

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(result.resultText, contains('fallback'));
      expect(paths, [
        '/v1/images/edits',
        '/v1/responses',
        '/v1/chat/completions',
        '/v1/chat/completions',
        '/v1/responses',
        '/v1/chat/completions',
        '/v1/images/generations',
      ]);
    },
  );

  test(
    'generates from the prompt when the provider cannot describe the selected image',
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
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          if (payload['modalities'] is List) {
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'No image returned.'},
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'error': {'message': 'vision is not supported'},
            }),
            400,
          );
        }
        if (request.url.path.endsWith('/images/generations')) {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['prompt'], contains('make it ultra photo-realistic'));
          expect(
            payload['prompt'],
            isNot(contains('Selected image visual description')),
          );
          return http.Response(
            jsonEncode({
              'data': [
                {'b64_json': base64Encode(_fixtureBytes)},
              ],
            }),
            200,
          );
        }
        fail('Unexpected route ${request.url.path}');
      });
      final now = DateTime.now();
      final result =
          await AIService(
            BackendConfig(
              openAiApiKey: _testKey(),
              openAiBaseUrl: 'https://example.test/v1',
              openAiModel: 'wither-chat',
              openAiImageModel: 'wither-image',
              imageApiMode: ImageApiMode.imagesGenerations,
            ),
            client,
            true,
          ).executeJob(
            AIJob(
              id: 'sketch-text-generation-fallback',
              projectId: 'project',
              capability: AICapability.sketchToImage,
              prompt: 'make it ultra photo-realistic',
              creativeParams: AICreativeParams(
                sourceImageBase64: base64Encode(_fixtureBytes),
              ),
              status: AIJobStatus.processing,
              createdAt: now,
              updatedAt: now,
            ),
            const [],
          );

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(result.resultText, contains('provider could not describe'));
      expect(paths, [
        '/v1/images/edits',
        '/v1/responses',
        '/v1/chat/completions',
        '/v1/chat/completions',
        '/v1/images/generations',
      ]);
    },
  );

  test('reports when every automatic edit and image route fails', () async {
    final paths = <String>[];
    final client = MockClient.streaming((request, body) async {
      paths.add(request.url.path);
      await body.toBytes();
      throw http.ClientException('Failed to fetch');
    });
    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'wither-chat',
            openAiImageModel: 'wither-image',
          ),
          client,
          true,
        ).executeJob(
          AIJob(
            id: 'chat-image-edit-fallback',
            projectId: 'project',
            capability: AICapability.sketchToImage,
            prompt: 'render the selected sketch as a photo',
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_fixtureBytes),
            ),
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.failed, reason: result.errorMessage);
    expect(result.resultArtifact, isNull);
    expect(paths, [
      '/v1/images/edits',
      '/v1/responses',
      '/v1/chat/completions',
      '/v1/chat/completions',
      '/v1/responses',
      '/v1/chat/completions',
      '/v1/images/generations',
    ]);
    expect(result.errorMessage, contains('network/CORS'));
    expect(result.errorMessage, contains('server-side proxy'));
    expect(result.errorMessage, contains('generation fallback'));
    expect(result.errorMessage, isNot(contains(_testKey())));
  });

  test('text-to-image works without a source image', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/images/generations');
      expect(
        request.headers['authorization'],
        ['Bearer', _testKey()].join(' '),
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['prompt'], 'a photorealistic jet');
      expect(body['model'], 'wither');
      expect(body.containsKey('sourceImageBase64'), isFalse);
      expect(body.containsKey('sourceImageUrl'), isFalse);
      return http.Response(
        jsonEncode({
          'data': [
            {'b64_json': base64Encode(_fixtureBytes)},
          ],
        }),
        200,
      );
    });

    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'wither',
            openAiImageModel: 'wither',
            imageApiMode: ImageApiMode.imagesGenerations,
          ),
          client,
          true,
        ).executeJob(
          AIJob(
            id: 'text-job',
            projectId: 'project',
            capability: AICapability.textToImage,
            prompt: 'a photorealistic jet',
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed);
    expect(result.resultAssetUrl, isNull);
    expect(result.resultImageUrls, isEmpty);
    expect(result.resultArtifact?.kind, AIArtifactKind.image);
    expect(
      validImageArtifactReference(result.resultArtifact?.reference),
      isNotNull,
    );
  });

  test('uses the configured image model for text-to-image', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/images/generations');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'dall-e-3');
      return http.Response(
        jsonEncode({
          'data': [
            {'b64_json': base64Encode(_fixtureBytes)},
          ],
        }),
        200,
      );
    });

    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'gpt-4o-mini',
            openAiImageModel: 'dall-e-3',
          ),
          client,
          true,
        ).executeJob(
          AIJob(
            id: 'configured-image-model-job',
            projectId: 'project',
            capability: AICapability.textToImage,
            prompt: 'a photorealistic jet',
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed);
  });

  test(
    'uses chat route directly for desktop chat-backed image models',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.url.path, '/v1/chat/completions');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'custom-9router-image-combo');
        expect(body['modalities'], ['text', 'image']);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': [
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': _dataUri('image/png', _fixtureBytes),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final now = DateTime.now();
      final result =
          await AIService(
            BackendConfig(
              openAiApiKey: _testKey(),
              openAiBaseUrl: 'https://example.test/v1',
              openAiModel: 'gpt-4o-mini',
              openAiImageModel: 'custom-9router-image-combo',
              imageApiMode: ImageApiMode.chatCompletions,
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
          ).executeJob(
            AIJob(
              id: 'desktop-chat-backed-image-job',
              projectId: 'project',
              capability: AICapability.textToImage,
              prompt: 'a photorealistic jet',
              status: AIJobStatus.processing,
              createdAt: now,
              updatedAt: now,
            ),
            const [],
          );

      expect(result.status, AIJobStatus.completed);
      expect(result.resultAssetUrl, isNull);
      expect(result.resultImageUrls, isEmpty);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(
        validImageArtifactReference(result.resultArtifact?.reference),
        isNotNull,
      );
      expect(paths, ['/v1/chat/completions']);
    },
  );

  test(
    'uses Responses image generation for local text-to-image providers',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.url.path, '/v1/responses');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'wither');
        expect(body['input'], 'a photorealistic jet');
        expect(body['tools'], [
          {'type': 'image_generation'},
        ]);
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'image_generation_call',
                'result': base64Encode(_fixtureBytes),
              },
            ],
          }),
          200,
        );
      });

      final now = DateTime.now();
      final result =
          await AIService(
            BackendConfig(
              openAiApiKey: _testKey(),
              openAiBaseUrl: 'http://localhost:20128/v1',
              openAiModel: 'wither',
              openAiImageModel: 'wither',
              imageApiMode: ImageApiMode.responses,
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
          ).executeJob(
            AIJob(
              id: 'local-responses-image-job',
              projectId: 'project',
              capability: AICapability.textToImage,
              prompt: 'a photorealistic jet',
              status: AIJobStatus.processing,
              createdAt: now,
              updatedAt: now,
            ),
            const [],
          );

      expect(result.status, AIJobStatus.completed);
      expect(result.resultAssetUrl, isNull);
      expect(result.resultImageUrls, isEmpty);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(
        validImageArtifactReference(result.resultArtifact?.reference),
        isNotNull,
      );
      expect(paths, ['/v1/responses']);
    },
  );

  test('auto uses Responses first for arbitrary image models', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(request.url.path, '/v1/responses');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'unused-chat-model');
      expect(body['tools'], [
        {'type': 'image_generation'},
      ]);
      return http.Response(
        jsonEncode({
          'output': [
            {
              'type': 'image_generation_call',
              'result': base64Encode(_fixtureBytes),
            },
          ],
        }),
        200,
      );
    });

    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'unused-chat-model',
            openAiImageModel: 'custom-9router-image-combo',
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
        ).executeJob(
          AIJob(
            id: 'auto-responses-image-job',
            projectId: 'project',
            capability: AICapability.textToImage,
            prompt: 'a photorealistic jet',
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed);
    expect(paths, ['/v1/responses']);
  });

  test('uses IPv4 loopback for web localhost image generation', () async {
    final client = MockClient((request) async {
      expect(request.url.host, '127.0.0.1');
      expect(request.url.path, '/v1/responses');
      return http.Response(
        jsonEncode({
          'output': [
            {
              'type': 'image_generation_call',
              'result': base64Encode(_fixtureBytes),
            },
          ],
        }),
        200,
      );
    });

    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'http://localhost:20128/v1',
            openAiModel: 'wither',
            openAiImageModel: 'wither',
            imageApiMode: ImageApiMode.responses,
          ),
          client,
          true,
        ).executeJob(
          AIJob(
            id: 'web-localhost-image-job',
            projectId: 'project',
            capability: AICapability.textToImage,
            prompt: 'a photorealistic jet',
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed);
  });

  test('auto falls back for arbitrary chat-backed image models', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/responses') ||
          request.url.path.endsWith('/images/generations')) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'model does not support image generation'},
          }),
          400,
        );
      }

      expect(request.url.path, '/v1/chat/completions');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'custom-9router-image-combo');
      expect(body['modalities'], ['text', 'image']);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': [
                  {
                    'type': 'image_url',
                    'image_url': {'url': _dataUri('image/png', _fixtureBytes)},
                  },
                ],
              },
            },
          ],
        }),
        200,
      );
    });

    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'gpt-4o-mini',
            openAiImageModel: 'custom-9router-image-combo',
          ),
          client,
          true,
        ).executeJob(
          AIJob(
            id: 'chat-backed-image-job',
            projectId: 'project',
            capability: AICapability.textToImage,
            prompt: 'a photorealistic jet',
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed);
    expect(result.resultAssetUrl, isNull);
    expect(result.resultImageUrls, isEmpty);
    expect(result.resultArtifact?.kind, AIArtifactKind.image);
    expect(
      validImageArtifactReference(result.resultArtifact?.reference),
      isNotNull,
    );
    expect(paths, ['/v1/responses', '/v1/chat/completions']);
  });

  test('extracts markdown image URLs from chat-backed image responses', () async {
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response.bytes(
          _fixtureBytes,
          200,
          headers: const {'content-type': 'image/png'},
        );
      }
      if (request.url.path.endsWith('/images/generations')) {
        return http.Response(
          jsonEncode({
            'error': {
              'message': '[openai-compatible-chat] images use chat output',
            },
          }),
          400,
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content':
                    'Generated image: ![Generated image](https://example.com/result.png)',
              },
            },
          ],
        }),
        200,
      );
    });

    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'gpt-4o-mini',
            openAiImageModel: 'custom-9router-image-combo',
          ),
          client,
          true,
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
        ).executeJob(
          AIJob(
            id: 'markdown-chat-image-job',
            projectId: 'project',
            capability: AICapability.textToImage,
            prompt: 'a photorealistic jet',
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
    expect(result.resultAssetUrl, isNull);
    expect(result.resultImageUrls, isEmpty);
    expect(result.resultArtifact?.kind, AIArtifactKind.image);
    expect(
      validImageArtifactReference(result.resultArtifact?.reference),
      isNotNull,
    );
  });

  test('extracts inline base64 image data from chat responses', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/images/generations')) {
        return http.Response(
          jsonEncode({
            'error': {'message': '[openai-compatible-chat] use chat output'},
          }),
          400,
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': [
                  {
                    'type': 'image',
                    'inline_data': {
                      'mime_type': 'image/jpeg',
                      'data': base64Encode(_fixtureBytes),
                    },
                  },
                ],
              },
            },
          ],
        }),
        200,
      );
    });

    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'gpt-4o-mini',
            openAiImageModel: 'custom-9router-image-combo',
          ),
          client,
          true,
        ).executeJob(
          AIJob(
            id: 'inline-chat-image-job',
            projectId: 'project',
            capability: AICapability.textToImage,
            prompt: 'a photorealistic jet',
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed);
    expect(result.resultAssetUrl, isNull);
    expect(result.resultImageUrls, isEmpty);
    expect(result.resultArtifact?.kind, AIArtifactKind.image);
    expect(
      validImageArtifactReference(result.resultArtifact?.reference),
      isNotNull,
    );
  });

  test('keeps provider HTTP 400 as a failed generation', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/images/generations');
      return http.Response(
        jsonEncode({
          'error': {'message': 'model does not support image generation'},
        }),
        400,
      );
    });

    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'chat-only-model',
            imageApiMode: ImageApiMode.imagesGenerations,
          ),
          client,
          true,
        ).executeJob(
          AIJob(
            id: 'failed-text-job',
            projectId: 'project',
            capability: AICapability.textToImage,
            prompt: 'a photorealistic jet',
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.failed);
    expect(result.isSimulated, isFalse);
    expect(
      result.errorMessage,
      contains('model does not support image generation'),
    );
    expect(result.errorMessage, isNot(contains(_testKey())));
  });

  test('falls back to Responses after a Web CORS failure', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/images/edits')) {
        throw http.ClientException('Failed to fetch');
      }
      return http.Response(
        jsonEncode({
          'output': [
            {
              'type': 'image_generation_call',
              'result': base64Encode(_fixtureBytes),
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await AIService(
      BackendConfig(
        openAiApiKey: _testKey(),
        openAiBaseUrl: 'https://example.test/v1',
        openAiModel: 'wither',
      ),
      client,
      true,
    ).executeJob(job(), const []);

    expect(paths, ['/v1/images/edits', '/v1/responses']);
    expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
    expect(result.isSimulated, isFalse);
    expect(result.resultArtifact?.kind, AIArtifactKind.image);
    expect(result.errorMessage, isNot(contains(_testKey())));
  });
  test(
    'extracts nested image output from a Responses-compatible endpoint',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/responses');
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_image',
                    'image_url': {'url': _dataUri('image/png', _fixtureBytes)},
                  },
                ],
              },
            ],
          }),
          200,
        );
      });

      final now = DateTime.now();
      final result =
          await AIService(
            BackendConfig(
              openAiApiKey: _testKey(),
              openAiBaseUrl: 'https://example.test/v1',
              openAiModel: 'wither-chat',
              openAiImageModel: 'wither',
              imageApiMode: ImageApiMode.responses,
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
          ).executeJob(
            AIJob(
              id: 'nested-responses-image-job',
              projectId: 'project',
              capability: AICapability.textToImage,
              prompt: 'a photorealistic house',
              status: AIJobStatus.processing,
              createdAt: now,
              updatedAt: now,
            ),
            const [],
          );

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
    },
  );

  test(
    'sketch-to-image falls back to Responses when browser edit route is unavailable',
    () async {
      final paths = <String>[];
      final client = MockClient.streaming((request, body) async {
        paths.add(request.url.path);
        if (request.url.path == '/v1/images/edits') {
          expect(request, isA<http.MultipartRequest>());
          final multipart = request as http.MultipartRequest;
          expect(multipart.fields['model'], 'wither-image');
          expect(multipart.files.map((file) => file.field), contains('image'));
          await body.toBytes();
          return http.StreamedResponse(
            http.ByteStream.fromBytes(utf8.encode('not found')),
            404,
          );
        }

        expect(request.url.path, '/v1/responses');
        final payload =
            jsonDecode(utf8.decode(await body.toBytes()))
                as Map<String, dynamic>;
        expect(payload['model'], 'wither-chat');
        expect(payload['tools'], [
          {'type': 'image_generation', 'action': 'edit'},
        ]);
        final input = (payload['input'] as List).single as Map<String, dynamic>;
        expect(
          (input['content'] as List).map((item) => (item as Map)['type']),
          ['input_text', 'input_image'],
        );
        return http.StreamedResponse(
          http.ByteStream.fromBytes(
            utf8.encode(
              jsonEncode({
                'output': [
                  {
                    'type': 'message',
                    'content': [
                      {'type': 'output_text', 'text': 'Image generated.'},
                    ],
                  },
                ],
                'data': [
                  {'b64_json': base64Encode(_fixtureBytes)},
                ],
              }),
            ),
          ),
          200,
        );
      });

      final now = DateTime.now();
      final result =
          await AIService(
            BackendConfig(
              openAiApiKey: _testKey(),
              openAiBaseUrl: 'https://example.test/v1',
              openAiModel: 'wither-chat',
              openAiImageModel: 'wither-image',
              imageApiMode: ImageApiMode.responses,
            ),
            client,
            true,
          ).executeJob(
            AIJob(
              id: 'sketch-to-image-job',
              projectId: 'project',
              capability: AICapability.sketchToImage,
              prompt: 'render this sketch realistically',
              creativeParams: AICreativeParams(
                sourceImageBase64: base64Encode(_fixtureBytes),
              ),
              status: AIJobStatus.processing,
              createdAt: now,
              updatedAt: now,
            ),
            const [],
          );

      expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
      expect(paths, ['/v1/images/edits', '/v1/responses']);
    },
  );
  test('sketch-to-image sends the selected sketch to Images API', () async {
    final client = MockClient.streaming((request, body) async {
      expect(request.url.path, '/v1/images/edits');
      expect(request, isA<http.MultipartRequest>());
      final multipart = request as http.MultipartRequest;
      expect(multipart.fields['model'], 'wither-image');
      expect(
        multipart.fields['prompt'],
        contains('User request: render this sketch realistically'),
      );
      expect(multipart.files.map((file) => file.field), contains('image'));
      await body.toBytes();
      return http.StreamedResponse(
        http.ByteStream.fromBytes(
          utf8.encode(
            jsonEncode({
              'data': [
                {'b64_json': base64Encode(_fixtureBytes)},
              ],
            }),
          ),
        ),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
    final now = DateTime.now();
    final result =
        await AIService(
          BackendConfig(
            openAiApiKey: _testKey(),
            openAiBaseUrl: 'https://example.test/v1',
            openAiModel: 'wither-chat',
            openAiImageModel: 'wither-image',
            imageApiMode: ImageApiMode.responses,
          ),
          client,
          true,
        ).executeJob(
          AIJob(
            id: 'sketch-to-image-multipart-job',
            projectId: 'project',
            capability: AICapability.sketchToImage,
            prompt: 'render this sketch realistically',
            creativeParams: AICreativeParams(
              sourceImageBase64: base64Encode(_fixtureBytes),
            ),
            status: AIJobStatus.processing,
            createdAt: now,
            updatedAt: now,
          ),
          const [],
        );

    expect(result.status, AIJobStatus.completed, reason: result.errorMessage);
    expect(result.resultArtifact?.kind, AIArtifactKind.image);
  });

  test('composition image actions use the Images API edit route', () async {
    final paths = <String>[];
    final prompts = <String>[];
    final client = MockClient.streaming((request, body) async {
      paths.add(request.url.path);
      expect(request.url.path, '/v1/images/edits');
      expect(request, isA<http.MultipartRequest>());
      final multipart = request as http.MultipartRequest;
      expect(multipart.fields['model'], 'wither-image');
      prompts.add(multipart.fields['prompt']!);
      expect(multipart.files.map((file) => file.field), contains('image'));
      await body.toBytes();
      return http.StreamedResponse(
        http.ByteStream.fromBytes(
          utf8.encode(
            jsonEncode({
              'data': [
                {'b64_json': base64Encode(_fixtureBytes)},
              ],
            }),
          ),
        ),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
    final now = DateTime.now();
    for (final capability in const [
      AICapability.populate,
      AICapability.compositionRemove,
      AICapability.rearrange,
      AICapability.expandScene,
      AICapability.smartCutout,
    ]) {
      final result =
          await AIService(
            BackendConfig(
              openAiApiKey: _testKey(),
              openAiBaseUrl: 'https://example.test/v1',
              openAiModel: 'wither-chat',
              openAiImageModel: 'wither-image',
              imageApiMode: ImageApiMode.responses,
            ),
            client,
            true,
          ).executeJob(
            AIJob(
              id: 'composition-${capability.name}',
              projectId: 'project',
              capability: capability,
              prompt: 'apply ${capability.name} to the selected image',
              creativeParams: AICreativeParams(
                sourceImageBase64: base64Encode(_fixtureBytes),
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
        reason: '${capability.name}: ${result.errorMessage}',
      );
      expect(result.resultArtifact?.kind, AIArtifactKind.image);
    }

    expect(paths, List.filled(5, '/v1/images/edits'));
    expect(prompts, hasLength(5));
    expect(
      prompts.every((prompt) => prompt.contains('User request: apply ')),
      isTrue,
    );
  });

  test(
    'unimplemented assistant and enhancement actions fail without requests',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      });
      final now = DateTime.now();
      for (final capability in const [
        AICapability.upscale,
        AICapability.denoise,
        AICapability.sharpen,
        AICapability.restore,
        AICapability.detailEnhancement,
        AICapability.callTools,
        AICapability.agentGenerate,
        AICapability.agentEdit,
        AICapability.agentArrange,
        AICapability.promptToDiagram,
      ]) {
        final result =
            await AIService(
              BackendConfig(
                openAiApiKey: _testKey(),
                openAiBaseUrl: 'https://example.test/v1',
                openAiModel: 'wither-chat',
                openAiImageModel: 'wither-image',
              ),
              client,
              true,
            ).executeJob(
              AIJob(
                id: 'unsupported-${capability.name}',
                projectId: 'project',
                capability: capability,
                prompt: 'run ${capability.name}',
                status: AIJobStatus.processing,
                createdAt: now,
                updatedAt: now,
              ),
              const [],
            );

        expect(result.status, AIJobStatus.failed, reason: capability.name);
        expect(result.resultArtifact, isNull, reason: capability.name);
        expect(result.errorMessage, isNotEmpty, reason: capability.name);
      }
      expect(requests, 0);
    },
  );

  test(
    'unsupported capabilities fail without a key or simulated output',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      });
      final now = DateTime.now();
      for (final capability in const [
        AICapability.upscale,
        AICapability.denoise,
        AICapability.callTools,
        AICapability.agentArrange,
        AICapability.understandCanvas,
        AICapability.understandSelection,
      ]) {
        final result =
            await AIService(
              const BackendConfig(openAiBaseUrl: 'https://example.test/v1'),
              client,
              true,
            ).executeJob(
              AIJob(
                id: 'no-key-${capability.name}',
                projectId: 'project',
                capability: capability,
                prompt: 'run ${capability.name}',
                status: AIJobStatus.processing,
                createdAt: now,
                updatedAt: now,
              ),
              const [],
            );

        expect(result.status, AIJobStatus.failed, reason: capability.name);
        expect(result.isSimulated, isFalse, reason: capability.name);
        expect(result.resultArtifact, isNull, reason: capability.name);
      }
      expect(requests, 0);
    },
  );
}
