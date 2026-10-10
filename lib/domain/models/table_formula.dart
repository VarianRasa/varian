import 'dart:math';
import 'node_payload.dart';

sealed class _V {}

class _N extends _V {
  final double n;
  _N(this.n);
}

class _S extends _V {
  final String s;
  _S(this.s);
}

class _B extends _V {
  final bool b;
  _B(this.b);
}

class _Range extends _V {
  final List<_V> values;
  _Range(this.values);
}

class TableFormula {
  static String evaluate(
    String raw,
    TablePayload table, {
    Map<String, TablePayload> tables = const {},
  }) {
    final s = raw.trim();
    if (!s.startsWith('=')) return raw;
    final expr = s.substring(1).trim();
    if (expr.isEmpty) return raw;
    try {
      final v = _Parser(expr, table, tables).parse();
      return _render(v);
    } catch (_) {
      return raw;
    }
  }

  static String _render(_V v) {
    switch (v) {
      case _N(:final n):
        if (n.isNaN || n.isInfinite) return '0';
        if (n == n.roundToDouble() && n.abs() < 1e15) {
          return n.toInt().toString();
        }
        return n.toStringAsFixed(2);
      case _S(:final s):
        return s;
      case _B(:final b):
        return b ? 'TRUE' : 'FALSE';
      case _Range():
        throw const FormatException('range outside aggregate');
    }
  }
}

class _Parser {
  final String _src;
  final TablePayload _table;
  final Map<String, TablePayload> _tables;
  int _i = 0;

  _Parser(this._src, this._table, this._tables);

  _V parse() {
    final v = _comparison();
    _skipWs();
    if (_i < _src.length) throw const FormatException('trailing input');
    return v;
  }

  _V _comparison() {
    var left = _additive();
    _skipWs();
    final op = _peekComparisonOp();
    if (op != null) {
      _i += op.length;
      final right = _additive();
      return _B(_compare(left, right, op));
    }
    return left;
  }

  String? _peekComparisonOp() {
    for (final op in const ['<>', '>=', '<=', '=', '>', '<']) {
      if (_src.startsWith(op, _i)) return op;
    }
    return null;
  }

  bool _compare(_V a, _V b, String op) {
    switch (op) {
      case '=':
        return _eq(a, b);
      case '<>':
        return !_eq(a, b);
      case '>':
      case '<':
      case '>=':
      case '<=':
        final cmp = _cmp(a, b);
        switch (op) {
          case '>':
            return cmp > 0;
          case '<':
            return cmp < 0;
          case '>=':
            return cmp >= 0;
          case '<=':
            return cmp <= 0;
        }
    }
    throw const FormatException('bad op');
  }

  bool _eq(_V a, _V b) {
    if (a is _N && b is _N) return a.n == b.n;
    if (a is _B && b is _B) return a.b == b.b;
    return _str(a) == _str(b);
  }

  int _cmp(_V a, _V b) {
    if (a is _N && b is _N) return a.n.compareTo(b.n);
    return _str(a).compareTo(_str(b));
  }

  _V _additive() {
    var left = _multiplicative();
    while (true) {
      _skipWs();
      if (_peek('+')) {
        _i++;
        final right = _multiplicative();
        left = _add(left, right);
      } else if (_peek('-')) {
        _i++;
        final right = _multiplicative();
        left = _N(_toNum(left) - _toNum(right));
      } else {
        break;
      }
    }
    return left;
  }

  _V _add(_V a, _V b) {
    if (a is _S || b is _S) return _S(_str(a) + _str(b));
    return _N(_toNum(a) + _toNum(b));
  }

  _V _multiplicative() {
    var left = _unary();
    while (true) {
      _skipWs();
      if (_peek('*')) {
        _i++;
        final right = _unary();
        left = _N(_toNum(left) * _toNum(right));
      } else if (_peek('/')) {
        _i++;
        final right = _unary();
        left = _N(_toNum(left) / _toNum(right));
      } else {
        break;
      }
    }
    return left;
  }

