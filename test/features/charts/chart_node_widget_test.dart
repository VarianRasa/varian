import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/charts/data/chart_database_adapter.dart';
import 'package:varian/features/charts/presentation/chart_node_widget.dart';

class _FakeDatabaseAdapter implements ChartDatabaseAdapter {
  final ChartPayload remote;
  final ChartDatabaseException? error;

  const _FakeDatabaseAdapter(this.remote, {this.error});

  @override
  Future<ChartPayload> load(ChartPayload payload) async {
    final error = this.error;
    if (error != null) throw error;
    return remote;
  }
}

void main() {
  testWidgets('renders every supported chart family with fl_chart', (
    tester,
  ) async {
    final expectedTypes = <ChartType, Type>{
      ChartType.line: LineChart,
      ChartType.bar: BarChart,
      ChartType.pie: PieChart,
      ChartType.doughnut: PieChart,
      ChartType.scatter: ScatterChart,
      ChartType.radar: RadarChart,
    };

    for (final entry in expectedTypes.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 240,
              child: ChartNodeWidget(
                payload: ChartPayload(
                  chartType: entry.key,
                  categories: const ['A', 'B', 'C', 'D'],
                  series: [
                    ChartSeries(
                      name: 'Primary',
                      values: const [4, 7, 5, 9],
                      points: [
                        ChartPoint(x: 0, y: 4),
                        ChartPoint(x: 1, y: 7),
                        ChartPoint(x: 2, y: 5),
                        ChartPoint(x: 3, y: 9),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(entry.value), findsOneWidget, reason: entry.key.name);
    }
  });

  testWidgets('loads database data while keeping saved fallback metadata', (
    tester,
  ) async {
    final payload = ChartPayload(
      databaseTableName: 'sales_chart',
      categories: const ['Saved'],
      series: [
        ChartSeries(values: const [99]),
      ],
    );
    final remote = ChartPayload(
      categories: const ['Q1', 'Q2'],
      series: [
        ChartSeries(values: const [10, 14]),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 240,
            child: ChartNodeWidget(
              payload: payload,
              databaseAdapter: _FakeDatabaseAdapter(remote),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots, [
      const FlSpot(0, 10),
      const FlSpot(1, 14),
    ]);
    expect(payload.databaseTableName, 'sales_chart');
    expect(payload.categories, ['Saved']);
  });

  testWidgets('keeps saved chart data when database loading fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 240,
            child: ChartNodeWidget(
              payload: ChartPayload(
                databaseTableName: 'sales_chart',
                categories: const ['Saved'],
                series: [
                  ChartSeries(values: const [99]),
                ],
              ),
              databaseAdapter: _FakeDatabaseAdapter(
                ChartPayload(),
                error: const ChartDatabaseException('denied'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots, [const FlSpot(0, 99)]);
    expect(find.text('Using saved chart data'), findsOneWidget);
  });

  testWidgets('configures native tooltip and crosshair touch handling', (
    tester,
  ) async {
    Future<void> pumpChart(bool showTooltips) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 240,
              child: ChartNodeWidget(
                payload: ChartPayload(
                  chartType: ChartType.line,
                  showTooltips: showTooltips,
                  categories: const ['A', 'B'],
                  series: [
                    ChartSeries(values: const [4, 7]),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpChart(true);
    final enabledChart = tester.widget<LineChart>(find.byType(LineChart));
    expect(enabledChart.data.lineTouchData.enabled, isTrue);
    expect(enabledChart.data.lineTouchData.handleBuiltInTouches, isTrue);

    await pumpChart(false);
    final disabledChart = tester.widget<LineChart>(find.byType(LineChart));
    expect(disabledChart.data.lineTouchData.enabled, isFalse);
  });

  testWidgets('routes chart tap responses to category callbacks', (
    tester,
  ) async {
    String? tappedCategory;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 240,
            child: ChartNodeWidget(
              payload: ChartPayload(
                chartType: ChartType.line,
                showTooltips: false,
                categories: const ['A', 'B'],
                series: [
                  ChartSeries(values: const [4, 7]),
                ],
              ),
              onCategoryTap: (category) => tappedCategory = category,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineTouchData.enabled, isTrue);
    expect(chart.data.lineTouchData.handleBuiltInTouches, isFalse);
    expect(chart.data.lineTouchData.touchCallback, isNotNull);
    final bar = chart.data.lineBarsData.single;
    chart.data.lineTouchData.touchCallback!(
      FlTapUpEvent(
        TapUpDetails(
          kind: PointerDeviceKind.touch,
          globalPosition: Offset.zero,
          localPosition: Offset.zero,
        ),
      ),
      LineTouchResponse(
        touchLocation: Offset.zero,
        touchChartCoordinate: Offset.zero,
        lineBarSpots: [TouchLineBarSpot(bar, 0, bar.spots[1], 0)],
      ),
    );
    expect(tappedCategory, 'B');
  });

  testWidgets('filters chart spots by persisted category filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 240,
            child: ChartNodeWidget(
              payload: ChartPayload(
                chartType: ChartType.line,
                categoryFilter: 'q',
                categories: const ['Q1', 'Q2', 'North'],
                series: [
                  ChartSeries(values: const [10, 14, 22]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots, [
      const FlSpot(0, 10),
      const FlSpot(1, 14),
    ]);
  });

  testWidgets('configures native touch feedback for pie and radar charts', (
    tester,
  ) async {
    Future<void> pumpChart(ChartType chartType, bool showTooltips) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 240,
              child: ChartNodeWidget(
                payload: ChartPayload(
                  chartType: chartType,
                  showTooltips: showTooltips,
                  categories: const ['A', 'B', 'C'],
                  series: [
                    ChartSeries(name: 'Primary', values: const [4, 7, 5]),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpChart(ChartType.pie, true);
    final pieChart = tester.widget<PieChart>(find.byType(PieChart));
    expect(pieChart.data.pieTouchData.enabled, isTrue);
    expect(pieChart.data.pieTouchData.touchCallback, isNotNull);
    expect(pieChart.data.sections[0].radius, 54);

    await pumpChart(ChartType.radar, true);
    final radarChart = tester.widget<RadarChart>(find.byType(RadarChart));
    expect(radarChart.data.radarTouchData.enabled, isTrue);
    expect(radarChart.data.radarTouchData.touchCallback, isNotNull);

    await pumpChart(ChartType.doughnut, false);
    final disabledDoughnut = tester.widget<PieChart>(find.byType(PieChart));
    expect(disabledDoughnut.data.pieTouchData.enabled, isFalse);
    expect(disabledDoughnut.data.pieTouchData.touchCallback, isNull);
  });
  testWidgets('chart touch label uses app chrome tokens', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 240,
            child: ChartNodeWidget(
              payload: ChartPayload(
                chartType: ChartType.pie,
                showTooltips: true,
                categories: const ['Q1', 'Q2'],
                series: [
                  ChartSeries(name: 'Revenue', values: const [4, 7]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<PieChart>(find.byType(PieChart));
    chart.data.pieTouchData.touchCallback!(
      FlTapDownEvent(
        TapDownDetails(globalPosition: Offset.zero, localPosition: Offset.zero),
      ),
      PieTouchResponse(
        touchLocation: Offset.zero,
        touchedSection: PieTouchedSection(chart.data.sections.first, 0, 0, 20),
      ),
    );
    await tester.pump();

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('chart-touch-label-surface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    final tokens = AppTheme.darkTheme.extension<AppTokens>()!;
    expect(decoration.color, tokens.panelElevated);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(tokens.controlRadius),
    );
    expect((decoration.border! as Border).top.width, AppBorder.thin);
    final labelPadding = tester.widget<Padding>(
      find.descendant(
        of: find.byKey(const ValueKey('chart-touch-label-surface')),
        matching: find.byType(Padding),
      ),
    );
    expect(
      labelPadding.padding,
      const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.xs),
    );
    expect((decoration.border! as Border).top.color, tokens.panelBorder);
    expect(find.text('Q1\nRevenue: 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
