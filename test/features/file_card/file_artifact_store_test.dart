import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';

void main() {
  test('file artifacts hydrate through an opaque reference', () async {
    final store = MemoryFileArtifactStore();
    final artifact = await store.save(
      Uint8List.fromList([1, 2, 3]),
      fileName: 'notes.txt',
    );

    final payload = FilePayload(
      fileName: 'notes.txt',
      fileExtension: 'txt',
      artifactReference: artifact.reference,
      localPath: r'C:\runtime\should-not-be-needed.txt',
      base64Data: 'c2hvdWxkLW5vdC1iZS1uZWVkZWQ=',
      remoteUrl: 'https://example.com/runtime.txt?token=transient',
    );
    final restored = FilePayload.fromJson(payload.toJson());
    final bytes = await TransientFileSourceResolver(
      fileArtifactStore: store,
    ).resolveBytes(restored);

    expect(bytes, [1, 2, 3]);
    expect(restored.artifactReference, artifact.reference);
    expect(restored.localPath, isNull);
    expect(restored.base64Data, isNull);
    expect(restored.remoteUrl, isNull);
  });

  test('file artifact store rejects invalid PDF signatures', () async {
    final store = MemoryFileArtifactStore();

    expect(
      () => store.save(Uint8List.fromList([1, 2, 3]), fileName: 'broken.pdf'),
      throwsA(isA<FileArtifactStoreException>()),
    );
  });

  test('file artifact store rejects empty and oversized content', () async {
    final store = MemoryFileArtifactStore();

    expect(
      () => store.save(Uint8List(0), fileName: 'empty.txt'),
      throwsA(isA<FileArtifactStoreException>()),
    );
    expect(
      () => store.save(
        Uint8List(maxFileArtifactBytes + 1),
        fileName: 'too-large.bin',
      ),
      throwsA(isA<FileArtifactStoreException>()),
    );
  });
}
