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
        // 요약: 큰 고정폭 "맞힌 수 / 푼 수" 아래에 형광펜 띠 하나 — 이 화면에서 눈에 띄는 건 이것뿐.
        final summary = Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('맞힌 문제', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                      left: -4,
                      right: -6,
                      bottom: 6,
                      height: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: total == 0 ? Colors.transparent : AppColors.highlight,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '$correct'),
                        TextSpan(
                            text: ' / $total',
                            style: const TextStyle(fontSize: 30, color: AppColors.inkMuted, letterSpacing: -0.8)),
                      ]),
                      style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -2,
                          height: 1.0,
                          color: AppColors.ink,
                          fontFeatures: AppColors.tabular),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: AccuracyBar(value: acc, color: accuracyColor(acc), height: 8)),
                  const SizedBox(width: 12),
                  Text('정답률 ${pct(acc)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: AppColors.inkSoft, fontFeatures: AppColors.tabular)),
                ]),
                const SizedBox(height: 18),
                Text(message, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                const SizedBox(height: 18),
                const Divider(height: 1),
                IntrinsicHeight(
                  child: Row(children: [
                    Expanded(child: _mini('걸린 시간', fmtDuration(time))),
                    const VerticalDivider(width: 1),
                    Expanded(child: _mini('문제당 평균', total == 0 ? '-' : fmtDuration(time ~/ (total == 0 ? 1 : total)))),
                    const VerticalDivider(width: 1),
                    Expanded(child: _mini('오늘 푼 문제', '${app.todayCount}')),
                  ]),
                ),
                const Divider(height: 1),
                const SizedBox(height: 20),
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
                  const SizedBox(height: 6),
                ],
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('홈으로'),
                ),
              ],
            ),
          ),
        );
        // 문항 목록: 카드 여러 장 대신 판 한 장 안에 구분선으로
        final list = ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 70),
                  _row(app, items[i], i),
                ],
              ]),
            ),
          ],
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

  /// 내 답 한 줄 — 서술형은 스스로 매긴 점수 그대로.
  static String _answerLine(Problem p, GradedAnswer g) {
    if (p.isEssay) return '점수 ${g.given}';
    final mine = p.isChoice ? circled(int.tryParse(g.given) ?? 0) : g.given;
    return g.correct ? '내 답 $mine' : '내 답 $mine · 정답 ${g.expectedDisplay}';
  }

  Widget _row(AppState app, SessionItem it, int i) {
    final p = it.problem;
    final g = it.graded;
    final color = Color(app.bank.subject(p.subjectId)?.color ?? 0xFF2B59C3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ResultMark(correct: g?.correct, size: 34),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${i + 1}번',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: AppColors.tabular)),
              const SizedBox(width: 8),
              Flexible(child: Pill(p.topic.isNotEmpty ? p.topic : p.unit, color: color, dense: true)),
              if (p.isVariant || p.isTwin) ...[
                const SizedBox(width: 6),
                const Pill('변형', color: AppColors.accent, dense: true),
              ],
              const Spacer(),
              Text(fmtDuration(it.timeMs),
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600, fontFeatures: AppColors.tabular)),
            ]),
            const SizedBox(height: 6),
            MathText(MathText.plain(p.stem).length > 120 ? '${MathText.plain(p.stem).substring(0, 120)}…' : p.stem,
                maxLines: 2, style: const TextStyle(fontSize: 14.5, color: AppColors.inkSoft, height: 1.5)),
            const SizedBox(height: 6),
            if (g != null)
              Text(_answerLine(p, g),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: g.correct ? AppColors.correct : AppColors.wrong,
                      fontFeatures: AppColors.tabular))
            else
              const Text('풀지 않음', style: TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
        ),
      ]),
    );
  }

  Widget _compact(SessionItem it, int i) {
    final g = it.graded;
    return Card(
      child: ListTile(
        minVerticalPadding: 12,
        leading: ResultMark(correct: g?.correct),
        title: Text('${i + 1}번 · ${it.problem.topic}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(g == null ? '풀지 않음' : _answerLine(it.problem, g),
            style: TextStyle(color: g == null ? AppColors.inkMuted : (g.correct ? AppColors.correct : AppColors.wrong))),
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, fontFeatures: AppColors.tabular)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
