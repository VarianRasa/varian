import 'dart:typed_data';

import 'video_frame_thumbnailer_stub.dart'
    if (dart.library.io) 'video_frame_thumbnailer_io.dart'
    as platform;

Future<Uint8List?> createVideoFrameThumbnail({
  required String sourceKey,
  Uint8List? sourceBytes,
  String? sourceFileName,
  int positionMs = 0,
  int maxDimension = 320,
}) => platform.createPlatformVideoFrameThumbnail(
  sourceKey: sourceKey,
  sourceBytes: sourceBytes,
  sourceFileName: sourceFileName,
  positionMs: positionMs,
  maxDimension: maxDimension,
);

bool get supportsVideoFrameThumbnail =>
    platform.supportsPlatformVideoFrameThumbnail;
