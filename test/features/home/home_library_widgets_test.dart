import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/home/presentation/widgets/backend_settings_dialog.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/home/presentation/widgets/collaboration_profile_dialog.dart';
import 'package:varian/features/home/presentation/widgets/home_library_widgets.dart';

import '../../test_app.dart';

void main() {
  final timestamp = DateTime.utc(2026, 10, 3);

  testWidgets(
    'status labels expose count semantics in compact and wide forms',
    (tester) async {
      await tester.pumpWidget(
        testApp(
          const Column(
            children: [
              ProjectStatusTabLabel(label: 'Active', count: 3, compact: true),
              ProjectStatusTabLabel(
                label: 'Archived',
                count: 2,
                compact: false,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label?.contains('3') == true,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bulk permanent-delete confirmation stays disabled initially', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var confirmed = false;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => BulkProjectActionDialog(
                  status: ProjectStatus.trashed,
                  count: 2,
                  permanent: true,
                  onCancel: () => Navigator.pop(context),
                  onConfirm: () => confirmed = true,
                ),
              ),
              child: const Text('Open bulk delete'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open bulk delete'));
    await tester.pumpAndSettle();

    expect(find.byType(BulkProjectActionDialog), findsOneWidget);
    final confirmation = tester.widget<UiTextField>(
      find.byKey(const ValueKey('bulk-delete-confirmation')),
    );
    expect(confirmation.controller?.text, isEmpty);
    expect(confirmed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single project deletion dialog renders without mutating data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var confirmed = false;
    final project = LocalProjectMetadata(
      id: 'local-delete-fixture',
      name: 'Local delete fixture',
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => DeleteProjectDialog(
                  project: project,
                  permanent: false,
                  onCancel: () => Navigator.pop(context),
                  onConfirm: () => confirmed = true,
                ),
              ),
              child: const Text('Open project delete'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open project delete'));
    await tester.pumpAndSettle();

    expect(find.text('“Local delete fixture”'), findsOneWidget);
    expect(find.byType(DeleteProjectDialog), findsOneWidget);
    expect(confirmed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace help popover opens without resuming onboarding', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: testApp(const WorkspaceHelpButton())),
    );
    await tester.tap(find.byKey(const ValueKey('workspace-help-button')));
    await tester.pumpAndSettle();

    expect(find.text('Quick start'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('resume-onboarding-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collaboration profile dialog uses local identity and responsive width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(child: testApp(const CollaborationProfileDialog())),
      );
      await tester.pumpAndSettle();

      expect(find.text('COLLABORATION PROFILE'), findsOneWidget);
      expect(find.text('Display name'), findsOneWidget);
      expect(tester.getSize(find.byType(Dialog)).width, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('backend settings uses isolated local configuration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendConfigProvider.overrideWith(
            (ref) => _OfflineBackendConfigNotifier(),
          ),
          supabaseClientProvider.overrideWithValue(null),
        ],
        child: testApp(const BackendSettingsDialog()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BACKEND & LIVE INTEGRATIONS'), findsOneWidget);
    expect(find.text('COLLABORATION USER IDENTITY'), findsOneWidget);
    expect(find.text('Save & Apply'), findsOneWidget);
    final labelSmallSize = Theme.of(
      tester.element(find.text('BACKEND & LIVE INTEGRATIONS')),
    ).textTheme.labelSmall!.fontSize;
    const labelSmallCopy = [
      'This checks endpoint connectivity and model names only; it does not verify image generation or editing support.',
      'OpenAI-compatible providers differ. A successful API connection does not confirm that the selected route and model can return edited images.',
      'OpenAI-compatible does not guarantee video support. The provider must implement POST /videos with input_reference, seconds, and size. Empty video key/base uses the general AI settings. Web API keys remain visible in the browser session.',
      'The worker must expose GET /health and the async /3d/jobs contract. TripoSR needs a reference image; TRELLIS or Hunyuan3D can handle text input when installed on the worker. Do not put model-provider keys in canvas metadata.',
    ];
    for (final copy in labelSmallCopy) {
      expect(
        tester.widget<Text>(find.text(copy)).style?.fontSize,
        labelSmallSize,
      );
    }
    expect(tester.getSize(find.byType(Dialog)).width, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });
}

class _OfflineBackendConfigNotifier extends BackendConfigNotifier {
  @override
  Future<void> loadConfig() async {
    state = const BackendConfig(currentUserName: 'Local Fixture');
  }
}
