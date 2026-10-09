import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import '../widgets/workbook_card.dart' show stageColor, workbookLevelColor;
import 'answer_key_screen.dart';
import 'concept_screen.dart';
import 'solve_screen.dart';

/// One 문제집: problems in order, progress, 이어 풀기 / 틀린 것만.
/// 개념 교재(CORE TYPE 처럼 개념·실전개념이 문제와 함께 든 책)는 목차마다 개념 카드가 문제 위에 나온다.
class WorkbookScreen extends StatefulWidget {
  const WorkbookScreen({super.key, required this.workbookId});
  final String workbookId;

  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkbookScreen(workbookId: id)));

  @override
  State<WorkbookScreen> createState() => _WorkbookScreenState();
}

class _WorkbookScreenState extends State<WorkbookScreen> {
  /// 전체 | 개념 | 문제
  String _show = 'all';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final w = app.bank.workbook(widget.workbookId);
    if (w == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('문제집을 찾을 수 없어요')));
    final course = app.bank.subject(w.course);
    final color = Color(course?.color ?? 0xFF5B6475);
    final ps = app.bank.problemsOf(w);
    final (done, total) = app.workbookProgress(w);
    final unsolved = [for (final p in ps) if (!app.isSolved(p.id)) p];
    final wrong = [for (final p in ps) if (app.stateOf(p.id).inWrongNote) p];
    final firstOpen = ps.indexWhere((p) => !app.isSolved(p.id));
    final onShelf = app.hasWorkbook(w.id);
    // 내 교재에 없는 책은 미리보기 — 풀기 버튼을 누르면 담고 바로 시작
    void solve(VoidCallback go) {
      if (!onShelf) {
        app.addWorkbook(w.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「${w.title}」을(를) 내 교재에 담았어요')));
      }
      go();
    }

    final concepts = app.bank.conceptsOf(w);
    final groups = tocGroups(ps, concepts);
    // 목차 순서대로 펼친 개념들 — 개념 화면에서 앞뒤로 넘기는 순서
    final readOrder = [for (final g in groups) ...g.concepts];
    final showConcepts = _show != 'problem';
    final showProblems = _show != 'concept';
    void openConcept(Concept c) {
      final i = readOrder.indexWhere((x) => x.id == c.id);
      ConceptScreen.open(context, concepts: readOrder, index: i < 0 ? 0 : i, workbookId: w.id, color: color);
    }

    return Scaffold(
      appBar: AppBar(title: Text(w.series.isNotEmpty ? w.series : (course?.name ?? '문제집'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, children: [
                  Pill(w.stage, color: stageColor(w.stage)),
                  Pill(w.level, color: workbookLevelColor(w.level)),
                  if (w.scope.isNotEmpty) Pill(w.scope, color: AppColors.inkSoft),
                  if (w.publisher.isNotEmpty) Pill(w.publisher, color: AppColors.inkSoft),
                  if (concepts.isNotEmpty) Pill('개념 ${concepts.length}편', color: color),
                ]),
                const SizedBox(height: 10),
                Text(w.title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.1)),
                if (w.desc.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(w.desc, style: const TextStyle(fontSize: 15.5, color: AppColors.inkSoft)),
                ],
              ]),
            ),
            ProgressRing(
              value: total == 0 ? 0 : done / total,
              size: 96,
              stroke: 10,
              color: color,
              child: Text('$done/$total', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
          ]),
          const SizedBox(height: 20),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (concepts.isNotEmpty)
              FilledButton.tonalIcon(
                key: const Key('wb-concepts'),
                onPressed: () {
                  final next = readOrder.indexWhere((c) => !app.isConceptRead(c.id));
                  openConcept(readOrder[next < 0 ? 0 : next]);
                },
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                icon: const Icon(Icons.auto_stories_rounded),
                label: Text(readOrder.every((c) => app.isConceptRead(c.id)) ? '개념 다시 보기' : '개념 읽기'),
              ),
            FilledButton.icon(
              key: const Key('wb-continue'),
              style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(0, 52)),
              onPressed: ps.isEmpty
                  ? null
                  : () => solve(() => SolveScreen.open(context,
                      title: w.title, problems: firstOpen <= 0 ? ps : [...ps.sublist(firstOpen), ...ps.sublist(0, firstOpen)])),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(!onShelf
                  ? '내 교재에 담고 풀기'
                  : done == 0
                      ? '처음부터 풀기'
                      : (unsolved.isEmpty ? '다시 풀기' : '이어 풀기 · ${unsolved.length}문항 남음')),
            ),
            if (kEndlessEnabled && onShelf)
              OutlinedButton.icon(
                onPressed: () => SolveScreen.endless(context, workbookId: w.id, title: w.title),
                icon: const Icon(Icons.all_inclusive_rounded),
                label: const Text('무한 풀기'),
              ),
            if (wrong.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => SolveScreen.open(context,
                    title: '${w.title} · 오답 변형', problems: [for (final p in wrong) app.makeVariant(p)], mode: 'variant'),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text('틀린 ${wrong.length}문항 변형으로'),
              ),
            OutlinedButton.icon(
              onPressed: ps.isEmpty
                  ? null
                  : () => solve(() => SolveScreen.open(context,
                      title: '${w.title} · 모의고사', problems: ps, mode: 'exam', timeLimitMs: ps.length * 3 * 60000)),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('시험처럼 풀기'),
            ),
            OutlinedButton.icon(
              key: const Key('wb-answers'),
              onPressed: () => AnswerKeyScreen.open(context, w.id),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('답안표'),
            ),
            TextButton.icon(
              key: const Key('wb-toggle'),
              onPressed: () {
                if (onShelf) {
                  app.removeWorkbook(w.id);
                } else {
                  app.addWorkbook(w.id);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(onShelf ? '내 교재에서 뺐어요 · 푼 기록은 그대로 남아요' : '내 교재에 담았어요')));
              },
              icon: Icon(onShelf ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded),
              label: Text(onShelf ? '내 교재에서 빼기' : '내 교재에 담기'),
            ),
          ]),
          const SizedBox(height: 24),
          if (concepts.isNotEmpty) ...[
            SegmentedButton<String>(
              key: const Key('wb-show'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'all', label: Text('전체')),
                ButtonSegment(value: 'concept', label: Text('개념만')),
                ButtonSegment(value: 'problem', label: Text('문제만')),
              ],
              selected: {_show},
              onSelectionChanged: (v) => setState(() => _show = v.first),
            ),
            const SizedBox(height: 18),
          ],
          // 단원이 여럿인 교재(FLOW·BRIDGE TYPE 처럼)는 단원별로 묶어서 — 번호는 교재 전체 번호 그대로
          for (final g in groups)
            if ((showConcepts && g.concepts.isNotEmpty) || (showProblems && g.idx.isNotEmpty)) ...[
              if (g.name.isNotEmpty)
                _SectionHeader(
                  name: g.name,
                  color: color,
                  count: g.idx.length,
                  concepts: g.concepts.length,
                  onSolve: g.idx.isEmpty
                      ? null
                      : () => solve(() => SolveScreen.open(context,
                          title: '${w.title} · ${g.name}', problems: [for (final i in g.idx) ps[i]])),
                ),
              if (showConcepts && g.concepts.isNotEmpty)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (var k = 0; k < g.concepts.length; k++) ...[
                      if (k > 0) const Divider(height: 1),
                      _ConceptRow(concept: g.concepts[k], color: color, onTap: () => openConcept(g.concepts[k])),
                    ],
                  ]),
                ),
              if (showConcepts && g.concepts.isNotEmpty && showProblems && g.idx.isNotEmpty) const SizedBox(height: 8),
              if (showProblems && g.idx.isNotEmpty)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (var k = 0; k < g.idx.length; k++) ...[
                      if (k > 0) const Divider(height: 1),
                      _Row(n: g.idx[k] + 1, problem: ps[g.idx[k]], color: color, withUnit: usesTableOfContents(ps), onTap: () {
                        final i = g.idx[k];
                        solve(() => SolveScreen.open(context, title: w.title, problems: [...ps.sublist(i), ...ps.sublist(0, i)]));
                      }),
                    ],
                  ]),
                ),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