  _V _unary() {
    _skipWs();
    if (_peek('-')) {
      _i++;
      return _N(-_toNum(_unary()));
    }
    if (_peek('+')) {
      _i++;
      return _unary();
    }
    return _primary();
  }

  _V _primary() {
    _skipWs();
    if (_peek('(')) {
      _i++;
      final v = _comparison();
      _skipWs();
      if (!_peek(')')) throw const FormatException('expected )');
      _i++;
      return v;
    }
    final c = _peekChar();
    if (_isDigit(c) || c == '.') return _N(_number());
    if (c == '"' || c == "'") return _S(_stringLiteral(c));
    if (c == '{') return _arrayLiteral();
    if (_isLetter(c)) {
      final name = _readIdentifier();
      _skipWs();
      if (_peek('!')) {
        _i++;
        _skipWs();
        final ref = _readRefToken();
        return _cellValue(ref, sheet: name);
      }
      if (_peek('(')) {
        _i++;
        return _function(name);
      }
      return _cellValue(name);
    }
    throw const FormatException('unexpected token');
  }

  _V _arrayLiteral() {
    // {1,2,3} or {1;2;3} (row) / {1,2;3,4} (matrix)
    _i++; // consume {
    final rows = <List<_V>>[];
    var current = <_V>[];
    while (true) {
      _skipWs();
      if (_peek('}')) {
        _i++;
        if (current.isNotEmpty) rows.add(current);
        break;
      }
      if (_peek(';')) {
        _i++;
        rows.add(current);
        current = <_V>[];
        continue;
      }
      if (_peek(',')) {
        _i++;
        continue;
      }
      current.add(_comparison());
    }
    // Flatten into a single-row range
    final flat = <_V>[];
    for (final r in rows) {
      flat.addAll(r);
    }
    return _Range(flat);
  }

  _V _function(String name) {
    final args = <_V>[];
    _skipWs();
    if (_peek(')')) {
      _i++;
    } else {
      while (true) {
        if (_peekRangeAhead()) {
          args.addAll(_consumeRange());
        } else {
          args.add(_comparison());
        }
        _skipWs();
        if (_peek(',')) {
          _i++;
          continue;
        }
        if (_peek(')')) {
          _i++;
          break;
        }
        throw const FormatException('expected , or )');
      }
    }
    return _apply(name.toUpperCase(), args);
  }

  bool _peekRangeAhead() {
    var j = _i;
    while (j < _src.length && _src[j] == ' ') {
      j++;
    }
    while (j < _src.length &&
        (_isLetter(_src[j]) || _src[j] == '!' || _isDigit(_src[j]))) {
      j++;
    }
    if (j < _src.length && _src[j] == ':') return true;
    return false;
  }

  List<_V> _consumeRange() {
    _skipWs();
    String? sheet;
    final first = _readRefToken();
    if (first.contains('!')) {
      final parts = first.split('!');
      sheet = parts[0];
    }
    _skipWs();
    if (!_peek(':')) throw const FormatException('expected :');
    _i++;
    _skipWs();
    final second = _readRefToken();
    final t = sheet != null && _tables.containsKey(sheet)
        ? _tables[sheet]!
        : _table;
    return [_Range(_rangeValues(first, second, t))];
  }

