import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:varian/features/ai/data/video_download_service.dart';

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
  test('uses a generated name when the video node has no name', () {
    expect(videoDownloadFileName(null), 'generated-video.mp4');
  });

  test('downloads artifact through the injected saver', () async {
    final calls = <String>[];
    final service = VideoDownloadService(
      saveBytes: (fileName, bytes) async {
        calls.add('$fileName:${bytes.length}');
      },
    );

    await service.download(
      VideoDownloadArtifact(fileName: 'generated.mp4', bytes: _minimalMp4()),
    );

    expect(calls, ['generated.mp4:16']);
  });

  test('adds an mp4 extension to unsafe download names', () async {
    String? savedName;
    final service = VideoDownloadService(
      saveBytes: (fileName, _) async => savedName = fileName,
    );

    await service.download(
      VideoDownloadArtifact(fileName: 'clip.txt', bytes: _minimalMp4()),
      suggestedName: '../clip.txt',
    );

    expect(savedName, 'clip.mp4');
  });

  test(
    'uses generated-video when the requested download name is blank',
    () async {
      String? savedName;
      final service = VideoDownloadService(
        saveBytes: (fileName, _) async => savedName = fileName,
      );

      await service.download(
        VideoDownloadArtifact(fileName: 'generated.mp4', bytes: _minimalMp4()),
        suggestedName: '   ',
      );

      expect(savedName, 'generated-video.mp4');
    },
  );

  test('rejects signed URLs before making an HTTP request', () async {
    var requests = 0;
    final service = VideoDownloadService(
      client: _CountingClient(onRequest: () => requests++),
      saveBytes: (_, _) async {},
    );

    await expectLater(
      service.downloadSource(
        fileName: 'generated.mp4',
        url: 'https://cdn.example.test/generated.mp4?token=secret',
      ),
      throwsA(isA<StateError>()),
    );
    expect(requests, 0);
  });

  test('rejects URL fragments before making an HTTP request', () async {
    var requests = 0;
    final service = VideoDownloadService(
      client: _CountingClient(onRequest: () => requests++),
      saveBytes: (_, _) async {},
    );

    await expectLater(
      service.downloadSource(
        fileName: 'generated.mp4',
        url: 'https://cdn.example.test/generated.mp4#fragment',
      ),
      throwsA(isA<StateError>()),
    );
    expect(requests, 0);
  });
}

class _CountingClient extends http.BaseClient {
  final void Function() onRequest;

  _CountingClient({required this.onRequest});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onRequest();
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}
