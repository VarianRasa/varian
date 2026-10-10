import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/document_package.dart';
import 'package:varian/domain/models/document_package_archive.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_presets.dart';
import 'package:varian/features/export/export_service.dart';
import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/features/import/import_service.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store_types.dart';

void main() {
  test('drops Draw.io edges whose endpoints are not imported nodes', () {
    const xml =
        '''<mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="v1" value="A" vertex="1" parent="1"><mxGeometry x="0" y="0" width="100" height="60" as="geometry"/></mxCell><mxCell id="e1" edge="1" source="v1" target="missing" parent="1"/></root></mxGraphModel>''';

    final result = ImportService.importFromDrawioXml(xml);

    expect(result.isSuccess, isFalse);
    expect(result.nodes, isEmpty);
    expect(result.edges, isEmpty);
    expect(result.error, contains('unknown target node'));
  });

  test('imports image bundle ZIP entries as embedded image assets', () {
    final source = Archive()
      ..addFile(ArchiveFile.bytes('images/hero.png', [1, 2, 3]))
      ..addFile(ArchiveFile.bytes('images/notes.txt', [4, 5]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(source));

    final result = ImportService.importFromImageBundle(bytes);

    expect(result.isSuccess, isTrue);
    expect(result.nodes, hasLength(1));
    expect(result.assets.items, hasLength(1));
    final asset = result.assets.items.single;
    expect(asset.durableReference, isNull);
    expect(result.transientAssetBytes[asset.id], [1, 2, 3]);
    expect(result.lossReport?.unsupported, contains('images/notes.txt'));
  });

  test(
    'image bundle materialization replaces transient bytes with an opaque reference',
    () async {
      final source = Archive()
        ..addFile(
          ArchiveFile.bytes('hero.png', [137, 80, 78, 71, 13, 10, 26, 10]),
        );
      final result = ImportService.importFromImageBundle(
        Uint8List.fromList(ZipEncoder().encode(source)),
      );
      final materialized = await result.materializeArtifacts(
        artifactStoreBundle: ArtifactStoreBundle(
          imageArtifactStore: MemoryImageArtifactStore(),
          fileArtifactStore: MemoryFileArtifactStore(),
        ),
      );
      final asset = materialized.assets.items.single;

      expect(materialized.transientAssetBytes, isEmpty);
      expect(asset.durableReference, startsWith('varian-image://'));
      expect(
        materialized.nodes.single.payload
            .toPersistenceJson()['imageArtifactReference'],
        startsWith('varian-image://'),
      );
    },
  );

  test('materializes an image artifact nested in a board payload', () async {
    final now = DateTime.utc(2026, 9, 26);
    final imageBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
    final asset = DocumentAsset(
      id: 'nested-image',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.embedded,
      name: 'nested.png',
      mimeType: 'image/png',
      sizeBytes: imageBytes.length,
      createdAt: now,
      updatedAt: now,
    );
    final nestedImage = CanvasNode(
      id: 'nested-image-node',
      type: NodeType.image,
      x: 10,
      y: 20,
      width: 120,
      height: 90,
      payload: ImagePayload(
        assetId: asset.id,
        localPath: 'transient/nested.png',
        url: 'https://example.invalid/nested.png',
      ),
    );
    final board = CanvasNode(
      id: 'nested-board-node',
      type: NodeType.nestedBoard,
      x: 0,
      y: 0,
      width: 400,
      height: 300,
      payload: NestedBoardPayload(subNodes: [nestedImage]),
    );

    final materialized =
        await ImportResult(
          nodes: [board],
          assets: DocumentAssetManifest(entries: {asset.id: asset}),
          transientAssetBytes: {asset.id: imageBytes},
        ).materializeArtifacts(
          artifactStoreBundle: ArtifactStoreBundle(
            imageArtifactStore: MemoryImageArtifactStore(),
            fileArtifactStore: MemoryFileArtifactStore(),
          ),
        );

    final child = (materialized.nodes.single.payload as NestedBoardPayload)
        .subNodes
        .single;
    final childPayload = child.payload as ImagePayload;
    expect(materialized.transientAssetBytes, isEmpty);
    expect(childPayload.imageArtifactReference, startsWith('varian-image://'));
    expect(childPayload.localPath, isNull);
    expect(childPayload.url, isNull);
  });

  test(
    'portable archive materialization hydrates embedded image bytes into the linked node',
    () async {
      final now = DateTime.utc(2026, 9, 24);
      final imageBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final asset = DocumentAsset(
        id: 'archive-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.embedded,
        name: 'archive.png',
        mimeType: 'image/png',
        sizeBytes: imageBytes.length,
        checksum: DocumentPackageArchiveChecksum.sha256(imageBytes),
        createdAt: now,
        updatedAt: now,
      );
      final node = CanvasNode(
        id: 'archive-image-node',
        type: NodeType.image,
        x: 80,
        y: 80,
        width: 220,
        height: 180,
        payload: ImagePayload(assetId: asset.id),
      );
      final archive = DocumentPackageArchive(
        package: CanvasDocumentPackage(
          document: CanvasDocument(
            projectId: 'archive-materialization-project',
            nodes: [node],
            assets: DocumentAssetManifest(entries: {asset.id: asset}),
            updatedAt: now,
          ),
        ),
        assetBytes: {asset.id: imageBytes},
      );

      final imported = ImportService.importFromFileBytes(
        fileName: 'archive.varian',
        bytes: archive.encode(),
      );
      expect(imported.isSuccess, isTrue);
      expect(imported.transientAssetBytes[asset.id], orderedEquals(imageBytes));

      final materialized = await imported.materializeArtifacts(
        artifactStoreBundle: ArtifactStoreBundle(
          imageArtifactStore: MemoryImageArtifactStore(),
          fileArtifactStore: MemoryFileArtifactStore(),
        ),
      );
      final materializedAsset = materialized.assets[asset.id]!;
      final materializedNode = materialized.nodes.single;

      expect(materialized.transientAssetBytes, isEmpty);
      expect(materializedAsset.durableReference, startsWith('varian-image://'));
      expect(
        (materializedNode.payload as ImagePayload).imageArtifactReference,
        materializedAsset.durableReference,
      );
    },
  );

  test(
    'materializes each supported imported artifact kind through its store',
    () async {
      final now = DateTime.utc(2026, 9, 25);
      final modelBytes = Uint8List.fromList([
        0x67,
        0x6C,
        0x54,
        0x46,
        0x02,
        0x00,
        0x00,
        0x00,
        0x18,
        0x00,
        0x00,
        0x00,
        0x04,
        0x00,
        0x00,
        0x00,
        0x4A,
        0x53,
        0x4F,
        0x4E,
        0x7B,
        0x7D,
        0x20,
        0x20,
      ]);
      final assets = DocumentAssetManifest(
        entries: {
          'audio-asset': DocumentAsset(
            id: 'audio-asset',
            kind: DocumentAssetKind.audio,
            storage: DocumentAssetStorage.embedded,
            name: 'voice.mp3',
            mimeType: 'audio/mpeg',
            sizeBytes: 4,
            createdAt: now,
            updatedAt: now,
          ),
          'video-asset': DocumentAsset(
            id: 'video-asset',
            kind: DocumentAssetKind.video,
            storage: DocumentAssetStorage.embedded,
            name: 'clip.mp4',
            mimeType: 'video/mp4',
            sizeBytes: 16,
            createdAt: now,
            updatedAt: now,
          ),
          'model-asset': DocumentAsset(
            id: 'model-asset',
            kind: DocumentAssetKind.model3d,
            storage: DocumentAssetStorage.embedded,
            name: 'chair.glb',
            mimeType: 'model/gltf-binary',
            sizeBytes: modelBytes.length,
            createdAt: now,
            updatedAt: now,
          ),
        },
      );
      final result = ImportResult(
        assets: assets,
        nodes: [
          CanvasNode(
            id: 'audio-node',
            type: NodeType.audioCard,
            x: 0,
            y: 0,
            width: 100,
            height: 50,
            payload: AudioPayload(assetId: 'audio-asset'),
          ),
          CanvasNode(
            id: 'video-node',
            type: NodeType.videoCard,
            x: 0,
            y: 0,
            width: 100,
            height: 50,
            payload: VideoPayload(assetId: 'video-asset'),
          ),
          CanvasNode(
            id: 'model-node',
            type: NodeType.model3d,
            x: 0,
            y: 0,
            width: 100,
            height: 50,
            payload: Model3DPayload(assetId: 'model-asset'),
          ),
        ],
        transientAssetBytes: {
          'audio-asset': Uint8List.fromList([1, 2, 3, 4]),
          'video-asset': Uint8List.fromList([
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
            0x6F,
            0x6D,
            0,
            0,
            0,
            0,
          ]),
          'model-asset': modelBytes,
        },
      );

      final materialized = await result.materializeArtifacts(
        artifactStoreBundle: ArtifactStoreBundle(
          imageArtifactStore: MemoryImageArtifactStore(),
          fileArtifactStore: MemoryFileArtifactStore(),
          mediaArtifactStore: MemoryMediaArtifactStore(),
          videoArtifactStore: MemoryVideoArtifactStore(),
          model3DArtifactStore: MemoryModel3DArtifactStore(),
        ),
      );

      expect(materialized.transientAssetBytes, isEmpty);
      expect(
        materialized.assets['audio-asset']!.durableReference,
        startsWith('varian-media://'),
      );
      expect(
        materialized.assets['video-asset']!.durableReference,
        startsWith('varian-video://'),
      );
      expect(
        materialized.assets['model-asset']!.durableReference,
        startsWith('varian-model3d://'),
      );
      expect(
        (materialized.nodes[0].payload as AudioPayload).audioArtifactReference,
        startsWith('varian-media://'),
      );
      expect(
        (materialized.nodes[1].payload as VideoPayload).videoArtifactReference,
        startsWith('varian-video://'),
      );
      expect(
        (materialized.nodes[2].payload as Model3DPayload).artifactReference,
        startsWith('varian-model3d://'),
      );
    },
  );

  test(
    'rewrites a video poster reference after materializing its image asset',
    () async {
      final now = DateTime.utc(2026, 9, 26);
      const oldVideoReference = 'varian-video://video-old-ref';
      const oldPosterReference = 'varian-image://poster-old-ref';
      final videoBytes = Uint8List.fromList([
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
      final posterBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final videoAsset = DocumentAsset(
        id: 'video-asset',
        kind: DocumentAssetKind.video,
        storage: DocumentAssetStorage.local,
        name: 'clip.mp4',
        mimeType: 'video/mp4',
        durableReference: oldVideoReference,
        createdAt: now,
        updatedAt: now,
      );
      final posterAsset = DocumentAsset(
        id: 'poster-asset',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'poster.png',
        mimeType: 'image/png',
        durableReference: oldPosterReference,
        createdAt: now,
        updatedAt: now,
      );
      final result = ImportResult(
        nodes: [
          CanvasNode(
            id: 'video-node',
            type: NodeType.videoCard,
            x: 0,
            y: 0,
            width: 120,
            height: 80,
            payload: VideoPayload(
              assetId: 'video-asset',
              posterArtifactReference: oldPosterReference,
            ),
          ),
        ],
        assets: DocumentAssetManifest(
          entries: {videoAsset.id: videoAsset, posterAsset.id: posterAsset},
        ),
        transientAssetBytes: {
          videoAsset.id: videoBytes,
          posterAsset.id: posterBytes,
        },
      );
      final materialized = await result.materializeArtifacts(
        artifactStoreBundle: ArtifactStoreBundle(
          imageArtifactStore: MemoryImageArtifactStore(),
          videoArtifactStore: MemoryVideoArtifactStore(),
        ),
      );

      final payload = materialized.nodes.single.payload as VideoPayload;
      final posterReference =
          materialized.assets[posterAsset.id]!.durableReference;
      expect(posterReference, isNot(oldPosterReference));
      expect(payload.posterArtifactReference, posterReference);
      expect(payload.posterArtifactReference, startsWith('varian-image://'));
    },
  );

  test(
    'rewrites media timeline references after materializing the source asset',
    () async {
      final now = DateTime.utc(2026, 9, 26);
      const oldReference =
          'varian-media://durable/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/proxy';
      final audioAsset = DocumentAsset(
        id: 'audio-asset',
        kind: DocumentAssetKind.audio,
        storage: DocumentAssetStorage.local,
        name: 'voice.mp3',
        mimeType: 'audio/mpeg',
        durableReference: oldReference,
        createdAt: now,
        updatedAt: now,
      );
      final result = ImportResult(
        nodes: [
          CanvasNode(
            id: 'audio-node',
            type: NodeType.audioCard,
            x: 0,
            y: 0,
            width: 120,
            height: 80,
            payload: AudioPayload(
              assetId: audioAsset.id,
              mediaTimeline: const MediaTimeline(
                artifacts: MediaArtifactManifest(
                  items: [
                    MediaArtifact(
                      kind: MediaArtifactKind.proxy,
                      reference: oldReference,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        assets: DocumentAssetManifest(entries: {audioAsset.id: audioAsset}),
        transientAssetBytes: {
          audioAsset.id: Uint8List.fromList([1, 2, 3, 4]),
        },
      );
      final materialized = await result.materializeArtifacts(
        artifactStoreBundle: ArtifactStoreBundle(
          mediaArtifactStore: MemoryMediaArtifactStore(),
        ),
      );

      final payload = materialized.nodes.single.payload as AudioPayload;
      final timelineReference =
          payload.mediaTimeline!.artifacts.items.single.reference;
      final sourceReference =
          materialized.assets[audioAsset.id]!.durableReference;
      expect(sourceReference, isNot(oldReference));
      expect(timelineReference, sourceReference);
      expect(timelineReference, startsWith('varian-media://durable/'));
    },
  );

  test(
    'portable archive is exposed through export preset and import service',
    () async {
      final document = CanvasDocument(
        projectId: 'preset-project',
        updatedAt: DateTime.utc(2026, 9, 13),
      );
      final presetResult = await ExportPresetRegistry.portablePackage.export(
        document,
      );

      expect(presetResult?.isBinary, isTrue);
      final imported = ImportService.importFromFileBytes(
        fileName: 'preset.varian',
        bytes: presetResult!.data,
      );

      expect(imported.isSuccess, isTrue);
      expect(imported.packageArchive, isA<DocumentPackageArchive>());
      expect(
        imported.packageArchive!.package.document.projectId,
        'preset-project',
      );
    },
  );

  test('rejects a non-portable archive before materialization', () {
    final now = DateTime.utc(2026, 9, 26);
    final asset = DocumentAsset(
      id: 'missing-image',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.embedded,
      name: 'missing.png',
      mimeType: 'image/png',
      sizeBytes: 8,
      checksum: 'a' * 64,
      createdAt: now,
      updatedAt: now,
    );
    final manifest = DocumentAssetManifest(entries: {asset.id: asset});
    final node = CanvasNode(
      id: 'missing-image-node',
      type: NodeType.image,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: ImagePayload(assetId: asset.id),
    );
    final archive = DocumentPackageArchive(
      package: CanvasDocumentPackage(
        document: CanvasDocument(
          projectId: 'non-portable-archive-test',
          nodes: [node],
          assets: manifest,
          updatedAt: now,
        ),
        assets: manifest,
      ),
    );

    final imported = ImportService.importFromFileBytes(
      fileName: 'non-portable.varian',
      bytes: archive.encode(),
    );

    expect(imported.packageArchive, isNotNull);
    expect(imported.packageArchive!.isPortable, isFalse);
    expect(imported.isSuccess, isFalse);
    expect(imported.error, contains('portable'));
  });

  test('portable export honors the asset policy before archiving', () {
    final document = CanvasDocument(
      projectId: 'policy-project',
      updatedAt: DateTime.utc(2026, 9, 13),
    );

    final bytes = ExportService.exportPortablePackage(document);

    expect(bytes, isNotEmpty);
  });

  test(
    'materializes image mask references and clears runtime delivery fields',
    () async {
      final now = DateTime.utc(2026, 9, 26);
      final asset = DocumentAsset(
        id: 'mask-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.embedded,
        name: 'mask.png',
        mimeType: 'image/png',
        sizeBytes: 8,
        createdAt: now,
        updatedAt: now,
      );
      final node = CanvasNode(
        id: 'masked-image-node',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(
          backgroundMask: ImageMask(
            assetId: asset.id,
            localPath: 'runtime/mask.png',
            url: 'https://example.invalid/mask.png',
          ),
        ),
      );

      final materialized =
          await ImportResult(
            nodes: [node],
            assets: DocumentAssetManifest(entries: {asset.id: asset}),
            transientAssetBytes: {
              asset.id: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
            },
          ).materializeArtifacts(
            artifactStoreBundle: ArtifactStoreBundle(
              imageArtifactStore: MemoryImageArtifactStore(),
            ),
          );

      final mask =
          (materialized.nodes.single.payload as ImagePayload).backgroundMask!;
      expect(mask.imageArtifactReference, startsWith('varian-image://'));
      expect(mask.localPath, isNull);
      expect(mask.url, isNull);
    },
  );

  test(
    'materializes annotated image references and clears runtime path',
    () async {
      final now = DateTime.utc(2026, 9, 26);
      final asset = DocumentAsset(
        id: 'annotated-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.embedded,
        name: 'annotated.png',
        mimeType: 'image/png',
        sizeBytes: 4,
        createdAt: now,
        updatedAt: now,
      );
      final node = CanvasNode(
        id: 'annotated-image-node',
        type: NodeType.annotatedImage,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: AnnotatedImagePayload(
          assetId: asset.id,
          imagePath: 'runtime/annotated.png',
        ),
      );

      final materialized =
          await ImportResult(
            nodes: [node],
            assets: DocumentAssetManifest(entries: {asset.id: asset}),
            transientAssetBytes: {
              asset.id: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
            },
          ).materializeArtifacts(
            artifactStoreBundle: ArtifactStoreBundle(
              imageArtifactStore: MemoryImageArtifactStore(),
            ),
          );

      final payload =
          materialized.nodes.single.payload as AnnotatedImagePayload;
      expect(payload.imageArtifactReference, startsWith('varian-image://'));
      expect(payload.imagePath, isNull);
    },
  );

  test('materializes transient file bytes nested in a board payload', () async {
    final child = CanvasNode(
      id: 'nested-file-node',
      type: NodeType.fileCard,
      x: 0,
      y: 0,
      width: 100,
      height: 80,
      payload: FilePayload(
        assetId: 'nested-file-asset',
        fileName: 'nested.txt',
        fileExtension: 'TXT',
      ),
    );
    final board = CanvasNode(
      id: 'nested-file-board',
      type: NodeType.nestedBoard,
      x: 0,
      y: 0,
      width: 300,
      height: 200,
      payload: NestedBoardPayload(subNodes: [child]),
    );

    final materialized =
        await ImportResult(
          nodes: [board],
          transientPayloadBytes: {
            child.id: Uint8List.fromList([9, 8, 7]),
          },
        ).materializeArtifacts(
          artifactStoreBundle: ArtifactStoreBundle(
            fileArtifactStore: MemoryFileArtifactStore(),
          ),
        );

    final nestedChild =
        (materialized.nodes.single.payload as NestedBoardPayload)
            .subNodes
            .single;
    final payload = nestedChild.payload as FilePayload;
    expect(materialized.transientPayloadBytes, isEmpty);
    expect(payload.artifactReference, startsWith('varian-file://'));
    expect(payload.localPath, isNull);
    expect(payload.base64Data, isNull);
    expect(payload.remoteUrl, isNull);
    expect(materialized.assets[payload.assetId!], isNotNull);
  });

  test('materializes transient media timeline artifacts', () async {
    const oldReference =
        'varian-media://durable/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/proxy';
    final node = CanvasNode(
      id: 'timeline-audio-node',
      type: NodeType.audioCard,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: AudioPayload(
        mediaTimeline: const MediaTimeline(
          artifacts: MediaArtifactManifest(
            items: [
              MediaArtifact(
                kind: MediaArtifactKind.proxy,
                path: r'C:\\runtime\\proxy',
                url: 'blob:runtime-proxy',
                reference: oldReference,
                mimeType: 'audio/mpeg',
              ),
            ],
          ),
        ),
      ),
    );
    final materialized =
        await ImportResult(
          nodes: [node],
          transientMediaArtifactBytes: {
            oldReference: Uint8List.fromList([1, 2, 3, 4]),
          },
        ).materializeArtifacts(
          artifactStoreBundle: ArtifactStoreBundle(
            mediaArtifactStore: MemoryMediaArtifactStore(),
          ),
        );

    final timeline =
        (materialized.nodes.single.payload as AudioPayload).mediaTimeline!;
    final artifact = timeline.artifacts.items.single;
    expect(materialized.transientMediaArtifactBytes, isEmpty);
    expect(artifact.reference, startsWith('varian-media://durable/'));
    expect(artifact.reference, isNot(oldReference));
    expect(artifact.path, isNull);
    expect(artifact.url, isNull);
  });

  test('materializes embedded document assets through the file store', () async {
    final now = DateTime.utc(2026, 9, 26);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final asset = DocumentAsset(
      id: 'document-asset',
      kind: DocumentAssetKind.document,
      storage: DocumentAssetStorage.embedded,
      name: 'brief.docx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      sizeBytes: bytes.length,
      createdAt: now,
      updatedAt: now,
    );
    final node = CanvasNode(
      id: 'document-node',
      type: NodeType.fileCard,
      x: 0,
      y: 0,
      width: 200,
      height: 120,
      payload: FilePayload(
        assetId: asset.id,
        fileName: asset.name,
        fileExtension: 'DOCX',
        localPath: 'runtime/brief.docx',
        base64Data: 'AQIDBA==',
        remoteUrl: 'https://example.invalid/brief.docx',
      ),
    );

    final materialized =
        await ImportResult(
          nodes: [node],
          assets: DocumentAssetManifest(entries: {asset.id: asset}),
          transientAssetBytes: {asset.id: bytes},
        ).materializeArtifacts(
          artifactStoreBundle: ArtifactStoreBundle(
            fileArtifactStore: MemoryFileArtifactStore(),
          ),
        );

    final payload = materialized.nodes.single.payload as FilePayload;
    expect(materialized.transientAssetBytes, isEmpty);
    expect(
      materialized.assets[asset.id]!.durableReference,
      startsWith('varian-file://'),
    );
    expect(
      payload.artifactReference,
      materialized.assets[asset.id]!.durableReference,
    );
    expect(payload.localPath, isNull);
    expect(payload.base64Data, isNull);
    expect(payload.remoteUrl, isNull);
  });

  test(
    'rewrites unkeyed durable references in nested component children',
    () async {
      final now = DateTime.utc(2026, 9, 26);
      const oldReference = 'varian-image://oldnestedasset';
      final asset = DocumentAsset(
        id: 'nested-component-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.embedded,
        name: 'nested.png',
        mimeType: 'image/png',
        durableReference: oldReference,
        sizeBytes: 8,
        createdAt: now,
        updatedAt: now,
      );
      final child = CanvasNode(
        id: 'unkeyed-nested-image',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 80,
        height: 80,
        payload: ImagePayload(imageArtifactReference: oldReference),
      );
      final component = CanvasNode(
        id: 'component-with-unkeyed-reference',
        type: NodeType.component,
        x: 0,
        y: 0,
        width: 200,
        height: 160,
        payload: ComponentPayload(
          masterComponentId: 'master',
          componentName: 'Nested image component',
          templateChildren: [child],
        ),
      );

      final materialized =
          await ImportResult(
            nodes: [component],
            assets: DocumentAssetManifest(entries: {asset.id: asset}),
            transientAssetBytes: {
              asset.id: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
            },
          ).materializeArtifacts(
            artifactStoreBundle: ArtifactStoreBundle(
              imageArtifactStore: MemoryImageArtifactStore(),
            ),
          );

      final nestedPayload =
          (materialized.nodes.single.payload as ComponentPayload)
                  .templateChildren
                  .single
                  .payload
              as ImagePayload;
      final nextReference = materialized.assets[asset.id]!.durableReference;
      expect(nextReference, isNot(oldReference));
      expect(nestedPayload.imageArtifactReference, nextReference);
    },
  );
}
