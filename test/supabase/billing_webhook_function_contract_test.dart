import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String fileName) =>
    File('supabase/functions/billing-webhook/$fileName').readAsStringSync();

void main() {
  test('billing webhook requires HMAC verification and bounded raw bytes', () {
    final source = _source('index.ts');

    expect(source, contains('BILLING_WEBHOOK_SECRET'));
    expect(source, contains('x-billing-timestamp'));
    expect(source, contains('x-billing-signature'));
    expect(source, contains('verifyWebhookSignature'));
    expect(source, contains('const maxBodyBytes = 256 * 1024'));
    expect(source, contains('PAYLOAD_TOO_LARGE'));
    expect(source, contains('INVALID_SIGNATURE'));
    expect(source, contains('apply_workspace_billing_webhook'));
  });

  test(
    'helper normalizes only safe entitlement fields and enforces replay window',
    () {
      final source = _source('helpers.ts');

      expect(source, contains('export function normalizeBillingWebhook'));
      expect(source, contains('const payload: JsonRecord ='));
      expect(source, contains('export function parseSignatureHeader'));
      expect(source, contains('export function isFreshTimestamp'));
      expect(source, contains('maxAgeSeconds = 300'));
      expect(source, contains('crypto.subtle.importKey'));
      expect(source, contains('constantTimeEqual'));
      expect(source, contains('Invalid entitlement limit'));
    },
  );

  test('function is configured for provider-signed requests without JWT', () {
    final config = File(
      'supabase/config.toml',
    ).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    expect(config, contains('[functions.billing-webhook]'));
    expect(config, contains('[functions.billing-webhook]\nverify_jwt = false'));
  });
}
