import 'dart:typed_data';

import 'canvas_image_file_loader_stub.dart'
    if (dart.library.io) 'canvas_image_file_loader_io.dart'
    as implementation;

Future<Uint8List?> readCanvasImageFileBytes(String path) =>
    implementation.readCanvasImageFileBytes(path);
