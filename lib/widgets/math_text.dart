import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Text with inline LaTeX between `$...$` (Korean outside, math inside).
class MathText extends StatelessWidget {
  const MathText(
    this.source, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.mathScale = 1.06,
  });

  final String source;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final double mathScale;

  static List<(bool, String)> split(String s) {
    final out = <(bool, String)>[];
    final b = StringBuffer();
    var inMath = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == r'\' && i + 1 < s.length && s[i + 1] == r'$') {
        b.write(r'$');
        i++;
        continue;
      }
      if (ch == r'$') {
        if (b.isNotEmpty) out.add((inMath, b.toString()));
        b.clear();
        inMath = !inMath;
        continue;
      }
      b.write(ch);
    }
    if (b.isNotEmpty) {
      // unbalanced $ → treat the tail as text
      out.add((false, inMath ? '\$${b.toString()}' : b.toString()));
    }
    return out;
  }

  /// Plain-text rendering (for previews / lists): strips LaTeX commands lightly.
  static String plain(String s) {
    var t = s.replaceAll(r'$', '');
    t = t.replaceAllMapped(RegExp(r'\\frac\{([^{}]*)\}\{([^{}]*)\}'), (m) => '${m[1]}/${m[2]}');
    t = t.replaceAllMapped(RegExp(r'\\text\{([^{}]*)\}'), (m) => m[1] ?? '');
    t = t.replaceAllMapped(RegExp(r'\\sqrt\{([^{}]*)\}'), (m) => '√${m[1]}');
    const map = {
      r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±', r'\le': '≤', r'\ge': '≥', r'\ne': '≠',
      r'\approx': '≈', r'\theta': 'θ', r'\alpha': 'α', r'\beta': 'β', r'\lambda': 'λ', r'\omega': 'ω',
      r'\Delta': 'Δ', r'\pi': 'π', r'\mu': 'μ', r'\rho': 'ρ', r'\sigma': 'σ', r'\circ': '°', r'\Omega': 'Ω',
      r'\infty': '∞', r'\to': '→', r'\rightarrow': '→', r'\,': ' ', r'\left': '', r'\right': '',
    };
    map.forEach((k, v) => t = t.replaceAll(k, v));
    t = t.replaceAll(RegExp(r'\\[a-zA-Z]+'), '');
    t = t.replaceAll(RegExp(r'[{}]'), '');
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final parts = split(source);
    final spans = <InlineSpan>[];
    for (final (isMath, text) in parts) {
      if (!isMath) {
        spans.add(TextSpan(text: text));
        continue;
      }
      final formula = Math.tex(
        text,
        // display-size fractions read better on a tablet; compact previews keep text size
        mathStyle: maxLines == null ? MathStyle.display : MathStyle.text,
        // only size + colour: weight/family from the surrounding text would switch KaTeX to upright glyphs
        textStyle: TextStyle(fontSize: (base.fontSize ?? 16) * mathScale, color: base.color),
        onErrorFallback: (err) => Text(text, style: base.copyWith(fontStyle: FontStyle.italic)),
      );
      // Break long formulas at relations/operators so they wrap like text;
      // any single piece that is still too wide is scaled down instead of overflowing.
      final pieces = formula.texBreak().parts;
      for (var i = 0; i < pieces.length; i++) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 1.5 : 0, right: i == pieces.length - 1 ? 1.5 : 0),
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: pieces[i]),
          ),
        ));
      }
    }
    return Text.rich(
      TextSpan(children: spans, style: base),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
