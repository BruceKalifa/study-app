import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/records.dart';
import '../app/theme.dart';
import '../ink/ink_model.dart';
import '../widgets/common.dart';
import '../widgets/ink_preview.dart';
import '../widgets/math_text.dart';
import 'solve_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        Row(children: [
          const Expanded(
            child: Text('풀이 기록', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
          ),
          for (final (i, l) in [(0, '전체'), (1, '정답'), (2, '오답')]) ...[
            ChoiceChip(label: Text(l), selected: _filter == i, onSelected: (_) => setState(() => _filter = i)),
            const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 6),
        const Text('기록을 누르면 그때 쓴 필기를 다시 재생해 볼 수 있어요.',
            style: TextStyle(color: AppColors.inkSoft, fontSize: 15)),
        const SizedBox(height: 20),
        if (shown.isEmpty)
          const EmptyState(icon: Icons.history_rounded, title: '아직 기록이 없어요', message: '문제를 풀면 여기에 차곡차곡 쌓여요.'),
        for (final e in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 10),
            child: Text(_dayLabel(e.key),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.inkSoft)),
          ),
          Card(
            child: Column(children: [
              for (var i = 0; i < e.value.length; i++) ...[
                if (i > 0) const Divider(indent: 70),
                _AttemptTile(attempt: e.value[i]),
              ],
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (all.length > shown.length)
          Center(
            child: TextButton(onPressed: () => setState(() => _limit += 80), child: const Text('더 보기')),
          ),
      ],
    );
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: ResultMark(correct: a.correct, size: 34),
      title: Row(children: [
        Flexible(
          child: Text(a.topic.isEmpty ? a.unit : a.topic,
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        if (sub != null) Pill(sub.name, color: Color(sub.color), dense: true),
        if (a.isVariant) ...[const SizedBox(width: 6), const Pill('변형', color: AppColors.accent, dense: true)],
      ]),
      subtitle: Text(
        '내 답 $given${a.correct ? '' : '  ·  정답 ${a.expected}'}  ·  ${fmtDuration(a.timeMs)}  ·  ${fmtDate(a.at)}',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (a.hasInk) const Icon(Icons.draw_outlined, size: 18, color: AppColors.inkMuted),
        const SizedBox(width: 6),
        const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
      ]),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttemptDetailScreen(attempt: a))),
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
                    MathText(p.stem, style: const TextStyle(fontSize: 16, color: AppColors.ink, height: 1.7)),
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
                    MathText(p.solution, style: const TextStyle(fontSize: 15, color: AppColors.ink, height: 1.7)),
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
