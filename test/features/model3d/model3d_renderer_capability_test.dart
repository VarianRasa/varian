import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/model3d/data/model3d_renderer_capability.dart';

void main() {
  test(
    'describes an unavailable Android renderer as a recoverable capability',
    () {
      final message = model3DRendererFallbackMessage(
        isAndroid: true,
        nativeRendererAvailable: false,
      );

      expect(message, contains('Android native renderer is unavailable'));
      expect(message, contains('project library remains usable'));
      expect(message, contains('Retry preview'));
    },
  );

  test('skips three_js construction only for unsupported Android', () {
    expect(
      shouldSkipModel3DRenderer(
        isAndroid: true,
        nativeRendererAvailable: false,
      ),
      isTrue,
    );
    expect(
      shouldSkipModel3DRenderer(isAndroid: true, nativeRendererAvailable: true),
      isFalse,
    );
    expect(
      shouldSkipModel3DRenderer(
        isAndroid: false,
        nativeRendererAvailable: false,
      ),
      isFalse,
    );
  });

  test(
    'does not show an Android fallback message for a supported renderer',
    () {
      expect(
        model3DRendererFallbackMessage(
          isAndroid: true,
          nativeRendererAvailable: true,
        ),
        isNull,
      );
    },
  );

  test('keeps non-Android targets on the existing renderer path', () {
    expect(
      model3DRendererFallbackMessage(
        isAndroid: false,
        nativeRendererAvailable: false,
      ),
      isNull,
    );
  });
}
