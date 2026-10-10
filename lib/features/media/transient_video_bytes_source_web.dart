import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<TransientVideoByteSource?> materializeTransientVideoBytes(
  Uint8List bytes, {
  required String mimeType,
}) async {
  if (bytes.isEmpty) return null;
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  var disposed = false;
  return TransientVideoByteSource(
    url,
    disposeCallback: () async {
      if (disposed) return;
      disposed = true;
      web.URL.revokeObjectURL(url);
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
