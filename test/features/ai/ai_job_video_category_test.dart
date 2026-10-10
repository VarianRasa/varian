import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/features/ai/state/ai_provider.dart';
import 'package:varian/features/ai/presentation/ai_panel.dart';

void main() {
  final now = DateTime(2026, 8, 24);

  AIJob jobFor(AICapability capability) => AIJob(
    id: 'job1',
    projectId: 'project1',
    capability: capability,
    prompt: 'test prompt',
    createdAt: now,
    updatedAt: now,
  );

  test('maps image and video capabilities to their creative categories', () {
    expect(
      jobFor(AICapability.imageToVideo).category,
      AICreativeCategory.videoAI,
    );
    expect(
      jobFor(AICapability.textToImage).category,
      AICreativeCategory.generation,
    );
    expect(
      jobFor(AICapability.videoFromImage).category,
      AICreativeCategory.videoAI,
    );
  });

  test('scopes image-to-video to the Video AI category', () {
    expect(
      aiCapabilitiesForCategory(AICreativeCategory.generation),
      isNot(contains(AICapability.imageToVideo)),
    );
    expect(aiCapabilitiesForCategory(AICreativeCategory.videoAI), [
      AICapability.imageToVideo,
    ]);
  });

  test('panel exposes only implemented capability groups', () {
    expect(
      aiCapabilitiesForCategory(AICreativeCategory.generation),
      isNot(contains(AICapability.imageToVideo)),
    );
    expect(aiCapabilitiesForCategory(AICreativeCategory.enhancement), isEmpty);
    expect(aiCapabilitiesForCategory(AICreativeCategory.aiAssistant), [
      AICapability.understandCanvas,
      AICapability.understandSelection,
    ]);
    expect(
      aiCapabilitiesForCategory(AICreativeCategory.compositionAI),
      containsAll(const [
        AICapability.populate,
        AICapability.compositionRemove,
        AICapability.rearrange,
        AICapability.expandScene,
        AICapability.smartCutout,
      ]),
    );
  });

  test('selects image-to-video when opening the video AI category', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(aiCreativeEngineProvider.notifier)
        .setCategory(AICreativeCategory.videoAI);

    expect(
      container.read(aiCreativeEngineProvider).activeCapability,
      AICapability.imageToVideo,
    );
  });
}
