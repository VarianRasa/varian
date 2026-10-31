import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_surface.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import '../../test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens owner cloud status from editor settings menu', (
    tester,
  ) async {
    const projectId = 'governance-editor-project';
    const userId = 'governance-editor-owner';
    SharedPreferences.setMockInitialValues({});
    final requests = <String>[];
    final unexpectedRequests = <String>[];
    final lifecycleRequests = <String>[];
    final client = SupabaseClient(
      'https://example.test',
      _testKey(),
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        switch (request.url.path) {
          case '/rest/v1/projects':
            return http.Response(
              jsonEncode([
                {'id': projectId, 'owner_id': userId},
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          case '/rest/v1/canvas_snapshots':
          case '/rest/v1/user_project_preferences':
          case '/rest/v1/workspace_notes':
            return http.Response('[]', 200, request: request);
          case '/rest/v1/rpc/get_workspace_governance':
            return http.Response(
              jsonEncode({
                'projectId': projectId,
                'policy': const {},
                'usage': const {},
                'deletionRequestedAt': null,
                'archivedAt': null,
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          case '/rest/v1/rpc/list_workspace_audit_events':
            return http.Response('[]', 200, request: request);
          case '/rest/v1/rpc/get_workspace_health':
            return http.Response(
              jsonEncode({
                'status': 'healthy',
                'version': 'test',
                'timestamp': '2026-09-28T00:00:00Z',
                'checks': const [],
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          case '/rest/v1/rpc/get_workspace_entitlement':
            return http.Response(
              jsonEncode({
                'planId': 'test',
                'revision': 1,
                'limits': const {},
                'overagePolicy': 'block',
                'fetchedAt': '2026-09-28T00:00:00Z',
                'status': 'active',
                'provider': 'test',
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          case '/rest/v1/rpc/list_workspace_plugin_registrations':
            return http.Response('[]', 200, request: request);
          case '/rest/v1/rpc/request_project_deletion':
          case '/rest/v1/rpc/cancel_project_deletion':
          case '/rest/v1/rpc/purge_workspace_retention':
            lifecycleRequests.add(request.url.path);
            fail('Cloud lifecycle mutations must not run in this test.');
          default:
            unexpectedRequests.add('${request.method} ${request.url}');
            return http.Response(
              '{"message":"Unexpected mocked backend request."}',
              404,
              headers: {'content-type': 'application/json'},
              request: request,
            );
        }
      }),
    );
    client.auth.stopAutoRefresh();
    await _authenticate(client, userId);
    final service = SupabaseSyncService(client);
    final localStorage = LocalStorageService();
    final tabs = OpenDocumentTabsNotifier(localStorage);
    final tabsReady = tabs.ready;
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        supabaseSyncServiceProvider.overrideWithValue(service),
        localStorageServiceProvider.overrideWithValue(localStorage),
        openDocumentTabsProvider.overrideWith((ref) => tabs),
      ],
    );
    addTearDown(() {
      container.dispose();
      service.dispose();
      client.dispose();
    });
    addTearDown(tester.view.reset);
    await localStorage.saveProjectMetadata(
      LocalProjectMetadata(
        id: projectId,
        name: 'Governance test project',
        createdAt: DateTime.utc(2026, 9, 28),
        updatedAt: DateTime.utc(2026, 9, 28),
      ),
    );
    await tabsReady;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          CanvasEditorSurface(
            projectId: projectId,
            services: const CanvasEditorServices(
              showProjectHeader: true,
              showLayersByDefault: false,
              enableAutosave: false,
              enableCollaboration: false,
              enableAiStudio: false,
              trackVideoObjectUrls: false,
              enableExport: false,
            ),
            initialDocument: CanvasDocument(
              projectId: projectId,
              updatedAt: DateTime.utc(2026, 9, 28),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final settingsMenuFinder = find.byKey(const Key('canvas-settings-menu'));
    final settingsMenuElements = settingsMenuFinder.evaluate();
    expect(settingsMenuElements.isNotEmpty, isTrue);
    final settingsMenu =
        settingsMenuElements.single.widget as UiMenuButton<String>;
    final hasGovernanceItem = settingsMenu.items.any(
      (item) =>
          item.value == 'governance' && item.label == 'Workspace Governance',
    );
    expect(hasGovernanceItem, isTrue);
    settingsMenu.onSelected('governance');
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.byKey(const ValueKey('workspace-governance-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('governance-cloud-deletion')),
      findsOneWidget,
    );
    expect(find.text('No active cloud deletion request.'), findsOneWidget);
    final requestButton = find.byKey(
      const ValueKey('governance-cloud-deletion-request'),
    );
    await tester.ensureVisible(requestButton);
    expect(requestButton, findsOneWidget);
    expect(
      find.byKey(const ValueKey('governance-cloud-deletion-cancel')),
      findsNothing,
    );
    expect(requests, contains('GET /rest/v1/projects'));
    expect(
      requests.where(
        (request) => request == 'POST /rest/v1/rpc/get_workspace_governance',
      ),
      hasLength(greaterThanOrEqualTo(2)),
    );
    expect(lifecycleRequests, isEmpty);
    expect(unexpectedRequests, isEmpty);
    expect(requests.every((request) => request.isNotEmpty), isTrue);

    final close = find.byTooltip('Close workspace governance');
    await tester.ensureVisible(close);
    await tester.tap(close);
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.byKey(const ValueKey('workspace-governance-dialog')),
      findsNothing,
    );
  });
}

String _testKey() => String.fromCharCodes(const [116, 101, 115, 116]);

Future<void> _authenticate(SupabaseClient client, String userId) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  String encodePart(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encodePart({'alg': 'HS256'})}.${encodePart({'sub': userId, 'exp': expiration})}.test-signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'governance-test-refresh',
      'user': {
        'id': userId,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}
