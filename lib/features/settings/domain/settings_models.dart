import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The storage boundary used by app-wide settings.
enum SettingsScope { device, user, workspace, projectView }

@immutable
class SettingsEnvelope<T> {
  final int schemaVersion;
  final SettingsScope scope;
  final String subjectId;
  final int revision;
  final DateTime updatedAt;
  final T value;
  final Map<String, dynamic> extensions;

  const SettingsEnvelope({
    required this.schemaVersion,
    required this.scope,
    required this.subjectId,
    required this.revision,
    required this.updatedAt,
    required this.value,
    this.extensions = const {},
  });

  SettingsEnvelope<T> copyWith({
    int? schemaVersion,
    SettingsScope? scope,
    String? subjectId,
    int? revision,
    DateTime? updatedAt,
    T? value,
    Map<String, dynamic>? extensions,
  }) => SettingsEnvelope<T>(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    scope: scope ?? this.scope,
    subjectId: subjectId ?? this.subjectId,
    revision: revision ?? this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
    value: value ?? this.value,
    extensions: extensions ?? this.extensions,
  );

  Map<String, dynamic> toJson(Object? Function(T value) encodeValue) => {
    'schemaVersion': schemaVersion,
    'scope': scope.name,
    'subjectId': subjectId,
    'revision': revision,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'value': encodeValue(value),
    'extensions': extensions,
  };

  static SettingsEnvelope<T> fromJson<T>(
    Object? raw, {
    required T Function(Object? raw) decodeValue,
    required SettingsEnvelope<T> fallback,
  }) {
    if (raw is! Map) return fallback;
    final scope = SettingsScope.values.firstWhere(
      (candidate) => candidate.name == raw['scope'],
      orElse: () => fallback.scope,
    );
    final updatedAt = DateTime.tryParse(raw['updatedAt']?.toString() ?? '');
    final extensions = raw['extensions'];
    return SettingsEnvelope<T>(
      schemaVersion:
          (raw['schemaVersion'] as num?)?.toInt() ?? fallback.schemaVersion,
      scope: scope,
      subjectId: raw['subjectId']?.toString() ?? fallback.subjectId,
      revision: (raw['revision'] as num?)?.toInt() ?? fallback.revision,
      updatedAt: updatedAt ?? fallback.updatedAt,
      value: decodeValue(raw['value']),
      extensions: extensions is Map
          ? Map<String, dynamic>.from(extensions)
          : fallback.extensions,
    );
  }

  String encode(Object? Function(T value) encodeValue) =>
      jsonEncode(toJson(encodeValue));
}

class SettingsConflictException implements Exception {
  final int expectedRevision;
  final int actualRevision;

  const SettingsConflictException({
    required this.expectedRevision,
    required this.actualRevision,
  });

  @override
  String toString() =>
      'Settings revision conflict (expected $expectedRevision, actual $actualRevision).';
}
