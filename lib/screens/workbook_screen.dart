import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import '../widgets/workbook_card.dart' show stageColor, workbookLevelColor;
import 'answer_key_screen.dart';
import 'solve_screen.dart';

/// One 문제집: problems in order, progress, 이어 풀기 / 틀린 것만.
class WorkbookScreen extends StatelessWidget {
  const WorkbookScreen({super.key, required this.workbookId});
  final String workbookId;

  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkbookScreen(workbookId: id)));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final w = app.bank.workbook(workbookId);
    if (w == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('문제집을 찾을 수 없어요')));
    final course = app.bank.subject(w.course);
    final color = Color(course?.color ?? 0xFF5B6475);
    final ps = app.bank.problemsOf(w);
    final (done, total) = app.workbookProgress(w);
    final unsolved = [for (final p in ps) if (!app.isSolved(p.id)) p];
    final wrong = [for (final p in ps) if (app.stateOf(p.id).inWrongNote) p];
    final firstOpen = ps.indexWhere((p) => !app.isSolved(p.id));
    final onShelf = app.hasWorkbook(w.id);
    // 내 교재에 없는 책은 미리보기 — 풀기 버튼을 누르면 담고 바로 시작
    void solve(VoidCallback go) {
      if (!onShelf) {
        app.addWorkbook(w.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「${w.title}」을(를) 내 교재에 담았어요')));
      }
      go();
    }

    return Scaffold(
      appBar: AppBar(title: Text(w.series.isNotEmpty ? w.series : (course?.name ?? '문제집'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, children: [
                  Pill(w.stage, color: stageColor(w.stage)),
                  Pill(w.level, color: workbookLevelColor(w.level)),
                  if (w.scope.isNotEmpty) Pill(w.scope, color: AppColors.inkSoft),
                  if (w.publisher.isNotEmpty) Pill(w.publisher, color: AppColors.inkSoft),
                ]),
                const SizedBox(height: 10),
                Text(w.title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.1)),
                if (w.desc.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(w.desc, style: const TextStyle(fontSize: 15.5, color: AppColors.inkSoft)),
                ],
              ]),
            ),
            ProgressRing(
              value: total == 0 ? 0 : done / total,
              size: 96,
              stroke: 10,
              color: color,
              child: Text('$done/$total', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
          ]),
          const SizedBox(height: 20),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
              key: const Key('wb-continue'),
              style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(0, 52)),
              onPressed: ps.isEmpty
                  ? null
                  : () => solve(() => SolveScreen.open(context,
                      title: w.title, problems: firstOpen <= 0 ? ps : [...ps.sublist(firstOpen), ...ps.sublist(0, firstOpen)])),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(!onShelf
                  ? '내 교재에 담고 풀기'
                  : done == 0
                      ? '처음부터 풀기'
                      : (unsolved.isEmpty ? '다시 풀기' : '이어 풀기 · ${unsolved.length}문항 남음')),
            ),
            if (onShelf)
              OutlinedButton.icon(
                onPressed: () => SolveScreen.endless(context, workbookId: w.id, title: w.title),
                icon: const Icon(Icons.all_inclusive_rounded),
                label: const Text('무한 풀기'),
              ),
            if (wrong.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => SolveScreen.open(context,
                    title: '${w.title} · 오답 변형', problems: [for (final p in wrong) app.makeVariant(p)], mode: 'variant'),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text('틀린 ${wrong.length}문항 변형으로'),
              ),
            OutlinedButton.icon(
              onPressed: ps.isEmpty
                  ? null
                  : () => solve(() => SolveScreen.open(context,
                      title: '${w.title} · 모의고사', problems: ps, mode: 'exam', timeLimitMs: ps.length * 3 * 60000)),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('시험처럼 풀기'),
            ),
            if (app.isTeacher)
              OutlinedButton.icon(
                key: const Key('wb-answers'),
                onPressed: () => AnswerKeyScreen.open(context, w.id),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('답안표'),
              ),
            TextButton.icon(
              key: const Key('wb-toggle'),
              onPressed: () {
                if (onShelf) {
                  app.removeWorkbook(w.id);
                } else {
                  app.addWorkbook(w.id);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(onShelf ? '내 교재에서 뺐어요 · 푼 기록은 그대로 남아요' : '내 교재에 담았어요')));
              },
              icon: Icon(onShelf ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded),
              label: Text(onShelf ? '내 교재에서 빼기' : '내 교재에 담기'),
            ),
          ]),
          const SizedBox(height: 24),
          // 단원이 여럿인 교재(FLOW·BRIDGE TYPE 처럼)는 단원별로 묶어서 — 번호는 교재 전체 번호 그대로
          for (final (unit, idx) in byTableOfContents(ps)) ...[
            if (unit.isNotEmpty) _SectionHeader(name: unit, color: color, count: idx.length, onSolve: () {
              solve(() => SolveScreen.open(context, title: '${w.title} · $unit', problems: [for (final i in idx) ps[i]]));
            }),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var k = 0; k < idx.length; k++) ...[
                  if (k > 0) const Divider(height: 1),
                  _Row(n: idx[k] + 1, problem: ps[idx[k]], color: color, onTap: () {
                    final i = idx[k];
                    solve(() => SolveScreen.open(context, title: w.title, problems: [...ps.sublist(i), ...ps.sublist(0, i)]));
                  }),
                ],
              ]),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

/// 교재의 문항을 목차별로 — 교재에 목차(section)가 있으면 그것, 없으면 단원으로.
/// 묶을 거리가 하나뿐이면 묶지 않는다. 값은 [ps] 안의 자리번호.
List<(String, List<int>)> byTableOfContents(List<Problem> ps) {
  final useSection = ps.any((p) => p.section.trim().isNotEmpty);
  final order = <String>[];
  final by = <String, List<int>>{};
  for (var i = 0; i < ps.length; i++) {
    final k = (useSection ? ps[i].section : ps[i].unit).trim();
    if (!by.containsKey(k)) {
      order.add(k);
      by[k] = [];
    }
    by[k]!.add(i);
  }
  if (order.length < 2) return [('', [for (var i = 0; i < ps.length; i++) i])];
  return [for (final k in order) (k, by[k]!)];
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.name, required this.color, required this.count, required this.onSolve});
  final String name;
  final Color color;
  final int count;
  final VoidCallback onSolve;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(children: [
        Container(width: 5, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(width: 8),
        Text('$count문항', style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w700, fontSize: 13)),
        const Spacer(),
        TextButton.icon(
          key: Key('wb-unit-$name'),
          onPressed: onSolve,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('이 목차 풀기'),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.n, required this.problem, required this.color, required this.onTap});
  final int n;
  final Problem problem;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final st = app.stateOf(problem.id);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(children: [
          SizedBox(
            width: 36,
            child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.inkSoft)),
          ),
          ResultMark(correct: st.attempts == 0 ? null : st.lastCorrect, size: 26),
          const SizedBox(width: 14),
          SizedBox(
            width: 180,
            child: Text(problem.topic.isEmpty ? problem.unit : problem.topic,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(MathText.plain(problem.stem).replaceAll('\n', ' '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkSoft)),
          ),
          const SizedBox(width: 12),
          if (problem.source != null) ...[
            Pill('기출', color: AppColors.accent, dense: true),
            const SizedBox(width: 8),
          ],
          if (problem.passageId != null) ...[
            const Pill('지문', color: AppColors.inkSoft, dense: true),
            const SizedBox(width: 8),
          ],
          DifficultyDots(problem.difficulty, color: color, size: 6),
        ]),
      ),
    );
  }
}
