// Grading of keypad / handwriting answers.
import 'dart:math' as math;

import 'expr.dart';
import 'problem.dart';

class GradeResult {
  final bool correct;

  /// The answer as understood by the grader (normalized form), or the raw
  /// trimmed input when it could not be understood.
  final String given;

  /// The expected answer (choice number or value, without unit).
  final String expected;

  /// Optional explanation, e.g. why the input could not be read.
  final String? note;

  const GradeResult({
    required this.correct,
    required this.given,
    required this.expected,
    this.note,
  });

  @override
  String toString() =>
      'GradeResult(correct: $correct, given: $given, expected: $expected'
      '${note == null ? '' : ', note: $note'})';
}

class _Operand {
  final String text;
  final int end;
  const _Operand(this.text, this.end);
}

enum _K { number, ident, lparen, rparen, other }

class _Piece {
  final _K kind;
  final String text;
  const _Piece(this.kind, this.text);
}

const Set<String> _functionNames = <String>{
  'sqrt', 'abs', 'sin', 'cos', 'tan', 'log', 'ln', 'exp', //
  'min', 'max', 'round', 'floor', 'ceil',
};

const String _circled = '①②③④⑤⑥⑦⑧⑨';
const String _circledNeg = '❶❷❸❹❺❻❼❽❾';

bool _isDigitCh(String c) {
  final u = c.codeUnitAt(0);
  return u >= 48 && u <= 57;
}

bool _isLetterCh(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 97 && u <= 122) || (u >= 65 && u <= 90) || u == 95;
}

bool _isSpaceRune(int r) =>
    r == 0x20 ||
    r == 0x09 ||
    r == 0x0A ||
    r == 0x0D ||
    r == 0xA0 ||
    r == 0x3000 ||
    (r >= 0x2000 && r <= 0x200B) ||
    r == 0x202F ||
    r == 0x205F ||
    r == 0xFEFF;

class Grader {
  Grader._();

  /// Grades [input] against problem [p].
  static GradeResult grade(Problem p, String input) {
    if (p.type == ProblemType.choice) return _gradeChoice(p, input);
    return _gradeShort(p, input);
  }

  static GradeResult _gradeChoice(Problem p, String input) {
    final expectedIdx = _parseChoice(p.answer);
    final expected = expectedIdx?.toString() ?? p.answer.trim();
    final raw = input.trim();
    if (raw.isEmpty) {
      return GradeResult(
          correct: false, given: '', expected: expected, note: '답을 입력하지 않았습니다');
    }
    final givenIdx = _parseChoice(raw);
    if (givenIdx == null) {
      return GradeResult(
        correct: false,
        given: raw,
        expected: expected,
        note: '선택지 번호(1~5)로 답하세요',
      );
    }
    final correct = expectedIdx != null
        ? givenIdx == expectedIdx
        : givenIdx.toString() == expected;
    return GradeResult(
        correct: correct, given: givenIdx.toString(), expected: expected);
  }

  static GradeResult _gradeShort(Problem p, String input) {
    final expectedRaw = _stripUnit(p.answer.trim(), p.answerUnit);
    final givenRaw = _stripUnit(input.trim(), p.answerUnit);
    final givenNorm = normalize(givenRaw);
    if (givenNorm == null) {
      return GradeResult(
        correct: false,
        given: '',
        expected: p.answer.trim(),
        note: '답을 입력하지 않았습니다',
      );
    }
    final e = parseNumber(expectedRaw);
    if (e != null) {
      final g = _evalNumber(givenNorm);
      if (g == null) {
        return GradeResult(
          correct: false,
          given: givenNorm,
          expected: p.answer.trim(),
          note: '숫자(또는 식)로 인식할 수 없습니다',
        );
      }
      final tol = math.max(p.tolerance, 1e-9 * math.max(1.0, e.abs()));
      final correct = (g - e).abs() <= tol;
      return GradeResult(
          correct: correct, given: givenNorm, expected: p.answer.trim());
    }
    final expNorm = normalize(expectedRaw) ?? expectedRaw;
    final correct = givenNorm.toLowerCase() == expNorm.toLowerCase();
    return GradeResult(
        correct: correct, given: givenNorm, expected: p.answer.trim());
  }

  /// Parses a choice answer: "3", "③", "3번", " 3 ", "(3)", "3)".
  /// Letters are not accepted. Returns null when not a single digit 1-9.
  static int? parseChoice(String input) => _parseChoice(input);

