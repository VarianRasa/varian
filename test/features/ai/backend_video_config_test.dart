import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/features/ai/data/comfy_ui_bridge_manager.dart';
import 'package:varian/features/ai/data/video_provider.dart';

String _testKey() => String.fromCharCodes(const [
  103,
  101,
  110,
  101,
  114,
  97,
  108,
  45,
  107,
  101,
  121,
]);

void main() {
  test('video settings fall back to general provider values', () {
    final config = BackendConfig(
      openAiApiKey: _testKey(),
      openAiBaseUrl: 'https://provider.test/v1',
      videoModel: 'video-model',
    );

    expect(config.effectiveVideoApiKey, _testKey());
    expect(config.effectiveVideoBaseUrl, 'https://provider.test/v1');
    expect(config.isVideoConfigured, isTrue);
  });

  test('video mode defaults to OpenAI videos', () {
    expect(
      const BackendConfig().videoProviderMode,
      VideoProviderMode.openAiVideos,
    );
  });

  test('bridge mode keeps its token separate from the OpenAI key', () {
    const config = BackendConfig(
      openAiApiKey: 'openai-key',
      videoApiKey: 'video-key',
      videoBridgeToken: 'bridge-token-12345678901234567890',
      videoModel: comfyUiBridgeModel,
      videoProviderMode: VideoProviderMode.comfyUiBridge,
    );

    expect(config.effectiveVideoApiKey, 'bridge-token-12345678901234567890');
    expect(config.effectiveVideoBaseUrl, 'http://127.0.0.1:20129/v1');
    expect(config.isVideoConfigured, isTrue);
  });

  test('bridge mode ignores a remote video base override', () {
    const config = BackendConfig(
      videoApiBaseUrl: 'https://paid-provider.test/v1',
      videoBridgeToken: 'bridge-token-12345678901234567890',
      videoModel: comfyUiBridgeModel,
      videoProviderMode: VideoProviderMode.comfyUiBridge,
    );

    expect(config.effectiveVideoBaseUrl, 'http://127.0.0.1:20129/v1');
  });

  test('Wan mode uses its own Hugging Face Space and token', () {
    const config = BackendConfig(
      openAiApiKey: 'general-api-key',
      videoApiKey: 'video-api-key',
      wanHfToken: 'hf_access_token',
      videoProviderMode: VideoProviderMode.wanGradio,
    );

    expect(config.wanHfSpaceUrl, WanGradioVideoProviderClient.defaultSpaceUrl);
    expect(config.effectiveVideoBaseUrl, config.wanHfSpaceUrl);
    expect(config.effectiveVideoApiKey, 'hf_access_token');
    expect(config.isVideoConfigured, isTrue);
    expect(
      config
          .copyWith(wanHfSpaceUrl: ' https://my-space.hf.space ')
          .normalized()
          .wanHfSpaceUrl,
      'https://my-space.hf.space',
    );
  });

  test('Wan mode requires a configured Hugging Face Space URL', () {
    const config = BackendConfig(
      wanHfSpaceUrl: '',
      videoProviderMode: VideoProviderMode.wanGradio,
    );

    expect(config.isVideoConfigured, isFalse);
  });

  test('unknown persisted video mode fails closed', () {
    expect(
      BackendConfig.parseVideoProviderMode('future-provider'),
      VideoProviderMode.invalid,
    );
  });

  test('video settings reject an invalid base URL', () {
    final config = BackendConfig(
      videoApiKey: _testKey(),
      videoApiBaseUrl: 'http://provider.test/v1?invalid=1',
      videoModel: 'video-model',
    );

    expect(config.isVideoConfigured, isFalse);
  });

  test('normalizes a valid video base override before saving', () {
    final config = BackendConfig(
      videoApiKey: _testKey(),
      videoApiBaseUrl: 'https://provider.test/v1///',
      videoModel: 'video-model',
    ).normalized();

    expect(config.videoApiBaseUrl, 'https://provider.test/v1');
    expect(config.effectiveVideoBaseUrl, 'https://provider.test/v1');
  });

  test('rejects video base URLs with userinfo when normalized', () {
    expect(
      () => const BackendConfig(
        videoApiBaseUrl: 'https://user@provider.test/v1',
        videoModel: 'video-model',
      ).normalized(),
      throwsA(isA<FormatException>()),
    );
  });

  test('keeps an empty video base as a fallback to the general base', () {
    final config = BackendConfig(
      openAiApiKey: _testKey(),
      openAiBaseUrl: 'https://general.test/v1',
      videoModel: 'video-model',
    );

    expect(config.videoApiBaseUrl, isEmpty);
    expect(config.effectiveVideoBaseUrl, 'https://general.test/v1');
  });
}
