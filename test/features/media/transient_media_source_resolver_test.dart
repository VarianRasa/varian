import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/video_artifact_store.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';
import 'package:varian/features/media/data/media_source_reader.dart';
import 'package:varian/features/media/data/transient_media_source_resolver.dart';

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

class _StreamingClient extends http.BaseClient {
  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
  Uri? requestedUri;

  _StreamingClient({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUri = request.url;
    return http.StreamedResponse(
      http.ByteStream.fromBytes(body),
      statusCode,
      headers: headers,
    );
  }
}

class _CountingVideoArtifactStore implements VideoArtifactStore {
  final bool throwOnRead;
  var disposed = 0;

  _CountingVideoArtifactStore({this.throwOnRead = false});

  @override
  Future<VideoArtifact> save(
    Uint8List bytes, {
    String fileName = 'video.mp4',
  }) => throw UnimplementedError();

  @override
  Future<VideoArtifact?> hydrate(String reference, {String? fileName}) async =>
      VideoArtifact(
        path: 'memory://video',
        reference: reference,
        fileName: fileName ?? 'video.mp4',
      );

  @override
  Future<bool> exists(VideoArtifact artifact) async => true;

  @override
  Future<Uint8List?> read(VideoArtifact artifact) async {
    if (throwOnRead) throw StateError('read failed');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> dispose(VideoArtifact artifact) async => disposed++;
}

class _MemoryArtifactStore implements MediaArtifactStore {
  final Map<String, Uint8List> items = {};
  final Map<String, MediaArtifact> hydrated = {};
  var nextId = 0;
  var disposed = 0;
  Object? readError;

  @override
  Future<MediaArtifact> save(
    Uint8List bytes, {
    required MediaArtifactKind kind,
    required String mimeType,
    required String checksum,
    required String fileName,
    MediaStoragePolicy storagePolicy = MediaStoragePolicy.cache,
  }) async {
    final reference = 'memory://media-${nextId++}';
    items[reference] = Uint8List.fromList(bytes);
    return MediaArtifact(
      kind: kind,
      path: reference,
      reference: reference,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      checksum: checksum,
    );
  }

  @override
  Future<bool> exists(MediaArtifact artifact) async =>
      items.containsKey(artifact.path ?? artifact.reference);

  @override
  Future<Uint8List?> read(MediaArtifact artifact) async {
    final error = readError;
    if (error != null) throw error;
    final bytes = items[artifact.path ?? artifact.reference];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<MediaArtifact?> hydrate(
    String reference, {
    MediaArtifactKind? kind,
    String? mimeType,
    String? checksum,
    String? fileName,
  }) async => hydrated[reference];

  @override
  Future<void> dispose(MediaArtifact artifact) async {
    disposed++;
    items.remove(artifact.path ?? artifact.reference);
  }
}

void main() {
  test('materializes hydrated audio bytes and disposes the owner', () async {
    final store = _MemoryArtifactStore();
    final resolver = TransientMediaSourceResolver(
      artifactStore: store,
      fileResolver: TransientFileSourceResolver(
        projectId: 'project-a',
        expectedUserId: 'user-a',
        storageReader:
            ({
              required projectId,
              required storagePath,
              required source,
              required expectedUserId,
              required maxBytes,
            }) async => Uint8List.fromList([1, 2, 3]),
      ),
    );
    final source = await resolver.resolveAudio(
      AudioPayload(storagePath: 'project-a/audio/track.mp3'),
    );

    expect(source.path, 'memory://media-0');
    expect(await source.readBytes(), [1, 2, 3]);
    expect(store.items, contains('memory://media-0'));

    await source.dispose();
    await source.dispose();
    expect(store.disposed, 1);
    expect(store.items, isEmpty);
  });

  test(
    'hydrates audio from a durable media reference before Storage fallback',
    () async {
      final checksum = 'c' * 64;
      final reference = 'varian-media://durable/$checksum/original';
      final store = _MemoryArtifactStore();
      store.items['memory://audio'] = Uint8List.fromList([9, 8, 7]);
      store.hydrated[reference] = MediaArtifact(
        kind: MediaArtifactKind.original,
        path: 'memory://audio',
        reference: reference,
        mimeType: 'audio/mpeg',
        sizeBytes: 3,
        checksum: checksum,
      );
      final resolver = TransientMediaSourceResolver(
        artifactStore: store,
        fileResolver: TransientFileSourceResolver(
          storageReader:
              ({
                required projectId,
                required storagePath,
                required source,
                required expectedUserId,
                required maxBytes,
              }) async => Uint8List.fromList([1, 2, 3]),
        ),
      );

      final source = await resolver.resolveAudio(
        AudioPayload(
          storagePath: 'project-a/audio/track.mp3',
          audioArtifactReference: reference,
        ),
      );

      expect(await source.readBytes(), [9, 8, 7]);
      expect(source.path, 'memory://media-0');
      await source.dispose();
    },
  );

  test(
    'uses the injected media store for source-reader durable references',
    () async {
      final store = MemoryMediaArtifactStore();
      final bytes = Uint8List.fromList([9, 8, 7]);
      final artifact = await store.save(
        bytes,
        kind: MediaArtifactKind.original,
        mimeType: 'audio/mpeg',
        checksum: mediaArtifactChecksum(bytes),
        fileName: 'track.mp3',
        storagePolicy: MediaStoragePolicy.durable,
      );

      final resolved = await readMediaSourceBytes(
        artifact.reference!,
        mediaArtifactStore: store,
      );

      expect(resolved, bytes);
    },
  );

  test('rejects an oversized data URI before returning bytes', () async {
    final source =
        'data:application/octet-stream;base64,${base64Encode([1, 2, 3, 4])}';

    expect(await readMediaSourceBytes(source, maxBytes: 3), isNull);
  });

  test('rejects a local media file larger than maxBytes', () async {
    final directory = await Directory.systemTemp.createTemp('varian-media-');
    final file = File('${directory.path}${Platform.pathSeparator}source.bin');
    await file.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() => directory.delete(recursive: true));

    expect(await readMediaSourceBytes(file.path, maxBytes: 3), isNull);
  });

