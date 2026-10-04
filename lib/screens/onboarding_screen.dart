import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';

/// First run (and "학습 설정 바꾸기"): 학년 → 목표 → 과목 → 문제집.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.editing = false});

  /// Opened from settings: prefilled, closes when done.
  final bool editing;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  late final TextEditingController _name;
  String _grade = '고2';
  String _goal = '수능';
  final Set<String> _courses = {};
  final Set<String> _workbooks = {};
  bool _coursesTouched = false;
  bool _workbooksTouched = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _name = TextEditingController(text: app.profile.name == '학생' ? '' : app.profile.name);
    if (widget.editing || app.learner.onboarded) {
      _grade = app.learner.grade;
      _goal = app.learner.goal;
      _courses.addAll(app.learner.courses);
      _workbooks.addAll(app.learner.workbooks);
      _coursesTouched = _courses.isNotEmpty;
      _workbooksTouched = _workbooks.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Subject> _gradeCourses(AppState app) => app.coursesForGrade(_grade);

  Set<String> _effectiveCourses(AppState app) =>
      _coursesTouched ? _courses : {for (final s in _gradeCourses(app)) s.id};

  List<Workbook> _availableWorkbooks(AppState app) {
    final ids = _effectiveCourses(app);
    return app.bank.workbooks.where((w) => ids.contains(w.course)).toList();
  }

  void _finish(AppState app) {
    final courses = _effectiveCourses(app).toList();
    final wbs = _workbooksTouched ? _workbooks.where((id) => _availableWorkbooks(app).any((w) => w.id == id)).toList() : <String>[];
    app.completeOnboarding(
      name: _name.text,
      grade: _grade,
      goal: _goal,
      courses: courses.length == _gradeCourses(app).length ? <String>[] : courses,
      workbooks: wbs,
    );
    if (widget.editing && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    const titles = ['반가워요!', '목표가 무엇인가요?', '공부할 과목을 골라요', '풀 문제집을 골라요'];
    const subs = [
      '학년에 맞는 과목과 문제집을 준비할게요.',
      '목표에 맞춰 D-day와 오늘의 세트를 짜 드려요.',
      '고른 과목에서만 오늘의 세트와 무한 풀기 문제가 나와요. 나중에 언제든 바꿀 수 있어요.',
      '문제집은 순서대로 풀 수 있는 세트예요. 안 고르면 내 과목의 문제집이 모두 보여요.',
    ];
    final last = _step == 3;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: widget.editing ? AppBar(title: const Text('학습 설정')) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  if (!widget.editing) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text('풀이노트', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                  ],
                  const Spacer(),
                  for (var i = 0; i < 4; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: i == _step ? 28 : 10,
                      height: 10,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: i <= _step ? AppColors.accent : AppColors.lineStrong,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                ]),
                const SizedBox(height: 34),
                Text(titles[_step], style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.4)),
                const SizedBox(height: 8),
                Text(subs[_step], style: const TextStyle(fontSize: 16, color: AppColors.inkSoft, height: 1.5)),
                const SizedBox(height: 26),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previous, if (current != null) current],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: SingleChildScrollView(child: SizedBox(width: double.infinity, child: _body(app))),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(120, 56)),
                      child: const Text('이전'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    key: Key(last ? 'onb-start' : 'onb-next'),
                    onPressed: last ? () => _finish(app) : () => setState(() => _step++),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(220, 58),
                      backgroundColor: last ? AppColors.accent : AppColors.ink,
                    ),
                    icon: Icon(last ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded),
                    label: Text(last ? (widget.editing ? '저장하기' : '시작하기 · 7일 무료 체험') : '다음'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppState app) {
    switch (_step) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Label('이름'),
          TextField(
            key: const Key('onb-name'),
            controller: _name,
            decoration: const InputDecoration(hintText: '이름 또는 닉네임'),
          ),
          const SizedBox(height: 26),
          const _Label('학년'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final g in kGrades)
              _BigChoice(
                key: Key('grade-$g'),
                label: g,
                selected: _grade == g,
                onTap: () => setState(() {
                  if (_grade != g) {
                    _grade = g;
                    _coursesTouched = false;
                    _courses.clear();
                    _workbooksTouched = false;
                    _workbooks.clear();
                  }
                }),
                width: 120,
              ),
          ]),
        ]);
      case 1:
        const goals = [
          ('수능', Icons.flag_rounded, '수능 D-day에 맞춰 실전 감각과 약점 유형을 관리해요'),
          ('내신', Icons.school_rounded, '학교 진도에 맞춰 단원별로 다지고 시험 기간을 대비해요'),
          ('둘 다', Icons.all_inclusive_rounded, '내신과 수능을 함께 챙겨요'),
        ];
        return Column(children: [
          for (final (g, icon, d) in goals)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GoalCard(
                key: Key('goal-$g'),
                title: g,
                desc: d,
                icon: icon,
                selected: _goal == g,
                onTap: () => setState(() => _goal = g),
              ),
            ),
        ]);
      case 2:
        final courses = _gradeCourses(app);
        final sel = _effectiveCourses(app);
        if (courses.isEmpty) return const Text('이 학년의 과목이 아직 없어요.');
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final g in SubjectGroup.all)
            if (courses.any((c) => c.group == g.id)) ...[
              _Label(g.name, color: Color(g.color)),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final c in courses.where((c) => c.group == g.id))
                  FilterChip(
                    key: Key('course-${c.id}'),
                    label: Text('${c.name}  ·  ${c.problems.length}문항'),
                    selected: sel.contains(c.id),
                    selectedColor: Color(c.color).withValues(alpha: 0.16),
                    checkmarkColor: Color(c.color),
                    onSelected: (v) => setState(() {
                      if (!_coursesTouched) {
                        _courses
                          ..clear()
                          ..addAll(sel);
                        _coursesTouched = true;
                      }
                      v ? _courses.add(c.id) : _courses.remove(c.id);
                    }),
                  ),
              ]),
              const SizedBox(height: 22),
            ],
        ]);
      default:
        final wbs = _availableWorkbooks(app);
        if (wbs.isEmpty) return const Text('고른 과목의 문제집이 아직 없어요. 무한 풀기와 오늘의 세트로 시작할 수 있어요.');
        final sel = _workbooksTouched ? _workbooks : {for (final w in wbs) w.id};
        return Column(children: [
          for (final w in wbs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CheckboxListTile(
                key: Key('wb-${w.id}'),
                value: sel.contains(w.id),
                onChanged: (v) => setState(() {
                  if (!_workbooksTouched) {
                    _workbooks
                      ..clear()
                      ..addAll(sel);
                    _workbooksTouched = true;
                  }
                  v == true ? _workbooks.add(w.id) : _workbooks.remove(w.id);
                }),
                tileColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text(w.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                    '${app.bank.subject(w.course)?.name ?? ''} · ${w.level} · ${w.problemIds.length}문항${w.desc.isEmpty ? '' : '\n${w.desc}'}'),
              ),
            ),
        ]);
    }
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.color = AppColors.inkSoft});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
      );
}

class _BigChoice extends StatelessWidget {
  const _BigChoice({super.key, required this.label, required this.selected, required this.onTap, this.width = 120});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: width,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.ink)),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard(
      {super.key, required this.title, required this.desc, required this.icon, required this.selected, required this.onTap});
  final String title, desc;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          ),
          child: Row(children: [
            Icon(icon, size: 30, color: selected ? AppColors.accent : AppColors.inkSoft),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.ink)),
                const SizedBox(height: 4),
                Text(desc,
                    style: TextStyle(
                        fontSize: 14.5, color: selected ? Colors.white.withValues(alpha: 0.75) : AppColors.inkSoft)),
              ]),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.accent),
          ]),
        ),
      ),
    );
  }
}
