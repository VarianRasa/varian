import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/models/document.dart';
import '../../../features/canvas/domain/canvas_navigation.dart';
import '../../../features/history/snapshot_manager.dart';
import '../../../features/assets/domain/asset_library.dart';
import 'durable_database_connection.dart';

/// The durable record kinds owned by the project persistence boundary.
///
/// Values are intentionally JSON envelopes instead of generated Drift tables
/// in this first migration slice. The table and transaction boundary are
/// durable, while the existing document codecs remain the compatibility
/// authority for each payload.
enum DurableProjectRecordKind {
  document,
  recovery,
  history,
  autoCheckpoint,
  viewport,
  assetIndex,
  assetLibrary,
  assetQueue,
  collaborationQueue,
  migration,
}

extension on DurableProjectRecordKind {
  String get wireName => name;
}

/// A small raw-SQL Drift database used by [DurableProjectStore].
///
/// The schema is deliberately additive and versioned. Keeping the payload as
/// JSON means document migrations can continue to evolve independently while
/// SQLite provides atomic replacement, per-project keys, and durable storage.
final class ProjectDurableDatabase extends GeneratedDatabase {
  ProjectDurableDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo> get allTables => const <TableInfo>[];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) async {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS project_records (
          project_id TEXT NOT NULL,
          record_kind TEXT NOT NULL,
          record_key TEXT NOT NULL,
          payload TEXT NOT NULL,
          schema_version INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (project_id, record_kind, record_key)
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS project_migration_state (
          migration_id TEXT PRIMARY KEY,
          state TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await customStatement('''
        CREATE INDEX IF NOT EXISTS project_records_kind_idx
        ON project_records(project_id, record_kind)
      ''');
    },
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from < 1) {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS project_records (
            project_id TEXT NOT NULL,
            record_kind TEXT NOT NULL,
            record_key TEXT NOT NULL,
            payload TEXT NOT NULL,
            schema_version INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (project_id, record_kind, record_key)
          )
        ''');
        await customStatement('''
          CREATE TABLE IF NOT EXISTS project_migration_state (
            migration_id TEXT PRIMARY KEY,
            state TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      }
    },
  );
}

/// A project-keyed durable storage adapter.
///
/// Every project record carries its project ID in the primary key and every
/// public method checks the caller's project ID before writing. This makes a
/// stale autosave, recovery write, or queue retry unable to land in another
/// project record.
final class DurableProjectStore {
  DurableProjectStore({
    ProjectDurableDatabase? database,
    this.beforeSnapshotWrite,
  }) : _database = database ?? ProjectDurableDatabase(_openConnection());

  /// Optional fault-injection seam used by lifecycle tests to hold a durable
  /// transaction open. Production stores leave it null.
  final Future<void> Function()? beforeSnapshotWrite;
  final ProjectDurableDatabase _database;
  Future<void>? _ready;
  bool _closed = false;

  static DatabaseConnection _openConnection() => openDurableDatabaseConnection(
    name: 'varian_project_runtime',
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  );

  Future<void> get ready => _ensureReady();

  Future<void> _ensureReady() {
    if (_closed) {
      return Future<void>.error(StateError('Durable project store is closed.'));
    }
    final current = _ready;
    if (current != null) return current;
    final opening = _database.customStatement('PRAGMA foreign_keys = ON');
    _ready = opening.catchError((Object error, StackTrace stackTrace) {
      _ready = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    return _ready!;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _database.close();
  }

  Future<CanvasDocument?> loadCanvasDocument(String projectId) async {
    final raw = await readDocument(projectId);
    if (raw == null) return null;
    try {
      return _decodeDocumentForProject(raw, projectId);
    } catch (error) {
      final recovery = await readRecovery(projectId);
      if (recovery == null) rethrow;
      try {
        return _decodeDocumentForProject(recovery, projectId);
      } catch (_) {
        Error.throwWithStackTrace(error, StackTrace.current);
      }
    }
  }

  CanvasDocument _decodeDocumentForProject(String payload, String projectId) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw const FormatException('Durable document payload is not an object.');
    }
    final document = CanvasDocument.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (document.projectId != projectId) {
      throw const FormatException('Durable document project mismatch.');
    }
    return document;
  }

