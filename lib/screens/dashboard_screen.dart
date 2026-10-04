import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/workbook_card.dart';
import 'exam_setup.dart';
import 'solve_screen.dart';

/// 홈: 오늘의 오답 변형 세트 · 순공 · 무한 풀기 · 내 문제집 · 할 일 · 약점 유형.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '늦은 밤까지 수고 많아요';
    if (h < 12) return '좋은 아침이에요';
    if (h < 18) return '오늘도 한 문제씩';
    return '오늘 하루 마무리해요';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final courses = app.myCourses;
    final l = app.learner;
    final dday = app.dDay;

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          // ---------- header
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_greeting()}, ${app.profile.name}님',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                const SizedBox(height: 6),
                Text(
                  '${l.grade} · ${l.goal} 목표 · ${courses.isEmpty ? '과목 없음' : courses.length == 1 ? courses.first.name : '${courses.first.name} 외 ${courses.length - 1}과목'}',
                  style: const TextStyle(fontSize: 15.5, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            if (app.streak > 0) ...[
              Pill('${app.streak}일 연속', icon: Icons.local_fire_department_rounded, color: AppColors.accent),
              const SizedBox(width: 10),
            ],
            if (!app.subscribed)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onNavigate(9),
                child: Pill('무료 체험 ${app.trialDaysLeft}일 남음', icon: Icons.workspace_premium_rounded, color: AppColors.blue),
              ),
            if (l.examDate > 0) ...[
              const SizedBox(width: 10),
              _DdayBadge(name: l.examName, dday: dday, onTap: () => onNavigate(3)),
            ],
          ]),
          const SizedBox(height: 24),

          // ---------- hero: daily set + study time
          _flex(
            wide,
            [
              (6, const _DailySetCard()),
              (
                4,
                Column(children: [
                  _StudyCard(onOpen: () => onNavigate(3)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: StatTile(
                        label: '오늘 푼 문제',
                        value: '${app.todayCount}',
                        sub: app.todayCount == 0 ? '첫 문제를 풀어 볼까요' : '정답 ${app.todayCorrect}개',
                        icon: Icons.task_alt_rounded,
                        color: AppColors.blue,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: StatTile(
                        label: '오답노트',
                        value: '${app.wrongNote.length}',
                        sub: app.dueCount > 0 ? '지금 복습 ${app.dueCount}개' : '복습할 문제 없음',
                        icon: Icons.assignment_late_rounded,
                        color: AppColors.review,
                      ),
                    ),
                  ]),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ---------- endless
          const SectionHeader('무한 풀기', subtitle: '맞히면 더 어렵게, 틀리면 쉽게 · 문제가 끝없이 이어져요'),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _EndlessChip(
              key: const Key('endless-all'),
              label: '내 과목 전체',
              icon: Icons.all_inclusive_rounded,
              color: AppColors.ink,
              onTap: () => SolveScreen.endless(context, title: '내 과목 전체'),
            ),
            for (final c in courses)
              _EndlessChip(
                key: Key('endless-${c.id}'),
                label: c.name,
                icon: courseIcon(c),
                color: Color(c.color),
                onTap: () => SolveScreen.endless(context, courseId: c.id),
              ),
            _EndlessChip(
              label: '모의고사 만들기',
              icon: Icons.timer_outlined,
              color: AppColors.inkSoft,
              outlined: true,
              onTap: () => showExamSetup(context),
            ),
          ]),
          const SizedBox(height: 32),

          // ---------- workbooks
          SectionHeader('내 문제집',
              subtitle: '순서대로 풀며 진도를 채워요',
              trailing: TextButton(onPressed: () => onNavigate(1), child: const Text('전체 보기'))),
          SizedBox(
            height: 178,
            child: app.myWorkbooks.isEmpty
                ? const Card(child: Center(child: Text('내 과목의 문제집이 아직 없어요', style: TextStyle(color: AppColors.inkMuted))))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: app.myWorkbooks.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, i) => SizedBox(width: 290, child: WorkbookCard(workbook: app.myWorkbooks[i])),
                  ),
          ),
          const SizedBox(height: 32),

          // ---------- todo + weak topics
          _flex(wide, [
            (1, _TodoPreview(onOpen: () => onNavigate(3))),
            (1, const _WeakTopics()),
          ], cross: CrossAxisAlignment.start),
        ],
      );
    });
  }

  Widget _flex(bool wide, List<(int, Widget)> items, {CrossAxisAlignment cross = CrossAxisAlignment.stretch}) {
    if (!wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: 16), items[i].$2],
      ]);
    }
    final row = Row(crossAxisAlignment: cross, children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 18),
        Expanded(flex: items[i].$1, child: items[i].$2),
      ],
    ]);
    return cross == CrossAxisAlignment.stretch ? IntrinsicHeight(child: row) : row;
  }
}

