import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../app/records.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/answer_panel.dart' show gradeAnswer, expectedDisplay, answerDisplay, showAnswerKeypad;
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import 'workbook_screen.dart' show byTableOfContents, tocRowLabel, usesTableOfContents;

/// 답안표 — 교재의 문항을 목차별로 한눈에 보는 표.
///
///  · 학생: 자기 답을 쭉 적고 한 번에 채점한다 (시험지 풀고 옮겨 적듯이).
///    이미 채점된 문항은 잠기고 O/X 와 정답이 보인다.
///  · 선생님: 정답을 보고 고친다. 고친 정답은 서버를 거쳐 학생 태블릿까지 반영된다.
class AnswerKeyScreen extends StatefulWidget {
  const AnswerKeyScreen({super.key, required this.workbookId});
  final String workbookId;

  static Future<void> open(BuildContext context, String workbookId) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AnswerKeyScreen(workbookId: workbookId)));

  @override
  State<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}

class _AnswerKeyScreenState extends State<AnswerKeyScreen> {
  final _typed = <String, String>{}; // 문항 id → 적은 답 (학생: 내 답, 선생님: 고친 정답)
  final _controllers = <String, TextEditingController>{};
  bool _busy = false;
  String _msg = '';
  bool _bad = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(Problem p, {required String initial}) =>
      _controllers.putIfAbsent(p.id, () => TextEditingController(text: initial));

  void _say(String msg, {bool bad = false}) {
    if (mounted) {
      setState(() {
        _msg = msg;
        _bad = bad;
      });
    }
  }

