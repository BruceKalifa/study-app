import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_model.dart';
import '../ink/ink_toolbar.dart';
import '../ink/shape_hint.dart';
import '../services/handwriting.dart';
import '../services/live_sync.dart';
import '../widgets/answer_panel.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import '../widgets/problem_card.dart';
import '../widgets/snapshot.dart';
import 'community_screen.dart' show WritePostScreen;
import 'questions_screen.dart' show AskTeacherScreen;
import 'result_screen.dart';

/// One problem per page, printed like a 모의고사 시험지; the rest of the page is writing space.
///
/// * 객관식: tap a choice (pen or finger) to mark it.
/// * 단답형: write the answer in the 답 box under the problem; it is recognised automatically.
/// * Full screen (default) hides everything except the paper, the pen tools and the page buttons.
class SolveScreen extends StatefulWidget {
  const SolveScreen({
    super.key,
    required this.title,
    required this.problems,
    this.mode = 'practice',
    this.timeLimitMs,
    this.feed,
  });

  /// 무한 풀기: more problems are drawn from this feed as the student goes.
  final EndlessFeed? feed;

  final String title;
  final List<Problem> problems;

  /// practice | review | variant | today | exam (answers hidden until the end)
  final String mode;
  final int? timeLimitMs;

  /// 무한 풀기 over the learner's courses (or one course / unit / 유형).
  static Future<void> endless(BuildContext context,
      {String? courseId, String? unit, String? topic, String? title, String? workbookId}) {
    final app = AppScope.read(context);
    final feed = EndlessFeed(courseId: courseId, unit: unit, topic: topic, workbookId: workbookId);
    final first = app.nextEndless(feed);
    if (first == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(app.myWorkbooks.isEmpty && workbookId == null
              ? '먼저 문제집을 골라 내 교재에 담아 주세요'
              : '풀 문제가 없어요')));
      return Future.value();
    }
    final name = title ?? topic ?? unit ?? (courseId == null ? '무한 풀기' : app.bank.subject(courseId)?.name ?? '무한 풀기');
    return open(context, title: '$name · 무한 풀기', problems: [first], mode: 'endless', feed: feed);
  }

  static Future<void> open(BuildContext context,
      {required String title,
      required List<Problem> problems,
      String mode = 'practice',
      int? timeLimitMs,
      EndlessFeed? feed}) {
    if (problems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('풀 문제가 없어요')));
      return Future.value();
    }
    return Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) =>
          SolveScreen(title: title, problems: problems, mode: mode, timeLimitMs: timeLimitMs, feed: feed),
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

class _SolveScreenState extends State<SolveScreen> with WidgetsBindingObserver {
  late List<Problem> _problems;
  int _index = 0;
  final Map<int, GradedAnswer> _graded = {};
  final Set<int> _retrying = {};
  final Map<int, int> _elapsed = {};
  DateTime _since = DateTime.now();
  Timer? _draftTimer;
  InkController? _ink;
  final GlobalKey<InkCanvasState> _canvasKey = GlobalKey<InkCanvasState>();

  /// The page (problem + handwriting) — attached to questions as a picture.
  final GlobalKey _pageShot = GlobalKey(debugLabel: 'page-shot');
  final ExamSheetKeys _sheet = ExamSheetKeys();
  StreamSubscription<LiveMessage>? _msgSub;
  late AppState _app;
  bool _started = false;
  bool _full = true;

  // answers (choice number as text, or the short answer)
  final Map<int, String> _answers = {};
  final Map<int, List<String>> _cands = {};
  final Set<int> _typed = {}; // answers typed on the keypad (kept even when the box is empty)
  Timer? _recogTimer;
  String _answerSig = '';
  bool _boxEmpty = true;
  bool _recognizing = false;

  // exam mode
  final DateTime _examStart = DateTime.now();
  bool _finishing = false;
  bool get _exam => widget.mode == 'exam';

  Problem get _p => _problems[_index];

  /// 세로 화면(지문형): 태블릿을 채우고도 남을 만큼 긴 종이 (더 쓰면 autoExtend 가 늘린다).
  static const double _portraitPageHeight = 2200;

