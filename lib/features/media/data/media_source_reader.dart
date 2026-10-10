import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'media_artifact_store.dart';

import 'media_source_reader_web.dart'
    if (dart.library.io) 'media_source_reader_io.dart'
    as platform;

Future<Uint8List?> readMediaSourceBytes(
  String sourceKey, {
  int maxBytes = maxMediaSourceBytes,
  http.Client? httpClient,
  VideoArtifactStore? videoArtifactStore,
  MediaArtifactStore? mediaArtifactStore,
}) => platform.readPlatformMediaSourceBytes(
  sourceKey,
  maxBytes: maxBytes,
  httpClient: httpClient,
  videoArtifactStore: videoArtifactStore,
  mediaArtifactStore: mediaArtifactStore,
);

const maxMediaSourceBytes = 512 * 1024 * 1024;
