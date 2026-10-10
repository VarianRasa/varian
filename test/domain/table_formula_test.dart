import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/table_formula.dart';

void main() {
  group('TableFormula', () {
    final table1 = TablePayload(
      name: 'Sheet1',
      columns: const ['A', 'B', 'C', 'D'],
      rows: const [
        ['10', '20', '=A1+B1', 'hello'],
        ['5', '2', '=SUM(A1:B2)', 'world'],
        ['3', '', '=COUNTA(A1:D2)', ''],
      ],
    );

    final table2 = TablePayload(
      name: 'Sheet2',
      columns: const ['A', 'B'],
      rows: const [
        ['100', '200'],
      ],
    );

    final allTables = {'Sheet1': table1, 'Sheet2': table2};

    test('evaluates arithmetic with cell references', () {
      expect(TableFormula.evaluate('=A1+B1', table1), '30');
    });

    test('evaluates SUM over a range', () {
      expect(TableFormula.evaluate('=SUM(A1:B2)', table1), '37');
    });

    test('handles parentheses and precedence', () {
      expect(TableFormula.evaluate('=(1+2)*3', table1), '9');
    });

    test('returns raw for non-formula text', () {
      expect(TableFormula.evaluate('hello', table1), 'hello');
    });

    test('numeric functions', () {
      expect(TableFormula.evaluate('=ABS(-5)', table1), '5');
      expect(TableFormula.evaluate('=ROUND(3.14159, 2)', table1), '3.14');
      expect(TableFormula.evaluate('=CEIL(3.2)', table1), '4');
      expect(TableFormula.evaluate('=FLOOR(3.8)', table1), '3');
      expect(TableFormula.evaluate('=SQRT(16)', table1), '4');
      expect(TableFormula.evaluate('=POW(2,3)', table1), '8');
      expect(TableFormula.evaluate('=MOD(7,3)', table1), '1');
      expect(TableFormula.evaluate('=COUNT(A1:B2)', table1), '4');
      expect(TableFormula.evaluate('=MEDIAN(1,3,2)', table1), '2');
    });

    test('logical functions', () {
      expect(TableFormula.evaluate('=IF(1>0, "yes", "no")', table1), 'yes');
      expect(TableFormula.evaluate('=AND(1, 1)', table1), 'TRUE');
      expect(TableFormula.evaluate('=OR(0, 1)', table1), 'TRUE');
      expect(TableFormula.evaluate('=NOT(0)', table1), 'TRUE');
      expect(TableFormula.evaluate('=1>=2', table1), 'FALSE');
    });

    test('text functions', () {
      expect(TableFormula.evaluate('=UPPER("abc")', table1), 'ABC');
      expect(TableFormula.evaluate('=LOWER("ABC")', table1), 'abc');
      expect(TableFormula.evaluate('=LEN("hello")', table1), '5');
      expect(TableFormula.evaluate('=TRIM("  hi  ")', table1), 'hi');
      expect(TableFormula.evaluate('=CONCAT("a", "b")', table1), 'ab');
    });

    test('conditional aggregates', () {
      expect(TableFormula.evaluate('=SUMIF(A1:B2, ">5")', table1), '30');
      expect(TableFormula.evaluate('=COUNTIF(A1:B2, ">=10")', table1), '2');
      expect(TableFormula.evaluate('=SUMIF(A1:B2, ">5", A1:B2)', table1), '30');
    });

    test('multi-criteria aggregates', () {
      expect(
        TableFormula.evaluate(
          '=SUMIFS(A1:A2, A1:A2, ">5", B1:B2, ">5")',
          table1,
        ),
        '10',
      );
      expect(
        TableFormula.evaluate('=COUNTIFS(A1:A2, ">5", B1:B2, ">5")', table1),
        '1',
      );
      expect(
        TableFormula.evaluate(
          '=AVERAGEIFS(A1:A2, A1:A2, ">5", B1:B2, ">5")',
          table1,
        ),
        '10',
      );
    });

    test('string escapes', () {
      expect(TableFormula.evaluate('=CONCAT("a\\"b")', table1), 'a"b');
    });

    test('cross-sheet references', () {
      expect(
        TableFormula.evaluate('=Sheet2!A1+A1', table1, tables: allTables),
        '110',
      );
      expect(
        TableFormula.evaluate('=SUM(Sheet2!A1:B1)', table1, tables: allTables),
        '300',
      );
    });

    test('array literals', () {
      expect(TableFormula.evaluate('=SUM({1, 2, 3})', table1), '6');
    });
  });
}
