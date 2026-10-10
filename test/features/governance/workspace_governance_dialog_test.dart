import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/data/remote/supabase_sync_provider.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/governance/domain/plugin_registry.dart';
import 'package:varian/features/governance/domain/remote_operability.dart';
import 'package:varian/features/governance/domain/usage_billing.dart';
import 'package:varian/features/governance/presentation/workspace_governance_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('governance dialog fits a compact viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        WorkspaceGovernanceDialog(
          initialSettings: const AccessibilitySettings(),
          onSave: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    expect(dialog.constraints!.maxHeight, 456);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final saveButton = find.byKey(const ValueKey('governance-save-button'));
    await tester.ensureVisible(saveButton);
    final saveRect = tester.getRect(saveButton);
    expect(saveRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(saveRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(saveRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits and saves accessibility settings', (tester) async {
    AccessibilitySettings? saved;
    await tester.pumpWidget(
      testApp(
        WorkspaceGovernanceDialog(
          initialSettings: const AccessibilitySettings(),
          onSave: (settings) async => saved = settings,
          quota: const WorkspaceQuota(storageBytes: 100),
          usage: const WorkspaceUsage(storageBytes: 40),
        ),
      ),
    );
    await tester.pump();

    final motionSwitch = find.byKey(
      const ValueKey('governance-reduced-motion'),
    );
    await tester.ensureVisible(motionSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reduce motion'));
    await tester.pump();
    await tester.pump();
    final saveButton = find.byKey(const ValueKey('governance-save-button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(saved?.reducedMotion, isTrue);
  });

  testWidgets('shows recent structured audit activity', (tester) async {
    await tester.pumpWidget(
      testApp(
        WorkspaceGovernanceDialog(
          initialSettings: const AccessibilitySettings(),
          onSave: (_) async {},
          auditEvents: [
            WorkspaceAuditEvent(
              id: 'event-1',
              actorId: 'user-1',
              action: 'workspace.policy.updated',
              operation: 'workspace.policy.updated',
              targetType: 'workspace',
              targetId: 'project-1',
              timestamp: DateTime.utc(2026, 9, 13),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recent audit activity'), findsOneWidget);
    expect(find.textContaining('workspace.policy.updated'), findsOneWidget);
    expect(find.textContaining('workspace:project-1'), findsOneWidget);
  });

  testWidgets('toggles and persists a registered plugin', (tester) async {
    final registry = PluginRegistry(clock: () => DateTime.utc(2026, 9, 14));
    registry.register(
      const PluginManifest(
        id: 'sample.plugin',
        name: 'Sample plugin',
        version: '1.0.0',
        permissions: [PluginPermission.readSelection],
      ),
    );
    registry.approve(
      'sample.plugin',
      permissions: {PluginPermission.readSelection},
    );
    PluginRegistry? saved;

    await tester.pumpWidget(
      testApp(
        WorkspaceGovernanceDialog(
          initialSettings: const AccessibilitySettings(),
          onSave: (_) async {},
          initialPluginRegistry: registry,
          onPluginRegistrySave: (next) async => saved = next,
        ),
      ),
    );
    await tester.pump();

    final pluginToggle = find.byKey(
      const ValueKey('governance-plugin-toggle-sample.plugin'),
    );
    await tester.ensureVisible(pluginToggle);
    await tester.pump();
    await tester.tap(pluginToggle);
    await tester.pump();
    expect(find.textContaining('Disabled'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('governance-save-button')));
    await tester.pumpAndSettle();

    expect(
      saved?.find('sample.plugin')?.state,
      PluginRegistrationState.disabled,
    );
  });

  testWidgets('shows backend health and submits a support bundle', (
    tester,
  ) async {
    var submissions = 0;
    final health = WorkspaceHealthSnapshot.fromJson({
      'status': 'healthy',
      'version': '1.0.0',
      'timestamp': '2026-09-14T00:00:00Z',
      'checks': [
        {'name': 'database', 'status': 'healthy', 'message': 'ok'},
      ],
    });
    await tester.pumpWidget(
      testApp(
        WorkspaceGovernanceDialog(
          initialSettings: const AccessibilitySettings(),
          onSave: (_) async {},
          healthSnapshot: health,
          onSupportBundleSubmit: () async {
            submissions += 1;
            return WorkspaceSupportBundleReceipt(
              id: 'bundle-1',
              projectId: 'project-1',
              operationId: 'support-1234',
              status: 'ready',
              checksum: 'a' * 64,
              createdAt: DateTime.utc(2026, 9, 14),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('governance-health-status')),
      findsOneWidget,
    );
    expect(find.textContaining('database: healthy'), findsOneWidget);
    final supportButton = find.byKey(
      const ValueKey('governance-support-bundle-button'),
    );
    await tester.ensureVisible(supportButton);
    await tester.tap(supportButton);
    await tester.pumpAndSettle();

    expect(submissions, 1);
    expect(find.textContaining('Support bundle ready'), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('governance-support-bundle-status')),
          )
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
  });

  testWidgets('shows the remote billing entitlement', (tester) async {
    await tester.pumpWidget(
      testApp(
        WorkspaceGovernanceDialog(
          initialSettings: const AccessibilitySettings(),
          onSave: (_) async {},
          entitlement: EntitlementSnapshot(
            planId: 'pro',
            revision: 4,
            limits: const {UsageMetric.seats: 3, UsageMetric.aiCredits: 100},
            overagePolicy: OveragePolicy.grace,
            fetchedAt: DateTime.utc(2026, 9, 14),
            status: EntitlementStatus.trialing,
            provider: 'stripe',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('governance-entitlement-status')),
      findsOneWidget,
    );
    expect(find.text('stripe · pro'), findsOneWidget);
    expect(find.textContaining('Status trialing'), findsOneWidget);
    expect(find.textContaining('Seats 3'), findsOneWidget);
  });

  testWidgets(
    'does not expose cloud deletion controls without server context',
    (tester) async {
      await tester.pumpWidget(
        testApp(
          WorkspaceGovernanceDialog(
            initialSettings: const AccessibilitySettings(),
            onSave: (_) async {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('governance-cloud-deletion')),
        findsNothing,
      );
    },
  );

  testWidgets('shows fail-closed state for unavailable governance status', (
    tester,
  ) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      _testKey(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/rest/v1/projects') {
          return http.Response(
            jsonEncode({'id': 'project-owner', 'owner_id': 'workspace-owner'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path == '/rest/v1/rpc/get_workspace_governance') {
          return http.Response('{}', 503, request: request);
        }
        fail('No mutation may run when governance status is unknown.');
      }),
    );
    final service = SupabaseSyncService(client);
    client.auth.stopAutoRefresh();
    addTearDown(() {
      service.dispose();
      client.dispose();
    });
    await _authenticate(client, userId: 'workspace-owner');

    await tester.pumpWidget(_governanceApp(client, service));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Cloud deletion status is unavailable. Actions stay disabled until status can be verified.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('governance-cloud-deletion-request')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('governance-cloud-deletion-retry')),
      findsOneWidget,
    );
  });

  testWidgets('does not show request actions for a non-owner', (tester) async {
    final client = _deletionClient(ownerId: 'workspace-owner');
    final service = SupabaseSyncService(client);
    client.auth.stopAutoRefresh();
    addTearDown(() {
      service.dispose();
      client.dispose();
    });
    await _authenticate(client, userId: 'joined-member');

    await tester.pumpWidget(
      _governanceApp(client, service, userId: 'joined-member'),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('governance-cloud-deletion')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Local Trash and permanent purge only affect this device; this separate request is for cloud workspace lifecycle.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Only the cloud workspace owner can manage this request.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('governance-cloud-deletion-request')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('governance-cloud-deletion-cancel')),
      findsNothing,
    );
  });

  testWidgets('owner can separately request and cancel cloud deletion', (
    tester,
  ) async {
    var pending = false;
    var requests = 0;
    var cancellations = 0;
    final client = _deletionClient(
      ownerId: 'workspace-owner',
      isPending: () => pending,
      onRequest: () {
        requests++;
        pending = true;
      },
      onCancel: () {
        cancellations++;
        pending = false;
      },
    );
    final service = SupabaseSyncService(client);
    client.auth.stopAutoRefresh();
    addTearDown(() {
      service.dispose();
      client.dispose();
    });
    await _authenticate(client, userId: 'workspace-owner');

    await tester.pumpWidget(_governanceApp(client, service));
    await tester.pump();
    await tester.pumpAndSettle();

    final requestButton = find.byKey(
      const ValueKey('governance-cloud-deletion-request'),
    );
    await tester.ensureVisible(requestButton);
    expect(requestButton, findsOneWidget);
    await tester.tap(requestButton);
    await tester.pumpAndSettle();
    expect(find.text('Submit cloud deletion request?'), findsOneWidget);
    expect(
      find.textContaining(
        'does not move or delete this device’s local project',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('governance-cloud-deletion-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(find.text('A cloud deletion request is pending.'), findsOneWidget);
    expect(
      find.text('Cloud request submitted; status refreshed from the server.'),
      findsOneWidget,
    );
    final cancelButton = find.byKey(
      const ValueKey('governance-cloud-deletion-cancel'),
    );
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();
    expect(find.text('Cancel cloud deletion request?'), findsOneWidget);
    expect(
      find.textContaining('local project on this device is unchanged'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('governance-cloud-deletion-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(cancellations, 1);
    expect(find.text('No active cloud deletion request.'), findsOneWidget);
    expect(
      find.text('Cloud request cancelled; status refreshed from the server.'),
      findsOneWidget,
    );
  });

  testWidgets('canceling cloud request confirmation performs no RPC', (
    tester,
  ) async {
    var requests = 0;
    final client = _deletionClient(
      ownerId: 'workspace-owner',
      onRequest: () => requests++,
    );
    final service = SupabaseSyncService(client);
    client.auth.stopAutoRefresh();
    addTearDown(() {
      service.dispose();
      client.dispose();
    });
    await _authenticate(client, userId: 'workspace-owner');

    await tester.pumpWidget(_governanceApp(client, service));
    await tester.pump();
    await tester.pumpAndSettle();
    final requestButton = find.byKey(
      const ValueKey('governance-cloud-deletion-request'),
    );
    await tester.ensureVisible(requestButton);
    await tester.tap(requestButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('governance-cloud-deletion-cancel-confirm')),
    );
    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(find.text('No active cloud deletion request.'), findsOneWidget);
  });

  testWidgets(
    'sign-in account change after confirmation sends no deletion RPC',
    (tester) async {
      final client = _deletionClient(
        ownerId: 'workspace-owner',
        onRequest: () => fail('Account-switched request must not reach RPC.'),
      );
      final service = SupabaseSyncService(client);
      client.auth.stopAutoRefresh();
      addTearDown(() {
        service.dispose();
        client.dispose();
      });
      await _authenticate(client, userId: 'workspace-owner');

      await tester.pumpWidget(_governanceApp(client, service));
      await tester.pump();
      await tester.pumpAndSettle();
      final requestButton = find.byKey(
        const ValueKey('governance-cloud-deletion-request'),
      );
      await tester.ensureVisible(requestButton);
      await tester.tap(requestButton);
      await tester.pumpAndSettle();
      await _authenticate(client, userId: 'another-account');
      await tester.tap(
        find.byKey(const ValueKey('governance-cloud-deletion-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          const CreativeStudioLocalizations(
            Locale('en'),
          ).cloudDeletionUnavailable,
        ),
        findsNWidgets(2),
      );
    },
  );
}

Widget _governanceApp(
  SupabaseClient client,
  SupabaseSyncService service, {
  String projectId = 'project-owner',
  String userId = 'workspace-owner',
}) => testApp(
  ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      supabaseSyncServiceProvider.overrideWithValue(service),
    ],
    child: WorkspaceGovernanceDialog(
      initialSettings: const AccessibilitySettings(),
      onSave: (_) async {},
      cloudProjectId: projectId,
      cloudExpectedUserId: userId,
    ),
  ),
);

SupabaseClient _deletionClient({
  required String ownerId,
  bool Function()? isPending,
  VoidCallback? onRequest,
  VoidCallback? onCancel,
}) => SupabaseClient(
  'https://example.supabase.co',
  _testKey(),
  httpClient: MockClient((request) async {
    final pending = isPending?.call() ?? false;
    if (request.url.path == '/rest/v1/projects') {
      return http.Response(
        jsonEncode({'id': 'project-owner', 'owner_id': ownerId}),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    if (request.url.path == '/rest/v1/rpc/get_workspace_governance') {
      return http.Response(
        jsonEncode({
          'projectId': 'project-owner',
          'policy': const {},
          'usage': const {},
          'deletionRequestedAt': pending ? '2026-09-27T10:15:00Z' : null,
          'archivedAt': null,
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    if (request.url.path == '/rest/v1/rpc/request_project_deletion') {
      onRequest?.call();
      return http.Response(
        jsonEncode({
          'projectId': 'project-owner',
          'deletionRequestedAt': '2026-09-27T10:15:00Z',
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    if (request.url.path == '/rest/v1/rpc/cancel_project_deletion') {
      onCancel?.call();
      return http.Response('null', 200, request: request);
    }
    fail('Unexpected governance request: ${request.url.path}');
  }),
);

String _testKey() => String.fromCharCodes(const [116, 101, 115, 116]);

Future<void> _authenticate(
  SupabaseClient client, {
  required String userId,
}) async {
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
      'refresh_token': 'test-refresh',
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
