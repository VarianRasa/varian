/// Checks whether the leading bytes match a known MIME signature.
///
/// Unknown MIME types and empty payloads are not classified here. Callers that
/// accept a restricted set must validate that allowlist separately.
bool assetBytesMatchMimeSignature(List<int> bytes, String mimeType) {
  final normalizedMimeType = mimeType.trim().toLowerCase();
  if (bytes.isEmpty || normalizedMimeType == 'application/octet-stream') {
    return true;
  }
  bool startsWith(List<int> prefix, {int offset = 0}) {
    if (bytes.length < offset + prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[offset + index] != prefix[index]) return false;
    }
    return true;
  }

  bool containsAscii(String value) {
    final needle = value.codeUnits;
    final limit = bytes.length - needle.length;
    for (var start = 0; start <= limit && start < 1024; start++) {
      var matches = true;
      for (var index = 0; index < needle.length; index++) {
        final actual = bytes[start + index];
        final expected = needle[index];
        final lowerActual = actual >= 65 && actual <= 90 ? actual + 32 : actual;
        final lowerExpected = expected >= 65 && expected <= 90
            ? expected + 32
            : expected;
        if (lowerActual != lowerExpected) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  return switch (normalizedMimeType) {
    'image/png' => startsWith([137, 80, 78, 71, 13, 10, 26, 10]),
    'image/jpeg' => startsWith([255, 216, 255]),
    'image/gif' => startsWith('GIF'.codeUnits),
    'image/webp' =>
      startsWith('RIFF'.codeUnits) && startsWith('WEBP'.codeUnits, offset: 8),
    'image/bmp' => startsWith('BM'.codeUnits),
    'image/svg+xml' => containsAscii('<svg'),
    'application/pdf' => startsWith('%PDF-'.codeUnits),
    'application/zip' ||
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
    'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
      startsWith([80, 75, 3, 4]) || startsWith([80, 75, 5, 6]),
    'application/msword' ||
    'application/vnd.ms-excel' ||
    'application/vnd.ms-powerpoint' => startsWith([
      208,
      207,
      17,
      224,
      161,
      177,
      26,
      225,
    ]),
    'application/vnd.rar' =>
      startsWith([82, 97, 114, 33, 26, 7, 0]) ||
          startsWith([82, 97, 114, 33, 26, 7, 1, 0]),
    'application/x-7z-compressed' => startsWith([55, 122, 188, 175, 39, 28]),
    'application/gzip' => startsWith([31, 139]),
    'application/x-tar' => startsWith('ustar'.codeUnits, offset: 257),
    'application/json' ||
    'model/gltf+json' => containsAscii('{') || containsAscii('['),
    'application/xml' => containsAscii('<'),
    'model/gltf-binary' => startsWith('glTF'.codeUnits),
    'video/mp4' ||
    'video/quicktime' ||
    'audio/mp4' => startsWith('ftyp'.codeUnits, offset: 4),
    'video/x-msvideo' =>
      startsWith('RIFF'.codeUnits) && startsWith('AVI '.codeUnits, offset: 8),
    'video/x-matroska' || 'video/webm' => startsWith([26, 69, 223, 163]),
    'audio/wav' =>
      startsWith('RIFF'.codeUnits) && startsWith('WAVE'.codeUnits, offset: 8),
    'audio/mpeg' =>
      startsWith('ID3'.codeUnits) ||
          (bytes.length >= 2 && bytes[0] == 255 && (bytes[1] & 224) == 224),
    'audio/aac' =>
      bytes.length >= 2 && bytes[0] == 255 && (bytes[1] & 246) == 240,
    'audio/flac' => startsWith('fLaC'.codeUnits),
    'audio/ogg' => startsWith('OggS'.codeUnits),
    _ => true,
  };
}
