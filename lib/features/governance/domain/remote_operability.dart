import 'dart:convert';

import 'operability.dart';

enum WorkspaceObservabilitySeverity { info, warning, error }

class WorkspaceObservabilityEvent {
  final String projectId;
  final String eventType;
  final WorkspaceObservabilitySeverity severity;
  final String correlationId;
  final Map<String, dynamic> payload;
  final DateTime recordedAt;

  const WorkspaceObservabilityEvent({
    required this.projectId,
    required this.eventType,
    required this.severity,
    required this.correlationId,
    required this.payload,
    required this.recordedAt,
  });

  List<String> validate() {
    final errors = <String>[];
    if (projectId.trim().isEmpty) errors.add('Project ID is required.');
    if (eventType.trim().length < 2 || eventType.trim().length > 128) {
      errors.add('Event type must contain 2 to 128 characters.');
    }
    if (correlationId.trim().length < 8 || correlationId.trim().length > 128) {
      errors.add('Correlation ID must contain 8 to 128 characters.');
    }
    if (utf8.encode(jsonEncode(payload)).length > 64 * 1024) {
      errors.add('Observability payload must be at most 64 KiB.');
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'eventType': eventType,
    'severity': severity.name,
    'correlationId': correlationId,
    'payload': _redact(payload),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };

  factory WorkspaceObservabilityEvent.fromJson(Map<String, dynamic> json) =>
      WorkspaceObservabilityEvent(
        projectId: _string(json, 'projectId', 'project_id'),
        eventType: _string(json, 'eventType', 'event_type'),
        severity: WorkspaceObservabilitySeverity.values.firstWhere(
          (value) => value.name == _string(json, 'severity'),
          orElse: () => WorkspaceObservabilitySeverity.info,
        ),
        correlationId: _string(json, 'correlationId', 'correlation_id'),
        payload: _map(json['payload']),
        recordedAt: _date(json, 'recordedAt', 'created_at'),
      );

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
    r'(token|secret|password|private.?key|anon.?key|api.?key)',
    caseSensitive: false,
  ).hasMatch(key);
}

class WorkspaceObservabilityReceipt {
  final String id;
  final String projectId;
  final String eventType;
  final WorkspaceObservabilitySeverity severity;
  final String correlationId;
  final bool duplicate;
  final DateTime createdAt;

  const WorkspaceObservabilityReceipt({
    required this.id,
    required this.projectId,
    required this.eventType,
    required this.severity,
    required this.correlationId,
    required this.duplicate,
    required this.createdAt,
  });

  factory WorkspaceObservabilityReceipt.fromJson(Map<String, dynamic> json) =>
      WorkspaceObservabilityReceipt(
        id: _string(json, 'id'),
        projectId: _string(json, 'projectId', 'project_id'),
        eventType: _string(json, 'eventType', 'event_type'),
        severity: WorkspaceObservabilitySeverity.values.firstWhere(
          (value) => value.name == _string(json, 'severity'),
          orElse: () => WorkspaceObservabilitySeverity.info,
        ),
        correlationId: _string(json, 'correlationId', 'correlation_id'),
        duplicate: json['duplicate'] as bool? ?? false,
        createdAt: _date(json, 'createdAt', 'created_at'),
      );
}

class WorkspaceSupportBundleReceipt {
  final String id;
  final String projectId;
  final String operationId;
  final String status;
  final String checksum;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? artifactUri;

  const WorkspaceSupportBundleReceipt({
    required this.id,
    required this.projectId,
    required this.operationId,
    required this.status,
    required this.checksum,
    required this.createdAt,
    this.expiresAt,
    this.artifactUri,
  });

  factory WorkspaceSupportBundleReceipt.fromJson(Map<String, dynamic> json) =>
      WorkspaceSupportBundleReceipt(
        id: _string(json, 'id', 'bundleId'),
        projectId: _string(json, 'projectId', 'project_id'),
        operationId: _string(json, 'operationId', 'operation_id'),
        status: _string(json, 'status', null, 'ready'),
        checksum: _string(json, 'checksum'),
        createdAt: _date(json, 'createdAt', 'created_at'),
        expiresAt: _optionalDate(json, 'expiresAt', 'expires_at'),
        artifactUri: _optionalString(json, 'artifactUri', 'artifact_uri'),
      );
}

