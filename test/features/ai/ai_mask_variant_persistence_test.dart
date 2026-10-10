import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/ai_mask_renderer.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/domain/ai_workflow_contract.dart';
import 'package:varian/features/ai/state/ai_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('renders a structured mask payload as a valid PNG', () async {
    const mask = AIMaskDocument(
      width: 64,
      height: 48,
      operation: AIMaskOperation.replaceObject,
      strokes: [
        AIMaskStroke(points: [Offset(8, 8), Offset(40, 24)], width: 12),
      ],
    );

    final bytes = await AIMaskRenderer.render(mask);

    expect(bytes, isNotEmpty);
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test(
    'persists mask payload and variant review state without mask bytes',
    () async {
      const mask = AIMaskDocument(
        width: 128,
        height: 96,
        operation: AIMaskOperation.inpaint,
        strokes: [
          AIMaskStroke(points: [Offset(12, 16)], width: 20),
        ],
      );
      const variants = AIVariantSet(
        id: 'group-1',
        variants: [
          AIOutputVariant(
            id: 'variant-a',
            index: 0,
            artifactReference: 'varian-image://variant-a',
            favorite: true,
            selectedForCompare: true,
            metadata: {'seed': 11},
          ),
          AIOutputVariant(
            id: 'variant-b',
            index: 1,
            artifactReference: 'varian-image://variant-b',
            selectedForCompare: true,
          ),
        ],
      );
      final job = AIJob(
        id: 'job-1',
        projectId: 'project-1',
        capability: AICapability.replaceObject,
        prompt: 'Replace the object',
        creativeParams: AICreativeParams(
          sourceImageUrl: 'https://cdn.example/source.png',
          sourceImageBase64: 'runtime-source-bytes',
          maskImageBase64: 'runtime-mask-bytes',
          maskPayload: mask.toJson(),
        ),
        sourceNodeIds: const ['source-node'],
        variantGroupId: variants.id,
        resultArtifact: const AIArtifact(
          kind: AIArtifactKind.image,
          reference: 'varian-image://variant-a',
          mimeType: 'image/png',
        ),
        variantSetPayload: variants.toJson(),
        outputMode: AIOutputMode.replace,
        status: AIJobStatus.completed,
        createdAt: DateTime.utc(2026, 9, 13),
        updatedAt: DateTime.utc(2026, 9, 13),
      );

      final storage = LocalStorageService();
      await storage.saveAIJobHistory(job.projectId, [job]);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ccs_ai_jobs_${job.projectId}');
      final restored = (await storage.loadAIJobHistory(job.projectId)).single;

      expect(raw, contains('maskPayload'));
      expect(raw, contains('variantSet'));
      expect(raw, isNot(contains('runtime-source-bytes')));
      expect(raw, isNot(contains('runtime-mask-bytes')));
      expect(restored.sourceNodeIds, ['source-node']);
      expect(restored.outputMode, AIOutputMode.replace);
      expect(
        AIMaskDocument.fromJson(restored.creativeParams!.maskPayload!),
        isA<AIMaskDocument>(),
      );
      final restoredVariants = AIVariantSet.fromJson(
        restored.variantSetPayload!,
      );
      expect(
        restoredVariants.variants
            .singleWhere((item) => item.id == 'variant-a')
            .favorite,
        isTrue,
      );
      expect(restoredVariants.compareSelection, hasLength(2));
      expect(restoredVariants.variants.first.metadata['seed'], 11);
    },
  );

  test('variant compare selection can be toggled off', () {
    const variants = AIVariantSet(
      id: 'group-2',
      variants: [AIOutputVariant(id: 'a', index: 0)],
    );

    final selected = variants.toggleCompare('a');
    final cleared = selected.toggleCompare('a');

    expect(selected.compareSelection, hasLength(1));
    expect(cleared.compareSelection, isEmpty);
  });

  test(
    'notifier preserves mask and variants through a replace workflow',
    () async {
      final container = ProviderContainer(
        overrides: [
          aiServiceProvider.overrideWithValue(_ReplaceFixtureAIService()),
        ],
      );
      addTearDown(container.dispose);
      final source = CanvasNode(
        id: 'source-node',
        type: NodeType.image,
        x: 40,
        y: 60,
        width: 320,
        height: 240,
        payload: ImagePayload(url: 'https://cdn.example/source.png'),
      );
      container.read(documentNodesProvider.notifier).addNode(source);
      final notifier = container.read(aiCreativeEngineProvider.notifier);
      const mask = AIMaskDocument(
        width: 256,
        height: 192,
        operation: AIMaskOperation.replaceObject,
        strokes: [
          AIMaskStroke(points: [Offset(10, 10), Offset(80, 40)], width: 18),
        ],
      );
      notifier.setMaskDocument(mask);
      notifier.setOutputMode(AIOutputMode.replace);

      final job = await notifier.executeSequence(
        projectId: 'project-e2e',
        sourceImageUrl: 'https://cdn.example/source.png',
        variantOfNodeId: source.id,
      );

      final updatedNode = container.read(documentNodesProvider).single;
      expect(updatedNode.id, source.id);
      expect((updatedNode.payload as ImagePayload).url, isNull);
      expect(
        (updatedNode.payload as ImagePayload).imageArtifactReference,
        'varian-image://fixture-1',
      );
      expect(job.outputMode, AIOutputMode.replace);
      expect(job.sourceNodeIds, [source.id]);
      expect(job.creativeParams?.maskPayload?['operation'], 'replaceObject');
      expect(
        AIVariantSet.fromJson(job.variantSetPayload!).variants,
        hasLength(2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final history = await LocalStorageService().loadAIJobHistory(
        'project-e2e',
      );
      expect(
        history.single.creativeParams?.maskPayload?['strokes'],
        isNotEmpty,
      );
      expect(
        AIVariantSet.fromJson(history.single.variantSetPayload!).variants,
        hasLength(2),
      );
    },
  );

  test(
    'notifier persists generated variants when inserting a new node',
    () async {
      final container = ProviderContainer(
        overrides: [
          aiServiceProvider.overrideWithValue(_ReplaceFixtureAIService()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(aiCreativeEngineProvider.notifier);
      notifier.setOutputMode(AIOutputMode.insert);

      final job = await notifier.executeSequence(projectId: 'project-insert');

      expect(container.read(documentNodesProvider), hasLength(1));
      expect(job.outputMode, AIOutputMode.insert);
      expect(
        AIVariantSet.fromJson(job.variantSetPayload!).variants,
        hasLength(2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final history = await LocalStorageService().loadAIJobHistory(
        'project-insert',
      );
      expect(history.single.outputMode, AIOutputMode.insert);
      expect(
        AIVariantSet.fromJson(history.single.variantSetPayload!).variants,
        hasLength(2),
      );
    },
  );
}

class _ReplaceFixtureAIService extends AIService {
  _ReplaceFixtureAIService()
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
        mimeType: 'image/png',
      ),
      variantGroupId: 'fixture-variants',
      variantSetPayload: {
        'id': 'fixture-variants',
        'variants': [
          {
            'id': 'fixture-variant-a',
            'artifactReference': 'varian-image://fixture-1',
            'index': 0,
          },
          {
            'id': 'fixture-variant-b',
            'artifactReference': 'varian-image://fixture-2',
            'index': 1,
          },
        ],
      },
      provider: 'fixture',
      model: 'fixture-image',
      updatedAt: DateTime.utc(2026, 9, 13),
    );
  }
}
