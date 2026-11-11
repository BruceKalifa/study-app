import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_model.dart';
import '../ink/ink_toolbar.dart';
import '../ink/shape_hint.dart';
import '../pdf/pdf_view.dart';
import 'solve_screen.dart';

/// 개념책 — 원본 PDF 쪽을 책처럼 넘겨 읽고, 그 위에 필기·형광펜.
/// 태블릿 가로는 두 쪽 펼침, 그 밖에는 한 쪽씩. 예제를 누르면 일반 풀이 화면으로 푼다.
/// 필기는 PDF 쪽마다 따로 저장해서, 펼침·한 쪽 보기를 오가도 같은 자리에 남는다.
class ConceptBookScreen extends StatefulWidget {
  const ConceptBookScreen({super.key, required this.concepts, this.index = 0, this.workbookId, this.color});

  /// 원본 PDF 가 있는 개념들 (책 순서).
  final List<Concept> concepts;
  final int index;
  final String? workbookId;
  final Color? color;

  static Future<void> open(BuildContext context,
      {required List<Concept> concepts, int index = 0, String? workbookId, Color? color}) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConceptBookScreen(concepts: concepts, index: index, workbookId: workbookId, color: color),
    ));
  }

  @override
  State<ConceptBookScreen> createState() => _ConceptBookScreenState();
}

/// 책의 한 쪽.
class BookPage {
  BookPage(this.concept, this.conceptIndex, this.indexInConcept, this.page, this.width, this.height, this.examples);
  final Concept concept;
  final int conceptIndex;
  final int indexInConcept;
  final int page;
  final double width, height;
  final List<PdfExample> examples;
  String get doc => concept.pdf!.doc;
}

/// 개념들 → 쪽 목록 (같은 쪽이 두 개념에 걸쳐 있으면 한 번만).
List<BookPage> bookPages(List<Concept> concepts) {
  final out = <BookPage>[];
  final seen = <String>{};
  for (var ci = 0; ci < concepts.length; ci++) {
    final c = concepts[ci];
    final pdf = c.pdf;
    if (pdf == null) continue;
    for (var i = 0; i < pdf.pages.length; i++) {
      final key = '${pdf.doc}#${pdf.pages[i]}';
      if (!seen.add(key)) continue;
      final (w, h) = pdf.sizeOf(i);
      out.add(BookPage(c, ci, i, pdf.pages[i], w, h, [for (final e in pdf.examples) if (e.page == pdf.pages[i]) e]));
    }
  }
  return out;
}

class _ConceptBookScreenState extends State<ConceptBookScreen> with WidgetsBindingObserver {
  late AppState _app;
  late final List<BookPage> _pages = bookPages(widget.concepts);
  int _cursor = 0; // 보이는 첫 쪽
  bool _spread = false; // 두 쪽 펼침
  InkController? _ink;
  List<BookPage> _shown = const [];
  Timer? _save;
  bool _dirty = false;
  int _seq = 0;
  bool _init = false;
  bool _loading = false;
  final GlobalKey<InkCanvasState> _canvas = GlobalKey<InkCanvasState>();
  final GlobalKey<ScaffoldState> _scaffold = GlobalKey<ScaffoldState>();

