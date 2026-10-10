export 'media_artifact_store_types.dart';

import 'dart:typed_data';

import 'package:varian/domain/models/media_timeline.dart';

import 'media_artifact_store_types.dart';
import 'media_artifact_store_web.dart'
    if (dart.library.io) 'media_artifact_store_io.dart'
    as platform;

MediaArtifactStore createMediaArtifactStore() =>
    platform.createPlatformMediaArtifactStore();

Future<MediaArtifact?> hydrateMediaArtifact(
  String reference, {
  MediaArtifactKind? kind,
  String? mimeType,
  String? checksum,
  String? fileName,
}) => platform.hydratePlatformMediaArtifact(
  reference,
  kind: kind,
  mimeType: mimeType,
  checksum: checksum,
  fileName: fileName,
);

Future<Uint8List?> readMediaArtifactReference(String reference) =>
    platform.readPlatformMediaArtifactReference(reference);

Future<void> disposeHydratedMediaArtifact(MediaArtifact artifact) =>
    platform.disposePlatformHydratedMediaArtifact(artifact);
