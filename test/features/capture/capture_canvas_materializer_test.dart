import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/capture/data/capture_canvas_materializer.dart';
import 'package:varian/features/capture/domain/capture_item.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';

void main() {
  final imageBytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/pWQAAAAASUVORK5CYII=',
    ),
  );
  final audioBytes = Uint8List.fromList([
    ...ascii.encode('ID3'),
    4,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);

  CaptureItem capture(
    CaptureKind kind, {
    String? title,
    String? text,
    String? sourceUri,
    String? mimeType,
    String? extension,
    int? byteSize,
  }) => CaptureItem(
    id: 'capture-1',
    kind: kind,
    createdAt: DateTime.utc(2026, 9, 27),
    updatedAt: DateTime.utc(2026, 9, 27),
    title: title,
    text: text,
    sourceUri: sourceUri,
    mimeType: mimeType,
    extension: extension,
    byteSize: byteSize,
    isFavorite: true,
    origin: CaptureOrigin.share,
  );

  test(
    'maps text into an undoable-compatible text node without a manifest',
    () {
      final prepared = prepareCaptureCanvasNode(
        capture: capture(
          CaptureKind.text,
          title: 'Note',
          text: ' Remember this ',
        ),
        center: const Offset(400, 300),
        nodeId: 'node-1',
      );

      expect(prepared.node.type, NodeType.text);
      expect((prepared.node.payload as TextPayload).text, 'Remember this');
      expect(prepared.asset, isNull);
    },
  );

  test('normalizes a valid link into a link card', () {
    final prepared = prepareCaptureCanvasNode(
      capture: capture(
        CaptureKind.link,
        title: 'Reference',
        sourceUri: 'https://example.com/path',
      ),
      center: const Offset(400, 300),
      nodeId: 'node-1',
    );

    expect(prepared.node.type, NodeType.linkCard);
    expect(
      (prepared.node.payload as LinkPayload).url,
      'https://example.com/path',
    );
    expect(prepared.asset, isNull);
  });

  test('rejects an invalid link before it can reach the materializer', () {
    expect(
      () => capture(CaptureKind.link, sourceUri: 'javascript:alert(1)'),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_INVALID_URL',
        ),
      ),
    );
  });

  test(
    'copies image into the owned image store and builds a typed manifest',
    () async {
      final imageStore = MemoryImageArtifactStore();
      final item = capture(
        CaptureKind.screenshot,
        title: 'capture.png',
        mimeType: 'image/png',
        extension: 'png',
        byteSize: imageBytes.length,
      );

      final prepared = await materializeCaptureCanvasNode(
        capture: item,
        center: const Offset(400, 300),
        nodeId: 'node-1',
        bytes: imageBytes,
        imageStore: imageStore,
        fileStore: MemoryFileArtifactStore(),
        mediaStore: MemoryMediaArtifactStore(),
      );

      expect(prepared.node.type, NodeType.image);
      expect(prepared.asset?.id, 'node-1');
      expect(prepared.asset?.kind, DocumentAssetKind.image);
      expect(prepared.asset?.localPath, isNull);
      expect(prepared.asset?.remoteUrl, isNull);
      expect(prepared.asset?.durableReference, startsWith('varian-image://'));
      expect(
        (prepared.node.payload as ImagePayload).imageArtifactReference,
        prepared.asset?.durableReference,
      );
      final hydrated = await imageStore.hydrate(
        prepared.asset!.durableReference!,
        fileName: prepared.asset!.name,
      );
      expect(hydrated, isNotNull);
      expect(await imageStore.read(hydrated!), imageBytes);
      expect(item.origin, CaptureOrigin.share);
      expect(item.isFavorite, isTrue);
    },
  );

  test('copies audio to durable original media storage', () async {
    final mediaStore = MemoryMediaArtifactStore();
    final prepared = await materializeCaptureCanvasNode(
      capture: capture(
        CaptureKind.audio,
        title: 'voice.mp3',
        mimeType: 'audio/mpeg',
        extension: 'mp3',
        byteSize: audioBytes.length,
      ),
      center: Offset.zero,
      nodeId: 'node-1',
      bytes: audioBytes,
      imageStore: MemoryImageArtifactStore(),
      fileStore: MemoryFileArtifactStore(),
      mediaStore: mediaStore,
    );

    expect(prepared.node.type, NodeType.audioCard);
    expect(prepared.asset?.kind, DocumentAssetKind.audio);
    expect(
      mediaStoragePolicyFromReference(prepared.asset!.durableReference!),
      MediaStoragePolicy.durable,
    );
    expect(
      mediaArtifactKindFromReference(prepared.asset!.durableReference!),
      MediaArtifactKind.original,
    );
    final hydrated = await mediaStore.hydrate(
      prepared.asset!.durableReference!,
    );
    expect(hydrated, isNotNull);
    expect(await mediaStore.read(hydrated!), audioBytes);
  });

  test('copies generic files to typed file storage', () async {
    final fileStore = MemoryFileArtifactStore();
    final bytes = Uint8List.fromList(ascii.encode('file contents'));
    final prepared = await materializeCaptureCanvasNode(
      capture: capture(
        CaptureKind.file,
        title: 'notes.txt',
        mimeType: 'text/plain',
        extension: 'txt',
        byteSize: bytes.length,
      ),
      center: Offset.zero,
      nodeId: 'node-1',
      bytes: bytes,
      imageStore: MemoryImageArtifactStore(),
      fileStore: fileStore,
      mediaStore: MemoryMediaArtifactStore(),
    );

    expect(prepared.node.type, NodeType.fileCard);
    expect(prepared.asset?.kind, DocumentAssetKind.document);
    expect(prepared.asset?.durableReference, startsWith('varian-file://'));
    final hydrated = await fileStore.hydrate(prepared.asset!.durableReference!);
    expect(hydrated, isNotNull);
    expect(await fileStore.read(hydrated!), bytes);
  });

  test(
    'rejects missing and corrupt binary bytes without publishing a result',
    () async {
      final args = (
        imageStore: MemoryImageArtifactStore(),
        fileStore: MemoryFileArtifactStore(),
        mediaStore: MemoryMediaArtifactStore(),
      );
      final image = capture(
        CaptureKind.image,
        title: 'capture.png',
        mimeType: 'image/png',
        extension: 'png',
      );

      for (final bytes in <Uint8List?>[
        null,
        Uint8List.fromList([1, 2, 3]),
      ]) {
        await expectLater(
          materializeCaptureCanvasNode(
            capture: image,
            center: Offset.zero,
            nodeId: 'node-1',
            bytes: bytes,
            imageStore: args.imageStore,
            fileStore: args.fileStore,
            mediaStore: args.mediaStore,
          ),
          throwsA(isA<CaptureCanvasMaterializationException>()),
        );
      }
    },
  );

  test('rejects empty text and missing binary references', () {
    expect(
      () => prepareCaptureCanvasNode(
        capture: capture(CaptureKind.text, text: '  '),
        center: Offset.zero,
        nodeId: 'node-1',
      ),
      throwsA(isA<CaptureCanvasMaterializationException>()),
    );
    expect(
      () => prepareCaptureCanvasNode(
        capture: capture(CaptureKind.file, title: 'notes.txt'),
        center: Offset.zero,
        nodeId: 'node-1',
        bytes: Uint8List.fromList([1]),
      ),
      throwsA(isA<CaptureCanvasMaterializationException>()),
    );
  });
}