  /// Validates the identity field when a raw compatibility payload has one.
  ///
  /// The low-level write APIs still accept legacy or intentionally opaque JSON
  /// so migration can preserve bytes. Typed save APIs and all document reads
  /// perform full [CanvasDocument] decoding and reject mismatched projects.
  void _validateDocumentPayload(String payload, String projectId) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      final embeddedProjectId = decoded['projectId'];
      if (embeddedProjectId is String && embeddedProjectId != projectId) {
        throw const FormatException('Durable document project mismatch.');
      }
    } on FormatException catch (error) {
      if (error.message.contains('project mismatch')) rethrow;
      // Preserve malformed legacy bytes for the recovery reader.
    }
  }

  void _validateRecoveryPayload(String payload, String projectId) {
    _validateDocumentPayload(payload, projectId);
  }

  void _validateSnapshotRecords(
    Iterable<DocumentSnapshotRecord> records,
    String projectId,
  ) {
    for (final record in records) {
      if (record.document.projectId != projectId) {
        throw StateError(
          'Durable snapshot ${record.id} belongs to another project.',
        );
      }
    }
  }

  void _validateSnapshotJson(String payload, String projectId) {
    final decoded = jsonDecode(payload);
    // Raw compatibility callers may store an opaque object. Typed history
    // methods validate every DocumentSnapshotRecord before reaching this seam.
    if (decoded is! List) return;
    for (final value in decoded) {
      if (value is! Map) continue;
      final document = value['document'];
      if (document is! Map) continue;
      final embeddedProjectId = document['projectId'];
      if (embeddedProjectId is String && embeddedProjectId != projectId) {
        throw const FormatException('Durable snapshot project mismatch.');
      }
    }
  }

  Future<void> saveCanvasDocument(
    CanvasDocument document, {
    CanvasNavigationState? navigation,
  }) async {
    final normalized = navigation == null
        ? document
        : document.copyWith(navigation: navigation.toJson());
    final encoded = jsonEncode(normalized.toPersistenceJson());
    var recoveryJson = encoded;

    // Keep the last validated primary document as the recovery point. Using
    // the incoming payload for both records makes recovery useless when the
    // new write is corrupt or only partially serialized by a caller.
    final previousJson = await readDocument(normalized.projectId);
    if (previousJson != null) {
      try {
        final previous = _decodeDocumentForProject(
          previousJson,
          normalized.projectId,
        );
        recoveryJson = jsonEncode(previous.toPersistenceJson());
      } catch (_) {
        // A malformed legacy primary must not replace a valid recovery point.
      }
    }

    await writeProjectSnapshot(
      projectId: normalized.projectId,
      documentJson: encoded,
      recoveryJson: recoveryJson,
      documentSchemaVersion: normalized.schemaVersion,
      recoverySchemaVersion: normalized.schemaVersion,
      viewportJson: jsonEncode(normalized.viewport.toJson()),
      assetIndexJson: jsonEncode(normalized.assets.toPersistenceJson()),
    );
  }

  Future<List<DocumentSnapshotRecord>> loadHistory(String projectId) async {
    final raw = await readHistory(projectId);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final records = [
      for (final item in decoded)
        if (item is Map)
          DocumentSnapshotRecord.fromJson(Map<String, dynamic>.from(item)),
    ];
    _validateSnapshotRecords(records, projectId);
    return records;
  }

  Future<void> saveHistory(
    String projectId,
    Iterable<DocumentSnapshotRecord> records,
  ) async {
    final bounded = records.toList(growable: false);
    _validateSnapshotRecords(bounded, projectId);
    await writeHistory(
      projectId: projectId,
      historyJson: jsonEncode(
        bounded
            .map((record) => record.toPersistenceJson())
            .toList(growable: false),
      ),
    );
  }

  Future<List<DocumentSnapshotRecord>> loadAutoCheckpoints(
    String projectId,
  ) async {
    final raw = await readAutoCheckpoint(projectId);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final records = [
      for (final item in decoded)
        if (item is Map)
          DocumentSnapshotRecord.fromJson(Map<String, dynamic>.from(item)),
    ];
    _validateSnapshotRecords(records, projectId);
    return records;
  }

  Future<void> saveAutoCheckpoints(
    String projectId,
    Iterable<DocumentSnapshotRecord> records,
  ) async {
    final bounded = records.toList(growable: false);
    _validateSnapshotRecords(bounded, projectId);
    await writeAutoCheckpoint(
      projectId: projectId,
      checkpointJson: jsonEncode(
        bounded
            .map((record) => record.toPersistenceJson())
            .toList(growable: false),
      ),
    );
  }

  Future<void> writeDocument({
    required String projectId,
    required String documentJson,
    int schemaVersion = 1,
  }) {
    _validateDocumentPayload(documentJson, projectId);
    return _put(
      projectId: projectId,
      kind: DurableProjectRecordKind.document,
      payload: documentJson,
      schemaVersion: schemaVersion,
    );
  }

  Future<String?> readDocument(String projectId) =>
      _get(projectId: projectId, kind: DurableProjectRecordKind.document);

  /// Replaces the primary document and its recovery copy in one SQLite
  /// transaction. The recovery copy is intentionally retained after a
  /// successful write so a later decode failure can still recover the last
  /// known-good payload.
  Future<void> writeProjectSnapshot({
    required String projectId,
    required String documentJson,
    required String recoveryJson,
    int documentSchemaVersion = 1,
    int recoverySchemaVersion = 1,
    String? viewportJson,
    String? assetIndexJson,
  }) async {
    _validateProjectId(projectId);
    _validateDocumentPayload(documentJson, projectId);
    _validateRecoveryPayload(recoveryJson, projectId);
    if (documentJson.isEmpty) {
      throw ArgumentError.value(
        documentJson,
        'documentJson',
        'Durable document payload is empty.',
      );
    }
    if (recoveryJson.isEmpty) {
      throw ArgumentError.value(
        recoveryJson,
        'recoveryJson',
        'Durable recovery payload is empty.',
      );
    }
    await _ensureReady();
    await beforeSnapshotWrite?.call();
    await _database.transaction(() async {
      await _putUnlocked(
        projectId: projectId,
        kind: DurableProjectRecordKind.recovery,
        payload: recoveryJson,
        schemaVersion: recoverySchemaVersion,
      );
      await _putUnlocked(
        projectId: projectId,
        kind: DurableProjectRecordKind.document,
        payload: documentJson,
        schemaVersion: documentSchemaVersion,
      );
      if (viewportJson != null) {
        await _putUnlocked(
          projectId: projectId,
          kind: DurableProjectRecordKind.viewport,
          payload: viewportJson,
          schemaVersion: documentSchemaVersion,
        );
      }
      if (assetIndexJson != null) {
        await _putUnlocked(
          projectId: projectId,
          kind: DurableProjectRecordKind.assetIndex,
          payload: assetIndexJson,
          schemaVersion: documentSchemaVersion,
        );
      }
    });
  }

  Future<void> writeRecovery({
    required String projectId,
    required String recoveryJson,
    int schemaVersion = 1,
  }) {
    _validateRecoveryPayload(recoveryJson, projectId);
    return _put(
      projectId: projectId,
      kind: DurableProjectRecordKind.recovery,
      payload: recoveryJson,
      schemaVersion: schemaVersion,
    );
  }

  Future<String?> readRecovery(String projectId) =>
      _get(projectId: projectId, kind: DurableProjectRecordKind.recovery);

  Future<void> writeHistory({
    required String projectId,
    required String historyJson,
    int schemaVersion = 1,
  }) {
    _validateSnapshotJson(historyJson, projectId);
    return _put(
      projectId: projectId,
      kind: DurableProjectRecordKind.history,
      payload: historyJson,
      schemaVersion: schemaVersion,
    );
  }

  Future<String?> readHistory(String projectId) =>
      _get(projectId: projectId, kind: DurableProjectRecordKind.history);

  Future<void> writeAutoCheckpoint({
    required String projectId,
    required String checkpointJson,
    int schemaVersion = 1,
  }) {
    _validateSnapshotJson(checkpointJson, projectId);
    return _put(
      projectId: projectId,
      kind: DurableProjectRecordKind.autoCheckpoint,
      payload: checkpointJson,
      schemaVersion: schemaVersion,
    );
  }

  Future<String?> readAutoCheckpoint(String projectId) =>
      _get(projectId: projectId, kind: DurableProjectRecordKind.autoCheckpoint);

  Future<void> writeViewport({
    required String projectId,
    required String viewportJson,
    int schemaVersion = 1,
  }) => _put(
    projectId: projectId,
    kind: DurableProjectRecordKind.viewport,
    payload: viewportJson,
    schemaVersion: schemaVersion,
  );

  Future<String?> readViewport(String projectId) =>
      _get(projectId: projectId, kind: DurableProjectRecordKind.viewport);

  Future<void> writeAssetIndex({
    required String projectId,
    required String assetIndexJson,
    int schemaVersion = 1,
  }) => _put(
    projectId: projectId,
    kind: DurableProjectRecordKind.assetIndex,
    payload: assetIndexJson,
    schemaVersion: schemaVersion,
  );

  Future<String?> readAssetIndex(String projectId) =>
      _get(projectId: projectId, kind: DurableProjectRecordKind.assetIndex);

  Future<List<AssetLibraryItem>> loadAssetLibrary(String projectId) async {
    final raw = await _get(
      projectId: projectId,
      kind: DurableProjectRecordKind.assetLibrary,
    );
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = <AssetLibraryItem>[];
      for (final value in decoded) {
        if (value is! Map) continue;
        try {
          final item = AssetLibraryItem.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (item.scopeId == projectId) items.add(item);
        } catch (_) {
          // Ignore one malformed catalog item and recover the rest.
        }
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAssetLibrary(
    String projectId,
    Iterable<AssetLibraryItem> items,
  ) => _put(
    projectId: projectId,
    kind: DurableProjectRecordKind.assetLibrary,
    payload: jsonEncode(
      items
          .where((item) => item.scopeId == projectId)
          .map((item) => item.toJson())
          .toList(growable: false),
    ),
    schemaVersion: 1,
  );

  Future<void> writeAssetQueue({
    required String projectId,
    required String queueJson,
    int schemaVersion = 1,
  }) => _put(
    projectId: projectId,
    kind: DurableProjectRecordKind.assetQueue,
    payload: queueJson,
    schemaVersion: schemaVersion,
  );

  Future<String?> readAssetQueue(String projectId) =>
      _get(projectId: projectId, kind: DurableProjectRecordKind.assetQueue);

  Future<void> writeCollaborationQueue({
    required String projectId,
    required String queueJson,
    int schemaVersion = 1,
    String? accountId,
    int? generation,
  }) => _put(
    projectId: projectId,
    kind: DurableProjectRecordKind.collaborationQueue,
    payload: queueJson,
    schemaVersion: schemaVersion,
    recordKey: _collaborationQueueRecordKey(
      accountId: accountId,
      generation: generation,
    ),
  );

  Future<String?> readCollaborationQueue(
    String projectId, {
    String? accountId,
    int? generation,
  }) => _get(
    projectId: projectId,
    kind: DurableProjectRecordKind.collaborationQueue,
    recordKey: _collaborationQueueRecordKey(
      accountId: accountId,
      generation: generation,
    ),
  );

  Future<void> clearCollaborationQueue(
    String projectId, {
    String? accountId,
    int? generation,
  }) => deleteRecord(
    projectId: projectId,
    kind: DurableProjectRecordKind.collaborationQueue,
    recordKey: _collaborationQueueRecordKey(
      accountId: accountId,
      generation: generation,
    ),
  );

  static String _collaborationQueueRecordKey({
    String? accountId,
    int? generation,
  }) {
    final owner = accountId?.trim();
    if ((owner == null || owner.isEmpty) && generation == null) {
      return 'default';
    }
    if (generation == null || generation < 0) {
      throw ArgumentError.value(
        generation,
        'generation',
        'A non-negative queue generation is required for scoped queues.',
      );
    }
    final normalizedOwner = owner == null || owner.isEmpty
        ? 'anonymous'
        : owner;
    final encodedOwner = base64Url.encode(utf8.encode(normalizedOwner));
    return 'collaboration:$encodedOwner:$generation';
  }

  Future<void> clearAutoCheckpoints(String projectId) => deleteRecord(
    projectId: projectId,
    kind: DurableProjectRecordKind.autoCheckpoint,
  );

  Future<void> clearHistory(String projectId) => deleteRecord(
    projectId: projectId,
    kind: DurableProjectRecordKind.history,
  );

  Future<void> deleteRecord({
    required String projectId,
    required DurableProjectRecordKind kind,
    String recordKey = 'default',
  }) async {
    _validateProjectId(projectId);
    _validateRecordKey(recordKey);
    await _ensureReady();
    await _database.transaction(() async {
      await _database.customStatement(
        '''
        DELETE FROM project_records
        WHERE project_id = ? AND record_kind = ? AND record_key = ?
        ''',
        [projectId, kind.wireName, recordKey],
      );
    });
  }

  Future<void> purgeProject(String projectId) => purgeProjects([projectId]);

  /// Removes every durable record owned by [projectIds] in one transaction.
  ///
  /// Migration state is intentionally retained: it belongs to the local
  /// migration ledger rather than to a project record, and removing it would
  /// make a later legacy migration ambiguous.
  Future<void> purgeProjects(Iterable<String> projectIds) async {
    final ids = projectIds.toSet();
    if (ids.isEmpty) return;
    for (final projectId in ids) {
      _validateProjectId(projectId);
    }
    await _ensureReady();
    await _database.transaction(() async {
      for (final projectId in ids) {
        await _database.customStatement(
          'DELETE FROM project_records WHERE project_id = ?',
          [projectId],
        );
      }
    });
  }

  /// Atomically marks a migration as in progress or complete.
  Future<void> setMigrationState({
    required String migrationId,
    required String state,
  }) async {
    _validateMigrationId(migrationId);
    if (state.trim().isEmpty) {
      throw ArgumentError.value(state, 'state', 'Migration state is required.');
    }
    await _ensureReady();
    await _database.transaction(() async {
      await _database.customStatement(
        '''
        INSERT INTO project_migration_state (migration_id, state, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(migration_id) DO UPDATE SET
          state = excluded.state,
          updated_at = excluded.updated_at
        ''',
        [migrationId, state, DateTime.now().toUtc().millisecondsSinceEpoch],
      );
    });
  }

  Future<String?> getMigrationState(String migrationId) async {
    _validateMigrationId(migrationId);
    await _ensureReady();
    final rows = await _database
        .customSelect(
          'SELECT state FROM project_migration_state WHERE migration_id = ?',
          variables: [Variable.withString(migrationId)],
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.single.data['state'] as String?;
  }

  /// Migrates one verified legacy payload atomically.
  ///
  /// The caller supplies a read callback so the legacy adapter can keep its
  /// existing compatibility rules. The legacy value is not removed here.
  /// This is intentional: a verified durable row is required before cleanup.
  Future<bool> migrateLegacyRecord({
    required String migrationId,
    required String projectId,
    required DurableProjectRecordKind kind,
    required Future<String?> Function() readLegacy,
    int schemaVersion = 1,
    bool Function(String payload)? verify = _defaultVerify,
  }) async {
    _validateProjectId(projectId);
    _validateMigrationId(migrationId);
    await _ensureReady();
    final existing = await _get(projectId: projectId, kind: kind);
    if (existing != null) {
      await setMigrationState(migrationId: migrationId, state: 'complete');
      return true;
    }
    await setMigrationState(migrationId: migrationId, state: 'running');
    final legacy = await readLegacy();
    if (legacy == null || legacy.isEmpty || !(verify?.call(legacy) ?? true)) {
      await setMigrationState(migrationId: migrationId, state: 'blocked');
      return false;
    }
    try {
      await _database.transaction(() async {
        // The legacy read happens before this transaction so it cannot block
        // the first local frame. A newer autosave may therefore win the race
        // while the migration is waiting for its source value. Re-check inside
        // the write transaction and never overwrite an existing durable row.
        final current = await _getUnlocked(projectId: projectId, kind: kind);
        if (current == null) {
          await _putUnlocked(
            projectId: projectId,
            kind: kind,
            payload: legacy,
            schemaVersion: schemaVersion,
          );
          final verified = await _getUnlocked(projectId: projectId, kind: kind);
          if (verified != legacy) {
            throw StateError('Durable migration verification failed.');
          }
        }
        await _database.customStatement(
          '''
          INSERT INTO project_migration_state (migration_id, state, updated_at)
          VALUES (?, 'complete', ?)
          ON CONFLICT(migration_id) DO UPDATE SET
            state = 'complete', updated_at = excluded.updated_at
          ''',
          [migrationId, DateTime.now().toUtc().millisecondsSinceEpoch],
        );
      });
      return true;
    } catch (_) {
      await setMigrationState(migrationId: migrationId, state: 'retryable');
      rethrow;
    }
  }

  Future<void> _put({
    required String projectId,
    required DurableProjectRecordKind kind,
    required String payload,
    required int schemaVersion,
    String recordKey = 'default',
  }) async {
    _validateProjectId(projectId);
    _validateRecordKey(recordKey);
    if (payload.isEmpty) {
      throw ArgumentError.value(
        payload,
        'payload',
        'Durable payload is empty.',
      );
    }
    if (schemaVersion < 1) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Durable schema version must be positive.',
      );
    }
    await _ensureReady();
    await _database.transaction(
      () => _putUnlocked(
        projectId: projectId,
        kind: kind,
        payload: payload,
        schemaVersion: schemaVersion,
        recordKey: recordKey,
      ),
    );
  }

  Future<void> _putUnlocked({
    required String projectId,
    required DurableProjectRecordKind kind,
    required String payload,
    required int schemaVersion,
    String recordKey = 'default',
  }) async {
    await _database.customStatement(
      '''
      INSERT INTO project_records
        (project_id, record_kind, record_key, payload, schema_version, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(project_id, record_kind, record_key) DO UPDATE SET
        payload = excluded.payload,
        schema_version = excluded.schema_version,
        updated_at = excluded.updated_at
      ''',
      [
        projectId,
        kind.wireName,
        recordKey,
        payload,
        schemaVersion,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  Future<String?> _get({
    required String projectId,
    required DurableProjectRecordKind kind,
    String recordKey = 'default',
  }) async {
    _validateProjectId(projectId);
    _validateRecordKey(recordKey);
    await _ensureReady();
    return _getUnlocked(projectId: projectId, kind: kind, recordKey: recordKey);
  }

  Future<String?> _getUnlocked({
    required String projectId,
    required DurableProjectRecordKind kind,
    String recordKey = 'default',
  }) async {
    _validateRecordKey(recordKey);
    final rows = await _database
        .customSelect(
          '''
      SELECT payload FROM project_records
      WHERE project_id = ? AND record_kind = ? AND record_key = ?
      ''',
          variables: [
            Variable.withString(projectId),
            Variable.withString(kind.wireName),
            Variable.withString(recordKey),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.single.data['payload'] as String?;
  }

  static bool _defaultVerify(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map || decoded is List;
    } catch (_) {
      return false;
    }
  }

  static void _validateProjectId(String value) {
    if (value.trim().isEmpty || value != value.trim()) {
      throw ArgumentError.value(value, 'projectId', 'Project ID is required.');
    }
  }

  static void _validateMigrationId(String value) {
    if (value.trim().isEmpty || value != value.trim()) {
      throw ArgumentError.value(
        value,
        'migrationId',
        'Migration ID is required.',
      );
    }
  }

  static void _validateRecordKey(String value) {
    if (value.isEmpty || value.length > 200 || value != value.trim()) {
      throw ArgumentError.value(value, 'recordKey', 'Record key is invalid.');
    }
  }
}

/// Encodes a JSON-safe payload for a store method that accepts bytes.
String durableJsonFromBytes(Uint8List bytes) => utf8.decode(bytes);
