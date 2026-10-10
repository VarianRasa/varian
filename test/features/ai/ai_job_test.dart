import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/ai/domain/ai_capability_matrix.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/state/ai_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AI Job Engine Tests', () {
    test('Summarize sticky notes extracts canvas ideas', () async {
      final container = ProviderContainer();
      final nodeNotifier = container.read(documentNodesProvider.notifier);

      nodeNotifier.addNode(
        CanvasNode(
          id: 'n1',
          type: NodeType.stickyNote,
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          payload: StickyNotePayload(text: 'Idea 1: Cross-platform Canvas'),
        ),
      );

      final aiNotifier = container.read(aiJobsProvider.notifier);
      final job = await aiNotifier.runJob(
        projectId: 'p1',
        capability: AICapability.summarizeNotes,
        prompt: '',
      );

      expect(job.status, AIJobStatus.completed);
      expect(job.resultText, contains('Idea 1: Cross-platform Canvas'));
    });

    test(
      'persists provenance, variants, output mode, and sanitized history',
      () async {
        final job = AIJob(
          id: 'job-1',
          projectId: 'p1',
          capability: AICapability.textToImage,
          prompt: 'A poster',
          creativeParams: const AICreativeParams(
            sourceImageBase64: 'sensitive-runtime-input',
            maskImageBase64: 'sensitive-mask',
          ),
          provider: 'openai-compatible',
          model: 'image-model',
          estimatedCost: 0.02,
          actualCost: 0.018,
          sourceAssetIds: const ['asset-1'],
          sourceNodeIds: const ['node-1'],
          variantGroupId: 'variant-group',
          variantIndex: 2,
          favorite: true,
          outputMode: AIOutputMode.compare,
          provenance: const {'license': 'provider-terms', 'seed': 42},
          createdAt: DateTime.utc(2026, 9, 11),
          updatedAt: DateTime.utc(2026, 9, 11),
        );
        final restored = AIJob.fromJson(job.toJson());
        expect(restored.provider, 'openai-compatible');
        expect(restored.outputMode, AIOutputMode.compare);
        expect(restored.variantIndex, 2);
        expect(restored.provenance['seed'], 42);

        final storage = LocalStorageService();
        await storage.saveAIJobHistory('p1', [job]);
        final history = await storage.loadAIJobHistory('p1');
        expect(history, hasLength(1));
        expect(history.single.creativeParams?.sourceImageBase64, isNull);
        expect(history.single.creativeParams?.maskImageBase64, isNull);
      },
    );

    test('persistence JSON excludes runtime inputs and outputs', () {
      final now = DateTime.utc(2026, 9, 23);
      final job = AIJob(
        id: 'job-hostile',
        projectId: 'p1',
        capability: AICapability.imageToVideo,
        prompt: 'make a secure preview',
        creativeParams: const AICreativeParams(
          sourceImageBase64: 'data:image/png;base64,secret-bytes',
          sourceImageUrl: 'https://storage.example.test/image.png?token=secret',
          referenceImageUrl: r'C:\runtime\reference.png',
          extraConfig: {
            'safeLabel': 'kept',
            'apiToken': 'secret-token',
            'providerUrl': 'https://provider.example.test?sig=secret',
          },
        ),
        resultAssetUrl: 'https://cdn.example.test/output.png?sig=secret',
        resultVideoPath: r'C:\runtime\output.mp4',
        resultVideoUrl: 'blob:https://example.test/runtime',
        resultVideoReference: 'memory://runtime/output',
        resultImageUrls: const ['data:image/png;base64,output-bytes'],
        errorMessage:
            'provider failed at https://cdn.example.test/output?token=secret',
        createdAt: now,
        updatedAt: now,
      );

      final encoded = job.toPersistenceJson();
      final encodedText = encoded.toString();
      expect(encodedText, isNot(contains('secret-bytes')));
      expect(encodedText, isNot(contains('token=secret')));
      expect(encodedText, isNot(contains('output.mp4')));
      expect(encodedText, isNot(contains('blob:')));
      expect(encodedText, isNot(contains('memory://')));
      expect(encodedText, contains('safeLabel'));
      expect(encodedText, contains('[redacted URL]'));
    });

    test(
      'capability matrix distinguishes configured and unavailable paths',
      () {
        final matrix = AICapabilityMatrix.fromProviderConfig(
          hasImageProvider: true,
          hasVideoProvider: false,
          hasThreeDProvider: true,
        );
        expect(matrix.canRun(AICapability.textToImage), isTrue);
        expect(matrix.canRun(AICapability.populate), isTrue);
        expect(matrix.canRun(AICapability.textTo3D), isTrue);
        expect(matrix.canRun(AICapability.imageToVideo), isFalse);
        expect(matrix.canRun(AICapability.upscale), isFalse);
        expect(matrix.canRun(AICapability.agentArrange), isFalse);
        expect(matrix.canRun(AICapability.understandCanvas), isFalse);
        expect(
          matrix[AICapability.imageToVideo].availability,
          AICapabilityAvailability.unavailable,
        );

        final chatMatrix = AICapabilityMatrix.fromProviderConfig(
          hasImageProvider: false,
          hasVideoProvider: false,
          hasThreeDProvider: false,
          hasChatProvider: true,
        );
        expect(chatMatrix.canRun(AICapability.understandCanvas), isTrue);
        expect(chatMatrix.canRun(AICapability.callTools), isFalse);
      },
    );
  });
}
