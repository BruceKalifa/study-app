import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/records.dart';
import '../app/theme.dart';
import '../ink/ink_model.dart';
import '../widgets/common.dart';
import '../widgets/ink_preview.dart';
import '../widgets/math_text.dart';
import 'solve_screen.dart';
import '../widgets/problem_stem.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.embedded = false});

  /// 학습관리 안의 한 칸으로 넣을 때: 큰 제목 없이.
  final bool embedded;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _filter = 0; // 0 all, 1 correct, 2 wrong
  int _limit = 80;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final all = app.attempts.reversed.where((a) {
      if (_filter == 1) return a.correct;
      if (_filter == 2) return !a.correct;
      return true;
    }).toList();
    final shown = all.take(_limit).toList();
    final groups = <String, List<Attempt>>{};
    for (final a in shown) {
      groups.putIfAbsent(dayKey(DateTime.fromMillisecondsSinceEpoch(a.at)), () => []).add(a);
    }

    return LayoutBuilder(builder: (context, box) {
      final gutter = box.maxWidth < 620 ? 16.0 : 32.0;
      final filters = Wrap(spacing: 8, children: [
        for (final (i, l) in [(0, '전체'), (1, '정답'), (2, '오답')])
          ChoiceChip(label: Text(l), selected: _filter == i, onSelected: (_) => setState(() => _filter = i)),
      ]);
      return ListView(
        padding: widget.embedded
            ? EdgeInsets.fromLTRB(gutter, 0, gutter, 40)
            : EdgeInsets.fromLTRB(gutter, 28, gutter, 40),
        children: [
          if (!widget.embedded) ...[
            const Text('풀이 기록', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1.0)),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Text('기록을 누르면 그때 쓴 필기를 다시 재생해 볼 수 있어요',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 14.5, fontWeight: FontWeight.w500)),
              filters,
            ],
          ),
          const SizedBox(height: 18),
          if (shown.isEmpty)
            const EmptyState(icon: Icons.history_rounded, title: '아직 기록이 없어요', message: '문제를 풀면 여기에 날짜별로 쌓여요.'),
          for (final e in groups.entries) ...[
            _DayHeader(label: _dayLabel(e.key), attempts: e.value),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < e.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 64),
                  _AttemptTile(attempt: e.value[i]),
                ],
              ]),
            ),
            const SizedBox(height: 20),
          ],
          if (all.length > shown.length)
            Center(
              child: TextButton(onPressed: () => setState(() => _limit += 80), child: const Text('더 보기')),
            ),
        ],
      );
    });
  }

  String _dayLabel(String key) {
    final today = dayKey(DateTime.now());
    final yest = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    if (key == today) return '오늘';
    if (key == yest) return '어제';
    final p = key.split('-');
    return '${int.parse(p[1])}월 ${int.parse(p[2])}일';
  }
}

class _AttemptTile extends StatelessWidget {
  const _AttemptTile({required this.attempt});
  final Attempt attempt;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = attempt;
    final sub = app.bank.subject(a.subjectId);
    final p = app.problem(a.problemId);
    final given = (p?.isChoice ?? false) ? circled(int.tryParse(a.answer) ?? 0) : a.answer;
    final d = DateTime.fromMillisecondsSinceEpoch(a.at);
    final clock = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    const meta = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttemptDetailScreen(attempt: a))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Row(children: [
          ResultMark(correct: a.correct, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(a.topic.isEmpty ? a.unit : a.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                ),
                if (sub != null) ...[const SizedBox(width: 8), Pill(sub.name, color: Color(sub.color), dense: true)],
                if (a.isVariant) ...[const SizedBox(width: 6), const Pill('변형', color: AppColors.accent, dense: true)],
              ]),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: '내 답 ', style: meta),
                  TextSpan(
                      text: given,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: a.correct ? AppColors.correct : AppColors.wrong)),
                  if (!a.correct) ...[
                    const TextSpan(text: '     정답 ', style: meta),
                    TextSpan(
                        text: a.expected,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  ],
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtDuration(a.timeMs),
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft, fontFeatures: AppColors.tabular)),
            const SizedBox(height: 2),
            Text(clock, style: meta.copyWith(fontSize: 12, fontFeatures: AppColors.tabular)),
          ]),
          const SizedBox(width: 6),
          if (a.hasInk)
            const Tooltip(
              message: '필기 있음',
              child: Icon(Icons.draw_outlined, size: 18, color: AppColors.inkMuted),
            )
          else
            const SizedBox(width: 18),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
        ]),
      ),
    );
  }
}

/// 날짜 머리: 날짜와 그날 맞힌 수.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.attempts});
  final String label;
  final List<Attempt> attempts;

  @override
  Widget build(BuildContext context) {
    final ok = attempts.where((a) => a.correct).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink)),
        const Spacer(),
        Text('${attempts.length}문제 중 $ok개 맞힘',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted, fontFeatures: AppColors.tabular)),
      ]),
    );
  }
}

class AttemptDetailScreen extends StatelessWidget {
  const AttemptDetailScreen({super.key, required this.attempt});
  final Attempt attempt;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = attempt;
    final p = app.problem(a.problemId);
    return Scaffold(
      appBar: AppBar(
        title: Text(a.topic.isEmpty ? '풀이 기록' : a.topic),
        actions: [
          if (p != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: () => SolveScreen.open(context, title: '다시 풀기', mode: 'review', problems: [p]),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('다시 풀기'),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 420,
            child: Card(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    ResultMark(correct: a.correct, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.correct ? '정답' : '오답',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: a.correct ? AppColors.correct : AppColors.wrong)),
                        Text('${fmtDate(a.at)} · ${fmtDuration(a.timeMs)}',
                            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  if (p != null) ...[
                    ProblemStem(p, style: const TextStyle(fontSize: 16, color: AppColors.ink, height: 1.7)),
                    if (p.boxItems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final b in p.boxItems)
                        MathText(b, style: const TextStyle(fontSize: 15, color: AppColors.inkSoft)),
                    ],
                    if (p.isChoice) ...[
                      const SizedBox(height: 10),
                      for (var i = 0; i < p.choices.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: MathText('${circled(i + 1)} ${p.choices[i]}',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: '${i + 1}' == p.answer ? FontWeight.w800 : FontWeight.w500,
                                  color: '${i + 1}' == p.answer ? AppColors.correct : AppColors.inkSoft)),
                        ),
                    ],
                    const SizedBox(height: 16),
                  ],
                  Text('내 답: ${(p?.isChoice ?? false) ? circled(int.tryParse(a.answer) ?? 0) : a.answer}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('정답: ${a.expected}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.correct)),
                  if (p != null) ...[
                    const Divider(height: 32),
                    const Text('해설', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    ProblemSolution(p, style: const TextStyle(fontSize: 15, color: AppColors.ink, height: 1.7)),
                  ],
                ]),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: FutureBuilder<InkDocument?>(
              future: app.loadAttemptInk(a.id),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final doc = snap.data;
                if (doc == null || doc.isEmpty) {
                  return const EmptyState(icon: Icons.draw_outlined, title: '저장된 필기가 없어요');
                }
                return InkReplay(doc: doc);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