IconData courseIcon(Subject s) {
  switch (s.id) {
    case 'phy1':
      return Icons.bolt_rounded;
    case 'phy2':
      return Icons.blur_circular_rounded;
    case 'earth1':
      return Icons.public_rounded;
  }
  switch (s.group) {
    case 'kor':
      return Icons.auto_stories_rounded;
    case 'math':
      return Icons.functions_rounded;
    case 'eng':
      return Icons.translate_rounded;
    case 'soc':
      return Icons.account_balance_rounded;
    case 'sci':
      return Icons.science_rounded;
  }
  return Icons.edit_note_rounded;
}

/// Kept for screens that only know the course id.
IconData subjectIcon(String id) => switch (id) {
      'phy1' => Icons.bolt_rounded,
      'phy2' => Icons.blur_circular_rounded,
      'earth1' => Icons.public_rounded,
      'math1' || 'math2' || 'prob' => Icons.functions_rounded,
      'integ' || 'mid-sci' => Icons.science_rounded,
      'kor-read' => Icons.auto_stories_rounded,
      'eng' => Icons.translate_rounded,
      'soc-int' => Icons.account_balance_rounded,
      _ => Icons.edit_note_rounded,
    };

class _DdayBadge extends StatelessWidget {
  const _DdayBadge({required this.name, required this.dday, required this.onTap});
  final String name;
  final int dday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(dday > 0 ? 'D-$dday' : (dday == 0 ? 'D-DAY' : 'D+${-dday}'),
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1)),
          ]),
        ),
      ),
    );
  }
}

class _DailySetCard extends StatelessWidget {
  const _DailySetCard();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final set = app.dailySet;
    final total = set.problemIds.length;
    final done = set.doneCount;
    final variants = set.count('twin') + set.count('variant') + set.count('similar');
    final review = set.count('review');
    final weak = set.count('weak');
    final fresh = set.count('new');
    final remaining = [
      for (final p in app.dailyProblems)
        if (!set.done.contains(p.id)) p
    ];
    final hasWrong = variants + review > 0;
    final white70 = Colors.white.withValues(alpha: 0.72);

