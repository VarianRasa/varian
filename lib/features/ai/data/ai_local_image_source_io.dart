import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readLocalAIImageBytes(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  return file.readAsBytes();
}
