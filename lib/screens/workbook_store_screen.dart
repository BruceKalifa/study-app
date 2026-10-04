import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/workbook_card.dart' show workbookLevelColor;
import 'dashboard_screen.dart' show courseIcon;
import 'workbook_screen.dart';

Color stageColor(String stage) => switch (stage) {
      '개념' => AppColors.correct,
      '유형' => const Color(0xFF0EA5E9),
      '기출' => AppColors.blue,
      'N제' => const Color(0xFF8C5BD6),
      '모의고사' => AppColors.accent,
      _ => AppColors.inkSoft,
    };

/// 문제집 고르기: 과목 → 커리큘럼 단계(개념 → 유형 → 기출 → N제 → 모의고사) → 내 교재에 담기.
class WorkbookStoreScreen extends StatelessWidget {
  const WorkbookStoreScreen({super.key, this.initialCourse});
  final String? initialCourse;

  static Future<void> open(BuildContext context, {String? course}) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => WorkbookStoreScreen(initialCourse: course)));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final n = app.learner.workbooks.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('문제집 고르기'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Pill(n == 0 ? '내 교재 비어 있음' : '내 교재 $n권', icon: Icons.collections_bookmark_rounded, color: AppColors.ink),
            ),
          ),
        ],
      ),
      body: WorkbookCatalog(
        grade: app.learner.grade,
        initialCourse: initialCourse,
        isSelected: app.hasWorkbook,
        onToggle: (w) {
          final had = app.hasWorkbook(w.id);
          if (had) {
            app.removeWorkbook(w.id);
          } else {
            app.addWorkbook(w.id);
          }
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              duration: const Duration(seconds: 2),
              content: Text(had ? '「${w.title}」을(를) 내 교재에서 뺐어요' : '「${w.title}」을(를) 내 교재에 담았어요'),
            ));
        },
        onOpen: (w) => WorkbookScreen.open(context, w.id),
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 40),
      ),
    );
  }
}

/// The catalog itself — also used inside onboarding.
class WorkbookCatalog extends StatefulWidget {
  const WorkbookCatalog({
    super.key,
    required this.grade,
    required this.isSelected,
    required this.onToggle,
    this.onOpen,
    this.initialCourse,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
  });

  final String grade;
  final bool Function(String workbookId) isSelected;
  final ValueChanged<Workbook> onToggle;
  final ValueChanged<Workbook>? onOpen;
  final String? initialCourse;
  final EdgeInsets padding;

  /// Inside another scroll view (onboarding).
  final bool shrinkWrap;

  @override
  State<WorkbookCatalog> createState() => _WorkbookCatalogState();
}

class _WorkbookCatalogState extends State<WorkbookCatalog> {
  String? _course;
  String? _scope;
  bool _allGrades = false;

