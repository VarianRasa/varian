import 'dart:typed_data';

Future<Uint8List?> createPlatformVideoFrameThumbnail({
  required String sourceKey,
  Uint8List? sourceBytes,
  String? sourceFileName,
  int positionMs = 0,
  int maxDimension = 320,
}) async => null;

const supportsPlatformVideoFrameThumbnail = false;