  // 펼침에서 한 쪽이 차지하는 너비 (종이 너비 1000 중)
  static const double _gap = 8;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      _app = AppScope.read(context);
      WidgetsBinding.instance.addObserver(this);
      final start = widget.concepts.isEmpty ? null : widget.concepts[widget.index.clamp(0, widget.concepts.length - 1)];
      final i = start == null ? 0 : _pages.indexWhere((p) => p.concept.id == start.id);
      _cursor = math.max(0, i);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flush();
    final c = _ink;
    if (c != null) {
      c.committed.removeListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    }
    super.dispose();
  }

  // ── 쪽 배치 (종이 좌표: 너비 1000) ──
  double get _slotWidth => _spread ? (1000 - _gap) / 2 : 1000;

  Offset _origin(int slot) => Offset(slot * (_slotWidth + _gap), 0);

  double _scaleOf(BookPage p) => _slotWidth / p.width; // 종이 단위 / 포인트

  /// 저장할 때 쓰는 쪽 좌표: 쪽 너비를 1000 으로.
  double _noteScale(BookPage p) => _slotWidth / 1000;

  List<BookPage> _visible(int cursor) {
    if (_pages.isEmpty) return const [];
    final a = cursor.clamp(0, _pages.length - 1);
    return [_pages[a], if (_spread && a + 1 < _pages.length) _pages[a + 1]];
  }

  int _alignCursor(int i) => _spread ? i - i % 2 : i;

  Future<void> _load() async {
    _flush();
    _loading = true;
    final seq = ++_seq;
    final shown = _visible(_cursor);
    final strokes = <InkStroke>[];
    var height = 0.0;
    for (var slot = 0; slot < shown.length; slot++) {
      final p = shown[slot];
      height = math.max(height, p.height * _scaleOf(p));
      final raw = await _app.readProfileFile(_app.conceptPageNotePath(p.concept.id, p.page));
      if (raw == null) continue;
      try {
        final doc = InkDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final k = _noteScale(p);
        final o = _origin(slot);
        strokes.addAll([for (final s in doc.strokes) _map(s, k, o)]);
      } catch (_) {}
    }
    if (!mounted || seq != _seq) return;
    _loading = false;
    final old = _ink;
    if (old != null) {
      old.committed.removeListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    final c = InkController(
        document: InkDocument(strokes: strokes, pageHeight: height + 40), settings: _app.ink, autoExtend: false);
    if (old != null) c.tool = old.tool;
    c.committed.addListener(_changed);
    setState(() {
      _ink = c;
      _shown = shown;
    });
  }

  static InkStroke _map(InkStroke s, double k, Offset o) => InkStroke(
        id: s.id,
        tool: s.tool,
        color: s.color,
        width: s.width * k,
        startedAt: s.startedAt,
        points: [for (final p in s.points) InkPoint(p.x * k + o.dx, p.y * k + o.dy, p.p, p.t)],
      );

  void _changed() {
    _dirty = true;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 900), _flush);
  }

  /// 펼친 종이의 필기를 쪽마다 나눠, 쪽 너비 1000 좌표로 저장한다.
  void _flush() {
    _save?.cancel();
    final c = _ink;
    if (c == null || !_dirty) return;
    _dirty = false;
    final shown = _shown;
    final per = [for (final _ in shown) <InkStroke>[]];
    for (final s in c.strokes) {
      if (s.points.isEmpty) continue;
      final cx = s.points.map((p) => p.x).reduce((a, b) => a + b) / s.points.length;
      final slot = shown.length > 1 && cx > _slotWidth + _gap / 2 ? 1 : 0;
      final k = _noteScale(shown[slot]);
      final o = _origin(slot);
      per[slot].add(_map(_map(s, 1, -o), 1 / k, Offset.zero));
    }
    for (var slot = 0; slot < shown.length; slot++) {
      final p = shown[slot];
      final doc = InkDocument(strokes: per[slot], pageHeight: 1000 * p.height / p.width);
      _app.writeProfileFile(_app.conceptPageNotePath(p.concept.id, p.page), jsonEncode(doc.toJson()));
    }
  }

  void _go(int cursor) {
    final n = _alignCursor(cursor.clamp(0, math.max(0, _pages.length - 1)));
    if (n == _cursor && _ink != null) return;
    _flush();
    setState(() => _cursor = n);
    _load();
    _canvas.currentState?.resetView();
  }

  void _step(int dir) => _go(_cursor + dir * (_spread ? 2 : 1));

  // ── 예제 ──
  bool _onTap(Offset pos, bool stylus) {
    for (var slot = 0; slot < _shown.length; slot++) {
      final p = _shown[slot];
      final k = _scaleOf(p);
      final o = _origin(slot);
      for (final e in p.examples) {
        final r = Rect.fromLTRB(o.dx + e.rect.x0 * k, o.dy + e.rect.y0 * k, o.dx + e.rect.x1 * k, o.dy + e.rect.y1 * k);
        if (_chipRect(r).inflate(6).contains(pos)) {
          _solve(e);
          return true;
        }
      }
    }
    return false;
  }

  /// "풀어 보기" 단추 자리 — 예제 영역 오른쪽 위.
  Rect _chipRect(Rect example) => Rect.fromLTWH(example.right - 96, example.top - 2, 96, 30);

  void _solve(PdfExample e) {
    final p = _app.bank.byId(e.problem);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이 예제 문제를 교재에서 찾지 못했어요')));
      return;
    }
    _flush();
    final c = _shown.isEmpty ? null : _shown.first.concept;
    SolveScreen.open(context, title: c == null || c.title.isEmpty ? '예제' : '${c.title} · 예제', problems: [p]);
  }

  List<Problem> _allExamples() {
    final out = <Problem>[];
    final seen = <String>{};
    for (final p in _pages) {
      for (final e in p.examples) {
        final pr = _app.bank.byId(e.problem);
        if (pr != null && seen.add(pr.id)) out.add(pr);
      }
    }
    return out;
  }

  // ── 그리기 ──
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final size = MediaQuery.sizeOf(context);
    final spread = size.width > size.height && size.width >= 900;
    if (spread != _spread || (_ink == null && !_loading)) {
      final was = _ink != null;
      if (was) _flush();
      _spread = spread;
      _cursor = _alignCursor(_cursor);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final color = widget.color ?? AppColors.blue;
    final ink = _ink;
    final cur = _shown.isEmpty ? (_pages.isEmpty ? null : _pages[_cursor]) : _shown.first;
    final concept = cur?.concept;
    final last = _shown.isEmpty ? _cursor : _cursor + _shown.length - 1;
    return Scaffold(
      key: _scaffold,
      backgroundColor: const Color(0xFFE3E7E2),
      drawer: Drawer(width: 400, child: _toc(app, color)),
      appBar: AppBar(
        leading: const BackButton(),
        titleSpacing: 0,
        title: Row(children: [
          IconButton(
            key: const Key('book-toc'),
            tooltip: '목차',
            onPressed: () => _scaffold.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(concept?.title.isNotEmpty == true ? concept!.title : '개념',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
      body: _pages.isEmpty
          ? const Center(child: Text('원본 PDF 쪽이 없어요'))
          : Column(children: [
              Expanded(
                child: Stack(children: [
                  Positioned.fill(
                    child: ink == null
                        ? const Center(child: CircularProgressIndicator())
                        : InkCanvas(
                            key: _canvas,
                            controller: ink,
                            paperColor: const Color(0xFFE3E7E2),
                            onTapPage: _onTap,
                            underlay: _spreadView(color),
                          ),
                  ),
                  if (ink != null) ...[
                    Positioned(
                      left: 14,
                      right: 14,
                      top: 10,
                      child: InkToolbar(
                        controller: ink,
                        onSettingsChanged: () => app.updateInk((_) {}),
                        onResetView: () => _canvas.currentState?.resetView(),
                      ),
                    ),
                    Positioned(left: 0, right: 0, bottom: 20, child: Center(child: ShapeSnapHint(controller: ink))),
                  ],
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(child: _turn(Icons.chevron_left_rounded, '이전 쪽', _cursor > 0 ? () => _step(-1) : null)),
                  ),
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                        child: _turn(Icons.chevron_right_rounded, '다음 쪽', last < _pages.length - 1 ? () => _step(1) : null)),
                  ),
                ]),
              ),
              _bottomBar(app, concept, color, last),
            ]),
    );
  }

  /// 종이(너비 1000) 위에 놓이는 쪽들 + 예제 "풀어 보기" 단추.
  Widget _spreadView(Color color) {
    final shown = _shown;
    if (shown.isEmpty) return const SizedBox(height: 400);
    return SizedBox(
      width: 1000,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var slot = 0; slot < shown.length; slot++) ...[
          if (slot > 0) const SizedBox(width: _gap),
          SizedBox(
            width: _slotWidth,
            child: PdfRegionView(
              key: ValueKey('page-${shown[slot].doc}-${shown[slot].page}'),
              doc: shown[slot].doc,
              page: shown[slot].page,
              rect: PdfBox(0, 0, shown[slot].width, shown[slot].height),
              overlay: LayoutBuilder(builder: (context, box) {
                final p = shown[slot];
                final k = box.maxWidth / p.width;
                return Stack(children: [
                  for (final e in p.examples)
                    Positioned.fromRect(
                      rect: _chipRect(Rect.fromLTRB(e.rect.x0 * k, e.rect.y0 * k, e.rect.x1 * k, e.rect.y1 * k)),
                      child: IgnorePointer(child: _SolveChip(color: color)),
                    ),
                ]);
              }),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _turn(IconData icon, String tip, VoidCallback? onTap) => Material(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 92,
            child: Icon(icon, size: 30, color: onTap == null ? AppColors.lineStrong : AppColors.inkSoft, semanticLabel: tip),
          ),
        ),
      );

  Widget _bottomBar(AppState app, Concept? c, Color color, int last) {
    final read = c != null && app.isConceptRead(c.id);
    final review = c != null && app.isConceptReview(c.id);
    final pageLabel = _shown.length > 1 ? '${_shown.first.page}–${_shown.last.page}쪽' : '${_shown.isEmpty ? '' : _shown.first.page}쪽';
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + MediaQuery.paddingOf(context).bottom),
      child: Row(children: [
        Text(pageLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        Text(' / ${_pages.length}', style: const TextStyle(color: AppColors.inkMuted, fontSize: 13.5)),
        Expanded(
          child: Slider(
            key: const Key('book-slider'),
            value: _cursor.toDouble(),
            min: 0,
            max: math.max(1, _pages.length - 1).toDouble(),
            activeColor: AppColors.ink,
            onChanged: _pages.length < 2 ? null : (v) => setState(() => _cursor = _alignCursor(v.round())),
            onChangeEnd: (v) => _go(v.round()),
          ),
        ),
        if (c != null) ...[
          OutlinedButton.icon(
            key: const Key('book-review'),
            onPressed: () => app.setConceptReview(c.id, !review),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              backgroundColor: review ? AppColors.reviewSoft : null,
            ),
            icon: Icon(review ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: review ? AppColors.review : AppColors.ink),
            label: const Text('다시 볼래'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const Key('book-understood'),
            onPressed: () {
              app.setConceptReview(c.id, false);
              app.setConceptRead(c.id, !read);
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 46),
              backgroundColor: read ? AppColors.correct : AppColors.ink,
            ),
            icon: Icon(read ? Icons.check_circle_rounded : Icons.check_rounded),
            label: Text(read ? '이해했어요 ✓' : '이해했어요'),
          ),
        ],
      ]),
    );
  }

  Widget _toc(AppState app, Color color) {
    final concepts = widget.concepts.where((c) => c.pdf != null).toList();
    final done = concepts.where((c) => app.isConceptRead(c.id)).length;
    final review = concepts.where((c) => app.isConceptReview(c.id)).length;
    final examples = _allExamples();
    final summary = concepts.where((c) => c.kind == '공식 정리' || c.title.contains('요약')).toList();
    final curId = _shown.isEmpty ? null : _shown.first.concept.id;
    final items = <Widget>[];
    String? unit;
    for (final c in concepts) {
      if (c.unit.isNotEmpty && c.unit != unit) {
        unit = c.unit;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 16, 4),
          child: Text(c.unit, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
        ));
      }
      items.add(_tocTile(app, c, curId));
    }
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 18, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('이해함 $done / ${concepts.length}${review > 0 ? ' · 다시 볼 곳 $review' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: concepts.isEmpty ? 0 : done / concepts.length,
                minHeight: 6,
                backgroundColor: AppColors.paperDeep,
                color: AppColors.correct,
              ),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
            ...items,
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Row(children: [
            if (summary.isNotEmpty) ...[
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48), backgroundColor: AppColors.ink),
                  onPressed: () {
                    Navigator.of(context).pop();
                    final i = _pages.indexWhere((p) => p.concept.id == summary.last.id);
                    if (i >= 0) _go(i);
                  },
                  child: const Text('시험 직전 요약'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton(
                key: const Key('book-all-examples'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: examples.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _flush();
                        SolveScreen.open(context, title: '예제 모아 풀기', problems: examples);
                      },
                child: Text('예제만 모아 풀기 · ${examples.length}'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _tocTile(AppState app, Concept c, String? curId) {
    return ListTile(
                key: Key('toc-${c.id}'),
                dense: true,
                selected: c.id == curId,
                selectedTileColor: AppColors.blueSoft,
                tileColor: app.isConceptReview(c.id) ? AppColors.reviewSoft : null,
                leading: SizedBox(
                  width: 22,
                  child: app.isConceptRead(c.id)
                      ? const Icon(Icons.check_rounded, color: AppColors.correct, semanticLabel: '이해함')
                      : app.isConceptReview(c.id)
                          ? const Icon(Icons.bookmark_rounded, color: AppColors.review, semanticLabel: '다시 볼래')
                          : null,
                ),
                title: Text(c.title, style: const TextStyle(fontSize: 14.5)),
                trailing: Text('${c.pdf!.pages.first}쪽', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
                onTap: () {
                  Navigator.of(context).pop();
                  final i = _pages.indexWhere((p) => p.concept.id == c.id);
                  if (i >= 0) _go(i);
                },
              );
  }
}

class _SolveChip extends StatelessWidget {
  const _SolveChip({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x401C2126), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.edit_rounded, size: 14, color: Colors.white),
        SizedBox(width: 4),
        Text('풀어 보기', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
