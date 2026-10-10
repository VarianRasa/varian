import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readLocalPreviewBytes(String path, {int? maxBytes}) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  if (maxBytes == null) return file.readAsBytesSync();

  final handle = file.openSync();
  try {
    return handle.readSync(maxBytes);
  } finally {
    handle.closeSync();
  }
}