    Widget chip(String label, int n, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text('$label $n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B2A4A), Color(0xFF2B3F6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(children: [
        ProgressRing(
          value: total == 0 ? 0 : done / total,
          size: 150,
          stroke: 14,
          color: set.complete ? AppColors.correct : AppColors.accent,
          track: Colors.white.withValues(alpha: 0.12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (set.complete)
              const Icon(Icons.check_rounded, color: Colors.white, size: 44)
            else
              Text('$done',
                  style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
            Text(set.complete ? '완료!' : '/ $total 문제', style: TextStyle(color: white70, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              const Text('오늘의 오답 변형 세트',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(width: 10),
              Text(fmtDate(DateTime.now().millisecondsSinceEpoch, withTime: false), style: TextStyle(color: white70, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Text(
              hasWrong
                  ? '틀린 문제를 쌍둥이 문항과 변형으로 다시 풀고, 약한 유형을 채웠어요.'
                  : '아직 오답이 없어서 내 과목의 새 문제로 채웠어요. 틀리면 내일 세트에 변형이 나와요.',
              style: TextStyle(color: white70, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (variants > 0) chip('오답 변형', variants, AppColors.accent),
              if (review > 0) chip('복습', review, AppColors.review),
              if (weak > 0) chip('약점 유형', weak, const Color(0xFFB58CFF)),
              if (fresh > 0) chip('새 문제', fresh, const Color(0xFF6FC3FF)),
            ]),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('daily-start'),
              style: FilledButton.styleFrom(
                backgroundColor: set.complete ? Colors.white.withValues(alpha: 0.14) : AppColors.accent,
                minimumSize: const Size(0, 52),
              ),
              onPressed: total == 0
                  ? null
                  : () => SolveScreen.open(context,
                      title: '오늘의 오답 변형 세트',
                      problems: set.complete || remaining.isEmpty ? app.dailyProblems : remaining,
                      mode: 'daily'),
              icon: Icon(set.complete ? Icons.replay_rounded : Icons.play_arrow_rounded),
              label: Text(set.complete
                  ? '한 번 더 풀기'
                  : done == 0
                      ? '시작하기'
                      : '이어 풀기 · ${remaining.length}문제 남음'),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// 순공 시간 with a start/stop button (ticks while running).
class _StudyCard extends StatefulWidget {
  const _StudyCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<_StudyCard> createState() => _StudyCardState();
}

class _StudyCardState extends State<_StudyCard> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AppScope.read(context).studying) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ms = app.todayStudyMs;
    final solve = app.solveMsOn(dayKey(DateTime.now()));
    final on = app.studying;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.timer_rounded, size: 18, color: on ? AppColors.accent : AppColors.inkSoft),
                  const SizedBox(width: 6),
                  Text(on ? '공부 중' : '오늘 순공',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? AppColors.accent : AppColors.inkSoft)),
                ]),
                const SizedBox(height: 8),
                Text(fmtStudy(ms),
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1)),
                Text('+ 문제 풀이 ${fmtDuration(solve)}', style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
              ]),
            ),
            FilledButton.icon(
              key: const Key('study-toggle'),
              onPressed: on ? app.stopStudy : app.startStudy,
              style: FilledButton.styleFrom(
                backgroundColor: on ? AppColors.wrong : AppColors.ink,
                minimumSize: const Size(0, 50),
              ),
              icon: Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(on ? '멈추기' : '시작'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 1:02:03 / 12:03
String fmtStudy(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

class _EndlessChip extends StatelessWidget {
  const _EndlessChip(
      {super.key, required this.label, required this.icon, required this.color, required this.onTap, this.outlined = false});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: outlined ? Colors.transparent : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: outlined ? AppColors.lineStrong : AppColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: outlined ? AppColors.paperDeep : color, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 19, color: outlined ? AppColors.inkSoft : Colors.white),
            ),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          ]),
        ),
      ),
    );
  }
}

class _TodoPreview extends StatelessWidget {
  const _TodoPreview({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final todos = app.todayTodos;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('오늘 할 일', trailing: TextButton(onPressed: onOpen, child: const Text('학습관리'))),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            _autoRow(Icons.auto_awesome_rounded, '오늘의 오답 변형 세트', app.dailySet.complete,
                '${app.dailySet.doneCount}/${app.dailySet.problemIds.length}'),
            if (app.dueCount > 0) _autoRow(Icons.assignment_late_rounded, '오답 복습 ${app.dueCount}문제', false, null),
            for (final t in todos.take(4))
              CheckboxListTile(
                dense: true,
                value: t.done,
                onChanged: (_) => app.toggleTodo(t.id),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(t.text,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: t.done ? TextDecoration.lineThrough : null,
                        color: t.done ? AppColors.inkMuted : AppColors.ink)),
              ),
            if (todos.isEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.add_rounded, color: AppColors.inkMuted),
                title: const Text('할 일을 추가해 보세요', style: TextStyle(color: AppColors.inkMuted)),
                onTap: onOpen,
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _autoRow(IconData icon, String text, bool done, String? trailing) => ListTile(
        dense: true,
        leading: Icon(done ? Icons.check_circle_rounded : icon, color: done ? AppColors.correct : AppColors.accent),
        title: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: trailing == null ? null : Text(trailing, style: const TextStyle(fontWeight: FontWeight.w800)),
      );
}

class _WeakTopics extends StatelessWidget {
  const _WeakTopics();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final weak = app.weakTopics;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('보완이 필요한 유형'),
      if (weak.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Text('문제를 더 풀면 약한 유형을 찾아 드려요.', style: TextStyle(color: AppColors.inkMuted)),
          ),
        )
      else
        Card(
          child: Column(children: [
            for (final (topic, acc, _) in weak.take(4))
              ListTile(
                title: Text(topic, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AccuracyBar(value: acc, color: accuracyColor(acc)),
                ),
                trailing: TextButton.icon(
                  onPressed: () => SolveScreen.endless(context, topic: topic, title: topic),
                  icon: const Icon(Icons.all_inclusive_rounded, size: 18),
                  label: Text('${pct(acc)} · 집중 풀기'),
                ),
              ),
          ]),
        ),
    ]);
  }
}
