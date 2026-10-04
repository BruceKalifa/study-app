import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import '../widgets/workbook_card.dart' show workbookLevelColor;
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

    return Scaffold(
      appBar: AppBar(title: Text(w.series.isNotEmpty ? w.series : (course?.name ?? '문제집'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Pill(w.level, color: workbookLevelColor(w.level)),
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
                  : () => SolveScreen.open(context,
                      title: w.title, problems: firstOpen <= 0 ? ps : [...ps.sublist(firstOpen), ...ps.sublist(0, firstOpen)]),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(done == 0 ? '처음부터 풀기' : (unsolved.isEmpty ? '다시 풀기' : '이어 풀기 · ${unsolved.length}문항 남음')),
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
                  : () => SolveScreen.open(context, title: '${w.title} · 모의고사', problems: ps, mode: 'exam', timeLimitMs: ps.length * 3 * 60000),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('시험처럼 풀기'),
            ),
          ]),
          const SizedBox(height: 24),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < ps.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _Row(n: i + 1, problem: ps[i], color: color, onTap: () {
                  SolveScreen.open(context, title: w.title, problems: [...ps.sublist(i), ...ps.sublist(0, i)]);
                }),
              ],
            ]),
          ),
        ],
      ),
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
