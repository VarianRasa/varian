import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_package.dart';
import 'package:varian/domain/models/document_package_archive.dart';
import 'package:varian/features/governance/domain/operability.dart';

void main() {
  final now = DateTime.utc(2026, 9, 13);

  test('feature flags are deterministic and respect rollout boundaries', () {
    const full = FeatureFlag(
      key: 'new-canvas',
      enabled: true,
      rolloutPercentage: 100,
    );
    const off = FeatureFlag(
      key: 'new-canvas',
      enabled: false,
      rolloutPercentage: 100,
    );
    const partial = FeatureFlag(
      key: 'new-canvas',
      enabled: true,
      rolloutPercentage: 25,
    );

    expect(full.isEnabledFor('user-1'), isTrue);
    expect(off.isEnabledFor('user-1'), isFalse);
    expect(partial.isEnabledFor('user-1'), partial.isEnabledFor('user-1'));
  });

  test('health response maps degraded and unhealthy checks to non-200', () {
    final registry = HealthCheckRegistry()
      ..register(
        'storage',
        () => const HealthCheckResult(
          name: 'storage',
          status: HealthStatus.healthy,
          message: 'ok',
        ),
      )
      ..register(
        'backend',
        () => const HealthCheckResult(
          name: 'backend',
          status: HealthStatus.degraded,
          message: 'offline',
        ),
      );
    final response = registry.respond(version: '1.0.0', now: now);

    expect(response.status, HealthStatus.degraded);
    expect(response.statusCode, 503);
    expect(response.body['version'], '1.0.0');
  });

  test('health response contains an unhealthy result when a check throws', () {
    final registry = HealthCheckRegistry()
      ..register('crashing-check', () => throw StateError('boom'));

    final response = registry.respond(now: now);

    expect(response.status, HealthStatus.unhealthy);
    expect(response.body['checks'], contains(isA<Map<String, dynamic>>()));
  });

  test('support bundles redact sensitive fields', () {
    final bundle = SupportBundle(
      generatedAt: now,
      sections: const {
        'health': {'status': 'healthy'},
        'config': {'anonKey': 'secret-value', 'mode': 'debug'},
      },
    );
    final encoded = bundle.encode();

    expect(encoded, contains('[REDACTED]'));
    expect(encoded, isNot(contains('secret-value')));
    expect(encoded, contains('debug'));
  });

  test('backup restore drill verifies portable encrypted archive', () {
    final archive = DocumentPackageArchive(
      package: CanvasDocumentPackage(
        document: CanvasDocument(projectId: 'backup-project', updatedAt: now),
      ),
    );
    final result = BackupRestoreDrill.verify(
      archive.encode(password: 'backup-password'),
      password: 'backup-password',
    );

    expect(result.restored, isTrue);
    expect(result.portable, isTrue);
    expect(result.projectId, 'backup-project');
  });

  test('diagnostics consent defaults to opt out and validates retention', () {
    const settings = DiagnosticsSettings();
    const invalid = DiagnosticsSettings(retentionDays: 0);

    expect(settings.isOptedIn, isFalse);
    expect(settings.validate(), isEmpty);
    expect(invalid.validate(), isNotEmpty);
  });

  test('release policy enforces rollback window', () {
    const policy = ReleasePolicy(
      channel: ReleaseChannel.stable,
      version: '1.0.0',
      rollbackVersion: '0.9.0',
      rollbackWindow: Duration(days: 7),
    );

    expect(policy.canRollback(now, now.add(const Duration(days: 6))), isTrue);
    expect(policy.canRollback(now, now.add(const Duration(days: 8))), isFalse);
  });
}
