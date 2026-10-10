import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/data/ai_canvas_actions.dart';
import 'package:varian/features/ai/domain/ai_canvas_transaction.dart';
import 'package:varian/features/ai/state/ai_canvas_transaction_provider.dart';
import 'package:varian/features/ai/state/ai_provider.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('completed image output is placed without transaction review', () async {
    final container = ProviderContainer(
      overrides: [aiServiceProvider.overrideWithValue(_FixtureAIService())],
    );
    addTearDown(container.dispose);

    final engine = container.read(aiCreativeEngineProvider.notifier);
    final job = await engine.executeSequence(projectId: 'generated-insert');
    final transactions = container.read(
      aiCanvasTransactionProvider('generated-insert').notifier,
    );

    expect(job.status, AIJobStatus.completed);
    expect(container.read(documentNodesProvider), hasLength(1));
    expect(transactions.state.entries, hasLength(1));
    expect(
      transactions.state.entries.single.action.type,
      AICanvasActionType.placeGeneratedOutput,
    );
    expect(
      transactions.state.entries.single.phase,
      AICanvasTransactionPhase.inserted,
    );
    final node = container.read(documentNodesProvider).single;
    final payload = node.payload as ImagePayload;
    expect(payload.url, isNull);
    expect(
      validImageArtifactReference(payload.imageArtifactReference),
      'varian-image://fixture-1',
    );
    final manifest = container.read(documentAssetsProvider);
    final assetId = payload.assetId;
    expect(assetId, node.id);
    expect(assetId, isNotNull);
    final asset = manifest[assetId!];
    expect(asset, isNotNull);
    expect(asset!.kind, DocumentAssetKind.image);
    expect(asset.durableReference, 'varian-image://fixture-1');
    expect(asset.mimeType, 'image/jpeg');
    expect(asset.sizeBytes, 123);
    expect(asset.checksum, isNull);
    expect(
      await transactions.undo(transactions.state.entries.single.id),
      isTrue,
    );
    expect(container.read(documentNodesProvider), isEmpty);
  });

  test('failed image edits leave the source canvas unchanged', () async {
    final container = ProviderContainer(
      overrides: [aiServiceProvider.overrideWithValue(_FailedImageAIService())],
    );
    addTearDown(container.dispose);
    final source = CanvasNode(
      id: 'source-image',
      type: NodeType.image,
      x: 40,
      y: 60,
      width: 320,
      height: 240,
      payload: ImagePayload(url: 'https://cdn.example/source.png'),
    );
    container.read(documentNodesProvider.notifier).addNode(source);
    final engine = container.read(aiCreativeEngineProvider.notifier)
      ..setCapability(AICapability.imageToImage)
      ..setPrompt('Edit the selected image.');

    final job = await engine.executeSequence(
      projectId: 'failed-image-edit',
      sourceImageUrl: 'https://cdn.example/source.png',
      variantOfNodeId: source.id,
      spawnCanvasPosition: const Offset(400, 60),
    );

    expect(job.status, AIJobStatus.failed);
    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(1));
    expect(nodes.single.id, source.id);
    expect(nodes.single.payload, isA<ImagePayload>());
    expect(
      (nodes.single.payload as ImagePayload).url,
      'https://cdn.example/source.png',
    );
    expect(
      container.read(aiCanvasTransactionProvider('failed-image-edit')).entries,
      isEmpty,
    );
  });

  test('generated output respects a read-only collaboration session', () async {
    final container = ProviderContainer(
      overrides: [aiServiceProvider.overrideWithValue(_FixtureAIService())],
    );
    addTearDown(container.dispose);

    final job = await container
        .read(aiCreativeEngineProvider.notifier)
        .executeSequence(
          projectId: 'generated-readonly',
          canEditCanvas: () => false,
        );

    expect(job.status, AIJobStatus.completed);
    expect(container.read(documentNodesProvider), isEmpty);
    expect(
      container
          .read(aiCanvasTransactionProvider('generated-readonly'))
          .entries
          .single
          .phase,
      AICanvasTransactionPhase.rejected,
    );
  });

  test('permission revoked before publication blocks placement', () async {
    var permissionChecks = 0;
    final container = ProviderContainer(
      overrides: [aiServiceProvider.overrideWithValue(_FixtureAIService())],
    );
    addTearDown(container.dispose);

    final job = await container
        .read(aiCreativeEngineProvider.notifier)
        .executeSequence(
          projectId: 'generated-revoked',
          canEditCanvas: () => ++permissionChecks < 3,
        );

    expect(permissionChecks, 3);
    expect(job.status, AIJobStatus.completed);
    expect(container.read(documentNodesProvider), isEmpty);
    expect(
      container
          .read(aiCanvasTransactionProvider('generated-revoked'))
          .entries
          .single
          .phase,
      AICanvasTransactionPhase.rejected,
    );
  });

  test(
    'generated image manifest keeps metadata and checksum from transient bytes',
    () async {
      final store = MemoryImageArtifactStore();
      final container = ProviderContainer(
        overrides: [
          aiServiceProvider.overrideWithValue(
            _FixtureByteImageAIService(store),
          ),
          imageArtifactStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      final engine = container.read(aiCreativeEngineProvider.notifier);
      final job = await engine.executeSequence(projectId: 'generated-bytes');
      final transactions = container.read(
        aiCanvasTransactionProvider('generated-bytes').notifier,
      );
      expect(
        transactions.state.entries.single.phase,
        AICanvasTransactionPhase.inserted,
      );

      final node = container.read(documentNodesProvider).single;
      final payload = node.payload as ImagePayload;
      final asset = container.read(documentAssetsProvider)[payload.assetId!];
      expect(asset, isNotNull);
      expect(job.resultArtifact?.mimeType, 'image/jpeg');
      expect(payload.mimeType, 'image/jpeg');
      expect(payload.byteLength, _minimalJpegBytes.length);
      expect(asset!.mimeType, 'image/jpeg');
      expect(asset.sizeBytes, _minimalJpegBytes.length);
      expect(asset.checksum, sha256.convert(_minimalJpegBytes).toString());
    },
  );

  test('video output with only a runtime path is not staged', () async {
    final container = ProviderContainer(
      overrides: [
        aiServiceProvider.overrideWithValue(_FixtureVideoPathAIService()),
      ],
    );
    addTearDown(container.dispose);

    final engine = container.read(aiCreativeEngineProvider.notifier);
    final job = await engine.executeSequence(projectId: 'runtime-video');

    expect(job.status, AIJobStatus.completed);
    expect(
      container.read(aiCanvasTransactionProvider('runtime-video')).entries,
      isEmpty,
    );
  });

  test('AI video placement registers a matching manifest asset', () async {
    final container = ProviderContainer(
      overrides: [
        aiServiceProvider.overrideWithValue(_FixtureVideoAIService()),
      ],
    );
    addTearDown(container.dispose);

    final engine = container.read(aiCreativeEngineProvider.notifier);
    engine.setCapability(AICapability.imageToVideo);
    final job = await engine.executeSequence(projectId: 'generated-video');
    final transactions = container.read(
      aiCanvasTransactionProvider('generated-video').notifier,
    );
    expect(
      transactions.state.entries.single.phase,
      AICanvasTransactionPhase.inserted,
    );

    final node = container.read(documentNodesProvider).single;
    final payload = node.payload as VideoPayload;
    expect(job.status, AIJobStatus.completed);
    expect(payload.assetId, node.id);
    expect(payload.assetId, isNotNull);
    final asset = container.read(documentAssetsProvider)[node.id];
    expect(asset, isNotNull);
    expect(asset!.kind, DocumentAssetKind.video);
    expect(asset.durableReference, 'varian-video://fixture-video');
  });

  test('Replace falls back to Insert for an incompatible source', () async {
    final container = ProviderContainer(
      overrides: [
        aiServiceProvider.overrideWithValue(_FixtureVideoAIService()),
      ],
    );
    addTearDown(container.dispose);
    final source = CanvasNode(
      id: 'image-source',
      type: NodeType.image,
      x: 40,
      y: 60,
      width: 320,
      height: 240,
      payload: ImagePayload(url: 'https://cdn.example/source.png'),
    );
    container.read(documentNodesProvider.notifier).addNode(source);

    final engine = container.read(aiCreativeEngineProvider.notifier)
      ..setCapability(AICapability.imageToVideo)
      ..setOutputMode(AIOutputMode.replace);
    final job = await engine.executeSequence(
      projectId: 'video-replace-fallback',
      sourceImageUrl: 'https://cdn.example/source.png',
      variantOfNodeId: source.id,
    );
    final transactions = container.read(
      aiCanvasTransactionProvider('video-replace-fallback').notifier,
    );

    expect(job.outputMode, AIOutputMode.insert);
    expect(
      transactions.state.entries.single.phase,
      AICanvasTransactionPhase.inserted,
    );
    expect(container.read(documentNodesProvider), hasLength(2));
    expect(container.read(documentNodesProvider).first.id, source.id);
  });

  test('AI Model3D placement registers a matching manifest asset', () async {
    final container = ProviderContainer(
      overrides: [
        aiServiceProvider.overrideWithValue(_FixtureModel3DAIService()),
      ],
    );
    addTearDown(container.dispose);

    final engine = container.read(aiCreativeEngineProvider.notifier);
    engine.setCapability(AICapability.textTo3D);
    final job = await engine.executeSequence(projectId: 'generated-model');
    final transactions = container.read(
      aiCanvasTransactionProvider('generated-model').notifier,
    );
    expect(
      transactions.state.entries.single.phase,
      AICanvasTransactionPhase.inserted,
    );

    final node = container.read(documentNodesProvider).single;
    final payload = node.payload as Model3DPayload;
    expect(job.status, AIJobStatus.completed);
    expect(payload.assetId, node.id);
    expect(payload.assetId, isNotNull);
    final asset = container.read(documentAssetsProvider)[node.id];
    expect(asset, isNotNull);
    expect(asset!.kind, DocumentAssetKind.model3d);
    expect(asset.durableReference, 'varian-model3d://fixture-model');
  });

  test('shared replacement receives a fresh asset identity', () async {
    final container = ProviderContainer(
      overrides: [aiServiceProvider.overrideWithValue(_FixtureAIService())],
    );
    addTearDown(container.dispose);

    final sharedAsset = DocumentAsset(
      id: 'shared-image',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'shared.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://shared-image',
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );
    container.read(documentAssetsProvider.notifier).upsert(sharedAsset);
    final source = CanvasNode(
      id: 'shared-source',
      type: NodeType.image,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: ImagePayload(
        assetId: sharedAsset.id,
        imageArtifactReference: sharedAsset.durableReference,
      ),
    );
    final other = source.copyWith(id: 'shared-other');
    container.read(documentNodesProvider.notifier).addNode(source);
    container.read(documentNodesProvider.notifier).addNode(other);

    final engine = container.read(aiCreativeEngineProvider.notifier);
    engine.setOutputMode(AIOutputMode.replace);
    await engine.executeSequence(
      projectId: 'generated-shared-replace',
      variantOfNodeId: source.id,
    );
    final transactions = container.read(
      aiCanvasTransactionProvider('generated-shared-replace').notifier,
    );

    expect(
      transactions.state.entries.single.phase,
      AICanvasTransactionPhase.replaced,
    );
    final replacement = container
        .read(documentNodesProvider)
        .firstWhere((node) => node.id == source.id);
    final payload = replacement.payload as ImagePayload;
    expect(payload.assetId, isNot(sharedAsset.id));
    expect(payload.assetId, source.id);
    expect(
      container.read(documentAssetsProvider)[sharedAsset.id]?.durableReference,
      sharedAsset.durableReference,
    );
    expect(container.read(documentAssetsProvider)[payload.assetId!], isNotNull);
  });

  test(
    'selected output semantics place generated results automatically',
    () async {
      final container = ProviderContainer(
        overrides: [aiServiceProvider.overrideWithValue(_FixtureAIService())],
      );
      addTearDown(container.dispose);

      final source = CanvasNode(
        id: 'source',
        type: NodeType.image,
        x: 40,
        y: 60,
        width: 320,
        height: 240,
        payload: ImagePayload(url: 'https://cdn.example/source.png'),
      );
      container.read(documentNodesProvider.notifier).addNode(source);
      final engine = container.read(aiCreativeEngineProvider.notifier);
      engine.setOutputMode(AIOutputMode.insert);
      await engine.executeSequence(
        projectId: 'generated-replace',
        variantOfNodeId: source.id,
      );
      final transactions = container.read(
        aiCanvasTransactionProvider('generated-replace').notifier,
      );

      expect(container.read(documentNodesProvider), hasLength(2));
      expect(
        transactions.state.entries.single.phase,
        AICanvasTransactionPhase.inserted,
      );
      expect(container.read(documentNodesProvider).first.id, source.id);

      final insertEntryId = transactions.state.entries.single.id;
      expect(await transactions.undo(insertEntryId), isTrue);
      expect(container.read(documentNodesProvider), hasLength(1));

      final replacementContainer = ProviderContainer(
        overrides: [aiServiceProvider.overrideWithValue(_FixtureAIService())],
      );
      addTearDown(replacementContainer.dispose);
      replacementContainer.read(documentNodesProvider.notifier).addNode(source);
      final replacementEngine = replacementContainer.read(
        aiCreativeEngineProvider.notifier,
      );
      replacementEngine.setOutputMode(AIOutputMode.replace);
      await replacementEngine.executeSequence(
        projectId: 'generated-replace-again',
        variantOfNodeId: source.id,
      );
      final replacementTransactions = replacementContainer.read(
        aiCanvasTransactionProvider('generated-replace-again').notifier,
      );

      expect(
        replacementTransactions.state.entries.single.phase,
        AICanvasTransactionPhase.replaced,
      );
      expect(replacementContainer.read(documentNodesProvider), hasLength(1));
      expect(
        replacementContainer.read(documentNodesProvider).single.id,
        source.id,
      );
      final replacementPayload =
          replacementContainer.read(documentNodesProvider).single.payload
              as ImagePayload;
      expect(replacementPayload.url, isNull);
      expect(
        validImageArtifactReference(replacementPayload.imageArtifactReference),
        'varian-image://fixture-1',
      );
      final replacementManifest = replacementContainer.read(
        documentAssetsProvider,
      );
      final replacementAssetId = replacementPayload.assetId;
      expect(replacementAssetId, isNotNull);
      final replacementAsset = replacementManifest[replacementAssetId!];
      expect(replacementAsset, isNotNull);
      expect(replacementAsset!.kind, DocumentAssetKind.image);
    },
  );
}

const _minimalJpegBytes = <int>[255, 216, 255];

class _FailedImageAIService extends AIService {
  _FailedImageAIService()
    : super(
        const BackendConfig(),
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
        null,
        MemoryImageArtifactStore(),
      );

  @override
  Future<AIJob> executeJob(AIJob job, List<CanvasNode> currentNodes) async =>
      job.copyWith(
        status: AIJobStatus.failed,
        errorMessage: 'provider returned no image asset',
        updatedAt: DateTime.utc(2026, 9, 29),
      );
}

class _FixtureByteImageAIService extends AIService {
  final ImageArtifactStore _store;

  _FixtureByteImageAIService(this._store)
    : super(
        const BackendConfig(),
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
        null,
        _store,
      );

  @override
  Future<AIJob> executeJob(AIJob job, List<CanvasNode> currentNodes) async {
    final artifact = await _store.save(
      Uint8List.fromList(_minimalJpegBytes),
      fileName: 'fixture.jpg',
    );
    return job.copyWith(
      status: AIJobStatus.completed,
      resultArtifact: AIArtifact(
        kind: AIArtifactKind.image,
        reference: artifact.reference,
        mimeType: 'image/jpeg',
        byteLength: _minimalJpegBytes.length,
        bytes: Uint8List.fromList(_minimalJpegBytes),
      ),
      updatedAt: DateTime.utc(2026, 9, 13),
    );
  }
}

class _FixtureVideoAIService extends AIService {
  _FixtureVideoAIService()
    : super(
        const BackendConfig(),
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
        null,
        MemoryImageArtifactStore(),
      );

  @override
  Future<AIJob> executeJob(AIJob job, List<CanvasNode> currentNodes) async {
    return job.copyWith(
      status: AIJobStatus.completed,
      resultVideoReference: 'varian-video://fixture-video',
      updatedAt: DateTime.utc(2026, 9, 13),
    );
  }
}

class _FixtureModel3DAIService extends AIService {
  _FixtureModel3DAIService()
    : super(
        const BackendConfig(),
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
        null,
        MemoryImageArtifactStore(),
      );

  @override
  Future<AIJob> executeJob(AIJob job, List<CanvasNode> currentNodes) async {
    return job.copyWith(
      status: AIJobStatus.completed,
      resultArtifact: const AIArtifact(
        kind: AIArtifactKind.model3d,
        reference: 'varian-model3d://fixture-model',
        fileName: 'fixture.glb',
        mimeType: 'model/gltf-binary',
      ),
      updatedAt: DateTime.utc(2026, 9, 13),
    );
  }

  @override
  Future<CanvasNode> spawnModel3DNodeFromJob(
    AIJob job, {
    required String projectId,
    Offset? position,
    String? variantOfNodeId,
  }) async => CanvasNode(
    id: 'model-node',
    type: NodeType.model3d,
    x: position?.dx ?? 200,
    y: position?.dy ?? 200,
    width: 320,
    height: 240,
    payload: Model3DPayload(
      fileName: 'fixture.glb',
      artifactReference: 'varian-model3d://fixture-model',
    ),
  );
}

class _FixtureVideoPathAIService extends AIService {
  _FixtureVideoPathAIService()
    : super(
        const BackendConfig(),
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
        null,
        MemoryImageArtifactStore(),
      );

  @override
  Future<AIJob> executeJob(AIJob job, List<CanvasNode> currentNodes) async {
    return job.copyWith(
      status: AIJobStatus.completed,
      resultVideoPath: r'C:\\runtime\\generated.mp4',
      updatedAt: DateTime.utc(2026, 9, 13),
    );
  }
}

class _FixtureAIService extends AIService {
  _FixtureAIService()
    : super(
        const BackendConfig(),
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
        null,
        MemoryImageArtifactStore(),
      );

  @override
  Future<AIJob> executeJob(AIJob job, List<CanvasNode> currentNodes) async {
    return job.copyWith(
      status: AIJobStatus.completed,
      resultArtifact: const AIArtifact(
        kind: AIArtifactKind.image,
        reference: 'varian-image://fixture-1',
        mimeType: 'image/jpeg',
        byteLength: 123,
      ),
      updatedAt: DateTime.utc(2026, 9, 13),
    );
  }
}
