import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_model.dart';
import '../ink/ink_toolbar.dart';
import '../ink/shape_hint.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import '../widgets/problem_card.dart' show showsOrigin;
import 'solve_screen.dart';

/// 개념 페이지 읽기 — 교재의 개념·실전개념·공식 정리를 종이처럼 펼쳐 놓고 펜으로 필기한다.
/// 필기는 개념마다 자동 저장되고, 연 개념은 "읽음" 으로 표시된다.
class ConceptScreen extends StatefulWidget {
  const ConceptScreen({super.key, required this.concepts, required this.index, this.workbookId, this.color});

  /// 앞뒤로 넘길 개념들 (교재 안 개념 전부, 또는 하나).
  final List<Concept> concepts;
  final int index;

  /// 교재 안에서 열었으면 그 교재 — "이 개념 문제 풀기" 가 이 교재의 문제만 고른다.
  final String? workbookId;
  final Color? color;

  static Future<void> open(BuildContext context,
      {required List<Concept> concepts, int index = 0, String? workbookId, Color? color}) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConceptScreen(concepts: concepts, index: index, workbookId: workbookId, color: color),
    ));
  }

  @override
  State<ConceptScreen> createState() => _ConceptScreenState();
}

class _ConceptScreenState extends State<ConceptScreen> {
  late AppState _app;
  bool _init = false;
  late int _index = widget.index.clamp(0, widget.concepts.length - 1);
  InkController? _ink;
  Timer? _save;
  final GlobalKey<InkCanvasState> _canvas = GlobalKey<InkCanvasState>();
  final GlobalKey _sheetKey = GlobalKey();
  int _loadSeq = 0;
  bool _dirty = false;

