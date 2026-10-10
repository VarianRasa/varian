import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_decoder/audio_decoder_platform_interface.dart';
import 'package:varian/features/media/data/media_processing_isolate_runner.dart';

import 'media_runtime_fixture_data.dart';
import 'runtime_audio_decoder_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerRuntimeAudioDecoderPlatform();

  const runtimeEnabled = bool.fromEnvironment(
    'VARIAN_MEDIA_RUNTIME',
    defaultValue: false,
  );
  final nativePluginUnavailable =
      !kIsWeb &&
      AudioDecoderPlatform.instance.runtimeType.toString().contains(
        'MethodChannel',
      );
  final runtimeSkip = kIsWeb
      ? 'Flutter test Web runner is headless; run tool/media_decoder_web_probe.dart in Chrome.'
      : nativePluginUnavailable
      ? 'Flutter unit tests do not register native codec plugins; run tool/media_decoder_runtime_probe.dart.'
      : runtimeEnabled
      ? null
      : 'Run with --dart-define=VARIAN_MEDIA_RUNTIME=true on a real platform.';
  const fixtures = [
    _RuntimeFixture(
      name: 'mp3',
      formatHint: 'mp3',
      parts: mediaRuntimeMp3Base64Parts,
    ),
    _RuntimeFixture(
      name: 'ogg',
      formatHint: 'ogg',
      parts: mediaRuntimeOggBase64Parts,
    ),
    _RuntimeFixture(
      name: 'm4a',
      formatHint: 'm4a',
      parts: mediaRuntimeM4aBase64Parts,
    ),
  ];

  for (final fixture in fixtures) {
    test('runtime decoder matrix handles ${fixture.name}', () async {
      final sourceBytes = Uint8List.fromList(
        base64Decode(fixture.parts.join()),
      );
      expect(sourceBytes, isNotEmpty);
      if (kIsWeb) {
        expect(
          AudioDecoderPlatform.instance.runtimeType.toString(),
          contains('AudioDecoderWeb'),
        );
      }

      const runner = MediaProcessingIsolateRunner(enabled: false);
      final waveform = await _decodeWaveform(
        sourceBytes: sourceBytes,
        formatHint: fixture.formatHint,
        runner: runner,
      );
      expect(waveform, isNotNull);
      expect(waveform, hasLength(32));
      expect(
        waveform!.every(
          (sample) => sample.isFinite && sample >= 0 && sample <= 1,
        ),
        isTrue,
      );

      final trimmed = await _trimAudio(
        sourceBytes,
        formatHint: fixture.formatHint,
        runner: runner,
      );
      expect(trimmed, isNotNull);
      expect(_isWav(trimmed!), isTrue);

      final transcoded = await _transcodeAudio(
        sourceBytes,
        formatHint: fixture.formatHint,
        runner: runner,
      );
      expect(transcoded, isNotNull);
      expect(_isWav(transcoded!), isTrue);
    }, skip: runtimeSkip);
  }

  test('runtime decoder matrix handles generated PCM WAV', () async {
    const runner = MediaProcessingIsolateRunner(enabled: false);
    final sourceBytes = _wavPcm16(
      samples: [0, 8_000, 16_000, 24_000, 32_000, 24_000, 16_000, 8_000],
    );
    final waveform = await runner.decodeWaveform(sourceBytes, sampleCount: 16);
    expect(waveform, isNotNull);
    expect(waveform, hasLength(8));
    expect(waveform!.any((sample) => sample > 0.9), isTrue);

    final trimmed = await _trimAudio(
      sourceBytes,
      formatHint: 'wav',
      runner: runner,
    );
    expect(trimmed, isNotNull);
    expect(_isWav(trimmed!), isTrue);
  }, skip: runtimeSkip);
}

Future<List<double>?> _decodeWaveform({
  required Uint8List sourceBytes,
  required String formatHint,
  required MediaProcessingIsolateRunner runner,
}) async {
  return runner
      .decodeCompressedWaveform(
        sourceBytes,
        sampleCount: 32,
        formatHint: formatHint,
      )
      .timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw StateError('Waveform decoder timed out for $formatHint.'),
      );
}

Future<Uint8List?> _trimAudio(
  Uint8List sourceBytes, {
  required String formatHint,
  required MediaProcessingIsolateRunner runner,
}) async {
  return runner
      .trimAudio(sourceBytes, formatHint: formatHint, startMs: 0, endMs: 100)
      .timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw StateError('Audio trim timed out for $formatHint.'),
      );
}

Future<Uint8List?> _transcodeAudio(
  Uint8List sourceBytes, {
  required String formatHint,
  required MediaProcessingIsolateRunner runner,
}) async {
  return runner
      .transcodeAudio(sourceBytes, formatHint: formatHint)
      .timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw StateError('Audio transcode timed out for $formatHint.'),
      );
}

final class _RuntimeFixture {
  final String name;
  final String formatHint;
  final List<String> parts;

  const _RuntimeFixture({
    required this.name,
    required this.formatHint,
    required this.parts,
  });
}

bool _isWav(Uint8List bytes) =>
    bytes.length >= 12 &&
    bytes[0] == 0x52 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46 &&
    bytes[3] == 0x46 &&
    bytes[8] == 0x57 &&
    bytes[9] == 0x41 &&
    bytes[10] == 0x56 &&
    bytes[11] == 0x45;

Uint8List _wavPcm16({required List<int> samples}) {
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
