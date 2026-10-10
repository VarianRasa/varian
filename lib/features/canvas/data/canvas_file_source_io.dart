import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

Future<Uint8List?> readCanvasFileBytes(
  String path, {
  int maxBytes = 512 * 1024 * 1024,
}) async {
  if (maxBytes <= 0) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  try {
    return await _readCanvasByteStreamBytes(
      file.openRead(),
      maxBytes: maxBytes,
    );
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _readCanvasByteStreamBytes(
  Stream<List<int>> chunks, {
  required int maxBytes,
}) async {
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

String? writeCanvasCroppedImage(Uint8List bytes) {
  final file = File(
    p.join(
      Directory.systemTemp.path,
      'cropped_${DateTime.now().millisecondsSinceEpoch}.png',
    ),
  );
  file.writeAsBytesSync(bytes, flush: true);
  return file.path;
}
