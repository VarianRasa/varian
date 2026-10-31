import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/varian_logo.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/home/presentation/home_screen.dart';
import 'package:varian/features/home/state/home_provider.dart';
import 'package:drift/native.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/domain/models/cloud_project_deletion.dart';
import 'package:varian/features/home/presentation/widgets/cloud_project_deletion_dialog.dart';
import '../../test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  String encodeTestPart(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  Future<void> authenticateTestClient(SupabaseClient client) async {
    final expiration =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    final token =
        '${encodeTestPart({'alg': 'HS256'})}.${encodeTestPart({'sub': 'account-1', 'exp': expiration})}.signature';
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'token_type': 'bearer',
        'expires_at': expiration,
        'expires_in': 3600,
        'refresh_token': 'refresh-token',
        'user': {
          'id': 'account-1',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-10-01T00:00:00Z',
        },
      }),
    );
  }

  Future<void> pumpHome(
    WidgetTester tester,
    List<LocalProjectMetadata> projects, {
    Locale locale = const Locale('en'),
    DurableProjectStore? durableStore,
    List<Override> providerOverrides = const [],
  }) async {
    final overrides = [
      ...providerOverrides,
      if (durableStore != null)
        durableProjectStoreProvider.overrideWithValue(durableStore),
    ];
    final prefs = <String, Object>{
      'ccs_local_projects_list': jsonEncode(
        projects.map((project) => project.toJson()).toList(),
      ),
    };
    SharedPreferences.setMockInitialValues(prefs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: testApp(const HomeScreen(), locale: locale),
      ),
    );
    await tester.pumpAndSettle();
  }

  LocalProjectMetadata project(
    String id,
    String name, {
    ProjectStatus status = ProjectStatus.active,
    bool pinned = false,
  }) {
    final created = DateTime(2026, 8, 25, 10);
    return LocalProjectMetadata(
      id: id,
      name: name,
      createdAt: created,
      updatedAt: created.add(Duration(hours: id.length)),
      status: status,
      isPinned: pinned,
    );
  }

  testWidgets('legacy default project titles use their creation timestamp', (
    tester,
  ) async {
    final created = DateTime(2026, 10, 2, 7, 4);
    final legacy = LocalProjectMetadata(
      id: 'legacy-default',
      name: 'Untitled Doc',
      createdAt: created,
      updatedAt: created,
    );
    final custom = project('custom-project', 'My canvas');

    await pumpHome(tester, [legacy, custom]);

    expect(find.text('2026-10-02 07:04'), findsOneWidget);
    expect(find.text('Untitled Doc'), findsNothing);
    expect(find.text('My canvas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project-library error icon uses the compact control token', (
    tester,
  ) async {
    final storage = LocalStorageService();
    final tabs = OpenDocumentTabsNotifier(storage);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          openDocumentTabsProvider.overrideWith((ref) => tabs),
          homeProjectsProvider.overrideWith(
            (ref) => _FailedHomeProjectsNotifier(ref, storage, tabs),
          ),
        ],
        child: testApp(const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Icon>(find.byIcon(Icons.cloud_off_outlined)).size,
      AppControlSize.compact,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('requires confirmation before adopting a local project', (
    tester,
  ) async {
    final metadata = LocalProjectMetadata(
      id: 'adopt-project',
      name: 'Local canvas',
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
    );
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/rest/v1/projects' => http.Response(
            jsonEncode([]),
            200,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-0/0',
            },
            request: request,
          ),
          _ => throw StateError('Unexpected cloud request: ${request.url}'),
        };
      }),
    );
    await authenticateTestClient(client);
    addTearDown(() => client.auth.stopAutoRefresh());
    final user = User(
      id: 'account-1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-10-01T00:00:00Z',
      isAnonymous: false,
    );
    final store = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    addTearDown(store.close);
    final prefs = <String, Object>{
      'ccs_local_projects_list': jsonEncode([metadata.toJson()]),
    };
    SharedPreferences.setMockInitialValues(prefs);
    final providers = [
      supabaseClientProvider.overrideWithValue(client),
      supabaseSyncServiceProvider.overrideWithValue(
        SupabaseSyncService(client),
      ),
      authUserProvider.overrideWith((ref) => Stream.value(user)),
    ];
    await pumpHome(
      tester,
      [metadata],
      durableStore: store,
      providerOverrides: providers,
    );

    final actions = find.bySemanticsLabel('Project actions');
    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adopt to cloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Adopt project to cloud?'), findsOneWidget);
    expect(
      requests.any(
        (request) =>
            request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership' ||
            request.method != 'GET',
      ),
      isFalse,
    );

    await tester.tap(find.text('CANCEL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      requests.any(
        (request) =>
            request.url.path == '/rest/v1/rpc/claim_canvas_project_ownership' ||
            request.method != 'GET',
      ),
      isFalse,
    );
    expect(
      (await LocalStorageService().getProjects()).single.cloudOwnerId,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps archived documents discoverable in the status tabs', (
    tester,
  ) async {
    await pumpHome(tester, [
      project('active', 'Current brief'),
      project('archived', 'Old campaign', status: ProjectStatus.archived),
    ]);

    expect(find.byKey(const ValueKey('project-status-tabs')), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Trash'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Old campaign'), findsOneWidget);
    expect(find.text('ARCHIVE EMPTY'), findsNothing);
  });

  testWidgets('does not move a document until delete is confirmed', (
    tester,
  ) async {
    await pumpHome(tester, [project('delete-me', 'Delete me')]);

    final actions = find.bySemanticsLabel('Project actions');
    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Move to Trash?'), findsOneWidget);
    expect(
      (await LocalStorageService().getProjects()).single.status,
      ProjectStatus.active,
    );

    await tester.tap(find.text('MOVE TO TRASH'));
    await tester.pumpAndSettle();

    expect(
      (await LocalStorageService().getProjects()).single.status,
      ProjectStatus.trashed,
    );
  });

  test('deleting a document closes its open tab', () async {
    final document = project('delete-tab', 'Delete tab');
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([document.toJson()]),
    });
    final storage = LocalStorageService();
    final tabs = OpenDocumentTabsNotifier(storage);
    await tabs.open(projectId: document.id, name: document.name);

    final container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        openDocumentTabsProvider.overrideWith((ref) => tabs),
      ],
    );
    addTearDown(container.dispose);
    await container.read(homeProjectsProvider.notifier).loadProjects();

    await container
        .read(homeProjectsProvider.notifier)
        .deleteProject(document.id);

    expect(tabs.state, isEmpty);
    expect((await storage.getProjects()).single.status, ProjectStatus.trashed);
  });

  testWidgets('cloud deletion requires confirmation and preserves local data', (
    tester,
  ) async {
    final metadata = LocalProjectMetadata(
      id: 'cloud-project',
      name: 'Cloud project',
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      cloudOwnerId: 'account-1',
    );
    final requests = <http.Request>[];
    var deletionStatusReads = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/projects')) {
          return http.Response(
            jsonEncode([]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path.endsWith(
          '/workspace_note_attachment_rehome_jobs',
        )) {
          deletionStatusReads++;
          return http.Response(
            jsonEncode(
              deletionStatusReads <= 2
                  ? []
                  : [
                      {
                        'id': 'rehome-job-1',
                        'requested_by': 'account-1',
                        'status': 'complete',
                        'attempt_count': 1,
                      },
                    ],
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path.endsWith(
          '/rpc/request_workspace_note_project_delete',
        )) {
          return http.Response(
            jsonEncode([
              {'status': 'pending', 'job_id': 'rehome-job-1'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        throw StateError('Unexpected cloud request: ${request.url}');
      }),
    );
    await authenticateTestClient(client);
    final sync = SupabaseSyncService(client);
    addTearDown(() {
      sync.dispose();
      client.dispose();
    });
    final user = User(
      id: 'account-1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-10-01T00:00:00Z',
      isAnonymous: false,
    );
    await pumpHome(
      tester,
      [metadata],
      providerOverrides: [
        supabaseClientProvider.overrideWithValue(client),
        supabaseSyncServiceProvider.overrideWithValue(sync),
        authUserProvider.overrideWith((ref) => Stream.value(user)),
      ],
    );

    final actions = find.bySemanticsLabel('Project actions');
    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    expect(find.text('Delete from cloud'), findsOneWidget);
    await tester.tap(find.text('Delete from cloud'));
    await tester.pumpAndSettle();

    expect(find.text('Delete cloud project?'), findsOneWidget);
    expect(
      requests.any(
        (request) => request.url.path.endsWith(
          '/rpc/request_workspace_note_project_delete',
        ),
      ),
      isFalse,
    );
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(requests.any((request) => request.method == 'DELETE'), isFalse);

    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from cloud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE FROM CLOUD'));
    await tester.pumpAndSettle();

    expect(find.text('Cloud deletion pending'), findsNWidgets(2));
    expect(
      requests.any(
        (request) => request.url.path.endsWith(
          '/rpc/request_workspace_note_project_delete',
        ),
      ),
      isTrue,
    );
    expect(requests.any((request) => request.method == 'DELETE'), isFalse);

    await tester.tap(find.text('CHECK STATUS'));
    await tester.pumpAndSettle();
    expect(find.text('Cloud deleted · local copy kept'), findsOneWidget);
    final local = (await LocalStorageService().getProjects()).single;
    expect(local.id, 'cloud-project');
    expect(local.cloudOwnerId, isNull);
    expect(local.cloudMetadataSyncPending, isFalse);
    expect(local.status, ProjectStatus.active);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries a failed cloud deletion and refreshes its status', (
    tester,
  ) async {
    String? retriedJobId;
    CloudProjectDeletionResult? changedStatus;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CloudProjectDeletionStatusDialog(
                  initialResult: const CloudProjectDeletionResult(
                    status: CloudProjectDeletionStatus.failed,
                    jobId: 'rehome-job-2',
                    attemptCount: 8,
                  ),
                  loadStatus: () async => const CloudProjectDeletionResult(
                    status: CloudProjectDeletionStatus.pending,
                    jobId: 'rehome-job-2',
                  ),
                  retry: (jobId) async => retriedJobId = jobId,
                  onStatusChanged: (result) => changedStatus = result,
                  onCompleted: () async {},
                ),
              ),
              child: const Text('Open status'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open status'));
    await tester.pumpAndSettle();
    expect(find.text('Cloud deletion failed'), findsOneWidget);

    await tester.tap(find.text('RETRY CLOUD DELETION'));
    await tester.pumpAndSettle();

    expect(retriedJobId, 'rehome-job-2');
    expect(changedStatus?.status, CloudProjectDeletionStatus.pending);
    expect(find.text('Cloud deletion pending'), findsOneWidget);
    expect(find.text('Cloud deletion failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requires confirmation before permanent deletion', (
    tester,
  ) async {
    await pumpHome(tester, [
      project('permanent', 'Old document', status: ProjectStatus.trashed),
    ]);

    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    final actions = find.bySemanticsLabel('Project actions');
    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.text('Delete permanently?'), findsOneWidget);
    expect(
      (await LocalStorageService().getProjects()).single.name,
      'Old document',
    );

    await tester.tap(find.text('DELETE PERMANENTLY'));
    await tester.pumpAndSettle();

    expect(await LocalStorageService().getProjects(), isEmpty);
  });

  testWidgets('clears an in-page search filter', (tester) async {
    await pumpHome(tester, [
      project('brief', 'Campaign brief'),
      project('board', 'Moodboard'),
    ]);

    await tester.enterText(
      find.byKey(const ValueKey('project-search-field')),
      'campaign',
    );
    await tester.pumpAndSettle();

    expect(find.text('Campaign brief'), findsOneWidget);
    expect(find.text('Moodboard'), findsNothing);
    expect(find.byKey(const ValueKey('clear-project-filters')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-project-filters')));
    await tester.pumpAndSettle();

    expect(find.text('Campaign brief'), findsOneWidget);
    expect(find.text('Moodboard'), findsOneWidget);
  });

  testWidgets('localizes project search and status controls in Indonesian', (
    tester,
  ) async {
    await pumpHome(tester, [
      project('brief', 'Campaign brief'),
    ], locale: const Locale('id'));

    expect(find.byKey(const ValueKey('project-search-field')), findsOneWidget);
    expect(find.text('Aktif'), findsOneWidget);
    expect(find.text('Arsip'), findsOneWidget);
    expect(find.text('Sampah'), findsOneWidget);
    expect(find.text('Pustaka proyek'), findsOneWidget);
    expect(find.text('Campaign brief'), findsOneWidget);
  });
  testWidgets('localizes home action accessibility labels in Indonesian', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHome(tester, [], locale: const Locale('id'));

    expect(find.byTooltip('Gabung ke ruang kolaborasi'), findsOneWidget);
    expect(find.byTooltip('Integrasi backend'), findsOneWidget);
    expect(find.byTooltip('Masuk untuk berkolaborasi'), findsOneWidget);
  });

  testWidgets('compact home actions remain visible in the localized menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHome(tester, [], locale: const Locale('id'));

    final moreActions = find.byTooltip('Aksi lainnya');
    expect(moreActions, findsOneWidget);
    await tester.tap(moreActions);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Gabung ke ruang kolaborasi'), findsOneWidget);
    expect(find.text('Integrasi backend'), findsOneWidget);
    expect(find.text('Masuk untuk berkolaborasi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders with the light Material theme without exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(const HomeScreen(), materialTheme: AppTheme.lightTheme),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the shared narrow-header breakpoint for the brand title', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);

    await pumpHome(tester, []);

    expect(find.byType(VarianBrandMark), findsOneWidget);
    expect(find.text('CREATIVE WORKSTATION'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home content uses shared page gutters and wide max width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(360, 640);
    await pumpHome(tester, []);
    final compactContext = tester.element(find.byType(HomeScreen));
    final compactPage = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.padding ==
              AppResponsive.pagePadding(
                compactContext,
              ).copyWith(bottom: AppSpacing.lg),
    );
    expect(compactPage, findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1600, 900);
    await pumpHome(tester, []);
    final wideContext = tester.element(find.byType(HomeScreen));
    final widePage = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.padding ==
              AppResponsive.pagePadding(
                wideContext,
              ).copyWith(bottom: AppSpacing.lg),
    );
    expect(widePage, findsOneWidget);

    final contentConstraint = find.byWidgetPredicate(
      (widget) =>
          widget is ConstrainedBox &&
          widget.constraints.maxWidth == AppBreakpoints.wide,
    );
    expect(contentConstraint, findsOneWidget);
    final contentRect = tester.getRect(contentConstraint);
    expect(contentRect.width, AppBreakpoints.wide);
    expect(contentRect.left, 80);
    expect(contentRect.right, 1520);
    expect(tester.takeException(), isNull);
  });
  testWidgets('home search and sort toolbar reflows at the medium breakpoint', (
    tester,
  ) async {
    Future<void> verifyLayout(Size viewport, {required bool compact}) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      await pumpHome(tester, []);

      final search = tester.getRect(
        find.byKey(const ValueKey('project-search-field')),
      );
      final sort = tester.getRect(
        find.byKey(const ValueKey('project-sort-select')),
      );
      if (compact) {
        expect(sort.top, greaterThan(search.bottom));
      } else {
        expect(sort.left, greaterThan(search.right));
        expect(sort.width, 168);
        expect(sort.center.dy, greaterThanOrEqualTo(search.top));
        expect(sort.center.dy, lessThanOrEqualTo(search.bottom));
      }
      expect(search.left, greaterThanOrEqualTo(0));
      expect(sort.right, lessThanOrEqualTo(viewport.width));
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.reset);
    await verifyLayout(const Size(839, 900), compact: true);
    await verifyLayout(const Size(840, 900), compact: false);
  });
  testWidgets('project cards preserve explicit compact and wide grid bounds', (
    tester,
  ) async {
    addTearDown(tester.view.reset);

    Future<void> verifyCard(Size viewport, double expectedHeight) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      final store = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      try {
        final fixture = project('grid-${viewport.width}', 'Grid fixture');
        await pumpHome(tester, [fixture], durableStore: store);
        final card = find.byKey(ValueKey(fixture.id));
        await tester.ensureVisible(card);
        final rect = tester.getRect(card);
        expect(rect.height, expectedHeight);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(viewport.width));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(viewport.height));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await store.close();
      }
    }

    await verifyCard(const Size(360, 900), 196);
    await verifyCard(const Size(1024, 900), 214);
  });
  testWidgets('project grid keeps the shared 16 px card gap', (tester) async {
    tester.view.physicalSize = const Size(690, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    try {
      final projects = [
        project('grid-gap-a', 'First grid card'),
        project('grid-gap-b', 'Second grid card'),
      ];
      await pumpHome(tester, projects, durableStore: store);

      final first = tester.getRect(find.byKey(const ValueKey('grid-gap-a')));
      final second = tester.getRect(find.byKey(const ValueKey('grid-gap-b')));
      expect(first.top, second.top);
      expect(second.left - first.right, AppSpacing.md);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await store.close();
    }
  });
}

class _FailedHomeProjectsNotifier extends HomeProjectsNotifier {
  _FailedHomeProjectsNotifier(super.ref, super.storage, super.tabs);

  @override
  Future<void> loadProjects() async {
    state = AsyncValue.error(
      StateError('local fixture failure'),
      StackTrace.current,
    );
  }
}
