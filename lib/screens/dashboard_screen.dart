import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import 'exam_setup.dart';
import 'library_screen.dart';
import 'solve_screen.dart';

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
    final goal = app.settings.dailyGoal;
    final today = app.todayCount;
    final due = app.dueCount;
    final weak = app.weakTopics;

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          // ---------- header
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_greeting()}, ${app.profile.name}님',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                const SizedBox(height: 4),
                Text(
                  today >= goal
                      ? '오늘 목표 $goal문제를 달성했어요! 🎉'
                      : '오늘 목표까지 ${goal - today}문제 남았어요${due > 0 ? ' · 복습할 문제 $due개' : ''}',
                  style: const TextStyle(fontSize: 15.5, color: AppColors.inkSoft, fontWeight: FontWeight.w500),
                ),
              ]),
            ),
            if (app.streak > 0)
              Pill('${app.streak}일 연속', icon: Icons.local_fire_department_rounded, color: AppColors.accent),
          ]),
          const SizedBox(height: 24),

          // ---------- hero row
          _maybeIntrinsic(wide, Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _wrap(wide, flex: 5, child: _TodayCard(goal: goal, today: today, due: due)),
              SizedBox(width: wide ? 18 : 0, height: wide ? 0 : 18),
              _wrap(
                wide,
                flex: 4,
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: StatTile(
                        label: '푼 문제',
                        value: '${app.totalSolved}',
                        sub: '오늘 $today문제',
                        icon: Icons.task_alt_rounded,
                        color: AppColors.blue,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: StatTile(
                        label: '정답률',
                        value: app.totalSolved == 0 ? '-' : pct(app.accuracy),
                        sub: '평균 ${app.totalSolved == 0 ? '-' : fmtDuration(app.avgTimeMs)}/문제',
                        icon: Icons.track_changes_rounded,
                        color: AppColors.correct,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _ReviewCard(due: due, total: app.wrongNote.length, onOpen: () => onNavigate(2)),
                ]),
              ),
            ],
          )),
          const SizedBox(height: 30),

          // ---------- subjects
          SectionHeader('과목별 문제집',
              subtitle: '단원을 골라 풀거나, 변형문제로 실력을 다져요',
              trailing: TextButton(onPressed: () => onNavigate(1), child: const Text('전체 보기'))),
          GridView.count(
            crossAxisCount: box.maxWidth >= 1200 ? 5 : (box.maxWidth >= 900 ? 3 : 2),
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.25,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [for (final s in app.bank.subjects) _SubjectCard(subject: s)],
          ),
          const SizedBox(height: 30),

          // ---------- weak topics + recent
          Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _wrap(
                wide,
                flex: 1,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SectionHeader('보완이 필요한 유형', subtitle: '정답률이 낮은 소단원이에요'),
                  if (weak.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(22),
                        child: Text('문제를 더 풀면 약한 유형을 찾아드려요.', style: TextStyle(color: AppColors.inkMuted)),
                      ),
                    )
                  else
                    Card(
                      child: Column(children: [
                        for (final (topic, acc, n) in weak)
                          ListTile(
                            title: Text(topic, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: AccuracyBar(value: acc, color: accuracyColor(acc)),
                            ),
                            trailing: Text('${pct(acc)} · $n회',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                            onTap: () => _practiceTopic(context, app, topic),
                          ),
                      ]),
                    ),
                ]),
              ),
              SizedBox(width: wide ? 18 : 0, height: wide ? 0 : 18),
              _wrap(
                wide,
                flex: 1,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SectionHeader('최근 기록', subtitle: '방금 푼 문제부터', trailing: TextButton(onPressed: () => onNavigate(4), child: const Text('더 보기'))),
                  Card(
                    child: app.attempts.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(22),
                            child: Text('아직 기록이 없어요. 오늘의 학습으로 시작해 보세요!',
                                style: TextStyle(color: AppColors.inkMuted)),
                          )
                        : Column(children: [
                            for (final a in app.attempts.reversed.take(5))
                              ListTile(
                                leading: ResultMark(correct: a.correct),
                                title: Text(a.topic.isEmpty ? a.unit : a.topic,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                    '${app.bank.subject(a.subjectId)?.name ?? ''} · ${fmtDate(a.at)}${a.isVariant ? ' · 변형' : ''}'),
                                trailing: Text(fmtDuration(a.timeMs),
                                    style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                              ),
                          ]),
                  ),
                ]),
              ),
            ],
          ),
        ],
      );
    });
  }

  Widget _maybeIntrinsic(bool wide, Widget child) => wide ? IntrinsicHeight(child: child) : child;

  Widget _wrap(bool wide, {required int flex, required Widget child}) =>
      wide ? Expanded(flex: flex, child: child) : child;

  void _practiceTopic(BuildContext context, AppState app, String topic) {
    final ps = app.bank.all.where((p) => p.topic == topic).toList();
    final set = <Problem>[for (final p in ps) p.hasTemplate ? app.makeVariant(p) : p];
    SolveScreen.open(context, title: '$topic 집중 연습', problems: set, mode: 'variant');
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.goal, required this.today, required this.due});
  final int goal, today, due;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
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
          value: goal == 0 ? 0 : today / goal,
          size: 148,
          stroke: 14,
          color: AppColors.accent,
          track: Colors.white.withValues(alpha: 0.12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$today',
                style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
            Text('/ $goal 문제', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('오늘의 학습',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
            const SizedBox(height: 6),
            Text(
              due > 0 ? '복습할 오답 $due문제와 새 문제를 섞어서 준비했어요.' : '안 푼 문제를 과목별로 골고루 골라 드려요.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 18),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                onPressed: () => SolveScreen.open(context, title: '오늘의 학습', problems: app.todayMix(), mode: 'today'),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('시작하기'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
                onPressed: () => LibraryScreen.openQuickVariant(context),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('변형문제 10개'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
                onPressed: () => showExamSetup(context),
                icon: const Icon(Icons.timer_outlined),
                label: const Text('모의고사'),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.due, required this.total, required this.onOpen});
  final int due, total;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: AppColors.reviewSoft, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.assignment_late_rounded, color: AppColors.review),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(due > 0 ? '지금 복습할 오답 $due개' : '오답노트 $total개',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const Text('틀린 문제는 1·3·7일 간격으로 다시 나와요',
                    style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
          ]),
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final color = Color(subject.color);
    final t = app.subjectTally(subject.id);
    final cov = app.coverage(subject);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SubjectScreen(subjectId: subject.id),
        )),
        child: Stack(children: [
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), shape: BoxShape.circle),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Icon(subjectIcon(subject.id), color: Colors.white, size: 21),
              ),
              const Spacer(),
              Text(subject.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 2),
              Text('${subject.problems.length}문제 · ${subject.units.length}단원',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              AccuracyBar(value: cov, color: color, height: 6),
              const SizedBox(height: 6),
              Text('진도 ${pct(cov)}${t.solved > 0 ? ' · 정답률 ${pct(t.accuracy)}' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}

IconData subjectIcon(String id) {
  switch (id) {
    case 'phy1':
      return Icons.bolt_rounded;
    case 'phy2':
      return Icons.blur_circular_rounded;
    case 'earth1':
      return Icons.public_rounded;
    case 'math':
      return Icons.functions_rounded;
    case 'integ':
      return Icons.science_rounded;
    default:
      return Icons.edit_note_rounded;
  }
}
