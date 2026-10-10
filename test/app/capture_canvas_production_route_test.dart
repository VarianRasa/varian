import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/supabase_bootstrap.dart';
import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/canvas/presentation/canvas_screen.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/capture/data/capture_asset_store.dart';
import 'package:varian/features/capture/data/capture_repository.dart';
import 'package:varian/features/capture/domain/capture_canvas_handoff.dart';
import 'package:varian/features/capture/domain/capture_item.dart';
import 'package:varian/features/capture/state/capture_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/features/home/presentation/home_screen.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store_types.dart';
import 'package:varian/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Capture Inbox text is inserted through the production project route',
    (tester) async {
      const projectId = 'local-capture-canvas-fixture';
      const projectName = 'Local capture target';
      const captureText = 'Fixture note reaches the canvas';
      final now = DateTime.utc(2026, 10, 3);
      final metadata = LocalProjectMetadata(
        id: projectId,
        name: projectName,
        createdAt: now,
        updatedAt: now,
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
      });
      defaultSupabaseBootstrap.markUnavailable();

      final captureRepository = LocalCaptureRepository(
        assetStore: MemoryCaptureAssetStore(),
      );
      final artifactStores = ArtifactStoreBundle(
        imageArtifactStore: MemoryImageArtifactStore(),
        fileArtifactStore: MemoryFileArtifactStore(),
        mediaArtifactStore: MemoryMediaArtifactStore(),
        videoArtifactStore: MemoryVideoArtifactStore(),
        model3DArtifactStore: MemoryModel3DArtifactStore(),
      );
      var failNextDurableSnapshotWrite = false;
      final durableStore = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
        beforeSnapshotWrite: () async {
          if (!failNextDurableSnapshotWrite) return;
          failNextDurableSnapshotWrite = false;
          throw StateError('fixture durable write failure');
        },
      );
      final syncService = SupabaseSyncService(
        null,
        artifactStoreBundle: artifactStores,
      );
      final localStorage = LocalStorageService(
        artifactStoreBundle: artifactStores,
        durableProjectStore: durableStore,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            captureRepositoryProvider.overrideWithValue(captureRepository),
            artifactStoreBundleProvider.overrideWithValue(artifactStores),
            durableProjectStoreProvider.overrideWithValue(durableStore),
            localStorageServiceProvider.overrideWithValue(localStorage),
            supabaseSyncServiceProvider.overrideWithValue(syncService),
            supabaseClientProvider.overrideWithValue(null),
          ],
          child: const CreativeCanvasApp(),
        ),
      );
      await tester.pumpAndSettle();

      final capture = await captureRepository.createCapture(
        CaptureInput.text(captureText),
      );
      final router = GoRouter.of(tester.element(find.byType(CanvasScreen)));
      router.go(
        '/project/$projectId',
        extra: CaptureCanvasHandoff(
          projectId: projectId,
          accountId: null,
          captureId: capture.id,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('project-route-editor')),
        findsOneWidget,
      );
      expect(find.byType(CanvasScreen), findsOneWidget);
      expect(
        tester.widget<CanvasScreen>(find.byType(CanvasScreen)).projectId,
        projectId,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CanvasScreen)),
      );
      final nodes = container.read(documentNodesProvider);
      final inserted = nodes.singleWhere((node) => node.type == NodeType.text);
      expect((inserted.payload as TextPayload).text, captureText);

      final captures = await captureRepository.listCaptures();
      expect(captures, hasLength(1));
      expect(captures.single.text, captureText);
      expect(captures.single.status, CaptureStatus.ready);
      expect(captures.single.isRead, isFalse);
      final autosave = container.read(autosaveControllerProvider);
      expect(autosave.activeProjectId, projectId);
      failNextDurableSnapshotWrite = true;
      router.go('/');
      await tester.pumpAndSettle();
      expect(find.byType(CanvasScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(autosave.activeProjectId, projectId);
      expect(tester.takeException(), isNull);

      router.go('/project/$projectId');
      await tester.pumpAndSettle();
      expect(find.byType(CanvasScreen), findsOneWidget);
      router.go('/');
      await tester.pumpAndSettle();

      expect(find.byType(CanvasScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(
        tester.widget<CanvasScreen>(find.byType(CanvasScreen)).projectId,
        isNot(projectId),
      );
      final guestProjectId = tester
          .widget<CanvasScreen>(find.byType(CanvasScreen))
          .projectId;
      expect(router.routeInformationProvider.value.uri.path, '/');
      final savedOnExit = await durableStore.loadCanvasDocument(projectId);
      expect(
        savedOnExit?.nodes.any(
          (node) =>
              node.type == NodeType.text &&
              (node.payload as TextPayload).text == captureText,
        ),
        isTrue,
      );
      await autosave.flushAndDeactivateProject(guestProjectId);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      syncService.dispose();
      await durableStore.close();
    },
  );
}
