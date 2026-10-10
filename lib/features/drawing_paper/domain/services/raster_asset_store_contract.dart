import 'dart:typed_data';

abstract interface class RasterAssetStore {
  Future<void> write(String reference, Uint8List bytes);
  Future<Uint8List?> read(String reference);
  Future<bool> contains(String reference);
  Future<void> delete(String reference);
}
