import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/artifacts/artifact_store_bundle.dart';
import '../data/media_processing_checkpoint_store.dart';
import '../data/media_processing_worker.dart';

final mediaProcessingCoordinatorProvider = Provider<MediaProcessingCoordinator>(
  (ref) {
    final artifactStores = ref.watch(artifactStoreBundleProvider);
    final coordinator = MediaProcessingCoordinator(
      artifactStore: artifactStores.mediaArtifactStore,
      mediaArtifactStore: artifactStores.mediaArtifactStore,
      videoArtifactStore: artifactStores.videoArtifactStore,
      checkpointStore: SharedPreferencesMediaProcessingCheckpointStore(),
    );
    ref.onDispose(coordinator.dispose);
    return coordinator;
  },
);