  /// 세로 화면(그 밖의 문항): 종이를 가로로 길게 — 왼쪽 절반에 문제(예전 그대로의 크기), 오른쪽 절반은 빈 풀이 공간.
  /// 화면에는 처음 문제만 꽉 차게 보이고, 오른쪽으로 넘기면(손가락으로 밀면) 풀이 공간이 나온다. 경계선은 없다.
  static const double _portraitSplitPageHeight = 1700;

  /// 세로 화면에서 두 단 종이를 쓰나 (지문형은 지문이 길어 예전처럼 위아래).
  bool _portraitSplit(BuildContext context) {
    final size = MediaQuery.maybeOf(context)?.size;
    if (size == null || size.width > size.height * 1.15) return false;
    return _app.bank.passageOf(_p) == null;
  }

  /// 지문형 문항은 가로에서도 지문이 길어 종이를 넉넉히 둔다.
  static const double _passagePageHeight = 1200;

  /// 가로 화면: 종이를 화면에 꼭 맞춰 풀이 공간이 문제 **아래**가 아니라 **옆**에 오게 한다.
  /// (오른쪽 단이 풀이 공간. 더 쓰면 autoExtend 가 아래로 늘려 준다.)
  double _pageHeightFor(BuildContext context) {
    final size = MediaQuery.maybeOf(context)?.size;
    if (size == null || size.width <= size.height * 1.15) {
      return _portraitSplit(context) ? _portraitSplitPageHeight : _portraitPageHeight;
    }
    if (_app.bank.passageOf(_p) != null) return _passagePageHeight;
    return math.max(620.0, kPageWidth * size.height / size.width);
  }
  bool get _locked => !_exam && _graded.containsKey(_index);

  @override
  void initState() {
    super.initState();
    _problems = List<Problem>.of(widget.problems);
    WidgetsBinding.instance.addObserver(this);
    Handwriting.instance.status.addListener(_onHandwritingStatus);
    Handwriting.instance.prepare();
  }

