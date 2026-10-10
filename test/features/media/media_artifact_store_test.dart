import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/features/media/data/media_artifact_store.dart';
import 'package:varian/features/media/data/media_processing_queue.dart';
import 'package:varian/features/media/data/media_processing_worker.dart';
import 'package:varian/features/media/data/media_video_proxy_transcoder.dart';

void main() {
  test('memory store saves, reads, hydrates, and disposes artifacts', () async {
    final store = MemoryMediaArtifactStore();
    final artifact = await store.save(
      Uint8List.fromList([1, 2, 3, 4]),
      kind: MediaArtifactKind.proxy,
      mimeType: 'video/mp4',
      checksum: 'checksum',
      fileName: 'source.mp4',
      storagePolicy: MediaStoragePolicy.durable,
    );

    expect(artifact.isAvailable, isTrue);
    expect(artifact.isPersistent, isTrue);
    expect(await store.exists(artifact), isTrue);
    expect(await store.read(artifact), [1, 2, 3, 4]);

    final hydrated = await store.hydrate(artifact.reference!);
    expect(hydrated?.kind, MediaArtifactKind.proxy);
    expect(await store.read(hydrated!), [1, 2, 3, 4]);

    await store.dispose(artifact);
    expect(await store.exists(artifact), isTrue);
    expect(await store.read(artifact), [1, 2, 3, 4]);
  });

  test(
    'memory store rejects a checksum that does not match the bytes',
    () async {
      final store = MemoryMediaArtifactStore();

      await expectLater(
        store.save(
          Uint8List.fromList([1, 2, 3]),
          kind: MediaArtifactKind.original,
          mimeType: 'audio/mpeg',
          checksum: '0' * 64,
          fileName: 'source.mp3',
          storagePolicy: MediaStoragePolicy.durable,
        ),
        throwsA(isA<MediaArtifactStoreException>()),
      );
    },
  );

  test('worker materializes media bytes and deterministic sidecars', () async {
    final store = MemoryMediaArtifactStore();
    final sourceBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
    final worker = DeterministicMediaProcessingWorker(
      artifactStore: store,
      videoProxyTranscoder: const _FakeVideoProxyTranscoder(),
    );
    final output = await worker.process(
      MediaProcessingRequest(
        id: 'materialized',
        sourceKey: 'source://memory',
        inputChecksum: 'input',
        artifactKinds: const [
          MediaArtifactKind.proxy,
          MediaArtifactKind.thumbnail,
          MediaArtifactKind.waveform,
        ],
        metadata: {
          'sourceMimeType': 'video/mp4',
          'sourceFileName': 'source.mp4',
          'sourceBytesBase64': base64Encode(sourceBytes),
        },
      ),
      MediaProcessingCancellationToken(),
    );

    final proxy = output.artifacts.find(MediaArtifactKind.proxy)!;
    final thumbnail = output.artifacts.find(MediaArtifactKind.thumbnail)!;
    final waveform = output.artifacts.find(MediaArtifactKind.waveform)!;
    expect(proxy.reference, startsWith('memory://cache/'));
    expect(await store.read(proxy), sourceBytes);
    expect(thumbnail.mimeType, 'image/svg+xml');
    expect((await store.read(thumbnail))!, containsUtf8('<svg'));
    final waveformJson =
        jsonDecode(utf8.decode((await store.read(waveform))!))
            as Map<String, dynamic>;
    expect(waveformJson['samples'], hasLength(96));
    expect(output.artifacts.items.every((item) => item.isAvailable), isTrue);
    expect(output.artifacts.items.every((item) => item.isPersistent), isTrue);
  });
}

Matcher containsUtf8(String expected) =>
    predicate<Uint8List>((value) => utf8.decode(value).contains(expected));

final class _FakeVideoProxyTranscoder implements MediaVideoProxyTranscoder {
  const _FakeVideoProxyTranscoder();

  @override
  Future<MediaVideoProxyResult> transcode({
    required String sourceKey,
    required Uint8List sourceBytes,
    required String? sourceMimeType,
    required String? sourceFileName,
    required String? formatHint,
    required String outputFormat,
    required List<MediaClip> clips,
  }) async => MediaVideoProxyResult(
    status: MediaVideoProxyStatus.supported,
    bytes: Uint8List.fromList(sourceBytes),
  );
}
