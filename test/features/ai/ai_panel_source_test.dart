import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/domain/models/ai_artifact.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/presentation/ai_panel.dart';
import 'package:varian/features/ai/state/ai_provider.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';
import '../../test_app.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final scenario in [
    (
      name: 'Image-to-Image sends the selected image node',
      capability: AICapability.imageToImage,
      payload: ImagePayload(url: 'https://cdn.example.test/source.png'),
    ),
    (
      name: 'Sketch-to-Image sends a direct image LinkCard',
      capability: AICapability.sketchToImage,
      payload: LinkPayload(url: 'https://i.pinimg.com/736x/source.jpg'),
    ),
  ]) {
    testWidgets(scenario.name, (tester) async {
      const sourceId = 'selected-source';
      const sourceX = 120.0;
      const sourceY = 75.0;
      const sourceWidth = 320.0;
      final service = _RecordingAIService();
      final container = ProviderContainer(
        overrides: [
          backendConfigProvider.overrideWith(
            (_) => _ReadyBackendConfigNotifier(),
          ),
          aiServiceProvider.overrideWithValue(service),
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
              id: sourceId,
              type: scenario.payload is ImagePayload
                  ? NodeType.image
                  : NodeType.linkCard,
              x: sourceX,
              y: sourceY,
              width: sourceWidth,
              height: 220,
              payload: scenario.payload,
            ),
          );
      container.read(selectionProvider.notifier).select(sourceId);
      container.read(aiCreativeEngineProvider.notifier)
        ..setCapability(scenario.capability)
        ..setPrompt('Turn this reference into a modern house.');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(const AIPanel(projectId: 'selected-source-test')),
        ),
      );
      await tester.pumpAndSettle();
      final generateButton = find.ancestor(
        of: find.text('Generate'),
        matching: find.byType(UiButton),
      );
      final onPressed = tester.widget<UiButton>(generateButton).onPressed!;
      await (onPressed as dynamic)();
      await tester.pumpAndSettle();

      final submitted = service.submittedJob;
      expect(submitted, isNotNull);
      expect(submitted!.capability, scenario.capability);
      expect(submitted.prompt, 'Turn this reference into a modern house.');
      expect(
        submitted.creativeParams?.sourceImageUrl,
        scenario.payload is ImagePayload
            ? 'https://cdn.example.test/source.png'
            : 'https://i.pinimg.com/736x/source.jpg',
      );
      expect(submitted.creativeParams?.sourceImageBase64, isNull);
      expect(submitted.sourceNodeIds, [sourceId]);

      final outputNode = container.read(documentNodesProvider).last;
      expect(outputNode.type, NodeType.image);
      expect(outputNode.x, sourceX + sourceWidth + 40);
      expect(outputNode.y, sourceY);
    });
  }

  testWidgets('attachment takes precedence over a selected canvas image', (
    tester,
  ) async {
    const sourceId = 'canvas-source';
    const attachmentBytes = _minimalPngBytes;
    final service = _RecordingAIService();
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(),
        ),
        aiServiceProvider.overrideWithValue(service),
        imageArtifactStoreProvider.overrideWithValue(
          MemoryImageArtifactStore(),
        ),
        aiImageAttachmentPickerProvider.overrideWithValue(
          () async => AssetPickerResult(
            name: 'reference.png',
            bytes: Uint8List.fromList(attachmentBytes),
            extension: 'png',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(documentNodesProvider.notifier)
        .addNode(
          CanvasNode(
            id: sourceId,
            type: NodeType.image,
            x: 20,
            y: 30,
            width: 120,
            height: 100,
            payload: ImagePayload(url: 'https://cdn.example.test/canvas.png'),
          ),
        );
    container.read(selectionProvider.notifier).select(sourceId);
    container.read(aiCreativeEngineProvider.notifier)
      ..setCapability(AICapability.imageToImage)
      ..setPrompt('Reimagine this reference.');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: 'attachment-source-test')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add or choose output'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload image'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('reference.png'), findsOneWidget);

    final generateButton = find.ancestor(
      of: find.text('Generate'),
      matching: find.byType(UiButton),
    );
    final onPressed = tester.widget<UiButton>(generateButton).onPressed!;
    await (onPressed as dynamic)();
    await tester.pumpAndSettle();

    final submitted = service.submittedJob;
    expect(submitted, isNotNull);
    expect(submitted!.capability, AICapability.imageToImage);
    expect(
      submitted.creativeParams?.sourceImageBase64,
      base64Encode(attachmentBytes),
    );
    expect(submitted.creativeParams?.sourceImageUrl, isNull);
    expect(submitted.creativeParams?.sourceImageMimeType, 'image/png');
    expect(submitted.sourceNodeIds, isEmpty);
    expect(container.read(documentNodesProvider), hasLength(2));
  });

  testWidgets('removing an attachment restores the selected canvas source', (
    tester,
  ) async {
    const sourceId = 'canvas-source-after-remove';
    const attachmentBytes = _minimalPngBytes;
    final service = _RecordingAIService();
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(),
        ),
        aiServiceProvider.overrideWithValue(service),
        imageArtifactStoreProvider.overrideWithValue(
          MemoryImageArtifactStore(),
        ),
        aiImageAttachmentPickerProvider.overrideWithValue(
          () async => AssetPickerResult(
            name: 'temporary.png',
            bytes: Uint8List.fromList(attachmentBytes),
            extension: 'png',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(documentNodesProvider.notifier)
        .addNode(
          CanvasNode(
            id: sourceId,
            type: NodeType.image,
            x: 20,
            y: 30,
            width: 120,
            height: 100,
            payload: ImagePayload(url: 'https://cdn.example.test/canvas.png'),
          ),
        );
    container.read(selectionProvider.notifier).select(sourceId);
    container.read(aiCreativeEngineProvider.notifier)
      ..setCapability(AICapability.imageToImage)
      ..setPrompt('Use the canvas image.');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: 'remove-source-test')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add or choose output'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload image'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('temporary.png'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();
    expect(find.text('temporary.png'), findsNothing);
    expect(find.byKey(const ValueKey('ai-canvas-source-chip')), findsOneWidget);

    final generateButton = find.ancestor(
      of: find.text('Generate'),
      matching: find.byType(UiButton),
    );
    final onPressed = tester.widget<UiButton>(generateButton).onPressed!;
    await (onPressed as dynamic)();
    await tester.pumpAndSettle();

    expect(service.submittedJob?.creativeParams?.sourceImageBase64, isNull);
    expect(
      service.submittedJob?.creativeParams?.sourceImageUrl,
      'https://cdn.example.test/canvas.png',
    );
    expect(service.submittedJob?.sourceNodeIds, [sourceId]);
  });

  testWidgets('text-to-3D image-only worker warns without image provider', (
    tester,
  ) async {
    const config = BackendConfig(
      threeDEnabled: true,
      threeDProvider: 'triposr',
    );
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(config),
        ),
        aiServiceProvider.overrideWithValue(_RecordingAIService()),
        imageArtifactStoreProvider.overrideWithValue(
          MemoryImageArtifactStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(aiCreativeEngineProvider.notifier)
      ..setCapability(AICapability.textTo3D)
      ..setThreeDProvider('triposr');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: 'triposr-requirement-test')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Configure a 3D worker/provider and an image-generation provider for text-to-3D.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('3D target follows whether a canvas image is selected', (
    tester,
  ) async {
    const sourceId = '3d-target-source';
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(),
        ),
        aiServiceProvider.overrideWithValue(_RecordingAIService()),
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
            id: sourceId,
            type: NodeType.image,
            x: 10,
            y: 20,
            width: 100,
            height: 80,
            payload: ImagePayload(url: 'https://cdn.example.test/model.png'),
          ),
        );
    container.read(selectionProvider.notifier).select(sourceId);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: '3d-target-test')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add or choose output'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create 3D model'));
    await tester.pumpAndSettle();

    expect(
      container.read(aiCreativeEngineProvider).activeCapability,
      AICapability.imageTo3D,
    );
    await tester.tap(find.byTooltip('Show options'));
    await tester.pumpAndSettle();
    expect(find.text('MESH QUALITY'), findsOneWidget);
  });

  testWidgets('uploading an image switches text-to-3D to image-to-3D', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(),
        ),
        aiServiceProvider.overrideWithValue(_RecordingAIService()),
        imageArtifactStoreProvider.overrideWithValue(
          MemoryImageArtifactStore(),
        ),
        aiImageAttachmentPickerProvider.overrideWithValue(
          () async => AssetPickerResult(
            name: 'model-reference.png',
            bytes: Uint8List.fromList(_minimalPngBytes),
            extension: 'png',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(aiCreativeEngineProvider.notifier)
        .setCapability(AICapability.textTo3D);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: '3d-upload-test')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add or choose output'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload image'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(
      container.read(aiCreativeEngineProvider).activeCapability,
      AICapability.imageTo3D,
    );
    expect(find.text('model-reference.png'), findsOneWidget);
  });

  testWidgets('video target selects image-to-video capability', (tester) async {
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(),
        ),
        aiServiceProvider.overrideWithValue(_RecordingAIService()),
        imageArtifactStoreProvider.overrideWithValue(
          MemoryImageArtifactStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: 'video-target-test')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add or choose output'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create video'));
    await tester.pumpAndSettle();

    expect(
      container.read(aiCreativeEngineProvider).activeCapability,
      AICapability.imageToVideo,
    );
    await tester.tap(find.byTooltip('Show options'));
    await tester.pumpAndSettle();
    expect(find.text('CAMERA MOTION TRAJECTORY'), findsOneWidget);
  });

  testWidgets('text-to-image submits a prompt without an image source', (
    tester,
  ) async {
    final service = _RecordingAIService();
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(),
        ),
        aiServiceProvider.overrideWithValue(service),
        imageArtifactStoreProvider.overrideWithValue(
          MemoryImageArtifactStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(aiCreativeEngineProvider.notifier)
      ..setCapability(AICapability.textToImage)
      ..setPrompt('A modern house beside a lake.');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: 'text-only-image-test')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-composer-send')));
    await tester.pumpAndSettle();

    expect(service.submittedJob?.capability, AICapability.textToImage);
    expect(service.submittedJob?.prompt, 'A modern house beside a lake.');
    expect(service.submittedJob?.creativeParams?.sourceImageBase64, isNull);
    expect(service.submittedJob?.creativeParams?.sourceImageUrl, isNull);
  });

  testWidgets('image edit without attachment or selection is blocked', (
    tester,
  ) async {
    final service = _RecordingAIService();
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(),
        ),
        aiServiceProvider.overrideWithValue(service),
        imageArtifactStoreProvider.overrideWithValue(
          MemoryImageArtifactStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(aiCreativeEngineProvider.notifier)
      ..setCapability(AICapability.imageToImage)
      ..setPrompt('Edit an image.');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: 'missing-source-test')),
      ),
    );
    await tester.pumpAndSettle();
    final generateButton = find.ancestor(
      of: find.text('Generate'),
      matching: find.byType(UiButton),
    );
    final onPressed = tester.widget<UiButton>(generateButton).onPressed!;
    await (onPressed as dynamic)();
    await tester.pumpAndSettle();

    expect(service.submittedJob, isNull);
    expect(find.text('Add an image or select one on canvas'), findsOneWidget);
  });

  testWidgets('composer exposes supported targets without category tabs', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(),
        ),
        aiServiceProvider.overrideWithValue(_RecordingAIService()),
        imageArtifactStoreProvider.overrideWithValue(
          MemoryImageArtifactStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: 'composer-targets-test')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add or choose output'), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);
    expect(find.text('Edit & Inpaint'), findsNothing);
    expect(find.text('SUB-ENGINE OPERATION'), findsNothing);
    expect(find.text('ADVANCED OPERATION'), findsNothing);

    await tester.tap(find.byTooltip('Show options'));
    await tester.pumpAndSettle();
    expect(find.text('STYLE PRESET'), findsOneWidget);
    expect(find.text('ADVANCED OPERATION'), findsOneWidget);
    expect(find.text('SUB-ENGINE OPERATION'), findsNothing);

    await tester.tap(find.byTooltip('Hide options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-generation-target')));
    await tester.pumpAndSettle();
    expect(find.text('Create image'), findsOneWidget);
    expect(find.text('Edit image'), findsOneWidget);
    expect(find.text('Create video'), findsOneWidget);
    expect(find.text('Create 3D model'), findsOneWidget);
    expect(find.text('Ask about canvas'), findsOneWidget);
  });
  testWidgets('uses the tokenized AI panel shell', (tester) async {
    final container = ProviderContainer(
      overrides: [
        backendConfigProvider.overrideWith(
          (_) => _ReadyBackendConfigNotifier(),
        ),
        aiServiceProvider.overrideWithValue(_RecordingAIService()),
        imageArtifactStoreProvider.overrideWithValue(
          MemoryImageArtifactStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const AIPanel(projectId: 'panel-shell-test')),
      ),
    );
    final panelShell = find.byKey(const ValueKey('ai-panel-shell'));
    expect(panelShell, findsOneWidget);
    final panelContent = find.descendant(
      of: panelShell,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox && widget.constraints.maxWidth == 360,
      ),
    );
    expect(panelContent, findsOneWidget);
    expect(tester.getSize(panelContent).width, lessThanOrEqualTo(360));
    expect(find.text('AI CREATIVE ENGINE'), findsOneWidget);
    final header = tester.widget<Container>(
      find.byKey(const ValueKey('ai-panel-header')),
    );
    expect(
      ((header.decoration! as BoxDecoration).border! as Border).bottom.width,
      AppBorder.thin,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'composer controls remain reachable on a narrow large-text panel',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          backendConfigProvider.overrideWith(
            (_) => _ReadyBackendConfigNotifier(),
          ),
          aiServiceProvider.overrideWithValue(_RecordingAIService()),
          imageArtifactStoreProvider.overrideWithValue(
            MemoryImageArtifactStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(
            MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 480),
                devicePixelRatio: 1,
                textScaler: TextScaler.linear(2),
              ),
              child: const AIPanel(projectId: 'compact-large-text-test'),
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Open AI backend settings: SIMULATION MODE'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final finder in [
        find.byKey(const ValueKey('ai-generation-target')),
        find.byKey(const ValueKey('ai-composer-send')),
      ]) {
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();

        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(viewport.width));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(viewport.height));
        expect(tester.takeException(), isNull);
      }
    },
  );
}

class _ReadyBackendConfigNotifier extends BackendConfigNotifier {
  _ReadyBackendConfigNotifier([BackendConfig config = const BackendConfig()]) {
    state = config;
  }

  @override
  Future<void> loadConfig() async {}
}

class _RecordingAIService extends AIService {
  _RecordingAIService()
    : super(
        const BackendConfig(),
        null,
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
      );

  AIJob? submittedJob;

  @override
  Future<AIJob> executeJob(AIJob job, List<CanvasNode> currentNodes) async {
    submittedJob = job;
    return job.copyWith(
      status: AIJobStatus.completed,
      resultArtifact: const AIArtifact(
        kind: AIArtifactKind.image,
        reference: 'varian-image://panel-fixture',
        mimeType: 'image/png',
        byteLength: 128,
      ),
      updatedAt: DateTime.utc(2026),
    );
  }
}
