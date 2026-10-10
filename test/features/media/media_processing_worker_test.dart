import 'package:flutter_test/flutter_test.dart';
import 'package:audio_decoder/audio_decoder_platform_interface.dart';
import 'package:image/image.dart' as image;
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';
import 'package:varian/features/media/data/media_processing_queue.dart';
import 'package:varian/features/media/data/media_processing_worker.dart';
import 'package:varian/features/media/data/media_video_proxy_transcoder.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  test(
    'deterministic worker creates checked artifacts and waveform patch',
    () async {
      const timeline = MediaTimeline(
        sourceDurationMs: 12_000,
        clips: [MediaClip(id: 'clip', startMs: 0, endMs: 12_000)],
      );
      final coordinator = MediaProcessingCoordinator();

      final processed = await coordinator.processTimeline(
        id: 'media-job',
        sourceKey: 'source://demo',
        inputChecksum: 'input-checksum',
        timeline: timeline,
        artifactKinds: const [
          MediaArtifactKind.proxy,
          MediaArtifactKind.thumbnail,
          MediaArtifactKind.waveform,
        ],
        storagePolicy: MediaStoragePolicy.durable,
        metadata: const {'sourceMimeType': 'video/webm'},
      );
      addTearDown(coordinator.dispose);

      expect(processed.hasProxy, isTrue);
      expect(processed.artifacts.contains(MediaArtifactKind.thumbnail), isTrue);
      expect(processed.artifacts.contains(MediaArtifactKind.waveform), isTrue);
      expect(processed.waveformSamples, hasLength(96));
      expect(
        processed.waveformSamples.every((sample) => sample >= 0 && sample <= 1),
        isTrue,
      );
      expect(
        processed.artifacts.find(MediaArtifactKind.proxy)!.url,
        startsWith('varian-media://durable/'),
      );
      expect(
        processed.artifacts.items.every(
          (artifact) => artifact.checksum != null,
        ),
        isTrue,
      );
    },
  );

  test('coordinator deduplicates already materialized artifacts', () async {
    const timeline = MediaTimeline(
      artifacts: MediaArtifactManifest(
        items: [
          MediaArtifact(
            kind: MediaArtifactKind.thumbnail,
            url: 'varian-media://cache/existing/thumbnail',
            checksum: 'thumbnail-checksum',
          ),
        ],
      ),
    );
    final coordinator = MediaProcessingCoordinator();

    final job = coordinator.enqueueTimeline(
      id: 'only-proxy',
      sourceKey: 'source://demo',
      inputChecksum: 'input-checksum',
      timeline: timeline,
      artifactKinds: const [
        MediaArtifactKind.thumbnail,
        MediaArtifactKind.proxy,
      ],
    );

    expect(job, isNotNull);
    expect(job!.request.artifactKinds, [MediaArtifactKind.proxy]);
    await coordinator.queue.waitForIdle();
    expect(
      coordinator.queue[job.request.id]!.status,
      MediaProcessingStatus.succeeded,
    );
    await coordinator.dispose();
  });

  test(
    'worker cancellation stops before materializing the next artifact',
    () async {
      const worker = DeterministicMediaProcessingWorker();
      final cancellation = MediaProcessingCancellationToken()..cancel();

      expect(
        () => worker.process(
          const MediaProcessingRequest(
            id: 'cancelled',
            sourceKey: 'source://demo',
            inputChecksum: 'checksum',
            artifactKinds: [MediaArtifactKind.proxy],
          ),
          cancellation,
        ),
        throwsA(isA<MediaProcessingException>()),
      );
    },
  );

  test('materializes real raster proxy and thumbnail bytes', () async {
    final source = image.Image(width: 8, height: 4);
    source.setPixelRgba(0, 0, 255, 32, 64, 255);
    final sourceBytes = Uint8List.fromList(image.encodePng(source));
    final store = MemoryMediaArtifactStore();
    const timeline = MediaTimeline(sourceDurationMs: 1_000);
    final worker = DeterministicMediaProcessingWorker(artifactStore: store);
    final output = await worker.process(
      MediaProcessingRequest(
        id: 'image-job',
        sourceKey: 'memory://image',
        inputChecksum: 'image-checksum',
        artifactKinds: const [
          MediaArtifactKind.proxy,
          MediaArtifactKind.thumbnail,
        ],
        metadata: {
          'sourceMimeType': 'image/png',
          'sourceFileName': 'source.png',
          'sourceBytesBase64': base64Encode(sourceBytes),
          'timelineJson': jsonEncode(timeline.toJson()),
        },
      ),
      MediaProcessingCancellationToken(),
    );

    final thumbnail = await store.read(
      output.artifacts.find(MediaArtifactKind.thumbnail)!,
    );
    final proxy = await store.read(
      output.artifacts.find(MediaArtifactKind.proxy)!,
    );
    expect(thumbnail, isNotNull);
    expect(proxy, isNotNull);
    expect(image.decodeImage(thumbnail!), isNotNull);
    expect(image.decodeImage(proxy!), isNotNull);
    expect(
      output.artifacts.find(MediaArtifactKind.thumbnail)!.mimeType,
      'image/png',
    );
  });

  test('extracts waveform peaks from PCM WAV sources', () async {
    final sourceBytes = _wavPcm16(
      samples: [0, 32767, -32768, 0, 0, 16384, -16384, 0],
    );
    final store = MemoryMediaArtifactStore();
    const timeline = MediaTimeline(sourceDurationMs: 1_000);
    final output =
        await DeterministicMediaProcessingWorker(artifactStore: store).process(
          MediaProcessingRequest(
            id: 'wav-job',
            sourceKey: 'memory://audio.wav',
            inputChecksum: 'wav-checksum',
            artifactKinds: const [MediaArtifactKind.waveform],
            metadata: {
              'sourceMimeType': 'audio/wav',
              'sourceFileName': 'audio.wav',
              'sourceBytesBase64': base64Encode(sourceBytes),
              'timelineJson': jsonEncode(timeline.toJson()),
            },
          ),
          MediaProcessingCancellationToken(),
        );

    final samples = output.timeline!.waveformSamples;
    expect(samples, isNotEmpty);
    expect(
      samples.reduce((left, right) => left > right ? left : right),
      greaterThan(0.99),
    );
    final waveform =
        jsonDecode(
              utf8.decode(
                (await store.read(
                  output.artifacts.find(MediaArtifactKind.waveform)!,
                ))!,
              ),
            )
            as Map<String, dynamic>;
    expect(waveform['samples'], samples);
  });

  test('creates a codec-aware WAV proxy for a single audio clip', () async {
    final original = AudioDecoderPlatform.instance;
    final decoder = _FakeTrimAudioDecoderPlatform();
    AudioDecoderPlatform.instance = decoder;
    addTearDown(() => AudioDecoderPlatform.instance = original);

    const timeline = MediaTimeline(
      sourceDurationMs: 5_000,
      clips: [MediaClip(id: 'clip', startMs: 1_000, endMs: 2_500)],
    );
    final store = MemoryMediaArtifactStore();
    final output =
        await DeterministicMediaProcessingWorker(artifactStore: store).process(
          MediaProcessingRequest(
            id: 'audio-proxy-job',
            sourceKey: 'memory://track.mp3',
            inputChecksum: 'audio-checksum',
            artifactKinds: const [MediaArtifactKind.proxy],
            metadata: {
              'sourceMimeType': 'audio/mpeg',
              'sourceFileName': 'track.mp3',
              'sourceBytesBase64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'timelineJson': jsonEncode(timeline.toJson()),
            },
          ),
          MediaProcessingCancellationToken(),
        );

    final artifact = output.artifacts.find(MediaArtifactKind.proxy)!;
    final bytes = await store.read(artifact);
    expect(bytes, [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);
    expect(artifact.mimeType, 'audio/wav');
    expect(decoder.formatHint, 'mp3');
    expect(decoder.start, const Duration(seconds: 1));
    expect(decoder.end, const Duration(milliseconds: 2_500));
    expect(decoder.outputFormat, 'wav');
  });

  test('concatenates enabled audio clips in timeline order', () async {
    final original = AudioDecoderPlatform.instance;
    final decoder = _FakeMultiClipAudioDecoderPlatform(
      outputsByStartMs: {
        1_000: _wavPcm16(samples: [100, 200]),
        3_000: _wavPcm16(samples: [300, 400, 500]),
      },
    );
    AudioDecoderPlatform.instance = decoder;
    addTearDown(() => AudioDecoderPlatform.instance = original);

    const timeline = MediaTimeline(
      sourceDurationMs: 5_000,
      clips: [
        MediaClip(id: 'first', startMs: 1_000, endMs: 2_000),
        MediaClip(id: 'disabled', startMs: 2_000, endMs: 3_000, enabled: false),
        MediaClip(id: 'second', startMs: 3_000, endMs: 4_000),
      ],
    );
    final store = MemoryMediaArtifactStore();
    final output =
        await DeterministicMediaProcessingWorker(artifactStore: store).process(
          MediaProcessingRequest(
            id: 'multi-audio-proxy-job',
            sourceKey: 'memory://track.mp3',
            inputChecksum: 'multi-audio-checksum',
            artifactKinds: const [MediaArtifactKind.proxy],
            metadata: {
              'sourceMimeType': 'audio/mpeg',
              'sourceFileName': 'track.mp3',
              'sourceBytesBase64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'timelineJson': jsonEncode(timeline.toJson()),
            },
          ),
          MediaProcessingCancellationToken(),
        );

    final artifact = output.artifacts.find(MediaArtifactKind.proxy)!;
    final bytes = await store.read(artifact);
    expect(_readPcm16Samples(bytes!), [100, 200, 300, 400, 500]);
    expect(decoder.trimStarts, [
      const Duration(seconds: 1),
      const Duration(seconds: 3),
    ]);
    expect(decoder.trimOutputFormats, ['wav', 'wav']);
    expect(artifact.mimeType, 'audio/wav');
  });

  test('transcodes a concatenated audio proxy to M4A when requested', () async {
    final original = AudioDecoderPlatform.instance;
    final decoder = _FakeMultiClipAudioDecoderPlatform(
      outputsByStartMs: {
        1_000: _wavPcm16(samples: [100]),
        3_000: _wavPcm16(samples: [200]),
      },
      m4aBytes: Uint8List.fromList([
        0,
        0,
        0,
        24,
        0x66,
        0x74,
        0x79,
        0x70,
        0,
        0,
        0,
        0,
      ]),
    );
    AudioDecoderPlatform.instance = decoder;
    addTearDown(() => AudioDecoderPlatform.instance = original);

    const timeline = MediaTimeline(
      sourceDurationMs: 5_000,
      clips: [
        MediaClip(id: 'first', startMs: 1_000, endMs: 2_000),
        MediaClip(id: 'second', startMs: 3_000, endMs: 4_000),
      ],
    );
    final store = MemoryMediaArtifactStore();
    final output =
        await DeterministicMediaProcessingWorker(artifactStore: store).process(
          MediaProcessingRequest(
            id: 'multi-audio-m4a-job',
            sourceKey: 'memory://track.mp3',
            inputChecksum: 'multi-audio-m4a-checksum',
            artifactKinds: const [MediaArtifactKind.proxy],
            metadata: {
              'proxyFormat': 'm4a',
              'sourceMimeType': 'audio/mpeg',
              'sourceFileName': 'track.mp3',
              'sourceBytesBase64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'timelineJson': jsonEncode(timeline.toJson()),
            },
          ),
          MediaProcessingCancellationToken(),
        );

    final artifact = output.artifacts.find(MediaArtifactKind.proxy)!;
    expect(await store.read(artifact), decoder.m4aBytes);
    expect(decoder.transcodeFormatHint, 'wav');
    expect(artifact.mimeType, 'audio/mp4');
  });

  test(
    'fails instead of copying source when clip WAV formats mismatch',
    () async {
      final original = AudioDecoderPlatform.instance;
      final decoder = _FakeMultiClipAudioDecoderPlatform(
        outputsByStartMs: {
          1_000: _wavPcm16(samples: [100]),
          3_000: _wavPcm16(samples: [200], sampleRate: 16_000),
        },
      );
      AudioDecoderPlatform.instance = decoder;
      addTearDown(() => AudioDecoderPlatform.instance = original);

      const timeline = MediaTimeline(
        sourceDurationMs: 5_000,
        clips: [
          MediaClip(id: 'first', startMs: 1_000, endMs: 2_000),
          MediaClip(id: 'second', startMs: 3_000, endMs: 4_000),
        ],
      );
      final worker = DeterministicMediaProcessingWorker(
        artifactStore: MemoryMediaArtifactStore(),
      );

      await expectLater(
        worker.process(
          MediaProcessingRequest(
            id: 'mismatch-audio-proxy-job',
            sourceKey: 'memory://track.mp3',
            inputChecksum: 'mismatch-audio-checksum',
            artifactKinds: const [MediaArtifactKind.proxy],
            metadata: {
              'sourceMimeType': 'audio/mpeg',
              'sourceFileName': 'track.mp3',
              'sourceBytesBase64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'timelineJson': jsonEncode(timeline.toJson()),
            },
          ),
          MediaProcessingCancellationToken(),
        ),
        throwsA(
          isA<MediaProcessingException>().having(
            (error) => error.message,
            'message',
            contains('materialize proxy'),
          ),
        ),
      );
    },
  );

  test(
    'does not generate a full-source proxy when all clips are disabled',
    () async {
      final original = AudioDecoderPlatform.instance;
      final decoder = _FakeMultiClipAudioDecoderPlatform(outputsByStartMs: {});
      AudioDecoderPlatform.instance = decoder;
      addTearDown(() => AudioDecoderPlatform.instance = original);

      const timeline = MediaTimeline(
        sourceDurationMs: 5_000,
        clips: [
          MediaClip(
            id: 'disabled',
            startMs: 1_000,
            endMs: 2_000,
            enabled: false,
          ),
        ],
      );
      final worker = DeterministicMediaProcessingWorker(
        artifactStore: MemoryMediaArtifactStore(),
      );

      await expectLater(
        worker.process(
          MediaProcessingRequest(
            id: 'empty-audio-proxy-job',
            sourceKey: 'memory://track.mp3',
            inputChecksum: 'empty-audio-checksum',
            artifactKinds: const [MediaArtifactKind.proxy],
            metadata: {
              'sourceMimeType': 'audio/mpeg',
              'sourceFileName': 'track.mp3',
              'sourceBytesBase64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'timelineJson': jsonEncode(timeline.toJson()),
            },
          ),
          MediaProcessingCancellationToken(),
        ),
        throwsA(isA<MediaProcessingException>()),
      );
      expect(decoder.trimStarts, isEmpty);
    },
  );

  test(
    'reports unsupported video proxy instead of copying source bytes',
    () async {
      final sourceBytes = Uint8List.fromList([1, 2, 3, 4]);
      final worker = DeterministicMediaProcessingWorker(
        artifactStore: MemoryMediaArtifactStore(),
      );

      await expectLater(
        worker.process(
          MediaProcessingRequest(
            id: 'unsupported-video-proxy-job',
            sourceKey: 'memory://video.mp4',
            inputChecksum: 'unsupported-video-checksum',
            artifactKinds: const [MediaArtifactKind.proxy],
            metadata: {
              'sourceMimeType': 'video/mp4',
              'sourceFileName': 'video.mp4',
              'sourceBytesBase64': base64Encode(sourceBytes),
            },
          ),
          MediaProcessingCancellationToken(),
        ),
        throwsA(
          isA<MediaProcessingException>().having(
            (error) => error.message,
            'message',
            contains('no platform video encoder'),
          ),
        ),
      );
    },
  );

  test('uses an injected video proxy transcoder backend', () async {
    final sourceBytes = Uint8List.fromList([1, 2, 3, 4]);
    final transcoder = _FakeVideoProxyTranscoder();
    final store = MemoryMediaArtifactStore();
    final worker = DeterministicMediaProcessingWorker(
      artifactStore: store,
      videoProxyTranscoder: transcoder,
    );

    final output = await worker.process(
      MediaProcessingRequest(
        id: 'supported-video-proxy-job',
        sourceKey: 'memory://video.mp4',
        inputChecksum: 'supported-video-checksum',
        artifactKinds: const [MediaArtifactKind.proxy],
        metadata: {
          'sourceMimeType': 'video/mp4',
          'sourceFileName': 'video.mp4',
          'sourceBytesBase64': base64Encode(sourceBytes),
          'timelineJson': jsonEncode(
            const MediaTimeline(
              sourceDurationMs: 5_000,
              clips: [
                MediaClip(id: 'first', startMs: 1_000, endMs: 2_000),
                MediaClip(id: 'second', startMs: 3_000, endMs: 4_000),
              ],
            ).toJson(),
          ),
        },
      ),
      MediaProcessingCancellationToken(),
    );

    final artifact = output.artifacts.find(MediaArtifactKind.proxy)!;
    expect(await store.read(artifact), transcoder.outputBytes);
    expect(transcoder.sourceKey, 'memory://video.mp4');
    expect(transcoder.formatHint, 'mp4');
    expect(transcoder.outputFormat, 'mp4');
    expect(transcoder.clips.map((clip) => clip.id), ['first', 'second']);
  });

  test(
    'hydrates varian video sources through the injected video store',
    () async {
      final sourceBytes = _validMp4Bytes();
      final videoStore = MemoryVideoArtifactStore();
      final source = await videoStore.save(sourceBytes, fileName: 'source.mp4');
      final artifactStore = MemoryMediaArtifactStore();
      final worker = DeterministicMediaProcessingWorker(
        artifactStore: artifactStore,
        videoArtifactStore: videoStore,
      );

      final output = await worker.process(
        MediaProcessingRequest(
          id: 'injected-video-source-job',
          sourceKey: source.reference!,
          inputChecksum: 'injected-video-source-checksum',
          artifactKinds: const [MediaArtifactKind.original],
          metadata: const {
            'sourceMimeType': 'video/mp4',
            'sourceFileName': 'source.mp4',
          },
        ),
        MediaProcessingCancellationToken(),
      );

      final artifact = output.artifacts.find(MediaArtifactKind.original)!;
      expect(await artifactStore.read(artifact), sourceBytes);
    },
  );

  test(
    'hydrates varian media sources through the injected media store',
    () async {
      final sourceBytes = Uint8List.fromList([1, 2, 3, 4]);
      final sourceStore = MemoryMediaArtifactStore();
      final source = await sourceStore.save(
        sourceBytes,
        kind: MediaArtifactKind.original,
        mimeType: 'audio/wav',
        checksum: mediaArtifactChecksum(sourceBytes),
        fileName: 'source.wav',
        storagePolicy: MediaStoragePolicy.durable,
      );
      final artifactStore = MemoryMediaArtifactStore();
      final worker = DeterministicMediaProcessingWorker(
        artifactStore: artifactStore,
        mediaArtifactStore: sourceStore,
      );

      final output = await worker.process(
        MediaProcessingRequest(
          id: 'injected-media-source-job',
          sourceKey: source.reference!,
          inputChecksum: 'injected-media-source-checksum',
          artifactKinds: const [MediaArtifactKind.original],
          metadata: const {
            'sourceMimeType': 'audio/wav',
            'sourceFileName': 'source.wav',
          },
        ),
        MediaProcessingCancellationToken(),
      );

      final artifact = output.artifacts.find(MediaArtifactKind.original)!;
      expect(await artifactStore.read(artifact), sourceBytes);
    },
  );
}

