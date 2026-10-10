import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:varian/features/media/data/media_processing_isolate_runner.dart';

import 'media_decoder_web_platform.dart';
import 'media_runtime_fixture_data.dart';

void main() {
  registerRuntimeAudioDecoderPlatform();
  runApp(const _ProbeApp());
}

final class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

final class _ProbeAppState extends State<_ProbeApp> {
  Object? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
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
    ];

    const runner = MediaProcessingIsolateRunner(enabled: false);
    for (final fixture in fixtures) {
      try {
        final waveform = await _withTimeout(
          runner.decodeCompressedWaveform(
            fixture.bytes,
            sampleCount: 32,
            formatHint: fixture.formatHint,
          ),
          'waveform',
          fixture.name,
        );
        final trimmed = await _withTimeout(
          runner.trimAudio(
            fixture.bytes,
            formatHint: fixture.formatHint,
            startMs: 0,
            endMs: 100,
          ),
          'trim',
          fixture.name,
        );
        final transcoded = await _withTimeout(
          runner.transcodeAudio(fixture.bytes, formatHint: fixture.formatHint),
          'transcode',
          fixture.name,
        );
        results.add({
          'name': fixture.name,
          'waveformSamples': waveform?.length ?? 0,
          'trimmedWav': _isWav(trimmed),
          'transcodedWav': _isWav(transcoded),
          'status': waveform == null || trimmed == null || transcoded == null
              ? 'unsupported'
              : 'passed',
        });
      } catch (error) {
        results.add({
          'name': fixture.name,
          'status': 'failed',
          'error': error.toString(),
        });
      }
    }
    if (!mounted) return;
    setState(() => _result = results);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SelectableText(
          _result == null ? 'running' : jsonEncode(_result),
          key: const ValueKey('probe-output'),
        ),
      ),
    ),
  );
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

bool _isWav(Uint8List? bytes) =>
    bytes != null &&
    bytes.length >= 12 &&
    bytes[0] == 0x52 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46 &&
    bytes[3] == 0x46 &&
    bytes[8] == 0x57 &&
    bytes[9] == 0x41 &&
    bytes[10] == 0x56 &&
    bytes[11] == 0x45;
