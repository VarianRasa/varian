import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:varian/domain/models/media_timeline.dart';

import 'media_codec_runtime.dart';
import 'media_video_proxy_transcoder.dart';

class PlatformMediaVideoProxyTranscoder
    implements CancellableMediaVideoProxyTranscoder {
  final String executable;
  final Duration timeout;
  final MediaCodecRuntime codecRuntime;

  const PlatformMediaVideoProxyTranscoder({
    this.executable = 'ffmpeg',
    this.timeout = const Duration(minutes: 5),
    this.codecRuntime = const MediaCodecRuntime(),
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
  }) async {
    return transcodeCancellable(
      sourceKey: sourceKey,
      sourceBytes: sourceBytes,
      sourceMimeType: sourceMimeType,
      sourceFileName: sourceFileName,
      formatHint: formatHint,
      outputFormat: outputFormat,
      clips: clips,
      isCancelled: () => false,
    );
  }

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
    Directory? temporaryDirectory;
    try {
      if (isCancelled()) {
        return const MediaVideoProxyResult.failed(
          message: 'Video proxy transcoding was cancelled.',
        );
      }
      final normalizedFormat = _normalizeFormat(outputFormat);
      final resolvedExecutable = await codecRuntime.resolveExecutable(
        configuredPath: executable,
      );
      if (resolvedExecutable == null) {
        return MediaVideoProxyResult.unsupported(
          message: executable == 'ffmpeg'
              ? 'Video proxy transcoding is unavailable: no native codec runtime was found.'
              : 'Video proxy transcoding is unavailable: encoder "$executable" could not be started (codec runtime probe failed).',
        );
      }
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'varian-video-proxy-',
      );
      final inputPath =
          '${temporaryDirectory.path}${Platform.pathSeparator}'
          'source${_sourceExtension(sourceFileName, formatHint, sourceMimeType)}';
      final outputPath =
          '${temporaryDirectory.path}${Platform.pathSeparator}'
          'proxy.$normalizedFormat';
      await File(inputPath).writeAsBytes(sourceBytes, flush: true);

      final enabledClips =
          clips.where((clip) => clip.enabled && clip.durationMs > 0).toList()
            ..sort((left, right) => left.startMs.compareTo(right.startMs));
      if (enabledClips.length <= 1) {
        final plan = MediaVideoProxyCommandBuilder.encode(
          inputPath: inputPath,
          outputPath: outputPath,
          outputFormat: normalizedFormat,
          clip: enabledClips.singleOrNull,
        );
        final result = await _run(
          executablePath: resolvedExecutable,
          arguments: plan.arguments,
          workingDirectory: temporaryDirectory.path,
          isCancelled: isCancelled,
        );
        if (!result.succeeded) return _failed(result.message);
      } else {
        final clipPaths = <String>[];
        for (var index = 0; index < enabledClips.length; index++) {
          final clipPath =
              '${temporaryDirectory.path}${Platform.pathSeparator}'
              'clip-$index.$normalizedFormat';
          final plan = MediaVideoProxyCommandBuilder.encode(
            inputPath: inputPath,
            outputPath: clipPath,
            outputFormat: normalizedFormat,
            clip: enabledClips[index],
          );
          final result = await _run(
            executablePath: resolvedExecutable,
            arguments: plan.arguments,
            workingDirectory: temporaryDirectory.path,
            isCancelled: isCancelled,
          );
          if (!result.succeeded) return _failed(result.message);
          clipPaths.add(clipPath);
        }
        final listPath =
            '${temporaryDirectory.path}${Platform.pathSeparator}'
            'concat.txt';
        await File(listPath).writeAsString(
          clipPaths
              .map(
                (path) =>
                    "file '${path.replaceAll('\\', '/').replaceAll("'", "'\\''")}'",
              )
              .join('\n'),
          flush: true,
        );
        final plan = MediaVideoProxyCommandBuilder.concat(
          listPath: listPath,
          outputPath: outputPath,
          outputFormat: normalizedFormat,
        );
        final result = await _run(
          executablePath: resolvedExecutable,
          arguments: plan.arguments,
          workingDirectory: temporaryDirectory.path,
          isCancelled: isCancelled,
        );
        if (!result.succeeded) return _failed(result.message);
      }

      final output = File(outputPath);
      if (!await output.exists()) {
        return const MediaVideoProxyResult.failed(
          message: 'Video encoder completed without producing an output file.',
        );
      }
      final bytes = await output.readAsBytes();
      if (bytes.isEmpty) {
        return const MediaVideoProxyResult.failed(
          message: 'Video encoder produced an empty output file.',
        );
      }
      return MediaVideoProxyResult(
        status: MediaVideoProxyStatus.supported,
        bytes: bytes,
      );
    } on ProcessException catch (error) {
      return MediaVideoProxyResult.unsupported(
        message:
            'Video proxy transcoding is unavailable: encoder "$executable" could not be started (${error.message}).',
      );
    } on ArgumentError catch (error) {
      return MediaVideoProxyResult.failed(message: '$error');
    } catch (error) {
      return MediaVideoProxyResult.failed(
        message: 'Video proxy failed: $error',
      );
    } finally {
      if (temporaryDirectory != null) {
        try {
          await temporaryDirectory.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<_ProcessResult> _run({
    required String executablePath,
    required List<String> arguments,
    required String workingDirectory,
    required bool Function() isCancelled,
  }) async {
    final process = await Process.start(
      executablePath,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final deadline = DateTime.now().add(timeout);
    var exitCode = -1;
    while (true) {
      final result = await Future.any<Object?>([
        process.exitCode,
        Future<void>.delayed(const Duration(milliseconds: 100)),
      ]);
      if (result is int) {
        exitCode = result;
        break;
      }
      if (isCancelled()) {
        process.kill(ProcessSignal.sigterm);
        await process.exitCode;
        return const _ProcessResult(
          exitCode: 125,
          message: 'Video proxy transcoding was cancelled.',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        process.kill(ProcessSignal.sigterm);
        await process.exitCode;
        return const _ProcessResult(
          exitCode: 124,
          message: 'Video proxy transcoding timed out.',
        );
      }
    }
    final stderr = await stderrFuture;
    return _ProcessResult(
      exitCode: exitCode,
      message: stderr.trim().isEmpty
          ? 'Encoder process failed.'
          : stderr.trim(),
    );
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

  static String _sourceExtension(
    String? sourceFileName,
    String? formatHint,
    String? sourceMimeType,
  ) {
    final candidates = [sourceFileName, formatHint, sourceMimeType];
    for (final candidate in candidates) {
      final value = candidate?.trim().toLowerCase() ?? '';
      final match = RegExp(r'\.([a-z0-9]{2,8})(?:$|[?#])').firstMatch(value);
      if (match != null) return '.${match.group(1)}';
      if (RegExp(r'^[a-z0-9]{2,8}$').hasMatch(value)) return '.$value';
      if (value == 'video/mp4') return '.mp4';
      if (value == 'video/webm') return '.webm';
      if (value == 'video/quicktime') return '.mov';
    }
    return '.bin';
  }

  static MediaVideoProxyResult _failed(String message) =>
      MediaVideoProxyResult.failed(message: message);
}

class _ProcessResult {
  final int exitCode;
  final String message;

  const _ProcessResult({required this.exitCode, required this.message});

  bool get succeeded => exitCode == 0;
}
