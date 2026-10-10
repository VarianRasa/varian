import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/domain/ai_provider_executor.dart';
import 'package:varian/features/ai/state/ai_canvas_transaction_provider.dart';
import 'package:varian/features/ai/state/ai_provider.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';

DateTime _now() => DateTime.now();

const _onePixelPngBytes = <int>[
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
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  3,
  3,
  1,
  0,
  157,
  107,
  68,
  112,
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

class _BlockingAIService extends AIService {
  final Completer<void> gate;
  final Completer<void> started = Completer<void>();

  _BlockingAIService(this.gate);

  @override
  Future<AIJob> executeJob(AIJob job, List<CanvasNode> currentNodes) async {
    started.complete();
    await gate.future;
    return job.copyWith(
      status: AIJobStatus.completed,
      resultArtifact: const AIArtifact(
        kind: AIArtifactKind.image,
        reference: 'varian-image://stale-result',
        mimeType: 'image/png',
      ),
      updatedAt: DateTime.utc(2026, 9, 26),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'materializes provider image output before returning a completed job',
    () async {
      final store = MemoryImageArtifactStore();
      final now = _now();
      final dataUri =
          'data:image/png;base64,${base64Encode(_onePixelPngBytes)}';
      final service = AIService(
        const BackendConfig(),
        null,
        false,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        {
          'fixture-provider': CallbackAIProviderExecutor(
            provider: 'fixture-provider',
            callback: (job, _) async => job.copyWith(
              status: AIJobStatus.completed,
              resultArtifact: AIArtifact(
                kind: AIArtifactKind.image,
                url: dataUri,
                mimeType: 'image/png',
              ),
              updatedAt: now,
            ),
          ),
        },
        null,
        store,
      );

      final completed = await service.executeJob(
        AIJob(
          id: 'provider-image-job',
          projectId: 'provider-image-project',
          capability: AICapability.textToImage,
          prompt: 'provider image',
          provider: 'fixture-provider',
          createdAt: now,
          updatedAt: now,
        ),
        const [],
      );

      expect(completed.status, AIJobStatus.completed);
      final artifact = completed.resultArtifact;
      expect(artifact?.kind, AIArtifactKind.image);
      expect(validImageArtifactReference(artifact?.reference), isNotNull);
      expect(artifact?.url, isNull);
      expect(
        await store.hydrate(artifact!.reference!, fileName: 'provider.png'),
        isNotNull,
      );
      expect(
        completed.toPersistenceJson().toString(),
        isNot(contains('data:')),
      );
    },
  );

  test(
    'keeps durable image source identity while stripping runtime inputs',
    () {
      const params = AICreativeParams(
        sourceImageBase64: 'runtime-base64',
        sourceImageUrl: 'https://runtime.example/image.png',
        sourceImageArtifactReference: 'varian-image://fixture-1',
        sourceImageStoragePath: 'source-project/images/input.png',
        sourceImageMimeType: 'image/jpeg',
        sourceImageByteLength: 123,
      );

      final persisted = params.toPersistenceJson();

      expect(
        persisted['sourceImageArtifactReference'],
        'varian-image://fixture-1',
      );
      expect(
        persisted['sourceImageStoragePath'],
        'source-project/images/input.png',
      );
      expect(persisted['sourceImageMimeType'], 'image/jpeg');
      expect(persisted['sourceImageByteLength'], 123);
      expect(persisted, isNot(contains('sourceImageBase64')));
      expect(persisted, isNot(contains('sourceImageUrl')));
    },
  );

  test('rejects an unsafe durable source storage path', () {
    const params = AICreativeParams(
      sourceImageStoragePath: '../other-project/images/input.png',
    );

    expect(
      params.toPersistenceJson(),
      isNot(contains('sourceImageStoragePath')),
    );
  });

  test(
    'round-trips durable source metadata without runtime delivery values',
    () {
      const params = AICreativeParams(
        sourceImageArtifactReference: 'varian-image://fixture-1',
        sourceImageStoragePath: 'source-project/images/input.png',
        sourceImageMimeType: 'image/webp',
        sourceImageByteLength: 456,
      );
      final restored = AICreativeParams.fromJson(params.toPersistenceJson());

      expect(restored.sourceImageArtifactReference, 'varian-image://fixture-1');
      expect(
        restored.sourceImageStoragePath,
        'source-project/images/input.png',
      );
      expect(restored.sourceImageMimeType, 'image/webp');
      expect(restored.sourceImageByteLength, 456);
      expect(restored.sourceImageBase64, isNull);
      expect(restored.sourceImageUrl, isNull);
    },
  );

  group('spawnImageNodeFromJob', () {
    AIJob completedJob() => AIJob(
      id: 'job1',
      projectId: 'p1',
      capability: AICapability.imageToImage,
      prompt: 'modern facade',
      status: AIJobStatus.completed,
      resultArtifact: const AIArtifact(
        kind: AIArtifactKind.image,
        reference: 'varian-image://fixture-1',
        mimeType: 'image/jpeg',
        byteLength: 123,
      ),
      createdAt: _now(),
      updatedAt: _now(),
    );

    test('uses the supplied world-space position', () {
      final node = AIService().spawnImageNodeFromJob(
        completedJob(),
        position: const Offset(37, 81),
      );

      expect(node.type, NodeType.image);
      expect(node.x, 37);
      expect(node.y, 81);
      expect((node.payload as ImagePayload).url, isNull);
      expect(
        validImageArtifactReference(
          (node.payload as ImagePayload).imageArtifactReference,
        ),
        'varian-image://fixture-1',
      );
    });

    test('preserves the source node when creating a linked variant', () {
      final node = AIService().spawnImageNodeFromJob(
        completedJob(),
        variantOfNodeId: 'source-node',
      );

      expect(node.variantOfNodeId, 'source-node');
      expect((node.payload as ImagePayload).url, isNull);
    });

    test('rejects a completed job without an opaque image artifact', () {
      final job = AIJob(
        id: 'job1',
        projectId: 'p1',
        capability: AICapability.imageToImage,
        prompt: 'modern facade',
        status: AIJobStatus.completed,
        resultImageUrls: ['https://cdn.example.com/list.png'],
        createdAt: _now(),
        updatedAt: _now(),
      );

      expect(
        () => AIService().spawnImageNodeFromJob(job),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('spawnVideoNodeFromJob', () {
    AIJob completedJob({
      String? resultAssetUrl,
      String? resultVideoReference,
    }) => AIJob(
      id: 'video-job',
      projectId: 'p1',
      capability: AICapability.imageToVideo,
      prompt: 'animate the facade',
      status: AIJobStatus.completed,
      resultAssetUrl: resultAssetUrl,
      resultVideoReference: resultVideoReference,
      createdAt: _now(),
      updatedAt: _now(),
    );

    test('materializes image-to-video jobs as video cards', () {
      const reference = 'varian-video://fixture-video-1';
      final node = AIService().spawnVideoNodeFromJob(
        completedJob(resultVideoReference: reference),
        position: const Offset(37, 81),
        variantOfNodeId: 'source-node',
      );

      expect(node.type, NodeType.videoCard);
      expect(node.x, 37);
      expect(node.y, 81);
      expect(node.variantOfNodeId, 'source-node');
      expect((node.payload as VideoPayload).videoArtifactReference, reference);
      expect((node.payload as VideoPayload).videoUrl, isNull);
    });

    for (final invalidUrl in [
      '',
      'https://cdn.example.com/result.mp4',
      'data:video/mp4,invalid',
      'blob-invalid',
      'http-invalid',
      'not a url',
    ]) {
      test(
        'rejects runtime video URL without durable artifact $invalidUrl',
        () {
          expect(
            () => AIService().spawnVideoNodeFromJob(
              completedJob(resultAssetUrl: invalidUrl),
            ),
            throwsA(isA<StateError>()),
          );
        },
      );
    }
  });

  test(
    'stale AI completion does not publish after the run is invalidated',
    () async {
      final gate = Completer<void>();
      final service = _BlockingAIService(gate);
      final container = ProviderContainer(
        overrides: [aiServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(aiCreativeEngineProvider.notifier);
      final pending = notifier.executeSequence(projectId: 'stale-project');
      await service.started.future;
      notifier.invalidatePendingRuns();
      gate.complete();

      final job = await pending;

      expect(job.status, AIJobStatus.canceled);
      expect(container.read(documentNodesProvider), isEmpty);
      expect(
        container.read(aiCanvasTransactionProvider('stale-project')).entries,
        isEmpty,
      );
    },
  );

  group('AI executeSequence placement', () {
    test('text-to-image works on an empty canvas', () async {
      final container = ProviderContainer(
        overrides: [
          imageArtifactStoreProvider.overrideWithValue(
            MemoryImageArtifactStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(aiCreativeEngineProvider.notifier);
      notifier.setPrompt('a photorealistic jet');
      final job = await notifier.executeSequence(projectId: 'p1');
      expect(job.capability, AICapability.textToImage);
      expect(job.status, AIJobStatus.completed);
      final nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(1));
      expect(nodes.single.type, NodeType.image);
      expect(nodes.single.x, 200);
      expect(nodes.single.y, 200);
      final payload = nodes.single.payload as ImagePayload;
      expect(payload.assetId, isNotNull);
      expect(
        container.read(documentAssetsProvider)[payload.assetId!]!.kind,
        DocumentAssetKind.image,
      );
    });

    test('completed generation reports the spawned node', () async {
      final container = ProviderContainer(
        overrides: [
          imageArtifactStoreProvider.overrideWithValue(
            MemoryImageArtifactStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      CanvasNode? createdNode;
      final notifier = container.read(aiCreativeEngineProvider.notifier);
      final job = await notifier.executeSequence(
        projectId: 'p1',
        onNodeCreated: (node) => createdNode = node,
      );
      expect(job.status, AIJobStatus.completed);
      expect(createdNode, isNotNull);
      expect(createdNode!.type, NodeType.image);
      expect(container.read(documentNodesProvider).single.id, createdNode!.id);
      final payload = createdNode!.payload as ImagePayload;
      expect(payload.assetId, isNotNull);
      expect(
        container.read(documentAssetsProvider)[payload.assetId!]!.kind,
        DocumentAssetKind.image,
      );
    });

    test('completed generation spawns node at spawnCanvasPosition', () async {
      final container = ProviderContainer(
        overrides: [
          imageArtifactStoreProvider.overrideWithValue(
            MemoryImageArtifactStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(documentNodesProvider.notifier)
          .addNode(
            CanvasNode(
              id: 'src1',
              type: NodeType.image,
              x: 100,
              y: 50,
              width: 300,
              height: 200,
              payload: ImagePayload(url: 'https://x.test/a.png'),
            ),
          );

      final notifier = container.read(aiCreativeEngineProvider.notifier);
      final job = await notifier.executeSequence(
        projectId: 'p1',
        sourceImageUrl: 'https://cdn.example.com/source.jpg',
        spawnCanvasPosition: const Offset(440, 50),
      );
      expect(job.status, AIJobStatus.completed);
      final nodes = container.read(documentNodesProvider);
      expect(nodes.length, 2);
      final spawned = nodes.last;
      expect(spawned.type, NodeType.image);
      expect(spawned.x, 440);
      expect(spawned.y, 50);
    });

    test('links an AI result to its source and preserves undo/redo', () async {
      final container = ProviderContainer(
        overrides: [
          imageArtifactStoreProvider.overrideWithValue(
            MemoryImageArtifactStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final source = CanvasNode(
        id: 'source-node',
        type: NodeType.image,
        x: 100,
        y: 50,
        width: 300,
        height: 200,
        payload: ImagePayload(url: 'https://x.test/source.png'),
      );
      final nodesNotifier = container.read(documentNodesProvider.notifier);
      nodesNotifier.addNode(source);

      final notifier = container.read(aiCreativeEngineProvider.notifier);
      notifier.setCapability(AICapability.imageToImage);
      final job = await notifier.executeSequence(
        projectId: 'p1',
        sourceImageUrl: 'https://x.test/source.png',
        variantOfNodeId: source.id,
        spawnCanvasPosition: const Offset(440, 50),
      );
      expect(job.status, AIJobStatus.completed);
      var nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(2));
      final generatedId = nodes.last.id;
      expect(nodes.first.id, source.id);
      expect(nodes.first.payload, source.payload);
      expect(nodes.last.variantOfNodeId, source.id);

      nodesNotifier.undo();
      nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(1));
      expect(nodes.single.id, source.id);

      nodesNotifier.redo();
      nodes = container.read(documentNodesProvider);
      expect(nodes, hasLength(2));
      expect(nodes.last.id, generatedId);
      expect(nodes.last.variantOfNodeId, source.id);
    });

    test('rejects a variant source that is no longer on the canvas', () async {
      final container = ProviderContainer(
        overrides: [
          imageArtifactStoreProvider.overrideWithValue(
            MemoryImageArtifactStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(aiCreativeEngineProvider.notifier);
      await expectLater(
        notifier.executeSequence(
          projectId: 'p1',
          variantOfNodeId: 'missing-source',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