  /// 선생님: 정답 고쳐 저장.
  Future<void> _saveKey(AppState app, String bookId) async {
    FocusScope.of(context).unfocus();
    final changes = Map<String, String>.from(_typed);
    if (changes.isEmpty) {
      _say('고친 정답이 없어요');
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final n = await app.updateAnswers(bookId, changes);
      _typed.clear();
      _say('$n개 고쳤어요 · 서버에 올리는 중이에요');
    } catch (e) {
      _say('저장하지 못했어요', bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// 학생: 적어 둔 답을 한 번에 채점.
  Future<void> _grade(AppState app, List<Problem> ps) async {
    FocusScope.of(context).unfocus();
    final todo = [
      for (final p in ps)
        if ((_typed[p.id] ?? '').trim().isNotEmpty && app.stateOf(p.id).attempts == 0) p,
    ];
    if (todo.isEmpty) {
      _say('적은 답이 없어요');
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    var right = 0;
    for (final p in todo) {
      final given = _typed[p.id]!.trim();
      final g = gradeAnswer(p, given);
      if (g.correct) right++;
      await app.record(p,
          answer: given, expected: expectedDisplay(p), correct: g.correct, timeMs: 0, mode: 'practice');
      _typed.remove(p.id);
    }
    _say('${todo.length}문항 채점 · 맞은 개수 $right');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final w = app.bank.workbook(widget.workbookId);
    if (w == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('문제집을 찾을 수 없어요')));
    final ps = app.bank.problemsOf(w);
    final teacher = app.isTeacher;
    final bookId = teacher ? app.bookIdOfWorkbook(w.id) : null;
    final course = app.bank.subject(w.course);
    final color = Color(course?.color ?? 0xFF5B6475);
    final toc = usesTableOfContents(ps);
    // 학생이 적었던 답 (문항마다 마지막 풀이)
    final mine = <String, Attempt>{for (final a in app.attempts) a.problemId: a};
    final left = teacher ? 0 : ps.where((p) => app.stateOf(p.id).attempts == 0).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${w.title} · 답안표'),
        actions: [
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(_msg,
                    key: const Key('answers-msg'),
                    style: TextStyle(fontWeight: FontWeight.w700, color: _bad ? AppColors.wrong : AppColors.correct)),
              ),
            ),
          if (teacher && bookId != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                key: const Key('answers-save'),
                onPressed: _busy ? null : () => _saveKey(app, bookId),
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(_typed.isEmpty ? '저장' : '저장 (${_typed.length})'),
              ),
            ),
          if (!teacher)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                key: const Key('answers-grade'),
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: _busy || _typed.isEmpty ? null : () => _grade(app, ps),
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(_typed.isEmpty ? '채점하기' : '채점하기 (${_typed.length})'),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 60),
        children: [
          Text(
            teacher
                ? (bookId == null
                    ? '이 교재는 앱에 들어 있는 문제라 여기서는 정답을 고칠 수 없어요'
                    : '정답을 고치면 저장할 때 학생 태블릿까지 반영돼요')
                : '푼 문제를 보고 답을 적은 뒤 채점하세요 · 아직 안 푼 $left문항'
                    '${left == ps.length ? '' : ' · 채점된 문항은 고칠 수 없어요'}',
            style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          for (final (section, idx) in byTableOfContents(ps)) ...[
            if (section.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 6),
                child: Row(children: [
                  Container(
                      width: 5, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 10),
                  Text(section, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(width: 8),
                  Text('${idx.length}문항',
                      style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var k = 0; k < idx.length; k++) ...[
                  if (k > 0) const Divider(height: 1),
                  _AnswerRow(
                    n: idx[k] + 1,
                    problem: ps[idx[k]],
                    color: color,
                    teacher: teacher,
                    withUnit: toc,
                    state: app.stateOf(ps[idx[k]].id),
                    attempt: mine[ps[idx[k]].id],
                    controller: _controllerFor(ps[idx[k]], initial: teacher ? ps[idx[k]].answer : ''),
                    editable: teacher ? bookId != null : app.stateOf(ps[idx[k]].id).attempts == 0,
                    changed: _typed.containsKey(ps[idx[k]].id),
                    onChanged: (v) {
                      final p = ps[idx[k]];
                      setState(() {
                        final t = v.trim();
                        if (t.isEmpty || (teacher && t == p.answer.trim())) {
                          _typed.remove(p.id);
                        } else {
                          _typed[p.id] = t;
                        }
                      });
                    },
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.n,
    required this.problem,
    required this.color,
    required this.teacher,
    required this.withUnit,
    required this.state,
    required this.attempt,
    required this.controller,
    required this.editable,
    required this.changed,
    required this.onChanged,
  });
  final int n;
  final Problem problem;
  final Color color;
  final bool teacher;
  final bool withUnit;
  final ProblemState state;
  final Attempt? attempt;
  final TextEditingController controller;
  final bool editable;
  final bool changed;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = problem;
    final choices = p.choices.isNotEmpty;
    final graded = !teacher && state.attempts > 0;
    return Container(
      color: changed ? AppColors.reviewSoft : null,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(children: [
        SizedBox(
          width: 36,
          child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.inkSoft)),
        ),
        SizedBox(
          width: 230,
          child: Text(tocRowLabel(p, withUnit: withUnit),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Text(MathText.plain(p.stem).replaceAll('\n', ' '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkMuted)),
        ),
        const SizedBox(width: 12),
        // 학생: 채점된 문항은 내가 쓴 답과 O/X, 아직 안 푼 문항은 입력칸
        if (graded) ...[
          SizedBox(
            width: 130,
            child: Text(answerDisplay(p, attempt?.answer ?? state.lastWrongAnswer ?? ''),
                key: Key('answer-done-${p.id}'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: state.lastCorrect == true ? AppColors.correct : AppColors.wrong)),
          ),
          const SizedBox(width: 10),
          ResultMark(correct: state.lastCorrect, size: 24),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text('정답 ${expectedDisplay(p)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
          ),
        ] else ...[
          SizedBox(
            width: choices ? 130 : 170,
            child: TextField(
              key: Key('answer-${p.id}'),
              controller: controller,
              enabled: editable,
              textAlign: TextAlign.center,
              keyboardType: choices ? TextInputType.number : TextInputType.text,
              inputFormatters:
                  choices ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)] : null,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: changed ? AppColors.review : AppColors.ink),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                hintText: teacher ? '정답' : '내 답',
                // 복소수(i)·√·π·±·구간 기호 키패드 — 시스템 키보드에 없는 기호를 넣을 때
                suffixIcon: choices || !editable
                    ? null
                    : IconButton(
                        key: Key('answer-keypad-${p.id}'),
                        tooltip: '수학 기호 키패드 (i, √, π, ±, ∞ …)',
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        icon: const Icon(Icons.calculate_outlined),
                        onPressed: () async {
                          final res = await showAnswerKeypad(context, problem: p, initial: controller.text, color: color);
                          if (res == null) return;
                          controller.text = res;
                          onChanged(res);
                        },
                      ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: changed ? AppColors.review : AppColors.line)),
              ),
              onChanged: onChanged,
            ),
          ),
          if (!teacher) const SizedBox(width: 124),
        ],
      ]),
    );
  }
}
