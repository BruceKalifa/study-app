// 복소수 식 계산 — 답안 채점용 ("3+4i", "-2i", "(1+√3i)/2" …).
//
// 입력은 Grader.normalize 를 거친 식 (√ 는 sqrt() 로, 곱셈은 * 로 풀려 있음).
// 문법은 expr.dart 와 같고 허수 단위 i 와 켤레 conj(), 크기 abs() 를 더 쓴다.
// 지원: + - * / ^(정수 지수는 정확히, 실수 지수는 극형식) sqrt(음수 포함) pi e i
import 'dart:math' as math;

class Cx {
  const Cx(this.re, this.im);
  final double re, im;

  static const zero = Cx(0, 0);
  static const one = Cx(1, 0);
  static const i = Cx(0, 1);

  bool get isFinite => re.isFinite && im.isFinite;
  double get abs => math.sqrt(re * re + im * im);

  Cx operator +(Cx o) => Cx(re + o.re, im + o.im);
  Cx operator -(Cx o) => Cx(re - o.re, im - o.im);
  Cx operator -() => Cx(-re, -im);
  Cx operator *(Cx o) => Cx(re * o.re - im * o.im, re * o.im + im * o.re);
  Cx operator /(Cx o) {
    final d = o.re * o.re + o.im * o.im;
    if (d == 0) return const Cx(double.nan, double.nan);
    return Cx((re * o.re + im * o.im) / d, (im * o.re - re * o.im) / d);
  }

  Cx get conj => Cx(re, -im);

  Cx sqrt() {
    if (im == 0) return re >= 0 ? Cx(math.sqrt(re), 0) : Cx(0, math.sqrt(-re));
    final r = abs;
    final a = math.sqrt((r + re) / 2);
    final b = math.sqrt((r - re) / 2);
    return Cx(a, im < 0 ? -b : b);
  }

  Cx pow(Cx e) {
    if (e.im == 0 && e.re == e.re.roundToDouble() && e.re.abs() <= 64) {
      var n = e.re.toInt().abs();
      var r = Cx.one;
      var b = this;
      while (n > 0) {
        if (n & 1 == 1) r = r * b;
        b = b * b;
        n >>= 1;
      }
      return e.re < 0 ? Cx.one / r : r;
    }
    if (re == 0 && im == 0) return e.re > 0 ? Cx.zero : const Cx(double.nan, double.nan);
    // 극형식: z^w = exp(w * ln z)
    final lnR = math.log(abs);
    final th = math.atan2(im, re);
    final xr = e.re * lnR - e.im * th;
    final xi = e.re * th + e.im * lnR;
    final m = math.exp(xr);
    return Cx(m * math.cos(xi), m * math.sin(xi));
  }

  /// 두 복소수가 오차 [tol] 안에서 같은가 (실수부·허수부를 따로 본다).
  bool near(Cx o, double tol) => (re - o.re).abs() <= tol && (im - o.im).abs() <= tol;

  @override
  String toString() => 'Cx($re, $im)';
}

class CxError implements Exception {
  CxError(this.message);
  final String message;
  @override
  String toString() => 'CxError: $message';
}

/// [source] 를 복소수로 계산한다. 못 읽으면 null.
Cx? evalComplex(String source) {
  try {
    final p = _CxParser(_lex(source));
    final v = p.parseAll();
    return v.isFinite ? v : null;
  } on CxError {
    return null;
  }
}

class _Tk {
  const _Tk(this.kind, this.text, [this.value = 0]);
  final String kind; // num | id | op | ( | ) | end
  final String text;
  final double value;
}

List<_Tk> _lex(String s) {
  final out = <_Tk>[];
  var k = 0;
  bool dig(int c) => c >= 48 && c <= 57;
  bool idStart(int c) => (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95;
  while (k < s.length) {
    final c = s.codeUnitAt(k);
    if (c == 32) {
      k++;
    } else if (dig(c) || (c == 46 && k + 1 < s.length && dig(s.codeUnitAt(k + 1)))) {
      final st = k;
      while (k < s.length && dig(s.codeUnitAt(k))) {
        k++;
      }
      if (k < s.length && s[k] == '.') {
        k++;
        while (k < s.length && dig(s.codeUnitAt(k))) {
          k++;
        }
      }
      final t = s.substring(st, k);
      final v = double.tryParse(t.startsWith('.') ? '0$t' : (t.endsWith('.') ? '${t}0' : t));
      if (v == null) throw CxError('숫자 "$t"');
      out.add(_Tk('num', t, v));
    } else if (idStart(c)) {
      final st = k;
      while (k < s.length && (idStart(s.codeUnitAt(k)) || dig(s.codeUnitAt(k)))) {
        k++;
      }
      out.add(_Tk('id', s.substring(st, k)));
    } else if ('+-*/^'.contains(s[k])) {
      out.add(_Tk('op', s[k]));
      k++;
    } else if (s[k] == '(' || s[k] == ')') {
      out.add(_Tk(s[k], s[k]));
      k++;
    } else {
      throw CxError('문자 "${s[k]}"');
    }
  }
  out.add(const _Tk('end', ''));
  return out;
}

class _CxParser {
  _CxParser(this.t);
  final List<_Tk> t;
  int p = 0;
  _Tk get cur => t[p];
  bool _op(String o) => cur.kind == 'op' && cur.text == o;

  Cx parseAll() {
    final v = _expr();
    if (cur.kind != 'end') throw CxError('남은 글자 "${cur.text}"');
    return v;
  }

  Cx _expr() {
    var l = _term();
    while (_op('+') || _op('-')) {
      final plus = cur.text == '+';
      p++;
      final r = _term();
      l = plus ? l + r : l - r;
    }
    return l;
  }

  Cx _term() {
    var l = _unary();
    while (_op('*') || _op('/')) {
      final mul = cur.text == '*';
      p++;
      final r = _unary();
      l = mul ? l * r : l / r;
    }
    return l;
  }

  Cx _unary() {
    if (_op('-')) {
      p++;
      return -_unary();
    }
    if (_op('+')) {
      p++;
      return _unary();
    }
    return _power();
  }

  Cx _power() {
    final b = _primary();
    if (_op('^')) {
      p++;
      return b.pow(_unary());
    }
    return b;
  }

  Cx _primary() {
    final tk = cur;
    if (tk.kind == 'num') {
      p++;
      return Cx(tk.value, 0);
    }
    if (tk.kind == '(') {
      p++;
      final v = _expr();
      if (cur.kind != ')') throw CxError('")" 필요');
      p++;
      return v;
    }
    if (tk.kind == 'id') {
      p++;
      final name = tk.text;
      if (cur.kind == '(') {
        p++;
        final a = _expr();
        if (cur.kind != ')') throw CxError('")" 필요');
        p++;
        switch (name) {
          case 'sqrt':
            return a.sqrt();
          case 'conj':
            return a.conj;
          case 'abs':
            return Cx(a.abs, 0);
          default:
            throw CxError('함수 $name');
        }
      }
      switch (name) {
        case 'i':
          return Cx.i;
        case 'pi':
          return const Cx(math.pi, 0);
        case 'e':
          return const Cx(math.e, 0);
        default:
          throw CxError('이름 $name');
      }
    }
    throw CxError('예상치 못한 "${tk.text}"');
  }
}