  _V _apply(String name, List<_V> args) {
    final flat = _flatten(args);
    switch (name) {
      case 'SUM':
        return _N(_nums(flat).fold(0.0, (a, b) => a + b));
      case 'AVG':
        final ns = _nums(flat);
        return _N(ns.isEmpty ? 0 : ns.fold(0.0, (a, b) => a + b) / ns.length);
      case 'MIN':
        final ns = _nums(flat);
        return _N(ns.isEmpty ? 0 : ns.reduce(min));
      case 'MAX':
        final ns = _nums(flat);
        return _N(ns.isEmpty ? 0 : ns.reduce(max));
      case 'COUNT':
        return _N(_nums(flat).length.toDouble());
      case 'COUNTA':
        return _N(
          flat.where((a) => _str(a).trim().isNotEmpty).length.toDouble(),
        );
      case 'MEDIAN':
        final ns = _nums(flat)..sort();
        if (ns.isEmpty) return _N(0);
        final mid = ns.length ~/ 2;
        if (ns.length.isOdd) return _N(ns[mid]);
        return _N((ns[mid - 1] + ns[mid]) / 2);
      case 'SUMIF':
        return _N(_sumIf(flat, args).fold(0.0, (a, b) => a + b));
      case 'AVERAGEIF':
        final ns = _sumIf(flat, args);
        return _N(ns.isEmpty ? 0 : ns.fold(0.0, (a, b) => a + b) / ns.length);
      case 'COUNTIF':
        return _N(_sumIf(flat, args).length.toDouble());
      case 'SUMIFS':
        return _N(_sumIfs(flat, args).fold(0.0, (a, b) => a + b));
      case 'AVERAGEIFS':
        final ns = _sumIfs(flat, args);
        return _N(ns.isEmpty ? 0 : ns.fold(0.0, (a, b) => a + b) / ns.length);
      case 'COUNTIFS':
        return _N(_countIfs(flat, args).toDouble());
      case 'ABS':
        return _N(_nums(flat).map((n) => n.abs()).reduce((a, b) => a));
      case 'ROUND':
        return _N(
          _round(
            _toNum(flat[0]),
            flat.length > 1 ? _toNum(flat[1]).toInt() : 0,
          ),
        );
      case 'CEIL':
        return _N(_toNum(flat[0]).ceilToDouble());
      case 'FLOOR':
        return _N(_toNum(flat[0]).floorToDouble());
      case 'SQRT':
        return _N(sqrt(_toNum(flat[0])));
      case 'POW':
        return _N(pow(_toNum(flat[0]), _toNum(flat[1])).toDouble());
      case 'MOD':
        return _N(_toNum(flat[0]) % _toNum(flat[1]));
      case 'IF':
        final cond = flat.isNotEmpty && flat[0] is _B
            ? (flat[0] as _B).b
            : _toNum(flat[0]) != 0;
        if (cond) return flat.length > 1 ? flat[1] : _N(0);
        return flat.length > 2 ? flat[2] : _N(0);
      case 'AND':
        return _B(flat.every((a) => _toBool(a)));
      case 'OR':
        return _B(flat.any((a) => _toBool(a)));
      case 'NOT':
        return _B(!_toBool(flat[0]));
      case 'CONCAT':
        return _S(flat.map(_str).join());
      case 'UPPER':
        return _S(_str(flat[0]).toUpperCase());
      case 'LOWER':
        return _S(_str(flat[0]).toLowerCase());
      case 'LEN':
        return _N(_str(flat[0]).length.toDouble());
      case 'TRIM':
        return _S(_str(flat[0]).trim());
      default:
        throw const FormatException('unknown function');
    }
  }

  List<_V> _flatten(List<_V> args) {
    final out = <_V>[];
    for (final a in args) {
      if (a is _Range) {
        out.addAll(a.values);
      } else {
        out.add(a);
      }
    }
    return out;
  }

  List<double> _sumIf(List<_V> flat, List<_V> rawArgs) {
    // SUMIF(range, criteria) or SUMIF(range, criteria, sum_range)
    final range = rawArgs.isNotEmpty && rawArgs[0] is _Range
        ? (rawArgs[0] as _Range).values
        : flat;
    final criteria = rawArgs.length > 1 ? _str(rawArgs[1]) : '';
    final sumRange = rawArgs.length > 2 && rawArgs[2] is _Range
        ? (rawArgs[2] as _Range).values
        : range;

    final out = <double>[];
    for (int i = 0; i < range.length; i++) {
      if (_matchesCriteria(range[i], criteria)) {
        final v = i < sumRange.length ? sumRange[i] : _N(0);
        final d = _tryNum(v);
        if (d != null) out.add(d);
      }
    }
    return out;
  }

