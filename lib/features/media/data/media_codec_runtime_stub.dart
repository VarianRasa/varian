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
  const MediaCodecRuntime();

  Future<MediaCodecProbeResult> probe({String? configuredPath}) async =>
      const MediaCodecProbeResult(
        available: false,
        reason: 'Native video codec runtime is unavailable on this platform.',
      );

  Future<String?> resolveExecutable({String? configuredPath}) async => null;
}
