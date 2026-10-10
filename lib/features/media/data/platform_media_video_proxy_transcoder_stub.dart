import 'dart:typed_data';

import 'package:varian/domain/models/media_timeline.dart';

import 'media_codec_runtime.dart';
import 'media_video_proxy_transcoder.dart';

class PlatformMediaVideoProxyTranscoder
    implements CancellableMediaVideoProxyTranscoder {
  const PlatformMediaVideoProxyTranscoder({
    String executable = 'ffmpeg',
    Duration timeout = const Duration(minutes: 5),
    MediaCodecRuntime codecRuntime = const MediaCodecRuntime(),
  });

  @override
  Future<MediaVideoProxyResult> transcode({
    required String sourceKey,
    required Uint8List sourceBytes,
    required String? sourceMimeType,
    required String? sourceFileName,
    required String? formatHint,
    required String outputFormat,
    required List<MediaClip> clips,
  }) async => const MediaVideoProxyResult.unsupported(
    message:
        'Video proxy transcoding is unavailable on this platform: no process encoder backend is available.',
  );

  @override
  Future<MediaVideoProxyResult> transcodeCancellable({
    required String sourceKey,
    required Uint8List sourceBytes,
    required String? sourceMimeType,
    required String? sourceFileName,
    required String? formatHint,
    required String outputFormat,
    required List<MediaClip> clips,
    required bool Function() isCancelled,
  }) async {
    if (isCancelled()) {
      return const MediaVideoProxyResult.failed(
        message: 'Video proxy transcoding was cancelled.',
      );
    }
    return transcode(
      sourceKey: sourceKey,
      sourceBytes: sourceBytes,
      sourceMimeType: sourceMimeType,
      sourceFileName: sourceFileName,
      formatHint: formatHint,
      outputFormat: outputFormat,
      clips: clips,
    );
  }
}
