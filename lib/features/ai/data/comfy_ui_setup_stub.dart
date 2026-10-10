import 'video_provider.dart';

import 'comfy_ui_setup_contract.dart';

ComfyUiSetupService createComfyUiSetupService() =>
    const _UnsupportedComfyUiSetupService();

class _UnsupportedComfyUiSetupService implements ComfyUiSetupService {
  const _UnsupportedComfyUiSetupService();

  @override
  Future<String> defaultInstallationPath() async => '';

  @override
  Future<void> install({
    required String destination,
    required bool confirmed,
    ComfyUiSetupCancellation? cancellation,
    void Function(double progress)? onProgress,
  }) async {
    throw const VideoProviderException(
      'VIDEO_CONFIGURATION_ERROR',
      'ComfyUI setup is supported only on Windows.',
    );
  }
}
