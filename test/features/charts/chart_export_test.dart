import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  test(
    'SVG export resolves hidden Table/Grid sources and category filters',
    () {
      final source = CanvasNode(
        id: 'sales-source',
        type: NodeType.tableGrid,
        x: 0,
        y: 0,
        width: 240,
        height: 140,
        visible: false,
        payload: TablePayload(
          columns: const ['Quarter', 'Revenue'],
          columnTypes: const [TableCellType.text, TableCellType.number],
          rows: const [
            ['Q1', '10'],
            ['Q2', '14'],
          ],
        ),
      );
      final chart = CanvasNode(
        id: 'sales-chart',
        type: NodeType.chart,
        x: 300,
        y: 40,
        width: 360,
        height: 240,
        payload: ChartPayload(
          chartType: ChartType.bar,
          tableSourceNodeId: source.id,
          categoryFilter: 'q2',
          showValues: true,
        ),
      );

      final svg = ExportService.exportVectorSvg(
        CanvasDocument(
          projectId: 'chart-export',
          updatedAt: DateTime(2026, 1, 1),
          nodes: [source, chart],
          edges: const [],
        ),
      );

      expect(svg, contains('>Q2</text>'));
      expect(svg, isNot(contains('>Q1</text>')));
      expect(svg, contains('>14</text>'));

      final markdown = ExportService.exportMarkdown(
        CanvasDocument(
          projectId: 'chart-export-markdown',
          updatedAt: DateTime(2026, 1, 1),
          nodes: [source, chart],
          edges: const [],
        ),
      );
      expect(markdown, contains('| Q2 | 14 |'));
      expect(markdown, isNot(contains('| Q1 |')));

      final plainText = ExportService.exportPlainText(
        CanvasDocument(
          projectId: 'chart-export-text',
          updatedAt: DateTime(2026, 1, 1),
          nodes: [source, chart],
          edges: const [],
        ),
      );
      expect(plainText, contains('  Q2: 14'));
      expect(plainText, isNot(contains('  Q1:')));
    },
  );

  test(
    'SVG export keeps manual chart data when its table source is missing',
    () {
      final chart = CanvasNode(
        id: 'manual-chart',
        type: NodeType.chart,
        x: 20,
        y: 20,
        width: 360,
        height: 240,
        payload: ChartPayload(
          chartType: ChartType.line,
          tableSourceNodeId: 'missing-source',
          categoryFilter: 'north',
          categories: const ['North', 'South'],
          series: [
            ChartSeries(values: const [8, 2]),
          ],
        ),
      );

      final svg = ExportService.exportVectorSvg(
        CanvasDocument(
          projectId: 'manual-chart-export',
          updatedAt: DateTime(2026, 1, 1),
          nodes: [chart],
          edges: const [],
        ),
      );

      expect(svg, contains('>North</text>'));
      expect(svg, isNot(contains('>South</text>')));
    },
  );
}
