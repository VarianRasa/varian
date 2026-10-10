import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/presentation/presentation_remote_dialogs.dart';

import '../../test_app.dart';

void main() {
  testWidgets('remote host dialog uses compact padding without a backend', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final syncService = SupabaseSyncService(null);
    addTearDown(syncService.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => PresenterRemoteHostDialog(
                  client: null,
                  syncService: syncService,
                ),
              ),
              child: const Text('Open host dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open host dialog'));
    await tester.pumpAndSettle();
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final cancel = tester.getRect(find.text('Cancel'));
    expect(cancel.left, greaterThanOrEqualTo(dialogRect.left));
    expect(cancel.right, lessThanOrEqualTo(dialogRect.right));
    expect(cancel.bottom, lessThanOrEqualTo(dialogRect.bottom));

    final shell = tester.widget<UiSurface>(find.byType(UiSurface).first);
    expect(
      shell.padding,
      AppResponsive.dialogPadding(tester.element(find.byType(UiSurface).first)),
    );
    expect(shell.padding, const EdgeInsets.all(AppSpacing.md));
    expect(find.text('Presenter Remote'), findsOneWidget);
    expect(find.text('Session ID'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'remote controller dialog uses compact padding and keeps backend actions disabled',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final syncService = SupabaseSyncService(null);
      addTearDown(syncService.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () => showUiDialog<void>(
                  context: context,
                  builder: (_) => PresenterRemoteControllerDialog(
                    projectId: 'local-project',
                    client: null,
                    syncService: syncService,
                  ),
                ),
                child: const Text('Open controller dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open controller dialog'));
      await tester.pumpAndSettle();
      final dialogRect = tester.getRect(find.byType(Dialog));
      expect(dialogRect.left, greaterThanOrEqualTo(0));
      expect(dialogRect.right, lessThanOrEqualTo(320));
      expect(dialogRect.top, greaterThanOrEqualTo(0));
      expect(dialogRect.bottom, lessThanOrEqualTo(480));
      await tester.ensureVisible(find.text('Close'));
      await tester.pumpAndSettle();
      final close = tester.getRect(find.text('Close'));
      expect(close.left, greaterThanOrEqualTo(dialogRect.left));
      expect(close.right, lessThanOrEqualTo(dialogRect.right));
      expect(close.bottom, lessThanOrEqualTo(dialogRect.bottom));
      final shellRect = tester.getRect(find.byType(UiSurface).first);
      expect(shellRect.height, lessThanOrEqualTo(456));
      expect(shellRect.left, greaterThanOrEqualTo(0));
      expect(shellRect.right, lessThanOrEqualTo(320));

      final shell = tester.widget<UiSurface>(find.byType(UiSurface).first);
      expect(shell.padding, const EdgeInsets.all(AppSpacing.md));
      expect(find.text('Remote Presenter Controller'), findsOneWidget);
      final create = tester.widget<UiButton>(
        find
            .ancestor(
              of: find.text('Create session'),
              matching: find.byType(UiButton),
            )
            .first,
      );
      expect(create.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
