import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

Future<TransientVideoByteSource?> materializeTransientVideoBytes(
  Uint8List bytes, {
  required String mimeType,
}) async {
  if (bytes.isEmpty) return null;
  final directory = await getTemporaryDirectory();
  final folder = Directory(p.join(directory.path, 'varian-transient-video'));
  await folder.create(recursive: true);
  final extension = switch (mimeType.toLowerCase()) {
    'video/webm' => 'webm',
    'video/quicktime' => 'mov',
    'application/vnd.apple.mpegurl' => 'm3u8',
    _ => 'mp4',
  };
  final file = File(p.join(folder.path, '${const Uuid().v4()}.$extension'));
  try {
    await file.writeAsBytes(bytes, flush: true);
  } catch (_) {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    rethrow;
  }
  var disposed = false;
  return TransientVideoByteSource(
    file.path,
    disposeCallback: () async {
      if (disposed) return;
      disposed = true;
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    },
  );
}

class TransientVideoByteSource {
  final String source;
  final Future<void> Function()? disposeCallback;

  const TransientVideoByteSource(this.source, {this.disposeCallback});

  Future<void> dispose() async {
    await disposeCallback?.call();
  }
}
