import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'media_runtime_fixture_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = <Map<String, Object?>>[];
  final fixtures = <_RuntimeFixture>[
    _RuntimeFixture(
      name: 'mp3',
      formatHint: 'mp3',
      bytes: Uint8List.fromList(
        base64Decode(mediaRuntimeMp3Base64Parts.join()),
      ),
    ),
    _RuntimeFixture(
      name: 'ogg',
      formatHint: 'ogg',
      bytes: Uint8List.fromList(
        base64Decode(mediaRuntimeOggBase64Parts.join()),
      ),
    ),
    _RuntimeFixture(
      name: 'm4a',
      formatHint: 'm4a',
      bytes: Uint8List.fromList(
        base64Decode(mediaRuntimeM4aBase64Parts.join()),
      ),
    ),
    _RuntimeFixture(name: 'wav', formatHint: 'wav', bytes: _wavPcm16()),
  ];

  for (final fixture in fixtures) {
    try {
      final waveform = await _withTimeout(
        AudioDecoder.getWaveformBytes(
          fixture.bytes,
          formatHint: fixture.formatHint,
          numberOfSamples: 32,
        ),
        'waveform',
        fixture.name,
      );
      final trimmed = await _withTimeout(
        AudioDecoder.trimAudioBytes(
          fixture.bytes,
          formatHint: fixture.formatHint,
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
          outputFormat: 'wav',
        ),
        'trim',
        fixture.name,
      );
      final transcoded = await _withTimeout(
        AudioDecoder.convertToWavBytes(
          fixture.bytes,
          formatHint: fixture.formatHint,
        ),
        'transcode',
        fixture.name,
      );
      results.add({
        'name': fixture.name,
        'platform': Platform.operatingSystem,
        'waveformSamples': waveform.length,
        'trimmedWav': _isWav(trimmed),
        'transcodedWav': _isWav(transcoded),
        'status': 'passed',
      });
    } catch (error) {
      final expectedUnsupported =
          Platform.isWindows && fixture.formatHint == 'ogg';
      results.add({
        'name': fixture.name,
        'platform': Platform.operatingSystem,
        'status': expectedUnsupported ? 'unsupported' : 'failed',
        'expected': expectedUnsupported,
        'error': error.toString(),
      });
    }
  }

  final report = jsonEncode(results);
  stdout.writeln(report);
  if (Platform.isAndroid || Platform.isIOS) {
    final directory = await getApplicationSupportDirectory();
    await File(
      '${directory.path}/media_decoder_runtime_probe.json',
    ).writeAsString(report);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final success = results.every(
    (result) => result['status'] == 'passed' || result['expected'] == true,
  );
  exit(success ? 0 : 1);
}

Future<T> _withTimeout<T>(Future<T> operation, String action, String fixture) =>
    operation.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw StateError('$action timed out for $fixture'),
    );

final class _RuntimeFixture {
  final String name;
  final String formatHint;
  final Uint8List bytes;

  const _RuntimeFixture({
    required this.name,
    required this.formatHint,
    required this.bytes,
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