/// 목차 한 칸: 이름, 그 안의 문제(자리번호), 그 안의 개념.
class TocGroup {
  final String name;
  final List<int> idx;
  final List<Concept> concepts;
  const TocGroup(this.name, this.idx, this.concepts);
}

/// 교재의 목차 칸들 — 문제는 [byTableOfContents], 개념은 `section` 이 같은 목차 칸에 들어간다.
/// 목차가 비어 있으면 첫 칸에, 어느 칸과도 안 맞으면 맨 앞에 개념만 있는 칸으로 둔다 (책머리 개념).
List<TocGroup> tocGroups(List<Problem> ps, List<Concept> concepts) {
  final base = byTableOfContents(ps);
  if (concepts.isEmpty) return [for (final (name, idx) in base) TocGroup(name, idx, const <Concept>[])];
  final names = [for (final (name, _) in base) name];
  final byName = <String, List<Concept>>{for (final n in names) n: <Concept>[]};
  final lead = <String, List<Concept>>{}; // 문제 칸이 없는 목차 이름 → 개념
  final unnamedOnly = names.length == 1 && names.first.isEmpty; // 목차 없는 교재
  for (final c in concepts) {
    final key = c.section.trim();
    if (!unnamedOnly && key.isNotEmpty && byName.containsKey(key)) {
      byName[key]!.add(c);
    } else if (key.isNotEmpty) {
      lead.putIfAbsent(key, () => <Concept>[]).add(c);
    } else {
      (names.isEmpty ? lead.putIfAbsent('', () => <Concept>[]) : byName[names.first]!).add(c);
    }
  }
  return [
    for (final e in lead.entries) TocGroup(e.key, const <int>[], e.value),
    for (final (name, idx) in base) TocGroup(name, idx, byName[name] ?? const <Concept>[]),
  ];
}

