import 'dart:math' as math;
import 'dart:ui';

import 'ink_model.dart';

/// 수식 한 줄을 읽어 값을 내는 아주 작은 계산기.
///
/// 쓸 수 있는 것: `+ - * / ^ ( )`, 암묵적 곱(`2x`, `3(x+1)`, `2sin x`),
/// `sin cos tan asin acos atan sinh cosh tanh sqrt abs ln log exp floor ceil round`,
/// 상수 `pi(π) e`, 변수 `x`. `log` 는 상용로그(밑 10), `ln` 은 자연로그.
class Expr {
  Expr._(this._root);
  final _Node _root;

  /// 수식 글귀 → [Expr]. 읽지 못하면 [FormatException].
  factory Expr.parse(String src) => Expr._(_Parser(src).parse());

  /// 읽지 못하면 null.
  static Expr? tryParse(String src) {
    try {
      return Expr.parse(src);
    } catch (_) {
      return null;
    }
  }

  double call(double x) => _root.eval(x);
}

/// `y = …`, `f(x) = …` 같은 머리말을 떼고 수식만 남긴다.
String stripFunctionPrefix(String src) {
  var s = src.trim();
  final m = RegExp(r'^\s*(y|f\s*\(\s*x\s*\)|g\s*\(\s*x\s*\)|h\s*\(\s*x\s*\))\s*=\s*', caseSensitive: false).firstMatch(s);
  if (m != null) s = s.substring(m.end);
  return s.trim();
}

// ───────────────────────── 파서 ─────────────────────────

abstract class _Node {
  double eval(double x);
}

class _Num implements _Node {
  _Num(this.v);
  final double v;
  @override
  double eval(double x) => v;
}

class _Var implements _Node {
  @override
  double eval(double x) => x;
}

class _Bin implements _Node {
  _Bin(this.op, this.a, this.b);
  final String op;
  final _Node a, b;
  @override
  double eval(double x) {
    final l = a.eval(x), r = b.eval(x);
    return switch (op) {
      '+' => l + r,
      '-' => l - r,
      '*' => l * r,
      '/' => l / r,
      '^' => math.pow(l, r).toDouble(),
      _ => double.nan,
    };
  }
}

class _Neg implements _Node {
  _Neg(this.a);
  final _Node a;
  @override
  double eval(double x) => -a.eval(x);
}

class _Fn implements _Node {
  _Fn(this.name, this.a);
  final String name;
  final _Node a;
  @override
  double eval(double x) {
    final v = a.eval(x);
    return switch (name) {
      'sin' => math.sin(v),
      'cos' => math.cos(v),
      'tan' => math.tan(v),
      'asin' => math.asin(v),
      'acos' => math.acos(v),
      'atan' => math.atan(v),
      'sinh' => (math.exp(v) - math.exp(-v)) / 2,
      'cosh' => (math.exp(v) + math.exp(-v)) / 2,
      'tanh' => (math.exp(2 * v) - 1) / (math.exp(2 * v) + 1),
      'sqrt' => math.sqrt(v),
      'abs' => v.abs(),
      'ln' => math.log(v),
      'log' => math.log(v) / math.ln10,
      'exp' => math.exp(v),
      'floor' => v.floorToDouble(),
      'ceil' => v.ceilToDouble(),
      'round' => v.roundToDouble(),
      _ => double.nan,
    };
  }
}

const _functions = {
  'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh',
  'sqrt', 'abs', 'ln', 'log', 'exp', 'floor', 'ceil', 'round',
};

class _Parser {
  _Parser(String src) : _s = _clean(src);
  final String _s;
  int _i = 0;

  static String _clean(String src) => src
      .replaceAll('−', '-') // 유니코드 빼기
      .replaceAll('×', '*')
      .replaceAll('·', '*')
      .replaceAll('÷', '/')
      .replaceAll('π', 'pi')
      .replaceAll('√', 'sqrt')
      .replaceAll(RegExp(r'\s+'), '');

  _Node parse() {
    if (_s.isEmpty) throw const FormatException('수식을 입력하세요');
    final n = _expr();
    if (_i < _s.length) throw FormatException('수식을 읽지 못했어요 (${_s.substring(_i)})');
    return n;
  }

  bool _eat(String c) {
    if (_i < _s.length && _s[_i] == c) {
      _i++;
      return true;
    }
    return false;
  }

  _Node _expr() {
    var n = _term();
    while (true) {
      if (_eat('+')) {
        n = _Bin('+', n, _term());
      } else if (_eat('-')) {
        n = _Bin('-', n, _term());
      } else {
        return n;
      }
    }
  }

  _Node _term() {
    var n = _power();
    while (true) {
      if (_eat('*')) {
        n = _Bin('*', n, _power());
      } else if (_eat('/')) {
        n = _Bin('/', n, _power());
      } else if (_i < _s.length && (_s[_i] == '(' || _isLetter(_s[_i]) || _isDigit(_s[_i]))) {
        // 암묵적 곱: 2x, 3(x+1), x sin x — 다만 숫자 바로 뒤 숫자는 아님
        n = _Bin('*', n, _power());
      } else {
        return n;
      }
    }
  }

  _Node _power() {
    final base = _unary();
    if (_eat('^')) return _Bin('^', base, _power()); // 오른쪽 결합
    return base;
  }

  // -x^2 는 -(x^2) 로 본다 (수학 관례)
  _Node _unary() {
    if (_eat('-')) return _Neg(_power());
    if (_eat('+')) return _power();
    return _atom();
  }

