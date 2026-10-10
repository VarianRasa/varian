import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ai/data/image_artifact_store.dart';
import '../../features/ai/data/video_artifact_store.dart';
import '../../features/assets/data/file_artifact_store.dart';
import '../../features/media/data/media_artifact_store.dart';
import '../../features/model3d/data/model3d_artifact_store.dart';

/// Application-owned artifact stores shared by producers and runtime hydrators.
///
/// The bundle owns store identity, not the individual widgets that consume it.
/// Releasing a hydrated object URL remains the responsibility of the consumer;
/// durable artifact bytes are never removed by this bundle.
class ArtifactStoreBundle {
  ArtifactStoreBundle({
    ImageArtifactStore? imageArtifactStore,
    FileArtifactStore? fileArtifactStore,
    MediaArtifactStore? mediaArtifactStore,
    VideoArtifactStore? videoArtifactStore,
    Model3DArtifactStore? model3DArtifactStore,
  }) : imageArtifactStore = imageArtifactStore ?? createImageArtifactStore(),
       fileArtifactStore = fileArtifactStore ?? createFileArtifactStore(),
       mediaArtifactStore = mediaArtifactStore ?? createMediaArtifactStore(),
       videoArtifactStore = videoArtifactStore ?? createVideoArtifactStore(),
       model3DArtifactStore =
           model3DArtifactStore ?? createModel3DArtifactStore();

  final ImageArtifactStore imageArtifactStore;
  final FileArtifactStore fileArtifactStore;
  final MediaArtifactStore mediaArtifactStore;
  final VideoArtifactStore videoArtifactStore;
  final Model3DArtifactStore model3DArtifactStore;
}

/// One non-auto-disposed bundle for the application/container lifetime.
final artifactStoreBundleProvider = Provider<ArtifactStoreBundle>((ref) {
  return ArtifactStoreBundle();
});
