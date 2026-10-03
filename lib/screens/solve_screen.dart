import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_toolbar.dart';
import '../services/live_sync.dart';
import '../widgets/answer_panel.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import '../widgets/problem_card.dart';
import 'result_screen.dart';

class SolveScreen extends StatefulWidget {
  const SolveScreen({super.key, required this.title, required this.problems, this.mode = 'practice'});

  final String title;
  final List<Problem> problems;
  final String mode;

  static Future<void> open(BuildContext context,
      {required String title, required List<Problem> problems, String mode = 'practice'}) {
    if (problems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('풀 문제가 없어요')));
      return Future.value();
    }
    return Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => SolveScreen(title: title, problems: problems, mode: mode),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
  }

  @override
  State<SolveScreen> createState() => _SolveScreenState();
}

class _SolveScreenState extends State<SolveScreen> {
  late List<Problem> _problems;
  int _index = 0;
  final Map<int, GradedAnswer> _graded = {};
  final Set<int> _retrying = {};
  final Map<int, int> _elapsed = {};
  int? _choice;
  DateTime _since = DateTime.now();
  Timer? _clock;
  Timer? _draftTimer;
  InkController? _ink;
  final GlobalKey<InkCanvasState> _canvasKey = GlobalKey<InkCanvasState>();
  StreamSubscription<LiveMessage>? _msgSub;
  late AppState _app;
  bool _started = false;

  Problem get _p => _problems[_index];