  static int? _parseChoice(String input) {
    final buf = StringBuffer();
    for (final r in input.trim().runes) {
      final ch = String.fromCharCode(r);
      final ci = _circled.indexOf(ch);
      if (ci >= 0) {
        buf.write(ci + 1);
        continue;
      }
      final cn = _circledNeg.indexOf(ch);
      if (cn >= 0) {
        buf.write(cn + 1);
        continue;
      }
      if (r >= 0xFF10 && r <= 0xFF19) {
        buf.write(r - 0xFF10);
        continue;
      }
      if (_isSpaceRune(r) ||
          ch == '(' ||
          ch == ')' ||
          ch == '（' ||
          ch == '）' ||
          ch == '번' ||
          ch == '.') {
        continue;
      }
      buf.write(ch);
    }
    final t = buf.toString();
    if (t.length == 1 && _isDigitCh(t) && t != '0') return int.parse(t);
    return null;
  }

  /// Removes a trailing unit equal to [unit] (whitespace/case-insensitive,
  /// "^2" and "²" treated alike).
  static String _stripUnit(String s, String? unit) {
    if (unit == null) return s;
    final u0 = unit.replaceAll(RegExp(r'\s+'), '');
    if (u0.isEmpty) return s;
    final compact = s.replaceAll(RegExp(r'\s+'), '');
    final variants = <String>{
      u0,
      u0.replaceAll('²', '^2').replaceAll('³', '^3'),
      u0.replaceAll('^2', '²').replaceAll('^3', '³'),
      u0.replaceAll('·', '*').replaceAll('⋅', '*'),
    };
    final lower = compact.toLowerCase();
    for (final u in variants) {
      if (u.isEmpty) continue;
      if (lower.length > u.length && lower.endsWith(u.toLowerCase())) {
        return compact.substring(0, compact.length - u.length);
      }
    }
    return s;
  }

