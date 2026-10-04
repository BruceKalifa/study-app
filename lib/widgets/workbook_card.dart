import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../screens/workbook_screen.dart';
import 'common.dart';

Color workbookLevelColor(String level) => switch (level) {
      '기본' => AppColors.correct,
      '실전' => AppColors.blue,
      '심화' => const Color(0xFF8C5BD6),
      '모의고사' => AppColors.accent,
      _ => AppColors.inkSoft,
    };

/// A 문제집 tile: course colour band, title, level, progress.
class WorkbookCard extends StatelessWidget {
  const WorkbookCard({super.key, required this.workbook});
  final Workbook workbook;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final course = app.bank.subject(workbook.course);
    final color = Color(course?.color ?? 0xFF5B6475);
    final (done, total) = app.workbookProgress(workbook);
    final lv = workbookLevelColor(workbook.level);
    return Card(
      key: Key('wbcard-${workbook.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => WorkbookScreen.open(context, workbook.id),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 10, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Pill(workbook.level, color: lv, dense: true),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(course?.name ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(workbook.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.25)),
                if (workbook.desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(workbook.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                ],
                const Spacer(),
                AccuracyBar(value: total == 0 ? 0 : done / total, color: color, height: 6),
                const SizedBox(height: 6),
                Text(done == total && total > 0 ? '완주! $total문항' : '$done / $total 문항',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
