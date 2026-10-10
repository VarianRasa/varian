export 'video_artifact_store_types.dart';

import 'video_artifact_store_types.dart';
import 'video_artifact_store_web.dart'
    if (dart.library.io) 'video_artifact_store_io.dart'
    as platform;

VideoArtifactStore createVideoArtifactStore() =>
    platform.createPlatformVideoArtifactStore();

Future<VideoArtifact?> hydrateVideoArtifact(String reference) =>
    platform.hydratePlatformVideoArtifact(reference);

Future<void> disposeHydratedVideoArtifact(VideoArtifact artifact) =>
    platform.disposePlatformHydratedVideoArtifact(artifact);
