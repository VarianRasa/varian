import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/table_formula.dart';

void main() {
  group('Enhanced Table Matrix Feature Suite', () {
    test('TablePayload serializes styling and summary row correctly', () {
      final payload = TablePayload(
        name: 'Sprint Budget',
        columns: ['Category', 'Estimated', 'Actual'],
        rows: [
          ['Dev', '1000', '950'],
          ['Design', '500', '480'],
        ],
        columnTypes: [
          TableCellType.text,
          TableCellType.currency,
          TableCellType.currency,
        ],
        showSummaryRow: true,
        summaryAggregates: {1: 'SUM', 2: 'SUM'},
      );

      final json = payload.toJson();
      expect(json['name'], equals('Sprint Budget'));
      expect(json['showSummaryRow'], isTrue);
      expect(json['summaryAggregates']['1'], equals('SUM'));

      final restored = TablePayload.fromJson(json);
      expect(restored.name, equals('Sprint Budget'));
      expect(restored.showSummaryRow, isTrue);
      expect(restored.columns.length, equals(3));
      expect(restored.typeForColumn(1), equals(TableCellType.currency));
    });

    test('TablePayload clone and copyWith preserves extended styling', () {
      final original = TablePayload(name: 'Sales Matrix', showSummaryRow: true);

      final cloned = original.clone();
      expect(cloned.name, equals('Sales Matrix'));
      expect(cloned.showSummaryRow, isTrue);

      final updated = original.copyWith(showSummaryRow: false);
      expect(updated.showSummaryRow, isFalse);
      expect(original.showSummaryRow, isTrue);
    });

    test('TableFormula calculates sums and arithmetic', () {
      final table = TablePayload(
        columns: ['A', 'B'],
        rows: [
          ['10', '20'],
          ['30', '40'],
        ],
        columnTypes: [TableCellType.number, TableCellType.number],
      );

      final resultSum = TableFormula.evaluate('=SUM(A1:A2)', table);
      expect(resultSum, equals('40'));

      final resultMath = TableFormula.evaluate('=A1+B1', table);
      expect(resultMath, equals('30'));
    });
  });
}
