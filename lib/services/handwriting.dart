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
  Future<List<String>> recognize(List<InkStroke> strokes,
      {double width = 0, double height = 0, AnswerShape shape = AnswerShape.other}) async {
    final r = _recognizer;
    if (r == null || strokes.isEmpty) return const [];
    try {
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
      return rank([for (final c in cands) c.text], shape: shape);
    } catch (e) {
      debugPrint('recognize failed: $e');
      return const [];
    }
  }

  /// Raw recognizer outputs (best first) → cleaned candidates: every output is read in each plausible way
  /// (e.g. "l" as 1 or as i), and the ones that look like the expected kind of answer come first.
  @visibleForTesting
  static List<String> rank(List<String> raws, {AnswerShape shape = AnswerShape.other, int limit = 6}) {
    final scored = <(String, int, int)>[];
    final seen = <String>{};
    for (var k = 0; k < raws.length && k < 10; k++) {
      for (final t in variants(raws[k], shape: shape)) {
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

  static final RegExp _numericChars = RegExp(r'^[0-9+\-*/^().√π±]+$');
  static final RegExp _complexChars = RegExp(r'^[0-9+\-*/^().√πi±]+$');

  static bool _looksLike(String t, AnswerShape shape) => switch (shape) {
        AnswerShape.numeric => _numericChars.hasMatch(t),
        AnswerShape.complex => _complexChars.hasMatch(t),
        AnswerShape.other => true,
      };

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
  static List<String> variants(String raw, {AnswerShape shape = AnswerShape.other}) {
    if (shape == AnswerShape.complex) {
      // 허수단위: i 로 읽는 쪽과 숫자 1 로 읽는 쪽을 둘 다 낸다 (i 가 있는 쪽이 앞)
      final asI = cleanAnswer(raw.replaceAll(RegExp(r'[lI|jJıíì!¡]'), 'i'), shape: shape);
      final asOne = cleanAnswer(raw, shape: shape, keepI: false);
      return asI == asOne ? [asI] : [asI, asOne];
    }
    return [cleanAnswer(raw, shape: shape)];
  }

  /// Map look-alike letters to digits/symbols that make sense in a numeric answer.
  /// A lowercase i is kept ("2+i" is a complex number, not "2+1") unless [keepI] is false.
  static String cleanAnswer(String raw, {AnswerShape shape = AnswerShape.other, bool keepI = true}) {
    var s = raw.trim().replaceAll(' ', '');
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
      ',': '.',
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
    return s;
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
