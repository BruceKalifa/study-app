import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/problem.dart';
import 'common.dart';
import 'math_text.dart';

/// Keys into the printed sheet so the solve screen can find, in page coordinates,
/// where the choices and the answer box are (for pen/finger taps and answer handwriting).
class ExamSheetKeys {
  final GlobalKey root = GlobalKey(debugLabel: 'sheet');
  final GlobalKey answerBox = GlobalKey(debugLabel: 'answer-box');
  final List<GlobalKey> choices = List.generate(8, (i) => GlobalKey(debugLabel: 'choice-$i'));

  /// Rect of [k] in page coordinates (the sheet is laid out at page scale at the page origin).
  Rect? rectOf(GlobalKey k) {
    final root = this.root.currentContext?.findRenderObject();
    final box = k.currentContext?.findRenderObject();
    if (root is! RenderBox || box is! RenderBox || !box.attached || !box.hasSize || !root.attached) return null;
    // include the print-size scaling between the item and the page
    return MatrixUtils.transformRect(box.getTransformTo(root), Offset.zero & box.size);
  }

  Rect? get answerRect => rectOf(answerBox);

  /// 1-based choice under [pos], or null.
  int? choiceAt(Offset pos, int count) {
    for (var i = 0; i < count && i < choices.length; i++) {
      final r = rectOf(choices[i]);
      if (r != null && r.inflate(10).contains(pos)) return i + 1;
    }
    return null;
  }
}

/// 배점 like a 모의고사 paper: easy 2점, normal 3점, hard 4점 (교재 문항은 [Problem.points], 0 = 없음).
int problemPoints(Problem p) => p.points ?? (p.difficulty <= 2 ? 2 : (p.difficulty == 3 ? 3 : 4));

/// The printed part of the page, laid out like a 모의고사 시험지 at page scale (width 1000)
/// under the ink. Everything else on the page is writing space.
class ProblemSheet extends StatelessWidget {
  const ProblemSheet({
    super.key,
    required this.problem,
    required this.number,
    required this.color,
    required this.keys,
    this.selectedChoice,
    this.revealAnswer = false,
    this.mark,
    this.answerText,
    this.answerNote,
    this.answerBoxEmpty = true,
    this.zoom = 1,
    this.columnFraction = 1,
    this.serif = true,
    this.passage,
    this.passageLabel,
  });

  /// 지문형: the passage printed with the question (left column in landscape, on top in portrait).
  final Passage? passage;

  /// e.g. "[1~3] 다음 글을 읽고 물음에 답하시오."
  final String? passageLabel;

  final Problem problem;
  final int number;
  final Color color;
  final ExamSheetKeys keys;
  final int? selectedChoice;

  /// Show the correct choice / answer (after grading).
  final bool revealAnswer;

  /// Teacher-style red mark over the number: true = ○, false = ╱, null = none.
  final bool? mark;

  /// Short answer as recognised from the answer box (or typed).
  final String? answerText;

  /// Small status line under the answer box (e.g. "인식 중…").
  final String? answerNote;
  final bool answerBoxEmpty;

  /// Print size relative to the page (< 1 in landscape, where the page is shown much wider,
  /// so the text keeps the same size on screen as in portrait).
  final double zoom;

  /// Share of the line the problem column takes (narrower in landscape: the right side is for solving).
  final double columnFraction;
  final bool serif;

  static const double _indent = 58;

