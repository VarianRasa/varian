import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/features/ai/data/image_artifact_store.dart';
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store_types.dart';

void main() {
  test('provider keeps one bundle and one store instance per container', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.read(artifactStoreBundleProvider);
    final second = container.read(artifactStoreBundleProvider);

    expect(identical(first, second), isTrue);
    expect(
      identical(first.imageArtifactStore, second.imageArtifactStore),
      isTrue,
    );
    expect(
      identical(first.fileArtifactStore, second.fileArtifactStore),
      isTrue,
    );
    expect(
      identical(first.mediaArtifactStore, second.mediaArtifactStore),
      isTrue,
    );
    expect(
      identical(first.videoArtifactStore, second.videoArtifactStore),
      isTrue,
    );
    expect(
      identical(first.model3DArtifactStore, second.model3DArtifactStore),
      isTrue,
    );
  });

  test('production seams can override the complete bundle', () {
    final bundle = ArtifactStoreBundle(
      imageArtifactStore: MemoryImageArtifactStore(),
      fileArtifactStore: MemoryFileArtifactStore(),
      mediaArtifactStore: MemoryMediaArtifactStore(),
      videoArtifactStore: MemoryVideoArtifactStore(),
      model3DArtifactStore: MemoryModel3DArtifactStore(),
    );
    final container = ProviderContainer(
      overrides: [artifactStoreBundleProvider.overrideWithValue(bundle)],
    );
    addTearDown(container.dispose);

    expect(container.read(artifactStoreBundleProvider), same(bundle));
  });
}
