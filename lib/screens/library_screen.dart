import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../core/problem_bank.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import 'dashboard_screen.dart' show subjectIcon, courseIcon;
import '../widgets/workbook_card.dart';
import 'exam_setup.dart';
import 'solve_screen.dart';

enum _Filter { all, unsolved, wrong, bookmarked }

/// Problem browser for one course (units, filters, search).
class CourseBrowser extends StatefulWidget {
  const CourseBrowser({super.key, this.initialSubject, this.standalone = false});
  final String? initialSubject;
  final bool standalone;

  /// 10 variants across subjects, weighted toward weak/wrong problems.
  static void openQuickVariant(BuildContext context, {String? subjectId}) {
    final app = AppScope.read(context);
    final rnd = math.Random();
    final pool = app.bank.all.where((p) => app.hasVariant(p) && (subjectId == null || p.subjectId == subjectId)).toList();
    if (pool.isEmpty) return;
    pool.sort((a, b) {
      double score(Problem p) {
        final s = app.stateOf(p.id);
        final acc = s.attempts == 0 ? 0.6 : s.correct / s.attempts;
        return acc + (s.inWrongNote ? -0.5 : 0) + rnd.nextDouble() * 0.5;
      }

      return score(a).compareTo(score(b));
    });
    final picked = pool.take(10).map(app.makeVariant).toList()..shuffle(rnd);
    SolveScreen.open(context, title: '변형문제 10', problems: picked, mode: 'variant');
  }

  @override
  State<CourseBrowser> createState() => _CourseBrowserState();
}

