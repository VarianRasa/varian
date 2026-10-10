import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/canvas/presentation/widgets/desktop_document_tabs.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';

import '../../test_app.dart';

void main() {
  testWidgets('titlebar create control uses compact by regular dimensions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var createRequests = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openDocumentTabsProvider.overrideWith(
            (ref) => OpenDocumentTabsNotifier(LocalStorageService()),
          ),
        ],
        child: testApp(
          SizedBox(
            width: 500,
            height: AppControlSize.regular,
            child: DesktopDocumentTabStrip(
              embedded: true,
              titleBarStyle: true,
              onCreateProject: (context) async => createRequests++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final createButton = find.byKey(const ValueKey('create-project-tab'));
    expect(tester.getSize(createButton), const Size(32, 36));

    await tester.tap(createButton);
    await tester.pump();
    expect(createRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create separator keeps its one-pixel width', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openDocumentTabsProvider.overrideWith(
            (ref) => OpenDocumentTabsNotifier(LocalStorageService()),
          ),
        ],
        child: testApp(
          SizedBox(
            width: 500,
            height: AppControlSize.regular,
            child: DesktopDocumentTabStrip(
              embedded: true,
              titleBarStyle: true,
              onCreateProject: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final separator = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.constraints ==
              const BoxConstraints.tightFor(width: AppBorder.thin, height: 22),
    );
    expect(separator, findsOneWidget);
    expect(tester.getSize(separator), const Size(AppBorder.thin, 22));
    expect(tester.takeException(), isNull);
  });
  testWidgets('titlebar document close control keeps its compact wrapper', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final tabs = OpenDocumentTabsNotifier(LocalStorageService());
    await tabs.open(projectId: 'local-titlebar-tab', name: 'Local tab');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [openDocumentTabsProvider.overrideWith((ref) => tabs)],
        child: testApp(
          SizedBox(
            width: 500,
            height: AppControlSize.regular,
            child: DesktopDocumentTabStrip(
              activeProjectId: 'local-titlebar-tab',
              embedded: true,
              titleBarStyle: true,
              onCloseDocument: (_, _, _, _) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(
        find.byKey(const ValueKey('close-document-tab-local-titlebar-tab')),
      ),
      const Size(AppControlSize.extraSmall, 30),
    );
    expect(tester.takeException(), isNull);
  });
}