  @override
  Widget build(BuildContext context) {
    final p = problem;
    final face = serif ? (p.texStyle ? AppTheme.texSerif : AppTheme.serif) : AppTheme.font;
    final correctChoice = int.tryParse(p.answer);
    const sans = AppTheme.font;
    final k = zoom.clamp(0.4, 1.0);
    final contentWidth = 1000 / k;
    final line = contentWidth - 128;
    final sideBySide = passage != null && columnFraction < 1;
    final columnWidth = sideBySide ? line * 0.47 : line * columnFraction.clamp(0.3, 1.0);
    // laid out wider and scaled down to the page width; [keys.root] stays in page coordinates
    return SizedBox(
      key: keys.root,
      width: 1000,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: contentWidth,
          child: _content(context, p, face, sans, correctChoice, columnWidth, line, sideBySide),
        ),
      ),
    );
  }

  Widget _passageBox(Passage ps) {
    final paras = ps.body.split(RegExp(r'\n\s*\n'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(passageLabel ?? '다음 글을 읽고 물음에 답하시오.',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.5)),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 14),
        decoration: BoxDecoration(border: Border.all(color: AppColors.ink, width: 1.2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final para in paras)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MathText('\u3000${para.trim()}', style: const TextStyle(fontSize: 23, height: 1.8)),
            ),
          if ((ps.source ?? '').isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Text(ps.source!, style: const TextStyle(fontSize: 17, color: AppColors.inkMuted)),
            ),
        ]),
      ),
    ]);
  }

  Widget _content(BuildContext context, Problem p, String face, String sans, int? correctChoice, double columnWidth,
      double line, bool sideBySide) {
    final ps = passage;
    final column = _problemColumn(p, correctChoice, columnWidth);
    return DefaultTextStyle(
      style: TextStyle(fontFamily: face, fontSize: 25, height: 1.75, color: AppColors.ink),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(64, 104, 64, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── header, like the top of a 시험지
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${p.subjectName} 영역',
                    style: TextStyle(
                        fontFamily: sans, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.4)),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    [p.unit, if (p.topic.isNotEmpty) p.topic].join('  ·  '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: sans, fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.inkMuted, height: 1.3),
                  ),
                ),
                const SizedBox(width: 12),
                DifficultyDots(p.difficulty, color: color, size: 8),
                if (p.source != null && p.label == null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(p.source!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: sans, fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accent)),
                  ),
                ],
                if (p.isVariant || p.isTwin) ...[
                  const SizedBox(width: 10),
                  const Pill('변형', color: AppColors.accent, icon: Icons.auto_awesome_rounded, dense: true),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Container(height: 3, color: AppColors.ink),
            const SizedBox(height: 3),
            Container(height: 1, color: AppColors.ink),
            const SizedBox(height: 34),
            if (ps != null && sideBySide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: line * 0.49, child: _passageBox(ps)),
                SizedBox(width: line * 0.04),
                column,
              ])
            else ...[
              if (ps != null) ...[_passageBox(ps), const SizedBox(height: 36)],
              column,
            ],
          ],
        ),
      ),
    );
  }

  Widget _problemColumn(Problem p, int? correctChoice, double columnWidth) {
    return SizedBox(
              width: columnWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.label != null)
                    Padding(
                      padding: const EdgeInsets.only(left: _indent, bottom: 12),
                      child: TexLabel(p, fontSize: 17),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _indent,
                        child: Stack(clipBehavior: Clip.none, children: [
                          Text('$number.',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.55)),
                          if (mark != null)
                            Positioned(
                              left: -13,
                              top: -10,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.easeOutCubic,
                                builder: (context, t, _) => CustomPaint(
                                  size: const Size(66, 62),
                                  painter: _MarkPainter(correct: mark!, progress: t),
                                ),
                              ),
                            ),
                        ]),
                      ),
                      Expanded(
                        // a stem that ends with a table gets its 배점 on the next line
                        child: MathText(_stemWithPoints(p),
                            texStyle: p.texStyle,
                            mathScale: p.texStyle ? texMathScale : 1.06,
                            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w400)),
                      ),
                    ],
                  ),
                  if (p.boxItems.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Padding(
                      padding: const EdgeInsets.only(left: _indent),
                      child: _BoxItems(items: p.boxItems),
                    ),
                  ],
                  if (p.isChoice && p.choices.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Padding(
                      padding: const EdgeInsets.only(left: _indent - 6),
                      child: _Choices(
                        choices: p.choices,
                        keys: keys.choices,
                        selected: selectedChoice,
                        correct: revealAnswer ? correctChoice : null,
                        color: color,
                      ),
                    ),
                  ],
                  if (!p.isChoice) ...[
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.only(left: _indent),
                      child: _AnswerBox(
                        boxKey: keys.answerBox,
                        unit: p.answerUnit,
                        empty: answerBoxEmpty,
                        text: answerText,
                        note: answerNote,
                        reveal: revealAnswer ? p.answer : null,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            );
  }
}

/// The stem with its 배점; a stem that ends with a table or a block gets it on the next line.
String _stemWithPoints(Problem p) {
  final pts = problemPoints(p);
  if (pts <= 0) return p.stem;
  final last = p.stem.trimRight().split('\n').last.trim();
  final block = last.startsWith('|') || last.startsWith(r'$$') || last.startsWith('[[');
  return block ? '${p.stem}\n[$pts점]' : '${p.stem}  [$pts점]';
}

/// 원문 수식 글꼴 크기: 본문(Noto Serif KR, 원문 Scale 0.92)보다 조금 크게.
const double texMathScale = 1.08;

/// 교재 머리표: 검은(또는 주황) 상자에 흰 글씨 + 옅은 회색 출처 — TeX 원문의 \TagBox.
class TexLabel extends StatelessWidget {
  const TexLabel(this.problem, {super.key, this.fontSize = 13});
  final Problem problem;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = problem;
    final src = p.source ?? '';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: fontSize * 0.6,
      runSpacing: 4,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: fontSize * 0.42, vertical: fontSize * 0.14),
          color: p.labelColor != null ? Color(p.labelColor!) : (p.labelAccent ? AppTheme.texAccent : Colors.black),
          child: Text(p.label ?? '',
              style: TextStyle(
                  fontFamily: AppTheme.font, fontSize: fontSize, height: 1.3, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
        if (src.isNotEmpty)
          Text(src,
              style: TextStyle(fontFamily: AppTheme.font, fontSize: fontSize, height: 1.3, color: AppTheme.texFaint)),
      ],
    );
  }
}