  List<Subject> _courses(AppState app) {
    final withBooks = {for (final w in app.bank.workbooks) ...app.bank.coursesOf(w)};
    return [
      for (final s in app.bank.subjects)
        if (withBooks.contains(s.id) && (_allGrades || s.grades.isEmpty || s.grades.contains(widget.grade))) s
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final courses = _courses(app);
    if (_course == null || !courses.any((c) => c.id == _course)) {
      final want = widget.initialCourse;
      _course = courses.any((c) => c.id == want) ? want : (courses.isEmpty ? null : courses.first.id);
      _scope = null;
    }
    final course = _course == null ? null : app.bank.subject(_course!);
    final books = course == null ? <Workbook>[] : app.workbooksForCourse(course.id);
    final scopes = <String>{for (final w in books) if (w.scope.isNotEmpty) w.scope}.toList();
    final shown = [for (final w in books) if (_scope == null || w.scope == _scope) w];
    final stages = <String>{for (final w in shown) w.stage}.toList()
      ..sort((a, b) => kWorkbookStages.indexOf(a).compareTo(kWorkbookStages.indexOf(b)));
    final mine = books.where((w) => widget.isSelected(w.id)).length;

    final children = <Widget>[
      // course chips
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final c in courses)
          ChoiceChip(
            key: Key('store-course-${c.id}'),
            avatar: Icon(courseIcon(c), size: 17, color: _course == c.id ? Colors.white : Color(c.color)),
            label: Text(c.name),
            selected: _course == c.id,
            selectedColor: Color(c.color),
            labelStyle: TextStyle(color: _course == c.id ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
            onSelected: (_) => setState(() {
              _course = c.id;
              _scope = null;
            }),
          ),
        TextButton(
          onPressed: () => setState(() => _allGrades = !_allGrades),
          child: Text(_allGrades ? '${widget.grade} 과목만 보기' : '다른 학년 과목도 보기'),
        ),
      ]),
      const SizedBox(height: 22),
      if (course == null)
        const Padding(
          padding: EdgeInsets.only(top: 30),
          child: EmptyState(icon: Icons.menu_book_rounded, title: '아직 문제집이 없어요', message: '새 문제집이 올라오면 여기에서 고를 수 있어요.'),
        )
      else ...[
        // curriculum path
        _CurriculumPath(
          color: Color(course.color),
          counts: {for (final s in kWorkbookStages) s: shown.where((w) => w.stage == s).length},
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text('${course.name} · 문제집 ${books.length}권${mine > 0 ? ' · 내 교재 $mine권' : ''}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
          ),
          if (scopes.length > 1)
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('전체 범위'), selected: _scope == null, onSelected: (_) => setState(() => _scope = null)),
              for (final s in scopes)
                ChoiceChip(
                  key: Key('store-scope-$s'),
                  label: Text(s),
                  selected: _scope == s,
                  onSelected: (_) => setState(() => _scope = s),
                ),
            ]),
        ]),
        const SizedBox(height: 8),
        for (final stage in stages) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 10),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: stageColor(stage), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(stage, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              const SizedBox(width: 8),
              Text(_stageHint(stage), style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
            ]),
          ),
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 1100 ? 3 : (box.maxWidth >= 640 ? 2 : 1);
            final w = (box.maxWidth - (cols - 1) * 14) / cols;
            return Wrap(spacing: 14, runSpacing: 14, children: [
              for (final b in shown.where((x) => x.stage == stage))
                SizedBox(
                  width: w,
                  child: _BookTile(
                    book: b,
                    color: Color(course.color),
                    selected: widget.isSelected(b.id),
                    onToggle: () => widget.onToggle(b),
                    onOpen: widget.onOpen == null ? null : () => widget.onOpen!(b),
                  ),
                ),
            ]);
          }),
        ],
      ],
    ];

    if (widget.shrinkWrap) {
      return Padding(
        padding: widget.padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
    }
    return ListView(padding: widget.padding, children: children);
  }

  static String _stageHint(String stage) => switch (stage) {
        '개념' => '교과 개념을 문제로 익혀요',
        '유형' => '자주 나오는 유형을 정리해요',
        '기출' => '수능·평가원·교육청 기출',
        'N제' => '실전 감각을 기르는 새 문항',
        '모의고사' => '시간을 재고 한 회씩',
        _ => '',
      };
}

/// 개념 → 유형 → 기출 → N제 → 모의고사
class _CurriculumPath extends StatelessWidget {
  const _CurriculumPath({required this.color, required this.counts});
  final Color color;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          const Text('커리큘럼', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
          const SizedBox(width: 16),
          for (var i = 0; i < kWorkbookStages.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.inkMuted),
              ),
            Opacity(
              opacity: (counts[kWorkbookStages[i]] ?? 0) > 0 ? 1 : 0.4,
              child: Pill(
                '${kWorkbookStages[i]} ${counts[kWorkbookStages[i]] ?? 0}',
                color: stageColor(kWorkbookStages[i]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.color, required this.selected, required this.onToggle, this.onOpen});
  final Workbook book;
  final Color color;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final (done, total) = app.workbookProgress(book);
    final meta = [
      if (book.scope.isNotEmpty) book.scope,
      '${book.problemIds.length}문항',
      book.level,
      if (book.publisher.isNotEmpty) book.publisher,
    ].join(' · ');
    return Material(
      color: selected ? color.withValues(alpha: 0.06) : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key('store-book-${book.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen ?? onToggle,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? color : AppColors.line, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            // book spine
            Container(
              width: 44,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(10)),
              ),
              alignment: Alignment.center,
              child: Text(book.stage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.1)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.25)),
                const SizedBox(height: 3),
                Text(meta, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: workbookLevelColor(book.level))),
                if (book.desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(book.desc,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                ],
                if (done > 0) ...[
                  const SizedBox(height: 6),
                  Text('$done/$total 풀었어요', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            selected
                ? FilledButton.icon(
                    key: Key('store-add-${book.id}'),
                    onPressed: onToggle,
                    style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('담김'),
                  )
                : OutlinedButton.icon(
                    key: Key('store-add-${book.id}'),
                    onPressed: onToggle,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('담기'),
                  ),
          ]),
        ),
      ),
    );
  }
}
