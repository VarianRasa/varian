import 'dart:typed_data';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:audio_decoder/audio_decoder_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:varian/features/media/data/media_processing_isolate_runner.dart';

void main() {
  test('decodes PCM waveform through the isolated runner', () async {
    const runner = MediaProcessingIsolateRunner();
    final waveform = await runner.decodeWaveform(
      _wavPcm16(samples: [0, 32767, -32768, 0]),
      sampleCount: 4,
    );

    expect(waveform, isNotNull);
    expect(waveform, hasLength(4));
    expect(
      waveform!.reduce((left, right) => left > right ? left : right),
      greaterThan(0.99),
    );
  });

  test(
    'resizes and encodes raster images through the isolated runner',
    () async {
      final source = image.Image(width: 8, height: 4);
      source.setPixelRgba(0, 0, 255, 32, 64, 255);
      const runner = MediaProcessingIsolateRunner();
      final encoded = await runner.rasterizeImage(
        Uint8List.fromList(image.encodePng(source)),
        maxDimension: 4,
        outputFormat: 'png',
      );

      expect(encoded, isNotNull);
      final decoded = image.decodeImage(encoded!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 4);
      expect(decoded.height, 2);
    },
  );

  test(
    'routes compressed waveform bytes through the platform decoder',
    () async {
      final original = AudioDecoderPlatform.instance;
      final fake = _FakeAudioDecoderPlatform();
      AudioDecoderPlatform.instance = fake;
      addTearDown(() => AudioDecoderPlatform.instance = original);

      const runner = MediaProcessingIsolateRunner(enabled: false);
      final waveform = await runner.decodeCompressedWaveform(
        Uint8List.fromList([0x49, 0x44, 0x33]),
        sampleCount: 4,
        formatHint: 'mp3',
      );

      expect(waveform, hasLength(16));
      expect(waveform!.first, 0.25);
      expect(waveform.last, 1.0);
      expect(waveform[10], closeTo(0.75, 0.001));
      expect(fake.inputData, [0x49, 0x44, 0x33]);
      expect(fake.formatHint, 'mp3');
      expect(fake.numberOfSamples, 16);
    },
  );

  test('returns null when the compressed decoder rejects the source', () async {
    final original = AudioDecoderPlatform.instance;
    AudioDecoderPlatform.instance = _FakeAudioDecoderPlatform(throws: true);
    addTearDown(() => AudioDecoderPlatform.instance = original);

    const runner = MediaProcessingIsolateRunner(enabled: false);
    final waveform = await runner.decodeCompressedWaveform(
      Uint8List.fromList([0xFF, 0xFB]),
      sampleCount: 96,
      formatHint: 'mp3',
    );

    expect(waveform, isNull);
  });

  test('routes trim and transcode through the codec backend', () async {
    final original = AudioDecoderPlatform.instance;
    final fake = _FakeAudioDecoderPlatform();
    AudioDecoderPlatform.instance = fake;
    addTearDown(() => AudioDecoderPlatform.instance = original);

    const runner = MediaProcessingIsolateRunner(enabled: false);
    final trimmed = await runner.trimAudio(
      Uint8List.fromList([1, 2, 3]),
      formatHint: 'mp3',
      startMs: 1_000,
      endMs: 2_500,
      outputFormat: 'wav',
    );
    final transcoded = await runner.transcodeAudio(
      Uint8List.fromList([4, 5, 6]),
      formatHint: 'mp3',
      outputFormat: 'm4a',
    );

    expect(trimmed, [0x52, 0x49, 0x46, 0x46]);
    expect(transcoded, [0x66, 0x74, 0x79, 0x70]);
    expect(fake.trimFormatHint, 'mp3');
    expect(fake.trimStart, const Duration(seconds: 1));
    expect(fake.trimEnd, const Duration(milliseconds: 2_500));
    expect(fake.trimOutputFormat, 'wav');
    expect(fake.transcodeFormatHint, 'mp3');
  });
}

final class _FakeAudioDecoderPlatform extends AudioDecoderPlatform {
  final bool throws;
  Uint8List? inputData;
  String? formatHint;
  int? numberOfSamples;
  String? trimFormatHint;
  Duration? trimStart;
  Duration? trimEnd;
  String? trimOutputFormat;
  String? transcodeFormatHint;

  _FakeAudioDecoderPlatform({this.throws = false});

  @override
  Future<List<double>> getWaveformBytes(
    Uint8List inputData,
    String formatHint,
    int numberOfSamples, {
    WaveformNormalization normalization = WaveformNormalization.perFile,
  }) async {
    if (throws) throw StateError('decoder unavailable');
    this.inputData = inputData;
    this.formatHint = formatHint;
    this.numberOfSamples = numberOfSamples;
    return const [0.25, 0.5, 0.75, 1.0];
  }

  @override
  Future<Uint8List> trimAudioBytes(
    Uint8List inputData,
    String formatHint,
    Duration start,
    Duration end, {
    String outputFormat = 'wav',
  }) async {
    trimFormatHint = formatHint;
    trimStart = start;
    trimEnd = end;
    trimOutputFormat = outputFormat;
    return Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);
  }

  @override
  Future<Uint8List> convertToM4aBytes(
    Uint8List inputData,
    String formatHint,
  ) async {
    transcodeFormatHint = formatHint;
    return Uint8List.fromList([0x66, 0x74, 0x79, 0x70]);
  }
}

Uint8List _wavPcm16({required List<int> samples}) {
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);
  final raw = bytes.buffer.asUint8List();
  raw.setRange(0, 4, [82, 73, 70, 70]);
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  raw.setRange(8, 12, [87, 65, 86, 69]);
  raw.setRange(12, 16, [102, 109, 116, 32]);
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 8000, Endian.little);
  bytes.setUint32(28, 16000, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  raw.setRange(36, 40, [100, 97, 116, 97]);
  bytes.setUint32(40, dataSize, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    bytes.setInt16(44 + index * 2, samples[index], Endian.little);
  }
  return raw;
}