/// Teacher's red pen: ○ for correct, a slash for wrong.
class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.correct, required this.progress});
  final bool correct;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE0353B).withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;
    if (correct) {
      final rect = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
      canvas.drawArc(rect, -math.pi * 0.62, math.pi * 2.08 * progress, false, paint);
    } else {
      final a = Offset(size.width * 0.86, size.height * 0.06);
      final b = Offset(size.width * 0.14, size.height * 0.96);
      canvas.drawLine(a, Offset.lerp(a, b, progress)!, paint);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.progress != progress || old.correct != correct;
}

class _BoxItems extends StatelessWidget {
  const _BoxItems({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(26, 30, 26, 16),
          decoration: BoxDecoration(border: Border.all(color: AppColors.ink, width: 1.4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MathText(it, style: const TextStyle(fontSize: 23)),
                ),
            ],
          ),
        ),
        Positioned(
          top: -17,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              color: const Color(0xFFFFFDF8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: const Text('<보 기>', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.choices,
    required this.keys,
    required this.selected,
    required this.correct,
    required this.color,
  });
  final List<String> choices;
  final List<GlobalKey> keys;
  final int? selected;
  final int? correct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final longest = choices.fold<int>(0, (m, c) => math.max(m, MathText.plain(c).length));
    final perRow = longest <= 6 ? 5 : (longest <= 16 ? 3 : (longest <= 26 ? 2 : 1));
    final rows = <List<int>>[];
    for (var i = 0; i < choices.length; i += perRow) {
      rows.add([for (var j = i; j < i + perRow && j < choices.length; j++) j]);
    }
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in row)
                  Expanded(
                    child: Container(
                      key: Key('choice-${i + 1}'),
                      child: KeyedSubtree(
                        key: i < keys.length ? keys[i] : null,
                        child: _ChoiceItem(
                          n: i + 1,
                          text: choices[i],
                          selected: selected == i + 1,
                          correct: correct == null ? null : correct == i + 1,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                for (var k = row.length; k < perRow; k++) const Expanded(child: SizedBox()),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChoiceItem extends StatelessWidget {
  const _ChoiceItem({required this.n, required this.text, required this.selected, required this.correct, required this.color});
  final int n;
  final String text;
  final bool selected;
  final bool? correct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // tap target is the whole item; generous vertical padding makes it easy to hit with a finger
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.07) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            height: 42,
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.ink : Colors.transparent,
                  border: Border.all(color: AppColors.ink, width: 1.6),
                ),
                child: Text('$n',
                    style: TextStyle(
                        fontFamily: AppTheme.font,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: selected ? Colors.white : AppColors.ink)),
              ),
              if (correct == true)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE0353B), width: 3.5),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 6),
          Expanded(child: MathText(text, style: const TextStyle(fontSize: 24))),
        ],
      ),
    );
  }
}

class _AnswerBox extends StatelessWidget {
  const _AnswerBox({
    required this.boxKey,
    required this.unit,
    required this.empty,
    required this.text,
    required this.note,
    required this.reveal,
    required this.color,
  });
  final GlobalKey boxKey;
  final String? unit;
  final bool empty;
  final String? text;
  final String? note;
  final String? reveal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const sans = AppTheme.font;
    final u = unit ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              key: boxKey,
              width: 330,
              height: 104,
              decoration: BoxDecoration(
                color: const Color(0x08000000),
                border: Border.all(color: AppColors.ink, width: 1.8),
              ),
              child: Stack(children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    color: AppColors.ink,
                    child: const Text('답',
                        style: TextStyle(fontFamily: sans, fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, height: 1.3)),
                  ),
                ),
                if (empty)
                  const Center(
                    child: Text('여기에 답을 쓰세요',
                        style: TextStyle(fontFamily: sans, fontSize: 16, color: AppColors.lineStrong, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
            if (u.isNotEmpty) ...[
              const SizedBox(width: 14),
              Flexible(child: Text(u, style: const TextStyle(fontSize: 26))),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 2,
          children: [
            if (text != null && text!.isNotEmpty) ...[
              Icon(Icons.auto_awesome_rounded, size: 20, color: color),
              Text('인식된 답', style: TextStyle(fontFamily: sans, fontSize: 17, fontWeight: FontWeight.w700, color: color)),
              Text(u.isEmpty ? text! : '${text!} $u',
                  key: const Key('recognized-answer'),
                  style: const TextStyle(fontFamily: sans, fontSize: 22, fontWeight: FontWeight.w800, height: 1.3)),
              if (reveal == null)
                const Text('  다르면 답칸을 손가락으로 톡',
                    style: TextStyle(fontFamily: sans, fontSize: 14.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            ] else if (note != null)
              Text(note!,
                  style: const TextStyle(fontFamily: sans, fontSize: 16, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            if (reveal != null)
              Text('   정답  ${u.isEmpty ? reveal! : '${reveal!} $u'}',
                  style: const TextStyle(fontFamily: sans, fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFFE0353B))),
          ],
        ),
      ],
    );
  }
}
