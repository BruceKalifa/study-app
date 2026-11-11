import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../widgets/common.dart';

const _sectionTitle = TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.ink);
const _meta = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted);

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, this.embedded = false});

  /// 학습관리 안의 한 칸으로 넣을 때: 제목 없이 내용만.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      final gutter = box.maxWidth < 620 ? 16.0 : 32.0;
      final figures = <(String, String, String?)>[
        ('푼 문제', '${app.totalSolved}', null),
        ('정답률', app.totalSolved == 0 ? '-' : pct(app.accuracy), app.totalSolved == 0 ? null : '${app.totalCorrect}개 맞힘'),
        ('연속 학습', '${app.streak}일', null),
        ('평균 풀이 시간', app.totalSolved == 0 ? '-' : fmtDuration(app.avgTimeMs), null),
      ];
      // 과목별은 내 교재 과목과 실제로 푼 과목만 (안 하는 과목이 "아직 없음" 으로 줄줄이 나오지 않게)
      final mine = {for (final w in app.myWorkbooks) w.course};
      final subjects = [
        for (final s in app.bank.subjects)
          if (mine.contains(s.id) || app.subjectTally(s.id).solved > 0) s
      ];
      return ListView(
        padding: embedded ? EdgeInsets.fromLTRB(gutter, 0, gutter, 40) : EdgeInsets.fromLTRB(gutter, 28, gutter, 40),
        children: [
          if (!embedded) ...[
            const Text('학습 통계', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1.0)),
            const SizedBox(height: 6),
            const Text('문제를 풀 때마다 자동으로 쌓여요', style: TextStyle(color: AppColors.inkSoft, fontSize: 15)),
            const SizedBox(height: 20),
          ],
          // 숫자 넷을 한 줄 띠로 (카드 네 개 대신)
          _FigureStrip(figures: figures, wide: box.maxWidth >= 620),
          const SizedBox(height: 16),
          _twoCol(
            wide,
            _panel(
              title: '최근 14일',
              subtitle: '막대 높이는 푼 문제, 진한 부분은 맞힌 문제',
              child: SizedBox(height: 196, child: _DailyBars(app: app)),
            ),
            _panel(
              title: '학습 달력',
              subtitle: '최근 18주, 진할수록 많이 풀었어요',
              child: SizedBox(height: 196, child: _Heatmap(app: app)),
            ),
          ),
          const SizedBox(height: 16),
          _twoCol(
            wide,
            _panel(
              title: '과목별',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (subjects.isEmpty) const Text('교재를 담고 문제를 풀면 과목별로 보여 드려요', style: _meta),
                for (final (i, s) in subjects.indexed) ...[
                  if (i > 0) const SizedBox(height: 18),
                  _barRow(s.name, app.subjectTally(s.id), Color(s.color), app.coverage(s)),
                ],
              ]),
            ),
            _panel(
              title: '난이도별 정답률',
              child: Column(children: [
                for (var d = 1; d <= 5; d++) ...[
                  if (d > 1) const SizedBox(height: 14),
                  _diffRow(d, app.byDifficulty[d]),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _panel(
            title: '단원별 성취도',
            subtitle: '정답률이 낮은 단원부터',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _unitRows(app, box.maxWidth >= 760)),
          ),
        ],
      );
    });
  }

  Widget _panel({required String title, String? subtitle, required Widget child}) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _sectionTitle),
            if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle, style: _meta)],
            const SizedBox(height: 18),
            child,
          ]),
        ),
      );

  Widget _twoCol(bool wide, Widget a, Widget b) => wide
      ? IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ]),
        )
      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 16), b]);

  Widget _barRow(String name, Tally t, Color color, double coverage) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        Text(t.solved == 0 ? '아직 없음' : pct(t.accuracy),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, fontFeatures: AppColors.tabular)),
      ]),
      const SizedBox(height: 8),
      AccuracyBar(value: t.accuracy, color: color, height: 8),
      const SizedBox(height: 6),
      Text(t.solved == 0 ? '진도 ${pct(coverage)}' : '${t.correct} / ${t.solved}문제 맞힘, 진도 ${pct(coverage)}',
          style: _meta.copyWith(fontSize: 12.5, fontFeatures: AppColors.tabular)),
    ]);
  }

  Widget _diffRow(int d, Tally? t) {
    final acc = t?.accuracy ?? 0;
    final has = t != null && t.solved > 0;
    return Row(children: [
      SizedBox(width: 64, child: DifficultyDots(d, size: 7)),
      const SizedBox(width: 10),
      Expanded(child: AccuracyBar(value: acc, color: has ? accuracyColor(acc) : AppColors.line, height: 8)),
      const SizedBox(width: 12),
      SizedBox(
        width: 92,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: has ? pct(acc) : '-',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 14.5)),
            if (has) TextSpan(text: '  ${t.solved}문제', style: _meta.copyWith(fontSize: 12)),
          ]),
          textAlign: TextAlign.right,
          style: const TextStyle(fontFeatures: AppColors.tabular),
        ),
      ),
    ]);
  }

  List<Widget> _unitRows(AppState app, bool wide) {
    final rows = <(String, String, Tally, Color)>[];
    app.byUnit.forEach((k, v) {
      final parts = k.split('|');
      final sub = app.bank.subject(parts.first);
      rows.add((sub?.name ?? parts.first, parts.length > 1 ? parts[1] : '', v, Color(sub?.color ?? 0xFF5B6475)));
    });
    rows.sort((a, b) => a.$3.accuracy.compareTo(b.$3.accuracy));
    if (rows.isEmpty) {
      return [const Text('아직 기록이 없어요', style: _meta)];
    }
    return [
      for (final (i, row) in rows.indexed) ...[
        if (i > 0) const Divider(height: 1),
        _unitRow(row.$1, row.$2, row.$3, row.$4, wide),
      ],
    ];
  }

  Widget _unitRow(String sub, String unit, Tally t, Color color, bool wide) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(
            flex: wide ? 4 : 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(unit.isEmpty ? sub : unit,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                    width: 7, height: 7, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _meta.copyWith(fontSize: 12.5)),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(flex: 5, child: AccuracyBar(value: t.accuracy, color: accuracyColor(t.accuracy), height: 8)),
          const SizedBox(width: 14),
          SizedBox(
            width: wide ? 150 : 64,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(pct(t.accuracy),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, fontFeatures: AppColors.tabular)),
              if (wide)
                Text('${t.solved}문제, 평균 ${fmtDuration(t.solved == 0 ? 0 : t.timeMs ~/ t.solved)}',
                    style: _meta.copyWith(fontSize: 12, fontFeatures: AppColors.tabular)),
            ]),
          ),
        ]),
      );
}

