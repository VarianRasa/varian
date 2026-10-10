import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/media/data/media_processing_isolate_runner.dart';

void main() {
  test(
    'cancellable isolate worker exits before starting when cancelled',
    () async {
      const runner = MediaProcessingIsolateRunner();
      final result = await runner.rasterizeImage(
        Uint8List.fromList([1, 2, 3]),
        maxDimension: 64,
        outputFormat: 'png',
        isCancelled: () => true,
      );
      expect(result, isNull);
    },
  );

  test('cancellable isolate worker returns a valid waveform', () async {
    const runner = MediaProcessingIsolateRunner();
    final result = await runner.decodeWaveform(
      _wavPcm16(),
      sampleCount: 16,
      isCancelled: () => false,
    );
    expect(result, hasLength(8));
  });
}

Uint8List _wavPcm16() {
  const samples = [0, 8_000, 16_000, 24_000, 32_000, 24_000, 16_000, 8_000];
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);
  final raw = bytes.buffer.asUint8List();
  raw.setRange(0, 4, [0x52, 0x49, 0x46, 0x46]);
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  raw.setRange(8, 12, [0x57, 0x41, 0x56, 0x45]);
  raw.setRange(12, 16, [0x66, 0x6d, 0x74, 0x20]);
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 8_000, Endian.little);
  bytes.setUint32(28, 16_000, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  raw.setRange(36, 40, [0x64, 0x61, 0x74, 0x61]);
  bytes.setUint32(40, dataSize, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    bytes.setInt16(44 + index * 2, samples[index], Endian.little);
  }
  return raw;
}
