import 'dart:typed_data';

bool isValidImageBytes(Uint8List bytes) {
  return _isPng(bytes) || _isJpeg(bytes) || _isWebP(bytes);
}

bool _isPng(Uint8List bytes) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  return bytes.length >= signature.length && _startsWith(bytes, signature);
}

bool _isJpeg(Uint8List bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255;
}

bool _isWebP(Uint8List bytes) {
  return bytes.length >= 12 &&
      _ascii(bytes, 0, 4) == 'RIFF' &&
      _ascii(bytes, 8, 4) == 'WEBP';
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

String _ascii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));

bool isValidMp4Bytes(Uint8List bytes) {
  if (bytes.length < 16) return false;
  final boxSize =
      (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  if (boxSize < 16 || boxSize > bytes.length) return false;
  return bytes[4] == 102 &&
      bytes[5] == 116 &&
      bytes[6] == 121 &&
      bytes[7] == 112;
}
