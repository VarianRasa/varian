import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/domain/models/document.dart';

void main() {
  test('session rejects documents from another project', () async {
    final database = ProjectDurableDatabase(NativeDatabase.memory());
    final store = DurableProjectStore(database: database);
    final session = ProjectSession(projectId: 'project-a', store: store);
    addTearDown(store.close);

    final document = CanvasDocument(
      projectId: 'project-b',
      updatedAt: DateTime.utc(2026, 1, 2),
    );

    await expectLater(
      session.saveDocument(document),
      throwsA(isA<StateError>()),
    );
  });

  test('disposed session invalidates its lifecycle generation', () async {
    final database = ProjectDurableDatabase(NativeDatabase.memory());
    final store = DurableProjectStore(database: database);
    final session = ProjectSession(projectId: 'project-a', store: store);
    addTearDown(store.close);

    expect(session.isDisposed, isFalse);
    final generation = session.generation;
    session.dispose();

    expect(session.isDisposed, isTrue);
    expect(session.generation, greaterThan(generation));
    expect(() => session.loadDocument(), throwsA(isA<StateError>()));
  });

  test(
    'provider-owned project sessions remain active after read-only access',
    () {
      final database = ProjectDurableDatabase(NativeDatabase.memory());
      final store = DurableProjectStore(database: database);
      final container = ProviderContainer(
        overrides: [durableProjectStoreProvider.overrideWithValue(store)],
      );
      addTearDown(() async {
        container.dispose();
        await store.close();
      });

      final projectA = container.read(projectSessionProvider('project-a'));
      final projectB = container.read(projectSessionProvider('project-b'));

      expect(projectA.store, same(store));
      expect(projectB.store, same(store));
      expect(projectA.isDisposed, isFalse);
      expect(projectB.isDisposed, isFalse);
    },
  );
}
