import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/supabase_bootstrap.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/features/canvas/presentation/canvas_screen.dart';
import 'package:varian/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens a guest canvas with its Workspace panel', (tester) async {
    tester.view.physicalSize = const Size(929, 1016);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    defaultSupabaseBootstrap.markUnavailable();
    final durableStore = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    addTearDown(durableStore.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          durableProjectStoreProvider.overrideWithValue(durableStore),
          supabaseClientProvider.overrideWithValue(null),
        ],
        child: const CreativeCanvasApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CanvasScreen), findsOneWidget);

    final guestProjectId = tester
        .widget<CanvasScreen>(find.byType(CanvasScreen))
        .projectId;
    final router = GoRouter.of(tester.element(find.byType(CanvasScreen)));
    final compactMenu = find.byKey(const ValueKey('ui-compact-actions-menu'));
    expect(compactMenu, findsOneWidget);
    expect(find.byTooltip('Workspace'), findsNothing);
    expect(find.text('Untitled Project'), findsOneWidget);

    await tester.tap(compactMenu);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Canvas menu'), findsOneWidget);
    expect(find.byTooltip('Workspace'), findsNothing);
    await tester.tapAt(const Offset(12, 300));
    await tester.pumpAndSettle();
    expect(find.text('Canvas menu'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('canvas-document-title-target')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('canvas-document-title-editor')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('canvas-document-title-editor')),
      'My canvas',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.routeInformationProvider.value.uri.path, '/auth');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['returnTo'],
      '/canvas/save',
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        'ccs_guest_pending_document_title',
      ),
      'My canvas',
    );

    await tester.tap(find.byTooltip('Back to canvas'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Untitled Project'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'ccs_guest_pending_document_title',
      ),
      isNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          durableProjectStoreProvider.overrideWithValue(durableStore),
          supabaseClientProvider.overrideWithValue(null),
        ],
        child: const CreativeCanvasApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CanvasScreen), findsOneWidget);
    expect(find.text('Untitled Project'), findsOneWidget);
    expect(find.byTooltip('Workspace'), findsNothing);

    router.go('/library');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(CanvasScreen), findsOneWidget);
    expect(await durableStore.loadCanvasDocument(guestProjectId), isNotNull);

    await tester.tap(find.byKey(const ValueKey('ui-compact-actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canvas-save-workspace')));
    await tester.pumpAndSettle();
    final menuTransitionException = tester.takeException();
    expect(
      menuTransitionException,
      isNull,
      reason:
          'Closing the anchored Canvas menu during navigation must not '
          'leave stale semantics nodes.',
    );
    expect(router.routeInformationProvider.value.uri.path, '/auth');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['returnTo'],
      '/canvas/save',
    );

    expect(await durableStore.loadCanvasDocument(guestProjectId), isNotNull);
    final projectsJson = (await SharedPreferences.getInstance()).getString(
      'ccs_local_projects_list',
    );
    expect(projectsJson ?? '', isNot(contains(guestProjectId)));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
