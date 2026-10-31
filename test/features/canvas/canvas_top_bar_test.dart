import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/desktop_window_title_bar.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/app/theme_mode_provider.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/features/canvas/presentation/canvas_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/desktop_document_tabs.dart';
import 'package:varian/features/canvas/presentation/widgets/inspector_panel.dart';
import 'package:varian/features/canvas/presentation/widgets/layers_panel.dart';
import 'package:varian/features/canvas/presentation/widgets/panel_visibility_toggle.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/collaboration/state/collaboration_session_provider.dart';
import 'package:varian/features/canvas/presentation/widgets/color_picker_primitives.dart';
import 'package:varian/features/canvas/presentation/widgets/toolbar.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import 'package:varian/features/canvas/state/viewport_provider.dart';
import '../../test_app.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpCanvas(
    WidgetTester tester, {
    bool readOnly = false,
    String projectName = 'Untitled Project',
    Future<void> Function(BuildContext context)? onCreateProject,
    Future<bool> Function(String newName)? onProjectNameChanged,
    double textScaleFactor = 1,
    Size size = const Size(1920, 1080),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          autosaveControllerProvider.overrideWith(
            (ref) => _NoopAutosaveController(ref),
          ),
          collaborationVerifiedRoleForTestingProvider.overrideWithValue(
            CollaborationRole.owner,
          ),
        ],
        child: testApp(
          MediaQuery(
            data: MediaQueryData.fromView(
              tester.view,
            ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
            child: CanvasScreen(
              projectId: 'top-bar-test',
              projectName: projectName,
              readOnly: readOnly,
              onProjectNameChanged: onProjectNameChanged,
              onCreateProject: onCreateProject,
              onOpenProjectLibrary: onCreateProject == null
                  ? null
                  : (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> openSettings(WidgetTester tester) async {
    final compactMenu = find.byKey(const ValueKey('ui-compact-actions-menu'));
    final settingsButton = find.byTooltip('Settings');
    if (compactMenu.evaluate().isNotEmpty &&
        settingsButton.evaluate().isEmpty) {
      await tester.tap(compactMenu);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(settingsButton.first);
    await tester.tap(settingsButton.first);
    await tester.pumpAndSettle();
  }

  test('keeps opened document tabs unique and updates their names', () async {
    final storage = LocalStorageService();
    final now = DateTime.now();
    for (final id in ['one', 'two']) {
      await storage.saveProjectMetadata(
        LocalProjectMetadata(
          id: id,
          name: id == 'one' ? 'First document' : 'Second document',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final tabs = OpenDocumentTabsNotifier(storage);
    addTearDown(tabs.dispose);

    await tabs.open(projectId: 'one', name: 'First document');
    await tabs.open(projectId: 'two', name: 'Second document');
    await tabs.open(projectId: 'one', name: 'Renamed document');

    expect(tabs.state, const [
      OpenDocumentTab(projectId: 'one', name: 'Renamed document'),
      OpenDocumentTab(projectId: 'two', name: 'Second document'),
    ]);
  });

  test('does not restore tabs for trashed projects', () async {
    final storage = LocalStorageService();
    final now = DateTime.now();
    await storage.saveProjectMetadata(
      LocalProjectMetadata(
        id: 'trashed',
        name: 'Deleted document',
        createdAt: now,
        updatedAt: now,
        status: ProjectStatus.trashed,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'ccs_open_document_tabs',
      jsonEncode([
        {'projectId': 'trashed', 'name': 'Deleted document'},
      ]),
    );

    final tabs = OpenDocumentTabsNotifier(storage);
    addTearDown(tabs.dispose);
    await tabs.ready;

    expect(tabs.state, isEmpty);
    expect(jsonDecode(prefs.getString('ccs_open_document_tabs')!), isEmpty);
  });

  test('closes a tab and restores the remaining tabs', () async {
    final storage = LocalStorageService();
    final now = DateTime.now();
    for (final id in ['one', 'two']) {
      await storage.saveProjectMetadata(
        LocalProjectMetadata(
          id: id,
          name: 'Document $id',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final tabs = OpenDocumentTabsNotifier(storage);
    addTearDown(tabs.dispose);
    await tabs.open(projectId: 'one', name: 'Document one');
    await tabs.open(projectId: 'two', name: 'Document two');
    await tabs.close('one');

    expect(tabs.state, const [
      OpenDocumentTab(projectId: 'two', name: 'Document two'),
    ]);

    final restored = OpenDocumentTabsNotifier(storage);
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state, const [
      OpenDocumentTab(projectId: 'two', name: 'Document two'),
    ]);
  });

  testWidgets('shows the breadcrumb and creates a document from its menu', (
    tester,
  ) async {
    var createRequested = false;
    await pumpCanvas(
      tester,
      projectName: 'Current document',
      onCreateProject: (_) async => createRequested = true,
    );

    expect(
      find.byKey(const ValueKey('document-switcher-menu')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('document-tab-top-bar-test')),
      findsNothing,
    );
    expect(find.text('Current document'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('document-switcher-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New blank Canvas'));
    await tester.pumpAndSettle();

    expect(createRequested, isTrue);
  });

  testWidgets('document title keeps a minimum touch target across widths', (
    tester,
  ) async {
    for (final width in [
      320.0,
      390.0,
      800.0,
      929.0,
      1024.0,
      1280.0,
      1439.0,
      1440.0,
    ]) {
      await pumpCanvas(
        tester,
        size: Size(width, 720),
        onProjectNameChanged: (_) async => true,
      );

      final titleTarget = find.byKey(
        const ValueKey('canvas-document-title-target'),
      );
      expect(titleTarget, findsOneWidget);
      final targetRect = tester.getRect(titleTarget);
      expect(
        targetRect.height,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
      expect(targetRect.left, greaterThanOrEqualTo(0));
      expect(targetRect.right, lessThanOrEqualTo(width));
      final layoutExceptions = <Object>[];
      Object? layoutException;
      do {
        layoutException = tester.takeException();
        if (layoutException != null) layoutExceptions.add(layoutException);
      } while (layoutException != null);
      expect(
        layoutExceptions,
        isEmpty,
        reason: 'Canvas header at width $width: $layoutExceptions',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('document title aligns with header controls', (tester) async {
    await pumpCanvas(
      tester,
      size: const Size(1280, 720),
      projectName: 'Untitled Project',
      onProjectNameChanged: (_) async => true,
    );

    final titleText = find.text('Untitled Project');
    final titleTarget = find.byKey(
      const ValueKey('canvas-document-title-target'),
    );
    final titleRect = tester.getRect(titleText);
    final targetRect = tester.getRect(titleTarget);
    final searchRect = tester.getRect(
      find.byKey(const ValueKey('canvas-search')),
    );
    expect(titleRect.center.dy, closeTo(searchRect.center.dy, 1));
    expect(targetRect.width, closeTo(titleRect.width, 1));
    expect(
      tester.getSize(titleTarget).height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
  });

  testWidgets('document title has no persistent frame decoration', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      projectName: 'Current document',
      onProjectNameChanged: (_) async => true,
    );

    final titleTarget = find.byKey(
      const ValueKey('canvas-document-title-target'),
    );
    expect(titleTarget, findsOneWidget);
    expect(
      find.descendant(of: titleTarget, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    expect(
      find.descendant(of: titleTarget, matching: find.byType(Container)),
      findsNothing,
    );
    expect(
      find.descendant(of: titleTarget, matching: find.byType(Card)),
      findsNothing,
    );
    expect(
      find.descendant(of: titleTarget, matching: find.byType(Material)),
      findsNothing,
    );
    expect(
      find.descendant(of: titleTarget, matching: find.text('Current document')),
      findsOneWidget,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(titleTarget));
    await mouse.moveTo(tester.getCenter(titleTarget));
    await tester.pump();
    expect(
      find.descendant(of: titleTarget, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    expect(
      find.descendant(of: titleTarget, matching: find.byType(Container)),
      findsNothing,
    );
    expect(
      find.descendant(of: titleTarget, matching: find.byType(Material)),
      findsNothing,
    );
    await mouse.removePointer();
  });

  testWidgets('long document title does not overflow at tablet width', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      size: const Size(929, 720),
      projectName:
          'A long project title that fills the available canvas header space',
      textScaleFactor: 1.25,
    );

    final layoutExceptions = <Object>[];
    Object? layoutException;
    do {
      layoutException = tester.takeException();
      if (layoutException != null) layoutExceptions.add(layoutException);
    } while (layoutException != null);

    expect(
      layoutExceptions,
      isEmpty,
      reason: 'Canvas title row: $layoutExceptions',
    );
  });

  testWidgets('editing document title fits the header at narrow widths', (
    tester,
  ) async {
    for (final width in [320.0, 390.0, 929.0, 1600.0, 1680.0, 1920.0]) {
      await pumpCanvas(
        tester,
        size: Size(width, 720),
        onProjectNameChanged: (_) async => true,
        onCreateProject: (_) async {},
      );
      await tester.tap(
        find.byKey(const ValueKey('canvas-document-title-target')),
      );
      await tester.pumpAndSettle();

      final layoutExceptions = <Object>[];
      Object? layoutException;
      do {
        layoutException = tester.takeException();
        if (layoutException != null) layoutExceptions.add(layoutException);
      } while (layoutException != null);

      expect(
        layoutExceptions,
        isEmpty,
        reason: 'Canvas title edit row at width $width: $layoutExceptions',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('renames the document title when the callback succeeds', (
    tester,
  ) async {
    String? savedTitle;
    await pumpCanvas(
      tester,
      projectName: 'Untitled Project',
      onProjectNameChanged: (name) async {
        savedTitle = name;
        return true;
      },
      size: const Size(1280, 720),
    );

    await tester.tap(
      find.byKey(const ValueKey('canvas-document-title-target')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('canvas-document-title-editor')),
      'Presentation draft',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(savedTitle, 'Presentation draft');
    expect(find.text('Presentation draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not rename a document when the callback rejects it', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      projectName: 'Untitled Project',
      onProjectNameChanged: (_) async => false,
      size: const Size(1280, 720),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CanvasScreen)),
    );
    await tester.tap(
      find.byKey(const ValueKey('canvas-document-title-target')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('canvas-document-title-editor')),
      'Not saved',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Untitled Project'), findsOneWidget);
    expect(find.text('Not saved'), findsNothing);
    expect(
      container.read(openDocumentTabsProvider).single.name,
      'Untitled Project',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('syncs a parent-provided document title update', (tester) async {
    await pumpCanvas(tester, projectName: 'First project');

    await pumpCanvas(tester, projectName: 'Second project');

    expect(find.text('Second project'), findsOneWidget);
    expect(find.text('First project'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps canvas quick actions visible outside the compact menu', (
    tester,
  ) async {
    for (final width in [320.0, 390.0, 420.0, 600.0, 620.0, 929.0]) {
      await pumpCanvas(tester, size: Size(width, 720));

      final appBar = find.byType(AppBar);
      final layersButton = find.byKey(
        const ValueKey('canvas-panel-toggle-layers'),
      );
      final inspectorButton = find.byKey(
        const ValueKey('canvas-panel-toggle-inspector'),
      );
      expect(
        find.byKey(const ValueKey('ui-compact-actions-menu')),
        findsOneWidget,
      );
      if (width >= 600) {
        expect(
          find.descendant(
            of: appBar,
            matching: find.byKey(const ValueKey('canvas-return-to-dashboard')),
          ),
          findsOneWidget,
          reason: 'Back to Dashboard should stay in the header at $width px.',
        );
      } else {
        expect(find.byTooltip('Back to Dashboard'), findsNothing);
      }
      expect(
        find.descendant(
          of: appBar,
          matching: find.byKey(const ValueKey('canvas-search')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: appBar,
          matching: find.byKey(const ValueKey('canvas-undo')),
        ),
        width >= 420 ? findsOneWidget : findsNothing,
      );
      expect(
        find.descendant(
          of: appBar,
          matching: find.byKey(const ValueKey('canvas-redo')),
        ),
        width >= 420 ? findsOneWidget : findsNothing,
      );
      for (final button in [layersButton, inspectorButton]) {
        expect(
          find.descendant(of: appBar, matching: button),
          width >= 600 ? findsOneWidget : findsNothing,
        );
      }
      final workspaceButton = find.byKey(
        const ValueKey('canvas-panel-toggle-workspace'),
      );
      expect(
        find.descendant(of: appBar, matching: workspaceButton),
        width >= 600 ? findsOneWidget : findsNothing,
      );
      expect(find.byKey(const ValueKey('canvas-toggle-layers')), findsNothing);
      expect(
        find.byKey(const ValueKey('canvas-toggle-inspector')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('canvas-toggle-ai-studio')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('ui-compact-actions-menu')));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Canvas menu'), findsOneWidget);
      expect(find.byTooltip('More canvas actions'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.byTooltip('Panels'), findsNothing);
      expect(
        find.byTooltip('Show Layers panel'),
        width >= 600 ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Show Layers panel'),
        width < 600 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byTooltip('Show Inspector panel'),
        width >= 600 ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Show Inspector panel'),
        width < 600 ? findsOneWidget : findsNothing,
      );
      expect(find.byTooltip('Show AI Studio panel'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byKey(const ValueKey('canvas-search')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tapAt(Offset(width / 2, 8));
      await tester.pumpAndSettle();
      expect(find.text('Canvas menu'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('document title has no adornment icons', (tester) async {
    await pumpCanvas(
      tester,
      size: const Size(390, 844),
      projectName: 'Untitled Project',
      onProjectNameChanged: (_) async => true,
    );

    expect(find.text('Untitled Project'), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Rename document title: Untitled Project',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps unavailable panel toggles out of the read-only header', (
    tester,
  ) async {
    await pumpCanvas(tester, size: const Size(929, 720), readOnly: true);

    expect(
      find.byKey(const ValueKey('canvas-panel-toggle-layers')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('canvas-panel-toggle-inspector')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('canvas-panel-toggle-workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('canvas-panel-toggle-ai-studio')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('canvas-panel-toggle-layers')));
    await tester.pumpAndSettle();
    expect(find.text('OBJECT TREE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps compact dropdown scrollable in a short viewport', (
    tester,
  ) async {
    await pumpCanvas(tester, size: const Size(929, 420));

    await tester.tap(find.byKey(const ValueKey('ui-compact-actions-menu')));
    await tester.pumpAndSettle();

    final settings = find.byKey(const Key('canvas-settings-menu'));
    await tester.ensureVisible(settings);
    final settingsRect = tester.getRect(settings);
    expect(settingsRect.top, greaterThanOrEqualTo(0));
    expect(settingsRect.bottom, lessThanOrEqualTo(420));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows compact actions in an anchored dismissible menu', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      size: const Size(929, 720),
      onCreateProject: (_) async {},
    );

    final menuButton = find.byKey(const ValueKey('ui-compact-actions-menu'));
    expect(menuButton, findsOneWidget);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Canvas menu'), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-save-workspace')), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-toggle-inspector')), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
    await tester.tapAt(const Offset(12, 300));
    await tester.pumpAndSettle();
    expect(find.text('Canvas menu'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact menu follows design tokens and motion preferences', (
    tester,
  ) async {
    await pumpCanvas(tester, size: const Size(929, 720));

    final menuButton = find.byKey(const ValueKey('ui-compact-actions-menu'));
    await tester.tap(menuButton);
    await tester.pump();

    final menuTitle = find.text('Canvas menu');
    final menuSubtitle = find.text('More tools and workspace controls');
    expect(menuTitle, findsOneWidget);
    expect(menuSubtitle, findsOneWidget);
    final titleStyle = tester.widget<Text>(menuTitle).style!;
    final subtitleStyle = tester.widget<Text>(menuSubtitle).style!;
    expect(titleStyle.fontWeight, FontWeight.w600);
    expect(titleStyle.color, AppTokens.dark.text);
    expect(subtitleStyle.color, AppTokens.dark.textMuted);

    final popup = tester.widget<PopupMenuButton<int>>(menuButton);
    expect(popup.popUpAnimationStyle?.curve, Curves.easeOutCubic);
    expect(popup.popUpAnimationStyle?.reverseCurve, Curves.easeInCubic);
    expect(popup.popUpAnimationStyle?.duration, AppMotion.standard);
    expect(popup.popUpAnimationStyle?.reverseDuration, AppMotion.short);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Panels'), findsNothing);
    expect(find.byTooltip('Show Inspector panel'), findsOneWidget);
    expect(find.byTooltip('Show AI Studio panel'), findsNothing);
    expect(find.byTooltip('Export Options'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    final settingsButton = find.byKey(const Key('canvas-settings-menu'));
    final menuRect = tester
        .getRect(menuTitle)
        .expandToInclude(tester.getRect(settingsButton));
    expect(menuRect.left, greaterThanOrEqualTo(0));
    expect(menuRect.right, lessThanOrEqualTo(929));
    expect(menuRect.top, greaterThanOrEqualTo(0));
    expect(menuRect.bottom, lessThanOrEqualTo(720));

    await tester.tapAt(const Offset(12, 300));
    await tester.pump();
    expect(find.text('Canvas menu'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Canvas menu'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpCanvas(tester, size: const Size(929, 720));
    final reducedMotionMenu = tester.widget<PopupMenuButton<int>>(
      find.byKey(const ValueKey('ui-compact-actions-menu')),
    );
    expect(reducedMotionMenu.popUpAnimationStyle?.duration, Duration.zero);
    expect(
      reducedMotionMenu.popUpAnimationStyle?.reverseDuration,
      Duration.zero,
    );
    await tester.tap(find.byKey(const ValueKey('ui-compact-actions-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Canvas menu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header title, badges, and actions fit at desktop breakpoints', (
    tester,
  ) async {
    for (final width in [
      840.0,
      929.0,
      1179.0,
      1180.0,
      1280.0,
      1439.0,
      1440.0,
      1600.0,
    ]) {
      await pumpCanvas(
        tester,
        size: Size(width, 720),
        projectName:
            'A long project title that competes with status badges and toolbar actions',
        textScaleFactor: 1.25,
        onCreateProject: (_) async {},
      );
      if (width == 1180) {
        expect(find.byTooltip('Workspace'), findsNothing);
        expect(
          find.byKey(const ValueKey('canvas-panel-toggle-workspace')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('ui-compact-actions-menu')),
          findsOneWidget,
        );
      }

      final layoutExceptions = <Object>[];
      Object? layoutException;
      do {
        layoutException = tester.takeException();
        if (layoutException != null) layoutExceptions.add(layoutException);
      } while (layoutException != null);

      expect(
        layoutExceptions,
        isEmpty,
        reason: 'Canvas header at width $width: $layoutExceptions',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('hides title status badges at tablet width', (tester) async {
    await pumpCanvas(tester, size: const Size(929, 720));

    expect(find.text('LOCAL ONLY'), findsNothing);
    expect(find.text('COLLAB OFF'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closes inactive and active tabs through the close action', (
    tester,
  ) async {
    final storage = LocalStorageService();
    final now = DateTime.now();
    for (final id in ['one', 'two']) {
      await storage.saveProjectMetadata(
        LocalProjectMetadata(
          id: id,
          name: 'Document $id',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    final tabs = OpenDocumentTabsNotifier(storage);
    await tabs.open(projectId: 'one', name: 'Document one');
    await tabs.open(projectId: 'two', name: 'Document two');

    OpenDocumentTab? closed;
    OpenDocumentTab? replacement;
    var closedActive = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [openDocumentTabsProvider.overrideWith((ref) => tabs)],
        child: testApp(
          DesktopDocumentTabs(
            activeProjectId: 'two',
            onCloseDocument: (context, tab, next, active) async {
              closed = tab;
              replacement = next;
              closedActive = active;
              await tabs.close(tab.projectId);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tabStrip = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('desktop-document-tab-strip')),
    );
    final stripBorder =
        (tabStrip.decoration as BoxDecoration).border! as Border;
    expect(stripBorder.bottom.width, AppBorder.thin);
    final firstTabKey = const ValueKey('document-tab-canvas::one');
    final secondTabKey = const ValueKey('document-tab-canvas::two');
    expect(find.byKey(firstTabKey), findsOneWidget);
    expect(find.byKey(secondTabKey), findsOneWidget);
    final inactiveTab = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byKey(firstTabKey),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (inactiveTab.decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(AppRadius.control),
    );

    await tester.tap(
      find.byKey(const ValueKey('close-document-tab-canvas::one')),
    );
    await tester.pumpAndSettle();
    expect(closed?.projectId, 'one');
    expect(replacement?.projectId, 'two');
    expect(closedActive, isFalse);
    expect(find.byKey(firstTabKey), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('close-document-tab-canvas::two')),
    );
    await tester.pumpAndSettle();
    expect(closed?.projectId, 'two');
    expect(replacement, isNull);
    expect(closedActive, isTrue);
    expect(find.byKey(secondTabKey), findsNothing);
  });

  testWidgets('keeps the Windows title bar clear of document tabs', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final storage = LocalStorageService();
      final now = DateTime.now();
      await storage.saveProjectMetadata(
        LocalProjectMetadata(
          id: 'windows-title-bar-doc',
          name: 'Windows title bar document',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final tabs = OpenDocumentTabsNotifier(storage);
      await tabs.open(
        projectId: 'windows-title-bar-doc',
        name: 'Windows title bar document',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [openDocumentTabsProvider.overrideWith((ref) => tabs)],
          child: testApp(const DesktopWindowTitleBar(child: SizedBox.expand())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('varian'), findsOneWidget);
      expect(find.text('DOCUMENTS'), findsNothing);
      expect(
        find.byKey(const ValueKey('desktop-window-resize-area')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-window-brand-drag-area')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-window-empty-drag-area')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('document-tab-windows-title-bar-doc')),
        findsNothing,
      );
      expect(find.byTooltip('Create new project'), findsNothing);
      expect(find.byTooltip('Minimize window'), findsOneWidget);
      expect(find.byTooltip('Maximize window'), findsOneWidget);
      expect(find.byTooltip('Close window'), findsOneWidget);

      await tester.tap(find.byTooltip('Minimize window'));
      await tester.pump();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('keeps opened documents out of the Windows title bar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final storage = LocalStorageService();
      final now = DateTime.now();
      await storage.saveProjectMetadata(
        LocalProjectMetadata(
          id: 'tab-order-doc',
          name: 'Tab order document',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final tabs = OpenDocumentTabsNotifier(storage);
      await tabs.open(projectId: 'tab-order-doc', name: 'Tab order document');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [openDocumentTabsProvider.overrideWith((ref) => tabs)],
          child: testApp(const DesktopWindowTitleBar(child: SizedBox.expand())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('document-tab-tab-order-doc')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('create-project-tab')), findsNothing);
      expect(
        find.byKey(const ValueKey('desktop-window-empty-drag-area')),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('uses native dragging only from non-interactive title areas', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('window_manager');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'isMaximized' || call.method == 'isFullScreen') {
        return false;
      }
      return null;
    });

    try {
      await tester.pumpWidget(
        testApp(const DesktopWindowTitleBar(child: SizedBox.expand())),
      );
      await tester.pumpAndSettle();

      Future<void> dragFrom(Key key) async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(key)),
        );
        await gesture.moveBy(const Offset(24, 12));
        await tester.pump();
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 50));
      }

      await dragFrom(const ValueKey('desktop-window-brand-drag-area'));
      await dragFrom(const ValueKey('desktop-window-empty-drag-area'));

      expect(calls.where((method) => method == 'startDragging'), hasLength(2));
      expect(find.byTooltip('Create new project'), findsNothing);
      expect(find.text('DOCUMENTS'), findsNothing);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('uses light theme colors for the Windows title bar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final tabs = OpenDocumentTabsNotifier(LocalStorageService());
      await tabs.open(
        projectId: 'light-title-bar-doc',
        name: 'Light title bar document',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [openDocumentTabsProvider.overrideWith((ref) => tabs)],
          child: testApp(
            const DesktopWindowTitleBar(child: SizedBox.expand()),
            data: AppTheme.lightTheme,
            materialTheme: AppTheme.lightTheme,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleBar = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('desktop-window-title-bar')),
      );
      final titleBarDecoration = titleBar.decoration as BoxDecoration;
      expect(titleBarDecoration.color, AppTokens.light.panel);
      expect(
        (titleBarDecoration.border! as Border).bottom.color,
        AppTokens.light.panelBorder,
      );

      expect(
        find.byKey(const ValueKey('document-tab-light-title-bar-doc')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('desktop-window-empty-drag-area')),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('keeps desktop Settings in the header without a drawer', (
    tester,
  ) async {
    await pumpCanvas(tester, size: const Size(1400, 900));

    final appBar = find.byType(AppBar);
    final settings = find.byKey(const Key('canvas-settings-menu'));
    expect(
      find.byKey(const ValueKey('ui-compact-actions-menu')),
      findsOneWidget,
    );
    expect(find.descendant(of: appBar, matching: settings), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.text('Import Diagram / JSON'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the dashboard action and groups secondary actions', (
    tester,
  ) async {
    await pumpCanvas(tester);

    expect(find.byTooltip('Back to Dashboard'), findsOneWidget);
    expect(find.byTooltip('Workspace'), findsNothing);
    expect(
      find.byKey(const ValueKey('canvas-panel-toggle-workspace')),
      findsOneWidget,
    );
    expect(find.byTooltip('Search (Ctrl+F)'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('More canvas actions'), findsOneWidget);
    expect(find.byTooltip('Collaboration Room'), findsNothing);
    expect(find.byTooltip('Export Options'), findsNothing);
    for (final tooltip in [
      'Import Diagram / JSON',
      'Quick Capture (Ctrl/Cmd+K)',
      'Board History',
      'Insert Flowchart Template',
      'Play Presentation Mode',
      'Backend & Live Integrations',
    ]) {
      expect(find.byTooltip(tooltip), findsNothing);
    }

    await tester.tap(find.byTooltip('More canvas actions'));
    await tester.pumpAndSettle();
    expect(find.text('Collaboration Room'), findsOneWidget);
    expect(find.byTooltip('Export Options'), findsOneWidget);
    await tester.tapAt(const Offset(12, 300));
    await tester.pumpAndSettle();

    await openSettings(tester);

    for (final label in [
      'Import Diagram / JSON',
      'Board History',
      'Quick Capture (Ctrl/Cmd+K)',
      'Insert Flowchart Template',
      'Play Presentation Mode',
      'Theme: System',
      'Backend & Live Integrations',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Enable'), findsNWidgets(4));
    expect(find.text('Disable'), findsNWidgets(4));
  });

  testWidgets('keeps desktop zoom controls visible and resets to 100%', (
    tester,
  ) async {
    await pumpCanvas(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CanvasScreen)),
    );
    container.read(viewportProvider.notifier).setZoom(2);
    await tester.pump();

    expect(find.byKey(const ValueKey('canvas-zoom-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-zoom-level')), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-zoom-in')), findsOneWidget);
    expect(find.text('200%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('canvas-zoom-in')));
    await tester.pump();
    expect(container.read(viewportProvider).zoom, closeTo(2.2, 0.001));

    final zoomLevel = find.byKey(const ValueKey('canvas-zoom-level'));
    final zoomLevelCenter = tester.getCenter(zoomLevel);
    final firstTap = await tester.startGesture(zoomLevelCenter);
    await firstTap.up();
    await tester.pump(const Duration(milliseconds: 50));
    final secondTap = await tester.startGesture(zoomLevelCenter);
    await secondTap.up();
    await tester.pumpAndSettle();
    expect(container.read(viewportProvider).zoom, closeTo(1, 0.001));
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps zoom actions available in the compact zoom menu', (
    tester,
  ) async {
    await pumpCanvas(tester, size: const Size(620, 720));

    final zoomMenu = find.byKey(const ValueKey('canvas-zoom-menu'));
    expect(zoomMenu, findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-zoom-in')), findsNothing);
    await tester.tap(zoomMenu);
    await tester.pumpAndSettle();

    expect(find.text('Zoom out'), findsOneWidget);
    expect(find.text('Reset zoom to 100%'), findsOneWidget);
    expect(find.text('Zoom in'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CanvasScreen)),
    );
    await tester.tap(find.text('Zoom in'));
    await tester.pumpAndSettle();
    expect(container.read(viewportProvider).zoom, closeTo(1.1, 0.001));

    await tester.tap(find.byKey(const ValueKey('canvas-zoom-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset zoom to 100%'));
    await tester.pumpAndSettle();
    expect(container.read(viewportProvider).zoom, closeTo(1, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('board history reads persisted auto checkpoints after restart', (
    tester,
  ) async {
    final storage = LocalStorageService();
    final now = DateTime.utc(2026, 9, 13, 12);
    await storage.saveProjectMetadata(
      LocalProjectMetadata(
        id: 'top-bar-test',
        name: 'History project',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await storage.saveAutoCheckpoint(
      'top-bar-test',
      CanvasDocument(projectId: 'top-bar-test', updatedAt: now),
    );

    await pumpCanvas(tester, projectName: 'History project');
    await openSettings(tester);
    await tester.tap(find.text('Board History'));
    await tester.pumpAndSettle();

    expect(find.text('BOARD HISTORY'), findsOneWidget);
    expect(find.text('Autosave'), findsOneWidget);
    expect(find.text('Restore as branch'), findsNothing);
    await tester.tap(find.byTooltip('Compare Autosave'));
    await tester.pumpAndSettle();
    expect(find.text('VERSION DIFF'), findsOneWidget);
    expect(find.text('Autosave checkpoint'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board history dialog fits a short viewport', (tester) async {
    await pumpCanvas(tester, size: const Size(1280, 420));
    await openSettings(tester);
    await tester.tap(find.text('Board History'));
    await tester.pumpAndSettle();

    final historyContent = find.byKey(const ValueKey('board-history-content'));
    expect(historyContent, findsOneWidget);
    expect(tester.getSize(historyContent).height, lessThanOrEqualTo(388));
    expect(
      find.byKey(const ValueKey('document-switcher-button')),
      findsNothing,
    );
    final dialogException = tester.takeException();
    expect(dialogException, isNull);
  });

  testWidgets('shows a compact AI composer at the bottom center of canvas', (
    tester,
  ) async {
    await pumpCanvas(tester, size: const Size(620, 720));

    final composer = find.byKey(const ValueKey('ai-prompt-composer'));
    expect(composer, findsOneWidget);
    expect(find.byKey(const ValueKey('ai-prompt-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-generation-target')), findsOneWidget);
    final providerSettings = find.byKey(
      const ValueKey('ai-composer-provider-settings'),
    );
    final optionsButton = find.byKey(const ValueKey('ai-composer-options'));
    final sendButton = find.byKey(const ValueKey('ai-composer-send'));
    expect(providerSettings, findsOneWidget);
    expect(optionsButton, findsOneWidget);
    expect(sendButton, findsOneWidget);
    expect(find.text('SETUP'), findsOneWidget);

    final composerRect = tester.getRect(composer);
    final composerCenterY = composerRect.center.dy;
    for (final control in [
      find.byKey(const ValueKey('ai-generation-target')),
      sendButton,
      find.text('SETUP'),
      providerSettings,
      optionsButton,
    ]) {
      expect(
        tester.getRect(control).center.dy,
        closeTo(composerCenterY, 2),
        reason: 'Compact AI controls should share one vertical centerline.',
      );
    }

    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('diagram-shape-drop-target')),
    );
    expect(composerRect.width, lessThanOrEqualTo(560));
    expect(composerRect.height, lessThanOrEqualTo(120));
    expect(composerRect.center.dx, closeTo(canvasRect.center.dx, 1));
    expect(composerRect.bottom, lessThanOrEqualTo(canvasRect.bottom));
    expect(
      find.byKey(const ValueKey('canvas-panel-toggle-ai-studio')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('ai-panel-shell')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai-composer-options')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ai-composer-governance-settings')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI prompt grows to four lines then scrolls', (tester) async {
    await pumpCanvas(tester, size: const Size(620, 720));

    final prompt = find.byKey(const ValueKey('ai-prompt-field'));
    final singleLineHeight = tester.getSize(prompt).height;
    final promptField = tester.widget<UiTextField>(prompt);
    expect(promptField.maxLines, 4);
    expect(promptField.textInputAction, TextInputAction.newline);

    await tester.enterText(prompt, 'one\ntwo\nthree');
    await tester.pumpAndSettle();
    final threeLineHeight = tester.getSize(prompt).height;
    expect(threeLineHeight, greaterThan(singleLineHeight));

    await tester.enterText(prompt, 'one\ntwo\nthree\nfour');
    await tester.pumpAndSettle();
    final fourLineHeight = tester.getSize(prompt).height;
    expect(fourLineHeight, greaterThan(threeLineHeight));

    await tester.enterText(prompt, 'one\ntwo\nthree\nfour\nfive\nsix');
    await tester.pumpAndSettle();
    expect(tester.getSize(prompt).height, closeTo(fourLineHeight, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the canvas usable at mobile width', (tester) async {
    await pumpCanvas(tester, size: const Size(390, 844));

    final canvas = tester.getRect(
      find.byKey(const ValueKey('diagram-shape-drop-target')),
    );
    expect(canvas.width, greaterThan(300));
    final composer = tester.getRect(
      find.byKey(const ValueKey('ai-prompt-composer')),
    );
    expect(composer.left, greaterThanOrEqualTo(0));
    expect(composer.right, lessThanOrEqualTo(390));
    for (final control in [
      find.byKey(const ValueKey('ai-generation-target')),
      find.byKey(const ValueKey('ai-composer-send')),
      find.byKey(const ValueKey('ai-composer-provider-settings')),
      find.byKey(const ValueKey('ai-composer-options')),
    ]) {
      final controlRect = tester.getRect(control);
      expect(controlRect.left, greaterThanOrEqualTo(0));
      expect(controlRect.right, lessThanOrEqualTo(390));
    }
    final compactActions = find.byKey(
      const ValueKey('ui-compact-actions-menu'),
    );
    expect(compactActions, findsOneWidget);
    await tester.tap(compactActions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Inspector panel'));
    await tester.pumpAndSettle();
    expect(find.text('NO SELECTION'), findsOneWidget);
    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    expect(find.text('NO SELECTION'), findsNothing);
    await tester.tap(compactActions);
    await tester.pumpAndSettle();
    expect(find.text('Show Inspector panel'), findsOneWidget);
    expect(find.byTooltip('Expand minimap'), findsOneWidget);
    expect(find.text('NO SELECTION'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel controls fit in a narrow Settings menu', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: UiMenuButton<String>(
                tooltip: 'Settings',
                icon: Icons.settings_outlined,
                items: [
                  UiMenuAction(
                    value: 'inspector',
                    icon: Icons.tune_outlined,
                    label: 'Inspector',
                    suffix: PanelVisibilityToggle(
                      id: 'inspector',
                      label: 'Inspector',
                      enabled: true,
                      onChanged: (_) {},
                    ),
                    rowInteractive: false,
                  ),
                ],
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('panel-enable-inspector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('panel-disable-inspector')),
      findsOneWidget,
    );
  });

  testWidgets('pins panel controls to their header edges', (tester) async {
    await pumpCanvas(tester);

    final appBar = find.byType(AppBar);
    final appBarBottom = tester.getRect(appBar).bottom;
    final layersButton = find.byKey(
      const ValueKey('canvas-panel-toggle-layers'),
    );
    final inspectorButton = find.byKey(
      const ValueKey('canvas-panel-toggle-inspector'),
    );

    expect(find.byKey(const ValueKey('canvas-panels-menu')), findsNothing);
    for (final button in [layersButton, inspectorButton]) {
      expect(find.descendant(of: appBar, matching: button), findsOneWidget);
      expect(
        find.descendant(
          of: button,
          matching: find.byType(SidebarPanelToggleIcon),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('canvas-panel-toggle-ai-studio')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('ai-prompt-composer')), findsOneWidget);
    expect(
      tester.getRect(layersButton).center.dx,
      lessThan(tester.getRect(appBar).center.dx),
    );
    expect(
      tester.getRect(inspectorButton).center.dx,
      greaterThan(tester.getRect(appBar).center.dx),
    );
    await tester.tap(layersButton);
    await tester.pumpAndSettle();
    expect(find.text('OBJECT TREE'), findsOneWidget);
    expect(
      tester.getRect(find.byType(LayersPanel)).top,
      closeTo(appBarBottom, 1),
    );

    await tester.tap(inspectorButton);
    await tester.pumpAndSettle();
    expect(find.text('NO SELECTION'), findsOneWidget);
    expect(
      tester.getRect(find.byType(InspectorPanel)).top,
      closeTo(appBarBottom, 1),
    );

    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('diagram-shape-drop-target')),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('ai-prompt-composer')))
          .center
          .dx,
      closeTo(canvasRect.center.dx, 1),
    );
  });

  testWidgets(
    'labels nested controls in the compact action menu and keeps them usable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? selectedAction;

      await tester.pumpWidget(
        testApp(
          UiPageScaffold(
            title: const Text('Canvas'),
            useCompactActionsMenu: true,
            compactActionsMenuAlways: true,
            compactActionKeys: {const ValueKey('inline-action')},
            actions: [
              UiIconButton(
                key: ValueKey('inline-action'),
                icon: Icons.star_outline,
                tooltip: 'Favorite',
                onPressed: () {},
              ),
              UiMenuButton<String>(
                tooltip: 'Workspace tools',
                icon: Icons.more_horiz,
                items: const [
                  UiMenuAction(
                    value: 'share',
                    icon: Icons.share_outlined,
                    label: 'Share workspace',
                  ),
                ],
                onSelected: (value) => selectedAction = value,
              ),
            ],
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ui-compact-actions-menu')));
      await tester.pumpAndSettle();

      final toolsEntry = find.text('Workspace tools');
      expect(toolsEntry, findsOneWidget);
      await tester.tap(toolsEntry);
      await tester.pumpAndSettle();
      expect(find.text('Share workspace'), findsOneWidget);
      await tester.tap(find.text('Share workspace'));
      await tester.pumpAndSettle();

      expect(selectedAction, 'share');
    },
  );

  testWidgets('settings explicitly disables and re-enables a panel button', (
    tester,
  ) async {
    await pumpCanvas(tester);

    await openSettings(tester);

    final enableInspector = find.byKey(
      const ValueKey('panel-enable-inspector'),
    );
    final disableInspector = find.byKey(
      const ValueKey('panel-disable-inspector'),
    );
    expect(enableInspector, findsOneWidget);
    expect(disableInspector, findsOneWidget);
    expect(find.bySemanticsLabel('Enable Inspector button'), findsOneWidget);
    expect(find.bySemanticsLabel('Disable Inspector button'), findsOneWidget);
    for (final action in [enableInspector, disableInspector]) {
      final actionSize = tester.getSize(action);
      expect(
        actionSize.width,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
      expect(
        actionSize.height,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
    }
    expect(
      tester.widget<UiButton>(enableInspector).variant,
      UiButtonVariant.primary,
    );
    expect(
      tester.widget<UiButton>(disableInspector).variant,
      UiButtonVariant.outline,
    );

    await tester.tap(disableInspector);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show Inspector panel'), findsNothing);
    expect(find.text('NO SELECTION'), findsNothing);
    expect(find.text('Inspector'), findsOneWidget);
    expect(
      tester.widget<UiButton>(disableInspector).variant,
      UiButtonVariant.primary,
    );
    expect(
      tester.widget<UiButton>(enableInspector).variant,
      UiButtonVariant.outline,
    );

    await tester.tap(enableInspector);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show Inspector panel'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Inspector panel'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('canvas-panel-toggle-inspector')),
    );
    await tester.pumpAndSettle();
    expect(find.text('NO SELECTION'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('canvas-panel-toggle-inspector')),
    );
    await tester.pumpAndSettle();
    expect(find.text('NO SELECTION'), findsNothing);
    await tester.tap(find.byKey(const Key('canvas-settings-menu')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<UiButton>(enableInspector).variant,
      UiButtonVariant.primary,
    );
    expect(
      tester.widget<UiButton>(disableInspector).variant,
      UiButtonVariant.outline,
    );
  });

  testWidgets('hides unavailable panel settings in read-only mode', (
    tester,
  ) async {
    await pumpCanvas(tester, readOnly: true);
    await openSettings(tester);

    expect(find.text('Board History'), findsNothing);
    expect(find.text('Search canvas'), findsNothing);
    expect(find.text('Import Diagram / JSON'), findsNothing);
    expect(find.text('Insert Flowchart Template'), findsOneWidget);
    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('AI Studio'), findsNothing);
    expect(find.text('Inspector'), findsNothing);
    expect(find.byKey(const ValueKey('panel-enable-layers')), findsOneWidget);
    expect(find.byKey(const ValueKey('panel-disable-layers')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('panel-disable-layers')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Layers panel'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('panel-enable-layers')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canvas-panel-toggle-layers')));
    await tester.pumpAndSettle();
    expect(find.text('OBJECT TREE'), findsOneWidget);
  });

  testWidgets('overlays the transparent header above the canvas and panels', (
    tester,
  ) async {
    await pumpCanvas(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CanvasScreen)),
    );
    container.read(documentNodesProvider.notifier).setNodes([
      CanvasNode(
        id: 'overflowing-canvas-node',
        type: NodeType.rectangle,
        x: -80,
        y: -40,
        width: 200,
        height: 140,
        payload: ShapePayload(),
      ),
    ]);

    await tester.tap(find.byKey(const ValueKey('canvas-panel-toggle-layers')));
    await tester.pumpAndSettle();

    final viewportClip = tester.getRect(
      find.byKey(const ValueKey('canvas-render-stack')),
    );
    final appBarRect = tester.getRect(find.byType(AppBar));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final layers = tester.getRect(find.byType(LayersPanel));
    final node = tester.getRect(
      find.byKey(const ValueKey('canvas-node-layer-overflowing-canvas-node')),
    );

    expect(scaffold.extendBodyBehindAppBar, isTrue);
    expect(appBar.backgroundColor, Colors.transparent);
    expect(viewportClip.left, closeTo(layers.right, 0.001));
    expect(viewportClip.right, closeTo(1920, 0.001));
    expect(viewportClip.top, lessThan(appBarRect.bottom));
    expect(node.left, lessThan(viewportClip.left));
    expect(node.top, lessThan(viewportClip.top));
    expect(
      find.ancestor(
        of: find.byKey(
          const ValueKey('canvas-node-layer-overflowing-canvas-node'),
        ),
        matching: find.byKey(const ValueKey('canvas-render-stack')),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Stack>(find.byKey(const ValueKey('canvas-render-stack')))
          .clipBehavior,
      Clip.hardEdge,
    );
  });

  testWidgets('theme menu action advances the selected theme mode', (
    tester,
  ) async {
    await pumpCanvas(tester);
    await openSettings(tester);

    await tester.ensureVisible(find.text('Theme: System'));
    await tester.tap(find.text('Theme: System'));
    await tester.pumpAndSettle();

    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(CanvasScreen)),
      ).read(themeModeProvider),
      ThemeMode.light,
    );
  });

  testWidgets('toolbar active icon keeps contrast in both themes', (
    tester,
  ) async {
    Future<void> expectActiveIcon({
      required ThemeData data,
      required ThemeData materialTheme,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            const CanvasToolbar(),
            data: data,
            materialTheme: materialTheme,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.near_me_outlined));
      final tokens = data.extension<AppTokens>()!;
      expect(icon.color, tokens.accentForeground);
      final aiIcon = tester.widget<Icon>(
        find.byIcon(Icons.auto_awesome_outlined),
      );
      expect(aiIcon.color, tokens.textMuted);
    }

    await expectActiveIcon(
      data: AppTheme.lightTheme,
      materialTheme: AppTheme.lightTheme,
    );
    await expectActiveIcon(
      data: AppTheme.darkTheme,
      materialTheme: AppTheme.darkTheme,
    );
  });

  testWidgets('charts flyout stays neutral until a chart is selected', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const CanvasToolbar()),
      ),
    );
    await tester.pumpAndSettle();

    final chartsCategory = find.byTooltip('Charts (Click to open)');
    expect(container.read(activeToolProvider), CanvasTool.select);
    expect(chartsCategory, findsOneWidget);
    expect(
      find.descendant(
        of: chartsCategory,
        matching: find.byIcon(Icons.arrow_right),
      ),
      findsOneWidget,
    );

    await tester.tap(chartsCategory);
    await tester.pumpAndSettle();
    expect(container.read(activeToolProvider), CanvasTool.select);
    expect(find.text('CHARTS'), findsOneWidget);
    expect(find.text('Chart types'), findsOneWidget);

    await tester.tap(find.text('Line'));
    await tester.pumpAndSettle();
    expect(container.read(activeToolProvider), CanvasTool.chart);
  });
  testWidgets('toolbar category targets are 44px and keep compact visuals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const CanvasToolbar()),
      ),
    );
    await tester.pumpAndSettle();

    for (final category in [
      'pointer',
      'shapes',
      'diagrams',
      'charts',
      'creative',
      'ai',
      'text',
      'org',
      'media',
      'collab',
    ]) {
      final target = find.byKey(
        ValueKey('canvas-toolbar-category-target-$category'),
      );
      expect(tester.getSize(target), const Size(44, 44));
      final visual = find.byKey(
        ValueKey('canvas-toolbar-category-visual-$category'),
      );
      expect(tester.getSize(visual), const Size(36, 36));
    }

    final shapeCategory = find.byTooltip('Shapes & Links (Click to open)');
    expect(shapeCategory.hitTestable(), findsOneWidget);
    await tester.tap(shapeCategory);
    await tester.pumpAndSettle();
    expect(find.text('SHAPES & LINKS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool flyout stays scrollable in a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const CanvasToolbar()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Shapes & Links (Click to open)'));
    await tester.pumpAndSettle();
    final flyout = find.byKey(const ValueKey('canvas-toolbar-flyout-scroll'));
    expect(flyout, findsOneWidget);
    expect(tester.getRect(flyout).height, lessThanOrEqualTo(220));

    final lastTool = find.text('Smart Connector (C)');
    await tester.ensureVisible(lastTool);
    expect(tester.getRect(lastTool).bottom, lessThanOrEqualTo(220));
    final lastToolTarget = find
        .ancestor(of: lastTool, matching: find.byType(InkWell))
        .first;
    expect(
      tester.getSize(lastToolTarget).height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    await tester.tapAt(
      tester.getRect(lastToolTarget).bottomRight - const Offset(2, 2),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeToolProvider), CanvasTool.connector);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom brush width stays reachable in compact Canvas chrome', (
    tester,
  ) async {
    await pumpCanvas(tester, size: const Size(390, 844));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CanvasScreen)),
    );
    container.read(activeToolProvider.notifier).setTool(CanvasTool.brush);
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('custom-brush-width'));
    await tester.ensureVisible(field);
    final fieldRect = tester.getRect(field);
    expect(fieldRect.left, greaterThanOrEqualTo(0));
    expect(fieldRect.right, lessThanOrEqualTo(390));
    expect(fieldRect.top, greaterThanOrEqualTo(0));
    expect(fieldRect.bottom, lessThanOrEqualTo(844));
    expect(tester.getSize(field).width, greaterThanOrEqualTo(62));
    expect(find.text('Custom'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(field, '36');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(container.read(activeBrushConfigProvider).strokeWidth, 36);
    expect(tester.takeException(), isNull);
  });

  testWidgets('brush preset opens the full brush color picker', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const CanvasToolbar()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Draw & Vector (Click to open)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brush / Freehand (B)'));
    await tester.pumpAndSettle();

    final brushPresetSurface = find.byWidgetPredicate(
      (widget) =>
          widget is UiSurface &&
          widget.padding == const EdgeInsets.all(AppSpacing.sm) &&
          widget.borderRadius == BorderRadius.circular(AppRadius.control),
    );
    expect(brushPresetSurface, findsOneWidget);
    final brushPresetRect = tester.getRect(brushPresetSurface);
    final brushPresetHeadingRect = tester.getRect(find.text('BRUSH PRESET'));
    expect(brushPresetHeadingRect.left - brushPresetRect.left, 9);
    expect(brushPresetHeadingRect.top - brushPresetRect.top, 9);
    final brushTypeControl = find.ancestor(
      of: find.text('INK'),
      matching: find.byType(Container),
    );
    expect(
      tester.widget<Container>(brushTypeControl.first).padding,
      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    );
    await tester.tap(find.bySemanticsLabel('Pick brush color'));
    await tester.pumpAndSettle();

    expect(find.byType(InspectorColorPickerArea), findsOneWidget);
    expect(find.byType(InspectorColorPickerSlider), findsNWidgets(2));
    expect(find.text('RGB'), findsOneWidget);
    expect(find.text('HSV'), findsOneWidget);
    expect(find.text('HEX'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('color-picker-hex')),
      '#FF336699',
    );
    await tester.pump();

    expect(
      container.read(activeBrushConfigProvider).color,
      const Color(0xFF336699),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('brush preset controls meet the shared touch target', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const CanvasToolbar()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Draw & Vector (Click to open)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brush / Freehand (B)'));
    await tester.pumpAndSettle();

    Finder targetFor(String visibleLabel) => find
        .ancestor(of: find.text(visibleLabel), matching: find.byType(InkWell))
        .first;

    final brushType = targetFor('MARKER');
    final brushTypeSize = tester.getSize(brushType);
    expect(
      brushTypeSize.width,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(
      brushTypeSize.height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    await tester.tapAt(
      tester.getRect(brushType).bottomRight - const Offset(2, 2),
    );
    await tester.pump();
    expect(
      container.read(activeBrushConfigProvider).brushType,
      BrushType.marker,
    );

    final smoothCurves = targetFor('SMOOTH: ON');
    final smoothSize = tester.getSize(smoothCurves);
    expect(
      smoothSize.width,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(
      smoothSize.height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    await tester.tapAt(
      tester.getRect(smoothCurves).bottomRight - const Offset(2, 2),
    );
    await tester.pump();
    expect(container.read(activeBrushConfigProvider).smoothCurves, isFalse);

    final eraser = targetFor('ERASER');
    await tester.tapAt(tester.getRect(eraser).bottomRight - const Offset(2, 2));
    await tester.pump();
    expect(
      container.read(activeBrushConfigProvider).brushType,
      BrushType.eraser,
    );

    final eraserMode = targetFor('MODE: STROKE');
    final eraserModeSize = tester.getSize(eraserMode);
    expect(
      eraserModeSize.width,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(
      eraserModeSize.height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    await tester.tapAt(
      tester.getRect(eraserMode).bottomRight - const Offset(2, 2),
    );
    await tester.pump();
    expect(
      container.read(activeBrushConfigProvider).eraserMode,
      EraserMode.segment,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('brush preset accepts and clamps custom width', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const CanvasToolbar()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Draw & Vector (Click to open)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brush / Freehand (B)'));
    await tester.pumpAndSettle();

    for (final width in [2, 4, 8, 16, 24]) {
      final target = find.byKey(ValueKey('canvas-brush-width-target-$width'));
      expect(
        tester.getSize(target),
        const Size(
          AppControlSize.minimumHitTarget,
          AppControlSize.minimumHitTarget,
        ),
      );
    }
    final width24 = find.byKey(const ValueKey('canvas-brush-width-target-24'));
    await tester.tapAt(
      tester.getRect(width24).bottomRight - const Offset(2, 2),
    );
    await tester.pump();
    expect(container.read(activeBrushConfigProvider).strokeWidth, 24);

    final customWidth = find.byKey(const ValueKey('custom-brush-width'));
    expect(customWidth, findsOneWidget);
    expect(
      tester.getSize(customWidth).height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(tester.getSize(customWidth).width, greaterThanOrEqualTo(62));
    final customLabel = find.text('Custom');
    expect(customLabel, findsOneWidget);
    final fieldRect = tester.getRect(customWidth);
    final labelRect = tester.getRect(customLabel);
    expect(labelRect.left, greaterThanOrEqualTo(fieldRect.left));
    expect(labelRect.right, lessThanOrEqualTo(fieldRect.right));

    await tester.enterText(customWidth, '42.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(container.read(activeBrushConfigProvider).strokeWidth, 42.5);

    await tester.enterText(customWidth, '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      container.read(activeBrushConfigProvider).strokeWidth,
      maxBrushWidth,
    );

    await tester.enterText(customWidth, 'not-a-width');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.widget<UiTextField>(customWidth).controller!.text, '100');
    expect(
      container.read(activeBrushConfigProvider).strokeWidth,
      maxBrushWidth,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI toolbar action exposes its open/closed state', (
    tester,
  ) async {
    var aiOpened = false;
    var aiActive = true;
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          StatefulBuilder(
            builder: (context, setState) => CanvasToolbar(
              aiActive: aiActive,
              onAiPressed: () {
                aiOpened = !aiOpened;
                setState(() => aiActive = !aiActive);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hidePrompt = find.byTooltip('Hide AI prompt');
    expect(hidePrompt, findsOneWidget);
    await tester.tap(hidePrompt);
    await tester.pumpAndSettle();
    expect(aiOpened, isTrue);
    expect(find.byTooltip('Show AI prompt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI toolbar toggles the canvas prompt visibility', (
    tester,
  ) async {
    await pumpCanvas(tester);

    final prompt = find.byKey(const ValueKey('ai-prompt-field'));
    expect(prompt, findsOneWidget);
    expect(find.byTooltip('Hide AI prompt'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide AI prompt'));
    await tester.pumpAndSettle();
    expect(prompt, findsNothing);
    expect(
      find.byKey(const ValueKey('diagram-shape-drop-target')),
      findsOneWidget,
    );
    expect(find.byTooltip('Show AI prompt'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Show AI prompt'));
    await tester.pumpAndSettle();
    expect(prompt, findsOneWidget);
    expect(tester.widget<UiTextField>(prompt).focusNode!.hasFocus, isTrue);
    expect(find.byTooltip('Hide AI prompt'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-panel-shell')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _NoopAutosaveController extends AutosaveController {
  _NoopAutosaveController(super.ref);

  @override
  void init(String projectId, {bool syncCloud = true}) {}

  @override
  Future<void> saveImmediately({bool syncCloud = true}) async {}

  @override
  Future<void> dispose() async {}
}
