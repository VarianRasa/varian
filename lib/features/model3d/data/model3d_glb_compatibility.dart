import 'dart:convert';
import 'dart:typed_data';

/// Converts integer KHR_texture_transform values to doubles before passing a
/// GLB to the current three_js loader.
///
/// The loader currently casts offset and scale entries with `as double`, but
/// valid JSON may decode whole-number values as Dart ints. Rebuild only the
/// JSON chunk when such values are present and preserve every binary chunk.
Uint8List normalizeModel3DGlbForThreeJs(Uint8List bytes) {
  if (bytes.length < 20) return bytes;

  final header = ByteData.sublistView(bytes);
  final jsonLength = header.getUint32(12, Endian.little);
  final jsonType = header.getUint32(16, Endian.little);
  if (header.getUint32(0, Endian.little) != 0x46546C67 ||
      header.getUint32(4, Endian.little) != 2 ||
      header.getUint32(8, Endian.little) != bytes.length ||
      jsonType != 0x4E4F534A ||
      jsonLength == 0 ||
      20 + jsonLength > bytes.length) {
    return bytes;
  }

  final String jsonText;
  try {
    jsonText = utf8.decode(bytes.sublist(20, 20 + jsonLength)).trim();
  } catch (_) {
    return bytes;
  }
  if (!jsonText.contains('"KHR_texture_transform"')) return bytes;

  dynamic document;
  try {
    document = jsonDecode(jsonText);
  } catch (_) {
    return bytes;
  }
  if (document is! Map || !_normalizeTextureTransforms(document)) {
    return bytes;
  }

  final encodedJson = Uint8List.fromList(utf8.encode(jsonEncode(document)));
  final paddedJsonLength = (encodedJson.length + 3) & ~3;
  final binaryOffset = 20 + jsonLength;
  final binaryLength = bytes.length - binaryOffset;
  final output = Uint8List(12 + 8 + paddedJsonLength + binaryLength);
  ByteData.sublistView(output)
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, output.length, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  output.setRange(20, 20 + encodedJson.length, encodedJson);
  for (
    var index = 20 + encodedJson.length;
    index < 20 + paddedJsonLength;
    index++
  ) {
    output[index] = 0x20;
  }
  output.setRange(20 + paddedJsonLength, output.length, bytes, binaryOffset);
  return output;
}

bool _normalizeTextureTransforms(dynamic value) {
  var changed = false;
  if (value is Map) {
    final extensions = value['extensions'];
    final transform = extensions is Map
        ? extensions['KHR_texture_transform']
        : null;
    if (transform is Map) {
      changed = _normalizeNumberList(transform, 'offset') || changed;
      changed = _normalizeNumberList(transform, 'scale') || changed;
      final rotation = transform['rotation'];
      if (rotation is num && rotation is! double) {
        transform['rotation'] = rotation.toDouble();
        changed = true;
      }
    }
    for (final child in value.values) {
      changed = _normalizeTextureTransforms(child) || changed;
    }
  } else if (value is List) {
    for (final child in value) {
      changed = _normalizeTextureTransforms(child) || changed;
    }
  }
  return changed;
}

bool _normalizeNumberList(Map transform, String key) {
  final values = transform[key];
  if (values is! List) return false;

  var changed = false;
  final normalized = values.map((value) {
    if (value is num && value is! double) {
      changed = true;
      return value.toDouble();
    }
    return value;
  }).toList();
  if (changed) transform[key] = normalized;
  return changed;
}
