import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/charts/data/chart_source_loader.dart';
import 'package:varian/features/charts/presentation/chart_node_widget.dart';

class _RemoteClient extends http.BaseClient {
  final int statusCode;
  final String body;

  _RemoteClient({this.statusCode = 200, required this.body});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream.value(bytes),
      statusCode,
      contentLength: bytes.length,
      request: request,
    );
  }
}

Future<void> _pumpChart(
  WidgetTester tester, {
  required ChartSourceLoader loader,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 240,
          child: ChartNodeWidget(
            payload: ChartPayload(
              dataSourceUrl: 'https://example.com/chart.json',
              categories: const ['Saved'],
              series: [
                ChartSeries(values: const [1]),
              ],
            ),
            sourceLoader: loader,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders validated remote data over saved chart data', (
    tester,
  ) async {
    final loader = ChartSourceLoader(
      client: _RemoteClient(
        body: jsonEncode({
          'categories': ['Remote A', 'Remote B'],
          'series': [
            {
              'name': 'Remote',
              'values': [10, 20],
            },
          ],
        }),
      ),
    );
    addTearDown(loader.dispose);

    await _pumpChart(tester, loader: loader);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots, [
      const FlSpot(0, 10),
      const FlSpot(1, 20),
    ]);
    expect(find.text('Using saved chart data'), findsNothing);
  });

  testWidgets('keeps saved chart data when the remote source fails', (
    tester,
  ) async {
    final loader = ChartSourceLoader(
      client: _RemoteClient(statusCode: 503, body: '{}'),
    );
    addTearDown(loader.dispose);

    await _pumpChart(tester, loader: loader);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots, [const FlSpot(0, 1)]);
    expect(find.text('Using saved chart data'), findsOneWidget);
  });
}
