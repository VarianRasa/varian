import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/link_card/domain/link_url_policy.dart';

void main() {
  test('normalizes valid web URLs', () {
    expect(
      normalizeLinkUrl(' HTTPS://Example.COM/path ').toString(),
      'https://example.com/path',
    );
  });

  test('rejects unsupported, credentialed, and local URLs', () {
    expect(
      () => normalizeLinkUrl('file:///tmp/a'),
      throwsA(isA<LinkUrlValidationException>()),
    );
    expect(
      () => normalizeLinkUrl('https://user:pass@example.com'),
      throwsA(isA<LinkUrlValidationException>()),
    );
    expect(
      () => normalizeLinkUrl('http://localhost'),
      throwsA(isA<LinkUrlValidationException>()),
    );
    expect(
      () => normalizeLinkUrl('http://127.0.0.1'),
      throwsA(isA<LinkUrlValidationException>()),
    );
    expect(
      () => normalizeLinkUrl('http://192.168.1.2'),
      throwsA(isA<LinkUrlValidationException>()),
    );
    expect(
      () => normalizeLinkUrl('http://[::1]'),
      throwsA(isA<LinkUrlValidationException>()),
    );
  });

  test('rejects private literal IPv6 without calling dart:io parsing APIs', () {
    expect(
      () => normalizeLinkUrl('http://[::1]'),
      throwsA(isA<LinkUrlValidationException>()),
    );
  });

  test('recognizes direct image URLs while ignoring query strings', () {
    expect(
      isDirectImageUrl('https://i.pinimg.com/736x/reference.jpg?width=1024'),
      isTrue,
    );
    expect(isDirectImageUrl('https://example.com/article'), isFalse);
    expect(isDirectImageUrl('file:///tmp/image.jpg'), isFalse);
  });

  test('accepts public image CDN URLs', () {
    expect(
      normalizeLinkUrl('https://i.pinimg.com/736x/example.jpg').host,
      'i.pinimg.com',
    );
  });

  test('rejects a hostname resolving to a prohibited address', () async {
    await expectLater(
      ensurePublicDestination(
        Uri.parse('https://internal.example'),
        lookup: (_) async => [InternetAddress('10.0.0.2')],
      ),
      throwsA(isA<LinkUrlValidationException>()),
    );
  });
}
