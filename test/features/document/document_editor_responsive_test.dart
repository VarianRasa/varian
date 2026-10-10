import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/document/presentation/document_editor_screen.dart';

import '../../test_app.dart';

void main() {
  testWidgets('document toolbar uses the shared compact control size', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          DocumentEditorScreen(
            initialPayload: DocumentPayload(
              title: 'Local fixture',
              deltaJson: jsonEncode([
                {'insert': 'Protected content\n'},
              ]),
            ),
            onSaveAndExit: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toolbarFinder = find.byType(quill.QuillSimpleToolbar);
    final toolbar = tester.widget<quill.QuillSimpleToolbar>(toolbarFinder);
    expect(toolbar.config.toolbarSize, AppControlSize.extraSmall);
    expect(
      tester.getSize(toolbarFinder).height,
      AppControlSize.extraSmall * 1.4,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact document toolbar keeps zoom usable and scrolls to link editing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final originalDelta = jsonEncode([
        {'insert': 'Toolbar navigation keeps this content unchanged\n'},
      ]);
      DocumentPayload? saved;
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            DocumentEditorScreen(
              initialPayload: DocumentPayload(
                title: 'Local toolbar fixture',
                deltaJson: originalDelta,
              ),
              onSave: (payload) => saved = payload,
              onSaveAndExit: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final zoomOut = find.byTooltip('Zoom Out (Ctrl -)');
      final zoomIn = find.byTooltip('Zoom In (Ctrl +)');
      expect(zoomOut, findsOneWidget);
      expect(zoomIn, findsOneWidget);
      for (final control in [zoomOut, zoomIn]) {
        final bounds = tester.getRect(control);
        expect(
          tester.getSize(control),
          const Size(
            AppControlSize.minimumHitTarget,
            AppControlSize.minimumHitTarget,
          ),
        );
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(320));
      }
      await tester.tap(zoomOut);
      await tester.pumpAndSettle();
      expect(find.text('90%'), findsOneWidget);
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
      expect(find.text('110%'), findsOneWidget);

      final toolbar = find.byType(quill.QuillSimpleToolbar);
      final toolbarViewport = find.descendant(
        of: toolbar,
        matching: find.byType(CustomScrollView),
      );
      expect(toolbarViewport, findsOneWidget);
      final insertUrl = find.byTooltip('Insert URL');
      expect(insertUrl, findsOneWidget);
      final toolbarBounds = tester.getRect(toolbarViewport);
      final initialUrlBounds = tester.getRect(insertUrl);
      expect(initialUrlBounds.right, greaterThan(toolbarBounds.right));
      await tester.ensureVisible(insertUrl);
      await tester.pumpAndSettle();
      final visibleUrlBounds = tester.getRect(insertUrl);
      expect(visibleUrlBounds.left, greaterThanOrEqualTo(toolbarBounds.left));
      expect(visibleUrlBounds.right, lessThanOrEqualTo(toolbarBounds.right));
      await tester.tap(insertUrl);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(jsonDecode(saved!.deltaJson!), jsonDecode(originalDelta));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'theme picker fits a short viewport and preserves Delta on save',
    (tester) async {
      tester.view.physicalSize = const Size(390, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final originalDelta = jsonEncode([
        {'insert': 'Protected text\n'},
      ]);
      DocumentPayload? saved;
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            DocumentEditorScreen(
              initialPayload: DocumentPayload(
                title: 'Notes',
                deltaJson: originalDelta,
              ),
              onSave: (payload) => saved = payload,
              onSaveAndExit: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Paper Tone / Theme'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Paper tone and theme'), findsOneWidget);
      expect(
        tester.getSize(find.byType(Dialog).last).height,
        lessThanOrEqualTo(480),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Vintage Sepia'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.themeId, 'sepia');
      expect(jsonDecode(saved!.deltaJson!), jsonDecode(originalDelta));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'paper settings save preset, orientation and margin without changing Delta',
    (tester) async {
      tester.view.physicalSize = const Size(360, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final originalDelta = jsonEncode([
        {'insert': 'Paper settings preserve content\n'},
      ]);
      DocumentPayload? saved;
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            DocumentEditorScreen(
              initialPayload: DocumentPayload(
                title: 'Notes',
                deltaJson: originalDelta,
              ),
              onSave: (payload) => saved = payload,
              onSaveAndExit: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Page and paper settings'));
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog).last;
      expect(tester.getSize(dialog).height, lessThanOrEqualTo(360));
      final presetList = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('document-paper-preset-list')),
      );
      expect(
        ((presetList.decoration as BoxDecoration).border! as Border).top.width,
        AppBorder.thin,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('US Letter'));
      final dividers = tester.widgetList<Divider>(find.byType(Divider));
      expect(dividers, isNotEmpty);
      expect(
        dividers.every((divider) => divider.height == AppBorder.thin),
        isTrue,
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Landscape'));
      await tester.tap(find.text('Landscape'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Wide (96pt)'));
      await tester.tap(find.text('Wide (96pt)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('DONE'));
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.paperPresetId, 'letter');
      expect(saved!.isLandscape, isTrue);
      expect(saved!.marginPreset, 96.0);
      expect(jsonDecode(saved!.deltaJson!), jsonDecode(originalDelta));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsaved exit confirmation fits short viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          DocumentEditorScreen(
            initialPayload: DocumentPayload(title: 'Notes'),
            onSaveAndExit: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Page and paper settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Landscape'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('DONE'));
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    expect(
      tester.getSize(find.byType(Dialog).last).height,
      lessThanOrEqualTo(360),
    );
    expect(find.text('Keep editing'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentEditorScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'export dialog fits a short viewport and closes without editing',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            DocumentEditorScreen(
              initialPayload: DocumentPayload(title: 'Notes'),
              onSaveAndExit: (_) {},
            ),
          ),
        ),
      );

      final exportAction = find.byTooltip('Export Document');
      await tester.ensureVisible(exportAction);
      await tester.pumpAndSettle();
      expect(tester.getRect(exportAction).right, lessThanOrEqualTo(360));
      await tester.tap(exportAction);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Export document'), findsOneWidget);
      expect(find.text('Copy Delta JSON'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
