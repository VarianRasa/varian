import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/governance/domain/operability.dart';
import 'package:varian/features/governance/domain/remote_operability.dart';

void main() {
  final now = DateTime.utc(2026, 9, 14, 8);

  test('redacts nested observability secrets and preserves wire fields', () {
    final event = WorkspaceObservabilityEvent(
      projectId: 'project-1',
      eventType: 'media.decode.failed',
      severity: WorkspaceObservabilitySeverity.error,
      correlationId: 'operation-1234',
      payload: {
        'health': {'status': 'degraded'},
        'accessToken': 'secret',
        'nested': {'apiKey': 'secret-too'},
      },
      recordedAt: now,
    );

    final encoded = jsonEncode(event.toJson());
    expect(encoded, contains('project-1'));
    expect(encoded, contains('[REDACTED]'));
    expect(encoded, isNot(contains('secret-too')));
    expect(event.validate(), isEmpty);
  });

  test('rejects oversized and malformed observability events', () {
    final event = WorkspaceObservabilityEvent(
      projectId: '',
      eventType: 'x',
      severity: WorkspaceObservabilitySeverity.info,
      correlationId: 'short',
      payload: {'data': 'a' * (64 * 1024)},
      recordedAt: now,
    );

    expect(event.validate(), contains('Project ID is required.'));
    expect(
      event.validate(),
      contains('Event type must contain 2 to 128 characters.'),
    );
    expect(
      event.validate(),
      contains('Correlation ID must contain 8 to 128 characters.'),
    );
    expect(
      event.validate(),
      contains('Observability payload must be at most 64 KiB.'),
    );
  });

  test('counts UTF-8 bytes when bounding observability payloads', () {
    final event = WorkspaceObservabilityEvent(
      projectId: 'project-1',
      eventType: 'editor.warning',
      severity: WorkspaceObservabilitySeverity.warning,
      correlationId: 'operation-1234',
      payload: {'data': '界' * 22_000},
      recordedAt: now,
    );

    expect(
      event.validate(),
      contains('Observability payload must be at most 64 KiB.'),
    );
  });

  test('round trips receipts and release policy snapshots', () {
    final receipt = WorkspaceSupportBundleReceipt.fromJson({
      'id': 'bundle-1',
      'project_id': 'project-1',
      'operation_id': 'support-1234',
      'status': 'ready',
      'checksum': 'abc',
      'created_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(days: 7)).toIso8601String(),
      'artifact_uri': 'storage://support/bundle-1.json',
    });
    expect(receipt.operationId, 'support-1234');
    expect(receipt.artifactUri, 'storage://support/bundle-1.json');

    final policy = WorkspaceReleasePolicySnapshot.fromJson({
      'project_id': 'project-1',
      'channel': 'beta',
      'version': '1.2.3',
      'rollback_version': '1.2.2',
      'released_at': now.toIso8601String(),
      'rollback_until': now.add(const Duration(days: 7)).toIso8601String(),
    });
    expect(policy.policy.channel, ReleaseChannel.beta);
    expect(policy.policy.version, '1.2.3');
    expect(
      policy.policy.canRollback(now, now.add(const Duration(days: 6))),
      isTrue,
    );
    expect(policy.toJson()['projectId'], 'project-1');
  });

  test('parses health snapshots and availability', () {
    final snapshot = WorkspaceHealthSnapshot.fromJson({
      'status': 'degraded',
      'version': '1.2.3',
      'timestamp': now.toIso8601String(),
      'checks': [
        {
          'name': 'database',
          'status': 'healthy',
          'message': 'ok',
          'latencyMs': 4,
        },
        {
          'name': 'realtime',
          'status': 'degraded',
          'message': 'slow',
          'latencyMs': 80,
        },
      ],
    });

    expect(snapshot.isAvailable, isTrue);
    expect(snapshot.status, HealthStatus.degraded);
    expect(snapshot.checks, hasLength(2));
    expect(snapshot.checks.last.latency, const Duration(milliseconds: 80));
  });
}
