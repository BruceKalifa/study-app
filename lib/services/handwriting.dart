import 'package:flutter/foundation.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../ink/ink_model.dart';

enum HandwritingStatus { unknown, downloading, ready, unavailable }

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

  /// Returns candidate texts, best first (cleaned up for numeric answers).
  Future<List<String>> recognize(List<InkStroke> strokes, {double width = 0, double height = 0}) async {
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
      final out = <String>[];
      for (final c in cands) {
        final t = cleanAnswer(c.text);
        if (t.isNotEmpty && !out.contains(t)) out.add(t);
        if (out.length >= 4) break;
      }
      return out;
    } catch (e) {
      debugPrint('recognize failed: $e');
      return const [];
    }
  }

  /// Map look-alike letters to digits/symbols that make sense in a numeric answer.
  static String cleanAnswer(String raw) {
    var s = raw.trim().replaceAll(' ', '');
    const map = {
      'O': '0', 'o': '0', 'D': '0', 'Q': '0',
      'l': '1', 'I': '1', '|': '1', 'i': '1',
      'Z': '2', 'z': '2',
      'S': '5', 's': '5',
      'b': '6', 'G': '6',
      'q': '9', 'g': '9',
      'B': '8',
      'T': '7',
      '÷': '/', '—': '-', '–': '-', '_': '-',
      ',': '.',
    };
    // only remap when the string is mostly digits (avoid ruining text answers like "sqrt")
    final digitCount = s.runes.where((r) => r >= 48 && r <= 57).length;
    if (digitCount >= (s.length / 2).floor() || s.length <= 2) {
      final b = StringBuffer();
      for (final ch in s.split('')) {
        b.write(map[ch] ?? ch);
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