/// 숫자 넷을 한 장 위에 칸만 나눠서.
class _FigureStrip extends StatelessWidget {
  const _FigureStrip({required this.figures, required this.wide});
  final List<(String, String, String?)> figures;
  final bool wide;

  Widget _cell((String, String, String?) f) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(f.$1, style: _meta),
          const SizedBox(height: 6),
          Text(f.$2,
              maxLines: 1,
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  height: 1.1,
                  color: AppColors.ink,
                  fontFeatures: AppColors.tabular)),
          if (f.$3 != null) ...[
            const SizedBox(height: 4),
            Text(f.$3!, style: _meta.copyWith(fontSize: 12.5)),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      child: wide
          ? IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < figures.length; i++) ...[
                  if (i > 0) const VerticalDivider(width: 1),
                  Expanded(child: _cell(figures[i])),
                ],
              ]),
            )
          : Wrap(children: [
              for (final f in figures) FractionallySizedBox(widthFactor: 0.5, child: _cell(f)),
            ]),
    );
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
      final barW = math.min(22.0, (box.maxWidth / days.length) * 0.5);
      const barH = 130.0;
      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Tooltip(
              message: '${days[i].month}/${days[i].day} · ${data[i].solved}문제 (맞힘 ${data[i].correct})',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (data[i].solved > 0)
                  Text('${data[i].solved}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft,
                          fontFeatures: AppColors.tabular)),
                const SizedBox(height: 4),
                Container(
                  width: barW,
                  height: math.max(3.0, barH * data[i].solved / maxV),
                  decoration: BoxDecoration(
                    color: data[i].solved == 0 ? AppColors.paperDeep : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: barW,
                    height: data[i].solved == 0 ? 0 : barH * data[i].correct / maxV,
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(5)),
                  ),
                ),
                const SizedBox(height: 7),
                _DayLabel('${days[i].day}', today: i == days.length - 1),
              ]),
            ),
          ),
      ]);
    });
  }
}

/// 날짜 숫자 — 오늘은 형광펜 띠를 깐다.
class _DayLabel extends StatelessWidget {
  const _DayLabel(this.text, {required this.today});
  final String text;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final label = Text(text,
        style: TextStyle(
            fontSize: 11,
            fontFeatures: AppColors.tabular,
            color: today ? AppColors.ink : AppColors.inkMuted,
            fontWeight: today ? FontWeight.w800 : FontWeight.w500));
    if (!today) return label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: AppColors.highlight, borderRadius: BorderRadius.circular(3)),
      child: label,
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.app});
  final AppState app;

  /// 설계도 파랑의 다섯 단계 (0문제 = 종이색)
  static const _levels = [
    AppColors.paperDeep,
    Color(0xFFC9D7F3),
    Color(0xFF94B0E8),
    Color(0xFF5B83D6),
    AppColors.accent,
  ];

  @override
  Widget build(BuildContext context) {
    const weeks = 18;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // align columns to weeks starting Monday
    final start = today.subtract(Duration(days: (weeks - 1) * 7 + (today.weekday - 1)));
    return LayoutBuilder(builder: (context, box) {
      final cell = math.max(4.0, math.min((box.maxWidth - 30) / weeks - 4, (box.maxHeight - 34) / 7 - 4));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            for (final d in const ['월', '', '수', '', '금', '', '일'])
              SizedBox(
                height: cell + 4,
                width: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(d, style: const TextStyle(fontSize: 10.5, color: AppColors.inkMuted)),
                ),
              ),
          ]),
          for (var w = 0; w < weeks; w++)
            Column(children: [
              for (var d = 0; d < 7; d++) _cell(start.add(Duration(days: w * 7 + d)), today, cell),
            ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const SizedBox(width: 24),
          const Text('적게', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
          const SizedBox(width: 6),
          for (final c in _levels)
            Container(
              width: 11,
              height: 11,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
            ),
          const SizedBox(width: 3),
          const Text('많이', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
        ]),
      ]);
    });
  }

  Widget _cell(DateTime day, DateTime today, double cell) {
    if (day.isAfter(today)) return SizedBox(width: cell + 4, height: cell + 4);
    final n = app.daily[dayKey(day)]?.solved ?? 0;
    final level = n == 0 ? 0 : (n < 3 ? 1 : (n < 6 ? 2 : (n < 10 ? 3 : 4)));
    return Tooltip(
      message: '${day.month}/${day.day} · $n문제',
      child: Container(
        width: cell,
        height: cell,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: _levels[level],
          borderRadius: BorderRadius.circular(3),
          border: day == today ? Border.all(color: AppColors.ink, width: 1.5) : null,
        ),
      ),
    );
  }
}
