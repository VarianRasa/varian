import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../features/history/snapshot_manager.dart';
import '../local_storage_service.dart';
import 'durable_project_store.dart';

/// Copies recoverable project data from SharedPreferences into the durable
/// project store without deleting the compatibility source.
final class LegacyProjectMigration {
  LegacyProjectMigration({required this.store, required this.legacy});

  final DurableProjectStore store;
  final LocalStorageService legacy;

  Future<void> run() async {
    final projects = await legacy.getProjects();
    for (final project in projects) {
      try {
        await migrateProject(project.id);
      } catch (error) {
        // One corrupt or unavailable legacy project must not prevent the
        // remaining projects from becoming durable.
        debugPrint(
          '[LegacyProjectMigration] Project ${project.id} deferred: $error',
        );
      }
    }
  }

  Future<void> migrateProject(String projectId) async {
    final document = await legacy.loadDocument(projectId);
    if (document != null && document.projectId == projectId) {
      await store.migrateLegacyRecord(
        migrationId: 'document-$projectId-v1',
        projectId: projectId,
        kind: DurableProjectRecordKind.document,
        readLegacy: () async => jsonEncode(document.toPersistenceJson()),
        verify: _isJsonObject,
      );
      await store.migrateLegacyRecord(
        migrationId: 'recovery-$projectId-v1',
        projectId: projectId,
        kind: DurableProjectRecordKind.recovery,
        readLegacy: () async => jsonEncode(document.toPersistenceJson()),
        verify: _isJsonObject,
      );
    }

    await _migrateJsonList(
      projectId: projectId,
      kind: DurableProjectRecordKind.history,
      migrationId: 'history-$projectId-v1',
      read: () async => _encodeRecords(await legacy.loadVersions(projectId)),
    );
    await _migrateJsonList(
      projectId: projectId,
      kind: DurableProjectRecordKind.autoCheckpoint,
      migrationId: 'checkpoints-$projectId-v1',
      read: () async =>
          _encodeRecords(await legacy.loadAutoCheckpoints(projectId)),
    );
    try {
      final navigation = await legacy.loadCanvasNavigation(projectId);
      await store.migrateLegacyRecord(
        migrationId: 'viewport-$projectId-v1',
        projectId: projectId,
        kind: DurableProjectRecordKind.viewport,
        readLegacy: () async => jsonEncode(navigation.toJson()),
        verify: _isJsonObject,
      );
    } catch (_) {
      // Projects created before canvas navigation existed have no record.
    }
  }

  Future<void> _migrateJsonList({
    required String projectId,
    required DurableProjectRecordKind kind,
    required String migrationId,
    required Future<String?> Function() read,
  }) async {
    await store.migrateLegacyRecord(
      migrationId: migrationId,
      projectId: projectId,
      kind: kind,
      readLegacy: read,
      verify: (payload) {
        try {
          return jsonDecode(payload) is List;
        } catch (_) {
          return false;
        }
      },
    );
  }

  static String? _encodeRecords(List<DocumentSnapshotRecord> records) =>
      records.isEmpty
      ? null
      : jsonEncode(
          records.map((record) => record.toPersistenceJson()).toList(),
        );

  static bool _isJsonObject(String payload) {
    try {
      return jsonDecode(payload) is Map;
    } catch (_) {
      return false;
    }
  }
}