  test(
    'rejects an oversized streamed HTTP response without redirecting',
    () async {
      final client = _StreamingClient(
        statusCode: 302,
        headers: {'location': 'https://redirected.example/source.bin'},
        body: [1, 2, 3, 4],
      );

      expect(
        await readMediaSourceBytes(
          'https://source.example/source.bin',
          maxBytes: 3,
          httpClient: client,
        ),
        isNull,
      );
      expect(
        client.requestedUri.toString(),
        'https://source.example/source.bin',
      );
    },
  );

  test('disposes an injected video artifact after reading it', () async {
    final store = _CountingVideoArtifactStore();

    final bytes = await readMediaSourceBytes(
      'varian-video://video-source',
      videoArtifactStore: store,
    );

    expect(bytes, [1, 2, 3]);
    expect(store.disposed, 1);
  });

  test('disposes a video artifact when reading fails', () async {
    final store = _CountingVideoArtifactStore(throwOnRead: true);

    await expectLater(
      readMediaSourceBytes(
        'varian-video://video-source',
        videoArtifactStore: store,
      ),
      throwsStateError,
    );
    expect(store.disposed, 1);
  });

  test(
    'disposes a hydrated media artifact when resolver reading fails',
    () async {
      final checksum = 'a' * 64;
      final reference = 'varian-media://durable/$checksum/original';
      final store = _MemoryArtifactStore()
        ..hydrated[reference] = MediaArtifact(
          kind: MediaArtifactKind.original,
          path: 'memory://audio',
          reference: reference,
          mimeType: 'audio/mpeg',
          sizeBytes: 3,
          checksum: checksum,
        );
      store.items['memory://audio'] = Uint8List.fromList([1, 2, 3]);
      store.readError = StateError('read failed');
      final resolver = TransientMediaSourceResolver(
        artifactStore: store,
        fileResolver: const TransientFileSourceResolver(),
      );

      await expectLater(
        resolver.resolveAudio(AudioPayload(audioArtifactReference: reference)),
        throwsStateError,
      );
      expect(store.disposed, 1);
    },
  );

  test('ignores non-durable media references', () async {
    final store = _MemoryArtifactStore();
    final resolver = TransientMediaSourceResolver(
      artifactStore: store,
      fileResolver: const TransientFileSourceResolver(),
    );

    final source = await resolver.resolveAudio(
      AudioPayload(
        audioArtifactReference: 'varian-media://cache/${'d' * 64}/original',
      ),
    );

    expect(source.isEmpty, isTrue);
  });

  test('hydrates a video reference from the injected store', () async {
    final videoStore = MemoryVideoArtifactStore();
    final artifact = await videoStore.save(
      _minimalMp4(),
      fileName: 'fixture.mp4',
    );
    final resolver = TransientMediaSourceResolver(
      artifactStore: _MemoryArtifactStore(),
      videoArtifactStore: videoStore,
      fileResolver: const TransientFileSourceResolver(),
    );

    final source = await resolver.resolveVideo(
      VideoPayload(videoArtifactReference: artifact.reference),
    );

    expect(await source.readBytes(), _minimalMp4());
    expect(source.path, 'memory://media-0');
  });

  test('rejects signed query URL as public fallback', () async {
    final resolver = TransientMediaSourceResolver(
      artifactStore: _MemoryArtifactStore(),
      fileResolver: const TransientFileSourceResolver(),
    );
    final source = await resolver.resolveVideo(
      VideoPayload(videoUrl: 'https://cdn.example/video.mp4?token=secret'),
    );

    expect(source.isEmpty, isTrue);
    expect(source.uri, isNull);
    expect(source.path, isNull);
  });

  test('keeps durable payload sources free of runtime delivery values', () {
    final payload = VideoPayload(
      storagePath: 'project-a/video/source.mp4',
      videoUrl: 'https://cdn.example/video.mp4?token=secret',
      videoPath: r'C:\temp\source.mp4',
      videoArtifactReference: 'varian-video://runtime',
    );

    final json = payload.toJson();
    expect(json['storagePath'], 'project-a/video/source.mp4');
    expect(json, isNot(contains('videoUrl')));
    expect(json, isNot(contains('videoPath')));
    expect(json, isNot(contains('videoArtifactReference')));
    expect(json.toString(), isNot(contains('token=secret')));
  });
}
