import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/domain/models/node_payload.dart';

class ChartDatabaseException implements Exception {
  final String message;

  const ChartDatabaseException(this.message);

  @override
  String toString() => message;
}

class ChartDatabaseQuery {
  final String tableName;
  final String categoryColumn;
  final List<String> valueColumns;
  final int limit;

  ChartDatabaseQuery({
    required String tableName,
    required String categoryColumn,
    required List<String> valueColumns,
    required int limit,
  }) : tableName = _identifier(tableName, 'table'),
       categoryColumn = _identifier(categoryColumn, 'category column'),
       valueColumns = _identifiers(valueColumns, 'value column'),
       limit = limit.clamp(1, 100).toInt() {
    if (valueColumns.isEmpty) {
      throw const ChartDatabaseException(
        'At least one database value column is required.',
      );
    }
    if (valueColumns.contains(categoryColumn)) {
      throw const ChartDatabaseException(
        'Category column cannot also be a value column.',
      );
    }
  }

  factory ChartDatabaseQuery.fromPayload(ChartPayload payload) {
    final tableName = payload.databaseTableName;
    if (tableName == null) {
      throw const ChartDatabaseException('Database table is not configured.');
    }
    return ChartDatabaseQuery(
      tableName: tableName,
      categoryColumn: payload.databaseCategoryColumn,
      valueColumns: payload.databaseValueColumns,
      limit: payload.databaseRowLimit,
    );
  }

  String get selectClause =>
      <String>{categoryColumn, ...valueColumns}.join(',');
}

abstract interface class ChartDatabaseAdapter {
  Future<ChartPayload> load(ChartPayload payload);
}

class ChartDatabasePayloadParser {
  const ChartDatabasePayloadParser._();

  static ChartPayload fromRows({
    required ChartPayload base,
    required ChartDatabaseQuery query,
    required List<Map<String, dynamic>> rows,
  }) {
    final boundedRows = rows.take(query.limit).toList();
    if (boundedRows.isEmpty) {
      throw const ChartDatabaseException('Chart database returned no rows.');
    }

    final categories = <String>[];
    for (final row in boundedRows) {
      final category = row[query.categoryColumn];
      final label = category?.toString().trim() ?? '';
      if (label.isEmpty) {
        throw const ChartDatabaseException(
          'Chart database returned an empty category.',
        );
      }
      categories.add(label);
    }

    final series = <ChartSeries>[];
    for (
      var columnIndex = 0;
      columnIndex < query.valueColumns.length;
      columnIndex++
    ) {
      final column = query.valueColumns[columnIndex];
      var hasNumericValue = false;
      final values = <double>[];
      for (final row in boundedRows) {
        final raw = row[column];
        if (_finiteNumber(raw) != null) hasNumericValue = true;
        values.add(_numberValue(raw, column));
      }
      if (!hasNumericValue) {
        throw ChartDatabaseException(
          'Chart database value column "$column" contains no numeric values.',
        );
      }
      series.add(
        ChartSeries(
          name: column,
          values: values,
          color: base.colors[columnIndex % base.colors.length],
        ),
      );
    }

    return base.copyWith(categories: categories, series: series);
  }

  static double _numberValue(Object? raw, String column) {
    if (raw == null) return 0;
    final value = _finiteNumber(raw);
    if (value == null) {
      throw ChartDatabaseException(
        'Chart database value column "$column" contains a non-numeric value.',
      );
    }
    return value;
  }

  static double? _finiteNumber(Object? raw) {
    final value = switch (raw) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    return value?.isFinite == true ? value : null;
  }
}

class SupabaseChartDatabaseAdapter implements ChartDatabaseAdapter {
  final SupabaseClient? _client;

  const SupabaseChartDatabaseAdapter(this._client);

  @override
  bool operator ==(Object other) =>
      other is SupabaseChartDatabaseAdapter && other._client == _client;

  @override
  int get hashCode => _client.hashCode;

  @override
  Future<ChartPayload> load(ChartPayload payload) async {
    final client = _client;
    if (client == null) {
      throw const ChartDatabaseException(
        'Supabase is not configured for database chart data.',
      );
    }
    final query = ChartDatabaseQuery.fromPayload(payload);
    try {
      final response = await client
          .from(query.tableName)
          .select(query.selectClause)
          .limit(query.limit);
      final rows = [
        for (final item in response) Map<String, dynamic>.from(item),
      ];
      return ChartDatabasePayloadParser.fromRows(
        base: payload,
        query: query,
        rows: rows,
      );
    } on ChartDatabaseException {
      rethrow;
    } on PostgrestException catch (_) {
      throw const ChartDatabaseException(
        'Chart database request was rejected by Supabase.',
      );
    } catch (_) {
      throw const ChartDatabaseException('Chart database could not be loaded.');
    }
  }
}

String _identifier(String value, String label) {
  final trimmed = value.trim();
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,62}$').hasMatch(trimmed)) {
    throw ChartDatabaseException('Invalid database $label.');
  }
  return trimmed;
}

List<String> _identifiers(Iterable<String> values, String label) {
  final identifiers = <String>[];
  for (final value in values) {
    final identifier = _identifier(value, label);
    if (!identifiers.contains(identifier)) identifiers.add(identifier);
  }
  return identifiers.take(12).toList();
}
