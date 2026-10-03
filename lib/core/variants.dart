// Variant (변형문제) generation from a problem's template.
import 'dart:math' as math;

import 'expr.dart';
import 'format.dart';
import 'problem.dart';

class VariantError implements Exception {
  final String message;
  VariantError(this.message);
  @override
  String toString() => 'VariantError: $message';
}

/// Multipliers tried (in order) when a distractor collides with the answer or
/// another distractor.
const List<double> _fixFactors = <double>[
  1.5, 0.5, 2, 3, 0.25, -1, 4, 0.75, 1.25, 5, 10, 0.1, -2, -0.5, 2.5, 6,
];

double _pickParam(String name, ParamSpec spec, math.Random rnd) {
  final values = spec.values;
  if (values != null && values.isNotEmpty) {
    return values[rnd.nextInt(values.length)];
  }
  final min = spec.min;
  final max = spec.max;
  if (min == null && max == null) {
    throw VariantError('매개변수 "$name" 에 min/max 또는 values 가 없습니다');
  }
  if (min == null) return max!;
  if (max == null || max <= min) return min;
  double step = spec.step ?? 1.0;
  if (!(step > 0)) step = 1.0;
  final count = ((max - min) / step + 1e-9).floor() + 1;
  if (count <= 1) return min;
  final k = rnd.nextInt(count > 1 << 30 ? 1 << 30 : count);
  return roundTo(min + k * step, 10);
}

double _eval(String expr, Map<String, double> vars, String where) {
  try {
    return Expr.eval(expr, vars);
  } on ExprError catch (e) {
    throw VariantError('$where 식 "$expr" 계산 실패: ${e.message}');
  }
}

final RegExp _placeholder = RegExp(r'\[\[(=?)(.*?)\]\]');

/// Replaces `[[name]]` with the parameter value and `[[=expr]]` with the
/// computed value (fmtNum, 3 decimals).
String _substitute(String text, Map<String, double> vars) {
  if (!text.contains('[[')) return text;
  return text.replaceAllMapped(_placeholder, (m) {
    final isExpr = (m.group(1) ?? '') == '=';
    final body = (m.group(2) ?? '').trim();
    if (body.isEmpty) return m.group(0) ?? '';
    if (!isExpr) {
      final v = vars[body];
      if (v != null) return fmtNum(v);
    }
    return fmtNum(_eval(body, vars, '치환'));
  });
}

