import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:varian/data/remote/supabase_storage_path_resolver.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('memory image artifacts are hydrated by opaque reference', () async {
    final store = MemoryImageArtifactStore();
    final artifact = await store.save(
      Uint8List.fromList(_pngBytes),
      fileName: 'fixture.png',
    );
    final cache = CanvasImageCache.scoped(imageArtifactStore: store);
    addTearDown(cache.dispose);

    final bytes = await cache.loadImageBytes(
      imageArtifactReference: artifact.reference,
    );

    expect(bytes, _pngBytes);
  });

  test('rendering a generated artifact caches its decoded image', () async {
    final source = await _solidImage(Colors.red);
    final byteData = await source.toByteData(format: ui.ImageByteFormat.png);
    source.dispose();
    final bytes = byteData!.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final store = MemoryImageArtifactStore();
    final artifact = await store.save(bytes, fileName: 'generated.png');
    final cache = CanvasImageCache.scoped(imageArtifactStore: store);
    addTearDown(cache.dispose);

    expect(
      await cache.loadImageBytes(imageArtifactReference: artifact.reference),
      bytes,
    );
    final node = CanvasNode(
      id: 'generated-artifact',
      type: NodeType.image,
      x: 0,
      y: 0,
      width: 8,
      height: 8,
      payload: ImagePayload(imageArtifactReference: artifact.reference),
    );
    final loadingRecorder = ui.PictureRecorder();
    NodePainter.paint(Canvas(loadingRecorder), node, imageCache: cache);
    loadingRecorder.endRecording().dispose();
    await pumpEventQueue();

    final renderedRecorder = ui.PictureRecorder();
    NodePainter.paint(Canvas(renderedRecorder), node, imageCache: cache);
    final picture = renderedRecorder.endRecording();
    final rendered = await picture.toImage(8, 8);
    final raw = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(
      [
        raw!.getUint8((4 * 8 + 4) * 4),
        raw.getUint8((4 * 8 + 4) * 4 + 1),
        raw.getUint8((4 * 8 + 4) * 4 + 2),
        raw.getUint8((4 * 8 + 4) * 4 + 3),
      ],
      [244, 67, 54, 255],
    );
    rendered.dispose();
    picture.dispose();
  });

  test(
    'a scoped cache can adopt a shared image artifact store after construction',
    () async {
      final store = MemoryImageArtifactStore();
      final artifact = await store.save(
        Uint8List.fromList(_pngBytes),
        fileName: 'shared.png',
      );
      final cache = CanvasImageCache.scoped();
      addTearDown(cache.dispose);

      cache.configureArtifactStore(store);

      expect(
        await cache.loadImageBytes(imageArtifactReference: artifact.reference),
        _pngBytes,
      );
    },
  );

  test(
    'private Storage is attempted before a compatibility local path',
    () async {
      final calls = <String>[];
      final resolver = SupabaseStoragePathResolver(
        currentUserId: () => 'user-1',
        signedUrlLoader:
            ({
              required bucket,
              required path,
              required expiresIn,
              expectedUserId,
            }) async {
              calls.add(path);
              return 'https://storage.example.test/image';
            },
        httpClient: _BytesHttpClient(Uint8List.fromList(_pngBytes)),
      );
      final cache = CanvasImageCache.scoped();
      cache.configureStorageResolver(
        resolver: resolver,
        projectId: 'project-1',
        expectedUserId: 'user-1',
      );
      addTearDown(() {
        cache.dispose();
        resolver.dispose();
      });

      final bytes = await cache.loadImageBytes(
        storagePath: 'project-1/images/object.png',
        localPath: 'not-a-real-local-path.png',
      );

      expect(bytes, _pngBytes);
      expect(calls, ['project-1/images/object.png']);
    },
  );

  test(
    'signed and private-network URLs are rejected by compatibility reads',
    () async {
      final cache = CanvasImageCache.scoped();
      addTearDown(cache.dispose);

      expect(
        await cache.loadImageBytes(
          url: 'https://cdn.example.test/image.png?token=runtime-only',
        ),
        isNull,
      );
      expect(
        await cache.loadImageBytes(url: 'https://127.0.0.1/image.png'),
        isNull,
      );
    },
  );

  test('invalid image bytes are rejected after artifact hydration', () async {
    final store = MemoryImageArtifactStore();
    expect(
      () => store.save(Uint8List.fromList([1, 2, 3]), fileName: 'bad.png'),
      throwsA(isA<ImageArtifactStoreException>()),
    );
  });

  test('NodePainter uses an editor-scoped image cache', () async {
    final cache = CanvasImageCache.scoped();
    addTearDown(cache.dispose);
    final recorder = ui.PictureRecorder();
    final source = await _solidImage(Colors.red);
    cache.cacheImage('scoped-key', source);
    CanvasImageCache.instance.clear();

    NodePainter.paint(
      Canvas(recorder),
      CanvasNode(
        id: 'scoped-image',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 4,
        height: 4,
        payload: ImagePayload(url: 'scoped-key'),
      ),
      imageCache: cache,
    );

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(4, 4);
    final raw = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(
      [raw!.getUint8(0), raw.getUint8(1), raw.getUint8(2), raw.getUint8(3)],
      [244, 67, 54, 255],
    );
    rendered.dispose();
    picture.dispose();
    cache.clear();
  });

  test(
    'a stale completion cannot release a newer same-key request ticket',
    () async {
      final source = await _solidImage(Colors.red);
      final byteData = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      final bytes = byteData!.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      const reference = 'varian-image://delayed-image';
      final store = _DelayedImageArtifactStore(bytes);
      final cache = CanvasImageCache.scoped(imageArtifactStore: store);
      addTearDown(cache.dispose);

      cache.requestImage(imageArtifactReference: reference);
      cache.clear();
      cache.requestImage(imageArtifactReference: reference);
      expect(store.hydrations, 2);

      store.completeHydration(0, reference);
      await pumpEventQueue();
      cache.requestImage(imageArtifactReference: reference);

      expect(store.hydrations, 2);
    },
  );
}

Future<ui.Image> _solidImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  picture.dispose();
  return image;
}

const _pngBytes = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

class _BytesHttpClient extends MockClient {
  _BytesHttpClient(Uint8List bytes)
    : super((request) async => Response.bytes(bytes, 200));
}

class _DelayedImageArtifactStore implements ImageArtifactStore {
  _DelayedImageArtifactStore(this.bytes);

  final Uint8List bytes;
  final List<Completer<ImageArtifact?>> _hydrationCompleters = [];

  int get hydrations => _hydrationCompleters.length;

  void completeHydration(int index, String reference) {
    _hydrationCompleters[index].complete(
      ImageArtifact(
        reference: reference,
        bytes: Uint8List.fromList(bytes),
        fileName: 'image.png',
      ),
    );
  }

  @override
  Future<ImageArtifact> save(
    Uint8List bytes, {
    String fileName = 'image.png',
  }) => throw UnimplementedError();

  @override
  Future<ImageArtifact?> hydrate(String reference, {String? fileName}) {
    final completer = Completer<ImageArtifact?>();
    _hydrationCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<bool> exists(ImageArtifact artifact) async => true;

  @override
  Future<Uint8List?> read(ImageArtifact artifact) async =>
      Uint8List.fromList(bytes);

  @override
  Future<void> dispose(ImageArtifact artifact) async {}
}