  void _onHandwritingStatus() {
    if (!mounted) return;
    setState(() {});
    if (Handwriting.instance.status.value == HandwritingStatus.ready) _scheduleRecognize(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _pauseTimer(); // time in the background does not count
      _saveDraftNow();
      _backgrounded = true;
    } else if (s == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      _since = DateTime.now();
      if (_full) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  bool _backgrounded = false;

  @override
  void didChangeMetrics() {
    // 세로로 돌리면 종이가 더 길어야 한다 (줄이지는 않는다 — 써 둔 글씨가 잘리면 안 되니까)
    final ink = _ink;
    if (ink == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ink != ink) return;
      final want = _pageHeightFor(context);
      if (ink.pageHeight < want) {
        setState(() => ink.pageHeight = want);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _app = AppScope.read(context);
      _full = _app.settings.fullscreenSolve;
      if (_full) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _msgSub = _app.live?.messages.listen(_onTeacherMessage);
      _open(0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Handwriting.instance.status.removeListener(_onHandwritingStatus);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pauseTimer();
    _saveDraftNow();
    _draftTimer?.cancel();
    _recogTimer?.cancel();
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

  // ------------------------------------------------------------ full screen
  void _setFull(bool v) {
    setState(() => _full = v);
    SystemChrome.setEnabledSystemUIMode(v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    _app.updateSettings((s) => s.fullscreenSolve = v);
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
    _recogTimer?.cancel();
    final ink = InkController(settings: _app.ink);
    ink.pageHeight = _pageHeightFor(context);
    ink.committed.addListener(_onInkChanged);
    setState(() {
      _index = i;
      _ink = ink;
      _since = DateTime.now();
      _answerSig = '';
      _boxEmpty = true;
      _recognizing = false;
    });
    final p = _problems[i];
    final draft = await _app.loadDraft(p.id);
    if (!mounted || _ink != ink) return;
    if (draft != null && ink.isEmpty) ink.load(draft); // never wipe strokes written while loading
    final want = _pageHeightFor(context);
    if (ink.pageHeight < want) ink.pageHeight = want;
    final live = _app.live;
    if (live != null) {
      ink.sink = live;
      live.sendPage(p, pageHeight: ink.pageHeight, strokes: () => ink.strokes);
    }
    if (_portraitSplit(context)) {
      _canvasKey.currentState?.resetView(); // 새 문제는 왼쪽(문제 단)부터
    } else {
      _canvasKey.currentState?.scrollToTop();
    }
    // the answer box position is known after layout: re-read an answer written earlier
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _ink == ink) _scheduleRecognize(force: true);
    });
  }

  void _onInkChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 2), _saveDraftNow);
    _scheduleRecognize();
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
    final feed = widget.feed;
    if (_index >= _problems.length - 1 && feed != null) {
      final more = _app.nextEndless(feed);
      if (more != null) {
        setState(() => _problems.add(more));
        _goTo(_index + 1);
        return;
      }
    }
    if (_index < _problems.length - 1) {
      _goTo(_index + 1);
    } else if (_exam) {
      _confirmFinish();
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _pauseTimer();
    if (_exam) {
      _finishing = true;
      _saveDraftNow();
      for (var i = 0; i < _problems.length; i++) {
        final ans = _answers[i];
        if (ans == null || ans.isEmpty) continue;
        final p = _problems[i];
        final g = gradeAnswer(p, ans);
        _graded[i] = g;
        final doc = i == _index ? _ink?.toDocument() : await _app.loadDraft(p.id);
        await _app.record(p,
            answer: ans,
            expected: g.expectedDisplay,
            correct: g.correct,
            timeMs: _elapsed[i] ?? 0,
            mode: 'exam',
            inkDoc: doc);
        await _app.deleteDraft(p.id);
      }
      if (!mounted) return;
    }
    final results = <SessionItem>[
      for (var i = 0; i < _problems.length; i++)
        SessionItem(problem: _problems[i], graded: _graded[i], timeMs: _elapsed[i] ?? 0),
    ];
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    // close anything above this screen (e.g. the "finish exam?" dialog when time runs out)
    if (route != null) nav.popUntil((r) => r == route);
    nav.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ResultScreen(title: widget.title, items: results, mode: widget.mode),
    ));
  }

  // ------------------------------------------------------------ answers on the page
  bool _inBox(Rect b, Rect box) {
    if (!box.contains(b.center)) return false;
    final i = b.intersect(box);
    if (i.width <= 0 || i.height <= 0) return false;
    final area = b.width * b.height;
    return area <= 0 || i.width * i.height >= 0.6 * area;
  }

  List<InkStroke> _answerStrokes() {
    final ink = _ink;
    final r = _sheet.answerRect;
    if (ink == null || r == null) return const [];
    final box = r.inflate(12);
    return [
      for (final s in ink.strokes)
        if (s.tool == InkTool.pen && _inBox(s.bounds, box)) s
    ];
  }

  void _scheduleRecognize({bool force = false}) {
    if (!mounted || _ink == null || _p.isChoice || _locked) return;
    final strokes = _answerStrokes();
    final sig = strokes.map((s) => s.id).join(',');
    final empty = strokes.isEmpty;
    if (empty != _boxEmpty) setState(() => _boxEmpty = empty);
    if (!force && sig == _answerSig) return;
    _answerSig = sig;
    _recogTimer?.cancel();
    final i = _index;
    if (empty) {
      if (!_typed.contains(i) && (_answers.containsKey(i) || _cands.containsKey(i))) {
        setState(() {
          _answers.remove(i);
          _cands.remove(i);
        });
      }
      return;
    }
    if (!_app.settings.handwritingAnswer) return;
    _recogTimer = Timer(const Duration(milliseconds: 600), () => _recognize(i, sig, strokes));
  }

  Future<void> _recognize(int i, String sig, List<InkStroke> strokes) async {
    final r = _sheet.answerRect;
    if (r == null || !mounted) return;
    setState(() => _recognizing = true);
    await Handwriting.instance.prepare();
    final local = [for (final s in strokes) s.translated(-r.left, -r.top)];
    final cands = await Handwriting.instance.recognize(local, width: r.width, height: r.height);
    if (!mounted) return;
    setState(() {
      _recognizing = false;
      if (i != _index || sig != _answerSig || _locked) return;
      _cands[i] = cands;
      if (cands.isNotEmpty) {
        _answers[i] = cands.first;
        _typed.remove(i);
      }
    });
  }

  /// Pen or finger tap on the page. Returns true when it picked something (no dot is drawn).
  bool _onTapPage(Offset pos, bool stylus) {
    final p = _p;
    if (p.isChoice) {
      final n = _sheet.choiceAt(pos, p.choices.length);
      if (n == null) return false;
      if (!_locked) {
        HapticFeedback.selectionClick();
        setState(() {
          if (_answers[_index] == '$n') {
            _answers.remove(_index);
          } else {
            _answers[_index] = '$n';
          }
        });
      }
      return true;
    }
    final r = _sheet.answerRect;
    if (!stylus && !_locked && r != null && r.contains(pos)) {
      _editAnswer();
      return true;
    }
    return false;
  }

  Future<void> _editAnswer() async {
    final i = _index;
    final p = _p;
    final res = await showAnswerKeypad(
      context,
      problem: p,
      initial: _answers[i] ?? '',
      candidates: _cands[i] ?? const [],
      color: _colorOf(p),
    );
    if (res == null || !mounted || i != _index) return;
    setState(() {
      if (res.isEmpty) {
        _answers.remove(i);
        _typed.remove(i);
      } else {
        _answers[i] = res;
        _typed.add(i);
      }
    });
  }

  // ------------------------------------------------------------ grading
  Future<void> _grade() async {
    final answer = _answers[_index];
    if (answer == null || answer.isEmpty || _exam || _locked) return;
    final p = _p;
    final i = _index;
    final time = _elapsedOf(i);
    _elapsed[i] = time;
    final g = gradeAnswer(p, answer);
    HapticFeedback.mediumImpact();
    widget.feed?.report(g.correct);
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

  Future<void> _confirmFinish() async {
    final missing = _problems.length - _answers.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('시험을 마칠까요?'),
        content: Text(missing > 0 ? '아직 답하지 않은 문제가 $missing개 있어요. 마치면 바로 채점돼요.' : '모든 문제에 답했어요. 채점할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속 풀기')),
          FilledButton(
              key: const Key('exam-finish-ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('채점하기')),
        ],
      ),
    );
    if (ok == true) _finish();
  }

  void _addVariant() {
    final v = _app.makeVariant(_p);
    if (v.id == _p.id) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이 문제는 변형문제를 만들 수 없어요')));
      return;
    }
    Map<int, T> shift<T>(Map<int, T> m) => {for (final e in m.entries) (e.key > _index ? e.key + 1 : e.key): e.value};
    void reset<T>(Map<int, T> m) {
      final s = shift(m);
      m
        ..clear()
        ..addAll(s);
    }

    Set<int> shiftSet(Set<int> s) => {for (final k in s) k > _index ? k + 1 : k};
    setState(() {
      _problems.insert(_index + 1, v);
      reset(_graded);
      reset(_elapsed);
      reset(_answers);
      reset(_cands);
      final r = shiftSet(_retrying), t = shiftSet(_typed);
      _retrying
        ..clear()
        ..addAll(r);
      _typed
        ..clear()
        ..addAll(t);
    });
    _goTo(_index + 1);
  }

  void _retry() {
    setState(() {
      _graded.remove(_index);
      _retrying.add(_index);
      _since = DateTime.now();
      if (_p.isChoice) _answers.remove(_index);
    });
    _scheduleRecognize(force: true);
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

  Color _colorOf(Problem p) => Color(_app.bank.subject(p.subjectId)?.color ?? 0xFF2F6BFF);

  String? _answerNote(AppState app) {
    if (_p.isChoice) return null;
    if (_recognizing) return '인식 중…';
    if (!app.settings.handwritingAnswer) return '답칸을 손가락으로 톡 누르면 답을 입력할 수 있어요';
    return switch (Handwriting.instance.status.value) {
      HandwritingStatus.downloading => '필기 인식 준비 중… (처음 한 번만)',
      HandwritingStatus.unavailable => '필기 인식을 쓸 수 없어요 · 답칸을 손가락으로 톡 눌러 입력하세요',
      _ => _boxEmpty ? null : (_answers[_index] == null ? '인식하지 못했어요 · 조금 크게 써 보세요' : null),
    };
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ink = _ink;
    final p = _p;
    final color = _colorOf(p);
    final graded = _exam ? null : _graded[_index];
    final mq = MediaQuery.of(context);
    final landscape = mq.size.width > mq.size.height * 1.15;
    final split = _portraitSplit(context);
    final answer = _answers[_index];

    // 가로 화면은 시험지처럼 두 단: 왼쪽이 문제, 오른쪽이 풀이 공간.
    // 세로 화면은 문제를 예전 그대로(화면 너비) 놓고, 풀이 공간은 그 오른쪽에 가로로 이어 붙인다 —
    // 처음엔 문제만 화면에 꽉 차게 보이고, 오른쪽으로 넘기면(손가락으로 밀면) 풀이 공간이 나온다. 경계선은 없다.
    final zoom = (950 / mq.size.width).clamp(0.45, 1.0);
    final columnFraction = landscape ? 0.44 : 1.0;
    // 단 경계선의 페이지 좌표 (ProblemSheet 의 안쪽 여백 64 · 줄 너비 = 1000/zoom − 128 과 맞춘다)
    final ruleX = landscape ? 64 * zoom + (1000 - 128 * zoom) * columnFraction + 22 : null;
    final pageShare = split ? 0.5 : 1.0;
    final initialZoom = split ? 2.0 : 1.0;

    final passage = app.bank.passageOf(p);
    String? passageLabel;
    if (passage != null) {
      var a = _index, b = _index;
      while (a > 0 && _problems[a - 1].passageId == p.passageId) {
        a--;
      }
      while (b < _problems.length - 1 && _problems[b + 1].passageId == p.passageId) {
        b++;
      }
      passageLabel = a == b ? '다음 글을 읽고 물음에 답하시오.' : '[${a + 1}~${b + 1}] 다음 글을 읽고 물음에 답하시오.';
    }

    final sheet = ProblemSheet(
      passage: passage,
      passageLabel: passageLabel,
      problem: p,
      number: _index + 1,
      color: color,
      keys: _sheet,
      selectedChoice: p.isChoice ? int.tryParse(graded?.given ?? answer ?? '') : null,
      revealAnswer: graded != null && !graded.correct,
      mark: graded?.correct,
      answerText: graded?.given ?? answer,
      answerNote: _answerNote(app),
      answerBoxEmpty: _boxEmpty,
      // the page always spans the screen width; keep print the same size on screen as in portrait
      zoom: zoom,
      columnFraction: columnFraction,
      pageShare: pageShare,
      serif: app.settings.examFont,
    );

    final canvas = ink == null
        ? const SizedBox()
        : Stack(children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: _pageShot,
                child: InkCanvas(
                  key: _canvasKey,
                  controller: ink,
                  onTapPage: _onTapPage,
                  underlay: sheet,
                  initialZoom: initialZoom,
                  columnRuleX: passage == null ? ruleX : null,
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              top: 12 + (_full ? mq.padding.top : 0),
              child: Row(children: [
                Expanded(
                  child: InkToolbar(
                    controller: ink,
                    onSettingsChanged: () => app.updateInk((_) {}),
                    onResetView: () => _canvasKey.currentState?.resetView(),
                  ),
                ),
                if (_full) ...[
                  const SizedBox(width: 10),
                  _fullCluster(app, color),
                ],
              ]),
            ),
            Positioned(left: 0, right: 0, bottom: 18, child: Center(child: ShapeSnapHint(controller: ink))),
            Positioned(left: 16, right: 16, bottom: 64, child: Center(child: PlacingHint(controller: ink))),
          ]);

    return Scaffold(
      backgroundColor: _full ? const Color(0xFFE9E6DF) : AppColors.paper,
      body: Stack(children: [
        Column(children: [
          if (!_full) SafeArea(bottom: false, child: _topBar(app, color)),
          Expanded(
            child: _full
                ? canvas
                : Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: ClipRRect(borderRadius: BorderRadius.circular(20), child: canvas),
                  ),
          ),
        ]),
        Positioned(
          left: 18,
          right: 18,
          bottom: 16 + mq.padding.bottom + (_full ? 0 : 10),
          child: _bottomBar(app, color, graded),
        ),
      ]),
    );
  }

  // ---------- floating controls
  /// Ignore taps that are really the palm resting while the pen writes.
  VoidCallback? _palmSafe(VoidCallback? f) => f == null
      ? null
      : () {
          if (InkCanvas.penBusy) return;
          f();
        };

  Widget _bottomBar(AppState app, Color color, GradedAnswer? graded) {
    final last = _index == _problems.length - 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _NavButton(
          key: const Key('prev'),
          icon: Icons.chevron_left_rounded,
          label: '이전',
          onTap: _palmSafe(_index > 0 ? () => _goTo(_index - 1) : null),
        ),
        Expanded(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: c),
              ),
              child: FittedBox(
                key: ValueKey('bar-$_index-${graded != null}'),
                fit: BoxFit.scaleDown,
                child: _centerPill(app, color, graded),
              ),
            ),
          ),
        ),
        _NavButton(
          key: const Key('next'),
          icon: last && widget.feed == null ? Icons.flag_rounded : Icons.chevron_right_rounded,
          label: last && widget.feed == null ? (_exam ? '시험 종료' : '결과 보기') : '다음',
          trailing: true,
          filled: graded != null || (_exam && last && widget.feed == null),
          color: color,
          onTap: _palmSafe(_next),
        ),
      ],
    );
  }

  Widget _pill({required List<Widget> children}) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.line),
          boxShadow: const [BoxShadow(color: Color(0x221B2A4A), blurRadius: 22, offset: Offset(0, 8))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _centerPill(AppState app, Color color, GradedAnswer? graded) {
    final p = _p;
    final answer = _answers[_index];
    final has = answer != null && answer.isNotEmpty;

    if (graded != null) {
      final c = graded.correct ? AppColors.correct : AppColors.wrong;
      return _pill(children: [
        const SizedBox(width: 6),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: Icon(graded.correct ? Icons.circle_outlined : Icons.close_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 10),
        Text(graded.correct ? '정답이에요!' : '오답 · 정답 ${graded.expectedDisplay}',
            key: const Key('grade-result'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c)),
        const SizedBox(width: 8),
        TextButton.icon(
          key: const Key('solution'),
          onPressed: _palmSafe(() => showSolutionSheet(context, p, graded)),
          icon: const Icon(Icons.menu_book_rounded, size: 19),
          label: const Text('해설'),
        ),
        if (!_exam && _app.hasVariant(p))
          TextButton.icon(
            onPressed: _palmSafe(_addVariant),
            icon: const Icon(Icons.auto_awesome_rounded, size: 19),
            label: const Text('변형'),
          ),
        if (_app.community != null || _app.signedIn)
          TextButton.icon(
            key: const Key('ask'),
            onPressed: _palmSafe(_ask),
            icon: const Icon(Icons.contact_support_rounded, size: 19),
            label: const Text('질문'),
          ),
        if (!graded.correct)
          TextButton.icon(
            onPressed: _palmSafe(_retry),
            icon: const Icon(Icons.refresh_rounded, size: 19),
            label: const Text('다시'),
          ),
      ]);
    }

    // answer chip: what will be handed in
    final Widget chip;
    if (p.isChoice) {
      chip = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          has ? '${circled(int.tryParse(answer) ?? 0)} 선택' : '선지를 눌러 고르세요',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: has ? AppColors.ink : AppColors.inkMuted),
        ),
      );
    } else {
      chip = InkWell(
        key: const Key('answer-edit'),
        borderRadius: BorderRadius.circular(24),
        onTap: _palmSafe(_editAnswer),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(has ? '답  ' : '답칸에 쓰면 자동 인식',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
            if (has)
              Text(answerDisplay(p, answer), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            const Icon(Icons.edit_rounded, size: 17, color: AppColors.inkMuted),
          ]),
        ),
      );
    }

    if (_exam) {
      return _pill(children: [
        chip,
        if (has)
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: Icon(Icons.check_circle_rounded, color: AppColors.correct, size: 20),
          ),
        Container(width: 1, height: 30, color: AppColors.line),
        TextButton(
          key: const Key('exam-finish'),
          onPressed: _palmSafe(_confirmFinish),
          child: Text('시험 종료 ${_answers.length}/${_problems.length}'),
        ),
      ]);
    }

    return _pill(children: [
      chip,
      const SizedBox(width: 4),
      FilledButton.icon(
        key: const Key('submit'),
        onPressed: has ? _palmSafe(_grade) : null,
        icon: const Icon(Icons.check_rounded, size: 20),
        label: const Text('채점하기'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          backgroundColor: color,
          disabledBackgroundColor: AppColors.line,
        ),
      ),
    ]);
  }

  /// Top-right corner in full screen: where am I, time, hint, leave full screen.
  Widget _fullCluster(AppState app, Color color) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: const [BoxShadow(color: Color(0x0F1B2A4A), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 8),
        if (widget.feed != null) ...[
          Icon(Icons.all_inclusive_rounded, size: 20, color: color),
          const SizedBox(width: 6),
          Text('${_index + 1}번째',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5)),
        ] else ...[
          Text('${_index + 1}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5)),
          Text(' / ${_problems.length}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
        ],
        const SizedBox(width: 8),
        if (_exam && widget.timeLimitMs != null)
          _Countdown(
            endsAt: _examStart.add(Duration(milliseconds: widget.timeLimitMs!)),
            onTimeout: _onExamTimeout,
          )
        else if (app.settings.showTimer)
          _ElapsedPill(elapsed: () => _elapsedOf(_index)),
        if (!_exam)
          IconButton(
            tooltip: '힌트',
            onPressed: _showHint,
            icon: const Icon(Icons.lightbulb_outline_rounded),
          ),
        if (!_exam && app.signedIn && !app.isTeacher)
          IconButton(
            key: const Key('ask-anytime'),
            tooltip: '선생님께 질문 (지금 풀이 화면을 함께 보내요)',
            onPressed: _palmSafe(_ask),
            icon: const Icon(Icons.contact_support_outlined),
          ),
        if (widget.feed != null)
          TextButton(key: const Key('endless-stop'), onPressed: _finish, child: const Text('그만 풀기')),
        IconButton(
          key: const Key('fullscreen-toggle'),
          tooltip: '전체화면 끄기',
          onPressed: () => _setFull(false),
          icon: const Icon(Icons.fullscreen_exit_rounded),
        ),
      ]),
    );
  }

  /// 질문: 선생님께 (지금 페이지 사진과 함께) 또는 커뮤니티에.
  Future<void> _ask() async {
    final app = _app;
    final p = _p;
    final canTeacher = app.signedIn && !app.isTeacher;
    final canCommunity = app.community != null;
    var choice = canTeacher ? 'teacher' : 'community';
    if (canTeacher && canCommunity) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              key: const Key('ask-teacher'),
              leading: const Icon(Icons.co_present_rounded, color: AppColors.correct),
              title: const Text('선생님께 질문', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(app.myTeachers.isEmpty
                  ? '선생님과 먼저 연결해요 (초대 코드)'
                  : '지금 풀이 화면을 사진으로 함께 보내요 · ${app.myTeachers.map((t) => t.name).join(', ')}'),
              onTap: () => Navigator.pop(c, 'teacher'),
            ),
            ListTile(
              key: const Key('ask-community'),
              leading: const Icon(Icons.forum_rounded, color: AppColors.blue),
              title: const Text('커뮤니티 질문 게시판에', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('다른 수험생들과 함께 풀어 봐요'),
              onTap: () => Navigator.pop(c, 'community'),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      );
      if (picked == null) return;
      choice = picked;
    }
    if (!mounted) return;
    if (choice == 'community') {
      await Navigator.of(context).push(MaterialPageRoute<bool>(
          builder: (_) => WritePostScreen(problem: p.isVariant ? (app.problem(p.familyId) ?? p) : p)));
      return;
    }
    final shot = await capturePng(_pageShot, pixelRatio: 1.0);
    if (!mounted) return;
    await AskTeacherScreen.open(context, problem: p, snapshot: shot);
  }

  void _onExamTimeout() {
    if (mounted && !_finishing) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('시간이 끝났어요. 채점할게요.')));
      _finish();
    }
  }

  Widget _topBar(AppState app, Color color) {
    final st = app.stateOf(app.baseIdOf(_p));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
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
              Text(widget.feed != null ? '${_index + 1}번째 문제 · 맞히면 더 어렵게' : '${_index + 1} / ${_problems.length} 문제',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _progressDots(color)),
        const SizedBox(width: 12),
        if (_exam && widget.timeLimitMs != null)
          _Countdown(
            endsAt: _examStart.add(Duration(milliseconds: widget.timeLimitMs!)),
            onTimeout: _onExamTimeout,
          )
        else if (app.settings.showTimer)
          _ElapsedPill(elapsed: () => _elapsedOf(_index)),
        const SizedBox(width: 6),
        _liveBadge(app),
        IconButton(
          tooltip: '힌트',
          onPressed: _exam ? null : _showHint,
          icon: const Icon(Icons.lightbulb_outline_rounded),
        ),
        IconButton(
          tooltip: st.bookmarked ? '북마크 해제' : '북마크',
          onPressed: () => app.toggleBookmark(app.baseIdOf(_p)),
          icon: Icon(st.bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: st.bookmarked ? AppColors.accent : null),
        ),
        IconButton(
          key: const Key('fullscreen-toggle'),
          tooltip: '전체화면으로 풀기',
          onPressed: () => _setFull(true),
          icon: const Icon(Icons.fullscreen_rounded),
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
                color: _exam
                    ? (i == _index ? color : (_answers.containsKey(i) ? AppColors.ink : AppColors.lineStrong))
                    : _graded[i] == null
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

/// Big round page button (이전 / 다음) floating at the bottom corners.
class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing = false,
    this.filled = false,
    this.color = AppColors.ink,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool trailing;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = filled ? Colors.white : (enabled ? AppColors.ink : AppColors.lineStrong);
    final ic = Icon(icon, size: 30, color: fg);
    final tx = Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg));
    return Material(
      color: filled ? color : AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: filled ? color : AppColors.line)),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 64,
          padding: EdgeInsets.only(left: trailing ? 22 : 10, right: trailing ? 10 : 22),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(32)),
            boxShadow: enabled
                ? const [BoxShadow(color: Color(0x1A1B2A4A), blurRadius: 20, offset: Offset(0, 8))]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: trailing ? [tx, ic] : [ic, tx]),
        ),
      ),
    );
  }
}

/// Ticks once a second on its own so the page (math, ink) is not rebuilt by the clock.
class _ElapsedPill extends StatefulWidget {
  const _ElapsedPill({required this.elapsed});
  final int Function() elapsed;

  @override
  State<_ElapsedPill> createState() => _ElapsedPillState();
}

class _ElapsedPillState extends State<_ElapsedPill> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Pill(fmtClock(widget.elapsed()), icon: Icons.timer_outlined, color: AppColors.inkSoft);
}

class _Countdown extends StatefulWidget {
  const _Countdown({required this.endsAt, required this.onTimeout});
  final DateTime endsAt;
  final VoidCallback onTimeout;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _t;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_fired && DateTime.now().isAfter(widget.endsAt)) {
        _fired = true;
        widget.onTimeout();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt.difference(DateTime.now()).inMilliseconds;
    final urgent = left < 60000;
    return Pill('남은 시간 ${fmtClock(left < 0 ? 0 : left)}',
        icon: Icons.hourglass_bottom_rounded, color: urgent ? AppColors.wrong : AppColors.ink);
  }
}
