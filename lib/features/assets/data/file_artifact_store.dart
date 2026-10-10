export 'file_artifact_store_types.dart';

import 'file_artifact_store_types.dart';
import 'file_artifact_store_web.dart'
    if (dart.library.io) 'file_artifact_store_io.dart'
    as platform;

FileArtifactStore createFileArtifactStore() =>
    platform.createPlatformFileArtifactStore();