  List<double> _sumIfs(List<_V> flat, List<_V> rawArgs) {
    // SUMIFS(sum_range, criteria_range1, criteria1, [criteria_range2, criteria2, ...])
    final (sumRange, pairs) = _parseIfs(flat, rawArgs);
    final out = <double>[];
    for (int i = 0; i < sumRange.length; i++) {
      var match = true;
      for (final (range, criteria) in pairs) {
        final v = i < range.length ? range[i] : _S('');
        if (!_matchesCriteria(v, criteria)) {
          match = false;
          break;
        }
      }
      if (match) {
        final d = _tryNum(sumRange[i]);
        if (d != null) out.add(d);
      }
    }
    return out;
  }

  int _countIfs(List<_V> flat, List<_V> rawArgs) {
    // COUNTIFS(criteria_range1, criteria1, [criteria_range2, criteria2, ...])
    final pairs = <(List<_V>, String)>[];
    for (int i = 0; i + 1 < rawArgs.length; i += 2) {
      final range = rawArgs[i] is _Range ? (rawArgs[i] as _Range).values : flat;
      pairs.add((range, _str(rawArgs[i + 1])));
    }
    final len = pairs.isNotEmpty ? pairs.first.$1.length : 0;
    var count = 0;
    for (int i = 0; i < len; i++) {
      var match = true;
      for (final (range, criteria) in pairs) {
        final v = i < range.length ? range[i] : _S('');
        if (!_matchesCriteria(v, criteria)) {
          match = false;
          break;
        }
      }
      if (match) count++;
    }
    return count;
  }

  (List<_V>, List<(List<_V>, String)>) _parseIfs(
    List<_V> flat,
    List<_V> rawArgs,
  ) {
    final sumRange = rawArgs.isNotEmpty && rawArgs[0] is _Range
        ? (rawArgs[0] as _Range).values
        : flat;
    final pairs = <(List<_V>, String)>[];
    for (int i = 1; i + 1 < rawArgs.length; i += 2) {
      final range = rawArgs[i] is _Range ? (rawArgs[i] as _Range).values : flat;
      pairs.add((range, _str(rawArgs[i + 1])));
    }
    return (sumRange, pairs);
  }

  bool _matchesCriteria(_V v, String criteria) {
    final c = criteria.trim();
    if (c.isEmpty) return true;
    final m = RegExp(r'^(<=|>=|<>|=|<|>)(.*)$').firstMatch(c);
    if (m != null) {
      final op = m.group(1)!;
      final rhs = m.group(2)!;
      final rhsNum = double.tryParse(rhs);
      final vNum = _tryNum(v);
      if (rhsNum != null && vNum != null) {
        switch (op) {
          case '<':
            return vNum < rhsNum;
          case '>':
            return vNum > rhsNum;
          case '<=':
            return vNum <= rhsNum;
          case '>=':
            return vNum >= rhsNum;
          case '=':
            return vNum == rhsNum;
          case '<>':
            return vNum != rhsNum;
        }
      }
      switch (op) {
        case '=':
          return _str(v) == rhs;
        case '<>':
          return _str(v) != rhs;
      }
      return false;
    }
    return _str(v).contains(c);
  }

  double? _tryNum(_V v) {
    if (v is _N) return v.n;
    if (v is _S) return double.tryParse(v.s.trim());
    if (v is _B) return v.b ? 1 : 0;
    return null;
  }

  double _round(double v, int digits) {
    final f = pow(10, digits).toDouble();
    return (v * f).roundToDouble() / f;
  }

  List<double> _nums(List<_V> args) {
    final out = <double>[];
    for (final a in args) {
      if (a is _N) {
        out.add(a.n);
      } else if (a is _S) {
        final d = double.tryParse(a.s.trim());
        if (d != null) out.add(d);
      }
    }
    return out;
  }

  double _toNum(_V v) {
    if (v is _N) return v.n;
    if (v is _B) return v.b ? 1 : 0;
    if (v is _S) {
      final d = double.tryParse(v.s.trim());
      if (d != null) return d;
    }
    throw const FormatException('not a number');
  }

  bool _toBool(_V v) {
    if (v is _B) return v.b;
    if (v is _N) return v.n != 0;
    if (v is _S) return v.s.trim().isNotEmpty;
    return false;
  }

