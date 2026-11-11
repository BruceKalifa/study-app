// 원본 PDF 를 그대로 보여 주는 교재 (문항 영역 · 개념 쪽). See docs/problem-schema.md "PDF 원본".
//
// 좌표는 PDF 포인트(1/72 inch), 쪽 왼쪽 위가 원점 — `pdftotext -bbox` 와 같다.

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// 쪽 위의 네모 (포인트, 왼쪽 위 원점).
class PdfBox {
  final double x0, y0, x1, y1;
  const PdfBox(this.x0, this.y0, this.x1, this.y1);

  double get width => x1 - x0;
  double get height => y1 - y0;
  bool get isValid => width > 0 && height > 0;

  static PdfBox? fromJson(Object? v) {
    if (v is! List || v.length != 4) return null;
    final b = PdfBox(_d(v[0]), _d(v[1]), _d(v[2]), _d(v[3]));
    return b.isValid ? b : null;
  }

  List<double> toJson() => [x0, y0, x1, y1];

  @override
  bool operator ==(Object other) => other is PdfBox && other.x0 == x0 && other.y0 == y0 && other.x1 == x1 && other.y1 == y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);
}

/// 문항 하나 = PDF 한 쪽의 한 영역. 객관식이면 ①~⑤ 글자 자리([choices], 쪽 좌표) — 그 자리를 눌러 고른다.
class PdfRegion {
  /// 교재 파일의 `pdfs` 안 PDF 이름.
  final String doc;

  /// 1부터.
  final int page;
  final PdfBox rect;
  final List<PdfBox> choices;

  const PdfRegion({required this.doc, required this.page, required this.rect, this.choices = const []});

  static PdfRegion? fromJson(Object? v) {
    if (v is! Map) return null;
    final doc = '${v['doc'] ?? ''}';
    final page = (v['page'] is num) ? (v['page'] as num).toInt() : int.tryParse('${v['page']}') ?? 0;
    final rect = PdfBox.fromJson(v['rect']);
    if (doc.isEmpty || page < 1 || rect == null) return null;
    final cs = v['choices'];
    return PdfRegion(
      doc: doc,
      page: page,
      rect: rect,
      choices: cs is List ? [for (final c in cs) PdfBox.fromJson(c)].whereType<PdfBox>().toList() : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'doc': doc,
        'page': page,
        'rect': rect.toJson(),
        if (choices.isNotEmpty) 'choices': [for (final c in choices) c.toJson()],
      };
}

/// 개념 쪽 위의 예제 — 누르면 [problem] 을 일반 풀이 화면으로 푼다.
class PdfExample {
  final int page;
  final PdfBox rect;
  final String problem;
  const PdfExample(this.page, this.rect, this.problem);

  static PdfExample? fromJson(Object? v) {
    if (v is! Map) return null;
    final rect = PdfBox.fromJson(v['rect']);
    final page = v['page'] is num ? (v['page'] as num).toInt() : 0;
    final problem = '${v['problem'] ?? ''}';
    if (rect == null || page < 1 || problem.isEmpty) return null;
    return PdfExample(page, rect, problem);
  }

  Map<String, dynamic> toJson() => {'page': page, 'rect': rect.toJson(), 'problem': problem};
}

/// 개념 하나 = PDF 의 연속된 쪽들 (책처럼 넘겨 읽는다).
class PdfPages {
  final String doc;
  final List<int> pages;

  /// 쪽마다 크기 (포인트) — 그리기 전에 자리를 잡는다. 비면 A4.
  final List<PdfBox> sizes;
  final List<PdfExample> examples;

  const PdfPages({required this.doc, required this.pages, this.sizes = const [], this.examples = const []});

  /// [i] 번째 쪽(0부터)의 가로·세로 (포인트).
  (double, double) sizeOf(int i) {
    if (i >= 0 && i < sizes.length) return (sizes[i].width, sizes[i].height);
    return (595.28, 841.89);
  }

  static PdfPages? fromJson(Object? v) {
    if (v is! Map) return null;
    final doc = '${v['doc'] ?? ''}';
    final ps = v['pages'];
    final pages = ps is List ? [for (final p in ps) if (p is num && p >= 1) p.toInt()] : <int>[];
    if (doc.isEmpty || pages.isEmpty) return null;
    final sz = v['sizes'];
    final ex = v['examples'];
    return PdfPages(
      doc: doc,
      pages: pages,
      sizes: sz is List ? [for (final s in sz) if (s is List && s.length == 2) PdfBox(0, 0, _d(s[0]), _d(s[1]))] : const [],
      examples: ex is List ? [for (final e in ex) PdfExample.fromJson(e)].whereType<PdfExample>().toList() : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'doc': doc,
        'pages': pages,
        if (sizes.isNotEmpty) 'sizes': [for (final s in sizes) [s.width, s.height]],
        if (examples.isNotEmpty) 'examples': [for (final e in examples) e.toJson()],
      };
}
