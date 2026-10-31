import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/canvas/presentation/widgets/desktop_document_tabs.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';

import '../../test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dropdown switches, closes, and creates documents', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final tabs = OpenDocumentTabsNotifier(LocalStorageService());
    await tabs.open(projectId: 'first', name: 'First document');
    await tabs.open(projectId: 'second', name: 'Second document');

    String? selectedProjectId;
    String? closedProjectId;
    OpenDocumentTab? replacement;
    var created = false;
    var createdNote = false;
    var openedCanvas = false;
    var openedNote = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [openDocumentTabsProvider.overrideWith((ref) => tabs)],
        child: testApp(
          DocumentBreadcrumbSwitcher(
            activeProjectId: 'first',
            onSelectDocument: (context, tab) async {
              selectedProjectId = tab.projectId;
            },
            onCreateProject: (context) async => created = true,
            onCreateCanvas: (context) async => created = true,
            onCreateNote: (context) async => createdNote = true,
            onOpenSavedCanvas: (context) async => openedCanvas = true,
            onOpenSavedNote: (context) async => openedNote = true,
            onCloseDocument: (context, tab, next, active) async {
              closedProjectId = tab.projectId;
              replacement = next;
              await tabs.close(tab.projectId);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('document-switcher-menu')));
    await tester.pumpAndSettle();
    expect(find.text('First document'), findsOneWidget);
    expect(find.text('Second document'), findsOneWidget);

    await tester.tap(find.text('Second document'));
    await tester.pumpAndSettle();
    expect(selectedProjectId, 'second');

    await tester.tap(find.byKey(const ValueKey('document-switcher-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close Second document'));
    await tester.pumpAndSettle();
    expect(closedProjectId, 'second');
    expect(replacement?.projectId, 'first');
    expect(tabs.state.map((tab) => tab.projectId), ['first']);

    await tester.tap(find.byKey(const ValueKey('document-switcher-menu')));
    await tester.pumpAndSettle();
    expect(find.text('New blank Canvas'), findsOneWidget);
    expect(find.text('New blank Notes'), findsOneWidget);
    expect(find.text('Open saved Canvas'), findsOneWidget);
    expect(find.text('Open saved Notes'), findsOneWidget);

    await tester.tap(find.text('New blank Canvas'));
    await tester.pumpAndSettle();
    expect(created, isTrue);

    await tester.tap(find.byKey(const ValueKey('document-switcher-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New blank Notes'));
    await tester.pumpAndSettle();
    expect(createdNote, isTrue);

    await tester.tap(find.byKey(const ValueKey('document-switcher-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open saved Canvas'));
    await tester.pumpAndSettle();
    expect(openedCanvas, isTrue);

    await tester.tap(find.byKey(const ValueKey('document-switcher-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open saved Notes'));
    await tester.pumpAndSettle();
    expect(openedNote, isTrue);
  });
}