class _CourseBrowserState extends State<CourseBrowser> {
  String? _subject;
  _Filter _filter = _Filter.all;
  int? _difficulty;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _subject = widget.initialSubject;
  }

  bool _match(AppState app, Problem p) {
    final st = app.stateOf(p.id);
    switch (_filter) {
      case _Filter.all:
        break;
      case _Filter.unsolved:
        if (st.attempts > 0) return false;
        break;
      case _Filter.wrong:
        if (!st.inWrongNote) return false;
        break;
      case _Filter.bookmarked:
        if (!st.bookmarked) return false;
        break;
    }
    if (_difficulty != null && p.difficulty != _difficulty) return false;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      final hay = '${p.topic} ${p.unit} ${MathText.plain(p.stem)} ${p.tags.join(' ')}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final subjects = app.bank.subjects;
    final sel = _subject == null ? null : app.bank.subject(_subject!);
    final shown = sel == null ? subjects : [sel];

    final content = CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 8),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(sel?.name ?? '문제집',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: '유형·단원·내용 검색'),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                if (!widget.standalone) ...[
                  ChoiceChip(
                    label: const Text('전체 과목'),
                    selected: _subject == null,
                    onSelected: (_) => setState(() => _subject = null),
                  ),
                  const SizedBox(width: 8),
                  for (final s in subjects) ...[
                    ChoiceChip(
                      avatar: Icon(subjectIcon(s.id), size: 16, color: _subject == s.id ? Colors.white : Color(s.color)),
                      label: Text(s.name),
                      selected: _subject == s.id,
                      selectedColor: Color(s.color),
                      onSelected: (_) => setState(() => _subject = s.id),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(width: 1, height: 26, color: AppColors.line, margin: const EdgeInsets.symmetric(horizontal: 6)),
                ],
                for (final f in _Filter.values) ...[
                  ChoiceChip(
                    label: Text(const {
                      _Filter.all: '모든 문제',
                      _Filter.unsolved: '안 푼 문제',
                      _Filter.wrong: '오답',
                      _Filter.bookmarked: '북마크',
                    }[f]!),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(width: 1, height: 26, color: AppColors.line, margin: const EdgeInsets.symmetric(horizontal: 6)),
                for (var d = 1; d <= 5; d++) ...[
                  ChoiceChip(
                    label: Text('난이도 $d'),
                    selected: _difficulty == d,
                    onSelected: (_) => setState(() => _difficulty = _difficulty == d ? null : d),
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
          ]),
        ),
      ),
      for (final s in shown)
        ..._subjectSlivers(context, app, s),
      const SliverToBoxAdapter(child: SizedBox(height: 40)),
    ]);

    if (!widget.standalone) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          TextButton.icon(
            onPressed: () => showExamSetup(context, subjectId: _subject),
            icon: const Icon(Icons.timer_outlined),
            label: const Text('모의고사'),
          ),
          TextButton.icon(
            onPressed: () => CourseBrowser.openQuickVariant(context, subjectId: _subject),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('변형문제 10개'),
          ),
          FilledButton.icon(
            key: const Key('course-endless'),
            onPressed: () => SolveScreen.endless(context, courseId: _subject),
            icon: const Icon(Icons.all_inclusive_rounded),
            label: const Text('무한 풀기'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: content,
    );
  }

  List<Widget> _subjectSlivers(BuildContext context, AppState app, Subject s) {
    final color = Color(s.color);
    final out = <Widget>[];
    for (final unit in s.units) {
      final all = s.problemsInUnit(unit);
      final ps = all.where((p) => _match(app, p)).toList();
      if (ps.isEmpty) continue;
      final solved = all.where((p) => app.isSolved(p.id)).length;
      final tally = app.byUnit['${s.id}|$unit'];
      out.add(SliverPadding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
        sliver: SliverToBoxAdapter(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: color, width: 5)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_subject == null ? '${s.name} · $unit' : unit,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                      const SizedBox(height: 6),
                      Row(children: [
                        SizedBox(width: 160, child: AccuracyBar(value: solved / all.length, color: color, height: 6)),
                        const SizedBox(width: 10),
                        Text('$solved/${all.length} 풀이'
                            '${tally != null && tally.solved > 0 ? ' · 정답률 ${pct(tally.accuracy)}' : ''}',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
                      ]),
                    ]),
                  ),
                  IconButton(
                    tooltip: '이 단원 무한 풀기',
                    onPressed: () => SolveScreen.endless(context, courseId: s.id, unit: unit, title: unit),
                    icon: const Icon(Icons.all_inclusive_rounded),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    onPressed: () {
                      final vs = ps.where(app.hasVariant).map(app.makeVariant).toList();
                      SolveScreen.open(context, title: '$unit · 변형', problems: vs, mode: 'variant');
                    },
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('변형'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    onPressed: () => SolveScreen.open(context, title: unit, problems: ps),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text('${ps.length}문제 풀기'),
                  ),
                ]),
              ),
              const Divider(),
              for (var i = 0; i < ps.length; i++) _ProblemRow(problem: ps[i], color: color, onTap: () {
                SolveScreen.open(context, title: unit, problems: ps.sublist(i) + ps.sublist(0, i));
              }),
            ]),
          ),
        ),
      ));
    }
    if (out.isEmpty && _subject != null) {
      out.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 40),
          child: EmptyState(icon: Icons.filter_alt_off_rounded, title: '조건에 맞는 문제가 없어요'),
        ),
      ));
    }
    return out;
  }
}

class _ProblemRow extends StatelessWidget {
  const _ProblemRow({required this.problem, required this.color, required this.onTap});
  final Problem problem;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final st = app.stateOf(problem.id);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          ResultMark(correct: st.attempts == 0 ? null : st.lastCorrect, size: 28),
          const SizedBox(width: 14),
          SizedBox(
            width: 170,
            child: Text(problem.topic.isEmpty ? problem.unit : problem.topic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(MathText.plain(problem.stem).replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          if (st.inWrongNote) ...[
            const Pill('오답', color: AppColors.wrong, dense: true),
            const SizedBox(width: 6),
          ],
          if (st.bookmarked) ...[
            const Icon(Icons.bookmark_rounded, color: AppColors.accent, size: 18),
            const SizedBox(width: 6),
          ],
          if (problem.passageId != null) ...[
            const Pill('지문', color: AppColors.inkSoft, dense: true),
            const SizedBox(width: 6),
          ],
          if (app.hasVariant(problem)) ...[
            const Tooltip(
              message: '변형문제 가능',
              child: Icon(Icons.auto_awesome_rounded, color: AppColors.inkMuted, size: 16),
            ),
            const SizedBox(width: 10),
          ],
          Pill(problem.isChoice ? '객관식' : '단답형', color: AppColors.inkSoft, dense: true),
          const SizedBox(width: 12),
          DifficultyDots(problem.difficulty, color: color, size: 6),
        ]),
      ),
    );
  }
}