  _Node _atom() {
    if (_i >= _s.length) throw const FormatException('수식이 끝나지 않았어요');
    if (_eat('(')) {
      final n = _expr();
      if (!_eat(')')) throw const FormatException('괄호를 닫아 주세요');
      return n;
    }
    if (_isDigit(_s[_i]) || _s[_i] == '.') {
      final start = _i;
      while (_i < _s.length && (_isDigit(_s[_i]) || _s[_i] == '.')) {
        _i++;
      }
      final v = double.tryParse(_s.substring(start, _i));
      if (v == null) throw FormatException('숫자를 읽지 못했어요 (${_s.substring(start, _i)})');
      return _Num(v);
    }
    if (_isLetter(_s[_i])) {
      final start = _i;
      while (_i < _s.length && _isLetter(_s[_i])) {
        _i++;
      }
      final run = _s.substring(start, _i).toLowerCase();
      // 공백이 없어도 읽히게 앞에서부터 가장 긴 이름을 떼어 낸다 (lne → ln·e, 2sinx → sin·x)
      for (var len = run.length; len >= 1; len--) {
        final name = run.substring(0, len);
        if (_functions.contains(name)) {
          _i = start + len;
          return _Fn(name, _power());
        }
        if (name == 'pi') {
          _i = start + len;
          return _Num(math.pi);
        }
        if (len == 1 && (name == 'x' || name == 'e')) {
          _i = start + 1;
          return name == 'x' ? _Var() : _Num(math.e);
        }
      }
      throw FormatException('모르는 글자예요 (${run[0]})');
    }
    throw FormatException('수식을 읽지 못했어요 (${_s.substring(_i)})');
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  static bool _isLetter(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
  }
}

// ───────────────────────── 그리기 ─────────────────────────

/// 수학 좌표 ↔ 화면 좌표. [origin] 은 화면에서 원점이 놓이는 자리, [scale] 은 1 칸의 픽셀 수.
class PlotFrame {
  const PlotFrame({required this.origin, required this.scaleX, required this.scaleY});
  final Offset origin;
  final double scaleX, scaleY;

  Offset toScreen(double x, double y) => Offset(origin.dx + x * scaleX, origin.dy - y * scaleY);
  double xAt(double sx) => (sx - origin.dx) / scaleX;
}

/// 함수 그래프를 획으로 만든다. 정의되지 않는 곳·급히 치솟는 곳에서 끊어 여러 획이 된다.
List<InkStroke> plotFunction(
  Expr f, {
  required PlotFrame frame,
  required Rect clip,
  required int color,
  required double width,
  int samples = 600,
  int startedAt = 0,
}) {
  final x0 = frame.xAt(clip.left), x1 = frame.xAt(clip.right);
  final out = <InkStroke>[];
  var run = <Offset>[];
  double? prevY;
  void flush() {
    if (run.length >= 2) {
      out.add(InkStroke(
        id: newInkId(),
        tool: InkTool.pen,
        color: color,
        width: width,
        startedAt: startedAt + out.length,
        points: [
          for (var i = 0; i < run.length; i++) InkPoint(run[i].dx, run[i].dy, 0.55, i),
        ],
      ));
    }
    run = <Offset>[];
  }

  for (var i = 0; i <= samples; i++) {
    final x = x0 + (x1 - x0) * i / samples;
    double y;
    try {
      y = f(x);
    } catch (_) {
      y = double.nan;
    }
    if (!y.isFinite) {
      flush();
      prevY = null;
      continue;
    }
    final p = frame.toScreen(x, y);
    // 점근선: 한 칸 사이에 화면 높이만큼 튀면 끊는다
    if (prevY != null && (y - prevY).abs() * frame.scaleY > clip.height * 1.5) {
      flush();
    }
    if (p.dy < clip.top - clip.height || p.dy > clip.bottom + clip.height) {
      flush();
      prevY = y;
      continue;
    }
    run.add(Offset(p.dx, p.dy.clamp(clip.top - 4, clip.bottom + 4)));
    prevY = y;
  }
  flush();
  return out;
}

/// x·y 축과 눈금 (한 칸 = [step] ).
List<InkStroke> plotAxes({
  required PlotFrame frame,
  required Rect clip,
  required int color,
  required double width,
  double step = 1,
  int startedAt = 0,
}) {
  final out = <InkStroke>[];
  var k = 0;
  InkStroke seg(Offset a, Offset b) => InkStroke(
        id: newInkId(),
        tool: InkTool.pen,
        color: color,
        width: width,
        startedAt: startedAt + k++,
        points: [InkPoint(a.dx, a.dy, 0.55, 0), InkPoint(b.dx, b.dy, 0.55, 1)],
      );
  final o = frame.origin;
  if (o.dy >= clip.top && o.dy <= clip.bottom) out.add(seg(Offset(clip.left, o.dy), Offset(clip.right, o.dy)));
  if (o.dx >= clip.left && o.dx <= clip.right) out.add(seg(Offset(o.dx, clip.bottom), Offset(o.dx, clip.top)));
  const tick = 5.0;
  if (step > 0) {
    for (var i = 1; i * step * frame.scaleX < math.max(clip.right - o.dx, o.dx - clip.left) + 1; i++) {
      for (final s in [1, -1]) {
        final x = o.dx + s * i * step * frame.scaleX;
        if (x >= clip.left && x <= clip.right && o.dy >= clip.top && o.dy <= clip.bottom) {
          out.add(seg(Offset(x, o.dy - tick), Offset(x, o.dy + tick)));
        }
      }
    }
    for (var i = 1; i * step * frame.scaleY < math.max(clip.bottom - o.dy, o.dy - clip.top) + 1; i++) {
      for (final s in [1, -1]) {
        final y = o.dy + s * i * step * frame.scaleY;
        if (y >= clip.top && y <= clip.bottom && o.dx >= clip.left && o.dx <= clip.right) {
          out.add(seg(Offset(o.dx - tick, y), Offset(o.dx + tick, y)));
        }
      }
    }
  }
  return out;
}
