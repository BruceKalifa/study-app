import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/answer_panel.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import 'solve_screen.dart';

class SessionItem {
  final Problem problem;
  final GradedAnswer? graded;
  final int timeMs;
  const SessionItem({required this.problem, required this.graded, required this.timeMs});
}

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.title, required this.items, required this.mode});
  final String title;
  final List<SessionItem> items;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final answered = items.where((e) => e.graded != null).toList();
    final correct = answered.where((e) => e.graded!.correct).length;
    final wrong = answered.where((e) => !e.graded!.correct).toList();
    final total = answered.length;
    final acc = total == 0 ? 0.0 : correct / total;
    final time = items.fold<int>(0, (s, e) => s + e.timeMs);
    final message = total == 0
        ? '아직 채점한 문제가 없어요'
        : acc >= 0.9
            ? '완벽에 가까워요! 👏'
            : acc >= 0.7
                ? '잘했어요! 틀린 문제만 다시 볼까요?'
                : acc >= 0.4
                    ? '좋아요, 오답을 복습하면 금방 올라가요'
                    : '괜찮아요. 해설을 보고 변형문제로 다시 연습해요';

    return Scaffold(
      appBar: AppBar(title: Text('$title · 결과')),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final summary = Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProgressRing(
                  value: acc,
                  size: 190,
                  stroke: 16,
                  color: accuracyColor(acc),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$correct / $total',
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
                    Text('정답률 ${pct(acc)}',
                        style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 20),
                Text(message,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: _mini('걸린 시간', fmtDuration(time), Icons.timer_outlined)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _mini('문제당 평균', total == 0 ? '-' : fmtDuration(time ~/ (total == 0 ? 1 : total)),
                          Icons.speed_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: _mini('오늘 푼 문제', '${app.todayCount}', Icons.today_rounded)),
                ]),
                const SizedBox(height: 22),
                if (wrong.isNotEmpty) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: AppColors.accent),
                    onPressed: () => SolveScreen.open(context,
                        title: '$title · 변형 복습',
                        mode: 'variant',
                        problems: [for (final w in wrong) app.makeVariant(w.problem)]),
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text('틀린 ${wrong.length}문제 변형문제로 복습'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: () => SolveScreen.open(context,
                        title: '$title · 다시 풀기', mode: 'review', problems: [for (final w in wrong) w.problem]),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('틀린 문제 다시 풀기'),
                  ),
                  const SizedBox(height: 10),
                ],
                TextButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('홈으로'),
                ),
              ],
            ),
          ),
        );
        final list = ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final it = items[i];
            final p = it.problem;
            final g = it.graded;
            final color = Color(app.bank.subject(p.subjectId)?.color ?? 0xFF2F6BFF);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ResultMark(correct: g?.correct, size: 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('${i + 1}번', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Pill(p.topic.isNotEmpty ? p.topic : p.unit, color: color, dense: true),
                        if (p.isVariant || p.isTwin) ...[
                          const SizedBox(width: 6),
                          const Pill('변형', color: AppColors.accent, dense: true),
                        ],
                        const Spacer(),
                        Text(fmtDuration(it.timeMs),
                            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 8),
                      MathText(MathText.plain(p.stem).length > 120 ? '${MathText.plain(p.stem).substring(0, 120)}…' : p.stem,
                          maxLines: 2, style: const TextStyle(fontSize: 14.5, color: AppColors.inkSoft)),
                      if (g != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          g.correct
                              ? '내 답 ${p.isChoice ? circled(int.tryParse(g.given) ?? 0) : g.given}'
                              : '내 답 ${p.isChoice ? circled(int.tryParse(g.given) ?? 0) : g.given}  →  정답 ${g.expectedDisplay}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: g.correct ? AppColors.correct : AppColors.wrong),
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('풀지 않음', style: TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                ]),
              ),
            );
          },
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 420, child: SingleChildScrollView(child: summary)),
                  const SizedBox(width: 24),
                  Expanded(child: list),
                ])
              : ListView(children: [summary, const SizedBox(height: 16), ...[
                  for (var i = 0; i < items.length; i++)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: SizedBox(child: _compact(items[i], i))),
                ]]),
        );
      }),
    );
  }

  Widget _compact(SessionItem it, int i) {
    final g = it.graded;
    return Card(
      child: ListTile(
        leading: ResultMark(correct: g?.correct),
        title: Text('${i + 1}번 · ${it.problem.topic}'),
        subtitle: Text(g == null ? '풀지 않음' : (g.correct ? '정답' : '정답 ${g.expectedDisplay}')),
      ),
    );
  }

  Widget _mini(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Icon(icon, size: 18, color: AppColors.inkMuted),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
      ]),
    );
  }
}
