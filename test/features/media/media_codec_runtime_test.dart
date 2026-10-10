import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/media/data/media_codec_runtime.dart';

void main() {
  test(
    'reports an explicit unavailable state for a missing codec runtime',
    () async {
      final result = await const MediaCodecRuntime().probe(
        configuredPath: 'varian-codec-that-does-not-exist',
      );

      expect(result.available, isFalse);
      expect(result.executable, isNull);
      expect(result.reason, contains('unavailable'));
    },
  );

  test('resolver never returns an unverified executable', () async {
    final executable = await const MediaCodecRuntime().resolveExecutable(
      configuredPath: 'varian-codec-that-does-not-exist',
    );

    expect(executable, isNull);
  });
}
