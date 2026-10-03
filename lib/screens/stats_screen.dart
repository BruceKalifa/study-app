import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../widgets/common.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      final tiles = [
        StatTile(label: '푼 문제', value: '${app.totalSolved}', icon: Icons.task_alt_rounded, color: AppColors.blue),
        StatTile(
            label: '정답률',
            value: app.totalSolved == 0 ? '-' : pct(app.accuracy),
            sub: '${app.totalCorrect}개 정답',
            icon: Icons.track_changes_rounded,
            color: AppColors.correct),
        StatTile(
            label: '연속 학습', value: '${app.streak}일', icon: Icons.local_fire_department_rounded, color: AppColors.accent),
        StatTile(
            label: '평균 풀이 시간',
            value: app.totalSolved == 0 ? '-' : fmtDuration(app.avgTimeMs),
            icon: Icons.timer_outlined,
            color: AppColors.review),
      ];
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          const Text('학습 통계', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
          const SizedBox(height: 4),
          const Text('문제를 풀 때마다 자동으로 쌓이고 업데이트돼요.', style: TextStyle(color: AppColors.inkSoft, fontSize: 15)),
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: tiles[i]),
              ],
            ]),
          ),
          const SizedBox(height: 24),
          _twoCol(
            wide,
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionHeader('최근 14일', subtitle: '막대 = 푼 문제, 진한 부분 = 정답'),
                  SizedBox(height: 200, child: _DailyBars(app: app)),
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionHeader('학습 달력', subtitle: '최근 18주'),
                  SizedBox(height: 200, child: _Heatmap(app: app)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _twoCol(
            wide,
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionHeader('과목별'),
                  for (final s in app.bank.subjects) ...[
                    _barRow(s.name, app.subjectTally(s.id), Color(s.color), app.coverage(s)),
                    const SizedBox(height: 14),
                  ],
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionHeader('난이도별 정답률'),
                  for (var d = 1; d <= 5; d++) ...[
                    _diffRow(d, app.byDifficulty[d]),
                    const SizedBox(height: 12),
                  ],
                ]),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionHeader('단원별 성취도', subtitle: '정답률이 낮은 단원부터'),
                ..._unitRows(app),
              ]),
            ),
          ),
        ],
      );
    });
  }

  Widget _twoCol(bool wide, Widget a, Widget b) => wide
      ? IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: a),
            const SizedBox(width: 18),
            Expanded(child: b),
          ]),
        )
      : Column(children: [a, const SizedBox(height: 18), b]);

  Widget _barRow(String name, Tally t, Color color, double coverage) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        const Spacer(),
        Text(t.solved == 0 ? '아직 없음' : '${t.correct}/${t.solved} · ${pct(t.accuracy)}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft, fontSize: 13)),
      ]),
      const SizedBox(height: 6),
      AccuracyBar(value: t.accuracy, color: color, height: 10),
      const SizedBox(height: 4),
      Text('진도 ${pct(coverage)}', style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
    ]);
  }

  Widget _diffRow(int d, Tally? t) {
    final acc = t?.accuracy ?? 0;
    return Row(children: [
      SizedBox(width: 70, child: DifficultyDots(d, size: 7)),
      const SizedBox(width: 10),
      Expanded(child: AccuracyBar(value: acc, color: accuracyColor(acc), height: 10)),
      const SizedBox(width: 10),
      SizedBox(
        width: 90,
        child: Text(t == null || t.solved == 0 ? '-' : '${pct(acc)} (${t.solved})',
            textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      ),
    ]);
  }

  List<Widget> _unitRows(AppState app) {
    final rows = <(String, String, Tally, Color)>[];
    app.byUnit.forEach((k, v) {
      final parts = k.split('|');
      final sub = app.bank.subject(parts.first);
      rows.add((sub?.name ?? parts.first, parts.length > 1 ? parts[1] : '', v, Color(sub?.color ?? 0xFF5B6475)));
    });
    rows.sort((a, b) => a.$3.accuracy.compareTo(b.$3.accuracy));
    if (rows.isEmpty) {
      return [const Text('아직 기록이 없어요.', style: TextStyle(color: AppColors.inkMuted))];
    }
    return [
      for (final (sub, unit, t, color) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(width: 110, child: Pill(sub, color: color, dense: true)),
            SizedBox(width: 220, child: Text(unit, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(child: AccuracyBar(value: t.accuracy, color: accuracyColor(t.accuracy), height: 10)),
            const SizedBox(width: 12),
            SizedBox(
              width: 130,
              child: Text('${pct(t.accuracy)} · ${t.solved}문제 · ${fmtDuration(t.solved == 0 ? 0 : t.timeMs ~/ t.solved)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
    ];
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = [for (var i = 13; i >= 0; i--) now.subtract(Duration(days: i))];
    final data = [for (final d in days) app.daily[dayKey(d)] ?? Tally()];
    final maxV = math.max(4, data.fold<int>(0, (m, t) => math.max(m, t.solved)));
    return LayoutBuilder(builder: (context, box) {
      final barW = (box.maxWidth / days.length) * 0.56;
      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Tooltip(
              message: '${days[i].month}/${days[i].day} · ${data[i].solved}문제 (정답 ${data[i].correct})',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (data[i].solved > 0)
                  Text('${data[i].solved}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                const SizedBox(height: 4),
                Container(
                  width: barW,
                  height: math.max(3.0, 140 * data[i].solved / maxV),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: barW,
                    height: data[i].solved == 0 ? 0 : 140 * data[i].correct / maxV,
                    decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${days[i].day}',
                    style: TextStyle(
                        fontSize: 11,
                        color: i == days.length - 1 ? AppColors.ink : AppColors.inkMuted,
                        fontWeight: i == days.length - 1 ? FontWeight.w800 : FontWeight.w500)),
              ]),
            ),
          ),
      ]);
    });
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    const weeks = 18;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // align columns to weeks starting Monday
    final start = today.subtract(Duration(days: (weeks - 1) * 7 + (today.weekday - 1)));
    return LayoutBuilder(builder: (context, box) {
      final cell = math.min((box.maxWidth - 30) / weeks - 4, (box.maxHeight - 20) / 7 - 4);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          for (final d in const ['월', '', '수', '', '금', '', '일'])
            SizedBox(
              height: cell + 4,
              width: 24,
              child: Text(d, style: const TextStyle(fontSize: 10, color: AppColors.inkMuted)),
            ),
        ]),
        for (var w = 0; w < weeks; w++)
          Column(children: [
            for (var d = 0; d < 7; d++)
              Builder(builder: (context) {
                final day = start.add(Duration(days: w * 7 + d));
                if (day.isAfter(today)) return SizedBox(width: cell + 4, height: cell + 4);
                final t = app.daily[dayKey(day)];
                final n = t?.solved ?? 0;
                final level = n == 0 ? 0 : (n < 3 ? 1 : (n < 6 ? 2 : (n < 10 ? 3 : 4)));
                const colors = [
                  Color(0xFFEDE9E1),
                  Color(0xFFFFD3C7),
                  Color(0xFFFFA38C),
                  Color(0xFFFF7A5C),
                  Color(0xFFE5532F),
                ];
                return Tooltip(
                  message: '${day.month}/${day.day} · $n문제',
                  child: Container(
                    width: cell,
                    height: cell,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: colors[level], borderRadius: BorderRadius.circular(4)),
                  ),
                );
              }),
          ]),
      ]);
    });
  }
}
