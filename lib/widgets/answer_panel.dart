import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/grader.dart';
import '../core/problem.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_model.dart';
import '../services/handwriting.dart';
import 'math_text.dart';

/// Result shown after grading.
class GradedAnswer {
  final String given;
  final bool correct;
  final String expectedDisplay;
  const GradedAnswer(this.given, this.correct, this.expectedDisplay);
}

String expectedDisplay(Problem p) {
  if (p.isChoice) {
    final n = int.tryParse(p.answer);
    return n == null ? p.answer : circled(n);
  }
  final u = p.answerUnit;
  return u == null || u.isEmpty ? p.answer : '${p.answer} $u';
}

/// Right-hand panel of the solve screen: answer input → 채점 → result.
class AnswerPanel extends StatefulWidget {
  const AnswerPanel({
    super.key,
    required this.problem,
    required this.color,
    required this.onSubmit,
    required this.graded,
    required this.handwritingEnabled,
    this.onChoiceChanged,
    this.onNext,
    this.onVariant,
    this.onRetry,
    this.isLast = false,
    this.examAnswer,
  });

  /// Exam mode: the answer already handed in for this problem (shown, can be changed).
  final String? examAnswer;

  final Problem problem;
  final Color color;
  final bool handwritingEnabled;
  final GradedAnswer? graded;
  final void Function(String answer) onSubmit;
  final ValueChanged<int?>? onChoiceChanged;
  final VoidCallback? onNext;
  final VoidCallback? onVariant;
  final VoidCallback? onRetry;
  final bool isLast;

  @override
  State<AnswerPanel> createState() => _AnswerPanelState();
}

