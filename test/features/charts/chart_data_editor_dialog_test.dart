import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/features/charts/presentation/chart_data_editor_dialog.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import '../../test_app.dart';

void main() {
  testWidgets('edits chart cells and imports pasted CSV data', (tester) async {
    ChartPayload? saved;
    final payload = ChartPayload(
      title: 'Revenue',
      categories: const ['A', 'B'],
      series: [
        ChartSeries(name: 'Sales', values: const [2, 4]),
        ChartSeries(name: 'Cost', values: const [1, 3]),
      ],
    );

    await tester.pumpWidget(
      testApp(
        ChartDataEditorDialog(
          payload: payload,
          onSave: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('chart-data-paste')),
      'Quarter,Sales,Cost\nQ1,10,7\nQ2,14,9',
    );
    await tester.tap(find.byKey(const ValueKey('chart-data-apply-paste')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chart-data-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.categories, ['Q1', 'Q2']);
    expect(saved!.series.map((series) => series.name), ['Sales', 'Cost']);
    expect(saved!.series.first.values, [10, 14]);
    expect(saved!.series.last.values, [7, 9]);
  });

  testWidgets('imports JSON rows into chart series', (tester) async {
    ChartPayload? saved;

    await tester.pumpWidget(
      testApp(
        ChartDataEditorDialog(
          payload: ChartPayload(),
          onSave: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('chart-data-paste')),
      '[{"category":"Q1","Sales":10,"Cost":7},{"category":"Q2","Sales":14,"Cost":9}]',
    );
    await tester.tap(find.byKey(const ValueKey('chart-data-apply-json')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chart-data-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.categories, ['Q1', 'Q2']);
    expect(saved!.series.map((series) => series.name), ['Sales', 'Cost']);
    expect(saved!.series.first.values, [10, 14]);
    expect(saved!.series.last.values, [7, 9]);
  });

  testWidgets('imports a persisted chart payload from JSON', (tester) async {
    ChartPayload? saved;

    await tester.pumpWidget(
      testApp(
        ChartDataEditorDialog(
          payload: ChartPayload(),
          onSave: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('chart-data-paste')),
      '{"categories":["A","B"],"series":[{"name":"Sales","values":[2,4]}]}',
    );
    await tester.tap(find.byKey(const ValueKey('chart-data-apply-json')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chart-data-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.categories, ['A', 'B']);
    expect(saved!.series.single.name, 'Sales');
    expect(saved!.series.single.values, [2, 4]);
  });

  testWidgets('edits individual cells and manages rows and series', (
    tester,
  ) async {
    ChartPayload? saved;
    final payload = ChartPayload(
      categories: const ['A'],
      series: [
        ChartSeries(name: 'Sales', values: const [2]),
      ],
    );

    await tester.pumpWidget(
      testApp(
        ChartDataEditorDialog(
          payload: payload,
          onSave: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('chart-data-category-0')),
      'Q1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('chart-data-value-0-0')),
      '8',
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -480));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chart-data-add-row')));
    await tester.tap(find.byKey(const ValueKey('chart-data-add-series')));
    await tester.tap(find.byKey(const ValueKey('chart-data-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.categories, ['Q1', 'Category 2']);
    expect(saved!.series, hasLength(2));
    expect(saved!.series.first.values, [8, 0]);
    expect(saved!.series.last.values, [0, 0]);
  });

  testWidgets('shows an error for invalid JSON input', (tester) async {
    await tester.pumpWidget(
      testApp(ChartDataEditorDialog(payload: ChartPayload(), onSave: (_) {})),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('chart-data-paste')),
      '{invalid',
    );
    await tester.tap(find.byKey(const ValueKey('chart-data-apply-json')));
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const ValueKey('chart-data-import-error')),
      findsOneWidget,
    );
    expect(find.text('Invalid JSON.'), findsOneWidget);
  });
  testWidgets(
    'labels chart data cells and reflows actions on compact screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        testApp(
          ChartDataEditorDialog(
            payload: ChartPayload(
              categories: const ['Q1'],
              series: [
                ChartSeries(name: 'Revenue', values: const [12]),
              ],
            ),
            onSave: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
      expect(dialog.constraints!.maxWidth, 296);
      final dialogRect = tester.getRect(find.byType(Dialog));
      expect(dialogRect.left, greaterThanOrEqualTo(0));
      expect(dialogRect.right, lessThanOrEqualTo(320));
      expect(dialogRect.top, greaterThanOrEqualTo(0));
      expect(dialogRect.bottom, lessThanOrEqualTo(720));

      for (final label in [
        'Series 1 name',
        'Category 1',
        'Revenue for Q1 (row 1)',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Category 1'))
            .flagsCollection
            .isTextField,
        isTrue,
      );
      final addSeries = find.byKey(const ValueKey('chart-data-add-series'));
      await tester.scrollUntilVisible(
        addSeries,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      final addSeriesRect = tester.getRect(addSeries);
      expect(addSeriesRect.left, greaterThanOrEqualTo(dialogRect.left));
      expect(addSeriesRect.right, lessThanOrEqualTo(dialogRect.right));
      expect(addSeriesRect.top, greaterThanOrEqualTo(dialogRect.top));
      expect(addSeriesRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
      final header = tester.widget<Container>(
        find.byKey(const ValueKey('chart-data-header-surface')),
      );
      final footer = tester.widget<Container>(
        find.byKey(const ValueKey('chart-data-footer-surface')),
      );
      final headerBorder =
          (header.decoration! as BoxDecoration).border! as Border;
      final footerBorder =
          (footer.decoration! as BoxDecoration).border! as Border;
      expect(headerBorder.bottom.width, AppBorder.thin);
      expect(headerBorder.bottom.color, AppTokens.dark.panelBorder);
      expect(footerBorder.top.width, AppBorder.thin);
      expect(footerBorder.top.color, AppTokens.dark.panelBorder);

      final compactDialog = tester.getRect(find.byType(Dialog));
      for (final finder in [
        find.byKey(const ValueKey('chart-data-header-surface')),
        find.byKey(const ValueKey('chart-data-footer-surface')),
        find.text('Cancel'),
        find.byKey(const ValueKey('chart-data-save')),
      ]) {
        final bounds = tester.getRect(finder);
        expect(bounds.left, greaterThanOrEqualTo(compactDialog.left));
        expect(bounds.top, greaterThanOrEqualTo(compactDialog.top));
        expect(bounds.right, lessThanOrEqualTo(compactDialog.right));
        expect(bounds.bottom, lessThanOrEqualTo(compactDialog.bottom));
      }
      expect(addSeries, findsOneWidget);
      final exception = tester.takeException();
      semantics.dispose();
      expect(exception, isNull);
    },
  );
  testWidgets(
    'short compact chart dialog scrolls data without hiding actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ChartPayload? saved;

      await tester.pumpWidget(
        testApp(
          ChartDataEditorDialog(
            payload: ChartPayload(
              categories: const ['Q1'],
              series: [
                ChartSeries(name: 'Revenue', values: const [12]),
              ],
            ),
            onSave: (value) => saved = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dialog = find.byType(Dialog);
      final dialogRect = tester.getRect(dialog);
      final header = find.byKey(const ValueKey('chart-data-header-surface'));
      final body = find.descendant(of: dialog, matching: find.byType(ListView));
      final footer = find.byKey(const ValueKey('chart-data-footer-surface'));
      final save = find.byKey(const ValueKey('chart-data-save'));
      expect(dialogRect.left, greaterThanOrEqualTo(0));
      expect(dialogRect.right, lessThanOrEqualTo(320));
      expect(dialogRect.top, greaterThanOrEqualTo(0));
      expect(dialogRect.bottom, lessThanOrEqualTo(480));
      expect(tester.getRect(header).top, greaterThanOrEqualTo(dialogRect.top));
      expect(
        tester.getRect(footer).bottom,
        lessThanOrEqualTo(dialogRect.bottom),
      );
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(dialogRect.bottom));
      expect(tester.getRect(body).height, greaterThan(0));

      final addRow = find.byKey(const ValueKey('chart-data-add-row'));
      final bodyScrollable = find
          .descendant(of: body, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(addRow, 100, scrollable: bodyScrollable);
      expect(
        tester.getRect(addRow).bottom,
        lessThanOrEqualTo(tester.getRect(body).bottom),
      );
      await tester.tap(addRow);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(saved?.categories, ['Q1', 'Category 2']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('wide chart editor keeps controls aligned in dialog bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        ChartDataEditorDialog(
          payload: ChartPayload(
            title: 'Wide fixture',
            categories: const ['Q1'],
            series: [
              ChartSeries(name: 'Revenue', values: const [12]),
            ],
          ),
          onSave: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.left, greaterThanOrEqualTo(0));
    expect(dialog.right, lessThanOrEqualTo(1280));
    expect(dialog.top, greaterThanOrEqualTo(0));
    expect(dialog.bottom, lessThanOrEqualTo(900));
    final title = tester.getRect(find.text('CHART DATA'));
    final close = tester.getRect(find.byTooltip('Close chart data editor'));
    expect(title.center.dy, close.center.dy);
    expect(close.right, lessThanOrEqualTo(dialog.right));

    final addRow = tester.getRect(
      find.byKey(const ValueKey('chart-data-add-row')),
    );
    final removeRow = tester.getRect(
      find.byKey(const ValueKey('chart-data-remove-row')),
    );
    final addSeries = tester.getRect(
      find.byKey(const ValueKey('chart-data-add-series')),
    );
    expect(addRow.center.dy, removeRow.center.dy);
    expect(removeRow.right, lessThanOrEqualTo(addSeries.left));
    final cancel = tester.getRect(find.text('Cancel'));
    final save = tester.getRect(find.byKey(const ValueKey('chart-data-save')));
    expect(cancel.center.dy, save.center.dy);
    expect(cancel.right, lessThanOrEqualTo(save.left));
    for (final action in [addRow, removeRow, addSeries, cancel, save]) {
      expect(action.left, greaterThanOrEqualTo(dialog.left));
      expect(action.right, lessThanOrEqualTo(dialog.right));
      expect(action.top, greaterThanOrEqualTo(dialog.top));
      expect(action.bottom, lessThanOrEqualTo(dialog.bottom));
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('uses one-pixel app borders around editor chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        ChartDataEditorDialog(
          payload: ChartPayload(
            categories: const ['Q1'],
            series: [
              ChartSeries(name: 'Revenue', values: const [12]),
            ],
          ),
          onSave: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final header = tester.widget<Container>(
      find.byKey(const ValueKey('chart-data-header-surface')),
    );
    final table = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('chart-data-table-surface')),
    );
    final footer = tester.widget<Container>(
      find.byKey(const ValueKey('chart-data-footer-surface')),
    );
    final headerBorder =
        (header.decoration! as BoxDecoration).border! as Border;
    final tableBorder = (table.decoration as BoxDecoration).border! as Border;
    final footerBorder =
        (footer.decoration! as BoxDecoration).border! as Border;

    expect(headerBorder.bottom.width, AppBorder.thin);
    expect(tableBorder.top.width, AppBorder.thin);
    expect(tableBorder.right.width, AppBorder.thin);
    expect(tableBorder.bottom.width, AppBorder.thin);
    expect(tableBorder.left.width, AppBorder.thin);
    expect(footerBorder.top.width, AppBorder.thin);
    expect(tester.takeException(), isNull);
  });
}
