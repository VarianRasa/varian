import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/canvas/presentation/guest_canvas_promotion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'promotes a durable guest draft before consuming its pending title',
    () async {
      const projectId = 'guest-promotion-draft';
      const title = 'Saved after sign in';
      SharedPreferences.setMockInitialValues({
        'ccs_guest_canvas_draft_id': projectId,
        'ccs_guest_pending_document_title': title,
      });
      final preferences = await SharedPreferences.getInstance();
      final store = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(store.close);
      final storage = LocalStorageService(durableProjectStore: store);
      final session = ProjectSession(projectId: projectId, store: store);
      final draft = CanvasDocument(
        projectId: projectId,
        updatedAt: DateTime.now(),
      );

      expect(await storage.getProjects(), isEmpty);
      expect(await store.loadCanvasDocument(projectId), isNull);

      await promoteGuestCanvasDraft(
        projectId: projectId,
        draft: draft,
        storage: storage,
        session: session,
        preferences: preferences,
      );

      final projects = await storage.getProjects();
      expect(projects.single.id, projectId);
      expect(projects.single.name, title);
      expect(await store.loadCanvasDocument(projectId), isNotNull);
      expect(preferences.getString('ccs_guest_canvas_draft_id'), isNull);
      expect(preferences.getString('ccs_guest_pending_document_title'), isNull);
    },
  );

  test('retains the staged title when durable promotion fails', () async {
    const projectId = 'guest-promotion-failure';
    const title = 'Keep until save succeeds';
    SharedPreferences.setMockInitialValues({
      'ccs_guest_canvas_draft_id': projectId,
      'ccs_guest_pending_document_title': title,
    });
    final preferences = await SharedPreferences.getInstance();
    final store = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
      beforeSnapshotWrite: () async =>
          throw StateError('fixture durable write failure'),
    );
    addTearDown(store.close);
    final storage = LocalStorageService(durableProjectStore: store);
    final session = ProjectSession(projectId: projectId, store: store);
    final draft = CanvasDocument(
      projectId: projectId,
      updatedAt: DateTime.now(),
    );

    await expectLater(
      promoteGuestCanvasDraft(
        projectId: projectId,
        draft: draft,
        storage: storage,
        session: session,
        preferences: preferences,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await storage.getProjects(), isEmpty);
    expect(await store.loadCanvasDocument(projectId), isNull);
    expect(preferences.getString('ccs_guest_canvas_draft_id'), projectId);
    expect(preferences.getString('ccs_guest_pending_document_title'), title);
  });
}