  Concept get _c => widget.concepts[_index];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      _app = AppScope.read(context);
      _open(_index);
    }
  }

  Future<void> _open(int i) async {
    _flush();
    final seq = ++_loadSeq;
    final old = _ink;
    if (old != null) {
      old.committed.removeListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    final concept = widget.concepts[i];
    final c = InkController(settings: _app.ink);
    final raw = await _app.readProfileFile(_app.conceptNotePath(concept.id));
    if (raw != null) {
      try {
        c.load(InkDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {}
    }
    c.committed.addListener(_changed);
    if (!mounted || seq != _loadSeq) {
      c.dispose();
      return;
    }
    setState(() {
      _index = i;
      _ink = c;
    });
    _app.setConceptRead(concept.id, true);
    _canvas.currentState?.scrollToTop();
    // 글이 길면 종이도 그만큼 길게 (글을 다 그린 뒤 높이를 잰다)
    for (final ms in [0, 400]) {
      Future<void>.delayed(Duration(milliseconds: ms), _fitPage);
    }
  }

  void _fitPage() {
    if (!mounted) return;
    final box = _sheetKey.currentContext?.findRenderObject();
    final c = _ink;
    if (box is! RenderBox || !box.hasSize || c == null) return;
    final want = box.size.height + 360;
    if (c.pageHeight < want) setState(() => c.pageHeight = want);
  }

  void _changed() {
    _dirty = true;
    _save?.cancel();
    _save = Timer(const Duration(seconds: 1), _flush);
  }

  void _flush() {
    _save?.cancel();
    final c = _ink;
    if (c == null || !_dirty) return;
    _dirty = false;
    final id = widget.concepts[_index].id;
    _app.writeProfileFile(_app.conceptNotePath(id), jsonEncode(c.toDocument().toJson()));
  }

  @override
  void dispose() {
    _flush();
    final c = _ink;
    if (c != null) {
      c.committed.removeListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    }
    super.dispose();
  }

  List<Problem> _problems() {
    final bank = _app.bank;
    final w = widget.workbookId == null ? null : bank.workbook(widget.workbookId!);
    return bank.problemsExplainedBy(_c, within: w == null ? null : bank.problemsOf(w));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = _c;
    final color = widget.color ?? AppColors.blue;
    final ink = _ink;
    final read = app.isConceptRead(c.id);
    final ps = _problems();
    return Scaffold(
      backgroundColor: const Color(0xFFE9E6DF),
      appBar: AppBar(
        title: Text(c.title.isEmpty ? '개념' : c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.concepts.length > 1)
            Center(
              child: Text('${_index + 1} / ${widget.concepts.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
            ),
          IconButton(
            key: const Key('concept-read'),
            tooltip: read ? '읽음 표시 빼기' : '읽음으로 표시',
            onPressed: () => app.setConceptRead(c.id, !read),
            icon: Icon(read ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                color: read ? AppColors.correct : AppColors.inkMuted),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(
          child: ink == null
              ? const Center(child: CircularProgressIndicator())
              : InkCanvas(
                  key: _canvas,
                  controller: ink,
                  underlay: ConceptSheet(key: _sheetKey, concept: c, color: color, serif: app.settings.examFont),
                ),
        ),
        if (ink != null) ...[
          Positioned(
            left: 14,
            right: 14,
            top: 12,
            child: InkToolbar(
              controller: ink,
              onSettingsChanged: () => app.updateInk((_) {}),
              onResetView: () => _canvas.currentState?.resetView(),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 84, child: Center(child: ShapeSnapHint(controller: ink))),
          Positioned(left: 16, right: 16, bottom: 120, child: Center(child: PlacingHint(controller: ink))),
        ],
        Positioned(
          left: 18,
          right: 18,
          bottom: 16 + MediaQuery.of(context).padding.bottom,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_index > 0) _navButton(Icons.chevron_left_rounded, '이전 개념', () => _open(_index - 1)),
            const SizedBox(width: 10),
            if (ps.isNotEmpty)
              FilledButton.icon(
                key: const Key('concept-solve'),
                style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(0, 52)),
                onPressed: () => SolveScreen.open(context, title: c.title.isEmpty ? '개념 문제' : '${c.title} · 문제', problems: ps),
                icon: const Icon(Icons.edit_rounded),
                label: Text('이 개념 문제 풀기 · ${ps.length}문항'),
              ),
            const SizedBox(width: 10),
            if (_index < widget.concepts.length - 1) _navButton(Icons.chevron_right_rounded, '다음 개념', () => _open(_index + 1)),
          ]),
        ),
      ]),
    );
  }

  Widget _navButton(IconData icon, String tip, VoidCallback onTap) => Material(
        color: AppColors.surface,
        elevation: 2,
        shape: const CircleBorder(),
        child: IconButton(tooltip: tip, onPressed: onTap, icon: Icon(icon, size: 28)),
      );
}

/// 종이(너비 1000) 위에 놓이는 개념 한 장: 종류 · 제목 · 본문.
class ConceptSheet extends StatelessWidget {
  const ConceptSheet({super.key, required this.concept, required this.color, this.serif = true});
  final Concept concept;
  final Color color;
  final bool serif;

  @override
  Widget build(BuildContext context) {
    final c = concept;
    final face = serif ? AppTheme.serif : AppTheme.font;
    return SizedBox(
      width: 1000,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(64, 72, 64, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pill(c.kind, color: color),
            if (c.topic.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(c.topic, style: const TextStyle(fontSize: 22, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            ],
          ]),
          const SizedBox(height: 14),
          if (c.title.isNotEmpty)
            Text(c.title,
                style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.25, fontFamily: face, letterSpacing: -1)),
          const SizedBox(height: 10),
          Container(height: 3, width: 120, color: color),
          const SizedBox(height: 30),
          MathText(c.body, style: TextStyle(fontSize: 27, height: 1.85, fontFamily: face, color: AppColors.ink)),
          if (showsOrigin(context) && (c.source ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(c.source!, style: const TextStyle(fontSize: 20, color: AppColors.inkMuted)),
            ),
        ]),
      ),
    );
  }
}
