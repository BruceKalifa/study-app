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
///   `[[cols:58:39]]` … `[[col]]` … `[[/cols]]`  나란히 (비율)
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
    t = t.replaceAll(RegExp(r'\[\[/?(box|center|cols[^\]]*|col)\]\]'), '');
    t = t.replaceAllMapped(RegExp(r'\$\$([\s\S]*?)\$\$'), (m) => '\$${m[1]}\$');
    return t.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
  }

  static const _fnNames =
      'arcsin|arccos|arctan|sinh|cosh|tanh|coth|sech|csch|sin|cos|tan|sec|csc|cot|log|ln|exp|lim|max|min|det|deg|arg|gcd';

  /// 수식(TeX) 을 그리기 전에 흔한 잘못 쓴 꼴을 고친다.
  ///  · `^(…)`·`_(…)` → `^{…}`·`_{…}` (그대로면 "(" 만 올라가서 tan^(-1) 처럼 보인다)
  ///  · 백슬래시 없이 쓴 함수 이름 + 첨자: `tan^{-1}` → `\tan^{-1}`
  ///  · `\tag{1}` → `(1)` (줄 안 수식에서는 지원하지 않아 통째로 깨진다)
  ///  · 짝이 안 맞는 `\left`·`\right` 는 빼고 괄호만 남긴다
  static String fixTex(String s) {
    var t = _parenScripts(s);
    t = t.replaceAllMapped(RegExp('(?<![\\\\A-Za-z{])($_fnNames)(?=\\s*[\\^_])'), (m) => '\\${m[1]}');
    t = t.replaceAllMapped(RegExp(r'\\tag\*?\{([^{}]*)\}'), (m) => '\\qquad(${m[1]})');
    final lefts = RegExp(r'\\left(?![a-zA-Z])').allMatches(t).length;
    final rights = RegExp(r'\\right(?![a-zA-Z])').allMatches(t).length;
    if (lefts != rights) {
      t = t.replaceAll(RegExp(r'\\(left|right)(?![a-zA-Z])\.?'), '');
    }
    return t;
  }

  static String _parenScripts(String s) {
    if (!s.contains('^(') && !s.contains('_(')) return s;
    final b = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if ((c == '^' || c == '_') && i + 1 < s.length && s[i + 1] == '(' && (i == 0 || s[i - 1] != '\\')) {
        var depth = 0, j = i + 1;
        for (; j < s.length; j++) {
          if (s[j] == '(') depth++;
          if (s[j] == ')' && --depth == 0) break;
        }
        if (j < s.length) {
          final inner = _parenScripts(s.substring(i + 2, j));
          // f^(n)·y^(4) 같은 "n계 도함수" 표기는 괄호를 살린다
          final keep = RegExp(r'^\s*([A-Za-z]|\d+|[ivx]+)\s*$').hasMatch(inner);
          b
            ..write(c)
            ..write('{')
            ..write(keep ? '($inner)' : inner)
            ..write('}');
          i = j + 1;
          continue;
        }
      }
      b.write(c);
      i++;
    }
    return b.toString();
  }

  /// `$` 밖에 글자 그대로 쓴 첨자 수식 (tan^(-1), x^2, e^(2x) …) → 수식 조각 `$…$`.
  static final RegExp _asciiPower = RegExp(
      r'(?<![\w\\$])((?:' + _fnNames + r')|[A-Za-z]|\d+(?:\.\d+)?|\))\^(\([^()]*\)|\{[^{}]*\}|-?[A-Za-z0-9]+)');

  @visibleForTesting
  static List<(bool, String)> asciiMath(String text) {
    if (!text.contains('^')) return [(false, text)];
    final out = <(bool, String)>[];
    var last = 0;
    for (final m in _asciiPower.allMatches(text)) {
      final base = m[1]!;
      if (base == ')') continue; // 괄호 묶음은 앞쪽까지 알 수 없어 그대로 둔다
      if (m.start > last) out.add((false, text.substring(last, m.start)));
      out.add((true, fixTex('$base^${m[2]}')));
      last = m.end;
    }
    if (last == 0) return [(false, text)];
    if (last < text.length) out.add((false, text.substring(last)));
    return out;
  }

  static const _sup = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    '-': '⁻', '+': '⁺', '=': '⁼', '(': '⁽', ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ', 'x': 'ˣ', 'k': 'ᵏ', 'T': 'ᵀ',
  };
  static const _sub = {
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
    '-': '₋', '+': '₊', 'n': 'ₙ', 'i': 'ᵢ', 'x': 'ₓ', 'k': 'ₖ', 'j': 'ⱼ', 'm': 'ₘ',
  };
  static String _script(String body, Map<String, String> table, String mark) {
    final t = body.replaceAll(' ', '');
    if (t.isNotEmpty && t.split('').every(table.containsKey)) return t.split('').map((c) => table[c]).join();
    return t.length == 1 ? '$mark$t' : '$mark($t)';
  }

  /// Plain-text rendering (for previews / lists): strips LaTeX commands and markup lightly.
  static String plain(String s) {
    var t = compact(s).replaceAll('**', '').replaceAll('__', '');
    t = t.replaceAll(RegExp(r'^\s*\|[-:| ]+\|\s*$', multiLine: true), '');
    t = t.replaceAll(RegExp(r'\s*\|\s*'), ' ').replaceAll(RegExp(r'\n{2,}'), '\n');
    t = fixTex(t.replaceAll(r'$', ''));
    t = t.replaceAllMapped(RegExp(r'\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}'), (m) => '${m[1]}/${m[2]}');
    // 함수 이름은 남기고 (\tan → tan), 첨자는 위·아래 글자로 (tan⁻¹, x², a₁)
    t = t.replaceAllMapped(RegExp('\\\\($_fnNames)(?![a-zA-Z])'), (m) => m[1]!);
    t = t.replaceAllMapped(RegExp(r'\\operatorname\{([^{}]*)\}'), (m) => m[1]!);
    t = t.replaceAllMapped(RegExp(r'\^\{([^{}]*)\}'), (m) => _script(m[1]!, _sup, '^'));
    t = t.replaceAllMapped(RegExp(r'\^(-?[0-9A-Za-z])'), (m) => _script(m[1]!, _sup, '^'));
    t = t.replaceAllMapped(RegExp(r'_\{([^{}]*)\}'), (m) => _script(m[1]!, _sub, '_'));
    t = t.replaceAllMapped(RegExp(r'_([0-9A-Za-z])'), (m) => _script(m[1]!, _sub, '_'));
    t = t.replaceAllMapped(RegExp(r'\\text\{([^{}]*)\}'), (m) => m[1] ?? '');
    t = t.replaceAllMapped(RegExp(r'\\sqrt\{([^{}]*)\}'), (m) => '√${m[1]}');
    const map = {
      r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±', r'\le': '≤', r'\ge': '≥', r'\ne': '≠',
      r'\approx': '≈', r'\theta': 'θ', r'\alpha': 'α', r'\beta': 'β', r'\lambda': 'λ', r'\omega': 'ω',
      r'\Delta': 'Δ', r'\pi': 'π', r'\mu': 'μ', r'\rho': 'ρ', r'\sigma': 'σ', r'\circ': '°', r'\Omega': 'Ω',
      r'\infty': '∞', r'\to': '→', r'\rightarrow': '→', r'\,': ' ', r'\left': '', r'\right': '',
      r'\neq': '≠', r'\leq': '≤', r'\geq': '≥', r'\cdots': '⋯', r'\ldots': '…', r'\dots': '…', r'\partial': '∂',
      r'\nabla': '∇', r'\int': '∫', r'\sum': 'Σ', r'\phi': 'φ', r'\varphi': 'φ', r'\epsilon': 'ε',
      r'\varepsilon': 'ε', r'\quad': ' ', r'\qquad': '  ', r'\;': ' ', r'\!': '',
    };
    // \le 가 \left 의 앞부분을 바꾸지 않게 명령어 경계에서만
    map.forEach((k, v) => t = t.replaceAll(RegExp(RegExp.escape(k) + (RegExp(r'[a-zA-Z]$').hasMatch(k) ? r'(?![a-zA-Z])' : '')), v));
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
      final cols = RegExp(r'^\[\[cols((?::\d+)*)\]\]$').firstMatch(l);
      if (cols != null) {
        var depth = 1;
        var j = i + 1;
        final parts = <List<String>>[[]];
        while (j < lines.length) {
          final t = lines[j].trim();
          if (t.startsWith('[[cols')) depth++;
          if (t == '[[/cols]]' && --depth == 0) break;
          if (t == '[[col]]' && depth == 1) {
            parts.add([]);
          } else {
            parts.last.add(lines[j]);
          }
          j++;
        }
        flush();
        final weights = [
          for (final w in cols.group(1)!.split(':').where((w) => w.isNotEmpty)) int.parse(w),
        ];
        children.add(Padding(
          padding: EdgeInsets.symmetric(vertical: fs * 0.2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var k = 0; k < parts.length; k++) ...[
              if (k > 0) SizedBox(width: fs * 0.8),
              Expanded(
                flex: k < weights.length ? weights[k] : 1,
                child: Align(
                  alignment: k == 0 ? Alignment.topLeft : Alignment.topRight,
                  child: _structured(parts[k], base, align),
                ),
              ),
            ],
          ]),
        ));
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
              fixTex(tex),
              mathStyle: MathStyle.display,
              textStyle: TextStyle(fontSize: fs * mathScale, color: base.color),
              // 그래도 못 그리면 TeX 명령어 대신 읽을 수 있는 글자로 (tan⁻¹x)
              onErrorFallback: (err) => Text(plain('\$$tex\$'), style: base),
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
    final pieces0 = [
      for (final (isMath, text) in parts) ...(isMath ? [(true, text)] : asciiMath(text)),
    ];
    for (final (isMath, text) in pieces0) {
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
        fixTex(text),
        // display-size fractions read better on a tablet; compact previews and TeX 원문 keep text size
        mathStyle: maxLines == null && !texStyle ? MathStyle.display : MathStyle.text,
        // only size + colour: weight/family from the surrounding text would switch KaTeX to upright glyphs
        textStyle: TextStyle(fontSize: (base.fontSize ?? 16) * mathScale, color: base.color),
        onErrorFallback: (err) => Text(plain('\$$text\$'), style: base),
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
