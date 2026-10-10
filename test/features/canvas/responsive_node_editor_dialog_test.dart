import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/table_matrix_editor_modal.dart';
import 'package:varian/features/canvas/presentation/widgets/todo_list_editor_modal.dart';

import '../../test_app.dart';

void main() {
  final tableNode = CanvasNode(
    id: 'table',
    type: NodeType.tableGrid,
    x: 0,
    y: 0,
    width: 800,
    height: 400,
    payload: TablePayload(),
  );
  final invalidTableNode = CanvasNode(
    id: 'invalid-table',
    type: NodeType.tableGrid,
    x: 0,
    y: 0,
    width: 800,
    height: 400,
    payload: TablePayload(
      columns: const ['Amount'],
      rows: const [
        <String>['not-a-number'],
      ],
      columnTypes: const [TableCellType.number],
    ),
  );
  final todoNode = CanvasNode(
    id: 'todo',
    type: NodeType.todoList,
    x: 0,
    y: 0,
    width: 400,
    height: 400,
    payload: TodoListPayload(
      items: [
        TodoItem(
          id: 'metadata-task',
          text: 'Keep metadata',
          dueDate: 'Friday',
          assignee: 'Ada',
        ),
      ],
    ),
  );

  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('checkbox table cell keeps its full action in reach', (
    tester,
  ) async {
    await setViewport(tester, const Size(640, 720));
    final checkboxTable = tableNode.copyWith(
      payload: TablePayload(
        columns: const ['Done'],
        rows: const [
          <String>['false'],
        ],
        columnTypes: const [TableCellType.checkbox],
      ),
    );
    CanvasNode? updatedTable;
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => TableMatrixEditorModal.show(
                context,
                node: checkboxTable,
                onUpdate: (node) => updatedTable = node,
              ),
              child: const Text('Open checkbox table'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open checkbox table'));
    await tester.pumpAndSettle();

    final checkbox = find.bySemanticsLabel('Toggle row 1');
    final checkboxSize = tester.getSize(checkbox);
    expect(
      checkboxSize.width,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(
      checkboxSize.height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    await tester.tapAt(
      tester.getRect(checkbox).bottomRight - const Offset(2, 2),
    );
    await tester.pump();
    expect((updatedTable!.payload as TablePayload).rows, [
      ['true'],
    ]);
    final dialogBounds = tester.getRect(find.byType(Dialog));
    final saveButtonBounds = tester.getRect(find.text('Save & Close'));
    expect(saveButtonBounds.left, greaterThanOrEqualTo(dialogBounds.left));
    expect(saveButtonBounds.right, lessThanOrEqualTo(dialogBounds.right));
    final tableException = tester.takeException();
    expect(tableException, isNull);
  });

  testWidgets(
    'table editor actions fit and remain available on compact screens',
    (tester) async {
      await setViewport(tester, const Size(390, 480));
      CanvasNode? updatedTable;
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () => TableMatrixEditorModal.show(
                  context,
                  node: tableNode,
                  onUpdate: (node) => updatedTable = node,
                ),
                child: const Text('Open table'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open table'));
      await tester.pumpAndSettle();
      final tableDialogBounds = tester.getRect(find.byType(Dialog));
      expect(tableDialogBounds.left, greaterThanOrEqualTo(0));
      expect(tableDialogBounds.right, lessThanOrEqualTo(390));
      expect(tableDialogBounds.top, greaterThanOrEqualTo(0));
      expect(tableDialogBounds.bottom, lessThanOrEqualTo(480));
      for (final action in [
        find.text('Import CSV'),
        find.text('Add Row'),
        find.text('Save & Close'),
      ]) {
        final actionBounds = tester.getRect(action);
        expect(actionBounds.left, greaterThanOrEqualTo(tableDialogBounds.left));
        expect(actionBounds.right, lessThanOrEqualTo(tableDialogBounds.right));
        expect(actionBounds.top, greaterThanOrEqualTo(tableDialogBounds.top));
        expect(
          actionBounds.bottom,
          lessThanOrEqualTo(tableDialogBounds.bottom),
        );
      }
      final viewportFrame = tester.widget<Container>(
        find.byKey(const ValueKey('table-editor-viewport-frame')),
      );
      expect(
        (viewportFrame.decoration! as BoxDecoration).border!.top.width,
        AppBorder.thin,
      );

      expect(find.text('Import CSV'), findsOneWidget);
      expect(find.text('Copy CSV'), findsOneWidget);
      expect(find.text('Add Row'), findsOneWidget);
      expect(find.text('Add Column'), findsOneWidget);
      expect(find.text('Summary Row:'), findsOneWidget);
      expect(find.text('Save & Close'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Import CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Import CSV Data'), findsOneWidget);
      await tester.enterText(
        find.byType(UiTextField).last,
        'Name,State\nBoard,Ready',
      );
      await tester.tap(find.text('Import CSV').last);
      await tester.pumpAndSettle();
      final updatedPayload = updatedTable!.payload as TablePayload;
      expect(updatedPayload.columns, ['Name', 'State']);
      expect(updatedPayload.rows, [
        ['Board', 'Ready'],
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid table values retain a thin validation border', (
    tester,
  ) async {
    await setViewport(tester, const Size(390, 480));
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => TableMatrixEditorModal.show(
                context,
                node: invalidTableNode,
                onUpdate: (_) {},
              ),
              child: const Text('Open invalid table'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open invalid table'));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Invalid format for this column type'),
      findsOneWidget,
    );
    final invalidCell = tester.widget<Container>(
      find
          .ancestor(
            of: find.byTooltip('Invalid format for this column type'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).border != null,
            ),
          )
          .first,
    );
    expect(
      (invalidCell.decoration! as BoxDecoration).border!.top.width,
      AppBorder.thin,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'checklist editor actions fit and remain available on compact screens',
    (tester) async {
      await setViewport(tester, const Size(390, 480));
      CanvasNode? updatedTodo;
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () => TodoListEditorModal.show(
                  context,
                  node: todoNode,
                  onUpdate: (node) => updatedTodo = node,
                ),
                child: const Text('Open checklist'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open checklist'));
      await tester.pumpAndSettle();
      final todoDialogBounds = tester.getRect(find.byType(Dialog));
      expect(todoDialogBounds.left, greaterThanOrEqualTo(0));
      expect(todoDialogBounds.right, lessThanOrEqualTo(390));
      expect(todoDialogBounds.top, greaterThanOrEqualTo(0));
      expect(todoDialogBounds.bottom, lessThanOrEqualTo(480));
      for (final action in [
        find.byTooltip('Batch Paste Tasks'),
        find.text('Done'),
      ]) {
        final actionBounds = tester.getRect(action);
        expect(actionBounds.left, greaterThanOrEqualTo(todoDialogBounds.left));
        expect(actionBounds.right, lessThanOrEqualTo(todoDialogBounds.right));
        expect(actionBounds.top, greaterThanOrEqualTo(todoDialogBounds.top));
        expect(actionBounds.bottom, lessThanOrEqualTo(todoDialogBounds.bottom));
      }

      expect(find.byTooltip('Batch Paste Tasks'), findsOneWidget);
      expect(find.text('Progress: 0 of 1 completed'), findsOneWidget);
      expect(find.text('Add a new task and press Enter...'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      for (final key in [
        'todo-editor-progress-frame',
        'todo-editor-add-item-frame',
        'todo-editor-metadata-metadata-task-due',
        'todo-editor-metadata-metadata-task-assignee',
      ]) {
        final frame = tester.widget<Container>(find.byKey(ValueKey(key)));
        expect(
          (frame.decoration! as BoxDecoration).border!.top.width,
          AppBorder.thin,
          reason: key,
        );
      }
      await tester.tap(find.byTooltip('Batch Paste Tasks'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(UiTextField).last,
        'First task\nSecond task',
      );
      await tester.tap(find.text('Add All Tasks'));
      await tester.pumpAndSettle();
      final updatedPayload = updatedTodo!.payload as TodoListPayload;
      expect(updatedPayload.items.map((item) => item.text), [
        'Keep metadata',
        'First task',
        'Second task',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