  /// Normalizes handwriting/keypad input to a parseable form; returns null
  /// if empty.
  static String? normalize(String input) {
    final mapped = StringBuffer();
    for (final r in input.runes) {
      if (_isSpaceRune(r)) continue;
      final ch = String.fromCharCode(r);
      if (r >= 0xFF10 && r <= 0xFF19) {
        mapped.write(r - 0xFF10);
        continue;
      }
      switch (ch) {
        case '−':
        case '–':
        case '—':
        case '‐':
        case '‑':
        case '﹣':
        case '－':
          mapped.write('-');
        case '＋':
          mapped.write('+');
        case '×':
        case '✕':
        case '✖':
        case '·':
        case '⋅':
        case '∙':
        case '＊':
          mapped.write('*');
        case '÷':
        case '∕':
        case '／':
          mapped.write('/');
        case '．':
          mapped.write('.');
        case '，':
          mapped.write(',');
        case '（':
        case '[':
        case '{':
          mapped.write('(');
        case '）':
        case ']':
        case '}':
          mapped.write(')');
        case '²':
          mapped.write('^2');
        case '³':
          mapped.write('^3');
        case 'π':
        case 'Π':
          mapped.write('pi');
        default:
          mapped.write(ch);
      }
    }
    var s = mapped.toString();
    if (s.isEmpty) return null;

    // Drop commas used as thousand separators (only outside parentheses so
    // that function arguments like max(1,2) survive).
    final noCommas = StringBuffer();
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '(') depth++;
      if (c == ')' && depth > 0) depth--;
      if (c == ',' && depth == 0) continue;
      noCommas.write(c);
    }
    s = noCommas.toString();
    if (s.isEmpty) return null;

    if (s.contains('√')) s = _expandSqrt(s);
    s = _insertImplicitMul(s);
    return s.isEmpty ? null : s;
  }

  /// Parses a number or simple expression ("-3/2", "2√3", "1,200").
  static double? parseNumber(String s) {
    final n = normalize(s);
    if (n == null) return null;
    return _evalNumber(n);
  }

  static double? _evalNumber(String normalized) {
    try {
      final v = Expr.eval(normalized);
      return v.isFinite ? v : null;
    } on ExprError {
      return null;
    } on FormatException {
      return null;
    }
  }

  // "√3" -> "sqrt(3)", "√(12)" -> "sqrt(12)", "√√16" -> "sqrt(sqrt(16))"
  static String _expandSqrt(String s) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '√') {
        final op = _sqrtOperand(s, i + 1);
        if (op == null) {
          out.write(c);
          i++;
        } else {
          out.write(op.text);
          i = op.end;
        }
      } else {
        out.write(c);
        i++;
      }
    }
    return out.toString();
  }

  /// Parses the operand of a √ starting at [j]; returns "sqrt(...)" text.
  static _Operand? _sqrtOperand(String s, int j) {
    if (j >= s.length) return null;
    final c = s[j];
    if (c == '(') {
      final close = _matchParen(s, j);
      final inner = s.substring(j + 1, close < 0 ? s.length : close);
      final end = close < 0 ? s.length : close + 1;
      return _Operand('sqrt(${_expandSqrt(inner)})', end);
    }
    if (_isDigitCh(c) || c == '.') {
      var k = j;
      while (k < s.length && (_isDigitCh(s[k]) || s[k] == '.')) {
        k++;
      }
      return _Operand('sqrt(${s.substring(j, k)})', k);
    }
    if (_isLetterCh(c)) {
      var k = j;
      while (k < s.length && (_isLetterCh(s[k]) || _isDigitCh(s[k]))) {
        k++;
      }
      var text = s.substring(j, k);
      if (k < s.length && s[k] == '(') {
        final close = _matchParen(s, k);
        final end = close < 0 ? s.length : close + 1;
        text = '$text(${_expandSqrt(s.substring(k + 1, close < 0 ? s.length : close))})';
        k = end;
      }
      return _Operand('sqrt($text)', k);
    }
    if (c == '√') {
      final inner = _sqrtOperand(s, j + 1);
      if (inner == null) return null;
      return _Operand('sqrt(${inner.text})', inner.end);
    }
    return null;
  }

  /// Index of the ')' matching the '(' at [open], or -1.
  static int _matchParen(String s, int open) {
    var depth = 0;
    for (var k = open; k < s.length; k++) {
      if (s[k] == '(') depth++;
      if (s[k] == ')') {
        depth--;
        if (depth == 0) return k;
      }
    }
    return -1;
  }

  /// Inserts '*' for implicit multiplication: "2pi" -> "2*pi",
  /// "2sqrt(3)" -> "2*sqrt(3)", "3(4)" -> "3*(4)", ")(" -> ")*(".
  static String _insertImplicitMul(String s) {
    final pieces = <_Piece>[];
    var i = 0;
    final n = s.length;
    while (i < n) {
      final c = s[i];
      if (_isDigitCh(c) || (c == '.' && i + 1 < n && _isDigitCh(s[i + 1]))) {
        final start = i;
        while (i < n && _isDigitCh(s[i])) {
          i++;
        }
        if (i < n && s[i] == '.') {
          i++;
          while (i < n && _isDigitCh(s[i])) {
            i++;
          }
        }
        if (i < n && (s[i] == 'e' || s[i] == 'E')) {
          var j = i + 1;
          if (j < n && (s[j] == '+' || s[j] == '-')) j++;
          if (j < n && _isDigitCh(s[j])) {
            i = j;
            while (i < n && _isDigitCh(s[i])) {
              i++;
            }
          }
        }
        pieces.add(_Piece(_K.number, s.substring(start, i)));
      } else if (_isLetterCh(c)) {
        final start = i;
        while (i < n && (_isLetterCh(s[i]) || _isDigitCh(s[i]))) {
          i++;
        }
        final word = s.substring(start, i);
        final lower = word.toLowerCase();
        final canonical =
            (_functionNames.contains(lower) || lower == 'pi') ? lower : word;
        pieces.add(_Piece(_K.ident, canonical));
      } else if (c == '(') {
        pieces.add(const _Piece(_K.lparen, '('));
        i++;
      } else if (c == ')') {
        pieces.add(const _Piece(_K.rparen, ')'));
        i++;
      } else {
        pieces.add(_Piece(_K.other, c));
        i++;
      }
    }
    final out = StringBuffer();
    for (var k = 0; k < pieces.length; k++) {
      final cur = pieces[k];
      if (k > 0 && _needsMul(pieces[k - 1], cur)) out.write('*');
      out.write(cur.text);
    }
    return out.toString();
  }

  static bool _needsMul(_Piece a, _Piece b) {
    final aIsValue = a.kind == _K.number ||
        a.kind == _K.rparen ||
        (a.kind == _K.ident && !_functionNames.contains(a.text.toLowerCase()));
    if (!aIsValue) return false;
    if (b.kind == _K.ident || b.kind == _K.lparen) return true;
    // "pi2" -> pi*2 ; "(2)3" -> (2)*3 ; number-number is never adjacent
    if (b.kind == _K.number) return a.kind != _K.number;
    return false;
  }
}
