// Expression evaluator shared by the variant generator, grader and calculator.
//
// Grammar (see docs/problem-schema.md):
//   expr    := term (('+' | '-') term)*
//   term    := unary (('*' | '/') unary)*
//   unary   := ('-' | '+') unary | power
//   power   := primary ('^' unary)?          // right-assoc, binds tighter than unary
//   primary := number | name | name '(' args ')' | '(' expr ')'
//
// Functions: sqrt abs sin cos tan (degrees) log (base 10) ln exp min max
// round(x[,n]) floor ceil. Constants: pi e.
import 'dart:math' as math;

import 'format.dart' show roundTo;

class ExprError implements Exception {
  final String message;
  ExprError(this.message);
  @override
  String toString() => 'ExprError: $message';
}

typedef _Eval = double Function(Map<String, double> vars);

enum _T { number, ident, op, lparen, rparen, comma, end }

class _Tok {
  final _T type;
  final String text;
  final int pos;
  final double value;
  const _Tok(this.type, this.text, this.pos, [this.value = 0]);
}

class Expr {
  Expr._();

  /// Evaluate an expression with the given variables.
  /// Throws [ExprError] on bad syntax / unknown names.
  static double eval(String source, [Map<String, double> vars = const {}]) {
    final f = _compile(source);
    return f(vars);
  }

  /// Returns true if the source parses (unknown variables are allowed).
  static bool isValid(String source) {
    try {
      _compile(source);
      return true;
    } on ExprError {
      return false;
    }
  }

  static final Map<String, _Eval> _cache = <String, _Eval>{};

  static _Eval _compile(String source) {
    final cached = _cache[source];
    if (cached != null) return cached;
    final parser = _Parser(_tokenize(source));
    final f = parser.parseAll();
    if (_cache.length > 2000) _cache.clear();
    _cache[source] = f;
    return f;
  }
}

bool _isDigit(int c) => c >= 48 && c <= 57;

