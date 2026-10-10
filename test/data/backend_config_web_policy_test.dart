import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/remote/backend_config.dart';

void main() {
  test('web endpoint warning is available only on web', () {
    const config = BackendConfig(openAiBaseUrl: 'http://localhost:20128/v1');
    if (kIsWeb) {
      expect(config.webEndpointWarning, contains('localhost'));
    } else {
      expect(config.webEndpointWarning, isNull);
    }
  });

  test('public HTTPS endpoint has no browser endpoint warning', () {
    const config = BackendConfig(openAiBaseUrl: 'https://ai.example.test/v1');
    expect(config.webEndpointWarning, isNull);
  });

  test('video endpoint warning follows a configured video override', () {
    const config = BackendConfig(
      openAiBaseUrl: 'https://ai.example.test/v1',
      videoApiBaseUrl: 'http://localhost:20128/v1',
    );
    if (kIsWeb) {
      expect(config.webEndpointWarning, contains('localhost'));
    } else {
      expect(config.webEndpointWarning, isNull);
    }
  });

  test('provider URL rejects embedded credentials', () {
    expect(
      () => BackendConfig.normalizeOpenAiBaseUrl(
        'https://user:secret@provider.example/v1',
      ),
      throwsFormatException,
    );
  });

  test('provider URL requires HTTPS outside loopback', () {
    expect(
      () => BackendConfig.normalizeOpenAiBaseUrl('http://provider.example/v1'),
      throwsFormatException,
    );
    expect(
      BackendConfig.normalizeOpenAiBaseUrl('http://localhost:11434/v1'),
      'http://localhost:11434/v1',
    );
  });
}
