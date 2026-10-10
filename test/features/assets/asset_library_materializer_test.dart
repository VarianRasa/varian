import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'package:varian/features/assets/data/asset_library_materializer.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/assets/domain/asset_library.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store_types.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25);

  test(
    'materializes every catalog binary through its owned artifact store',
    () async {
      final imageBytes = Uint8List.fromList(<int>[
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
      final fileBytes = Uint8List.fromList('%PDF-1.7'.codeUnits);
      final audioBytes = Uint8List.fromList(<int>[73, 68, 51, 3, 0, 0]);
      final videoBytes = Uint8List.fromList(<int>[
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
      final modelBytes = Uint8List.fromList(<int>[
        0x67,
        0x6c,
        0x54,
        0x46,
        2,
        0,
        0,
        0,
        24,
        0,
        0,
        0,
        4,
        0,
        0,
        0,
        0x4a,
        0x53,
        0x4f,
        0x4e,
        32,
        32,
        32,
        32,
      ]);
      final bytesById = <String, Uint8List>{
        'image': imageBytes,
        'file': fileBytes,
        'audio': audioBytes,
        'video': videoBytes,
        'model': modelBytes,
      };
      final materializer = AssetLibraryMaterializer(
        imageArtifactStore: MemoryImageArtifactStore(),
        fileArtifactStore: MemoryFileArtifactStore(),
        mediaArtifactStore: MemoryMediaArtifactStore(),
        videoArtifactStore: MemoryVideoArtifactStore(),
        model3DArtifactStore: MemoryModel3DArtifactStore(),
        readBytes: (item) async => bytesById[item.id],
      );

      AssetLibraryItem item(
        String id,
        AssetLibraryItemKind kind,
        String name,
        String mimeType,
      ) => AssetLibraryItem(
        id: id,
        scopeId: 'project-1',
        kind: kind,
        source: AssetLibrarySource.upload,
        name: name,
        mimeType: mimeType,
        createdAt: now,
        updatedAt: now,
      );

      final items = <AssetLibraryItem>[
        item('image', AssetLibraryItemKind.image, 'hero.png', 'image/png'),
        item('file', AssetLibraryItemKind.file, 'brief.pdf', 'application/pdf'),
        item('audio', AssetLibraryItemKind.audio, 'voice.mp3', 'audio/mpeg'),
        item('video', AssetLibraryItemKind.video, 'demo.mp4', 'video/mp4'),
        item(
          'model',
          AssetLibraryItemKind.model3d,
          'chair.glb',
          'model/gltf-binary',
        ),
      ];

      for (final item in items) {
        final result = await materializer.materialize(item);

        expect(result, isNotNull, reason: item.id);
        expect(result!.bytes, bytesById[item.id]);
        expect(result.sizeBytes, bytesById[item.id]!.length);
        expect(result.checksum, sha256.convert(bytesById[item.id]!).toString());
        expect(result.reference, startsWith('varian-'), reason: item.id);
      }
    },
  );

  test('rejects a catalog item outside the active project scope', () async {
    final materializer = AssetLibraryMaterializer(
      imageArtifactStore: MemoryImageArtifactStore(),
      fileArtifactStore: MemoryFileArtifactStore(),
      mediaArtifactStore: MemoryMediaArtifactStore(),
      videoArtifactStore: MemoryVideoArtifactStore(),
      model3DArtifactStore: MemoryModel3DArtifactStore(),
      readBytes: (item) async =>
          Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      isCurrent: () => true,
      activeProjectId: 'project-active',
    );

    final result = await materializer.materialize(
      AssetLibraryItem(
        id: 'foreign-scope',
        scopeId: 'project-foreign',
        kind: AssetLibraryItemKind.image,
        source: AssetLibrarySource.upload,
        name: 'foreign.png',
        mimeType: 'image/png',
        storagePath: 'project-active/library/foreign.png',
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(result, isNull);
  });

  test(
    'stops before saving when the operation becomes stale after reading',
    () async {
      var current = true;
      final materializer = AssetLibraryMaterializer(
        imageArtifactStore: MemoryImageArtifactStore(),
        fileArtifactStore: MemoryFileArtifactStore(),
        mediaArtifactStore: MemoryMediaArtifactStore(),
        videoArtifactStore: MemoryVideoArtifactStore(),
        model3DArtifactStore: MemoryModel3DArtifactStore(),
        readBytes: (item) async {
          current = false;
          return Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
        },
        isCurrent: () => current,
      );

      final result = await materializer.materialize(
        AssetLibraryItem(
          id: 'stale',
          scopeId: 'project-1',
          kind: AssetLibraryItemKind.image,
          source: AssetLibrarySource.upload,
          name: 'stale.png',
          mimeType: 'image/png',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(result, isNull);
    },
  );

  test(
    'rejects missing, corrupt, declared-size, and checksum-mismatched input',
    () async {
      final materializer = AssetLibraryMaterializer(
        imageArtifactStore: MemoryImageArtifactStore(),
        fileArtifactStore: MemoryFileArtifactStore(),
        mediaArtifactStore: MemoryMediaArtifactStore(),
        videoArtifactStore: MemoryVideoArtifactStore(),
        model3DArtifactStore: MemoryModel3DArtifactStore(),
        readBytes: (item) async =>
            item.id == 'missing' ? null : Uint8List.fromList(<int>[1, 2, 3, 4]),
      );

      AssetLibraryItem item(
        String id,
        AssetLibraryItemKind kind,
        String name,
        String mimeType, {
        int? sizeBytes,
        String? checksum,
      }) => AssetLibraryItem(
        id: id,
        scopeId: 'project-1',
        kind: kind,
        source: AssetLibrarySource.upload,
        name: name,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        checksum: checksum,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        await materializer.materialize(
          item(
            'missing',
            AssetLibraryItemKind.image,
            'missing.png',
            'image/png',
          ),
        ),
        isNull,
      );
      expect(
        await materializer.materialize(
          item(
            'corrupt',
            AssetLibraryItemKind.image,
            'corrupt.png',
            'image/png',
          ),
        ),
        isNull,
      );
      expect(
        await materializer.materialize(
          item(
            'size',
            AssetLibraryItemKind.file,
            'brief.txt',
            'text/plain',
            sizeBytes: 9,
          ),
        ),
        isNull,
      );
      expect(
        await materializer.materialize(
          item(
            'checksum',
            AssetLibraryItemKind.file,
            'brief.txt',
            'text/plain',
            checksum: '0' * 64,
          ),
        ),
        isNull,
      );
    },
  );
}