Uint8List _validMp4Bytes() {
  return Uint8List.fromList([
    0,
    0,
    0,
    16,
    0x66,
    0x74,
    0x79,
    0x70,
    0x69,
    0x73,
    0x6f,
    0x6d,
    0,
    0,
    0,
    0,
  ]);
}

final class _FakeTrimAudioDecoderPlatform extends AudioDecoderPlatform {
  String? formatHint;
  Duration? start;
  Duration? end;
  String? outputFormat;

  @override
  Future<Uint8List> trimAudioBytes(
    Uint8List inputData,
    String formatHint,
    Duration start,
    Duration end, {
    String outputFormat = 'wav',
  }) async {
    this.formatHint = formatHint;
    this.start = start;
    this.end = end;
    this.outputFormat = outputFormat;
    return Uint8List.fromList([
      0x52,
      0x49,
      0x46,
      0x46,
      0,
      0,
      0,
      0,
      0x57,
      0x41,
      0x56,
      0x45,
    ]);
  }
}

final class _FakeVideoProxyTranscoder implements MediaVideoProxyTranscoder {
  final outputBytes = Uint8List.fromList([
    0,
    0,
    0,
    24,
    0x66,
    0x74,
    0x79,
    0x70,
    0x69,
    0x73,
    0x6f,
    0x6d,
  ]);
  String? sourceKey;
  String? formatHint;
  String? outputFormat;
  List<MediaClip> clips = const [];