class _AnswerPanelState extends State<AnswerPanel> {
  int? _choice;
  final TextEditingController _text = TextEditingController();
  late InkController _pad;
  Timer? _recognizeTimer;
  List<String> _candidates = [];
  bool _recognizing = false;
  bool _keypad = false;
  bool _showSolution = false;
  Size _padSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _pad = _newPad();
    _keypad = !widget.handwritingEnabled;
    Handwriting.instance.prepare();
  }

  InkController _newPad() {
    final c = InkController(
      autoExtend: false,
      settings: InkSettings(
        penWidth: 10,
        penColor: 0xFF1B2A4A,
        fingerDraws: true,
        holdToStraighten: false,
        twoFingerUndo: false,
        paper: PaperStyle.blank,
      ),
    );
    c.committed.addListener(_onPadChanged);
    return c;
  }

  @override
  void didUpdateWidget(covariant AnswerPanel old) {
    super.didUpdateWidget(old);
    if (old.problem.id != widget.problem.id) {
      _reset();
    } else if (old.graded != null && widget.graded == null) {
      _reset();
    }
  }

  void _reset() {
    _choice = null;
    _text.clear();
    _candidates = [];
    _showSolution = false;
    final old = _pad;
    old.committed.removeListener(_onPadChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _pad = _newPad();
    _recognizeTimer?.cancel();
  }

  @override
  void dispose() {
    _recognizeTimer?.cancel();
    _pad.committed.removeListener(_onPadChanged);
    _pad.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onPadChanged() {
    _recognizeTimer?.cancel();
    if (mounted) setState(() {});
    if (_pad.strokes.isEmpty) {
      setState(() {
        _candidates = [];
        _text.clear();
      });
      return;
    }
    _recognizeTimer = Timer(const Duration(milliseconds: 550), _recognize);
  }

  Future<void> _recognize() async {
    final strokes = List<InkStroke>.of(_pad.strokes);
    setState(() => _recognizing = true);
    final w = kPageWidth;
    final h = _padSize.width > 0 ? kPageWidth * _padSize.height / _padSize.width : 300.0;
    final cands = await Handwriting.instance.recognize(strokes, width: w, height: h);
    if (!mounted) return;
    setState(() {
      _recognizing = false;
      _candidates = cands;
      if (cands.isNotEmpty) _text.text = cands.first;
    });
  }

  void _submit() {
    final p = widget.problem;
    if (p.isChoice) {
      if (_choice == null) return;
      widget.onSubmit('$_choice');
    } else {
      final t = _text.text.trim();
      if (t.isEmpty) return;
      widget.onSubmit(t);
    }
  }

  bool get _canSubmit => widget.problem.isChoice ? _choice != null : _text.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final g = widget.graded;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      child: g == null ? _input(context) : _result(context, g),
    );
  }

  // ---------------------------------------------------------------- input
  Widget _input(BuildContext context) {
    final p = widget.problem;
    return Column(
      key: const ValueKey('input'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Text('답 쓰기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (!p.isChoice)
            _ModeToggle(
              keypad: _keypad,
              onChanged: (k) => setState(() => _keypad = k),
            ),
        ]),
        if (widget.examAnswer != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppColors.blueSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.inbox_rounded, size: 18, color: AppColors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '제출한 답: ${p.isChoice ? circled(int.tryParse(widget.examAnswer!) ?? 0) : widget.examAnswer!} · 다시 고르면 바뀌어요',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(child: p.isChoice ? _choiceInput() : _shortInput()),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('submit'),
          onPressed: _canSubmit ? _submit : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('채점하기'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(58),
            backgroundColor: widget.color,
            disabledBackgroundColor: AppColors.line,
          ),
        ),
      ],
    );
  }

  Widget _choiceInput() {
    final p = widget.problem;
    return ListView.separated(
      itemCount: p.choices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final n = i + 1;
        final sel = _choice == n;
        return Material(
          key: Key('choice-$n'),
          color: sel ? widget.color.withValues(alpha: 0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() => _choice = sel ? null : n);
              widget.onChoiceChanged?.call(_choice);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: sel ? widget.color : AppColors.line, width: sel ? 2 : 1),
              ),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sel ? widget.color : AppColors.paperDeep,
                  ),
                  child: Text('$n',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: sel ? Colors.white : AppColors.inkSoft)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MathText(p.choices[i],
                      maxLines: 3, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _shortInput() {
    final p = widget.problem;
    final unit = p.answerUnit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // answer display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(children: [
            const Text('답', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkMuted)),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _text,
                readOnly: _keypad || widget.handwritingEnabled,
                showCursor: true,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: '—',
                ),
              ),
            ),
            if (unit != null && unit.isNotEmpty)
              Text(unit, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
            if (_text.text.isNotEmpty)
              IconButton(
                tooltip: '지우기',
                onPressed: () {
                  _text.clear();
                  _pad.clearAll();
                  setState(() => _candidates = []);
                },
                icon: const Icon(Icons.backspace_outlined, size: 20),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        if (!_keypad) ...[
          Expanded(child: _padArea()),
          const SizedBox(height: 8),
          _candidateRow(),
        ] else
          Expanded(child: _Keypad(onKey: _onKey)),
      ],
    );
  }

  Widget _padArea() {
    return ValueListenableBuilder<HandwritingStatus>(
      valueListenable: Handwriting.instance.status,
      builder: (context, st, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.sheet,
              border: Border.all(color: AppColors.lineStrong, width: 1.2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: LayoutBuilder(builder: (context, box) {
              _padSize = Size(box.maxWidth, box.maxHeight);
              final h = kPageWidth * box.maxHeight / (box.maxWidth <= 0 ? 1 : box.maxWidth);
              if ((_pad.pageHeight - h).abs() > 1) _pad.pageHeight = h;
              return Stack(children: [
                Positioned.fill(
                  child: InkCanvas(
                    controller: _pad,
                    interactive: false,
                    paper: PaperStyle.blank,
                    paperColor: AppColors.sheet,
                  ),
                ),
                // baseline guide
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: box.maxHeight * 0.26,
                  child: IgnorePointer(child: Container(height: 1.2, color: AppColors.line)),
                ),
                if (_pad.isEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.draw_rounded, color: AppColors.lineStrong, size: 30),
                          const SizedBox(height: 6),
                          Text(
                            st == HandwritingStatus.downloading
                                ? '필기 인식 준비 중… (처음 한 번)'
                                : st == HandwritingStatus.unavailable
                                    ? '필기 인식을 쓸 수 없어요 · 키패드를 이용하세요'
                                    : '여기에 답을 쓰세요\n예) 12   -3/2   2.5   2√3',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600, height: 1.5),
                          ),
                        ]),
                      ),
                    ),
                  ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Row(children: [
                    if (_recognizing)
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    IconButton(
                      tooltip: '한 획 지우기',
                      onPressed: _pad.canUndo ? _pad.undo : null,
                      icon: const Icon(Icons.undo_rounded, size: 20),
                    ),
                    IconButton(
                      tooltip: '모두 지우기',
                      onPressed: _pad.isEmpty ? null : _pad.clearAll,
                      icon: const Icon(Icons.clear_rounded, size: 20),
                    ),
                  ]),
                ),
              ]);
            }),
          ),
        );
      },
    );
  }

  Widget _candidateRow() {
    if (_candidates.length <= 1) {
      return const SizedBox(
        height: 36,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('인식된 답이 다르면 다른 후보를 고르거나 키패드로 고치세요',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
        ),
      );
    }
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in _candidates)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(c),
                selected: _text.text == c,
                onSelected: (_) => setState(() => _text.text = c),
              ),
            ),
        ],
      ),
    );
  }

  void _onKey(String k) {
    setState(() {
      final t = _text.text;
      if (k == '⌫') {
        if (t.isNotEmpty) _text.text = t.substring(0, t.length - 1);
      } else if (k == 'C') {
        _text.clear();
      } else {
        _text.text = t + k;
      }
    });
  }

  // ---------------------------------------------------------------- result
  Widget _result(BuildContext context, GradedAnswer g) {
    final p = widget.problem;
    final color = g.correct ? AppColors.correct : AppColors.wrong;
    final given = p.isChoice ? circled(int.tryParse(g.given) ?? 0) : g.given;
    return Column(
      key: const ValueKey('result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.elasticOut,
          builder: (context, s, child) => Transform.scale(scale: s, child: child),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 1.4),
            ),
            child: Row(children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(g.correct ? Icons.circle_outlined : Icons.close_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.correct ? '정답이에요!' : '아쉬워요, 오답이에요',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                  const SizedBox(height: 4),
                  Text('내 답  $given${!p.isChoice && (p.answerUnit ?? '').isNotEmpty ? ' ${p.answerUnit}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                  if (!g.correct)
                    Text('정답  ${g.expectedDisplay}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                  if (!g.correct)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('오답노트에 담았어요',
                          style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: _showSolution || !g.correct
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.menu_book_rounded, size: 18, color: AppColors.inkSoft),
                        SizedBox(width: 6),
                        Text('해설', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ]),
                      const SizedBox(height: 10),
                      MathText(p.solution.isEmpty ? '해설이 없어요.' : p.solution,
                          style: const TextStyle(fontSize: 15.5, color: AppColors.ink, height: 1.7)),
                    ]),
                  )
                : Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showSolution = true),
                      icon: const Icon(Icons.menu_book_rounded),
                      label: const Text('해설 보기'),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          if (widget.onVariant != null && p.hasTemplate || (p.isVariant && widget.onVariant != null))
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onVariant,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('변형문제'),
              ),
            ),
          if (widget.onRetry != null && !g.correct) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('다시 풀기'),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('next'),
          onPressed: widget.onNext,
          icon: Icon(widget.isLast ? Icons.flag_rounded : Icons.arrow_forward_rounded),
          label: Text(widget.isLast ? '결과 보기' : '다음 문제'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.keypad, required this.onChanged});
  final bool keypad;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData icon, bool on, VoidCallback tap) => GestureDetector(
          onTap: tap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: on ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: on ? const [BoxShadow(color: Color(0x141B2A4A), blurRadius: 6)] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: on ? AppColors.ink : AppColors.inkMuted),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? AppColors.ink : AppColors.inkMuted)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.paperDeep, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('손글씨', Icons.draw_rounded, !keypad, () => onChanged(false)),
        KeyedSubtree(key: const Key('mode-keypad'), child: seg('키패드', Icons.dialpad_rounded, keypad, () => onChanged(true))),
      ]),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});
  final ValueChanged<String> onKey;

  static const _keys = [
    ['7', '8', '9', '/'],
    ['4', '5', '6', '√'],
    ['1', '2', '3', 'π'],
    ['-', '0', '.', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _keys)
          Expanded(
            child: Row(
              children: [
                for (final k in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Material(
                        key: Key('key-$k'),
                        color: _isOp(k) ? AppColors.paperDeep : AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onKey(k),
                          onLongPress: k == '⌫' ? () => onKey('C') : null,
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Text(k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static bool _isOp(String k) => !RegExp(r'^[0-9]$').hasMatch(k);
}

/// Grades with the shared grader and formats the expected answer.
GradedAnswer gradeAnswer(Problem p, String input) {
  final r = Grader.grade(p, input);
  return GradedAnswer(input, r.correct, expectedDisplay(p));
}
