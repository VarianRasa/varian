class DocumentSchemaException extends FormatException {
  const DocumentSchemaException(super.message);
}

class DocumentMigrationResult {
  final Map<String, dynamic> json;
  final int sourceVersion;
  final int targetVersion;
  final List<String> appliedMigrations;

  const DocumentMigrationResult({
    required this.json,
    required this.sourceVersion,
    required this.targetVersion,
    required this.appliedMigrations,
  });
}

class DocumentMigrations {
  DocumentMigrations._();

  static const int currentVersion = 4;

  static DocumentMigrationResult migrate(Map<String, dynamic> input) {
    final migrated = Map<String, dynamic>.from(input);
    final sourceVersion = _readVersion(migrated['schemaVersion']);
    if (sourceVersion > currentVersion) {
      throw DocumentSchemaException(
        'Document schema $sourceVersion is newer than supported schema $currentVersion.',
      );
    }

    var version = sourceVersion;
    final applied = <String>[];
    while (version < currentVersion) {
      switch (version) {
        case 1:
          _migrateV1ToV2(migrated);
          applied.add('v1_to_v2');
          version = 2;
          break;
        case 2:
          _migrateV2ToV3(migrated);
          applied.add('v2_to_v3');
          version = 3;
          break;
        case 3:
          _migrateV3ToV4(migrated);
          applied.add('v3_to_v4');
          version = 4;
          break;
        default:
          throw DocumentSchemaException(
            'No migration exists for document schema $version.',
          );
      }
    }

    migrated['schemaVersion'] = currentVersion;
    return DocumentMigrationResult(
      json: migrated,
      sourceVersion: sourceVersion,
      targetVersion: currentVersion,
      appliedMigrations: List<String>.unmodifiable(applied),
    );
  }

  static int _readVersion(Object? raw) {
    if (raw == null) return 1;
    if (raw is num && raw.toInt() >= 1) return raw.toInt();
    throw const DocumentSchemaException('Document schemaVersion is invalid.');
  }

  static void _migrateV1ToV2(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    if (metadata is! Map) {
      json['metadata'] = <String, dynamic>{};
    }
    if (json['nodes'] is! List) json['nodes'] = <dynamic>[];
    if (json['edges'] is! List) json['edges'] = <dynamic>[];
    if (json['assets'] == null) {
      json['assets'] = <String, dynamic>{'version': 1, 'items': <dynamic>[]};
    }
  }

  static void _migrateV2ToV3(Map<String, dynamic> json) {
    if (json['tokens'] == null) {
      json['tokens'] = <String, dynamic>{
        'version': 1,
        'modes': <String>['base'],
        'items': <dynamic>[],
      };
    }
  }

  static void _migrateV3ToV4(Map<String, dynamic> json) {
    if (json['navigation'] is! Map) {
      json['navigation'] = <String, dynamic>{};
    }
  }
}