/// Standalone page for one subject (from dashboard cards).
class SubjectScreen extends StatelessWidget {
  const SubjectScreen({super.key, required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) => CourseBrowser(initialSubject: subjectId, standalone: true);
}


/// 문제집 탭: 교과군별 문제집과 과목.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  static void openQuickVariant(BuildContext context, {String? subjectId}) =>
      CourseBrowser.openQuickVariant(context, subjectId: subjectId);

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _group = 'all';
  bool _mine = true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final mineIds = app.myCourseIds;
    final courses = [
      for (final s in app.bank.subjects)
        if ((!_mine || mineIds.contains(s.id) || s.id == ProblemBank.customSubjectId) &&
            (_group == 'all' || s.group == _group) &&
            s.problems.isNotEmpty)
          s
    ];
    final courseIds = {for (final c in courses) c.id};
    final wbs = app.bank.workbooks.where((w) => app.bank.coursesOf(w).any(courseIds.contains)).toList();

    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 1200 ? 4 : (box.maxWidth >= 860 ? 3 : 2);
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          Row(children: [
            const Expanded(
              child: Text('문제집', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
            ),
            FilterChip(
              key: const Key('lib-mine'),
              label: const Text('내 과목만'),
              selected: _mine,
              selectedColor: AppColors.ink,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(color: _mine ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
              onSelected: (v) => setState(() => _mine = v),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('전체'), selected: _group == 'all', onSelected: (_) => setState(() => _group = 'all')),
            for (final g in SubjectGroup.all)
              ChoiceChip(
                key: Key('group-${g.id}'),
                label: Text(g.name),
                selected: _group == g.id,
                selectedColor: Color(g.color),
                labelStyle: TextStyle(
                    color: _group == g.id ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
                onSelected: (_) => setState(() => _group = g.id),
              ),
          ]),
          const SizedBox(height: 26),
          SectionHeader('문제집', subtitle: '${wbs.length}권 · 순서대로 풀며 진도를 채워요'),
          if (wbs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Text('조건에 맞는 문제집이 없어요', style: TextStyle(color: AppColors.inkMuted)),
              ),
            )
          else
            GridView.count(
              crossAxisCount: cols,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.75,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final w in wbs) WorkbookCard(workbook: w)],
            ),
          const SizedBox(height: 30),
          SectionHeader('과목별 문제', subtitle: '단원을 골라 풀거나, 과목 전체를 무한 풀기로'),
          GridView.count(
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.45,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [for (final c in courses) _CourseCard(course: c)],
          ),
        ],
      );
    });
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});
  final Subject course;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final color = Color(course.color);
    final t = app.subjectTally(course.id);
    final cov = app.coverage(course);
    final grades = course.grades.isEmpty ? '' : (course.grades.length > 3 ? '${course.grades.first}~${course.grades.last}' : course.grades.join('·'));
    return Card(
      key: Key('coursecard-${course.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SubjectScreen(subjectId: course.id))),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Icon(courseIcon(course), color: Colors.white, size: 21),
              ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: '무한 풀기',
                onPressed: () => SolveScreen.endless(context, courseId: course.id),
                icon: const Icon(Icons.all_inclusive_rounded, size: 20),
              ),
            ]),
            const Spacer(),
            Text(course.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 2),
            Text(
                [if (grades.isNotEmpty) grades, if (course.track.isNotEmpty) course.track, '${course.problems.length}문항']
                    .join(' · '),
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            AccuracyBar(value: cov, color: color, height: 6),
            const SizedBox(height: 6),
            Text('진도 ${pct(cov)}${t.solved > 0 ? ' · 정답률 ${pct(t.accuracy)}' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
