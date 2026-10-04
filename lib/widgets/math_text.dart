import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Text with inline LaTeX between `$...$` (Korean outside, math inside).
///
/// Block markup (full renders only; one marker per line — see docs/problem-schema.md):
///   `$$…$$`                    가운데 수식 줄 (display)
///   `[[box]]` … `[[/box]]`      조건 상자
///   `[[center]]` … `[[/center]]` 가운데 정렬
///   `[[svg]]<svg…>[[/svg]]`     그림 (TeX 원문의 TikZ 를 옮긴 것)
///   `| a | b |`                표
class MathText extends StatelessWidget {
  const MathText(
    this.source, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.mathScale = 1.06,
    this.texStyle = false,
  });

  final String source;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final double mathScale;

  /// TeX 원문처럼: 글줄 안 수식은 text style (분수는 \dfrac 일 때만 크게).
  final bool texStyle;

  /// TeX 본문 글자 크기(pt) — 그림(pt 단위)을 글자 크기에 맞춰 키운다.
  static const double texBodyPt = 9.2;

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

  /// One-line form of block markup (previews): figures → [그림], boxes dropped, `$$x$$` → `$x$`.
  static String compact(String s) {
    if (!s.contains('[[') && !s.contains(r'$$')) return s;
    var t = s.replaceAll(RegExp(r'\[\[svg\]\][\s\S]*?\[\[/svg\]\]'), '[그림]');
    t = t.replaceAll(RegExp(r'\[\[/?(box|center)\]\]'), '');
    t = t.replaceAllMapped(RegExp(r'\$\$([\s\S]*?)\$\$'), (m) => '\$${m[1]}\$');
    return t.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
  }

  /// Plain-text rendering (for previews / lists): strips LaTeX commands and markup lightly.
  static String plain(String s) {
    var t = compact(s).replaceAll('**', '').replaceAll('__', '');
    t = t.replaceAll(RegExp(r'^\s*\|[-:| ]+\|\s*$', multiLine: true), '');
    t = t.replaceAll(RegExp(r'\s*\|\s*'), ' ').replaceAll(RegExp(r'\n{2,}'), '\n');
    t = t.replaceAll(r'$', '');
    t = t.replaceAllMapped(RegExp(r'\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}'), (m) => '${m[1]}/${m[2]}');
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

  static final RegExp _blockLine = RegExp(r'^\s*(\$\$|\[\[)');

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    // block layout only for full renders; previews flatten blocks
    if (maxLines != null) return _inline(compact(source), base);
    if (source.contains('[[') || source.contains(r'$$')) {
      final lines = source.split('\n');
      if (lines.any((l) => _blockLine.hasMatch(l))) return _structured(lines, base, textAlign);
    }
    if (source.contains('|')) {
      final lines = source.split('\n');
      if (lines.any((l) => _tableLine.hasMatch(l))) return _blocks(context, lines, base);
    }
    return _inline(source, base);
  }

  /// Lines with block markers → column of text runs, display math, boxes, centred parts and figures.
  Widget _structured(List<String> lines, TextStyle base, TextAlign align) {
    final fs = base.fontSize ?? 16;
    final children = <Widget>[];
    final run = <String>[];
    void flush() {
      if (run.isEmpty) return;
      final t = run.join('\n');
      run.clear();
      if (t.trim().isEmpty) return;
      final hasTable = t.split('\n').any((l) => _tableLine.hasMatch(l));
      children.add(hasTable
          ? Builder(builder: (c) => _blocks(c, t.split('\n'), base))
          : _inline(t, base, align: align));
    }

    var i = 0;
    while (i < lines.length) {
      final l = lines[i].trim();
      final open = RegExp(r'^\[\[(box|center)\]\]$').firstMatch(l);
      if (open != null) {
        // find the matching close (blocks may nest)
        final kind = open.group(1)!;
        var depth = 1;
        var j = i + 1;
        while (j < lines.length) {
          final t = lines[j].trim();
          if (t == '[[$kind]]') depth++;
          if (t == '[[/$kind]]' && --depth == 0) break;
          j++;
        }
        flush();
        final inner = lines.sublist(i + 1, j.clamp(i + 1, lines.length));
        if (kind == 'box') {
          children.add(Padding(
            padding: EdgeInsets.symmetric(vertical: fs * 0.3),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(fs * 0.62, fs * 0.36, fs * 0.62, fs * 0.36),
              decoration: BoxDecoration(border: Border.all(color: base.color ?? const Color(0xFF1B2A4A), width: 1.1)),
              child: _structured(inner, base, align),
            ),
          ));
        } else {
          children.add(SizedBox(width: double.infinity, child: _structured(inner, base, TextAlign.center)));
        }
        i = j + 1;
        continue;
      }
      if (l.startsWith('[[svg]]')) {
        flush();
        var svg = l.substring(7);
        var j = i;
        while (!svg.contains('[[/svg]]') && j + 1 < lines.length) {
          svg += '\n${lines[++j]}';
        }
        svg = svg.replaceFirst(RegExp(r'\[\[/svg\]\]\s*$'), '');
        children.add(_figure(svg, fs, align));
        i = j + 1;
        continue;
      }
      if (l.startsWith(r'$$') && l.endsWith(r'$$') && l.length > 4) {
        flush();
        children.add(_display(l.substring(2, l.length - 2), base));
        i++;
        continue;
      }
      if (l.startsWith('[[/')) {
        i++; // stray close
        continue;
      }
      run.add(lines[i]);
      i++;
    }
    flush();
    final cross = align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return Column(crossAxisAlignment: cross, mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _display(String tex, TextStyle base) {
    final fs = base.fontSize ?? 16;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: fs * 0.32),
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Math.tex(
              tex,
              mathStyle: MathStyle.display,
              textStyle: TextStyle(fontSize: fs * mathScale, color: base.color),
              onErrorFallback: (err) => Text(tex, style: base.copyWith(fontStyle: FontStyle.italic)),
            ),
          ),
        ),
      ),
    );
  }

  static final RegExp _svgSize = RegExp(r'<svg[^>]*?\swidth="([\d.]+)"[^>]*?\sheight="([\d.]+)"');

  Widget _figure(String svg, double fs, TextAlign align) {
    final m = _svgSize.firstMatch(svg);
    final k = fs / texBodyPt;
    final w = m == null ? null : double.parse(m.group(1)!) * k;
    final h = m == null ? null : double.parse(m.group(2)!) * k;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: fs * 0.3),
      child: Align(
        alignment: align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SvgPicture.string(svg, width: w, height: h, fit: BoxFit.contain),
        ),
      ),
    );
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
        // display-size fractions read better on a tablet; compact previews and TeX 원문 keep text size
        mathStyle: maxLines == null && !texStyle ? MathStyle.display : MathStyle.text,
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
