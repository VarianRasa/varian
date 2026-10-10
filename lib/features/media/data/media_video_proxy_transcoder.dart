import 'dart:typed_data';

import 'package:varian/domain/models/media_timeline.dart';

enum MediaVideoProxyStatus { supported, unsupported, failed }

class MediaVideoProxyResult {
  final MediaVideoProxyStatus status;
  final Uint8List? bytes;
  final String? message;

  const MediaVideoProxyResult({required this.status, this.bytes, this.message});

  const MediaVideoProxyResult.unsupported({String? message})
    : this(status: MediaVideoProxyStatus.unsupported, message: message);

  const MediaVideoProxyResult.failed({String? message})
    : this(status: MediaVideoProxyStatus.failed, message: message);

  bool get isAvailable =>
      status == MediaVideoProxyStatus.supported &&
      bytes != null &&
      bytes!.isNotEmpty;
}

abstract interface class MediaVideoProxyTranscoder {
  Future<MediaVideoProxyResult> transcode({
    required String sourceKey,
    required Uint8List sourceBytes,
    required String? sourceMimeType,
    required String? sourceFileName,
    required String? formatHint,
    required String outputFormat,
    required List<MediaClip> clips,
  });
}

abstract interface class CancellableMediaVideoProxyTranscoder
    implements MediaVideoProxyTranscoder {
  Future<MediaVideoProxyResult> transcodeCancellable({
    required String sourceKey,
    required Uint8List sourceBytes,
    required String? sourceMimeType,
    required String? sourceFileName,
    required String? formatHint,
    required String outputFormat,
    required List<MediaClip> clips,
    required bool Function() isCancelled,
  });
}

class MediaVideoProxyCommand {
  final List<String> arguments;

  const MediaVideoProxyCommand(this.arguments);
}

class MediaVideoProxyCommandBuilder {
  MediaVideoProxyCommandBuilder._();

  static MediaVideoProxyCommand encode({
    required String inputPath,
    required String outputPath,
    required String outputFormat,
    MediaClip? clip,
  }) {
    final format = _normalizeFormat(outputFormat);
    final arguments = <String>[
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      if (clip != null) ...[
        '-ss',
        _seconds(clip.startMs),
        '-t',
        _seconds(clip.durationMs),
      ],
      '-i',
      inputPath,
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      ..._codecArguments(format),
      outputPath,
    ];
    return MediaVideoProxyCommand(arguments);
  }

  static MediaVideoProxyCommand concat({
    required String listPath,
    required String outputPath,
    required String outputFormat,
  }) {
    final format = _normalizeFormat(outputFormat);
    return MediaVideoProxyCommand([
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      listPath,
      '-c',
      'copy',
      if (format == 'mp4' || format == 'm4v' || format == 'mov') ...[
        '-movflags',
        '+faststart',
      ],
      outputPath,
    ]);
  }

  static String _normalizeFormat(String value) {
    final format = value.trim().toLowerCase().replaceFirst('.', '');
    if (!{'mp4', 'm4v', 'mov', 'webm', 'mkv'}.contains(format)) {
      throw ArgumentError.value(
        value,
        'outputFormat',
        'Unsupported video format.',
      );
    }
    return format;
  }

  static List<String> _codecArguments(String format) => format == 'webm'
      ? const ['-c:v', 'libvpx-vp9', '-b:v', '2M', '-c:a', 'libopus']
      : const [
          '-c:v',
          'libx264',
          '-preset',
          'veryfast',
          '-crf',
          '28',
          '-c:a',
          'aac',
          '-b:a',
          '128k',
          '-movflags',
          '+faststart',
        ];

  static String _seconds(int milliseconds) =>
      (milliseconds / 1000).toStringAsFixed(3);
}

class UnsupportedMediaVideoProxyTranscoder
    implements MediaVideoProxyTranscoder {
  const UnsupportedMediaVideoProxyTranscoder();

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
        'Video proxy transcoding is unavailable: no platform video encoder is configured. Source bytes are not used as a proxy.',
  );
}
