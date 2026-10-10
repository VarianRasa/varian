import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/features/media/data/platform_media_video_proxy_transcoder.dart';
import 'package:varian/features/media/data/media_video_proxy_transcoder.dart';

void main() {
  test('builds a bounded single-clip H.264 proxy command', () {
    final plan = MediaVideoProxyCommandBuilder.encode(
      inputPath: 'source.mp4',
      outputPath: 'proxy.mp4',
      outputFormat: 'mp4',
      clip: const MediaClip(id: 'clip', startMs: 1500, endMs: 4250),
    );

    expect(
      plan.arguments,
      containsAllInOrder(<String>[
        '-ss',
        '1.500',
        '-t',
        '2.750',
        '-i',
        'source.mp4',
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        '-c:v',
        'libx264',
        'proxy.mp4',
      ]),
    );
  });

  test('builds concat command without copying source bytes as a proxy', () {
    final plan = MediaVideoProxyCommandBuilder.concat(
      listPath: 'concat.txt',
      outputPath: 'proxy.webm',
      outputFormat: 'webm',
    );

    expect(
      plan.arguments,
      containsAllInOrder(<String>[
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        'concat.txt',
        '-c',
        'copy',
        'proxy.webm',
      ]),
    );
    expect(plan.arguments, isNot(contains('-c:v')));
  });

  test('rejects unsupported proxy formats before spawning a process', () {
    expect(
      () => MediaVideoProxyCommandBuilder.encode(
        inputPath: 'source.mp4',
        outputPath: 'proxy.avi',
        outputFormat: 'avi',
      ),
      throwsArgumentError,
    );
  });

  test('reports an unavailable encoder without copying source bytes', () async {
    final result =
        await const PlatformMediaVideoProxyTranscoder(
          executable: 'varian-encoder-does-not-exist',
        ).transcode(
          sourceKey: 'memory://video.mp4',
          sourceBytes: Uint8List.fromList([1, 2, 3]),
          sourceMimeType: 'video/mp4',
          sourceFileName: 'video.mp4',
          formatHint: 'mp4',
          outputFormat: 'mp4',
          clips: const [],
        );

    expect(result.status, MediaVideoProxyStatus.unsupported);
    expect(result.bytes, isNull);
    expect(result.message, contains('could not be started'));
  });

  test('honors cancellation before starting the codec process', () async {
    final result =
        await const PlatformMediaVideoProxyTranscoder(
          executable: 'varian-encoder-does-not-exist',
        ).transcodeCancellable(
          sourceKey: 'memory://video.mp4',
          sourceBytes: Uint8List.fromList([1, 2, 3]),
          sourceMimeType: 'video/mp4',
          sourceFileName: 'video.mp4',
          formatHint: 'mp4',
          outputFormat: 'mp4',
          clips: const [],
          isCancelled: () => true,
        );

    expect(result.status, MediaVideoProxyStatus.failed);
    expect(result.message, contains('cancelled'));
  });
}
