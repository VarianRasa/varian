import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:varian/data/remote/backend_config.dart';

void main() {
  test('3D configuration rejects unsupported providers and invalid URLs', () {
    const unsupportedProvider = BackendConfig(
      threeDEnabled: true,
      threeDProvider: 'unknown-provider',
    );
    const invalidUrl = BackendConfig(
      threeDEnabled: true,
      threeDBaseUrl: 'https://worker.test/v1?token=leak',
    );

    expect(unsupportedProvider.isThreeDConfigured, isFalse);
    expect(invalidUrl.isThreeDConfigured, isFalse);
  });

  test('3D configuration normalizes the provider identifier', () {
    final config = const BackendConfig(
      threeDEnabled: true,
      threeDBaseUrl: 'https://worker.test/v1///',
      threeDProvider: 'TRELLIS',
    ).normalized();

    expect(config.threeDBaseUrl, 'https://worker.test/v1');
    expect(config.threeDProvider, 'trellis');
    expect(config.isThreeDConfigured, isTrue);
  });

  test('accepts the ComfyUI direct workflow provider', () {
    final config = const BackendConfig(
      threeDEnabled: true,
      threeDBaseUrl: 'https://worker.test/v1',
      threeDProvider: 'COMFYUI',
    ).normalized();

    expect(config.threeDProvider, 'comfyui');
    expect(config.isThreeDConfigured, isTrue);
  });

  test('accepts the explicitly enabled hosted FAL TRELLIS2 provider', () {
    final config = const BackendConfig(
      threeDEnabled: true,
      threeDBaseUrl: 'https://worker.test/v1',
      threeDProvider: 'FAL-TRELLIS2',
    ).normalized();

    expect(config.threeDProvider, 'fal-trellis2');
    expect(config.isThreeDConfigured, isTrue);
  });

  test('3D settings persist and reload from preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = BackendConfigNotifier();
    await notifier.waitUntilReady();
    await notifier.saveConfig(
      const BackendConfig(
        threeDEnabled: true,
        threeDBaseUrl: 'https://worker.test/v1',
        threeDProvider: 'hunyuan3d',
      ),
    );

    final reloaded = BackendConfigNotifier();
    await reloaded.waitUntilReady();

    expect(reloaded.state.threeDEnabled, isTrue);
    expect(reloaded.state.threeDBaseUrl, 'https://worker.test/v1');
    expect(reloaded.state.threeDProvider, 'hunyuan3d');
  });
}
