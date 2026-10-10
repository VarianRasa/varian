import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/artifacts/transient_artifact_hydrator.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store_types.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';
import 'package:varian/domain/models/media_timeline.dart';

void main() {
  test(
    'hydrates opaque local artifacts without mutating durable document',
    () async {
      final imageStore = MemoryImageArtifactStore();
      final videoStore = MemoryVideoArtifactStore();
      final modelStore = MemoryModel3DArtifactStore();
      final image = await imageStore.save(_pngBytes());
      final video = await videoStore.save(_mp4Bytes());
      final model = await modelStore.save(_minimalGlb());
      final document = CanvasDocument(
        projectId: 'project-a',
        updatedAt: DateTime.utc(2026, 9, 24),
        nodes: [
          _node('image', ImagePayload(imageArtifactReference: image.reference)),
          _node('video', VideoPayload(videoArtifactReference: video.reference)),
          _node('model', Model3DPayload(artifactReference: model.reference)),
        ],
      );
      final durableBefore = document.toPersistenceJson();

      final hydrated = await TransientArtifactHydrator(
        imageArtifactStore: imageStore,
        videoArtifactStore: videoStore,
        model3DArtifactStore: modelStore,
      ).hydrate(document, projectId: 'project-a');

      expect(document.toPersistenceJson(), durableBefore);
      expect(hydrated.nodes[0].payload, isA<ImagePayload>());
      expect((hydrated.nodes[0].payload as ImagePayload).localPath, isNull);
      expect((hydrated.nodes[0].payload as ImagePayload).url, isNull);
      expect(
        (hydrated.nodes[1].payload as VideoPayload).videoPath ??
            (hydrated.nodes[1].payload as VideoPayload).videoUrl,
        isNotNull,
      );
      expect(
        (hydrated.nodes[2].payload as Model3DPayload).modelPath ??
            (hydrated.nodes[2].payload as Model3DPayload).modelUrl,
        isNotNull,
      );
      expect(hydrated.toPersistenceJson(), durableBefore);
    },
  );

  test(
    'hydrates a file artifact reference through the file artifact store',
    () async {
      final fileStore = _RecordingFileArtifactStore();
      final document = CanvasDocument(
        projectId: 'project-file',
        updatedAt: DateTime.utc(2026, 9, 26),
        nodes: [
          _node(
            'file',
            FilePayload(
              fileName: 'notes.txt',
              fileExtension: 'TXT',
              artifactReference: 'varian-file://hydrated',
            ),
          ),
        ],
      );

      final hydrated = await TransientArtifactHydrator(
        fileArtifactStore: fileStore,
      ).hydrate(document, projectId: 'project-file');

      final payload = hydrated.nodes.single.payload as FilePayload;
      expect(fileStore.hydrateCalled, isTrue);
      expect(payload.artifactReference, 'varian-file://hydrated');
      expect(payload.localPath, 'memory://notes.txt');
      expect(payload.base64Data, isNull);
    },
  );

  test(
    'hydrates a file Storage path through the file artifact store',
    () async {
      final fileStore = _RecordingFileArtifactStore();
      final document = CanvasDocument(
        projectId: 'project-file-storage',
        updatedAt: DateTime.utc(2026, 9, 26),
        nodes: [
          _node(
            'file',
            FilePayload(
              fileName: 'notes.txt',
              fileExtension: 'TXT',
              storagePath: 'project-file-storage/files/notes.txt',
            ),
          ),
        ],
      );

      final hydrated = await TransientArtifactHydrator(
        fileArtifactStore: fileStore,
        storageByteReader:
            ({
              required projectId,
              required path,
              accountId,
              required maxBytes,
            }) async {
              expect(projectId, 'project-file-storage');
              expect(path, 'project-file-storage/files/notes.txt');
              return Uint8List.fromList([1, 2, 3]);
            },
      ).hydrate(document, projectId: 'project-file-storage');

      final payload = hydrated.nodes.single.payload as FilePayload;
      expect(fileStore.saveCalled, isTrue);
      expect(payload.artifactReference, 'varian-file://saved-artifact');
      expect(payload.localPath, 'memory://notes.txt');
      expect(payload.base64Data, isNull);
    },
  );

  test(
    'hydrates an audio artifact reference through the media artifact store',
    () async {
      final mediaStore = MemoryMediaArtifactStore();
      final bytes = Uint8List.fromList([1, 2, 3]);
      final reference = mediaArtifactReference(
        MediaStoragePolicy.durable,
        mediaArtifactChecksum(bytes),
        MediaArtifactKind.original,
      );
      await mediaStore.save(
        bytes,
        kind: MediaArtifactKind.original,
        mimeType: 'audio/mpeg',
        checksum: mediaArtifactChecksum(bytes),
        fileName: 'voice.mp3',
        storagePolicy: MediaStoragePolicy.durable,
      );
      final document = CanvasDocument(
        projectId: 'project-audio',
        updatedAt: DateTime.utc(2026, 9, 26),
        nodes: [
          _node('audio', AudioPayload(audioArtifactReference: reference)),
        ],
      );

      final hydrated = await TransientArtifactHydrator(
        mediaArtifactStore: mediaStore,
      ).hydrate(document, projectId: 'project-audio');

      final payload = hydrated.nodes.single.payload as AudioPayload;
      expect(payload.audioArtifactReference, reference);
      expect(payload.audioPath ?? payload.audioUrl, isNotNull);
    },
  );

  test('project fence returns the original durable document', () async {
    final document = CanvasDocument(
      projectId: 'project-a',
      updatedAt: DateTime.utc(2026, 9, 24),
    );
    final hydrated = await TransientArtifactHydrator().hydrate(
      document,
      projectId: 'project-b',
    );
    expect(identical(hydrated, document), isTrue);
  });
}

class _RecordingFileArtifactStore implements FileArtifactStore {
  bool hydrateCalled = false;
  bool saveCalled = false;

  @override
  Future<FileArtifact> save(
    Uint8List bytes, {
    String fileName = 'document.bin',
  }) async {
    saveCalled = true;
    return FileArtifact(
      path: 'memory://$fileName',
      reference: 'varian-file://saved-artifact',
      fileName: fileName,
    );
  }

  @override
  Future<FileArtifact?> hydrate(String reference, {String? fileName}) async {
    hydrateCalled = true;
    return FileArtifact(
      path: 'memory://${fileName ?? 'document.bin'}',
      reference: reference,
      fileName: fileName ?? 'document.bin',
    );
  }

  @override
  Future<bool> exists(FileArtifact artifact) async => true;

  @override
  Future<Uint8List?> read(FileArtifact artifact) async =>
      Uint8List.fromList([1]);

  @override
  Future<void> dispose(FileArtifact artifact) async {}
}

CanvasNode _node(String id, NodePayload payload) => CanvasNode(
  id: id,
  type: switch (payload) {
    ImagePayload() => NodeType.image,
    VideoPayload() => NodeType.videoCard,
    Model3DPayload() => NodeType.model3d,
    _ => NodeType.rectangle,
  },
  x: 0,
  y: 0,
  width: 100,
  height: 100,
  payload: payload,
);

Uint8List _pngBytes() => Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0,
  0,
  0,
  0,
]);

Uint8List _mp4Bytes() => Uint8List.fromList([
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
  0,
  0,
  0,
  0,
  0x69,
  0x73,
  0x6f,
  0x6d,
  0,
  0,
  0,
  0,
]);

Uint8List _minimalGlb() => Uint8List.fromList([
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