bool _isIdentStart(int c) =>
    (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95;

bool _isIdentPart(int c) => _isIdentStart(c) || _isDigit(c);

List<_Tok> _tokenize(String s) {
  final toks = <_Tok>[];
  var i = 0;
  final n = s.length;
  while (i < n) {
    final c = s.codeUnitAt(i);
    // whitespace
    if (c == 32 || c == 9 || c == 10 || c == 13) {
      i++;
      continue;
    }
    // number: 12, 1.5, .5, 5., 1e3, 2.5E-4
    if (_isDigit(c) || (c == 46 && i + 1 < n && _isDigit(s.codeUnitAt(i + 1)))) {
      final start = i;
      while (i < n && _isDigit(s.codeUnitAt(i))) {
        i++;
      }
      if (i < n && s.codeUnitAt(i) == 46) {
        i++;
        while (i < n && _isDigit(s.codeUnitAt(i))) {
          i++;
        }
      }
      if (i < n && (s.codeUnitAt(i) == 101 || s.codeUnitAt(i) == 69)) {
        var j = i + 1;
        if (j < n && (s.codeUnitAt(j) == 43 || s.codeUnitAt(j) == 45)) {
          j++;
        }
        if (j < n && _isDigit(s.codeUnitAt(j))) {
          i = j;
          while (i < n && _isDigit(s.codeUnitAt(i))) {
            i++;
          }
        }
      }
      final text = s.substring(start, i);
      // Build a canonical form that double.parse surely accepts.
      var mantissa = text;
      var exponent = '';
      final eIdx = text.indexOf(RegExp('[eE]'));
      if (eIdx >= 0) {
        mantissa = text.substring(0, eIdx);
        exponent = text.substring(eIdx);
      }
      if (mantissa.startsWith('.')) mantissa = '0$mantissa';
      if (mantissa.endsWith('.')) mantissa = '${mantissa}0';
      final v = double.tryParse('$mantissa$exponent');
      if (v == null) {
        throw ExprError('잘못된 숫자 "$text" (위치 $start)');
      }
      toks.add(_Tok(_T.number, text, start, v));
      continue;
    }
    if (_isIdentStart(c)) {
      final start = i;
      while (i < n && _isIdentPart(s.codeUnitAt(i))) {
        i++;
      }
      toks.add(_Tok(_T.ident, s.substring(start, i), start));
      continue;
    }
    if (c == 43 || c == 45 || c == 42 || c == 47 || c == 94) {
      // + - * / ^
      toks.add(_Tok(_T.op, String.fromCharCode(c), i));
      i++;
    } else if (c == 40) {
      toks.add(_Tok(_T.lparen, '(', i));
      i++;
    } else if (c == 41) {
      toks.add(_Tok(_T.rparen, ')', i));
      i++;
    } else if (c == 44) {
      toks.add(_Tok(_T.comma, ',', i));
      i++;
    } else {
      throw ExprError('알 수 없는 문자 "${String.fromCharCode(c)}" (위치 $i)');
    }
  }
  toks.add(_Tok(_T.end, '', n));
  return toks;
}

const double _deg = math.pi / 180.0;

double _log10(double x) {
  final r = math.log(x) / math.ln10;
  if (r.isFinite) {
    final rr = r.roundToDouble();
    if ((r - rr).abs() < 1e-9 && math.pow(10, rr).toDouble() == x) return rr;
  }
  return r;
}

class _Parser {
  final List<_Tok> toks;
  int p = 0;
  _Parser(this.toks);

  _Tok get cur => toks[p];

  _Eval parseAll() {
    if (cur.type == _T.end) throw ExprError('빈 식');
    final e = parseExpr();
    if (cur.type != _T.end) {
      throw ExprError('예상치 못한 "${cur.text}" (위치 ${cur.pos})');
    }
    return e;
  }

  bool _isOp(String op) => cur.type == _T.op && cur.text == op;

  _Eval parseExpr() {
    var left = parseTerm();
    while (_isOp('+') || _isOp('-')) {
      final op = cur.text;
      p++;
      final right = parseTerm();
      final l = left;
      if (op == '+') {
        left = (v) => l(v) + right(v);
      } else {
        left = (v) => l(v) - right(v);
      }
    }
    return left;
  }

  _Eval parseTerm() {
    var left = parseUnary();
    while (_isOp('*') || _isOp('/')) {
      final op = cur.text;
      p++;
      final right = parseUnary();
      final l = left;
      if (op == '*') {
        left = (v) => l(v) * right(v);
      } else {
        left = (v) => l(v) / right(v);
      }
    }
    return left;
  }

  _Eval parseUnary() {
    if (_isOp('-')) {
      p++;
      final inner = parseUnary();
      return (v) => -inner(v);
    }
    if (_isOp('+')) {
      p++;
      return parseUnary();
    }
    return parsePower();
  }

  _Eval parsePower() {
    final base = parsePrimary();
    if (_isOp('^')) {
      p++;
      final exp = parseUnary(); // right-assoc: 2^3^2 = 2^(3^2); 2^-1 ok
      return (v) => math.pow(base(v), exp(v)).toDouble();
    }
    return base;
  }

  _Eval parsePrimary() {
    final t = cur;
    if (t.type == _T.number) {
      p++;
      final value = t.value;
      return (v) => value;
    }
    if (t.type == _T.lparen) {
      p++;
      final inner = parseExpr();
      if (cur.type != _T.rparen) {
        throw ExprError('")" 가 필요합니다 (위치 ${cur.pos})');
      }
      p++;
      return inner;
    }
    if (t.type == _T.ident) {
      p++;
      if (cur.type == _T.lparen) {
        p++;
        final args = <_Eval>[];
        if (cur.type != _T.rparen) {
          args.add(parseExpr());
          while (cur.type == _T.comma) {
            p++;
            args.add(parseExpr());
          }
        }
        if (cur.type != _T.rparen) {
          throw ExprError('")" 가 필요합니다 (위치 ${cur.pos})');
        }
        p++;
        return _makeCall(t.text, args, t.pos);
      }
      final name = t.text;
      return (v) {
        final x = v[name];
        if (x != null) return x;
        if (name == 'pi') return math.pi;
        if (name == 'e') return math.e;
        throw ExprError('알 수 없는 이름 "$name"');
      };
    }
    if (t.type == _T.end) throw ExprError('식이 끝났습니다');
    throw ExprError('예상치 못한 "${t.text}" (위치 ${t.pos})');
  }

  _Eval _makeCall(String name, List<_Eval> args, int pos) {
    final int minN;
    final int maxN;
    if (name == 'round') {
      minN = 1;
      maxN = 2;
    } else if (name == 'min' || name == 'max') {
      minN = 1;
      maxN = 64;
    } else if (_unary.contains(name)) {
      minN = 1;
      maxN = 1;
    } else {
      throw ExprError('알 수 없는 함수 "$name" (위치 $pos)');
    }
    if (args.length < minN || args.length > maxN) {
      throw ExprError('$name 의 인자 개수가 잘못되었습니다 (위치 $pos)');
    }
    final a = args[0];
    final _Eval? b = args.length > 1 ? args[1] : null;

    if (name == 'sqrt') return (v) => math.sqrt(a(v));
    if (name == 'abs') return (v) => a(v).abs();
    if (name == 'sin') return (v) => math.sin(a(v) * _deg);
    if (name == 'cos') return (v) => math.cos(a(v) * _deg);
    if (name == 'tan') return (v) => math.tan(a(v) * _deg);
    if (name == 'log') return (v) => _log10(a(v));
    if (name == 'ln') return (v) => math.log(a(v));
    if (name == 'exp') return (v) => math.exp(a(v));
    if (name == 'floor') return (v) => a(v).floorToDouble();
    if (name == 'ceil') return (v) => a(v).ceilToDouble();
    if (name == 'round') {
      return (v) {
        final x = a(v);
        final double nd = b?.call(v) ?? 0.0;
        if (!nd.isFinite || nd.abs() > 300) {
          throw ExprError('round 의 자릿수가 잘못되었습니다');
        }
        return roundTo(x, nd.round());
      };
    }
    final isMin = name == 'min';
    return (v) {
      var r = a(v);
      for (var i = 1; i < args.length; i++) {
        final x = args[i](v);
        if (x.isNaN || r.isNaN) {
          r = double.nan;
        } else if (isMin ? x < r : x > r) {
          r = x;
        }
      }
      return r;
    };
  }
}

const Set<String> _unary = <String>{
  'sqrt', 'abs', 'sin', 'cos', 'tan', 'log', 'ln', 'exp', 'floor', 'ceil', //
};
