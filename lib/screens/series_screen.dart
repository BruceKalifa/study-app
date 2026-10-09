import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/workbook_card.dart' show stageColor, workbookLevelColor;
import 'solve_screen.dart';
import 'workbook_screen.dart';

/// 같은 시리즈끼리 묶는다 (시리즈가 없는 문제집은 혼자). 처음 나온 순서를 지킨다.
/// 교재 고르기·내 교재가 같은 기준으로 "한 권" 을 센다.
List<List<Workbook>> groupBySeries(Iterable<Workbook> books) {
  final order = <String>[];
  final by = <String, List<Workbook>>{};
  for (final w in books) {
    final k = w.series.trim().isEmpty ? 'id:${w.id}' : 'series:${w.series.trim()}';
    if (!by.containsKey(k)) {
      order.add(k);
      by[k] = [];
    }
    by[k]!.add(w);
  }
  return [for (final k in order) by[k]!];
}

/// 시리즈 안의 회차 고르기 — 내 교재에서 "FLOW TYPE" 을 누르면 1회차·2회차… 가 나온다.
class SeriesScreen extends StatelessWidget {
  const SeriesScreen({super.key, required this.series, this.onlyMine = true});
  final String series;

  /// 내 교재에 담은 회차만 (false 면 그 시리즈 전부).
  final bool onlyMine;

  static Future<void> open(BuildContext context, String series, {bool onlyMine = true}) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => SeriesScreen(series: series, onlyMine: onlyMine)));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final books = [
      for (final w in app.bank.workbooks)
        if (w.series == series && (!onlyMine || app.hasWorkbook(w.id))) w,
    ];
    final course = books.isEmpty ? null : app.bank.subject(books.first.course);
    final color = Color(course?.color ?? 0xFF5B6475);
    final done = books.fold<int>(0, (n, w) => n + app.workbookProgress(w).$1);
    final total = books.fold<int>(0, (n, w) => n + app.workbookProgress(w).$2);

    return Scaffold(
      appBar: AppBar(title: Text(series)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (books.isNotEmpty)
                  Wrap(spacing: 8, children: [
                    Pill(books.first.stage, color: stageColor(books.first.stage)),
                    Pill(books.first.level, color: workbookLevelColor(books.first.level)),
                    if (books.first.scope.isNotEmpty) Pill(books.first.scope, color: AppColors.inkSoft),
                    if (books.first.publisher.isNotEmpty) Pill(books.first.publisher, color: AppColors.inkSoft),
                  ]),
                const SizedBox(height: 10),
                Text(series, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.1)),
                const SizedBox(height: 4),
                Text('${books.length}회차 · $done/$total 문항 풀이',
                    style: const TextStyle(fontSize: 15, color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
              ]),
            ),
            ProgressRing(
              value: total == 0 ? 0 : done / total,
              size: 86,
              stroke: 9,
              color: color,
              child: Text('$done/$total', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ]),
          const SizedBox(height: 22),
          if (books.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(icon: Icons.menu_book_rounded, title: '이 시리즈에 담은 회차가 없어요'),
            ),
          for (final w in books) ...[
            _RoundRow(workbook: w, series: series, color: color),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// 회차 한 줄 — "1회차 · 27문항", 진도, 이어 풀기.
class _RoundRow extends StatelessWidget {
  const _RoundRow({required this.workbook, required this.series, required this.color});
  final Workbook workbook;
  final String series;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final w = workbook;
    final (done, total) = app.workbookProgress(w);
    final name = roundName(w, series);
    final ps = app.bank.problemsOf(w);
    final firstOpen = ps.indexWhere((p) => !app.isSolved(p.id));
    return Card(
      key: Key('round-${w.id}'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => WorkbookScreen.open(context, w.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            Container(width: 6, height: 38, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 14),
            SizedBox(
              width: 150,
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.4)),
            ),
            Expanded(
              child: Text(w.desc.isEmpty ? '$total문항' : w.desc,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
            ),
            const SizedBox(width: 14),
            SizedBox(width: 120, child: AccuracyBar(value: total == 0 ? 0 : done / total, color: color, height: 6)),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              child: Text(done == total && total > 0 ? '완주!' : '$done / $total',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              key: Key('round-solve-${w.id}'),
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: ps.isEmpty
                  ? null
                  : () => SolveScreen.open(context,
                      title: w.title,
                      problems: firstOpen <= 0 ? ps : [...ps.sublist(firstOpen), ...ps.sublist(0, firstOpen)]),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(done == 0 ? '풀기' : (done == total ? '다시' : '이어')),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 시리즈 이름을 뗀 회차 이름 ("FLOW TYPE 1회차" → "1회차").
String roundName(Workbook w, String series) {
  final t = w.title.trim();
  if (series.isNotEmpty && t.startsWith(series)) {
    final rest = t.substring(series.length).trim();
    if (rest.isNotEmpty) return rest;
  }
  return t;
}
