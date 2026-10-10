import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/supabase_sync_provider.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/capture/data/capture_asset_store.dart';
import 'package:varian/features/capture/data/capture_repository.dart';
import 'package:varian/features/capture/domain/capture_canvas_handoff.dart';
import 'package:varian/features/capture/domain/capture_item.dart';
import 'package:varian/features/capture/presentation/capture_inbox_panel.dart';
import 'package:varian/features/capture/state/capture_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('chooser lists active local projects but excludes rooms', (
    tester,
  ) async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final item = await repository.createCapture(CaptureInput.text('Keep me'));
    await _seedProjects([
      _project('active-local', 'Active local'),
      _project(
        'archived-local',
        'Archived local',
        status: ProjectStatus.archived,
      ),
      _project('trashed-local', 'Trashed local', status: ProjectStatus.trashed),
      _project('room-owner', 'Room owner', collaborationRoomCode: '123456'),
      _project('room-editor', 'Room editor', collaborationRoomCode: '123457'),
      _project('room-viewer', 'Room viewer', collaborationRoomCode: '123458'),
      _project(
        'room-commenter',
        'Room commenter',
        collaborationRoomCode: '123459',
      ),
    ]);
    final router = _router();
    await tester.pumpWidget(_host(repository, router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Capture actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to canvas'));
    await tester.pumpAndSettle();

    expect(find.text('Add capture to canvas'), findsOneWidget);
    expect(find.text('Active local'), findsOneWidget);
    expect(find.text('Archived local'), findsNothing);
    expect(find.text('Trashed local'), findsNothing);
    expect(find.text('Room owner'), findsNothing);
    expect(find.text('Room editor'), findsNothing);
    expect(find.text('Room viewer'), findsNothing);
    expect(find.text('Room commenter'), findsNothing);
    expect(await repository.getCapture(item.id), isNotNull);
  });

  testWidgets('cancelling the chooser keeps the Inbox capture unchanged', (
    tester,
  ) async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final item = await repository.createCapture(CaptureInput.text('Keep me'));
    await _seedProjects([_project('active-local', 'Active local')]);
    final router = _router();
    await tester.pumpWidget(_host(repository, router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Capture actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to canvas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    final unchanged = await repository.getCapture(item.id);
    expect(unchanged?.status, CaptureStatus.ready);
    expect(unchanged?.isRead, isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('selecting a project hands off only through router extra', (
    tester,
  ) async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final item = await repository.createCapture(CaptureInput.text('Keep me'));
    await _seedProjects([_project('project space', 'Target project')]);
    CaptureCanvasHandoff? received;
    final router = _router(onHandoff: (handoff) => received = handoff);
    await tester.pumpWidget(_host(repository, router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Capture actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to canvas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target project'));
    await tester.pumpAndSettle();

    expect(find.text('Project project space'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters, isEmpty);
    expect(received?.projectId, 'project space');
    expect(received?.captureId, item.id);
    expect(received?.isConsumed, isFalse);
    expect(await repository.getCapture(item.id), isNotNull);
  });

  testWidgets('compact chooser scrolls project actions and cancel into view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    await repository.createCapture(CaptureInput.text('Keep me'));
    await _seedProjects([
      for (var index = 0; index < 12; index++)
        _project('small-$index', 'Project $index'),
    ]);
    final router = _router();
    await tester.pumpWidget(_host(repository, router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Capture actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to canvas'));
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(Scrollable),
    );
    expect(find.text('Add capture to canvas'), findsOneWidget);
    final scrollableRect = tester.getRect(scrollable);
    expect(scrollableRect.top, greaterThanOrEqualTo(0));
    expect(scrollableRect.bottom, lessThanOrEqualTo(320));
    await tester.scrollUntilVisible(
      find.text('Project 11'),
      160,
      scrollable: scrollable,
    );
    expect(find.text('Project 11'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('CANCEL'),
      160,
      scrollable: scrollable,
    );
    expect(find.text('CANCEL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _seedProjects(List<LocalProjectMetadata> projects) async {
  await LocalStorageService().saveProjectMetadata(projects.first);
  for (final project in projects.skip(1)) {
    await LocalStorageService().saveProjectMetadata(project);
  }
}

LocalProjectMetadata _project(
  String id,
  String name, {
  ProjectStatus status = ProjectStatus.active,
  String? collaborationRoomCode,
}) {
  final now = DateTime.utc(2026, 9, 27);
  return LocalProjectMetadata(
    id: id,
    name: name,
    createdAt: now,
    updatedAt: now,
    status: status,
    collaborationRoomCode: collaborationRoomCode,
    collaborationRole: collaborationRoomCode == null ? null : 'viewer',
    collaborationAccountId: collaborationRoomCode == null ? null : 'account-1',
  );
}

Widget _host(LocalCaptureRepository repository, GoRouter router) =>
    ProviderScope(
      overrides: [
        captureRepositoryProvider.overrideWithValue(repository),
        supabaseSyncServiceProvider.overrideWithValue(
          SupabaseSyncService(null),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => AppThemeScope(
          data: AppTheme.darkTheme,
          child: SizedBox(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );

GoRouter _router({void Function(CaptureCanvasHandoff handoff)? onHandoff}) =>
    GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              SingleChildScrollView(child: const CaptureInboxPanel()),
        ),
        GoRoute(
          path: '/project/:projectId',
          builder: (context, state) {
            final handoff = state.extra;
            if (handoff is CaptureCanvasHandoff) onHandoff?.call(handoff);
            return Scaffold(
              body: Text('Project ${state.pathParameters['projectId']}'),
            );
          },
        ),
      ],
    );
