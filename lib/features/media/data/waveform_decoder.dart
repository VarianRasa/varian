import 'dart:math' as math;
import 'dart:typed_data';

List<double>? decodePcmWaveform(
  Uint8List bytes, {
  required int sampleCount,
  void Function()? onBucket,
}) {
  final format = _readWaveFormat(bytes);
  if (format == null || format.dataSize <= 0) return null;
  final frameBytes = format.channels * format.bytesPerSample;
  if (frameBytes <= 0) return null;
  final frames = format.dataSize ~/ frameBytes;
  if (frames <= 0) return null;

  final requested = sampleCount.clamp(16, 2048).toInt();
  final count = math.min(requested, frames);
  final data = ByteData.sublistView(bytes);
  final values = <double>[];
  for (var bucket = 0; bucket < count; bucket++) {
    onBucket?.call();
    final start = bucket * frames ~/ count;
    final end = math.max(start + 1, (bucket + 1) * frames ~/ count);
    var peak = 0.0;
    for (var frame = start; frame < end && frame < frames; frame++) {
      final frameOffset = format.dataOffset + frame * frameBytes;
      for (var channel = 0; channel < format.channels; channel++) {
        final offset = frameOffset + channel * format.bytesPerSample;
        final amplitude = _sampleAmplitude(bytes, data, offset, format);
        if (amplitude > peak) peak = amplitude;
      }
    }
    values.add(peak.clamp(0.0, 1.0).toDouble());
  }
  return values;
}

_WaveFormat? _readWaveFormat(Uint8List bytes) {
  if (bytes.length < 12 || _ascii(bytes, 0, 4) != 'RIFF') return null;
  if (_ascii(bytes, 8, 4) != 'WAVE') return null;

  var cursor = 12;
  var audioFormat = 0;
  var channels = 0;
  var bitsPerSample = 0;
  var dataOffset = -1;
  var dataSize = 0;
  while (cursor + 8 <= bytes.length) {
    final chunkId = _ascii(bytes, cursor, 4);
    final chunkSize = _u32(bytes, cursor + 4);
    final payloadStart = cursor + 8;
    final payloadEnd = payloadStart + chunkSize;
    if (payloadEnd > bytes.length) return null;
    if (chunkId == 'fmt ' && chunkSize >= 16) {
      audioFormat = _u16(bytes, payloadStart);
      channels = _u16(bytes, payloadStart + 2);
      bitsPerSample = _u16(bytes, payloadStart + 14);
    } else if (chunkId == 'data') {
      dataOffset = payloadStart;
      dataSize = chunkSize;
    }
    cursor = payloadEnd + (chunkSize.isOdd ? 1 : 0);
  }

  final bytesPerSample = (bitsPerSample + 7) ~/ 8;
  final supportedFormat = audioFormat == 1 || audioFormat == 3;
  final supportedBits = audioFormat == 3
      ? bitsPerSample == 32
      : bitsPerSample == 8 ||
            bitsPerSample == 16 ||
            bitsPerSample == 24 ||
            bitsPerSample == 32;
  if (!supportedFormat || !supportedBits || channels <= 0 || dataOffset < 0) {
    return null;
  }
  return _WaveFormat(
    audioFormat: audioFormat,
    channels: channels,
    bitsPerSample: bitsPerSample,
    bytesPerSample: bytesPerSample,
    dataOffset: dataOffset,
    dataSize: dataSize,
  );
}

double _sampleAmplitude(
  Uint8List bytes,
  ByteData data,
  int offset,
  _WaveFormat format,
) {
  if (format.audioFormat == 3) {
    final value = data.getFloat32(offset, Endian.little);
    return value.isFinite ? value.abs() : 0.0;
  }
  switch (format.bitsPerSample) {
    case 8:
      return ((bytes[offset] - 128) / 128).abs();
    case 16:
      return (data.getInt16(offset, Endian.little) / 32768).abs();
    case 24:
      var value =
          bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
      if ((value & 0x800000) != 0) value -= 0x1000000;
      return (value / 8388608).abs();
    case 32:
      return (data.getInt32(offset, Endian.little) / 2147483648).abs();
    default:
      return 0.0;
  }
}

String _ascii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));

int _u16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

class _WaveFormat {
  final int audioFormat;
  final int channels;
  final int bitsPerSample;
  final int bytesPerSample;
  final int dataOffset;
  final int dataSize;

  const _WaveFormat({
    required this.audioFormat,
    required this.channels,
    required this.bitsPerSample,
    required this.bytesPerSample,
    required this.dataOffset,
    required this.dataSize,
  });
}
