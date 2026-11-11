import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../screens/workbook_screen.dart';

Color workbookLevelColor(String level) => switch (level) {
      '기본' => AppColors.correct,
      '실전' => AppColors.blue,
      '심화' => const Color(0xFF8C5BD6),
      '모의고사' => AppColors.accent,
      _ => AppColors.inkSoft,
    };

/// 커리큘럼 단계 색 (개념 → 유형 → 기출 → N제 → 모의고사).
Color stageColor(String stage) => switch (stage) {
      '개념' => AppColors.correct,
      '유형' => const Color(0xFF0EA5E9),
      '기출' => AppColors.blue,
      'N제' => const Color(0xFF8C5BD6),
      '모의고사' => AppColors.accent,
      _ => AppColors.inkSoft,
    };

/// 책 표지처럼 생긴 한 칸: 왼쪽에 과목 색 책등, 단계·과목 한 줄, 제목, 아래에 얇은 진도 막대.
/// [WorkbookCard] 와 시리즈 묶음 칸이 같이 쓴다.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.color,
    required this.stage,
    required this.meta,
    required this.title,
    required this.done,
    required this.total,
    required this.onTap,
    this.subtitle = '',
    this.trailing,
  });

  final Color color;
  final String stage;

  /// 단계 옆에 붙는 짧은 말 (과목 이름, "11회차" …).
  final String meta;
  final String title;
  final String subtitle;
  final int done, total;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final finished = total > 0 && done >= total;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 책등: 과목 색 + 제본선
          Container(
            width: 16,
            decoration: BoxDecoration(color: color),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(width: 2, color: Colors.white.withValues(alpha: 0.28)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (stage.isNotEmpty) ...[
                    Text(stage,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: stageColor(stage))),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkMuted)),
                  ),
                  if (trailing != null) ...[const Spacer(), trailing!],
                ]),
                const SizedBox(height: 8),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.25)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                ],
                const Spacer(),
                Row(children: [
                  Expanded(child: _ThinProgress(value: total == 0 ? 0 : done / total, color: color)),
                  const SizedBox(width: 12),
                  if (finished) ...[
                    const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.correct),
                    const SizedBox(width: 4),
                    Text('$total문항 완주',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.correct, fontFeatures: AppColors.tabular)),
                  ] else
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '$done', style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
                        TextSpan(text: ' / $total 문항'),
                      ]),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted, fontFeatures: AppColors.tabular),
                    ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 얇은 진도 막대 (4dp) — 빈 곳은 종이색.
class _ThinProgress extends StatelessWidget {
  const _ThinProgress({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 4,
        color: AppColors.paperDeep,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}

/// A 문제집 tile: course colour spine, stage, title, progress.
class WorkbookCard extends StatelessWidget {
  const WorkbookCard({super.key, required this.workbook});
  final Workbook workbook;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final course = app.bank.subject(workbook.course);
    final color = Color(course?.color ?? 0xFF5B6475);
    final courseLabel = workbook.series.isEmpty
        ? (course?.name ?? '')
        : '${workbook.series} · ${[for (final id in app.bank.coursesOf(workbook)) app.bank.subject(id)?.name ?? id].join('·')}';
    final (done, total) = app.workbookProgress(workbook);
    return KeyedSubtree(
      key: Key('wbcard-${workbook.id}'),
      child: BookCover(
        color: color,
        stage: workbook.stage,
        meta: courseLabel,
        title: workbook.title,
        subtitle: workbook.desc,
        done: done,
        total: total,
        onTap: () => WorkbookScreen.open(context, workbook.id),
      ),
    );
  }
}