class WorkspaceReleasePolicySnapshot {
  final String projectId;
  final ReleasePolicy policy;
  final DateTime releasedAt;
  final DateTime? updatedAt;

  const WorkspaceReleasePolicySnapshot({
    required this.projectId,
    required this.policy,
    required this.releasedAt,
    this.updatedAt,
  });

  factory WorkspaceReleasePolicySnapshot.fromJson(Map<String, dynamic> json) =>
      WorkspaceReleasePolicySnapshot(
        projectId: _string(json, 'projectId', 'project_id'),
        policy: ReleasePolicy(
          channel: ReleaseChannel.values.firstWhere(
            (value) => value.name == _string(json, 'channel'),
            orElse: () => ReleaseChannel.stable,
          ),
          version: _string(json, 'version', null, '0.0.0'),
          rollbackVersion: _optionalString(
            json,
            'rollbackVersion',
            'rollback_version',
          ),
          rollbackWindow: _durationUntil(json),
        ),
        releasedAt: _date(json, 'releasedAt', 'released_at'),
        updatedAt: _optionalDate(json, 'updatedAt', 'updated_at'),
      );

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'channel': policy.channel.name,
    'version': policy.version,
    'rollbackVersion': policy.rollbackVersion,
    'releasedAt': releasedAt.toUtc().toIso8601String(),
    'rollbackUntil': releasedAt
        .toUtc()
        .add(policy.rollbackWindow)
        .toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };
}

class WorkspaceHealthSnapshot {
  final HealthStatus status;
  final String version;
  final DateTime generatedAt;
  final List<HealthCheckResult> checks;

  const WorkspaceHealthSnapshot({
    required this.status,
    required this.version,
    required this.generatedAt,
    required this.checks,
  });

  bool get isAvailable => status != HealthStatus.unhealthy;

  factory WorkspaceHealthSnapshot.fromJson(Map<String, dynamic> json) {
    final checks = json['checks'] is List
        ? (json['checks'] as List)
              .whereType<Map>()
              .map((item) {
                final map = Map<String, dynamic>.from(item);
                return HealthCheckResult(
                  name: _string(map, 'name'),
                  status: HealthStatus.values.firstWhere(
                    (value) => value.name == _string(map, 'status'),
                    orElse: () => HealthStatus.unhealthy,
                  ),
                  message: _string(map, 'message'),
                  latency: Duration(
                    milliseconds: (map['latencyMs'] as num?)?.toInt() ?? 0,
                  ),
                );
              })
              .toList(growable: false)
        : const <HealthCheckResult>[];
    return WorkspaceHealthSnapshot(
      status: HealthStatus.values.firstWhere(
        (value) => value.name == _string(json, 'status'),
        orElse: () => HealthStatus.unhealthy,
      ),
      version: _string(json, 'version', null, 'unknown'),
      generatedAt: _date(json, 'timestamp', 'generated_at'),
      checks: checks,
    );
  }
}

String _string(
  Map<String, dynamic> json,
  String key, [
  String? alternate,
  String fallback = '',
]) =>
    (json[key] ?? (alternate == null ? null : json[alternate]))?.toString() ??
    fallback;

String? _optionalString(
  Map<String, dynamic> json,
  String key, [
  String? alternate,
]) {
  final value = json[key] ?? (alternate == null ? null : json[alternate]);
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

DateTime _date(Map<String, dynamic> json, String key, [String? alternate]) =>
    DateTime.tryParse(_string(json, key, alternate))?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _optionalDate(
  Map<String, dynamic> json,
  String key, [
  String? alternate,
]) {
  final value = _optionalString(json, key, alternate);
  return value == null ? null : DateTime.tryParse(value)?.toUtc();
}

Duration _durationUntil(Map<String, dynamic> json) {
  final rollbackUntil = _optionalDate(json, 'rollbackUntil', 'rollback_until');
  final releasedAt = _date(json, 'releasedAt', 'released_at');
  if (rollbackUntil == null || !rollbackUntil.isAfter(releasedAt)) {
    return Duration.zero;
  }
  return rollbackUntil.difference(releasedAt);
}
