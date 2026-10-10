import 'dart:typed_data';

const maxModel3DBytes = 100 * 1024 * 1024;

class Model3DValidationException implements Exception {
  final String message;

  const Model3DValidationException(this.message);

  @override
  String toString() => message;
}

bool isValidGlbBytes(Uint8List bytes) {
  if (bytes.length < 20 || bytes.length > maxModel3DBytes) return false;
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(0, Endian.little) != 0x46546C67) return false;
  if (header.getUint32(4, Endian.little) != 2) return false;
  if (header.getUint32(8, Endian.little) != bytes.length) return false;
  final jsonChunkLength = header.getUint32(12, Endian.little);
  final jsonChunkType = header.getUint32(16, Endian.little);
  return jsonChunkType == 0x4E4F534A &&
      jsonChunkLength > 0 &&
      20 + jsonChunkLength <= bytes.length;
}

void validateGlbBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const Model3DValidationException('GLB file is empty.');
  }
  if (bytes.length > maxModel3DBytes) {
    throw const Model3DValidationException(
      'GLB file is too large. Maximum size is 100 MB.',
    );
  }
  if (bytes.length < 20) {
    throw const Model3DValidationException('GLB file header is incomplete.');
  }
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(0, Endian.little) != 0x46546C67) {
    throw const Model3DValidationException('File is not a valid GLB model.');
  }
  if (header.getUint32(4, Endian.little) != 2) {
    throw const Model3DValidationException('Only GLB version 2 is supported.');
  }
  if (header.getUint32(8, Endian.little) != bytes.length) {
    throw const Model3DValidationException('GLB file length is invalid.');
  }
  if (header.getUint32(12, Endian.little) <= 0 ||
      header.getUint32(16, Endian.little) != 0x4E4F534A ||
      20 + header.getUint32(12, Endian.little) > bytes.length) {
    throw const Model3DValidationException('GLB JSON chunk is invalid.');
  }
}

String sanitizeModel3DFileName(String value) {
  final base = value
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[<>:"|?*\u0000-\u001F]'), '_')
      .trim();
  final withoutExtension = base.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final safeBase = withoutExtension
      .trim()
      .replaceFirst(RegExp(r'^\.+'), '')
      .trim();
  final name = safeBase.isEmpty ? 'model' : safeBase;
  final bounded = name.substring(0, name.length > 120 ? 120 : name.length);
  return '$bounded.glb';
}
