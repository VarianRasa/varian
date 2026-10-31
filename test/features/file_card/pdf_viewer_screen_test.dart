import 'package:mix/mix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf/pdf_annotation_layer.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf/pdf_search_bar.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf/pdf_sidebar.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf_viewer_screen.dart';

import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import '../../test_app.dart';

class _FakePdfTextSearcher implements PdfTextSearcher {
  final Set<VoidCallback> _listeners = {};

  @override
  VoidCallback addListener(VoidCallback listener) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  @override
  List<PdfPageTextRange> get matches => const [];

  @override
  int? get currentIndex => null;

  @override
  bool get hasMatches => false;

  @override
  bool get isSearching => false;

  @override
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
  }) {}

  @override
  void resetTextSearch() {}

  @override
  void dispose() {
    _listeners.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF Acrobat Suite Tests', () {
    test('PdfAnnotation models creation and copyWith', () {
      final note = PdfStickyNote(
        id: 'note-1',
        pageNumber: 2,
        relativePosition: const Offset(0.4, 0.6),
        text: 'Review this paragraph',
        color: Colors.amber,
        createdAt: DateTime.now(),
      );

      expect(note.id, equals('note-1'));
      expect(note.pageNumber, equals(2));
      expect(note.text, equals('Review this paragraph'));

      final updated = note.copyWith(text: 'Updated comment');
      expect(updated.text, equals('Updated comment'));
      expect(updated.pageNumber, equals(2));

      const stroke = PdfStroke(
        id: 'stroke-1',
        pageNumber: 2,
        relativePoints: [Offset(0.1, 0.1), Offset(0.2, 0.2)],
        color: Colors.red,
        strokeWidth: 2.0,
        isHighlighter: false,
      );
      expect(stroke.relativePoints.length, equals(2));
      expect(stroke.isHighlighter, isFalse);
    });

    testWidgets(
      'PdfAnnotationPainter paints strokes and current stroke without throwing',
      (tester) async {
        final painter = PdfAnnotationPainter(
          strokes: const [
            PdfStroke(
              id: 'stroke-1',
              pageNumber: 1,
              relativePoints: [Offset(0.1, 0.1), Offset(0.2, 0.2)],
              color: Colors.blue,
              strokeWidth: 3.0,
            ),
            PdfStroke(
              id: 'stroke-2',
              pageNumber: 1,
              relativePoints: [Offset(0.3, 0.3), Offset(0.4, 0.4)],
              color: Colors.yellow,
              strokeWidth: 14.0,
              isHighlighter: true,
            ),
          ],
          pageSize: const Size(200, 200),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(size: const Size(200, 200), painter: painter),
            ),
          ),
        );

        expect(find.byType(CustomPaint), findsWidgets);
      },
    );

    testWidgets(
      'PdfSearchBar renders and triggers search interaction correctly',
      (tester) async {
        final textSearcher = _FakePdfTextSearcher();
        bool closed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PdfSearchBar(
                textSearcher: textSearcher,
                onClose: () => closed = true,
                isDarkTheme: true,
              ),
            ),
          ),
        );

        expect(find.byType(Box), findsWidgets);
        final outerSize = tester.getSize(find.byType(Box).first);
        final contentSize = tester.getSize(find.byType(Row).first);
        expect(
          outerSize.width - contentSize.width,
          AppSpacing.md * 2 + AppBorder.thin * 2,
        );
        expect(
          outerSize.height - contentSize.height,
          AppSpacing.xs * 2 + AppBorder.thin * 2,
        );
        expect(find.byIcon(Icons.search), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'evaluation');
        await tester.pump();

        await tester.tap(find.byTooltip('Close Search (Esc)'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(closed, isTrue);

        textSearcher.dispose();
      },
    );
    testWidgets(
      'PdfSearchBar keeps trailing actions reachable in a narrow viewport',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final textSearcher = _FakePdfTextSearcher();
        var closed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 288,
                  child: PdfSearchBar(
                    textSearcher: textSearcher,
                    onClose: () => closed = true,
                    isDarkTheme: true,
                  ),
                ),
              ),
            ),
          ),
        );

        final closeSearch = find.byTooltip('Close Search (Esc)');
        expect(closeSearch, findsOneWidget);
        for (final action in [
          closeSearch,
          find.byTooltip('Previous Match (Shift+Enter)'),
          find.byTooltip('Next Match (Enter)'),
        ]) {
          expect(
            tester.getSize(action),
            const Size(
              AppControlSize.minimumHitTarget,
              AppControlSize.minimumHitTarget,
            ),
          );
        }
        final actionsScroll = find.byKey(
          const ValueKey('pdf-search-actions-scroll'),
        );
        expect(actionsScroll, findsOneWidget);
        await tester.drag(actionsScroll, const Offset(-600, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close Search (Esc)'));
        expect(closed, isTrue);

        textSearcher.dispose();
      },
    );

    testWidgets('PdfSidebar renders tabs and handles tab switching', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = PdfViewerController();
      PdfSidebarTab activeTab = PdfSidebarTab.thumbnails;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    height: 900,
                    child: PdfSidebar(
                      pdfController: controller,
                      activeTab: activeTab,
                      onTabChanged: (tab) => setState(() => activeTab = tab),
                      outlineNodes: null,
                      stickyNotes: [
                        PdfStickyNote(
                          id: 'note-1',
                          pageNumber: 1,
                          relativePosition: const Offset(0.5, 0.5),
                          text: 'Test note content',
                          color: Colors.orange,
                          createdAt: DateTime.now(),
                        ),
                      ],
                      currentPage: 1,
                      pageCount: 3,
                      isDarkTheme: true,
                      onClose: () {},
                      onPageSelected: (_) {},
                      onDestSelected: (_) {},
                      onNoteSelected: (_) {},
                      onNoteDeleted: (_) {},
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Pages'), findsOneWidget);
      final sidebar = tester.widget<Container>(
        find.byKey(const ValueKey('pdf-sidebar-frame')),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('pdf-sidebar-frame'))).width,
        280,
      );
      final sidebarBorder =
          (sidebar.decoration! as BoxDecoration).border! as Border;
      expect(sidebarBorder.right.width, AppBorder.thin);
      expect(sidebarBorder.right.color, AppTokens.dark.panelBorder);

      final sidebarHeader = find.byKey(const ValueKey('pdf-sidebar-header'));
      expect(
        tester.getSize(sidebarHeader).height,
        AppControlSize.minimumHitTarget + AppBorder.thin,
      );
      final closeSidebar = find.byTooltip('Close Sidebar');
      expect(
        tester.getSize(closeSidebar),
        const Size(
          AppControlSize.minimumHitTarget,
          AppControlSize.minimumHitTarget,
        ),
      );
      final sidebarHeaderBorder =
          (tester.widget<Container>(sidebarHeader).decoration! as BoxDecoration)
                  .border!
              as Border;
      expect(sidebarHeaderBorder.bottom.width, AppBorder.thin);
      expect(sidebarHeaderBorder.bottom.color, AppTokens.dark.panelBorder);

      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);

      // Thumbnails tab shows page items
      expect(find.text('PAGE 1'), findsOneWidget);

      final pageFrames = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).border != null &&
            widget.child is AspectRatio,
      );
      expect(pageFrames, findsNWidgets(2));
      final currentFrame = tester.widget<Container>(pageFrames.at(0));
      final otherFrame = tester.widget<Container>(pageFrames.at(1));
      expect(
        (currentFrame.decoration! as BoxDecoration).border!.top.width,
        AppBorder.focus,
      );
      expect(
        (otherFrame.decoration! as BoxDecoration).border!.top.width,
        AppBorder.thin,
      );
      // Switch to Notes tab
      await tester.tap(find.text('Notes'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Test note content'), findsOneWidget);

      // Switch to Bookmarks tab
      await tester.tap(find.text('Bookmarks'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No Bookmarks / Outline'), findsOneWidget);
    });

    testWidgets('PdfViewerScreen renders complete Acrobat UI suite', (
      tester,
    ) async {
      final payload = FilePayload(
        fileName: 'Skripsi_Heuristic_Evaluation.pdf',
        fileExtension: 'PDF',
        fileSizeText: '1.3 MB',
      );

      await tester.pumpWidget(
        testApp(PdfViewerScreen(payload: payload), data: AppTheme.lightTheme),
      );

      await tester.pumpAndSettle();
      final viewer = find.byTooltip('Hand Tool (Pan / Scroll)');
      final viewerTokens = Theme.of(tester.element(viewer)).appTokens;
      expect(viewerTokens.canvas, AppTokens.dark.canvas);
      expect(viewerTokens.panel, AppTokens.dark.panel);
      expect(viewerTokens.text, AppTokens.dark.text);
      final header = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.child is SizedBox &&
            (widget.child! as SizedBox).height == 56,
      );
      expect(header, findsOneWidget);
      final headerBorder =
          (tester.widget<DecoratedBox>(header).decoration as BoxDecoration)
                  .border!
              as Border;
      expect(headerBorder.bottom.width, AppBorder.thin);
      expect(headerBorder.bottom.color, AppTokens.dark.panelBorder);

      final toolbar = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.child is SingleChildScrollView &&
            widget.decoration is BoxDecoration,
      );
      expect(toolbar, findsOneWidget);
      final toolbarBorder =
          (tester.widget<Container>(toolbar).decoration! as BoxDecoration)
                  .border!
              as Border;
      expect(toolbarBorder.bottom.width, AppBorder.thin);
      expect(toolbarBorder.bottom.color, AppTokens.dark.panelBorder);

      for (final controlLabel in ['Page 1 / 1', '100%']) {
        final control = find.ancestor(
          of: find.text(controlLabel),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.child is Text &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).border != null,
          ),
        );
        expect(control, findsOneWidget);
        final controlBorder =
            (tester.widget<Container>(control).decoration! as BoxDecoration)
                    .border!
                as Border;
        expect(controlBorder.top.width, AppBorder.thin);
        expect(controlBorder.top.color, AppTokens.dark.panelBorder);
      }

      for (final key in [
        const ValueKey('pdf-page-jump-target'),
        const ValueKey('pdf-zoom-reset-target'),
      ]) {
        final target = find.byKey(key);
        final targetRect = tester.getRect(target);
        expect(
          targetRect.height,
          greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
        );
      }
      final toolbarViewport = tester.getRect(toolbar);
      final screenWidth = MediaQuery.sizeOf(
        tester.element(find.byType(PdfViewerScreen)),
      ).width;
      final toolbarScroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('pdf-acrobat-toolbar-scroll')),
      );
      expect(toolbarScroll.scrollDirection, Axis.horizontal);
      expect(toolbarViewport.left, 0);
      expect(toolbarViewport.right, screenWidth);
      expect(tester.takeException(), isNull);

      final toolbarDividers = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.color == AppTokens.dark.panelBorder &&
            widget.margin ==
                const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      );
      expect(toolbarDividers, findsNWidgets(4));
      for (var index = 0; index < 4; index++) {
        expect(
          tester.getSize(toolbarDividers.at(index)),
          Size(AppBorder.thin + AppSpacing.sm * 2, AppSpacing.pageWide),
        );
      }

      // Check header details
      expect(find.text('Skripsi_Heuristic_Evaluation.pdf'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);

      // Check Acrobat toolbar tool buttons
      expect(find.byTooltip('Hand Tool (Pan / Scroll)'), findsOneWidget);
      expect(find.byTooltip('Text Selection Tool (Copy Text)'), findsOneWidget);
      expect(find.byTooltip('Pen Draw Tool'), findsOneWidget);
      expect(find.byTooltip('Highlighter Tool'), findsOneWidget);
      expect(
        find.byTooltip('Sticky Note Tool (Click on page to place note)'),
        findsOneWidget,
      );
      expect(find.byTooltip('Rotate 90° Clockwise'), findsOneWidget);
      final statusStrip = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints ==
                const BoxConstraints(minHeight: AppControlSize.extraSmall),
      );
      expect(statusStrip, findsOneWidget);
      expect(
        tester.widget<Container>(statusStrip).constraints!.minHeight,
        AppControlSize.extraSmall,
      );
      final statusStripBorder =
          (tester.widget<Container>(statusStrip).decoration! as BoxDecoration)
                  .border!
              as Border;
      expect(statusStripBorder.top.width, AppBorder.thin);
      expect(statusStripBorder.top.color, AppTokens.dark.panelBorder);

      await tester.tap(find.byTooltip('Presentation Mode (F11)'));
      await tester.pumpAndSettle();
      final fullscreenControl = find.byTooltip('Exit Fullscreen (Esc / F11)');
      final fullscreenPosition = tester.widget<Positioned>(
        find
            .ancestor(of: fullscreenControl, matching: find.byType(Positioned))
            .first,
      );
      expect(fullscreenPosition.top, AppSpacing.md);
      expect(fullscreenPosition.right, AppSpacing.md);
      expect(statusStrip, findsNothing);
      await tester.tap(fullscreenControl);
      await tester.pumpAndSettle();
      expect(statusStrip, findsOneWidget);

      // Toggle search
      await tester.tap(find.byTooltip('Switch to Light Theme'));
      await tester.pumpAndSettle();
      final lightTokens = Theme.of(tester.element(viewer)).appTokens;
      expect(lightTokens.canvas, AppTokens.light.canvas);
      expect(lightTokens.panel, AppTokens.light.panel);
      expect(lightTokens.text, AppTokens.light.text);
      expect(
        AppMixTokens.colors(lightTokens)[AppMixTokens.text],
        AppTokens.light.text,
      );

      await tester.tap(find.byTooltip('Switch to Dark Theme'));
      await tester.pumpAndSettle();
      final darkTokens = Theme.of(tester.element(viewer)).appTokens;
      expect(darkTokens.canvas, AppTokens.dark.canvas);
      expect(darkTokens.panel, AppTokens.dark.panel);
      expect(darkTokens.text, AppTokens.dark.text);
      expect(
        AppMixTokens.colors(darkTokens)[AppMixTokens.text],
        AppTokens.dark.text,
      );

      // Search stays unavailable until the document is ready.
      final searchButton = find.byWidgetPredicate(
        (widget) =>
            widget is UiIconButton &&
            widget.tooltip == 'Search Document (Ctrl + F)',
      );
      expect(searchButton, findsOneWidget);
      expect(tester.widget<UiIconButton>(searchButton).onPressed, isNull);
      expect(find.byType(PdfSearchBar), findsNothing);

      // Toggle sidebar after dismissing the overlapping search overlay.
      await tester.tap(
        find.byTooltip('Show Navigation Panel (Thumbnails & Outline)'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PdfSidebar), findsOneWidget);
    });

    testWidgets('PDF toolbar controls meet touch bounds and scroll safely', (
      tester,
    ) async {
      for (final width in [320.0, 390.0, 599.0, 600.0, 800.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        final exceptions = <Object>[];
        Object? exception;
        await tester.pumpWidget(
          ProviderScope(
            child: testApp(
              PdfViewerScreen(
                payload: FilePayload(
                  fileName: 'local.pdf',
                  fileExtension: 'PDF',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (width < AppBreakpoints.compact) {
          expect(find.byTooltip('PDF viewer actions'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('pdf-compact-header-actions')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Search document'), findsOneWidget);
          expect(find.text('Switch to light theme'), findsOneWidget);
          await tester.tap(find.text('Switch to light theme'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('pdf-compact-header-actions')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Switch to dark theme'), findsOneWidget);
          await tester.tap(find.text('Switch to dark theme'));
          await tester.pumpAndSettle();
        }

        final toolbarViewport = tester.getRect(
          find.byKey(const ValueKey('pdf-acrobat-toolbar-scroll')),
        );
        expect(toolbarViewport.top, 56);
        expect(toolbarViewport.height, AppControlSize.minimumHitTarget);
        expect(toolbarViewport.left, AppSpacing.md);
        expect(toolbarViewport.right, width - AppSpacing.md);

        final scrollKey = find.byKey(
          const ValueKey('pdf-acrobat-toolbar-scroll'),
        );
        final scrollRect = tester.getRect(scrollKey);
        final toolbarScroll = tester.widget<SingleChildScrollView>(scrollKey);
        expect(toolbarScroll.scrollDirection, Axis.horizontal);
        final toolbarContent = find.byKey(
          const ValueKey('pdf-acrobat-toolbar-content'),
        );
        final contentScrollRect = tester.getRect(toolbarContent);
        if (width <= 800) {
          expect(contentScrollRect.right, greaterThan(scrollRect.right));
        } else {
          expect(contentScrollRect.right, lessThanOrEqualTo(scrollRect.right));
        }

        final pageTarget = find.byKey(const ValueKey('pdf-page-jump-target'));
        final zoomTarget = find.byKey(const ValueKey('pdf-zoom-reset-target'));
        for (final target in [pageTarget, zoomTarget]) {
          expect(target, findsOneWidget);
          expect(
            tester.getSize(target).height,
            greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
          );
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          final targetRect = tester.getRect(target);
          expect(targetRect.left, greaterThanOrEqualTo(scrollRect.left - 1));
          expect(targetRect.right, lessThanOrEqualTo(scrollRect.right + 1));
          expect(target.hitTestable(), findsOneWidget);
        }

        await tester.ensureVisible(pageTarget);
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(pageTarget));
        await tester.pumpAndSettle();
        expect(find.text('Go to Page'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        while ((exception = tester.takeException()) != null) {
          exceptions.add(exception!);
        }
        expect(
          exceptions,
          isEmpty,
          reason: 'PDF viewer at $width: $exceptions',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
      addTearDown(tester.view.reset);
    });

    testWidgets('sticky-note dialog uses standard app spacing', (tester) async {
      final note = PdfStickyNote(
        id: 'note-spacing',
        pageNumber: 1,
        relativePosition: const Offset(0.5, 0.5),
        text: 'Local fixture note',
        color: Colors.amber,
        createdAt: DateTime.utc(2026, 10, 3),
      );
      final payload = FilePayload(
        fileName: 'local.pdf',
        pdfAnnotations: PdfAnnotationData(stickyNotes: [note]),
      );
      await tester.pumpWidget(
        ProviderScope(child: testApp(PdfViewerScreen(payload: payload))),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip('Show Navigation Panel (Thumbnails & Outline)'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local fixture note'));
      await tester.pumpAndSettle();

      final header = tester.getRect(
        find.ancestor(
          of: find.text('Note on Page 1'),
          matching: find.byType(Row),
        ),
      );
      final noteTextRect = tester.getRect(find.text('Local fixture note').last);
      final closeButton = tester.getRect(
        find.ancestor(of: find.text('Close'), matching: find.byType(UiButton)),
      );
      expect(noteTextRect.top - header.bottom, AppSpacing.lg);
      expect(closeButton.top - noteTextRect.bottom, AppSpacing.lg);
      expect(tester.takeException(), isNull);
    });
  });
}
