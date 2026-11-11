import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../ink/ink_model.dart';

enum HandwritingStatus { unknown, downloading, ready, unavailable }

/// 정답이 어떻게 생겼나 (필기를 읽을 때만 쓴다): 숫자·분수·√·π / 복소수(i 포함) / 그 밖.
enum AnswerShape { numeric, complex, other }

/// On-device handwriting recognition (Google ML Kit Digital Ink) for answers.
class Handwriting {
  Handwriting._();
  static final Handwriting instance = Handwriting._();

  static const String language = 'en-US'; // digits, fractions, decimals, symbols

  final ValueNotifier<HandwritingStatus> status = ValueNotifier(HandwritingStatus.unknown);
  mlkit.DigitalInkRecognizer? _recognizer;
  Future<void>? _preparing;

  /// Make sure the model is downloaded (≈ 20 MB, once). Safe to call many times.
  Future<void> prepare() {
    return _preparing ??= _prepare();
  }

  Future<void> _prepare() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) {
      status.value = HandwritingStatus.unavailable;
      return;
    }
    try {
      final mm = mlkit.DigitalInkRecognizerModelManager();
      var ok = await mm.isModelDownloaded(language);
      if (!ok) {
        status.value = HandwritingStatus.downloading;
        ok = await mm.downloadModel(language, isWifiRequired: false);
      }
      if (ok) {
        _recognizer = mlkit.DigitalInkRecognizer(languageCode: language);
        status.value = HandwritingStatus.ready;
      } else {
        status.value = HandwritingStatus.unavailable;
        _preparing = null; // allow retry later
      }
    } catch (e) {
      debugPrint('handwriting prepare failed: $e');
      status.value = HandwritingStatus.unavailable;
      _preparing = null;
    }
  }

  /// Returns candidate texts, best first. [shape] is what the answer is *expected to look like*
  /// (숫자 / 복소수 / 그 밖) — it only tells how to read look-alike letters, never what the value is.
  /// [list]: 정답이 쉼표로 이은 여러 값이다 (쉼표를 소수점으로 바꾸지 않는다).
  Future<List<String>> recognize(List<InkStroke> strokes,
      {double width = 0, double height = 0, AnswerShape shape = AnswerShape.other, bool list = false}) async {
    final r = _recognizer;
    if (r == null || strokes.isEmpty) return const [];
    try {
      final whole = [
        if (shape != AnswerShape.other) ...await _readSigned(r, strokes, shape: shape, list: list),
        ...await _read(r, strokes, width: width, height: height),
      ];
      // 분수를 위아래로 쓴 경우 (분자 / 가로줄 / 분모): 한 줄로 읽으면 "34" 처럼 되므로 따로 읽어 잇는다
      final f = splitFraction(strokes);
      if (f != null && shape != AnswerShape.other) {
        Future<List<String>> part(List<InkStroke> ss) async => ss.isEmpty
            ? const ['']
            : [
                for (final t in [...await _readSigned(r, ss, shape: shape, list: list), ...await _read(r, ss)])
                  cleanAnswer(t, shape: shape, keepComma: list)
              ];
        final combos = combineFraction(
          await part(f.before),
          await part(f.numerator),
          await part(f.denominator),
          await part(f.after),
        );
        return rank([...combos, ...whole], shape: shape, list: list);
      }
      return rank(whole, shape: shape, list: list);
    } catch (e) {
      debugPrint('recognize failed: $e');
      return const [];
    }
  }

  Future<List<String>> _read(mlkit.DigitalInkRecognizer r, List<InkStroke> strokes,
      {double width = 0, double height = 0}) async {
    final ink = mlkit.Ink();
    final ordered = [...strokes]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    for (final s in ordered) {
      final st = mlkit.Stroke();
      for (final p in s.points) {
        st.points.add(mlkit.StrokePoint(x: p.x, y: p.y, t: s.startedAt + p.t));
      }
      ink.strokes.add(st);
    }
    final ctx = width > 0 && height > 0
        ? mlkit.DigitalInkRecognitionContext(writingArea: mlkit.WritingArea(width: width, height: height))
        : null;
    final cands = await r.recognize(ink, context: ctx);
    return [for (final c in cands) c.text];
  }

  /// 부호(+ − =)와 허수단위 i 는 모양이 뚜렷하니 획 모양으로 직접 찾고, 그 사이 숫자 덩어리만 인식기에 맡긴다.
  /// 한 줄로 통째 읽으면 "-3i+45" 가 "-31+45" 처럼 i 가 1, + 가 t·1 로 읽히기 쉽다.
  /// 부호를 하나도 못 찾으면 빈 목록 (통째 읽은 것만 쓴다).
  Future<List<String>> _readSigned(mlkit.DigitalInkRecognizer r, List<InkStroke> strokes,
      {required AnswerShape shape, bool list = false}) async {
    final tokens = tokenize(strokes, findI: shape == AnswerShape.complex);
    if (tokens == null) return const [];
    final parts = <List<String>>[];
    for (final t in tokens) {
      if (t.op != null) {
        parts.add([t.op!]);
        continue;
      }
      final raws = await _read(r, t.strokes);
      final c = <String>[];
      // 덩어리는 숫자부터 (i 는 이미 따로 찾았다), 복소수 답이면 l·I 를 i 로 읽은 것도 뒤에
      for (final raw in raws.take(4)) {
        final n = cleanAnswer(raw, shape: AnswerShape.numeric, keepComma: list);
        if (n.isNotEmpty && !c.contains(n)) c.add(n);
      }
      if (shape == AnswerShape.complex) {
        for (final raw in raws.take(2)) {
          for (final v in variants(raw, shape: shape, list: list)) {
            if (v.isNotEmpty && !c.contains(v)) c.add(v);
          }
        }
      }
      if (c.isNotEmpty) parts.add(c);
    }
    return combineParts(parts);
  }

  /// 획들 → 왼쪽부터 [InkToken] (부호 / 숫자 덩어리). 부호가 하나도 없으면 null.
  /// + : 거의 수평인 획과 거의 수직인 획이 서로의 가운데쯤에서 엇갈린 것.
  /// i : 작은 점 바로 아래의 짧은 세로획 ([findI] 일 때만).
  /// − : 다른 획과 좌우로 겹치지 않는 수평 획 (5 의 윗줄·7 의 가로줄·√ 의 지붕·분수 줄은 겹친다).
  /// = : 서로 겹친 수평 획 둘.
  @visibleForTesting
  static List<InkToken>? tokenize(List<InkStroke> strokes, {bool findI = true}) {
    final ss = [for (final s in strokes) if (s.points.isNotEmpty) s];
    if (ss.isEmpty) return null;
    final box = {for (final s in ss) s: _boxOf(s)};
    final hs = [for (final s in ss) box[s]!.height]..sort();
    final lineH = math.max(hs[math.min(hs.length - 1, (hs.length * 0.75).floor())], 8.0);

    bool flat(Rect b) => b.width >= lineH * 0.25 && b.height <= math.max(b.width * 0.3, lineH * 0.12);
    bool tall(Rect b) => b.height >= lineH * 0.25 && b.width <= b.height * 0.45;
    bool dot(Rect b) => math.max(b.width, b.height) <= math.max(lineH * 0.25, 3.0);

    final used = <InkStroke>{};
    final ops = <(String, Rect)>[];

    // + 
    for (final a in ss) {
      if (used.contains(a) || !flat(box[a]!)) continue;
      final ba = box[a]!;
      for (final v in ss) {
        if (identical(v, a) || used.contains(v) || !tall(box[v]!)) continue;
        final bv = box[v]!;
        final ratio = ba.width / bv.height;
        if (ratio < 0.35 || ratio > 2.8 || bv.height > lineH * 1.4) continue;
        final cx = bv.center.dx, cy = ba.center.dy;
        if (cx < ba.left + ba.width * 0.15 || cx > ba.right - ba.width * 0.15) continue;
        if (cy < bv.top + bv.height * 0.2 || cy > bv.bottom - bv.height * 0.2) continue;
        used..add(a)..add(v);
        ops.add(('+', ba.expandToInclude(bv)));
        break;
      }
    }
    // i
    if (findI) {
      for (final t in ss) {
        if (used.contains(t)) continue;
        final bt = box[t]!;
        if (bt.height < lineH * 0.25 || bt.height > lineH * 1.25 || bt.width > bt.height * 0.6) continue;
        InkStroke? best;
        var bestD = double.infinity;
        for (final d in ss) {
          if (identical(d, t) || used.contains(d)) continue;
          final bd = box[d]!;
          if (!dot(bd) || math.max(bd.width, bd.height) > bt.height * 0.6) continue;
          final dx = (bd.center.dx - bt.center.dx).abs();
          final gap = bt.top - bd.bottom;
          if (dx > math.max(bt.height * 0.35, bt.width) || bd.center.dy > bt.top + bt.height * 0.1) continue;
          if (gap > bt.height * 0.9) continue;
          final dist = dx + gap.abs();
          if (dist < bestD) {
            bestD = dist;
            best = d;
          }
        }
        if (best != null) {
          used..add(t)..add(best);
          ops.add(('i', bt.expandToInclude(box[best]!)));
        }
      }
    }
    // − and =
    final rest = [for (final s in ss) if (!used.contains(s)) s];
    if (rest.isNotEmpty) {
      var top = double.infinity, bottom = -double.infinity;
      for (final s in rest) {
        top = math.min(top, box[s]!.top);
        bottom = math.max(bottom, box[s]!.bottom);
      }
      double overlap(Rect a, Rect b) => math.max(0, math.min(a.right, b.right) - math.max(a.left, b.left));
      final flats = [
        for (final s in rest)
          if (flat(box[s]!) && box[s]!.width <= lineH * 2.5) s
      ];
      final taken = <InkStroke>{};
      for (final m in flats) {
        if (taken.contains(m)) continue;
        final bm = box[m]!;
        InkStroke? twin;
        var clash = false;
        for (final o in rest) {
          if (identical(o, m)) continue;
          final bo = box[o]!;
          if (overlap(bm, bo) <= bm.width * 0.25) continue;
          if (twin == null && flats.contains(o) && !taken.contains(o) && overlap(bm, bo) >= math.min(bm.width, bo.width) * 0.5) {
            twin = o;
          } else {
            clash = true;
            break;
          }
        }
        if (clash) continue;
        if (twin != null) {
          taken..add(m)..add(twin);
          ops.add(('=', bm.expandToInclude(box[twin]!)));
        } else if (rest.length == 1 || (bm.center.dy >= top - lineH * 0.2 && bm.center.dy <= bottom + lineH * 0.2)) {
          taken.add(m);
          ops.add(('-', bm));
        }
      }
      used.addAll(taken);
    }
    if (ops.isEmpty) return null;

    // 부호 사이의 획들을 왼쪽부터 덩어리로
    ops.sort((a, b) => a.$2.center.dx.compareTo(b.$2.center.dx));
    final groups = List.generate(ops.length + 1, (_) => <InkStroke>[]);
    for (final s in ss) {
      if (used.contains(s)) continue;
      final cx = box[s]!.center.dx;
      var k = 0;
      while (k < ops.length && ops[k].$2.center.dx < cx) {
        k++;
      }
      groups[k].add(s);
    }
    return [
      for (var k = 0; k <= ops.length; k++) ...[
        if (groups[k].isNotEmpty) InkToken.strokes(groups[k]),
        if (k < ops.length) InkToken.op(ops[k].$1),
      ]
    ];
  }

  static Rect _boxOf(InkStroke s) {
    var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    for (final p in s.points) {
      x0 = math.min(x0, p.x);
      y0 = math.min(y0, p.y);
      x1 = math.max(x1, p.x);
      y1 = math.max(y1, p.y);
    }
    return Rect.fromLTRB(x0, y0, x1, y1);
  }

  /// 부분마다의 후보 (좋은 것부터) → 이어 붙인 후보들, 앞 후보들의 합이 작은 것부터.
  @visibleForTesting
  static List<String> combineParts(List<List<String>> parts, {int limit = 6}) {
    if (parts.isEmpty) return const [];
    final ps = [for (final p in parts) p.take(3).toList()];
    var acc = <(String, int)>[('', 0)];
    for (final p in ps) {
      final next = [
        for (final a in acc)
          for (var j = 0; j < p.length; j++) ('${a.$1}${p[j]}', a.$2 + j)
      ];
      // 점수가 같으면 앞 조각의 순서대로 (정렬이 순서를 지키게)
      final order = [for (var k = 0; k < next.length; k++) k]
        ..sort((x, y) => next[x].$2 != next[y].$2 ? next[x].$2.compareTo(next[y].$2) : x.compareTo(y));
      acc = [for (final k in order.take(24)) next[k]];
    }
    final out = <String>[];
    for (final a in acc) {
      if (!out.contains(a.$1)) out.add(a.$1);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 획들이 위아래로 쓴 분수인지 본다: 가로줄 하나와 그 위(분자)·아래(분모)에 획이 있으면 나눈다.
  /// 줄 왼쪽·오른쪽 획(− 부호, π 따위)은 [FractionSplit.before] / [FractionSplit.after].
  @visibleForTesting
  static FractionSplit? splitFraction(List<InkStroke> strokes) {
    if (strokes.length < 3) return null;
    Rect box(InkStroke s) {
      var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
      for (final p in s.points) {
        x0 = math.min(x0, p.x);
        y0 = math.min(y0, p.y);
        x1 = math.max(x1, p.x);
        y1 = math.max(y1, p.y);
      }
      return Rect.fromLTRB(x0, y0, x1, y1);
    }

    final boxes = {for (final s in strokes) s: box(s)};
    FractionSplit? best;
    var bestW = 0.0;
    for (final bar in strokes) {
      final b = boxes[bar]!;
      if (b.width < 14 || b.height > math.max(6.0, b.width * 0.22)) continue; // 가로줄
      final lo = b.left - b.width * 0.15, hi = b.right + b.width * 0.15;
      final top = <InkStroke>[], bottom = <InkStroke>[], before = <InkStroke>[], after = <InkStroke>[];
      for (final s in strokes) {
        if (identical(s, bar)) continue;
        final c = boxes[s]!.center;
        if (c.dx >= lo && c.dx <= hi && c.dy < b.center.dy - 2) {
          top.add(s);
        } else if (c.dx >= lo && c.dx <= hi && c.dy > b.center.dy + 2) {
          bottom.add(s);
        } else if (c.dx < lo) {
          before.add(s);
        } else if (c.dx > hi) {
          after.add(s);
        } else {
          // 줄과 같은 높이 한가운데 (= 의 다른 줄 같은 것) → 분수가 아님
          top.clear();
          break;
        }
      }
      if (top.isEmpty || bottom.isEmpty) continue;
      if (b.width > bestW) {
        bestW = b.width;
        best = FractionSplit(before, top, bottom, after);
      }
    }
    return best;
  }

  /// 앞·분자·분모·뒤 후보 → "앞(분자)/(분모)뒤" 후보들 (좋은 것부터, 각 부분 앞의 몇 개만).
  @visibleForTesting
  static List<String> combineFraction(List<String> before, List<String> num, List<String> den, List<String> after) {
    String wrap(String t) => RegExp(r'^[0-9.√π]+$').hasMatch(t) || RegExp(r'^\(.*\)$').hasMatch(t) ? t : '($t)';
    final out = <String>[];
    final seen = <String>{};
    final pre = before.take(2).toList(), nn = num.take(3).toList(), dd = den.take(3).toList(), post = after.take(2).toList();
    for (var score = 0; score <= 6; score++) {
      for (var a = 0; a < pre.length; a++) {
        for (var i = 0; i < nn.length; i++) {
          for (var j = 0; j < dd.length; j++) {
            for (var z = 0; z < post.length; z++) {
              if (a + i + j + z != score) continue;
              if (nn[i].isEmpty || dd[j].isEmpty) continue;
              var p = pre[a];
              if (RegExp(r'^[-_—–−]+$').hasMatch(p)) p = '-';
              final t = '$p${wrap(nn[i])}/${wrap(dd[j])}${post[z]}';
              if (seen.add(t)) out.add(t);
            }
          }
        }
      }
    }
    return out;
  }

  /// Raw recognizer outputs (best first) → cleaned candidates: every output is read in each plausible way
  /// (e.g. "l" as 1 or as i), and the ones that look like the expected kind of answer come first.
  @visibleForTesting
  static List<String> rank(List<String> raws, {AnswerShape shape = AnswerShape.other, int limit = 6, bool list = false}) {
    final scored = <(String, int, int)>[];
    final seen = <String>{};
    for (var k = 0; k < raws.length && k < 16; k++) {
      for (final t in variants(raws[k], shape: shape, list: list)) {
        if (t.isEmpty || !seen.add(t)) continue;
        var score = k;
        if (!_looksLike(t, shape)) score += 100;
        if (shape == AnswerShape.complex && !t.contains('i')) score += 40; // a complex answer has an i
        scored.add((t, score, scored.length));
      }
    }
    scored.sort((x, y) => x.$2 != y.$2 ? x.$2.compareTo(y.$2) : x.$3.compareTo(y.$3));
    return [for (final e in scored.take(limit)) e.$1];
  }

  static final RegExp _numericChars = RegExp(r'^[0-9+\-*/^().,√π±]+$');
  static final RegExp _complexChars = RegExp(r'^[0-9+\-*/^().,√πi±]+$');

  static bool _looksLike(String t, AnswerShape shape) => switch (shape) {
        AnswerShape.numeric => _numericChars.hasMatch(t),
        AnswerShape.complex => _complexChars.hasMatch(t),
        AnswerShape.other => true,
      };

  /// 정답이 쉼표로 이은 여러 값인지 (예: "1,3", "-2, 5").
  static bool isListAnswer(String answer) => answer.contains(',');

  /// What the *expected answer* looks like — used only to read the handwriting, never to check it.
  static AnswerShape shapeOf(String answer) {
    final a = answer.replaceAll(RegExp(r'\s'), '');
    if (a.isEmpty) return AnswerShape.other;
    if (_numericChars.hasMatch(a)) return AnswerShape.numeric;
    if (a.contains('i') && _complexChars.hasMatch(a)) return AnswerShape.complex;
    return AnswerShape.other;
  }

  /// The ways one recognizer output can be read, most likely first.
  @visibleForTesting
  static List<String> variants(String raw, {AnswerShape shape = AnswerShape.other, bool list = false}) {
    if (shape == AnswerShape.complex) {
      // 허수단위: i 로 읽는 쪽과 숫자 1 로 읽는 쪽을 둘 다 낸다 (i 가 있는 쪽이 앞)
      final asI = cleanAnswer(raw.replaceAll(RegExp(r'[lI|jJıíì!¡]'), 'i'), shape: shape, keepComma: list);
      final asOne = cleanAnswer(raw, shape: shape, keepI: false, keepComma: list);
      return asI == asOne ? [asI] : [asI, asOne];
    }
    return [cleanAnswer(raw, shape: shape, keepComma: list)];
  }

  /// Map look-alike letters to digits/symbols that make sense in a numeric answer.
  /// A lowercase i is kept ("2+i" is a complex number, not "2+1") unless [keepI] is false.
  static String cleanAnswer(String raw,
      {AnswerShape shape = AnswerShape.other, bool keepI = true, bool keepComma = false}) {
    var s = raw.trim().replaceAll(' ', '');
    // 숫자 답에서 빠지는 군더더기: 끝의 마침표, "답:" · "=" 로 시작하는 것
    if (shape != AnswerShape.other) {
      s = s.replaceFirst(RegExp(r'^(답|ans|Ans|A)?[:=]'), '');
      s = s.replaceFirst(RegExp(r'[.,]$'), '');
    }
    const map = {
      'O': '0', 'o': '0', 'D': '0', 'Q': '0',
      'l': '1', 'I': '1', '|': '1', 'L': '1',
      'Z': '2', 'z': '2',
      'E': '3',
      'A': '4',
      'S': '5', 's': '5',
      'b': '6', 'G': '6',
      'T': '7',
      'B': '8',
      'q': '9', 'g': '9',
      '÷': '/', '—': '-', '–': '-', '_': '-', '−': '-', '×': '*', '·': '*',
    };
    // √ and π are not in the en-US model: they come back as V / v / r and TT / n / T
    s = s.replaceAllMapped(RegExp(r'(^|[\d)])[Vv√](?=[\d(])'), (m) => '${m[1]}√');
    s = s.replaceAll(RegExp(r'TT|∏|Π'), 'π');
    s = s.replaceAllMapped(RegExp(r'(\d)n$'), (m) => '${m[1]}π');
    // an answer that is expected to be a number never has letters: always remap.
    // otherwise only when the string is mostly digits (avoid ruining text answers like "sqrt")
    final digitCount = s.runes.where((r) => r >= 48 && r <= 57).length;
    final numeric = shape != AnswerShape.other;
    if (numeric || digitCount >= (s.length / 2).floor() || s.length <= 2) {
      final b = StringBuffer();
      for (final ch in s.split('')) {
        if (ch == 'i') {
          // 숫자 답에는 허수단위가 없으니 1 로, 복소수·그 밖의 답에서는 i 그대로
          final asI = shape == AnswerShape.other || (shape == AnswerShape.complex && keepI);
          b.write(asI ? 'i' : '1');
        } else {
          b.write(map[ch] ?? ch);
        }
      }
      s = b.toString();
    }
    // 쉼표: 여러 값을 묻는 답이면 그대로, 아니면 아래로 찍힌 소수점
    if (!keepComma) s = s.replaceAll(',', '.');
    return s;
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}

/// 한 줄 답을 나눈 조각: 부호(+ − = i) 하나, 또는 그 사이 숫자 덩어리의 획들.
class InkToken {
  const InkToken.op(String this.op) : strokes = const [];
  const InkToken.strokes(this.strokes) : op = null;
  final String? op;
  final List<InkStroke> strokes;
  @override
  String toString() => op ?? '[${strokes.map((s) => s.id).join(',')}]';
}

/// 위아래로 쓴 분수를 나눈 획들.
class FractionSplit {
  const FractionSplit(this.before, this.numerator, this.denominator, this.after);
  final List<InkStroke> before, numerator, denominator, after;
}