  @override
  Future<MediaVideoProxyResult> transcode({
    required String sourceKey,
    required Uint8List sourceBytes,
    required String? sourceMimeType,
    required String? sourceFileName,
    required String? formatHint,
    required String outputFormat,
    required List<MediaClip> clips,
  }) async {
    this.sourceKey = sourceKey;
    this.formatHint = formatHint;
    this.outputFormat = outputFormat;
    this.clips = clips;
    return MediaVideoProxyResult(
      status: MediaVideoProxyStatus.supported,
      bytes: outputBytes,
    );
  }
}

final class _FakeMultiClipAudioDecoderPlatform extends AudioDecoderPlatform {
  final Map<int, Uint8List> outputsByStartMs;
  final Uint8List m4aBytes;
  final List<Duration> trimStarts = [];
  final List<String> trimOutputFormats = [];
  String? transcodeFormatHint;

  _FakeMultiClipAudioDecoderPlatform({
    required this.outputsByStartMs,
    Uint8List? m4aBytes,
  }) : m4aBytes = m4aBytes ?? Uint8List.fromList([0x66, 0x74, 0x79, 0x70]);

  @override
  Future<Uint8List> trimAudioBytes(
    Uint8List inputData,
    String formatHint,
    Duration start,
    Duration end, {
    String outputFormat = 'wav',
  }) async {
    trimStarts.add(start);
    trimOutputFormats.add(outputFormat);
    final bytes = outputsByStartMs[start.inMilliseconds];
    if (bytes == null) throw StateError('missing fixture');
    return bytes;
  }

  @override
  Future<Uint8List> convertToM4aBytes(
    Uint8List inputData,
    String formatHint,
  ) async {
    transcodeFormatHint = formatHint;
    return m4aBytes;
  }
}

Uint8List _wavPcm16({
  required List<int> samples,
  int sampleRate = 8_000,
  int channels = 1,
}) {
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);
  final raw = bytes.buffer.asUint8List();
  raw.setRange(0, 4, [82, 73, 70, 70]);
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  raw.setRange(8, 12, [87, 65, 86, 69]);
  raw.setRange(12, 16, [102, 109, 116, 32]);
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  raw.setRange(36, 40, [100, 97, 116, 97]);
  bytes.setUint32(40, dataSize, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    bytes.setInt16(44 + index * 2, samples[index], Endian.little);
  }
  return raw;
}

List<int> _readPcm16Samples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final dataSize = data.getUint32(40, Endian.little);
  return [
    for (var offset = 44; offset < 44 + dataSize; offset += 2)
      data.getInt16(offset, Endian.little),
  ];
}
