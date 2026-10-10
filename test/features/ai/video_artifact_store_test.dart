import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/ai/data/video_artifact_store.dart';
import 'package:varian/features/ai/data/video_provider.dart';

Uint8List _minimalMp4() => Uint8List.fromList([
  0,
  0,
  0,
  16,
  102,
  116,
  121,
  112,
  105,
  115,
  111,
  109,
  0,
  0,
  0,
  0,
]);

void main() {
  test('rejects bytes without an MP4 signature', () async {
    final store = MemoryVideoArtifactStore();
    expect(
      () => store.save(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<VideoProviderException>()),
    );
  });

  test('stores and reads a valid MP4 artifact', () async {
    final store = MemoryVideoArtifactStore();
    final bytes = _minimalMp4();
    final artifact = await store.save(bytes, fileName: 'generated.mp4');

    expect(await store.exists(artifact), isTrue);
    expect(await store.read(artifact), bytes);
    expect(artifact.fileName, 'generated.mp4');
  });

  test('sanitizes an unsafe artifact name', () async {
    final store = MemoryVideoArtifactStore();
    final artifact = await store.save(
      _minimalMp4(),
      fileName: '../fixture.txt',
    );

    expect(artifact.fileName, 'fixture.mp4');
  });

  test('artifact references are stable and contain no video bytes', () async {
    final artifact = await MemoryVideoArtifactStore().save(_minimalMp4());
    expect(artifact.reference, artifact.path);
    expect(artifact.reference, isNot(contains('base64')));
  });

  test(
    'disposed handles cannot read embedded bytes but durable hydration survives',
    () async {
      final store = MemoryVideoArtifactStore();
      final bytes = _minimalMp4();
      final artifact = await store.save(bytes);

      await store.dispose(artifact);

      expect(await store.read(artifact), isNull);
      final rehydrated = await store.hydrate(artifact.reference!);
      expect(rehydrated, isNotNull);
      expect(await store.read(rehydrated!), bytes);
    },
  );
}
