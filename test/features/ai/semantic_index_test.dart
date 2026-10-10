import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/ai/domain/semantic_index.dart';
import 'package:varian/features/ai/state/semantic_index_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('search ranks title and filters record kinds', () {
    final index = SemanticIndex.empty('project-1').replaceAll([
      SemanticIndexRecord(
        id: 'node-hero',
        kind: SemanticRecordKind.node,
        title: 'Hero headline',
        content: 'Build a faster canvas',
        updatedAt: DateTime.utc(2026, 9, 13, 8),
      ),
      SemanticIndexRecord(
        id: 'comment-1',
        kind: SemanticRecordKind.comment,
        title: 'Review note',
        content: 'The hero needs a stronger contrast.',
        updatedAt: DateTime.utc(2026, 9, 13, 9),
      ),
    ]);

    final results = index.search('hero');
    expect(results.first.record.id, 'node-hero');
    expect(
      index.search('hero', kind: SemanticRecordKind.comment),
      hasLength(1),
    );
    expect(index.search('missing'), isEmpty);
    expect(results.first.matchedTokens, contains('hero'));
  });

  test('serializes metadata and deduplicates records by kind and id', () {
    final now = DateTime.utc(2026, 9, 13);
    final index = SemanticIndex(
      projectId: 'project-1',
      updatedAt: now,
      records: [
        SemanticIndexRecord(
          id: 'asset-1',
          kind: SemanticRecordKind.asset,
          title: 'Logo',
          updatedAt: now,
          metadata: const {'license': 'CC0', 'size': 42},
        ),
        SemanticIndexRecord(
          id: 'asset-1',
          kind: SemanticRecordKind.asset,
          title: 'Old logo',
          updatedAt: now.subtract(const Duration(hours: 1)),
        ),
      ],
    );

    final restored = SemanticIndex.fromJson(index.toJson());

    expect(restored.projectId, 'project-1');
    expect(restored.updatedAt, now);
    expect(restored.records, hasLength(1));
    expect(restored.records.single.title, 'Old logo');
    expect(restored.records.single.metadata['license'], isNull);
  });

  test('provider persists and removes indexed records', () async {
    final storage = LocalStorageService();
    final notifier = SemanticIndexNotifier(storage, 'project-1');
    addTearDown(notifier.dispose);
    await notifier.ready;

    final record = SemanticIndexRecord(
      id: 'version-1',
      kind: SemanticRecordKind.version,
      title: 'Approved handoff',
      content: 'Final review version',
      updatedAt: DateTime.utc(2026, 9, 13),
    );
    await notifier.upsert(record);
    expect(notifier.search('handoff').single.record.id, 'version-1');

    final persisted = await storage.loadSemanticIndex('project-1');
    expect(persisted.records.single.id, 'version-1');

    await notifier.remove(id: 'version-1', kind: SemanticRecordKind.version);
    expect(notifier.search('handoff'), isEmpty);
    expect((await storage.loadSemanticIndex('project-1')).records, isEmpty);
  });
}
