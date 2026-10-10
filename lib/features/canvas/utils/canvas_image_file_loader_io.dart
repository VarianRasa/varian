import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readCanvasImageFileBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  return bytes.isEmpty ? null : bytes;
}
