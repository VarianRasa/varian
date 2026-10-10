import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

export 'canvas_file_source_stub.dart'
    if (dart.library.io) 'canvas_file_source_io.dart';

export 'package:cross_file/cross_file.dart' show XFile;

/// Reads a byte stream without allowing an unbounded allocation.
///
/// A stream is rejected as soon as its byte count exceeds [maxBytes]. The
/// returned bytes are transient and must be materialized through an owned
/// artifact store before they cross a durable boundary.
Future<Uint8List?> readCanvasByteStreamBytes(
  Stream<List<int>> chunks, {
  required int maxBytes,
}) async {
  if (maxBytes <= 0) return null;

  final builder = BytesBuilder(copy: false);
  var total = 0;
  try {
    await for (final chunk in chunks) {
      if (chunk.isEmpty) continue;
      total += chunk.length;
      if (total > maxBytes) return null;
      builder.add(chunk);
    }
  } catch (_) {
    return null;
  }
  if (total == 0) return null;
  return builder.takeBytes();
}

/// Reads a picked file without allowing an unbounded allocation.
Future<Uint8List?> readCanvasXFileBytes(XFile file, {required int maxBytes}) =>
    readCanvasByteStreamBytes(file.openRead(), maxBytes: maxBytes);
