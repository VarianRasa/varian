import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum MediaCodecSource { configured, bundled, path }

class MediaCodecProbeResult {
  final bool available;
  final String? executable;
  final MediaCodecSource? source;
  final String? version;
  final String reason;

  const MediaCodecProbeResult({
    required this.available,
    required this.reason,
    this.executable,
    this.source,
    this.version,
  });
}

class MediaCodecRuntime {
  final Duration probeTimeout;

  const MediaCodecRuntime({this.probeTimeout = const Duration(seconds: 3)});

  Future<MediaCodecProbeResult> probe({String? configuredPath}) async {
    final candidates = _candidates(configuredPath);
    for (final candidate in candidates) {
      final version = await _version(candidate.path);
      if (version == null) continue;
      return MediaCodecProbeResult(
        available: true,
        executable: candidate.path,
        source: candidate.source,
        version: version,
        reason: 'Native video codec runtime is available.',
      );
    }
    return const MediaCodecProbeResult(
      available: false,
      reason:
          'Native video codec runtime is unavailable. Install or bundle ffmpeg and configure VARIAN_VIDEO_ENCODER.',
    );
  }

  Future<String?> resolveExecutable({String? configuredPath}) async {
    final result = await probe(configuredPath: configuredPath);
    return result.executable;
  }

  List<_CodecCandidate> _candidates(String? configuredPath) {
    final result = <_CodecCandidate>[];
    final seen = <String>{};

    void add(String? path, MediaCodecSource source) {
      final value = path?.trim();
      if (value == null || value.isEmpty || !seen.add(value)) return;
      result.add(_CodecCandidate(value, source));
    }

    final configured = configuredPath?.trim();
    if (configured != null && configured.isNotEmpty && configured != 'ffmpeg') {
      add(configured, MediaCodecSource.configured);
    }
    add(
      Platform.environment['VARIAN_VIDEO_ENCODER'],
      MediaCodecSource.configured,
    );
    add(
      Platform.environment['VARIAN_FFMPEG_PATH'],
      MediaCodecSource.configured,
    );

    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final executableName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final bundleRoots = <String>[
      Platform.environment['VARIAN_CODEC_BUNDLE_DIR'] ?? '',
      Platform.environment['VARIAN_APP_SUPPORT'] ?? '',
      executableDirectory,
    ].where((value) => value.trim().isNotEmpty).toSet();
    for (final root in bundleRoots) {
      for (final relativePath in [
        executableName,
        'codecs${Platform.pathSeparator}$executableName',
        'data${Platform.pathSeparator}codecs${Platform.pathSeparator}$executableName',
        'resources${Platform.pathSeparator}codecs${Platform.pathSeparator}$executableName',
      ]) {
        add(
          File('$root${Platform.pathSeparator}$relativePath').path,
          MediaCodecSource.bundled,
        );
      }
    }
    for (final relativePath in [
      'codecs${Platform.pathSeparator}$executableName',
      'data${Platform.pathSeparator}codecs${Platform.pathSeparator}$executableName',
      'resources${Platform.pathSeparator}codecs${Platform.pathSeparator}$executableName',
    ]) {
      add(
        File('$executableDirectory${Platform.pathSeparator}$relativePath').path,
        MediaCodecSource.bundled,
      );
    }
    add(
      configured == null || configured.isEmpty ? 'ffmpeg' : configured,
      MediaCodecSource.path,
    );
    return result;
  }

  Future<String?> _version(String executable) async {
    Process? process;
    try {
      process = await Process.start(executable, const [
        '-version',
      ], runInShell: false);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final result = await Future.wait<Object?>([
        process.exitCode,
        stdoutFuture,
        stderrFuture,
      ]).timeout(probeTimeout);
      final exitCode = result[0] as int;
      if (exitCode != 0) return null;
      final output = '${result[1] as String}\n${result[2] as String}'.trim();
      if (output.isEmpty) return null;
      return output.split(RegExp(r'\r?\n')).first.trim();
    } on Object {
      if (process != null) {
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode;
        } catch (_) {}
      }
      return null;
    }
  }
}

class _CodecCandidate {
  final String path;
  final MediaCodecSource source;

  const _CodecCandidate(this.path, this.source);
}
