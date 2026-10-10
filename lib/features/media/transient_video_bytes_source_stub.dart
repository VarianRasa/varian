import 'dart:typed_data';

Future<TransientVideoByteSource?> materializeTransientVideoBytes(
  Uint8List bytes, {
  required String mimeType,
}) async => null;

class TransientVideoByteSource {
  final String source;
  final Future<void> Function()? disposeCallback;

  const TransientVideoByteSource(this.source, {this.disposeCallback});

  Future<void> dispose() async {
    await disposeCallback?.call();
  }
}
