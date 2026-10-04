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

  /// Plain-text rendering (for previews / lists): strips LaTeX commands and markup lightly.
  static String plain(String s) {
    var t = s.replaceAll('**', '').replaceAll('__', '');
    t = t.replaceAll(RegExp(r'^\s*\|[-:| ]+\|\s*$', multiLine: true), '');
    t = t.replaceAll(RegExp(r'\s*\|\s*'), ' ').replaceAll(RegExp(r'\n{2,}'), '\n');
    t = t.replaceAll(r'$', '');
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

  static final RegExp _tableLine = RegExp(r'^\s*\|');
  static final RegExp _ruleLine = RegExp(r'^\s*\|?\s*:?-{2,}');

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    // block layout (tables) only for full renders; previews flatten tables
    if (maxLines == null && source.contains('|')) {
      final lines = source.split('\n');
      if (lines.any((l) => _tableLine.hasMatch(l))) return _blocks(context, lines, base);
    }
    return _inline(source, base);
  }

  Widget _blocks(BuildContext context, List<String> lines, TextStyle base) {
    final children = <Widget>[];
    final text = <String>[];
    final table = <String>[];
    void flushText() {
      if (text.isEmpty) return;
      final t = text.join('\n');
      text.clear();
      if (t.trim().isEmpty) return;
      children.add(_inline(t, base));
    }

    void flushTable() {
      if (table.isEmpty) return;
      children.add(Padding(
        padding: EdgeInsets.symmetric(vertical: (base.fontSize ?? 16) * 0.5),
        child: _table(table, base),
      ));
      table.clear();
    }

    for (final l in lines) {
      if (_tableLine.hasMatch(l)) {
        flushText();
        table.add(l);
      } else {
        flushTable();
        text.add(l);
      }
    }
    flushText();
    flushTable();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }

  static List<String> _cells(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.trim()).toList();
  }

  Widget _table(List<String> rows, TextStyle base) {
    var header = false;
    final data = <List<String>>[];
    for (var i = 0; i < rows.length; i++) {
      if (_ruleLine.hasMatch(rows[i]) && !rows[i].replaceAll(RegExp(r'[|\-:\s]'), '').isNotEmpty) {
        if (i == 1) header = true;
        continue;
      }
      data.add(_cells(rows[i]));
    }
    final cols = data.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    if (cols == 0) return const SizedBox();
    final line = BorderSide(color: base.color ?? const Color(0xFF1B2A4A), width: 1);
    final thin = BorderSide(color: (base.color ?? const Color(0xFF1B2A4A)).withValues(alpha: 0.35), width: 0.8);
    final cellStyle = base.copyWith(height: 1.35, fontSize: (base.fontSize ?? 16) * 0.92);
    return Table(
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(top: line, bottom: line, horizontalInside: thin, verticalInside: thin),
      children: [
        for (var r = 0; r < data.length; r++)
          TableRow(
            decoration: BoxDecoration(color: header && r == 0 ? const Color(0x0F1B2A4A) : null),
            children: [
              for (var c = 0; c < cols; c++)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: (base.fontSize ?? 16) * 0.5, vertical: (base.fontSize ?? 16) * 0.32),
                  child: Center(
                    child: _inline(c < data[r].length ? data[r][c] : '',
                        header && r == 0 ? cellStyle.copyWith(fontWeight: FontWeight.w700) : cellStyle,
                        align: TextAlign.center),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  static final RegExp _marks = RegExp(r'(\*\*|__)');

  Widget _inline(String src, TextStyle base, {TextAlign? align}) {
    final parts = split(src);
    final spans = <InlineSpan>[];
    var bold = false, under = false;
    TextStyle? cur() => bold || under
        ? TextStyle(
            fontWeight: bold ? FontWeight.w700 : null,
            decoration: under ? TextDecoration.underline : null,
            decorationThickness: under ? 1.6 : null,
          )
        : null;
    for (final (isMath, text) in parts) {
      if (!isMath) {
        var last = 0;
        for (final m in _marks.allMatches(text)) {
          if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: cur()));
          if (m.group(0) == '**') {
            bold = !bold;
          } else {
            under = !under;
          }
          last = m.end;
        }
        if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: cur()));
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
      textAlign: align ?? textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
