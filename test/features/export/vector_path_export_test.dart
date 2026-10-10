import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  test(
    'exports compound vector contours, fill rules, gradients, and dash offset',
    () {
      final payload = VectorPathPayload(
        subpaths: [
          [
            const BezierPoint(point: Offset(0, 0)),
            const BezierPoint(point: Offset(40, 0)),
            const BezierPoint(point: Offset(40, 40)),
          ],
          [
            const BezierPoint(point: Offset(10, 10)),
            const BezierPoint(point: Offset(20, 10)),
            const BezierPoint(point: Offset(20, 20)),
          ],
        ],
        subpathClosed: [true, true],
        fillRule: VectorFillRule.evenOdd,
        fill: const Color(0xCCFF0000),
        stroke: const Color(0x99000000),
        strokeWidth: 2,
        dashPattern: const [3, 2],
        dashOffset: 1.5,
        isGradientFill: true,
        gradientEndColor: const Color(0xCC0000FF),
      );
      final svg = ExportService.exportVectorSvg(
        CanvasDocument(
          projectId: 'vector-export-test',
          updatedAt: DateTime(2026),
          nodes: [
            CanvasNode(
              id: 'compound-vector',
              type: NodeType.vectorPath,
              x: 10,
              y: 20,
              width: 40,
              height: 40,
              payload: payload,
            ),
          ],
        ),
      );

      expect(svg, contains('M 10.0 20.0'));
      expect(svg, contains('M 20.0 30.0'));
      expect(svg, contains('fill-rule="evenodd"'));
      expect(svg, contains('stroke-dasharray="3.0,2.0"'));
      expect(svg, contains('stroke-dashoffset="1.5"'));
      expect(svg, contains('<linearGradient id="gradient_compound-vector"'));
      expect(svg, contains('fill="url(#gradient_compound-vector)"'));
      expect(svg, isNot(contains('fill="none"')));
    },
  );

  test('exports all chart families as native SVG geometry', () {
    final charts = <ChartType, String>{
      ChartType.line: '<polyline',
      ChartType.bar: '<rect',
      ChartType.pie: '<path',
      ChartType.doughnut: '<path',
      ChartType.scatter: '<circle',
      ChartType.radar: '<polygon',
    };

    for (final entry in charts.entries) {
      final payload = ChartPayload(
        title: 'Sales & margin',
        chartType: entry.key,
        categories: const ['Q1', 'Q2', 'Q3'],
        series: [
          ChartSeries(
            name: 'Sales',
            values: const [3, 5, 4],
            points: [
              ChartPoint(x: 0, y: 3),
              ChartPoint(x: 1, y: 5),
              ChartPoint(x: 2, y: 4),
            ],
          ),
        ],
        showValues: true,
      );
      final svg = ExportService.exportVectorSvg(
        CanvasDocument(
          projectId: 'chart-svg-export-test',
          updatedAt: DateTime(2026),
          nodes: [
            CanvasNode(
              id: 'chart-${entry.key.name}',
              type: NodeType.chart,
              x: 10,
              y: 20,
              width: 360,
              height: 240,
              payload: payload,
            ),
          ],
        ),
      );

      expect(svg, contains('Sales &amp; margin'));
      expect(svg, contains(entry.value));
      expect(svg, isNot(contains('CHART')));
    }
  });

  test('keeps chart data in markdown, text, and PDF exports', () {
    final document = CanvasDocument(
      projectId: 'chart-summary-export-test',
      updatedAt: DateTime(2026),
      nodes: [
        CanvasNode(
          id: 'chart-summary',
          type: NodeType.chart,
          x: 20,
          y: 30,
          width: 320,
          height: 220,
          payload: ChartPayload(
            title: 'Quarterly sales',
            chartType: ChartType.bar,
            categories: const ['Q1', 'Q2'],
            series: [
              ChartSeries(name: 'Revenue', values: const [12, 18]),
            ],
          ),
        ),
      ],
    );

    expect(
      ExportService.exportMarkdown(document),
      allOf(contains('Quarterly sales'), contains('| Q2 | 18 |')),
    );
    expect(
      ExportService.exportPlainText(document),
      allOf(contains('bar chart'), contains('Q1: 12')),
    );
    final pdf = String.fromCharCodes(
      ExportService.exportMultiPagePdf(document),
    );
    expect(pdf, contains(r'Quarterly sales \(bar chart\)'));
  });
}