/// Deterministic for (base.id, seed): uses dart:math Random(seed).
Problem generateVariant(Problem base, int seed) {
  final t = base.template;
  if (t == null) {
    throw VariantError('${base.id}: template 이 없습니다');
  }
  final rnd = math.Random(seed);

  // 1. pick parameters satisfying every `require` expression (> 0)
  Map<String, double>? vars;
  for (var attempt = 0; attempt < 200; attempt++) {
    final candidate = <String, double>{};
    for (final e in t.params.entries) {
      candidate[e.key] = _pickParam(e.key, e.value, rnd);
    }
    var ok = true;
    for (final r in t.require) {
      if (r.trim().isEmpty) continue;
      final v = _eval(r, candidate, 'require');
      if (!(v > 0)) {
        ok = false;
        break;
      }
    }
    if (ok) {
      vars = candidate;
      break;
    }
  }
  if (vars == null) {
    throw VariantError('${base.id}: require 조건을 만족하는 값을 찾지 못했습니다');
  }
  final env = vars;

  // 2. text substitution
  final stem = _substitute(t.stem, env);
  final solution = _substitute(t.solution ?? base.solution, env);
  final hintSrc = t.hint ?? base.hint;
  final hint = hintSrc == null ? null : _substitute(hintSrc, env);
  final boxItems = List<String>.unmodifiable(
      base.boxItems.map((b) => _substitute(b, env)));

  // 3. answer
  final round = t.round;
  var answerValue = _eval(t.answer, env, 'answer');
  if (!answerValue.isFinite) {
    throw VariantError('${base.id}: 정답 값이 유한하지 않습니다');
  }
  double tolerance;
  String answer;
  if (round != null) {
    answerValue = roundTo(answerValue, round);
    answer = fmtNum(answerValue, maxDecimals: round < 0 ? 0 : round);
    tolerance = math.pow(10, -round).toDouble();
  } else {
    answer = fmtNum(answerValue);
    tolerance = base.tolerance;
    // The stored string lost precision (e.g. 1/3 -> "0.333"): accept the
    // displayed value as well as the exact one.
    final shown = double.tryParse(answer);
    if (shown != null &&
        (shown - answerValue).abs() > 1e-12 &&
        tolerance < 5e-4) {
      tolerance = 5e-4;
    }
  }

  // 4. choices
  var choices = const <String>[];
  if (base.type == ProblemType.choice) {
    final exprs = t.choiceExprs;
    if (exprs == null || exprs.isEmpty) {
      throw VariantError('${base.id}: 객관식 템플릿에 choiceExprs 가 없습니다');
    }
    final decimals = round ?? 2;
    final shownDecimals = decimals < 0 ? 0 : decimals;
    String key(double v) =>
        fmtNum(roundTo(v, decimals), maxDecimals: shownDecimals);

    final correct = roundTo(_eval(exprs[0], env, 'choiceExprs[0]'), decimals);
    if (!correct.isFinite) {
      throw VariantError('${base.id}: 정답 선택지 값이 유한하지 않습니다');
    }
    final values = <double>[correct];
    final seen = <String>{key(correct)};
    for (var i = 1; i < 5; i++) {
      double v = double.nan;
      if (i < exprs.length) {
        try {
          v = roundTo(Expr.eval(exprs[i], env), decimals);
        } on ExprError {
          v = double.nan;
        }
      }
      if (!v.isFinite || seen.contains(key(v))) {
        v = double.nan;
        for (final k in _fixFactors) {
          final c = roundTo(correct * k, decimals);
          if (c.isFinite && !seen.contains(key(c))) {
            v = c;
            break;
          }
        }
        if (v.isNaN) {
          // correct == 0 (or extreme): additive fallback, always terminates.
          for (var j = 1; j <= 10000; j++) {
            final c = roundTo(correct + j, decimals);
            if (!seen.contains(key(c))) {
              v = c;
              break;
            }
          }
        }
      }
      values.add(v);
      seen.add(key(v));
    }
    final order = <int>[0, 1, 2, 3, 4]..shuffle(rnd);
    choices = List<String>.unmodifiable(order.map((i) {
      final text = t.choiceFormat.replaceAll('[[v]]', key(values[i]));
      return _substitute(text, env);
    }));
    answer = '${order.indexOf(0) + 1}';
  }

  return Problem(
    id: '${base.id}~v$seed',
    subjectId: base.subjectId,
    subjectName: base.subjectName,
    unit: base.unit,
    topic: base.topic,
    stem: stem,
    answer: answer,
    solution: solution,
    difficulty: base.difficulty,
    type: base.type,
    boxItems: boxItems,
    choices: choices,
    answerUnit: base.answerUnit,
    hint: hint,
    tolerance: tolerance,
    tags: base.tags,
    template: null,
    variantOf: base.id,
    variantSeed: seed,
    custom: base.custom,
  );
}

/// Convenience: [n] variants with distinct seeds derived from [seedBase].
/// Seeds that would produce a problem identical to an earlier one are
/// skipped (up to 20*n seeds are tried), so fewer than [n] may be returned
/// when the parameter space is small.
List<Problem> generateVariants(Problem base, int n, {int seedBase = 1}) {
  final out = <Problem>[];
  if (n <= 0) return out;
  final seen = <String>{};
  final maxTries = n * 20;
  for (var i = 0; i < maxTries && out.length < n; i++) {
    final v = generateVariant(base, seedBase + i);
    final sig = '${v.stem}\u0000${v.answer}\u0000${v.choices.join('\u0001')}';
    if (seen.add(sig)) out.add(v);
  }
  return out;
}
