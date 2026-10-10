export 'model3d_artifact_store_types.dart';

import 'model3d_artifact_store_types.dart';
import 'model3d_artifact_store_web.dart'
    if (dart.library.io) 'model3d_artifact_store_io.dart'
    as platform;

Model3DArtifactStore createModel3DArtifactStore() =>
    platform.createPlatformModel3DArtifactStore();

Future<Model3DArtifact?> hydrateModel3DArtifact(String reference) =>
    platform.hydratePlatformModel3DArtifact(reference);

Future<bool> isAllowedModel3DArtifactPath(String path) =>
    platform.isPlatformModel3DArtifactPathAllowed(path);

Future<void> disposeHydratedModel3DArtifact(Model3DArtifact artifact) =>
    platform.disposePlatformHydratedModel3DArtifact(artifact);
