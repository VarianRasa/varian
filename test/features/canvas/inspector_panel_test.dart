import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/rich_text.dart';
import 'package:varian/domain/models/model3d_studio.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/color_picker_primitives.dart';
import 'package:varian/features/canvas/presentation/widgets/inspector_panel.dart';
import 'package:varian/features/canvas/domain/canvas_precision.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';
import 'package:varian/features/mermaid/domain/mermaid_renderer.dart';

const _inspectorMermaidSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect id="A" x="10" y="10" width="20" height="20" />
  <rect id="B" x="70" y="70" width="20" height="20" />
  <path data-edge="true" data-from="A" data-to="B" d="M30 20 L70 80" />
</svg>
''';

class _InspectorMermaidRenderer implements MermaidRenderer {
  final Completer<MermaidRenderResult>? pending;
  int renderCalls = 0;

  _InspectorMermaidRenderer({this.pending});

  @override
  String get rendererVersion => 'inspector-test-renderer';

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async => const MermaidValidationResult.valid(diagramType: 'flowchart');

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) {
    renderCalls++;
    return pending?.future ??
        Future.value(
          const MermaidRenderResult(
            svg: _inspectorMermaidSvg,
            diagramType: 'flowchart',
          ),
        );
  }
}

void main() {
  testWidgets('edits and clears responsive node constraints', (tester) async {
    final frame = CanvasNode(
      id: 'constraint-frame',
      type: NodeType.frame,
      x: 0,
      y: 0,
      width: 400,
      height: 300,
      payload: ShapePayload(),
    );
    final child = CanvasNode(
      id: 'constraint-child',
      type: NodeType.rectangle,
      x: 40,
      y: 30,
      width: 120,
      height: 80,
      parentId: frame.id,
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([frame, child]);
    container.read(selectionProvider.notifier).select(child.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RESPONSIVE CONSTRAINTS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('horizontal_constraint_constraint-child')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('vertical_constraint_constraint-child')),
      findsOneWidget,
    );

    await tester.tap(find.byType(UiSelect<CanvasHorizontalConstraint>));
    await tester.pumpAndSettle();
    final leftRightOption = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownMenuItem<CanvasHorizontalConstraint> &&
          widget.value == CanvasHorizontalConstraint.leftRight,
    );
    expect(leftRightOption, findsOneWidget);
    await tester.tap(leftRightOption);
    await tester.pumpAndSettle();

    final constrained = container
        .read(documentNodesProvider)
        .firstWhere((node) => node.id == child.id);
    expect(
      constrained.constraints?.horizontal,
      CanvasHorizontalConstraint.leftRight,
    );
    expect(constrained.constraints?.vertical, CanvasVerticalConstraint.top);

    await tester.tap(
      find.byKey(const ValueKey('clear_constraints_constraint-child')),
    );
    await tester.pumpAndSettle();
    expect(
      container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == child.id)
          .constraints,
      isNull,
    );
  });

  testWidgets('drawing controls use standard app spacing', (tester) async {
    final drawing = CanvasNode(
      id: 'drawing-spacing',
      type: NodeType.drawing,
      x: 0,
      y: 0,
      width: 240,
      height: 160,
      payload: DrawingPayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([drawing]);
    container.read(selectionProvider.notifier).select(drawing.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RASTER BRUSH & STROKE'), findsOneWidget);
    expect(find.text('Brush Preset'), findsOneWidget);
    expect(find.text('Stroke Color'), findsOneWidget);
    expect(find.text('Stroke Width'), findsOneWidget);
    expect(find.text('Smooth Stroke Curves'), findsOneWidget);
    final drawingSection = tester.widget<Column>(
      find
          .ancestor(
            of: find.text('RASTER BRUSH & STROKE'),
            matching: find.byType(Column),
          )
          .first,
    );
    final sectionGaps = drawingSection.children.whereType<SizedBox>().where(
      (gap) => gap.height == AppSpacing.sm,
    );
    expect(sectionGaps, hasLength(4));
    expect(
      container.read(documentNodesProvider).single.payload,
      isA<DrawingPayload>(),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('nested-board summary uses the standard control radius', (
    tester,
  ) async {
    final node = CanvasNode(
      id: 'nested-board-radius',
      type: NodeType.nestedBoard,
      x: 0,
      y: 0,
      width: 400,
      height: 300,
      payload: NestedBoardPayload(
        boardName: 'Local fixture',
        childNodeCount: 2,
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final summary = find.ancestor(
      of: find.text('Contains 2 canvas items'),
      matching: find.byType(Container),
    );
    final summaryDecoration = tester
        .widgetList<Container>(summary)
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.borderRadius != null);
    expect(
      summaryDecoration.borderRadius,
      BorderRadius.circular(AppRadius.control),
    );
    final summaryContainer = tester
        .widgetList<Container>(summary)
        .firstWhere(
          (container) =>
              container.decoration is BoxDecoration &&
              (container.decoration! as BoxDecoration).borderRadius != null,
        );
    expect(
      summaryContainer.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xxs,
        vertical: AppSpacing.sm,
      ),
    );
    final summarySurface = find
        .ancestor(
          of: find.text('Contains 2 canvas items'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).borderRadius != null,
          ),
        )
        .first;
    final firstAction = find.ancestor(
      of: find.text('Open Sub-Canvas'),
      matching: find.byType(UiButton),
    );
    final secondAction = find.ancestor(
      of: find.text('Open Sub-Canvas Workspace'),
      matching: find.byType(UiButton),
    );
    expect(
      tester.getTopLeft(secondAction).dy - tester.getBottomLeft(firstAction).dy,
      AppSpacing.sm + AppSpacing.xxs,
    );
    final boardNameField = find.byWidgetPredicate(
      (widget) => widget is UiTextField && widget.label == 'Board Name',
    );
    final descriptionField = find.byWidgetPredicate(
      (widget) => widget is UiTextField && widget.label == 'Description',
    );
    expect(
      tester.getTopLeft(descriptionField).dy -
          tester.getBottomLeft(boardNameField).dy,
      AppSpacing.sm,
    );
    expect(
      tester.getTopLeft(summarySurface).dy -
          tester.getBottomLeft(descriptionField).dy,
      AppSpacing.sm + AppSpacing.xxs,
    );
    expect(
      (container.read(documentNodesProvider).single.payload
              as NestedBoardPayload)
          .childNodeCount,
      2,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('audited inspector chrome uses border and spacing tokens', (
    tester,
  ) async {
    final todo = CanvasNode(
      id: 'thin-checklist',
      type: NodeType.todoList,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: TodoListPayload(
        items: [TodoItem(id: 'thin-task', text: 'Keep data', dueDate: 'Today')],
      ),
    );
    final board = CanvasNode(
      id: 'thin-board',
      type: NodeType.nestedBoard,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: NestedBoardPayload(childNodeCount: 2),
    );
    final annotated = CanvasNode(
      id: 'thin-annotation',
      type: NodeType.annotatedImage,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: AnnotatedImagePayload(
        pins: [
          ImageAnnotationPin(id: 'pin', position: Offset.zero, text: 'Note'),
        ],
      ),
    );
    final richText = CanvasNode(
      id: 'thin-rich-text',
      type: NodeType.text,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: TextPayload(
        renderMode: TextRenderMode.rich,
        blocks: const [
          RichTextBlock(spans: [RichTextSpan(text: 'Preserve text')]),
        ],
      ),
    );
    final file = CanvasNode(
      id: 'thin-file',
      type: NodeType.fileCard,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: FilePayload(fileName: 'Fixture.pdf'),
    );

    final cases = <(CanvasNode, List<String>)>[
      (
        todo,
        [
          'inspector-node-type-chip',
          'inspector-checklist-progress',
          'thin-task',
        ],
      ),
      (board, ['inspector-nested-board-summary']),
      (annotated, ['inspector-annotation-toggles']),
      (richText, ['inspector-rich-text-block-0']),
      (file, ['inspector-file-details', 'inspector-shadow-toggle']),
    ];

    for (final (node, keys) in cases) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(documentNodesProvider.notifier).setNodes([node]);
      container.read(selectionProvider.notifier).select(node.id);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: AppThemeScope(
              data: AppTheme.darkTheme,
              child: const InspectorPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final key in keys) {
        final decoration =
            tester.widget<Container>(find.byKey(ValueKey(key))).decoration!
                as BoxDecoration;
        expect(decoration.border!.top.width, AppBorder.thin, reason: key);
        if (key == 'inspector-checklist-progress') {
          final progress = tester.widget<Container>(find.byKey(ValueKey(key)));
          expect(progress.padding, const EdgeInsets.all(AppSpacing.sm));
        }
      }
      if (node.payload case TodoListPayload payload) {
        expect(payload.items.single.text, 'Keep data');
        final progress = find.byKey(
          const ValueKey('inspector-checklist-progress'),
        );
        final filterRow = find
            .ancestor(of: find.text('Filter: '), matching: find.byType(Row))
            .first;
        final addTask = find
            .ancestor(
              of: find.text('Add Task'),
              matching: find.byType(UiButton),
            )
            .first;
        final taskItem = find.byKey(const ValueKey('thin-task'));
        final controlGap = find.byKey(
          const ValueKey('inspector-checklist-task-control-gap'),
        );
        expect(
          find.byKey(const ValueKey('item_text_thin-task')),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Mark task done',
          ),
          findsOneWidget,
        );
        final assigneeGap = find.byKey(
          const ValueKey('inspector-checklist-assignee-gap'),
        );

        expect(
          tester.getTopLeft(filterRow).dy - tester.getBottomLeft(progress).dy,
          AppSpacing.sm + AppSpacing.xxs,
        );
        expect(
          tester.getTopLeft(addTask).dy - tester.getBottomLeft(filterRow).dy,
          AppSpacing.sm,
        );
        expect(
          tester.getTopLeft(taskItem).dy - tester.getBottomLeft(addTask).dy,
          AppSpacing.sm,
        );
        expect(tester.getSize(controlGap).width, AppSpacing.sm);
        expect(tester.getSize(assigneeGap).height, AppSpacing.xs);
      }
      if (node.payload case AnnotatedImagePayload payload) {
        final toggles = find.byKey(
          const ValueKey('inspector-annotation-toggles'),
        );
        final toggleContainer = tester.widget<Container>(toggles);
        expect(
          toggleContainer.padding,
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        );
        expect(
          tester
              .widget<Divider>(
                find.byKey(
                  const ValueKey('inspector-annotation-toggle-divider'),
                ),
              )
              .height,
          AppSpacing.sm,
        );
        expect(
          tester
              .getSize(
                find.byKey(
                  const ValueKey('inspector-annotation-pin-section-gap'),
                ),
              )
              .height,
          AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
        );
        final pinCard = find.byKey(
          ValueKey('inspector-annotation-pin-${payload.pins.single.id}'),
        );
        expect(
          tester.widget<Container>(pinCard).padding,
          const EdgeInsets.all(AppSpacing.sm),
        );
        expect(find.text('Note'), findsOneWidget);
      }
    }
  });
  testWidgets('shadow-toggle row border remains distinct from value', (
    tester,
  ) async {
    final node = CanvasNode(
      id: 'shadow-toggle',
      type: NodeType.fileCard,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: FilePayload(hasShadow: false),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester.widget<Container>(
      find.byKey(const ValueKey('inspector-shadow-toggle')),
    );
    expect(
      row.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xxs,
        vertical: AppSpacing.xs,
      ),
    );
    expect(
      (row.decoration! as BoxDecoration).border!.top.width,
      AppBorder.thin,
    );
    expect(
      (container.read(documentNodesProvider).single.payload as FilePayload)
          .hasShadow,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('component inspector list gaps use standard spacing tokens', (
    tester,
  ) async {
    final payload = ComponentPayload(
      masterComponentId: 'component-spacing',
      componentName: 'Local fixture',
      isMaster: true,
      tokenBindings: const {'color.primary': 'brand.primary'},
      slots: const [ComponentSlot(id: 'body', name: 'Body')],
    );
    final node = CanvasNode(
      id: 'component-spacing',
      type: NodeType.component,
      x: 0,
      y: 0,
      width: 240,
      height: 120,
      payload: payload,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final componentControls = tester.widget<Column>(
      find
          .ancestor(of: find.text('◇ Instance'), matching: find.byType(Column))
          .first,
    );
    final componentGaps = componentControls.children
        .whereType<SizedBox>()
        .where((gap) => gap.height == AppSpacing.sm + AppSpacing.xxs);
    expect(componentGaps, hasLength(1));

    final tokenControls = tester.widget<Column>(
      find
          .ancestor(
            of: find.text('BOUND DESIGN TOKENS'),
            matching: find.byType(Column),
          )
          .first,
    );
    final slotControls = tester.widget<Column>(
      find
          .ancestor(
            of: find.text('CONTENT SLOTS'),
            matching: find.byType(Column),
          )
          .first,
    );
    expect(
      tokenControls.children.whereType<SizedBox>().map((gap) => gap.height),
      contains(AppSpacing.xs),
    );
    expect(
      slotControls.children.whereType<SizedBox>().map((gap) => gap.height),
      contains(AppSpacing.xs),
    );
    final savedPayload =
        container.read(documentNodesProvider).single.payload
            as ComponentPayload;
    expect(savedPayload.tokenBindings, payload.tokenBindings);
    expect(savedPayload.slots, payload.slots);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ellipse inspector field gaps use the standard spacing token', (
    tester,
  ) async {
    final node = CanvasNode(
      id: 'ellipse-spacing',
      type: NodeType.ellipse,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shapeControls = tester.widget<Column>(
      find
          .ancestor(of: find.text('ARC / DONUT'), matching: find.byType(Column))
          .first,
    );
    expect(
      shapeControls.children.whereType<SizedBox>().where(
        (gap) => gap.height == AppSpacing.xs + AppSpacing.xxs,
      ),
      hasLength(2),
    );
    expect(
      (container.read(documentNodesProvider).single.payload as ShapePayload)
          .startAngle,
      0,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('rectangle corner controls use tokenized row spacing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final node = CanvasNode(
      id: 'rectangle-corner-spacing',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Switch).first);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    final radiusFields = find.byType(UiTextField).evaluate().where((element) {
      final widget = element.widget as UiTextField;
      return const {'TL', 'TR', 'BL', 'BR'}.contains(widget.label);
    }).toList();
    expect(radiusFields, hasLength(4));
    final topRow = tester.widget<Row>(
      find
          .ancestor(
            of: find.byWidget(radiusFields[0].widget),
            matching: find.byType(Row),
          )
          .first,
    );
    final bottomRow = tester.widget<Row>(
      find
          .ancestor(
            of: find.byWidget(radiusFields[2].widget),
            matching: find.byType(Row),
          )
          .first,
    );
    final topRowRect = tester.getRect(
      find
          .ancestor(
            of: find.byWidget(radiusFields[0].widget),
            matching: find.byType(Row),
          )
          .first,
    );
    final bottomRowRect = tester.getRect(
      find
          .ancestor(
            of: find.byWidget(radiusFields[2].widget),
            matching: find.byType(Row),
          )
          .first,
    );
    final column = tester.widget<Column>(
      find
          .ancestor(of: find.byWidget(topRow), matching: find.byType(Column))
          .first,
    );
    expect(
      column.children.whereType<SizedBox>().where(
        (gap) => gap.height == AppSpacing.xs + AppSpacing.xxs,
      ),
      hasLength(2),
    );
    expect(
      bottomRowRect.top - topRowRect.bottom,
      AppSpacing.xs + AppSpacing.xxs,
    );
    for (final row in [topRow, bottomRow]) {
      expect(
        row.children.whereType<SizedBox>().where(
          (gap) => gap.width == AppSpacing.xs + AppSpacing.xxs,
        ),
        hasLength(1),
      );
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('frame layout preset controls keep token-sized gaps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final frame = CanvasNode(
      id: 'frame-spacing-fixture',
      type: NodeType.frame,
      x: 0,
      y: 0,
      width: 360,
      height: 240,
      payload: FramePayload(layoutDirection: AutoLayoutDirection.horizontal),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([frame]);
    container.read(selectionProvider.notifier).select(frame.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final wraps = tester.widgetList<Wrap>(find.byType(Wrap));
    for (final key in const [
      'inspector-frame-layout-preset-gap',
      'inspector-frame-spacing-preset-gap',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))).height,
        AppSpacing.xs + AppSpacing.xxs,
      );
    }
    expect(find.text('LAYOUT PRESET'), findsOneWidget);
    expect(find.text('SPACING PRESET'), findsOneWidget);
    expect(
      wraps.where(
        (wrap) =>
            wrap.spacing == AppSpacing.xs && wrap.runSpacing == AppSpacing.xs,
      ),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('document inspector section gaps keep exact token geometry', (
    tester,
  ) async {
    final document = CanvasNode(
      id: 'document-inspector-spacing',
      type: NodeType.document,
      x: 0,
      y: 0,
      width: 595,
      height: 842,
      payload: DocumentPayload(title: 'Fixture document'),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([document]);
    container.read(selectionProvider.notifier).select(document.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final key in const [
      'inspector-document-title-gap',
      'inspector-document-template-gap',
      'inspector-document-appearance-gap',
      'inspector-document-border-gap',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))).height,
        AppSpacing.sm + AppSpacing.xxs,
      );
    }
    expect(
      tester
          .getSize(find.byKey(const ValueKey('inspector-document-theme-gap')))
          .height,
      AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
    );
    expect(find.text('DOCUMENT CARD'), findsOneWidget);
    expect(
      (container.read(documentNodesProvider).single.payload as DocumentPayload)
          .title,
      'Fixture document',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('InspectorPanel ignores a selection missing from the document', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectionProvider.overrideWith(
            (ref) => SelectionNotifier()..select('missing-node'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 280, child: InspectorPanel()),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('NO SELECTION'), findsOneWidget);
  });

  testWidgets('Chart inspector edits chart fields through document history', (
    tester,
  ) async {
    final chart = CanvasNode(
      id: 'chart-inspector',
      type: NodeType.chart,
      x: 0,
      y: 0,
      width: 360,
      height: 240,
      payload: ChartPayload(
        title: 'Initial chart',
        chartType: ChartType.bar,
        categories: const ['A', 'B'],
        series: [
          ChartSeries(name: 'Revenue', values: const [2, 4]),
        ],
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([chart]);
    container.read(selectionProvider.notifier).select(chart.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CHART'), findsAtLeastNWidgets(1));
    expect(find.text('SERIES DATA'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chart_title_chart-inspector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chart_categories_chart-inspector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chart_category_filter_chart-inspector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chart_series_values_chart-inspector_0')),
      findsOneWidget,
    );
    final seriesCard = tester.widget<Container>(
      find.byKey(
        const ValueKey('inspector-chart-series-card-chart-inspector-0'),
      ),
    );
    final seriesCardBorder =
        (seriesCard.decoration! as BoxDecoration).border! as Border;
    expect(seriesCardBorder.top.width, AppBorder.thin);
    expect(find.byType(UiSelect<ChartType>), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chart_min_y_chart-inspector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chart_max_y_chart-inspector')),
      findsOneWidget,
    );

    await tester.tap(find.byType(UiSelect<ChartType>));
    await tester.pumpAndSettle();
    final lineOption = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownMenuItem<ChartType> &&
          widget.value == ChartType.line,
    );
    expect(lineOption, findsOneWidget);
    await tester.tap(lineOption);
    await tester.pumpAndSettle();
    expect(
      (container.read(documentNodesProvider).single.payload as ChartPayload)
          .chartType,
      ChartType.line,
    );

    await tester.enterText(
      find.byKey(const ValueKey('chart_title_chart-inspector')),
      'Updated chart',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chart_categories_chart-inspector')),
      'Q1, Q2, Q3',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chart_category_filter_chart-inspector')),
      'Q',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chart_series_values_chart-inspector_0')),
      '3, 8, 13',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chart_min_y_chart-inspector')),
      '0',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chart_max_y_chart-inspector')),
      '20',
    );
    await tester.pump();

    final stored = container.read(documentNodesProvider).single;
    final payload = stored.payload as ChartPayload;
    expect(payload.title, 'Updated chart');
    expect(payload.categories, ['Q1', 'Q2', 'Q3']);
    expect(payload.categoryFilter, 'Q');
    expect(payload.series.single.values, [3, 8, 13]);
    expect(payload.minY, 0);
    expect(payload.maxY, 20);
    expect(container.read(historyProvider).canUndo, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chart inspector exposes JSON source and refresh controls', (
    tester,
  ) async {
    final chart = CanvasNode(
      id: 'chart-json-source',
      type: NodeType.chart,
      x: 0,
      y: 0,
      width: 360,
      height: 240,
      payload: ChartPayload(
        dataSourceUrl: 'https://example.com/chart.json',
        dataRefreshRevision: 2,
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([chart]);
    container.read(selectionProvider.notifier).select(chart.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chart_data_source_url_chart-json-source')),
      findsOneWidget,
    );
    final refresh = find.byKey(
      const ValueKey('chart_refresh_source_chart-json-source'),
    );
    expect(refresh, findsOneWidget);
    await tester.scrollUntilVisible(
      refresh,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(refresh);
    await tester.pump(const Duration(milliseconds: 120));

    final stored = container.read(documentNodesProvider).single;
    expect((stored.payload as ChartPayload).dataRefreshRevision, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chart inspector exposes database source controls', (
    tester,
  ) async {
    final chart = CanvasNode(
      id: 'chart-database-source',
      type: NodeType.chart,
      x: 0,
      y: 0,
      width: 360,
      height: 240,
      payload: ChartPayload(
        databaseTableName: 'sales_chart',
        databaseCategoryColumn: 'category',
        databaseValueColumns: const ['revenue', 'cost'],
        databaseRowLimit: 20,
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([chart]);
    container.read(selectionProvider.notifier).select(chart.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tableField = find.byKey(
      const ValueKey('chart_database_table_chart-database-source'),
    );
    final refresh = find.byKey(
      const ValueKey('chart_refresh_database_chart-database-source'),
    );
    expect(tableField, findsOneWidget);
    expect(refresh, findsOneWidget);
    await tester.scrollUntilVisible(
      refresh,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(refresh);
    await tester.pump(const Duration(milliseconds: 120));

    final stored = container.read(documentNodesProvider).single;
    expect((stored.payload as ChartPayload).dataRefreshRevision, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chart inspector binds a table data source', (tester) async {
    final table = CanvasNode(
      id: 'table-source',
      type: NodeType.tableGrid,
      x: 0,
      y: 0,
      width: 280,
      height: 160,
      payload: TablePayload(
        name: 'Sales Table',
        columns: const ['Quarter', 'Revenue', 'Cost'],
        columnTypes: const [
          TableCellType.text,
          TableCellType.number,
          TableCellType.number,
        ],
        rows: const [
          ['Q1', '10', '7'],
          ['Q2', '14', '9'],
        ],
      ),
    );
    final chart = CanvasNode(
      id: 'chart-table-binding',
      type: NodeType.chart,
      x: 320,
      y: 0,
      width: 360,
      height: 240,
      payload: ChartPayload(dataSourceUrl: 'https://example.com/chart.json'),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([table, chart]);
    container.read(selectionProvider.notifier).select(chart.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tableSourceSelect = find.byType(UiSelect<String>);
    await tester.ensureVisible(tableSourceSelect);
    await tester.pumpAndSettle();
    await tester.tap(tableSourceSelect);
    await tester.pumpAndSettle();
    final tableOption = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownMenuItem<String> && widget.value == table.id,
    );
    expect(tableOption, findsOneWidget);
    await tester.tap(tableOption);
    await tester.pumpAndSettle();

    final stored = container
        .read(documentNodesProvider)
        .firstWhere((node) => node.id == chart.id);
    expect((stored.payload as ChartPayload).tableSourceNodeId, table.id);
    expect((stored.payload as ChartPayload).dataSourceUrl, isNull);
    expect(find.byType(UiSelect<int>), findsOneWidget);
  });

  testWidgets('Chart inspector opens the data table editor action', (
    tester,
  ) async {
    final chart = CanvasNode(
      id: 'chart-editor-action',
      type: NodeType.chart,
      x: 0,
      y: 0,
      width: 320,
      height: 220,
      payload: ChartPayload(
        categories: const ['A', 'B'],
        series: [
          ChartSeries(values: const [1, 2]),
        ],
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([chart]);
    container.read(selectionProvider.notifier).select(chart.id);
    CanvasNode? opened;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: InspectorPanel(onEditChartData: (node) => opened = node),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('chart_edit_data_chart-editor-action')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(opened?.id, chart.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mermaid inspector converts through the async lifecycle', (
    tester,
  ) async {
    final source = CanvasNode(
      id: 'mermaid-ui',
      type: NodeType.mermaid,
      x: 0,
      y: 0,
      width: 480,
      height: 320,
      payload: MermaidPayload(source: 'sequenceDiagram\n  Alice->>Bob: Hello'),
    );
    final renderer = _InspectorMermaidRenderer();
    final container = ProviderContainer(
      overrides: [
        documentNodesProvider.overrideWith(
          (ref) => DocumentNodesNotifier(
            ref,
            initialNodes: [source],
            mermaidRenderer: renderer,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(selectionProvider.notifier).select(source.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final convertButton = find.byKey(
      const ValueKey('mermaid-convert-mermaid-ui'),
    );
    expect(convertButton, findsOneWidget);
    await tester.tap(convertButton);
    await tester.pumpAndSettle();

    expect(renderer.renderCalls, 1);
    final stored = container.read(documentNodesProvider).first;
    final payload = stored.payload as MermaidPayload;
    expect(payload.renderMode, MermaidRenderMode.native);
    expect(payload.nativeNodeIds, hasLength(2));
    expect(payload.nativeEdgeIds, hasLength(1));
    expect(
      find.byKey(const ValueKey('mermaid-regenerate-mermaid-ui')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mermaid inspector disables duplicate conversion requests', (
    tester,
  ) async {
    final source = CanvasNode(
      id: 'mermaid-ui-pending',
      type: NodeType.mermaid,
      x: 0,
      y: 0,
      width: 480,
      height: 320,
      payload: MermaidPayload(source: 'sequenceDiagram\n  Alice->>Bob: Hello'),
    );
    final pending = Completer<MermaidRenderResult>();
    final renderer = _InspectorMermaidRenderer(pending: pending);
    final container = ProviderContainer(
      overrides: [
        documentNodesProvider.overrideWith(
          (ref) => DocumentNodesNotifier(
            ref,
            initialNodes: [source],
            mermaidRenderer: renderer,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(selectionProvider.notifier).select(source.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final convertButton = find.byKey(
      const ValueKey('mermaid-convert-mermaid-ui-pending'),
    );
    await tester.tap(convertButton);
    await tester.pump();

    expect(find.text('Converting…'), findsOneWidget);
    expect(tester.widget<UiButton>(convertButton).onPressed, isNull);

    pending.complete(
      const MermaidRenderResult(
        svg: _inspectorMermaidSvg,
        diagramType: 'flowchart',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(documentNodesProvider).first.payload is MermaidPayload,
      isTrue,
    );
  });

  testWidgets(
    'InspectorPanel does not update a provider while syncing fields',
    (tester) async {
      final node = CanvasNode(
        id: 'node-1',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 120,
        height: 80,
        payload: ShapePayload(),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(documentNodesProvider.notifier).setNodes([node]);
      container.read(selectionProvider.notifier).select(node.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: AppThemeScope(
              data: AppTheme.darkTheme,
              child: const InspectorPanel(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      container
          .read(documentNodesProvider.notifier)
          .updateNode(node.copyWith(x: 120));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(container.read(documentNodesProvider).single.x, 120);
    },
  );

  testWidgets('model inspector exposes preview actions and metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final node = CanvasNode(
      id: 'model-node',
      type: NodeType.model3d,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: Model3DPayload(
        fileName: 'chair.glb',
        fileSizeText: '24 B',
        artifactReference: 'varian-model3d://model-1',
        cameraBookmarks: const [
          Model3DCameraBookmark(id: 'duplicate'),
          Model3DCameraBookmark(id: 'duplicate'),
        ],
        activeCameraBookmarkId: 'missing-bookmark',
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    var resetCount = 0;
    var retryCount = 0;
    var replaceCount = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 240,
                child: InspectorPanel(
                  width: 240,
                  onResetModel3d: (_) => resetCount++,
                  onRetryModel3d: (_) => retryCount++,
                  onReplaceModel3d: (_) async => replaceCount++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final inspectorBounds = tester.getRect(find.byType(InspectorPanel));
    expect(inspectorBounds.left, greaterThanOrEqualTo(0));
    expect(inspectorBounds.right, lessThanOrEqualTo(360));
    expect(inspectorBounds.top, greaterThanOrEqualTo(0));
    expect(inspectorBounds.bottom, lessThanOrEqualTo(480));
    expect(inspectorBounds.width, 240);
    final modelSurface = find.ancestor(
      of: find.text('chair.glb'),
      matching: find.byType(UiSurface),
    );
    await tester.scrollUntilVisible(
      find.text('chair.glb'),
      240,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final modelSurfaceBounds = tester.getRect(modelSurface.first);
    expect(modelSurfaceBounds.left, greaterThanOrEqualTo(inspectorBounds.left));
    expect(modelSurfaceBounds.right, lessThanOrEqualTo(inspectorBounds.right));
    for (final action in [
      find.text('Reset view'),
      find.text('Retry preview'),
      find.text('Replace GLB'),
    ]) {
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(action);
      expect(bounds.left, greaterThanOrEqualTo(inspectorBounds.left));
      expect(bounds.right, lessThanOrEqualTo(inspectorBounds.right));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(480));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('GLB MODEL'), findsOneWidget);
    expect(find.text('chair.glb'), findsOneWidget);
    expect(find.text('Reset view'), findsOneWidget);
    expect(find.text('Retry preview'), findsOneWidget);
    final duplicateDiagnostic = find.text(
      'Camera bookmark IDs are duplicated.',
    );
    final missingDiagnostic = find.text(
      'Active camera bookmark does not exist.',
    );
    final diagnosticRowPadding = find.ancestor(
      of: duplicateDiagnostic,
      matching: find.byType(Padding),
    );
    expect(diagnosticRowPadding, findsWidgets);
    expect(
      tester.widget<Padding>(diagnosticRowPadding.first).padding,
      const EdgeInsets.only(bottom: AppSpacing.xxs),
    );
    final nextDiagnosticRowPadding = find.ancestor(
      of: missingDiagnostic,
      matching: find.byType(Padding),
    );
    expect(
      tester.widget<Padding>(nextDiagnosticRowPadding.first).padding,
      const EdgeInsets.only(bottom: AppSpacing.xxs),
    );

    for (final action in [
      find.text('Reset view'),
      find.text('Retry preview'),
      find.text('Replace GLB'),
    ]) {
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(milliseconds: 200));

    expect(resetCount, 1);
    expect(retryCount, 1);
    expect(replaceCount, 1);
  });

  testWidgets('model inspector exposes Sketchfab display controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final node = CanvasNode(
      id: 'model-controls',
      type: NodeType.model3d,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: Model3DPayload(
        fileName: 'car.glb',
        artifactReference: 'varian-model3d://model-controls',
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 280, child: InspectorPanel()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'WIREFRAME (5)',
      'Single Sided',
      'VIEWPORT',
      '3D',
      '3D + 2D',
      '2D',
      'Transparent background',
      'RENDER (1)',
      'Final Render',
      'No Post-Processing',
      'MATERIAL CHANNELS (2)',
      'Base Color',
      'Metalness',
      'Roughness',
      'Normal Map',
      'AO map',
      'Cavity',
      'Opacity',
      'Specular F0',
      'Clear Coat',
      'Clear Coat Roughness',
      'Clear Coat Normal Map',
      'GEOMETRY (3)',
      'Matcap',
      'Matcap+Surface',
      'Wireframe',
      'Vertex Normals',
      'UV (4)',
      'UV Checker',
    ]) {
      expect(
        find.text(label),
        label == 'Opacity' ? findsWidgets : findsOneWidget,
        reason: label,
      );
    }

    Future<void> reveal(Finder finder) async {
      final listView = find.byType(ListView).last;
      for (
        var attempt = 0;
        attempt < 20 && finder.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        final targetBounds = tester.getRect(finder);
        final viewportBounds = tester.getRect(listView);
        final dragDirection = targetBounds.center.dy > viewportBounds.bottom
            ? -1.0
            : 1.0;
        await tester.drag(listView, Offset(0, dragDirection * 220));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder.hitTestable(), findsOneWidget);
    }

    Future<void> tapLabel(String label) async {
      final finder = find.text(label).last;
      await reveal(finder);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 150));
    }

    await tapLabel('3D + 2D');
    await tapLabel('No Post-Processing');
    var updated =
        container.read(documentNodesProvider).single.payload as Model3DPayload;
    expect(
      updated.inspectorSelection,
      Model3DInspectorSelection.noPostProcessing,
    );
    expect(updated.renderMode, Model3DRenderMode.noPostProcessing);
    expect(updated.materialChannel, Model3DMaterialChannel.baseColor);
    expect(updated.geometryMode, Model3DGeometryMode.none);
    expect(updated.uvChecker, isFalse);

    await tapLabel('Metalness');
    updated =
        container.read(documentNodesProvider).single.payload as Model3DPayload;
    expect(updated.inspectorSelection, Model3DInspectorSelection.metalness);
    expect(updated.renderMode, Model3DRenderMode.finalRender);
    expect(updated.materialChannel, Model3DMaterialChannel.metalness);
    expect(updated.geometryMode, Model3DGeometryMode.none);
    expect(updated.uvChecker, isFalse);

    await tapLabel('Vertex Normals');
    updated =
        container.read(documentNodesProvider).single.payload as Model3DPayload;
    expect(updated.inspectorSelection, Model3DInspectorSelection.vertexNormals);
    expect(updated.renderMode, Model3DRenderMode.finalRender);
    expect(updated.materialChannel, Model3DMaterialChannel.baseColor);
    expect(updated.geometryMode, Model3DGeometryMode.vertexNormals);
    expect(updated.uvChecker, isFalse);

    await tapLabel('Wireframe');
    updated =
        container.read(documentNodesProvider).single.payload as Model3DPayload;
    expect(updated.inspectorSelection, Model3DInspectorSelection.wireframe);
    expect(updated.geometryMode, Model3DGeometryMode.wireframe);
    expect(updated.uvChecker, isFalse);

    final disableWireframe = find.bySemanticsLabel('Disable wireframe');
    await reveal(disableWireframe);
    await tester.tap(disableWireframe);
    await tester.pump(const Duration(milliseconds: 150));
    updated =
        container.read(documentNodesProvider).single.payload as Model3DPayload;
    expect(updated.inspectorSelection, Model3DInspectorSelection.finalRender);
    expect(updated.geometryMode, Model3DGeometryMode.none);

    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pump();
    await tapLabel('UV Checker');

    final transparentSwitch = find.bySemanticsLabel('Transparent background');
    await tester.ensureVisible(transparentSwitch);
    await tester.pump();
    await tester.tap(transparentSwitch);
    await tester.pump(const Duration(milliseconds: 150));

    updated =
        container.read(documentNodesProvider).single.payload as Model3DPayload;
    expect(updated.viewportMode, Model3DViewportMode.threeDAndTwoD);
    expect(updated.inspectorSelection, Model3DInspectorSelection.uvChecker);
    expect(updated.renderMode, Model3DRenderMode.finalRender);
    expect(updated.materialChannel, Model3DMaterialChannel.baseColor);
    expect(updated.geometryMode, Model3DGeometryMode.none);
    expect(updated.uvChecker, isTrue);
    expect(updated.transparentBackground, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board inspector controls stay within the panel width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final payloads = <NodePayload>[
      TodoListPayload(
        title: 'Design Review Checklist',
        items: [
          TodoItem(id: 'todo-1', text: 'Color contrast check', isDone: true),
          TodoItem(id: 'todo-2', text: 'Typography hierarchy', isDone: true),
          TodoItem(id: 'todo-3', text: 'QA and release'),
        ],
      ),
      ColumnPayload(
        headerTitle: 'Sprint Backlog',
        wipLimit: 3,
        cards: [
          const ColumnCardItem(
            id: 'card-1',
            title: 'Implement Canvas',
            isDone: true,
          ),
          const ColumnCardItem(id: 'card-2', title: 'Add Color Palette'),
          const ColumnCardItem(id: 'card-3', title: 'QA & Release'),
        ],
      ),
    ];

    for (final payload in payloads) {
      final node = CanvasNode(
        id: 'board-node',
        type: payload is TodoListPayload
            ? NodeType.todoList
            : NodeType.columnContainer,
        x: 0,
        y: 0,
        width: 120,
        height: 80,
        payload: payload,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(documentNodesProvider.notifier).setNodes([node]);
      container.read(selectionProvider.notifier).select(node.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: AppThemeScope(
              data: AppTheme.darkTheme,
              child: const InspectorPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      if (payload is ColumnPayload) {
        final stats = find.byKey(const ValueKey('inspector-column-stats'));
        final statsRect = tester.getRect(stats);
        final summaryRow = find
            .descendant(of: stats, matching: find.byType(Row))
            .first;
        final summaryRect = tester.getRect(summaryRow);
        expect(
          summaryRect.left - statsRect.left,
          AppBorder.thin + AppSpacing.sm,
        );
        expect(summaryRect.top - statsRect.top, AppBorder.thin + AppSpacing.sm);
        expect(find.text('Sprint Backlog'), findsOneWidget);
        final statsWrap = find.descendant(
          of: stats,
          matching: find.byType(Wrap),
        );
        final statsWrapWidget = tester.widget<Wrap>(statsWrap);
        expect(statsWrapWidget.spacing, AppSpacing.sm);
        expect(statsWrapWidget.runSpacing, AppSpacing.xs + AppSpacing.xxs);
        expect(find.text('Cards: 3 / WIP 3'), findsOneWidget);
        expect(find.text('Done: 1'), findsOneWidget);

        final statsRows = find.descendant(
          of: stats,
          matching: find.byType(Row),
        );
        final wipRowRect = tester.getRect(statsRows.at(1));
        final collapseRowRect = tester.getRect(statsRows.at(2));
        expect(collapseRowRect.left - wipRowRect.right, AppSpacing.sm);

        final wipGap = find.byKey(const ValueKey('inspector-column-wip-gap'));
        final wipLimit = find.byKey(const ValueKey('wip_limit_board-node'));
        expect(tester.getRect(wipGap).width, AppSpacing.xs);
        expect(tester.getRect(wipLimit).left - tester.getRect(wipGap).right, 0);
        expect(
          tester
              .widget<UiSwitch>(
                find.byKey(const ValueKey('inspector-column-collapse')),
              )
              .value,
          isFalse,
        );
        final cardControlGap = find.byKey(
          const ValueKey('inspector-column-card-control-gap-card-1'),
        );
        expect(tester.getRect(cardControlGap).width, AppSpacing.xs);

        final cardFinder = find.byKey(const ValueKey('column_card_card-1'));
        final cardRect = tester.getRect(cardFinder);
        final firstCardRow = find
            .descendant(of: cardFinder, matching: find.byType(Row))
            .first;
        final firstCardRowRect = tester.getRect(firstCardRow);
        expect(
          firstCardRowRect.left - cardRect.left,
          AppBorder.thin + AppSpacing.xs + AppSpacing.xxs,
        );
        expect(
          firstCardRowRect.top - cardRect.top,
          AppBorder.thin + AppSpacing.xs + AppSpacing.xxs,
        );
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const ValueKey('card_title_card-1')),
                  matching: find.byType(TextField),
                ),
              )
              .controller!
              .text,
          'Implement Canvas',
        );
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: wipLimit, matching: find.byType(TextField)),
              )
              .controller!
              .text,
          '3',
        );
      }
    }
  });

  testWidgets('color swatch is reachable and opens with keyboard activation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final node = CanvasNode(
      id: 'keyboard-color-node',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var focused = false;
    for (var index = 0; index < 80 && !focused; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      focused =
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<UiButton>()
              ?.semanticsLabel ==
          'Pick Fill Color';
    }
    expect(focused, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(InspectorColorPickerArea), findsOneWidget);
  });

  testWidgets('custom color picker dialog renders and stays bounded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final node = CanvasNode(
      id: 'color-node',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Pick Fill Color'));
    await tester.pumpAndSettle();

    expect(find.byType(InspectorColorPickerArea), findsOneWidget);
    expect(find.byType(InspectorColorPickerSlider), findsNWidgets(2));
    expect(find.text('RGB'), findsOneWidget);
    expect(find.text('HSV'), findsOneWidget);
    expect(find.text('HEX'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(InspectorColorPickerArea)).right,
      lessThanOrEqualTo(1024),
    );
  });

  testWidgets('color picker HEX input ignores incomplete colors', (
    tester,
  ) async {
    final node = CanvasNode(
      id: 'color-node',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Pick Fill Color'));
    await tester.pumpAndSettle();

    final hexField = find.byKey(const ValueKey('color-picker-hex'));
    await tester.enterText(hexField, '#00ff00');
    await tester.pump();
    expect(
      (container.read(documentNodesProvider).single.payload as ShapePayload)
          .fill,
      const Color(0xFF00FF00),
    );

    await tester.enterText(hexField, '#12');
    await tester.pump();
    expect(
      (container.read(documentNodesProvider).single.payload as ShapePayload)
          .fill,
      const Color(0xFF00FF00),
    );
    expect(find.text('Use 3, 6, or 8 hexadecimal digits.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('color picker RGB and HSV fields update color', (tester) async {
    final node = CanvasNode(
      id: 'color-node',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Pick Fill Color'));
    await tester.pumpAndSettle();

    Future<void> enterChannel(String channel, String value) async {
      await tester.enterText(
        find.byKey(ValueKey('color-picker-$channel')),
        value,
      );
      await tester.pump();
    }

    await enterChannel('r', '255');
    await enterChannel('g', '128');
    await enterChannel('b', '64');
    var color =
        (container.read(documentNodesProvider).single.payload as ShapePayload)
            .fill;
    expect(color.r, closeTo(1, 0.01));
    expect(color.g, closeTo(128 / 255, 0.01));
    expect(color.b, closeTo(64 / 255, 0.01));

    await enterChannel('h', '120');
    await enterChannel('s', '50');
    await enterChannel('v', '75');
    color =
        (container.read(documentNodesProvider).single.payload as ShapePayload)
            .fill;
    final hsv = HSVColor.fromColor(color);
    expect(hsv.hue, closeTo(120, 1));
    expect(hsv.saturation, closeTo(0.5, 0.01));
    expect(hsv.value, closeTo(0.75, 0.01));

    await enterChannel('s', '120');
    color =
        (container.read(documentNodesProvider).single.payload as ShapePayload)
            .fill;
    expect(HSVColor.fromColor(color).saturation, 1);
    expect(
      tester
          .widget<UiTextField>(find.byKey(const ValueKey('color-picker-s')))
          .controller!
          .text,
      '100',
    );

    await tester.enterText(
      find.byKey(const ValueKey('color-picker-hex')),
      '#FF0000',
    );
    await tester.pump();
    expect(
      tester
          .widget<UiTextField>(find.byKey(const ValueKey('color-picker-r')))
          .controller!
          .text,
      '255',
    );
    expect(
      tester
          .widget<UiTextField>(find.byKey(const ValueKey('color-picker-g')))
          .controller!
          .text,
      '0',
    );
    expect(
      tester
          .widget<UiTextField>(find.byKey(const ValueKey('color-picker-h')))
          .controller!
          .text,
      '0',
    );
  });

  testWidgets('color picker area keeps drag gestures alive', (tester) async {
    final node = CanvasNode(
      id: 'color-node',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final initialColor = (node.payload as ShapePayload).fill;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Pick Fill Color'));
    await tester.pumpAndSettle();

    final area = tester.getRect(find.byType(InspectorColorPickerArea));
    final gesture = await tester.startGesture(
      Offset(area.left + area.width * 0.2, area.top + area.height * 0.2),
    );
    await tester.pump();
    final firstColor =
        (container.read(documentNodesProvider).single.payload as ShapePayload)
            .fill;

    await gesture.moveTo(
      Offset(area.left + area.width * 0.8, area.top + area.height * 0.8),
    );
    await tester.pump();
    final secondColor =
        (container.read(documentNodesProvider).single.payload as ShapePayload)
            .fill;
    await gesture.up();

    expect(firstColor, isNot(initialColor));
    expect(secondColor, isNot(firstColor));
    expect(tester.takeException(), isNull);
  });

  testWidgets('color picker dialog fits a 320px viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final node = CanvasNode(
      id: 'color-node',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
      payload: ShapePayload(),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final colorAction = find.bySemanticsLabel('Pick Fill Color');
    await tester.ensureVisible(colorAction);
    await tester.pumpAndSettle();
    await tester.tap(colorAction);
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('InspectorPanel applies tidy alignment to multiple nodes', (
    tester,
  ) async {
    final nodes = [
      CanvasNode(
        id: 'node-1',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 120,
        height: 80,
        payload: ShapePayload(),
      ),
      CanvasNode(
        id: 'node-2',
        type: NodeType.rectangle,
        x: 240,
        y: 100,
        width: 80,
        height: 60,
        payload: ShapePayload(),
      ),
    ];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes(nodes);
    container
        .read(selectionProvider.notifier)
        .selectAll(nodes.map((node) => node.id).toList());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('Align Left'));
    await tester.pump(const Duration(milliseconds: 100));

    final aligned = container.read(documentNodesProvider);
    expect(aligned.map((node) => node.x), everyElement(0));
  });
  testWidgets('InspectorPanel reflows all alignment actions at narrow widths', (
    tester,
  ) async {
    const labels = [
      'Align Left',
      'Align Horizontal Center',
      'Align Right',
      'Align Top',
      'Align Vertical Middle',
      'Align Bottom',
    ];
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final width in [280.0, 320.0]) {
      final nodes = [
        CanvasNode(
          id: 'alignment-left',
          type: NodeType.rectangle,
          x: 0,
          y: 0,
          width: 120,
          height: 80,
          payload: ShapePayload(),
        ),
        CanvasNode(
          id: 'alignment-right',
          type: NodeType.rectangle,
          x: 240,
          y: 100,
          width: 80,
          height: 60,
          payload: ShapePayload(),
        ),
      ];
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(documentNodesProvider.notifier).setNodes(nodes);
      container
          .read(selectionProvider.notifier)
          .selectAll(nodes.map((node) => node.id).toList());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: AppThemeScope(
              data: AppTheme.darkTheme,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: InspectorPanel(width: width),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.byType(InspectorPanel));
      final compactActions = find.byKey(
        const ValueKey('inspector-alignment-actions-compact'),
      );
      final wideActions = find.byKey(
        const ValueKey('inspector-alignment-actions-wide'),
      );
      final alignmentActions = width == 280 ? compactActions : wideActions;
      expect(alignmentActions, findsOneWidget);
      final viewport = tester.getRect(
        find
            .ancestor(of: alignmentActions, matching: find.byType(ListView))
            .first,
      );
      for (final label in labels) {
        final action = find.bySemanticsLabel(label);
        expect(
          action,
          findsOneWidget,
          reason: 'missing $label at width $width',
        );
        expect(
          action.hitTestable(),
          findsOneWidget,
          reason: '$label is clipped or occluded at width $width',
        );
        final bounds = tester.getRect(action);
        final size = tester.getSize(action);
        expect(
          size.width,
          greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
        );
        expect(bounds.left, greaterThanOrEqualTo(panel.left));
        expect(bounds.right, lessThanOrEqualTo(panel.right));
        expect(bounds.top, greaterThanOrEqualTo(viewport.top));
        expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
      }

      await tester.tap(find.bySemanticsLabel('Align Left'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(documentNodesProvider).map((node) => node.x),
        everyElement(0),
      );
      await tester.tap(find.bySemanticsLabel('Align Top'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(documentNodesProvider).map((node) => node.y),
        everyElement(0),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'tidy board distribution actions retain target sizes at narrow widths',
    (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final width in [280.0, 320.0]) {
        final nodes = List.generate(
          3,
          (index) => CanvasNode(
            id: 'distribution-${width.toInt()}-$index',
            type: NodeType.rectangle,
            x: index * 120,
            y: index * 80,
            width: 80,
            height: 60,
            payload: ShapePayload(),
          ),
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(documentNodesProvider.notifier).setNodes(nodes);
        container
            .read(selectionProvider.notifier)
            .selectAll(nodes.map((node) => node.id).toList());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: width == 280
                        ? const TextScaler.linear(1.5)
                        : TextScaler.noScaling,
                  ),
                  child: AppThemeScope(
                    data: AppTheme.darkTheme,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: InspectorPanel(width: width),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final panel = tester.getRect(find.byType(InspectorPanel));
        for (final label in [
          'Distribute Horizontally',
          'Distribute Vertically',
        ]) {
          final action = find.bySemanticsLabel(label);
          expect(action, findsOneWidget);
          expect(action.hitTestable(), findsOneWidget);
          final size = tester.getSize(action);
          final bounds = tester.getRect(action);
          final viewport = tester.getRect(
            find.ancestor(of: action, matching: find.byType(ListView)).first,
          );
          expect(
            size.width,
            greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
          );
          expect(
            size.height,
            greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
          );
          expect(bounds.left, greaterThanOrEqualTo(panel.left));
          expect(bounds.right, lessThanOrEqualTo(panel.right));
          expect(bounds.top, greaterThanOrEqualTo(viewport.top));
          expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(
            tester
                .widget<UiButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is UiButton && widget.semanticsLabel == label,
                  ),
                )
                .onPressed,
            isNotNull,
          );
        }

        container
            .read(selectionProvider.notifier)
            .selectAll(nodes.take(2).map((node) => node.id).toList());
        await tester.pumpAndSettle();
        for (final label in [
          'Distribute Horizontally',
          'Distribute Vertically',
        ]) {
          final action = find.bySemanticsLabel(label);
          expect(action, findsOneWidget);
          expect(action.hitTestable(), findsOneWidget);
          final size = tester.getSize(action);
          final bounds = tester.getRect(action);
          final viewport = tester.getRect(
            find.ancestor(of: action, matching: find.byType(ListView)).first,
          );
          expect(
            size.width,
            greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
          );
          expect(
            size.height,
            greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
          );
          expect(bounds.left, greaterThanOrEqualTo(panel.left));
          expect(bounds.right, lessThanOrEqualTo(panel.right));
          expect(bounds.top, greaterThanOrEqualTo(viewport.top));
          expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(
            tester
                .widget<UiButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is UiButton && widget.semanticsLabel == label,
                  ),
                )
                .onPressed,
            isNull,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'frame-only auto layout action retains target size at compact widths',
    (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final width in [280.0, 320.0]) {
        final frame = CanvasNode(
          id: 'auto-layout-frame-${width.toInt()}',
          type: NodeType.frame,
          x: 0,
          y: 0,
          width: 360,
          height: 240,
          payload: FramePayload(
            layoutDirection: AutoLayoutDirection.horizontal,
          ),
        );
        final child = CanvasNode(
          id: 'auto-layout-child-${width.toInt()}',
          type: NodeType.rectangle,
          x: 0,
          y: 0,
          width: 80,
          height: 60,
          parentId: frame.id,
          payload: ShapePayload(),
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(documentNodesProvider.notifier).setNodes([frame, child]);
        container.read(selectionProvider.notifier).select(frame.id);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: AppThemeScope(
                data: AppTheme.darkTheme,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: InspectorPanel(width: width),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final action = find.bySemanticsLabel(
          'Apply Auto Layout to frame children',
        );
        expect(action, findsOneWidget);
        expect(action.hitTestable(), findsOneWidget);
        final panel = tester.getRect(find.byType(InspectorPanel));
        final bounds = tester.getRect(action);
        final viewport = tester.getRect(
          find.ancestor(of: action, matching: find.byType(ListView)).first,
        );
        final size = tester.getSize(action);
        expect(
          size.width,
          greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
        );
        expect(bounds.left, greaterThanOrEqualTo(panel.left));
        expect(bounds.right, lessThanOrEqualTo(panel.right));
        expect(bounds.top, greaterThanOrEqualTo(viewport.top));
        expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(
          tester
              .widget<UiButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is UiButton &&
                      widget.semanticsLabel ==
                          'Apply Auto Layout to frame children',
                ),
              )
              .onPressed,
          isNotNull,
        );

        await tester.tap(action);
        await tester.pumpAndSettle();
        final updatedNodes = container.read(documentNodesProvider);
        final updatedChild = updatedNodes.firstWhere(
          (node) => node.id == child.id,
        );
        expect(updatedChild.x, frame.x + 16);
        expect(updatedChild.y, frame.y + 16);

        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('InspectorPanel rotates native diagram shapes', (tester) async {
    final node = CanvasNode(
      id: 'diagram-rotate',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 140,
      height: 90,
      payload: ShapePayload(diagramShapeId: 'hexagon'),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([node]);
    container.read(selectionProvider.notifier).select(node.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rotate 90°'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(documentNodesProvider).single.rotation,
      closeTo(math.pi / 2, 0.0001),
    );

    final rotationField = find.byWidgetPredicate(
      (widget) =>
          widget is UiTextField &&
          (widget.label?.startsWith('Rotation') ?? false),
    );
    expect(rotationField, findsOneWidget);
    await tester.ensureVisible(rotationField);
    await tester.enterText(rotationField, '45');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Image inspector exposes non-destructive editing controls', (
    tester,
  ) async {
    final image = CanvasNode(
      id: 'image-editing-inspector',
      type: NodeType.image,
      x: 0,
      y: 0,
      width: 320,
      height: 220,
      payload: ImagePayload(
        assetId: 'hero.png',
        cropX: 0.1,
        cropY: 0.1,
        cropWidth: 0.8,
        cropHeight: 0.8,
        adjustments: const [
          ImageAdjustment(
            id: 'existing-saturation',
            type: ImageAdjustmentType.saturation,
            amount: 1.2,
          ),
        ],
        backgroundMask: const ImageMask(
          assetId: 'mask.png',
          mode: ImageMaskMode.luminance,
          opacity: 0.75,
        ),
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(documentNodesProvider.notifier).setNodes([image]);
    container.read(selectionProvider.notifier).select(image.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppThemeScope(
            data: AppTheme.darkTheme,
            child: const InspectorPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sourceBadge = tester.widget<Container>(
      find.byKey(const ValueKey('inspector-image-source-badge')),
    );
    expect(
      sourceBadge.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs + AppSpacing.xxs,
        vertical: AppSpacing.xxs,
      ),
    );
    expect(find.text('IMAGE ASSET'), findsOneWidget);
    expect(find.text('ADJUSTMENT STACK'), findsOneWidget);
    expect(find.text('BACKGROUND MASK'), findsOneWidget);
    expect(find.text('Mask mode'), findsOneWidget);

    final addExposure = find.text('+ Exposure');
    await tester.ensureVisible(addExposure);
    await tester.pumpAndSettle();
    await tester.tap(addExposure);
    await tester.pump(const Duration(milliseconds: 200));

    final stored = container.read(documentNodesProvider).single;
    final payload = stored.payload as ImagePayload;
    expect(payload.cropX, 0.1);
    expect(payload.adjustments.map((item) => item.type), [
      ImageAdjustmentType.saturation,
      ImageAdjustmentType.exposure,
    ]);
    expect(payload.backgroundMask?.mode, ImageMaskMode.luminance);
    expect(tester.takeException(), isNull);
  });

  group('accessibility', () {
    testWidgets('color picker controls expose clear semantics labels', (
      tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();

      final node = CanvasNode(
        id: 'color-node',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 120,
        height: 80,
        payload: ShapePayload(),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(documentNodesProvider.notifier).setNodes([node]);
      container.read(selectionProvider.notifier).select(node.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: AppThemeScope(
              data: AppTheme.darkTheme,
              child: const InspectorPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Pick Fill Color'));
      await tester.pumpAndSettle();

      for (final label in [
        'Color area',
        'Hue',
        'Alpha',
        'HEX color input',
        'Done',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }

      final beforeIncrease =
          (container.read(documentNodesProvider).single.payload as ShapePayload)
              .fill;
      tester.semantics.performAction(
        find.semantics.byLabel('Color area'),
        SemanticsAction.increase,
      );
      await tester.pump();
      final afterIncrease =
          (container.read(documentNodesProvider).single.payload as ShapePayload)
              .fill;
      expect(afterIncrease, isNot(beforeIncrease));

      semanticsHandle.dispose();
      expect(tester.takeException(), isNull);
    });
  });
}
