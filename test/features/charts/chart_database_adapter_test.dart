import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/charts/data/chart_database_adapter.dart';

void main() {
  test('builds a bounded, identifier-only database query', () {
    final query = ChartDatabaseQuery(
      tableName: 'sales_chart',
      categoryColumn: 'category',
      valueColumns: const ['revenue', 'cost'],
      limit: 500,
    );

    expect(query.selectClause, 'category,revenue,cost');
    expect(query.limit, 100);

    expect(
      () => ChartDatabaseQuery(
        tableName: 'public.sales_chart',
        categoryColumn: 'category',
        valueColumns: const [],
        limit: 10,
      ),
      throwsA(isA<ChartDatabaseException>()),
    );
  });

  test('converts bounded rows into chart categories and series', () {
    final payload = ChartPayload(
      databaseTableName: 'sales_chart',
      databaseCategoryColumn: 'category',
      databaseValueColumns: const ['revenue', 'cost'],
      databaseRowLimit: 2,
      categories: const ['Saved'],
      series: [
        ChartSeries(values: const [99]),
      ],
    );
    final query = ChartDatabaseQuery.fromPayload(payload);

    final resolved = ChartDatabasePayloadParser.fromRows(
      base: payload,
      query: query,
      rows: const [
        {'category': 'Q1', 'revenue': 10, 'cost': '7.5'},
        {'category': 'Q2', 'revenue': 14, 'cost': null},
        {'category': 'Q3', 'revenue': 20, 'cost': 12},
      ],
    );

    expect(resolved.categories, ['Q1', 'Q2']);
    expect(resolved.series.map((item) => item.name), ['revenue', 'cost']);
    expect(resolved.series[0].values, [10, 14]);
    expect(resolved.series[1].values, [7.5, 0]);
  });

  test('requires an explicit value allowlist and rejects malformed values', () {
    final payload = ChartPayload(
      databaseTableName: 'sales_chart',
      databaseCategoryColumn: 'category',
    );
    expect(
      () => ChartDatabaseQuery.fromPayload(payload),
      throwsA(isA<ChartDatabaseException>()),
    );

    final invalidQuery = ChartDatabaseQuery(
      tableName: 'sales_chart',
      categoryColumn: 'category',
      valueColumns: const ['revenue'],
      limit: 10,
    );
    expect(
      () => ChartDatabasePayloadParser.fromRows(
        base: payload,
        query: invalidQuery,
        rows: const [
          {'category': 'Q1', 'revenue': 'not-a-number'},
        ],
      ),
      throwsA(isA<ChartDatabaseException>()),
    );
  });

  test('round-trips database source metadata', () {
    final payload = ChartPayload(
      databaseTableName: 'sales_chart',
      databaseCategoryColumn: 'category',
      databaseValueColumns: const ['revenue'],
      databaseRowLimit: 40,
      dataRefreshRevision: 2,
    );
    final restored = ChartPayload.fromJson(payload.toJson());

    expect(restored.databaseTableName, 'sales_chart');
    expect(restored.databaseCategoryColumn, 'category');
    expect(restored.databaseValueColumns, ['revenue']);
    expect(restored.databaseRowLimit, 40);
    expect(
      restored.copyWith(clearDatabaseTable: true).databaseTableName,
      isNull,
    );
  });
}