final _dayRe = RegExp(r'DAY\s*(\d+)');

/// 이 교재에 목차가 있나 — 문항에 목차(section)가 적혀 있거나, 유형에 DAY 표시가 있으면.
bool usesTableOfContents(List<Problem> ps) =>
    ps.any((p) => p.section.trim().isNotEmpty || _dayRe.hasMatch(p.topic));

/// 한 문항이 들어갈 목차 이름 (목차가 없는 교재면 단원).
String sectionOf(Problem p, {required bool toc}) {
  if (!toc) return p.unit.trim();
  final s = p.section.trim();
  if (s.isNotEmpty) return s;
  final m = _dayRe.firstMatch(p.topic);
  return m == null ? '수업문항' : '숙제문항 DAY ${m.group(1)}';
}

/// 목록 한 줄에 쓸 이름 — 목차로 묶었으면 단원을 앞에 붙이고, DAY 표시는 (머리글에 있으니) 뗀다.
String tocRowLabel(Problem p, {required bool withUnit}) {
  final topic = p.topic.replaceFirst(RegExp(r'^\s*DAY\s*\d+\s*·\s*'), '').trim();
  final unit = p.unit.trim();
  if (!withUnit) return topic.isEmpty ? unit : topic;
  if (topic.isEmpty) return unit;
  return unit.isEmpty ? topic : '$unit · $topic';
}

/// 교재의 문항을 목차별로 (수업문항 · 숙제문항 DAY 1 …), 목차가 없으면 단원으로.
/// 묶을 거리가 하나뿐이면 묶지 않는다. 값은 [ps] 안의 자리번호.
List<(String, List<int>)> byTableOfContents(List<Problem> ps) {
  final toc = usesTableOfContents(ps);
  final order = <String>[];
  final by = <String, List<int>>{};
  for (var i = 0; i < ps.length; i++) {
    final k = sectionOf(ps[i], toc: toc);
    if (!by.containsKey(k)) {
      order.add(k);
      by[k] = [];
    }
    by[k]!.add(i);
  }
  if (order.length < 2) return [('', [for (var i = 0; i < ps.length; i++) i])];
  return [for (final k in order) (k, by[k]!)];
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.name, required this.color, required this.count, this.concepts = 0, required this.onSolve});
  final String name;
  final Color color;
  final int count;
  final int concepts;
  final VoidCallback? onSolve;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(children: [
        Container(width: 5, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(width: 8),
        Text([if (concepts > 0) '개념 $concepts', if (count > 0 || concepts == 0) '$count문항'].join(' · '),
            style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w700, fontSize: 13)),
        const Spacer(),
        if (onSolve != null)
          TextButton.icon(
            key: Key('wb-unit-$name'),
            onPressed: onSolve,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('이 목차 풀기'),
          ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.n, required this.problem, required this.color, required this.onTap, this.withUnit = false});
  final int n;
  final Problem problem;
  final Color color;
  final bool withUnit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final st = app.stateOf(problem.id);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(children: [
          SizedBox(
            width: 36,
            child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.inkSoft)),
          ),
          ResultMark(correct: st.attempts == 0 ? null : st.lastCorrect, size: 26),
          const SizedBox(width: 14),
          SizedBox(
            width: 230,
            child: Text(tocRowLabel(problem, withUnit: withUnit),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(MathText.plain(problem.stem).replaceAll('\n', ' '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkSoft)),
          ),
          const SizedBox(width: 12),
          if (problem.source != null) ...[
            Pill('기출', color: AppColors.accent, dense: true),
            const SizedBox(width: 8),
          ],
          if (problem.passageId != null) ...[
            const Pill('지문', color: AppColors.inkSoft, dense: true),
            const SizedBox(width: 8),
          ],
          DifficultyDots(problem.difficulty, color: color, size: 6),
        ]),
      ),
    );
  }
}

class _ConceptRow extends StatelessWidget {
  const _ConceptRow({required this.concept, required this.color, required this.onTap});
  final Concept concept;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final read = app.isConceptRead(concept.id);
    return InkWell(
      key: Key('concept-${concept.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(children: [
          SizedBox(width: 36, child: Icon(Icons.auto_stories_rounded, size: 22, color: color)),
          Icon(read ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 24, color: read ? AppColors.correct : AppColors.lineStrong),
          const SizedBox(width: 14),
          Expanded(
            child: Text(concept.title.isEmpty ? '개념' : concept.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (concept.topic.isNotEmpty) ...[
            Text(concept.topic,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkMuted)),
            const SizedBox(width: 12),
          ],
          Pill(concept.kind, color: color, dense: true),
        ]),
      ),
    );
  }
}
