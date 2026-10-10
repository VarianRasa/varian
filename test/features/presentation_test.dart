import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/component_editor_modal.dart';
import '../test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/prototype_interaction.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/presentation/presentation_screen.dart';

void main() {
  group('Milestone 2: Presentation & Hotspot Tests', () {
    testWidgets(
      'PresentationScreen loads slides from Frame nodes and navigates',
      (tester) async {
        final frame1 = CanvasNode(
          id: 'f1',
          type: NodeType.frame,
          x: 0,
          y: 0,
          width: 800,
          height: 600,
          payload: FramePayload(name: 'Intro Slide'),
        );
        final frame2 = CanvasNode(
          id: 'f2',
          type: NodeType.frame,
          x: 1000,
          y: 0,
          width: 800,
          height: 600,
          payload: FramePayload(name: 'Architecture Slide'),
        );

        final doc = CanvasDocument(
          projectId: 'test-project',
          nodes: [frame1, frame2],
          edges: [],
          viewport: const Viewport(),
          updatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(home: PresentationScreen(document: doc)),
        );
        await tester.pumpAndSettle();

        expect(find.text('SLIDE 1 / 2: Intro Slide'), findsOneWidget);

        final previousButton = find.byWidgetPredicate(
          (widget) =>
              widget is UiIconButton &&
              widget.tooltip == 'Previous Slide (Left Arrow)',
        );
        final nextButton = find.byWidgetPredicate(
          (widget) =>
              widget is UiIconButton &&
              widget.tooltip == 'Next Slide (Right Arrow / Space)',
        );
        expect(previousButton, findsOneWidget);
        expect(nextButton, findsOneWidget);
        expect(tester.widget<UiIconButton>(previousButton).onPressed, isNull);
        expect(tester.widget<UiIconButton>(nextButton).onPressed, isNotNull);

        await tester.tap(nextButton);
        await tester.pumpAndSettle();

        expect(find.text('SLIDE 2 / 2: Architecture Slide'), findsOneWidget);
        expect(
          tester.widget<UiIconButton>(previousButton).onPressed,
          isNotNull,
        );
        expect(tester.widget<UiIconButton>(nextButton).onPressed, isNull);
      },
    );

    testWidgets('presentation chrome stays reachable on a compact viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final document = CanvasDocument(
        projectId: 'compact-presentation',
        nodes: [
          CanvasNode(
            id: 'intro',
            type: NodeType.frame,
            x: 0,
            y: 0,
            width: 800,
            height: 600,
            payload: FramePayload(name: 'Intro'),
          ),
          CanvasNode(
            id: 'details',
            type: NodeType.frame,
            x: 900,
            y: 0,
            width: 800,
            height: 600,
            payload: FramePayload(name: 'Details'),
          ),
        ],
        edges: [],
        viewport: const Viewport(),
        updatedAt: DateTime.utc(2026, 10, 4),
      );

      await tester.pumpWidget(
        MaterialApp(home: PresentationScreen(document: document)),
      );
      await tester.pumpAndSettle();

      final title = find.text('SLIDE 1 / 2: Intro');
      final header = find
          .ancestor(of: title, matching: find.byType(UiSurface))
          .first;
      expect(
        tester.widget<UiSurface>(header).padding,
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      );
      final headerPosition = tester.widget<Positioned>(
        find.ancestor(of: header, matching: find.byType(Positioned)).first,
      );
      expect(headerPosition.top, AppSpacing.sm);
      expect(headerPosition.left, AppSpacing.sm);
      expect(headerPosition.right, AppSpacing.sm);
      expect(tester.getRect(header).right, lessThanOrEqualTo(360));

      final horizontalControls = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      expect(horizontalControls, findsOneWidget);
      final next = find.byTooltip('Next Slide (Right Arrow / Space)');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(find.text('SLIDE 2 / 2: Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PresentationScreen handles empty frames gracefully', (
      tester,
    ) async {
      final doc = CanvasDocument(
        projectId: 'empty-project',
        nodes: [],
        edges: [],
        viewport: const Viewport(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(home: PresentationScreen(document: doc)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Frames Found for Presentation'), findsOneWidget);
      expect(find.text('Return to Canvas'), findsOneWidget);
    });

    testWidgets(
      'PresentationScreen executes a prototype navigation interaction',
      (tester) async {
        final frame1 = CanvasNode(
          id: 'f1',
          type: NodeType.frame,
          x: 0,
          y: 0,
          width: 800,
          height: 600,
          payload: FramePayload(name: 'Intro Slide'),
        );
        final frame2 = CanvasNode(
          id: 'f2',
          type: NodeType.frame,
          x: 1000,
          y: 0,
          width: 800,
          height: 600,
          payload: FramePayload(name: 'Details Slide'),
        );
        final button = CanvasNode(
          id: 'button',
          type: NodeType.rectangle,
          x: 100,
          y: 100,
          width: 120,
          height: 48,
          parentId: 'f1',
          prototypeInteractions: const [
            PrototypeInteraction(
              id: 'open-details',
              action: PrototypeAction.navigate,
              targetFrameId: 'f2',
            ),
          ],
          payload: ShapePayload(),
        );

        final doc = CanvasDocument(
          projectId: 'prototype-project',
          nodes: [frame1, frame2, button],
          edges: [],
          viewport: const Viewport(),
          updatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(home: PresentationScreen(document: doc)),
        );
        await tester.pumpAndSettle();

        expect(find.text('SLIDE 1 / 2: Intro Slide'), findsOneWidget);
        final presentationSize = tester.getSize(
          find.byType(PresentationScreen),
        );
        final scale =
            (presentationSize.width / 1440 < presentationSize.height / 900
                ? presentationSize.width / 1440
                : presentationSize.height / 900) *
            0.92;
        final offsetX = (presentationSize.width - 1440 * scale) / 2;
        final offsetY = (presentationSize.height - 900 * scale) / 2;
        await tester.tapAt(
          Offset(offsetX + 160 * scale, offsetY + 124 * scale),
        );
        await tester.pumpAndSettle();

        expect(find.text('SLIDE 2 / 2: Details Slide'), findsOneWidget);
      },
    );
    testWidgets('reduced motion disables configured prototype transitions', (
      tester,
    ) async {
      final document = CanvasDocument(
        projectId: 'reduced-motion-presentation',
        nodes: [
          CanvasNode(
            id: 'first',
            type: NodeType.frame,
            x: 0,
            y: 0,
            width: 800,
            height: 600,
            payload: FramePayload(name: 'First'),
          ),
          CanvasNode(
            id: 'second',
            type: NodeType.frame,
            x: 900,
            y: 0,
            width: 800,
            height: 600,
            payload: FramePayload(name: 'Second'),
          ),
          CanvasNode(
            id: 'button',
            type: NodeType.rectangle,
            x: 100,
            y: 100,
            width: 120,
            height: 48,
            parentId: 'first',
            prototypeInteractions: const [
              PrototypeInteraction(
                id: 'open-second',
                action: PrototypeAction.navigate,
                targetFrameId: 'second',
                transition: PrototypeTransition.dissolve,
                durationMs: 800,
              ),
            ],
            payload: ShapePayload(),
          ),
        ],
        edges: [],
        viewport: const Viewport(),
        updatedAt: DateTime.utc(2026, 10, 5),
      );
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: PresentationScreen(document: document),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero,
      );

      final presentationSize = tester.getSize(find.byType(PresentationScreen));
      final scale =
          (presentationSize.width / 1440 < presentationSize.height / 900
              ? presentationSize.width / 1440
              : presentationSize.height / 900) *
          0.92;
      final offsetX = (presentationSize.width - 1440 * scale) / 2;
      final offsetY = (presentationSize.height - 900 * scale) / 2;
      await tester.tapAt(Offset(offsetX + 160 * scale, offsetY + 124 * scale));
      await tester.pumpAndSettle();

      expect(find.text('SLIDE 2 / 2: Second'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'prototype hotspots are keyboard accessible without changing slide navigation',
      (tester) async {
        tester.view.physicalSize = const Size(900, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final frame1 = CanvasNode(
          id: 'f1',
          type: NodeType.frame,
          x: 0,
          y: 0,
          width: 800,
          height: 600,
          payload: FramePayload(name: 'Intro Slide'),
        );
        final frame2 = CanvasNode(
          id: 'f2',
          type: NodeType.frame,
          x: 1000,
          y: 0,
          width: 800,
          height: 600,
          payload: FramePayload(name: 'Details Slide'),
        );
        final button = CanvasNode(
          id: 'button',
          type: NodeType.rectangle,
          name: 'Open details',
          x: 100,
          y: 100,
          width: 120,
          height: 48,
          parentId: 'f1',
          prototypeInteractions: const [
            PrototypeInteraction(
              id: 'open-details',
              action: PrototypeAction.navigate,
              targetFrameId: 'f2',
            ),
          ],
          payload: ShapePayload(),
        );
        final doc = CanvasDocument(
          projectId: 'prototype-accessibility-project',
          nodes: [frame1, frame2, button],
          edges: [],
          viewport: const Viewport(),
          updatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(home: PresentationScreen(document: doc)),
        );
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel('Open details'), findsOneWidget);
        final semantics = tester.ensureSemantics();
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Open details'))
              .flagsCollection
              .isButton,
          isTrue,
        );
        semantics.dispose();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(find.text('SLIDE 2 / 2: Details Slide'), findsOneWidget);
      },
    );

    testWidgets('property dialog stays usable on a short viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final node = CanvasNode(
        id: 'component-master',
        type: NodeType.component,
        x: 0,
        y: 0,
        width: 240,
        height: 120,
        payload: ComponentPayload(
          masterComponentId: 'component-master',
          componentName: 'Action',
          isMaster: true,
        ),
      );
      CanvasNode? updated;

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () => ComponentEditorModal.show(
                  context,
                  node: node,
                  onUpdate: (value) => updated = value,
                ),
                child: const Text('Edit component'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit component'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Dialog).last).height, greaterThan(0));
      await tester.tap(find.text('New Prop'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Add component property'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final propertyName = find.byWidgetPredicate(
        (widget) => widget is UiTextField && widget.label == 'Property Name',
      );
      await tester.enterText(propertyName, 'label');
      await tester.tap(find.text('Add Property'));
      await tester.pumpAndSettle();

      expect(
        (updated!.payload as ComponentPayload).properties.single.name,
        'label',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
