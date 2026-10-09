import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import 'dashboard_screen.dart' show subjectIcon, courseIcon;
import '../widgets/workbook_card.dart';
import 'exam_setup.dart';
import 'series_screen.dart';
import 'solve_screen.dart';
import 'workbook_screen.dart';
import 'workbook_store_screen.dart';

enum _Filter { all, unsolved, wrong, bookmarked }

/// 문제를 묶어 보여 주는 방법: 교재(문제집)별 · 단원별.
enum _GroupBy { book, unit }

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
  _GroupBy _group = _GroupBy.book;
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
                for (final g in _GroupBy.values) ...[
                  ChoiceChip(
                    key: Key('browse-by-${g.name}'),
                    label: Text(g == _GroupBy.book ? '교재별' : '단원별'),
                    selected: _group == g,
                    onSelected: (_) => setState(() => _group = g),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(width: 1, height: 26, color: AppColors.line, margin: const EdgeInsets.symmetric(horizontal: 6)),
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
      if (_group == _GroupBy.book)
        ..._bookSlivers(context, app)
      else
        for (final s in shown) ..._subjectSlivers(context, app, s),
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
          if (kEndlessEnabled)
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

  /// 교재별 보기 — 내 교재 먼저, 그다음 그 밖의 교재. 시리즈(FLOW TYPE…)끼리 묶는다.
  List<Widget> _bookSlivers(BuildContext context, AppState app) {
    bool inSubject(Workbook w) => _subject == null || app.bank.coursesOf(w).contains(_subject);
    final books = [
      for (final w in app.bank.workbooks)
        if (inSubject(w) && app.bank.problemsOf(w).any((p) => _match(app, p))) w,
    ];
    final mine = [for (final w in books) if (app.hasWorkbook(w.id)) w];
    final rest = [for (final w in books) if (!app.hasWorkbook(w.id)) w];
    // 선생님은 담는 교재가 따로 없으니 한 묶음으로
    final sections = app.isTeacher ? [('교재', books)] : [('내 교재', mine), ('그 밖의 교재', rest)];
    final out = <Widget>[];
    for (final (title, list) in sections) {
      if (list.isEmpty) continue;
      out.add(SliverPadding(
        padding: const EdgeInsets.fromLTRB(32, 22, 32, 4),
        sliver: SliverToBoxAdapter(
          child: Row(children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(width: 8),
            Text('${list.length}권', style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
          ]),
        ),
      ));
      String? series;
      for (final w in list) {
        if (w.series.isNotEmpty && w.series != series) {
          series = w.series;
          out.add(SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 12, 32, 2),
            sliver: SliverToBoxAdapter(
              child: Text(series,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.inkMuted, letterSpacing: 0.2)),
            ),
          ));
        } else if (w.series.isEmpty) {
          series = null;
        }
        out.add(SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
          sliver: SliverToBoxAdapter(child: _BookRow(workbook: w)),
        ));
      }
    }
    if (out.isEmpty) {
      out.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 40),
          child: EmptyState(icon: Icons.menu_book_rounded, title: '조건에 맞는 교재가 없어요'),
        ),
      ));
    }
    return out;
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
                  if (kEndlessEnabled)
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

