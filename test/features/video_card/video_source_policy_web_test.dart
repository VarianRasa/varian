import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/video_card/data/video_source_policy_web.dart';

void main() {
  test('rejects private RFC1918 IPv4 ranges on web', () {
    expect(isPublicVideoHost('172.16.0.1'), isFalse);
    expect(isPublicVideoHost('172.31.255.254'), isFalse);
  });

  test('rejects private and link-local IPv6 ranges on web', () {
    expect(isPublicVideoHost('fd00::1'), isFalse);
    expect(isPublicVideoHost('fe80::1'), isFalse);
  });

  test('allows public literal hosts on web', () {
    expect(isPublicVideoHost('8.8.8.8'), isTrue);
    expect(isPublicVideoHost('2001:4860:4860::8888'), isTrue);
  });
}