  @override
  void initState() {
    super.initState();
    _problems = List<Problem>.of(widget.problems);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _app = AppScope.read(context);
      _msgSub = _app.live?.messages.listen(_onTeacherMessage);
      _open(0);
    }
  }

  @override
  void dispose() {
    _pauseTimer();
    _saveDraftNow();
    _clock?.cancel();
    _draftTimer?.cancel();
    _msgSub?.cancel();
    _app.live?.leavePage();
    final ink = _ink;
    if (ink != null) {
      ink.sink = null;
      ink.committed.removeListener(_onInkChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) => ink.dispose());
    }
    super.dispose();
  }

  // ------------------------------------------------------------ timing
  int _elapsedOf(int i) {
    final base = _elapsed[i] ?? 0;
    if (i == _index && !_graded.containsKey(i)) {
      return base + DateTime.now().difference(_since).inMilliseconds;
    }
    return base;
  }

  void _pauseTimer() {
    if (!_graded.containsKey(_index)) {
      _elapsed[_index] = _elapsedOf(_index);
    }
    _since = DateTime.now();
  }

  // ------------------------------------------------------------ navigation
  Future<void> _open(int i) async {
    if (_ink != null) {
      _pauseTimer();
      _saveDraftNow();
      final old = _ink!;
      old.sink = null;
      old.committed.removeListener(_onInkChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    final ink = InkController(settings: _app.ink);
    ink.committed.addListener(_onInkChanged);
    setState(() {
      _index = i;
      _ink = ink;
      _choice = null;
      _since = DateTime.now();
    });
    final p = _problems[i];
    final draft = await _app.loadDraft(p.id);
    if (!mounted || _ink != ink) return;
    if (draft != null) ink.load(draft);
    final live = _app.live;
    if (live != null) {
      ink.sink = live;
      live.sendPage(p, pageHeight: ink.pageHeight, strokes: () => ink.strokes);
    }
    _canvasKey.currentState?.scrollToTop();
  }

  void _onInkChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 2), _saveDraftNow);
  }

  void _saveDraftNow() {
    _draftTimer?.cancel();
    final ink = _ink;
    if (ink == null) return;
    if (_graded.containsKey(_index)) return; // attempt already stored its ink
    _app.saveDraft(_problems[_index].id, ink.toDocument());
  }

  void _goTo(int i) {
    if (i < 0 || i >= _problems.length || i == _index) return;
    _open(i);
  }

  void _next() {
    if (_index < _problems.length - 1) {
      _goTo(_index + 1);
    } else {
      _finish();
    }
  }

  void _finish() {
    _pauseTimer();
    final results = <SessionItem>[
      for (var i = 0; i < _problems.length; i++)
        SessionItem(problem: _problems[i], graded: _graded[i], timeMs: _elapsed[i] ?? 0),
    ];
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ResultScreen(title: widget.title, items: results, mode: widget.mode),
    ));
  }

  // ------------------------------------------------------------ grading
  Future<void> _submit(String answer) async {
    final p = _p;
    final i = _index;
    final time = _elapsedOf(i);
    _elapsed[i] = time;
    final g = gradeAnswer(p, answer);
    setState(() => _graded[i] = g);
    if (!_retrying.contains(i)) {
      await _app.record(
        p,
        answer: answer,
        expected: g.expectedDisplay,
        correct: g.correct,
        timeMs: time,
        mode: widget.mode,
        inkDoc: _ink?.toDocument(),
      );
      await _app.deleteDraft(p.id);
    }
    if (g.correct && _app.settings.autoAdvance && mounted && _index == i) {
      Future<void>.delayed(const Duration(milliseconds: 1400), () {
        if (mounted && _index == i) _next();
      });
    }
  }

  void _addVariant() {
    final v = _app.makeVariant(_p);
    if (v.id == _p.id) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이 문제는 변형문제를 만들 수 없어요')));
      return;
    }
    Map<int, T> shift<T>(Map<int, T> m) => {for (final e in m.entries) (e.key > _index ? e.key + 1 : e.key): e.value};
    setState(() {
      _problems.insert(_index + 1, v);
      final g = shift(_graded), el = shift(_elapsed);
      _graded
        ..clear()
        ..addAll(g);
      _elapsed
        ..clear()
        ..addAll(el);
      final r = {for (final k in _retrying) k > _index ? k + 1 : k};
      _retrying
        ..clear()
        ..addAll(r);
    });
    _goTo(_index + 1);
  }

  void _retry() {
    setState(() {
      _graded.remove(_index);
      _retrying.add(_index);
      _since = DateTime.now();
    });
  }

  void _onTeacherMessage(LiveMessage m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Row(children: [
        const Icon(Icons.campaign_rounded, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text('${m.from}: ${m.text}')),
      ]),
    ));
  }

  void _showHint() {
    final h = _p.hint;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lightbulb_rounded, color: AppColors.review),
          SizedBox(width: 8),
          Text('힌트'),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: MathText(h == null || h.isEmpty ? '이 문제는 힌트가 없어요. 조건을 하나씩 식으로 옮겨 보세요.' : h,
              style: const TextStyle(fontSize: 17, color: AppColors.ink, height: 1.7)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
      ),
    );
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ink = _ink;
    final p = _p;
    final color = Color(app.bank.subject(p.subjectId)?.color ?? 0xFF2F6BFF);
    final graded = _graded[_index];
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final panel = AnswerPanel(
      key: ValueKey('panel-${p.id}-$_index'),
      problem: p,
      color: color,
      graded: graded,
      handwritingEnabled: app.settings.handwritingAnswer,
      onSubmit: _submit,
      onChoiceChanged: (c) => setState(() => _choice = c),
      onNext: _next,
      onVariant: (p.hasTemplate || p.isVariant) ? _addVariant : null,
      onRetry: _retry,
      isLast: _index == _problems.length - 1,
    );

    final canvas = ink == null
        ? const SizedBox()
        : Stack(children: [
            Positioned.fill(
              child: InkCanvas(
                key: _canvasKey,
                controller: ink,
                underlay: ProblemSheet(
                  problem: p,
                  number: _index + 1,
                  color: color,
                  selectedChoice: graded == null ? _choice : int.tryParse(graded.given),
                  revealAnswer: graded != null,
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              top: 12,
              child: InkToolbar(
                controller: ink,
                onSettingsChanged: () => app.updateInk((_) {}),
                onResetView: () => _canvasKey.currentState?.resetView(),
              ),
            ),
          ]);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(children: [
          _topBar(app, color),
          Expanded(
            child: wide
                ? Row(children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 6, 12),
                        child: ClipRRect(borderRadius: BorderRadius.circular(22), child: canvas),
                      ),
                    ),
                    SizedBox(
                      width: 372,
                      child: Padding(padding: const EdgeInsets.fromLTRB(8, 0, 16, 16), child: panel),
                    ),
                  ])
                : Column(children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                        child: ClipRRect(borderRadius: BorderRadius.circular(18), child: canvas),
                      ),
                    ),
                    SizedBox(
                      height: 360,
                      child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: panel),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _topBar(AppState app, Color color) {
    final st = app.stateOf(app.baseIdOf(_p));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 10),
      child: Row(children: [
        IconButton(
          tooltip: '나가기',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 4),
        Flexible(
          flex: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              Text('${_index + 1} / ${_problems.length} 문제',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _progressDots(color)),
        const SizedBox(width: 12),
        if (app.settings.showTimer)
          Pill(fmtClock(_elapsedOf(_index)), icon: Icons.timer_outlined, color: AppColors.inkSoft),
        const SizedBox(width: 6),
        _liveBadge(app),
        IconButton(
          tooltip: '힌트',
          onPressed: _showHint,
          icon: const Icon(Icons.lightbulb_outline_rounded),
        ),
        IconButton(
          tooltip: st.bookmarked ? '북마크 해제' : '북마크',
          onPressed: () => app.toggleBookmark(app.baseIdOf(_p)),
          icon: Icon(st.bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: st.bookmarked ? AppColors.accent : null),
        ),
        IconButton(
          tooltip: '이전 문제',
          onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: '다음 문제',
          onPressed: _index < _problems.length - 1 ? () => _goTo(_index + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
    );
  }

  Widget _progressDots(Color color) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < _problems.length; i++)
          GestureDetector(
            onTap: () => _goTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == _index ? 26 : 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: _graded[i] == null
                    ? (i == _index ? color : AppColors.lineStrong)
                    : (_graded[i]!.correct ? AppColors.correct : AppColors.wrong),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _liveBadge(AppState app) {
    final live = app.live;
    if (live == null || !app.settings.liveEnabled) return const SizedBox();
    return ValueListenableBuilder<LiveStatus>(
      valueListenable: live.status,
      builder: (context, s, _) {
        final (label, c) = switch (s) {
          LiveStatus.online => ('선생님과 공유 중', AppColors.correct),
          LiveStatus.connecting => ('연결 중', AppColors.review),
          LiveStatus.error => ('연결 끊김', AppColors.wrong),
          LiveStatus.off => ('공유 꺼짐', AppColors.inkMuted),
        };
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Pill(label, color: c, icon: Icons.podcasts_rounded),
        );
      },
    );
  }
}
