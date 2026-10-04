import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/grader.dart';
import '../core/problem.dart';
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

/// How an answer reads in the UI ("3번" for a choice, "12 m/s" for a short answer).
String answerDisplay(Problem p, String answer) {
  if (p.isChoice) return circled(int.tryParse(answer) ?? 0);
  final u = p.answerUnit;
  return u == null || u.isEmpty ? answer : '$answer $u';
}

/// Grades with the shared grader and formats the expected answer.
GradedAnswer gradeAnswer(Problem p, String input) {
  final r = Grader.grade(p, input);
  return GradedAnswer(input, r.correct, expectedDisplay(p));
}

/// Bottom sheet to type / fix a short answer (other recognition candidates + keypad).
/// Returns the new answer, '' to clear it, or null when cancelled.
Future<String?> showAnswerKeypad(
  BuildContext context, {
  required Problem problem,
  String initial = '',
  List<String> candidates = const [],
  Color color = AppColors.blue,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => _KeypadSheet(problem: problem, initial: initial, candidates: candidates, color: color),
  );
}

class _KeypadSheet extends StatefulWidget {
  const _KeypadSheet({required this.problem, required this.initial, required this.candidates, required this.color});
  final Problem problem;
  final String initial;
  final List<String> candidates;
  final Color color;

  @override
  State<_KeypadSheet> createState() => _KeypadSheetState();
}

class _KeypadSheetState extends State<_KeypadSheet> {
  late String _t = widget.initial;

  void _onKey(String k) {
    setState(() {
      if (k == '⌫') {
        if (_t.isNotEmpty) _t = _t.substring(0, _t.length - 1);
      } else if (k == 'C') {
        _t = '';
      } else {
        _t += k;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.problem.answerUnit;
    final others = widget.candidates.where((c) => c != _t).toList();
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('답 고치기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('답칸에 쓴 글씨가 다르게 인식됐을 때 여기서 고쳐요',
                  style: TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Container(
                height: 66,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.color, width: 2),
                ),
                child: Row(children: [
                  const Text('답', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkMuted)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(_t.isEmpty ? '—' : _t,
                        key: const Key('keypad-value'),
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                  if (unit != null && unit.isNotEmpty)
                    Text(unit, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                ]),
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 9),
                    child: Text('다른 후보', style: TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
                  ),
                  for (final c in others)
                    ActionChip(label: Text(c), onPressed: () => setState(() => _t = c)),
                ]),
              ],
              const SizedBox(height: 12),
              SizedBox(height: 300, child: AnswerKeypad(onKey: _onKey)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const Key('keypad-ok'),
                    onPressed: () => Navigator.pop(context, _t.trim()),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: widget.color),
                    child: const Text('이 답으로 할게요'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class AnswerKeypad extends StatelessWidget {
  const AnswerKeypad({super.key, required this.onKey});
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

/// 해설 bottom sheet.
Future<void> showSolutionSheet(BuildContext context, Problem p, GradedAnswer? g) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      minChildSize: 0.3,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 32),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.menu_book_rounded, color: AppColors.inkSoft),
            const SizedBox(width: 8),
            const Text('해설', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Spacer(),
            if (g != null)
              Text(
                g.correct ? '정답 ${g.expectedDisplay}' : '내 답 ${answerDisplay(p, g.given)}  ·  정답 ${g.expectedDisplay}',
                style: TextStyle(fontWeight: FontWeight.w800, color: g.correct ? AppColors.correct : AppColors.wrong),
              ),
          ]),
          const SizedBox(height: 16),
          MathText(p.solution.isEmpty ? '해설이 없어요.' : p.solution,
              style: const TextStyle(fontSize: 18, color: AppColors.ink, height: 1.8)),
          if ((p.hint ?? '').isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.reviewSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_rounded, color: AppColors.review, size: 20),
                const SizedBox(width: 8),
                Expanded(child: MathText(p.hint!, style: const TextStyle(fontSize: 16, height: 1.7))),
              ]),
            ),
          ],
        ],
      ),
    ),
  );
}
