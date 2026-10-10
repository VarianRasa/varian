export 'image_artifact_store_types.dart';

import 'image_artifact_store_types.dart';
import 'image_artifact_store_web.dart'
    if (dart.library.io) 'image_artifact_store_io.dart'
    as platform;

ImageArtifactStore createImageArtifactStore() =>
    platform.createPlatformImageArtifactStore();

Future<ImageArtifact?> hydrateImageArtifact(String reference) =>
    platform.hydratePlatformImageArtifact(reference);

Future<void> disposeHydratedImageArtifact(ImageArtifact artifact) =>
    platform.disposePlatformHydratedImageArtifact(artifact);
