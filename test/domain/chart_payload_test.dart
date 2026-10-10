import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';

void main() {
  group('ChartPayload', () {
    test('round-trips every supported chart type and data shape', () {
      for (final chartType in ChartType.values) {
        final payload = ChartPayload(
          title: 'Quarterly performance',
          chartType: chartType,
          categories: const ['Q1', 'Q2', 'Q3'],
          series: [
            ChartSeries(
              name: 'Revenue',
              values: const [12, 18, 15],
              points: [
                ChartPoint(x: 1, y: 12, label: 'Q1'),
                ChartPoint(x: 2, y: 18, label: 'Q2'),
              ],
              color: const Color(0xFFF97316),
            ),
            ChartSeries(
              name: 'Costs',
              values: const [8, 10, 9],
              color: const Color(0xFF38BDF8),
            ),
          ],
          barOrientation: ChartBarOrientation.horizontal,
          showLegend: false,
          showGrid: false,
          showAxes: true,
          showValues: true,
          showTooltips: false,
        );

        final restored = ChartPayload.fromJson(payload.toJson());

        expect(restored.chartType, chartType);
        expect(restored.title, payload.title);
        expect(restored.categories, payload.categories);
        expect(restored.series.length, 2);
        expect(restored.series.first.values, [12, 18, 15]);
        expect(restored.series.first.points.last.label, 'Q2');
        expect(restored.series.last.color, const Color(0xFF38BDF8));
        expect(restored.barOrientation, ChartBarOrientation.horizontal);
        expect(restored.showLegend, isFalse);
        expect(restored.showGrid, isFalse);
        expect(restored.showAxes, isTrue);
        expect(restored.showValues, isTrue);
        expect(restored.showTooltips, isFalse);
      }
    });

    test('persists API source metadata without replacing saved chart data', () {
      final payload = ChartPayload(
        dataSourceUrl: 'https://example.com/chart.json',
        dataRefreshRevision: 3,
        categories: const ['Saved'],
        series: [
          ChartSeries(values: const [42]),
        ],
      );

      final restored = ChartPayload.fromJson(payload.toJson());

      expect(restored.dataSourceUrl, payload.dataSourceUrl);
      expect(restored.dataRefreshRevision, 3);
      expect(restored.categories, ['Saved']);
      expect(restored.series.single.values, [42]);
      expect(payload.copyWith(clearDataSourceUrl: true).dataSourceUrl, isNull);
    });

    test('persists and resolves a table data source', () {
      final payload = ChartPayload(
        tableSourceNodeId: 'table-sales',
        tableCategoryColumn: 0,
      );
      final restored = ChartPayload.fromJson(payload.toJson());
      final table = TablePayload(
        columns: const ['Quarter', 'Revenue', 'Cost'],
        columnTypes: const [
          TableCellType.text,
          TableCellType.number,
          TableCellType.currency,
        ],
        rows: const [
          ['Q1', '10', '\$7'],
          ['Q2', '14', '\$9'],
        ],
      );

      final resolved = restored.resolvedFromTable(table);

      expect(restored.tableSourceNodeId, 'table-sales');
      expect(restored.tableCategoryColumn, 0);
      expect(resolved.categories, ['Q1', 'Q2']);
      expect(resolved.series.map((series) => series.name), ['Revenue', 'Cost']);
      expect(resolved.series.first.values, [10, 14]);
      expect(resolved.series.last.values, [7, 9]);
    });

    test('persists and filters categories with aligned series values', () {
      final payload = ChartPayload(
        categoryFilter: 'q',
        categories: const ['Q1', 'Q2', 'North'],
        series: [
          ChartSeries(
            values: const [10, 14, 22],
            points: [
              ChartPoint(x: 0, y: 10),
              ChartPoint(x: 1, y: 14),
              ChartPoint(x: 2, y: 22),
            ],
          ),
        ],
      );
      final restored = ChartPayload.fromJson(payload.toJson());
      final filtered = restored.filteredByCategory();

      expect(restored.categoryFilter, 'q');
      expect(filtered.categories, ['Q1', 'Q2']);
      expect(filtered.series.single.values, [10, 14]);
      expect(filtered.series.single.points.map((point) => point.x), [0, 1]);
    });

    test('bounds malformed imported data and replaces non-finite numbers', () {
      final restored = ChartPayload.fromJson({
        'chartType': 'scatter',
        'categories': List<dynamic>.filled(300, 'label'),
        'series': [
          {
            'name': 'Unsafe',
            'values': [double.nan, double.infinity, -double.infinity, 4],
            'points': [
              {'x': double.nan, 'y': double.infinity},
            ],
          },
        ],
      });

      expect(restored.categories.length, lessThanOrEqualTo(100));
      expect(restored.series.length, 1);
      expect(restored.series.first.values, [0, 0, 0, 4]);
      expect(restored.series.first.points.single.x, 0);
      expect(restored.series.first.points.single.y, 0);
      expect(ChartPayload(colors: const []).colors, isNotEmpty);
    });

    test('clone deep-copies chart collections', () {
      final payload = ChartPayload(
        categories: ['A', 'B'],
        series: [
          ChartSeries(
            name: 'Series',
            values: [1, 2],
            points: [ChartPoint(x: 1, y: 2)],
          ),
        ],
      );

      final clone = payload.clone();
      clone.categories[0] = 'Changed';
      clone.series[0].values[0] = 99;
      clone.series[0].points[0] = ChartPoint(x: 42, y: 2);

      expect(payload.categories, ['A', 'B']);
      expect(payload.series.first.values, [1, 2]);
      expect(payload.series.first.points.single.x, 1);
    });

    test('CanvasNode JSON dispatch restores chart payload', () {
      final node = CanvasNode(
        id: 'chart-node',
        type: NodeType.chart,
        x: 20,
        y: 40,
        width: 320,
        height: 220,
        payload: ChartPayload(
          chartType: ChartType.radar,
          title: 'Coverage',
          categories: const ['A', 'B', 'C'],
          series: [
            ChartSeries(name: 'Score', values: const [3, 5, 4]),
          ],
        ),
      );

      final restored = CanvasNode.fromJson(node.toJson());

      expect(restored.type, NodeType.chart);
      expect(restored.payload, isA<ChartPayload>());
      expect((restored.payload as ChartPayload).chartType, ChartType.radar);
      expect((restored.payload as ChartPayload).series.single.values, [
        3,
        5,
        4,
      ]);
    });

    test('CanvasDocument JSON persistence keeps chart nodes intact', () {
      final document = CanvasDocument(
        projectId: 'chart-persistence',
        updatedAt: DateTime(2026, 1, 2),
        nodes: [
          CanvasNode(
            id: 'chart-document-node',
            type: NodeType.chart,
            x: 8,
            y: 12,
            width: 280,
            height: 180,
            payload: ChartPayload(
              chartType: ChartType.doughnut,
              title: 'Mix',
              series: [
                ChartSeries(values: const [2, 3, 5]),
              ],
            ),
          ),
        ],
      );

      final restored = CanvasDocument.fromJson(document.toJson());
      final node = restored.nodes.single;

      expect(node.type, NodeType.chart);
      expect((node.payload as ChartPayload).chartType, ChartType.doughnut);
      expect((node.payload as ChartPayload).series.single.values, [2, 3, 5]);
    });
  });
}