  String _str(_V v) {
    switch (v) {
      case _N(:final n):
        if (n == n.roundToDouble() && n.abs() < 1e15) {
          return n.toInt().toString();
        }
        return n.toString();
      case _S(:final s):
        return s;
      case _B(:final b):
        return b ? 'TRUE' : 'FALSE';
      case _Range(:final values):
        return values.map(_str).join(', ');
    }
  }

  _V _cellValue(String ref, {String? sheet}) {
    final table = sheet != null && _tables.containsKey(sheet)
        ? _tables[sheet]!
        : _table;
    final (c, r) = _parseRef(ref);
    final col = c.toInt();
    final row = r.toInt();
    if (row < 0 || row >= table.rows.length) return _S('');
    final rowData = table.rows[row];
    if (col < 0 || col >= rowData.length) return _S('');
    final raw = rowData[col].trim();
    final d = double.tryParse(raw);
    if (d != null) return _N(d);
    return _S(raw);
  }

  String _readRefToken() {
    final start = _i;
    while (_i < _src.length &&
        (_isLetter(_src[_i]) || _src[_i] == '!' || _isDigit(_src[_i]))) {
      _i++;
    }
    return _src.substring(start, _i);
  }

  List<_V> _rangeValues(String a, String b, [TablePayload? targetTable]) {
    final table = targetTable ?? _table;
    final cleanA = a.contains('!') ? a.split('!').last : a;
    final cleanB = b.contains('!') ? b.split('!').last : b;
    final (c1, r1) = _parseRef(cleanA);
    final (c2, r2) = _parseRef(cleanB);
    final cMin = min(c1, c2).toInt();
    final cMax = max(c1, c2).toInt();
    final rMin = min(r1, r2).toInt();
    final rMax = max(r1, r2).toInt();
    final values = <_V>[];
    for (int r = rMin; r <= rMax && r < table.rows.length; r++) {
      final row = table.rows[r];
      for (int c = cMin; c <= cMax && c < row.length; c++) {
        final raw = row[c].trim();
        final d = double.tryParse(raw);
        values.add(d != null ? _N(d) : _S(raw));
      }
    }
    return values;
  }

  (double, double) _parseRef(String s) {
    int i = 0;
    int col = 0;
    while (i < s.length && _isLetter(s[i])) {
      col = col * 26 + (s[i].toUpperCase().codeUnitAt(0) - 64);
      i++;
    }
    if (i == 0) throw const FormatException('no column');
    col -= 1;
    if (i >= s.length) throw const FormatException('no row');
    final row = int.parse(s.substring(i)) - 1;
    return (col.toDouble(), row.toDouble());
  }

  double _number() {
    final start = _i;
    while (_i < _src.length && (_isDigit(_src[_i]) || _src[_i] == '.')) {
      _i++;
    }
    return double.parse(_src.substring(start, _i));
  }

  String _stringLiteral(String quote) {
    _i++;
    final buf = StringBuffer();
    while (_i < _src.length && _src[_i] != quote) {
      final c = _src[_i];
      if (c == '\\' && _i + 1 < _src.length) {
        _i++;
        final next = _src[_i];
        switch (next) {
          case 'n':
            buf.write('\n');
          case 't':
            buf.write('\t');
          case '\\':
            buf.write('\\');
          case '"':
            buf.write('"');
          case "'":
            buf.write("'");
          default:
            buf.write(next);
        }
      } else {
        buf.write(c);
      }
      _i++;
    }
    if (_i >= _src.length) throw const FormatException('unterminated string');
    _i++;
    return buf.toString();
  }

  String _readIdentifier() {
    final start = _i;
    while (_i < _src.length && _isLetter(_src[_i])) {
      _i++;
    }
    while (_i < _src.length && _isDigit(_src[_i])) {
      _i++;
    }
    return _src.substring(start, _i);
  }

  void _skipWs() {
    while (_i < _src.length && _src[_i] == ' ') {
      _i++;
    }
  }

  bool _peek(String s) => _src.startsWith(s, _i);

  String _peekChar() => _i < _src.length ? _src[_i] : '\u0000';

  bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  bool _isLetter(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
  }
}
