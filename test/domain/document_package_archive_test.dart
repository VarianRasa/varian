import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/document_package.dart';
import 'package:varian/domain/models/document_package_archive.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/export/domain/asset_export_policy.dart';
import 'package:varian/features/export/domain/portable_asset_collector.dart';
import 'package:varian/features/export/export_service.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store_types.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';

void main() {
  Uint8List minimalMp4() => Uint8List.fromList([
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

  Uint8List minimalGlb() => Uint8List.fromList([
    0x67,
    0x6c,
    0x54,
    0x46,
    0x02,
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
    0x7b,
    0x7d,
    0x20,
    0x20,
  ]);

  final createdAt = DateTime.utc(2026, 9, 13);

  final validPngBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

  DocumentPackageArchive createArchive({
    Map<String, Uint8List> bytes = const {},
  }) {
    final embeddedBytes = bytes['image-1'];
    final asset = DocumentAsset(
      id: 'image-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.embedded,
      name: 'image.png',
      mimeType: 'image/png',
      sizeBytes: embeddedBytes?.length,
      checksum: embeddedBytes == null
          ? null
          : DocumentPackageArchiveChecksum.sha256(embeddedBytes),
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final document = CanvasDocument(
      projectId: 'portable-project',
      assets: DocumentAssetManifest(entries: {'image-1': asset}),
      updatedAt: createdAt,
    );
    return DocumentPackageArchive(
      package: CanvasDocumentPackage(document: document),
      assetBytes: bytes,
    );
  }

  test('round trips a portable archive with embedded asset bytes', () {
    final source = createArchive(bytes: {'image-1': validPngBytes});

    final restored = DocumentPackageArchive.decode(source.encode());

    expect(restored.isPortable, isTrue);
    expect(restored.package.document.projectId, 'portable-project');
    expect(restored.assetBytes['image-1'], orderedEquals(validPngBytes));
    expect(restored.encrypted, isFalse);
  });

  test(
    'collects owned artifact bytes without persisting runtime delivery',
    () async {
      final now = DateTime.utc(2026, 9, 13);
      final imageStore = MemoryImageArtifactStore();
      final imageBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final imageArtifact = await imageStore.save(
        imageBytes,
        fileName: 'hero.png',
      );
      final asset = DocumentAsset(
        id: 'image-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'hero.png',
        mimeType: 'image/png',
        durableReference: imageArtifact.reference,
        createdAt: now,
        updatedAt: now,
      );
      final collector = PortableAssetCollector(
        imageArtifactStore: imageStore,
        fileArtifactStore: MemoryFileArtifactStore(),
        mediaArtifactStore: MemoryMediaArtifactStore(),
        videoArtifactStore: MemoryVideoArtifactStore(),
        model3DArtifactStore: MemoryModel3DArtifactStore(),
      );

      final result = await collector.collect(
        DocumentAssetManifest(entries: {asset.id: asset}),
      );

      expect(result.assetBytes['image-1'], orderedEquals(imageBytes));
      expect(result.isComplete, isTrue);
    },
  );

  test(
    'portable collection releases handles without deleting source artifacts',
    () async {
      final now = DateTime.utc(2026, 9, 13);
      final imageStore = MemoryImageArtifactStore();
      final fileStore = MemoryFileArtifactStore();
      final mediaStore = MemoryMediaArtifactStore();
      final videoStore = MemoryVideoArtifactStore();
      final modelStore = MemoryModel3DArtifactStore();
      final videoBytes = minimalMp4();
      final modelBytes = minimalGlb();
      final mediaBytes = Uint8List.fromList([1, 2, 3, 4]);
      final video = await videoStore.save(videoBytes, fileName: 'clip.mp4');
      final model = await modelStore.save(modelBytes, fileName: 'model.glb');
      final mediaChecksum = mediaArtifactChecksum(mediaBytes);
      final media = await mediaStore.save(
        mediaBytes,
        kind: MediaArtifactKind.original,
        mimeType: 'application/octet-stream',
        checksum: mediaChecksum,
        fileName: 'audio.bin',
        storagePolicy: MediaStoragePolicy.durable,
      );
      final assets = <String, DocumentAsset>{
        'video-1': DocumentAsset(
          id: 'video-1',
          kind: DocumentAssetKind.video,
          storage: DocumentAssetStorage.local,
          name: 'clip.mp4',
          mimeType: 'video/mp4',
          sizeBytes: videoBytes.length,
          checksum: DocumentPackageArchiveChecksum.sha256(videoBytes),
          durableReference: video.reference,
          createdAt: now,
          updatedAt: now,
        ),
        'model-1': DocumentAsset(
          id: 'model-1',
          kind: DocumentAssetKind.model3d,
          storage: DocumentAssetStorage.local,
          name: 'model.glb',
          mimeType: 'model/gltf-binary',
          sizeBytes: modelBytes.length,
          checksum: DocumentPackageArchiveChecksum.sha256(modelBytes),
          durableReference: model.reference,
          createdAt: now,
          updatedAt: now,
        ),
        'media-1': DocumentAsset(
          id: 'media-1',
          kind: DocumentAssetKind.audio,
          storage: DocumentAssetStorage.local,
          name: 'audio.bin',
          mimeType: 'application/octet-stream',
          sizeBytes: mediaBytes.length,
          checksum: mediaChecksum,
          durableReference: media.reference,
          createdAt: now,
          updatedAt: now,
        ),
      };
      final collector = PortableAssetCollector(
        imageArtifactStore: imageStore,
        fileArtifactStore: fileStore,
        mediaArtifactStore: mediaStore,
        videoArtifactStore: videoStore,
        model3DArtifactStore: modelStore,
      );

      final result = await collector.collect(
        DocumentAssetManifest(entries: assets),
      );

      expect(result.isComplete, isTrue);
      expect(result.assetBytes['video-1'], orderedEquals(videoBytes));
      expect(result.assetBytes['model-1'], orderedEquals(modelBytes));
      expect(result.assetBytes['media-1'], orderedEquals(mediaBytes));
      expect(await videoStore.exists(video), isTrue);
      expect(await modelStore.exists(model), isTrue);
      expect(await mediaStore.exists(media), isTrue);
    },
  );

  test(
    'export service materializes owned bytes for portable archives',
    () async {
      final now = DateTime.utc(2026, 9, 13);
      final imageStore = MemoryImageArtifactStore();
      final imageBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final imageArtifact = await imageStore.save(
        imageBytes,
        fileName: 'hero.png',
      );
      final asset = DocumentAsset(
        id: 'image-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'hero.png',
        mimeType: 'image/png',
        durableReference: imageArtifact.reference,
        createdAt: now,
        updatedAt: now,
      );
      final document = CanvasDocument(
        projectId: 'portable-project',
        assets: DocumentAssetManifest(entries: {asset.id: asset}),
        updatedAt: now,
      );
      final collector = PortableAssetCollector(
        imageArtifactStore: imageStore,
        fileArtifactStore: MemoryFileArtifactStore(),
        mediaArtifactStore: MemoryMediaArtifactStore(),
        videoArtifactStore: MemoryVideoArtifactStore(),
        model3DArtifactStore: MemoryModel3DArtifactStore(),
      );

      final encoded = await ExportService.exportPortablePackageWithAssets(
        document,
        collector: collector,
      );
      final restored = DocumentPackageArchive.decode(encoded);

      expect(restored.isPortable, isTrue);
      expect(restored.assetBytes['image-1'], orderedEquals(imageBytes));
    },
  );

  test('rejects embedded bytes with a declared-size mismatch', () {
    final asset = DocumentAsset(
      id: 'image-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.embedded,
      name: 'image.png',
      mimeType: 'image/png',
      sizeBytes: validPngBytes.length + 1,
      checksum: DocumentPackageArchiveChecksum.sha256(validPngBytes),
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final document = CanvasDocument(
      projectId: 'size-mismatch',
      assets: DocumentAssetManifest(entries: {asset.id: asset}),
      updatedAt: createdAt,
    );

    expect(
      () => DocumentPackageArchive(
        package: CanvasDocumentPackage(document: document),
        assetBytes: {asset.id: validPngBytes},
      ).encode(),
      throwsA(isA<DocumentPackageArchiveException>()),
    );
  });

  test('rejects embedded bytes with a wrong MIME signature', () {
    final asset = DocumentAsset(
      id: 'image-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.embedded,
      name: 'image.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: validPngBytes.length,
      checksum: DocumentPackageArchiveChecksum.sha256(validPngBytes),
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final document = CanvasDocument(
      projectId: 'mime-mismatch',
      assets: DocumentAssetManifest(entries: {asset.id: asset}),
      updatedAt: createdAt,
    );

    expect(
      () => DocumentPackageArchive(
        package: CanvasDocumentPackage(document: document),
        assetBytes: {asset.id: validPngBytes},
      ).encode(),
      throwsA(isA<DocumentPackageArchiveException>()),
    );
  });

  test('requires a checksum for direct embedded bytes', () {
    final asset = DocumentAsset(
      id: 'image-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.embedded,
      name: 'image.png',
      mimeType: 'image/png',
      sizeBytes: validPngBytes.length,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final document = CanvasDocument(
      projectId: 'checksum-missing',
      assets: DocumentAssetManifest(entries: {asset.id: asset}),
      updatedAt: createdAt,
    );

    expect(
      () => DocumentPackageArchive(
        package: CanvasDocumentPackage(document: document),
        assetBytes: {asset.id: validPngBytes},
      ).encode(),
      throwsA(isA<DocumentPackageArchiveException>()),
    );
  });

  test('portable decode requires a document checksum for embedded bytes', () {
    final asset = DocumentAsset(
      id: 'image-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.embedded,
      name: 'image.png',
      mimeType: 'image/png',
      sizeBytes: validPngBytes.length,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final document = CanvasDocument(
      projectId: 'decode-checksum-missing',
      assets: DocumentAssetManifest(entries: {asset.id: asset}),
      updatedAt: createdAt,
    );
    final source = DocumentPackageArchive(
      package: CanvasDocumentPackage(document: document),
    );
    final manifest = source.toManifestJson()
      ..['portable'] = true
      ..['assets'] = [
        {
          'id': asset.id,
          'name': asset.name,
          'mimeType': asset.mimeType,
          'path': 'assets/aW1hZ2UtMQ',
          'embedded': true,
          'sizeBytes': validPngBytes.length,
          'checksum': DocumentPackageArchiveChecksum.sha256(validPngBytes),
        },
      ];
    final zip = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
      ..addFile(
        ArchiveFile.bytes(
          'document.json',
          utf8.encode(source.package.encode(pretty: false)),
        ),
      )
      ..addFile(ArchiveFile.bytes('assets/aW1hZ2UtMQ', validPngBytes));

    expect(
      () => DocumentPackageArchive.decode(ZipEncoder().encodeBytes(zip)),
      throwsA(isA<DocumentPackageArchiveException>()),
    );
  });

  test(
    'caller-supplied bytes rescue an embedded asset without a reference',
    () {
      final asset = DocumentAsset(
        id: 'image-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.embedded,
        name: 'image.png',
        mimeType: 'image/png',
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final document = CanvasDocument(
        projectId: 'supplied-bytes',
        assets: DocumentAssetManifest(entries: {asset.id: asset}),
        updatedAt: createdAt,
      );

      final encoded = ExportService.exportPortablePackage(
        document,
        assetBytes: {asset.id: validPngBytes},
      );
      final restored = DocumentPackageArchive.decode(encoded);

      expect(restored.isPortable, isTrue);
      expect(restored.assetBytes[asset.id], orderedEquals(validPngBytes));
    },
  );

  test(
    'rejects unknown caller-supplied bytes in collector-backed exports',
    () async {
      final now = DateTime.utc(2026, 9, 13);
      final asset = DocumentAsset(
        id: 'image-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.embedded,
        name: 'image.png',
        mimeType: 'image/png',
        createdAt: now,
        updatedAt: now,
      );
      final document = CanvasDocument(
        projectId: 'unknown-supplied-bytes',
        assets: DocumentAssetManifest(entries: {asset.id: asset}),
        updatedAt: now,
      );
      final collector = PortableAssetCollector(
        imageArtifactStore: MemoryImageArtifactStore(),
        fileArtifactStore: MemoryFileArtifactStore(),
        mediaArtifactStore: MemoryMediaArtifactStore(),
        videoArtifactStore: MemoryVideoArtifactStore(),
        model3DArtifactStore: MemoryModel3DArtifactStore(),
      );

      await expectLater(
        ExportService.exportPortablePackageWithAssets(
          document,
          collector: collector,
          assetBytes: {'unknown': validPngBytes},
        ),
        throwsA(isA<DocumentPackageArchiveException>()),
      );
    },
  );

  test('collects keyed and unkeyed poster dependencies together', () async {
    final now = DateTime.utc(2026, 9, 13);
    final imageStore = MemoryImageArtifactStore();
    final videoStore = MemoryVideoArtifactStore();
    final posterBytes = validPngBytes;
    final videoBytes = minimalMp4();
    final poster = await imageStore.save(posterBytes, fileName: 'poster.png');
    final video = await videoStore.save(videoBytes, fileName: 'clip.mp4');
    final assets = {
      'video-1': DocumentAsset(
        id: 'video-1',
        kind: DocumentAssetKind.video,
        storage: DocumentAssetStorage.local,
        name: 'clip.mp4',
        mimeType: 'video/mp4',
        sizeBytes: videoBytes.length,
        checksum: DocumentPackageArchiveChecksum.sha256(videoBytes),
        durableReference: video.reference,
        createdAt: now,
        updatedAt: now,
      ),
      'poster-1': DocumentAsset(
        id: 'poster-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'poster.png',
        mimeType: 'image/png',
        sizeBytes: posterBytes.length,
        checksum: DocumentPackageArchiveChecksum.sha256(posterBytes),
        durableReference: poster.reference,
        createdAt: now,
        updatedAt: now,
      ),
    };
    final node = CanvasNode(
      id: 'video-node',
      type: NodeType.videoCard,
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      payload: VideoPayload(
        assetId: 'video-1',
        videoArtifactReference: video.reference,
        posterArtifactReference: poster.reference,
      ),
    );
    final collector = PortableAssetCollector(
      imageArtifactStore: imageStore,
      fileArtifactStore: MemoryFileArtifactStore(),
      mediaArtifactStore: MemoryMediaArtifactStore(),
      videoArtifactStore: videoStore,
      model3DArtifactStore: MemoryModel3DArtifactStore(),
    );

    final result = await collector.collect(
      DocumentAssetManifest(entries: assets),
      nodes: [node],
    );

    expect(result.isComplete, isTrue);
    expect(
      result.assetBytes.keys,
      containsAll(<String>['video-1', 'poster-1']),
    );
  });

  test(
    'reports a keyed dependency whose manifest kind or reference disagrees',
    () async {
      final now = DateTime.utc(2026, 9, 13);
      final imageStore = MemoryImageArtifactStore();
      final image = await imageStore.save(validPngBytes, fileName: 'hero.png');
      final asset = DocumentAsset(
        id: 'hero',
        kind: DocumentAssetKind.video,
        storage: DocumentAssetStorage.local,
        name: 'hero.png',
        mimeType: 'image/png',
        durableReference: image.reference,
        createdAt: now,
        updatedAt: now,
      );
      final node = CanvasNode(
        id: 'image-node',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(
          assetId: 'hero',
          imageArtifactReference: image.reference,
        ),
      );
      final collector = PortableAssetCollector(
        imageArtifactStore: imageStore,
        fileArtifactStore: MemoryFileArtifactStore(),
        mediaArtifactStore: MemoryMediaArtifactStore(),
        videoArtifactStore: MemoryVideoArtifactStore(),
        model3DArtifactStore: MemoryModel3DArtifactStore(),
      );

      final result = await collector.collect(
        DocumentAssetManifest(entries: {'hero': asset}),
        nodes: [node],
      );

      expect(result.isComplete, isFalse);
      expect(result.invalidAssetIds, contains('hero'));
    },
  );

  test(
    'direct portable export rejects a node dependency excluded by policy',
    () {
      final asset = DocumentAsset(
        id: 'hero',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.embedded,
        name: 'hero.png',
        mimeType: 'image/png',
        sizeBytes: validPngBytes.length,
        checksum: DocumentPackageArchiveChecksum.sha256(validPngBytes),
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final document = CanvasDocument(
        projectId: 'excluded-dependency',
        nodes: [
          CanvasNode(
            id: 'hero-node',
            type: NodeType.image,
            x: 0,
            y: 0,
            width: 100,
            height: 100,
            payload: ImagePayload(assetId: 'hero'),
          ),
        ],
        assets: DocumentAssetManifest(entries: {'hero': asset}),
        updatedAt: createdAt,
      );

      expect(
        () => ExportService.exportPortablePackage(
          document,
          policy: const AssetExportPolicy(includedAssetIds: {'other'}),
          assetBytes: {'hero': validPngBytes},
        ),
        throwsA(isA<DocumentPackageArchiveException>()),
      );
    },
  );

  test('archive rejects manifest key and asset ID mismatches', () {
    final asset = DocumentAsset(
      id: 'asset-id',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.embedded,
      name: 'image.png',
      mimeType: 'image/png',
      sizeBytes: validPngBytes.length,
      checksum: DocumentPackageArchiveChecksum.sha256(validPngBytes),
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final malformedAssets = DocumentAssetManifest(
      entries: {'manifest-key': asset},
    );
    final package = CanvasDocumentPackage(
      document: CanvasDocument(
        projectId: 'mismatched-manifest',
        assets: malformedAssets,
        updatedAt: createdAt,
      ),
      assets: malformedAssets,
    );
    final archive = DocumentPackageArchive(
      package: package,
      assetBytes: {'asset-id': validPngBytes},
    );

    expect(archive.isPortable, isFalse);
    expect(archive.toManifestJson, throwsFormatException);
    expect(
      () => archive.encode(),
      throwsA(isA<DocumentPackageArchiveException>()),
    );
  });

  test(
    'portable archive decode rejects an embedded payload with wrong MIME',
    () {
      final jpegBytes = Uint8List.fromList([255, 216, 255]);
      final asset = DocumentAsset(
        id: 'image-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.embedded,
        name: 'image.png',
        mimeType: 'image/png',
        sizeBytes: jpegBytes.length,
        checksum: DocumentPackageArchiveChecksum.sha256(jpegBytes),
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final document = CanvasDocument(
        projectId: 'decode-mime-mismatch',
        assets: DocumentAssetManifest(entries: {'image-1': asset}),
        updatedAt: createdAt,
      );
      final source = DocumentPackageArchive(
        package: CanvasDocumentPackage(document: document),
      );
      final manifest = source.toManifestJson()
        ..['portable'] = true
        ..['assets'] = [
          {
            'id': asset.id,
            'name': asset.name,
            'mimeType': asset.mimeType,
            'path': 'assets/aW1hZ2UtMQ',
            'embedded': true,
            'sizeBytes': jpegBytes.length,
            'checksum': DocumentPackageArchiveChecksum.sha256(jpegBytes),
          },
        ];
      final zip = Archive()
        ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
        ..addFile(
          ArchiveFile.bytes(
            'document.json',
            utf8.encode(source.package.encode(pretty: false)),
          ),
        )
        ..addFile(ArchiveFile.bytes('assets/aW1hZ2UtMQ', jpegBytes));

      expect(
        () => DocumentPackageArchive.decode(ZipEncoder().encodeBytes(zip)),
        throwsA(isA<DocumentPackageArchiveException>()),
      );
    },
  );

  test('portable archive decode rejects embedded size metadata drift', () {
    final bytes = validPngBytes;
    final asset = DocumentAsset(
      id: 'image-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.embedded,
      name: 'image.png',
      mimeType: 'image/png',
      sizeBytes: bytes.length + 1,
      checksum: DocumentPackageArchiveChecksum.sha256(bytes),
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final document = CanvasDocument(
      projectId: 'decode-size-mismatch',
      assets: DocumentAssetManifest(entries: {'image-1': asset}),
      updatedAt: createdAt,
    );
    final source = DocumentPackageArchive(
      package: CanvasDocumentPackage(document: document),
    );
    final manifest = source.toManifestJson()
      ..['portable'] = true
      ..['assets'] = [
        {
          'id': asset.id,
          'name': asset.name,
          'mimeType': asset.mimeType,
          'path': 'assets/aW1hZ2UtMQ',
          'embedded': true,
          'sizeBytes': bytes.length,
          'checksum': DocumentPackageArchiveChecksum.sha256(bytes),
        },
      ];
    final zip = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
      ..addFile(
        ArchiveFile.bytes(
          'document.json',
          utf8.encode(source.package.encode(pretty: false)),
        ),
      )
      ..addFile(ArchiveFile.bytes('assets/aW1hZ2UtMQ', bytes));

    expect(
      () => DocumentPackageArchive.decode(ZipEncoder().encodeBytes(zip)),
      throwsA(isA<DocumentPackageArchiveException>()),
    );
  });

  test('portable archive decode rejects a stale portability flag', () {
    final source = createArchive(bytes: {'image-1': validPngBytes});
    final manifest = source.toManifestJson()..['portable'] = false;
    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
      ..addFile(
        ArchiveFile.bytes(
          'document.json',
          utf8.encode(source.package.encode(pretty: false)),
        ),
      )
      ..addFile(ArchiveFile.bytes('assets/aW1hZ2UtMQ', validPngBytes));

    expect(
      () => DocumentPackageArchive.decode(ZipEncoder().encodeBytes(archive)),
      throwsA(isA<DocumentPackageArchiveException>()),
    );
  });

  test('encrypts archives with authenticated password protection', () {
    final source = createArchive(bytes: {'image-1': validPngBytes});
    final encoded = source.encode(password: 'correct horse battery staple');
    final restored = DocumentPackageArchive.decode(
      encoded,
      password: 'correct horse battery staple',
    );

    expect(restored.isPortable, isTrue);
    expect(restored.encrypted, isTrue);
    expect(
      () => DocumentPackageArchive.decode(encoded, password: 'wrong password'),
      throwsA(isA<DocumentPackageArchiveException>()),
    );
  });

  test(
    'reports missing payloads instead of pretending the package is portable',
    () {
      final restored = DocumentPackageArchive.decode(createArchive().encode());

      expect(restored.isPortable, isFalse);
      expect(restored.missingAssetIds, ['image-1']);
    },
  );

  test('rejects embedded bytes that are not paired with a document asset', () {
    final inMemory = createArchive(
      bytes: {
        'unknown': Uint8List.fromList([9]),
      },
    );
    expect(inMemory.isPortable, isFalse);
    expect(
      () => inMemory.encode(),
      throwsA(isA<DocumentPackageArchiveException>()),
    );

    final source = createArchive();
    final zip = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'format': DocumentPackageArchive.format,
            'archiveVersion': DocumentPackageArchive.archiveVersion,
            'document': 'document.json',
            'manifest': 'manifest.json',
            'assets': [
              {
                'id': 'unknown',
                'path': 'assets/dW5rbm93bg',
                'embedded': true,
                'sizeBytes': 1,
                'checksum': DocumentPackageArchiveChecksum.sha256([9]),
              },
            ],
          }),
        ),
      )
      ..addFile(
        ArchiveFile.bytes(
          'document.json',
          utf8.encode(source.package.encode(pretty: false)),
        ),
      )
      ..addFile(ArchiveFile.bytes('assets/dW5rbm93bg', [9]));

    expect(
      () => DocumentPackageArchive.decode(ZipEncoder().encodeBytes(zip)),
      throwsA(isA<DocumentPackageArchiveException>()),
    );
  });

  test(
    'portable export rejects a durable asset whose bytes are unavailable',
    () {
      final now = DateTime.utc(2026, 9, 26);
      final asset = DocumentAsset(
        id: 'missing-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'missing.png',
        mimeType: 'image/png',
        durableReference: 'varian-image://missing-image',
        createdAt: now,
        updatedAt: now,
      );
      final document = CanvasDocument(
        projectId: 'missing-portable-source',
        assets: DocumentAssetManifest(entries: {asset.id: asset}),
        updatedAt: now,
      );

      expect(
        () => ExportService.exportPortablePackage(document),
        throwsA(isA<DocumentPackageArchiveException>()),
      );
    },
  );

  test(
    'collector-backed export rejects unsupported or missing asset sources',
    () async {
      final now = DateTime.utc(2026, 9, 26);
      final asset = DocumentAsset(
        id: 'unsupported-drawing',
        kind: DocumentAssetKind.drawing,
        storage: DocumentAssetStorage.embedded,
        name: 'drawing.vec',
        mimeType: 'application/octet-stream',
        createdAt: now,
        updatedAt: now,
      );
      final document = CanvasDocument(
        projectId: 'unsupported-portable-source',
        assets: DocumentAssetManifest(entries: {asset.id: asset}),
        updatedAt: now,
      );
      final collector = PortableAssetCollector(
        imageArtifactStore: MemoryImageArtifactStore(),
        fileArtifactStore: MemoryFileArtifactStore(),
        mediaArtifactStore: MemoryMediaArtifactStore(),
        videoArtifactStore: MemoryVideoArtifactStore(),
        model3DArtifactStore: MemoryModel3DArtifactStore(),
      );

      await expectLater(
        ExportService.exportPortablePackageWithAssets(
          document,
          policy: const AssetExportPolicy(includeMissingSources: true),
          collector: collector,
        ),
        throwsA(isA<DocumentPackageArchiveException>()),
      );
    },
  );
}
