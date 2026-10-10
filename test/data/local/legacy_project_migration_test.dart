import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/legacy_project_migration.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/domain/models/document.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('one corrupt legacy project does not block a later project', () async {
    final legacy = LocalStorageService();
    final now = DateTime.utc(2026, 1, 2);
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([
        {
          'id': 'project-bad',
          'name': 'Bad',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'status': 'active',
        },
        {
          'id': 'project-good',
          'name': 'Good',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'status': 'active',
        },
      ]),
      'ccs_doc_project-bad': '{bad-json',
      'ccs_doc_project-good': jsonEncode(
        CanvasDocument(projectId: 'project-good', updatedAt: now).toJson(),
      ),
    });

    final database = ProjectDurableDatabase(NativeDatabase.memory());
    final store = DurableProjectStore(database: database);
    addTearDown(store.close);

    await LegacyProjectMigration(store: store, legacy: legacy).run();

    expect(await store.readDocument('project-bad'), isNull);
    expect(await store.readDocument('project-good'), isNotNull);
  });
}