/// 교재별 보기의 한 줄 — 제목 · 범위 · 진도. 누르면 그 교재 화면으로.
class _BookRow extends StatelessWidget {
  const _BookRow({required this.workbook});
  final Workbook workbook;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final w = workbook;
    final course = app.bank.subject(w.course);
    final color = Color(course?.color ?? 0xFF5B6475);
    final (done, total) = app.workbookProgress(w);
    final sub = [
      if (w.scope.isNotEmpty) w.scope,
      if (w.stage.isNotEmpty) w.stage,
      '$total문항',
    ].join(' · ');
    return Card(
      key: Key('book-row-${w.id}'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => WorkbookScreen.open(context, w.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Row(children: [
            Container(width: 6, height: 34, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.3)),
                const SizedBox(height: 3),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.inkMuted, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(width: 14),
            SizedBox(width: 120, child: AccuracyBar(value: total == 0 ? 0 : done / total, color: color, height: 6)),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: Text('$done/$total',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
          ]),
        ),
      ),
    );
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


/// 내 교재: 학생이 담은 문제집만. 새 문제집은 "문제집 담기"(커리큘럼별 카탈로그)에서.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  static void openQuickVariant(BuildContext context, {String? subjectId}) =>
      CourseBrowser.openQuickVariant(context, subjectId: subjectId);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final books = app.myWorkbooks;
    final byCourse = <String, List<Workbook>>{};
    for (final w in books) {
      byCourse.putIfAbsent(w.course, () => []).add(w);
    }
    final solved = books.fold<int>(0, (n, w) => n + app.workbookProgress(w).$1);
    final total = books.fold<int>(0, (n, w) => n + app.workbookProgress(w).$2);

    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 620;
      final cols = box.maxWidth >= 1200 ? 4 : (box.maxWidth >= 860 ? 3 : (box.maxWidth >= 560 ? 2 : 1));
      return ListView(
        padding: EdgeInsets.fromLTRB(narrow ? 16 : 32, narrow ? 18 : 28, narrow ? 16 : 32, 40),
        children: [
          // 머리말 — 폰 세로에서는 제목 아래로 버튼을 내린다
          Builder(builder: (context) {
            final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('내 교재',
                  style: TextStyle(fontSize: narrow ? 24 : 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
              const SizedBox(height: 4),
              Text(
                books.isEmpty ? '풀 문제집을 골라 담으면 여기에서 풀 수 있어요' : '${books.length}권 · $solved/$total 문항 풀이',
                style: TextStyle(fontSize: narrow ? 14 : 15, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
              ),
            ]);
            final buttons = <Widget>[
              if (books.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => showExamSetup(context),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('모의고사 만들기'),
                ),
              FilledButton.icon(
                key: const Key('lib-add'),
                onPressed: () => WorkbookStoreScreen.open(context),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size(0, 50)),
                icon: const Icon(Icons.add_rounded),
                label: const Text('문제집 담기'),
              ),
            ];
            if (!narrow) {
              return Row(children: [
                Expanded(child: title),
                for (final b in buttons) ...[const SizedBox(width: 10), b],
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 8, children: buttons),
            ]);
          }),
          const SizedBox(height: 24),
          if (books.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: EmptyState(
                  icon: Icons.collections_bookmark_rounded,
                  title: '내 교재가 비어 있어요',
                  message: '개념서부터 N제·모의고사까지, 과목과 커리큘럼별로 골라 담아 보세요.\n담은 문제집으로 오늘의 세트가 만들어져요.',
                  action: FilledButton.icon(
                    key: const Key('lib-empty-add'),
                    onPressed: () => WorkbookStoreScreen.open(context),
                    icon: const Icon(Icons.storefront_rounded),
                    label: const Text('문제집 고르러 가기'),
                  ),
                ),
              ),
            )
          else
            for (final e in byCourse.entries) ...[
              _CourseHeader(courseId: e.key),
              GridView.count(
                crossAxisCount: cols,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.75,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // 같은 시리즈(FLOW TYPE…)는 한 칸으로 묶고, 누르면 회차를 고른다
                children: [
                  for (final g in groupBySeries(e.value))
                    g.length == 1 ? WorkbookCard(workbook: g.first) : _SeriesCard(books: g),
                ],
              ),
              const SizedBox(height: 26),
            ],
        ],
      );
    });
  }
}

/// 시리즈 한 칸 — "FLOW TYPE · 11회차". 누르면 회차 고르기로.
class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.books});
  final List<Workbook> books;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final first = books.first;
    final series = first.series.trim();
    final course = app.bank.subject(first.course);
    final color = Color(course?.color ?? 0xFF5B6475);
    var done = 0, total = 0;
    for (final w in books) {
      final (d, t) = app.workbookProgress(w);
      done += d;
      total += t;
    }
    final doneBooks = books.where((w) {
      final (d, t) = app.workbookProgress(w);
      return t > 0 && d == t;
    }).length;
    return Card(
      key: Key('seriescard-$series'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => SeriesScreen.open(context, series),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 10, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Pill(first.stage, color: stageColor(first.stage), dense: true),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('${books.length}회차',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted, size: 20),
                ]),
                const SizedBox(height: 10),
                Text(series,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.25)),
                const SizedBox(height: 4),
                Text(doneBooks == 0 ? '회차를 골라 푸세요' : '$doneBooks회차 완주',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                const Spacer(),
                AccuracyBar(value: total == 0 ? 0 : done / total, color: color, height: 6),
                const SizedBox(height: 6),
                Text('$done / $total 문항',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CourseHeader extends StatelessWidget {
  const _CourseHeader({required this.courseId});
  final String courseId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = app.bank.subject(courseId);
    final color = Color(c?.color ?? 0xFF5B6475);
    final t = app.subjectTally(courseId);
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 620; // 폰 세로에서는 글자 없이 아이콘만
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Icon(c == null ? Icons.menu_book_rounded : courseIcon(c), color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(c?.name ?? courseId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ),
          const SizedBox(width: 10),
          if (t.solved > 0)
            Text('정답률 ${pct(t.accuracy)}', style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (narrow) ...[
            if (kEndlessEnabled)
              IconButton(
                tooltip: '이 과목 무한 풀기',
                onPressed: () => SolveScreen.endless(context, courseId: courseId, title: c?.name),
                icon: const Icon(Icons.all_inclusive_rounded, size: 20),
              ),
            IconButton(
              tooltip: '더 담기',
              onPressed: () => WorkbookStoreScreen.open(context, course: courseId),
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ] else ...[
            if (kEndlessEnabled)
              TextButton.icon(
                onPressed: () => SolveScreen.endless(context, courseId: courseId, title: c?.name),
                icon: const Icon(Icons.all_inclusive_rounded, size: 18),
                label: const Text('이 과목 무한 풀기'),
              ),
            TextButton.icon(
              onPressed: () => WorkbookStoreScreen.open(context, course: courseId),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('더 담기'),
            ),
          ],
        ]),
      );
    });
  }
}
