import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../domain/models/document_package_archive.dart';

class DiagnosticsSettings {
  final bool crashReportingEnabled;
  final bool sessionDiagnosticsEnabled;
  final bool includePerformanceData;
  final int retentionDays;

  const DiagnosticsSettings({
    this.crashReportingEnabled = false,
    this.sessionDiagnosticsEnabled = false,
    this.includePerformanceData = false,
    this.retentionDays = 30,
  });

  bool get isOptedIn => crashReportingEnabled || sessionDiagnosticsEnabled;

  List<String> validate() => retentionDays < 1 || retentionDays > 365
      ? const ['Diagnostics retention must be between 1 and 365 days.']
      : const [];

  Map<String, dynamic> toJson() => {
    'crashReportingEnabled': crashReportingEnabled,
    'sessionDiagnosticsEnabled': sessionDiagnosticsEnabled,
    'includePerformanceData': includePerformanceData,
    'retentionDays': retentionDays,
  };
}

class FeatureFlag {
  final String key;
  final bool enabled;
  final int rolloutPercentage;

  const FeatureFlag({
    required this.key,
    this.enabled = false,
    this.rolloutPercentage = 0,
  });

  bool isEnabledFor(String subjectId) {
    if (!enabled) return false;
    if (rolloutPercentage >= 100) return true;
    if (rolloutPercentage <= 0) return false;
    final digest = sha256.convert(utf8.encode('$key:$subjectId')).toString();
    final bucket = int.parse(digest.substring(0, 8), radix: 16) % 100;
    return bucket < rolloutPercentage;
  }

  List<String> validate() => rolloutPercentage < 0 || rolloutPercentage > 100
      ? const ['Feature flag rollout must be between 0 and 100.']
      : const [];
}

enum HealthStatus { healthy, degraded, unhealthy }

class HealthCheckResult {
  final String name;
  final HealthStatus status;
  final String message;
  final Duration latency;

  const HealthCheckResult({
    required this.name,
    required this.status,
    required this.message,
    this.latency = Duration.zero,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'status': status.name,
    'message': message,
    'latencyMs': latency.inMilliseconds,
  };
}

class HealthEndpointResponse {
  final int statusCode;
  final HealthStatus status;
  final Map<String, dynamic> body;

  const HealthEndpointResponse({
    required this.statusCode,
    required this.status,
    required this.body,
  });

  String encode() => jsonEncode(body);
}

class HealthCheckRegistry {
  final Map<String, HealthCheckResult Function()> _checks = {};

  void register(String name, HealthCheckResult Function() check) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    _checks[name] = check;
  }

  HealthEndpointResponse respond({String version = 'dev', DateTime? now}) {
    final checks = <HealthCheckResult>[];
    for (final entry in _checks.entries) {
      try {
        checks.add(entry.value());
      } catch (error) {
        checks.add(
          HealthCheckResult(
            name: entry.key,
            status: HealthStatus.unhealthy,
            message: 'Health check failed.',
          ),
        );
      }
    }
    final status = checks.any((check) => check.status == HealthStatus.unhealthy)
        ? HealthStatus.unhealthy
        : checks.any((check) => check.status == HealthStatus.degraded)
        ? HealthStatus.degraded
        : HealthStatus.healthy;
    return HealthEndpointResponse(
      statusCode: status == HealthStatus.healthy ? 200 : 503,
      status: status,
      body: {
        'status': status.name,
        'version': version,
        'timestamp': (now ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
        'checks': checks.map((check) => check.toJson()).toList(growable: false),
      },
    );
  }
}

class SupportBundle {
  final DateTime generatedAt;
  final Map<String, dynamic> sections;

  const SupportBundle({required this.generatedAt, required this.sections});

  Map<String, dynamic> toJson() => {
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'sections': _redact(sections),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static Object? _redact(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _isSensitive(entry.key.toString())
              ? '[REDACTED]'
              : _redact(entry.value),
      };
    }
    if (value is Iterable) return value.map(_redact).toList(growable: false);
    return value;
  }

  static bool _isSensitive(String key) => RegExp(
    r'(token|secret|password|private.?key|anon.?key)',
    caseSensitive: false,
  ).hasMatch(key);
}

class MigrationTelemetryEvent {
  final String migrationId;
  final int sourceVersion;
  final int targetVersion;
  final bool succeeded;
  final Duration duration;
  final DateTime recordedAt;

  const MigrationTelemetryEvent({
    required this.migrationId,
    required this.sourceVersion,
    required this.targetVersion,
    required this.succeeded,
    required this.duration,
    required this.recordedAt,
  });

  Map<String, dynamic> toJson() => {
    'migrationId': migrationId,
    'sourceVersion': sourceVersion,
    'targetVersion': targetVersion,
    'succeeded': succeeded,
    'durationMs': duration.inMilliseconds,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}

enum ReleaseChannel { stable, beta, nightly }

class ReleasePolicy {
  final ReleaseChannel channel;
  final String version;
  final String? rollbackVersion;
  final Duration rollbackWindow;

  const ReleasePolicy({
    required this.channel,
    required this.version,
    this.rollbackVersion,
    this.rollbackWindow = const Duration(days: 7),
  });

  bool canRollback(DateTime releasedAt, DateTime now) =>
      rollbackVersion != null &&
      !releasedAt.toUtc().add(rollbackWindow).isBefore(now.toUtc());
}

class BackupRestoreDrillResult {
  final bool restored;
  final bool portable;
  final String? projectId;
  final String? error;

  const BackupRestoreDrillResult({
    required this.restored,
    required this.portable,
    this.projectId,
    this.error,
  });
}

class BackupRestoreDrill {
  BackupRestoreDrill._();

  static BackupRestoreDrillResult verify(Uint8List backup, {String? password}) {
    try {
      final archive = DocumentPackageArchive.decode(backup, password: password);
      return BackupRestoreDrillResult(
        restored: true,
        portable: archive.isPortable,
        projectId: archive.package.document.projectId,
      );
    } catch (error) {
      return BackupRestoreDrillResult(
        restored: false,
        portable: false,
        error: '$error',
      );
    }
  }
}
