import 'video_provider.dart';

ComfyUiBridgeManager createComfyUiBridgeManager() =>
    const _UnsupportedComfyUiBridgeManager();

Future<void> shutdownComfyUiBridge() async {}

abstract interface class ComfyUiBridgeManager {
  Future<void> ensureReady({
    required String installationPath,
    required int comfyUiPort,
    required String bridgeToken,
  });

  Future<void> shutdown();
}

class _UnsupportedComfyUiBridgeManager implements ComfyUiBridgeManager {
  const _UnsupportedComfyUiBridgeManager();

  @override
  Future<void> ensureReady({
    required String installationPath,
    required int comfyUiPort,
    required String bridgeToken,
  }) async {
    throw const VideoProviderException(
      'VIDEO_CONFIGURATION_ERROR',
      'ComfyUI auto-start is supported only on Windows. Start the bridge manually on this platform.',
    );
  }

  @override
  Future<void> shutdown() async {}
}
