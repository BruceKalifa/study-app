import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/goals.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import 'workbook_store_screen.dart' show WorkbookCatalog;

/// First run (and "학습 설정 바꾸기"): 이름·학년 → 목표 → 문제집 고르기(내 교재).
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
  /// 고른 학년·과정 (복수 선택, 고른 순서대로 — 첫 번째가 대표)
  final List<String> _grades = [];
  /// 고른 목표 (복수 선택) — 고른 과정에 맞는 목록에서 고른다 (lib/app/goals.dart)
  final List<String> _goals = [];
  final List<String> _workbooks = [];

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final acc = app.account;
    _name = TextEditingController(text: acc != null ? acc.name : (app.profile.name == '학생' ? '' : app.profile.name));
    if (acc != null && acc.grades.isNotEmpty) {
      _grades.addAll(acc.grades);
    } else if (acc != null && acc.grade.isNotEmpty) {
      _grades.add(acc.grade);
    }
    if (widget.editing || app.learner.onboarded) {
      _grades
        ..clear()
        ..addAll(app.learner.grades);
      _goals.addAll(app.learner.goals);
      _workbooks.addAll(app.learner.workbooks);
    } else if (kGrades.contains(app.learner.grade) && acc != null && acc.grade.isEmpty) {
      _grades.add(app.learner.grade);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// 과정을 다시 골랐을 수 있으니 목록에 없는 목표는 빼고, 하나도 없으면 맨 위 것을 미리 골라 둔다.
  void _syncGoals() {
    final valid = goalLabels(_grades);
    _goals.removeWhere((g) => !valid.contains(g));
    if (_goals.isEmpty && valid.isNotEmpty) _goals.add(valid.first);
  }

  void _finish(AppState app) {
    app.completeOnboarding(
      name: _name.text,
      grade: _grades.first,
      grades: List<String>.of(_grades),
      goals: List<String>.of(_goals),
      courses: const <String>[],
      workbooks: List<String>.of(_workbooks),
    );
    if (widget.editing && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    const titles = ['반가워요!', '목표가 무엇인가요?', '풀 문제집을 골라요'];
    const subs = [
      '학년에 맞는 과목과 문제집을 보여 드릴게요.',
      '고른 과정에 맞는 목표예요. 여러 개 골라도 돼요. 목표에 맞춰 D-day와 오늘의 세트를 짜 드려요.',
      '과목별로 개념서부터 유형·기출·N제·모의고사까지 있어요. 고른 문제집이 "내 교재"에 담기고, 내 교재의 문제로 오늘의 세트가 만들어져요. 나중에 언제든 더 담을 수 있어요.',
    ];
    final last = _step == 2;
    final n = _workbooks.length;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: widget.editing ? AppBar(title: const Text('학습 설정')) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: last ? 1100 : 820),
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
                    const Text(kAppName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                  ],
                  const Spacer(),
                  for (var i = 0; i < 3; i++)
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
                const SizedBox(height: 30),
                Text(titles[_step], style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.4)),
                const SizedBox(height: 8),
                Text(subs[_step], style: const TextStyle(fontSize: 16, color: AppColors.inkSoft, height: 1.5)),
                const SizedBox(height: 22),
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
                  if (last) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        n == 0 ? '아직 고른 문제집이 없어요' : '내 교재 $n권: ${[for (final id in _workbooks) app.bank.workbook(id)?.title ?? id].join(', ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: Key(last ? 'onb-start' : 'onb-next'),
                    onPressed: _grades.isEmpty || (_step == 1 && _goals.isEmpty)
                        ? null // 학년·과정, 목표를 하나 이상 골라야 넘어간다
                        : (last
                            ? () => _finish(app)
                            : () => setState(() {
                                  _step++;
                                  if (_step == 1) _syncGoals();
                                })),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(220, 58),
                      backgroundColor: last ? AppColors.accent : AppColors.ink,
                    ),
                    icon: Icon(last ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded),
                    label: Text(last
                        ? (widget.editing
                            ? '저장하기'
                            : n == 0
                                ? '나중에 고르고 시작하기'
                                : '$n권 담고 시작하기')
                        : '다음'),
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
          const _Label('학년·과정'),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('여러 개 골라도 돼요 (예: 한양대 + N수 + 편입)',
                style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
          ),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final g in kGrades)
              _BigChoice(
                key: Key('grade-$g'),
                label: g,
                selected: _grades.contains(g),
                onTap: () => setState(() {
                  if (!_grades.remove(g)) _grades.add(g);
                }),
                width: 120,
              ),
          ]),
        ]);
      case 1:
        final sections = goalSections(_grades);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (grade, options) in sections) ...[
            // 과정을 둘 이상 골랐을 때만 과정 이름으로 나눠 보여 준다
            if (sections.length > 1) _Label(grade),
            for (final o in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GoalCard(
                  key: Key('goal-${o.label}'),
                  title: o.label,
                  desc: o.desc,
                  icon: o.icon,
                  selected: _goals.contains(o.label),
                  onTap: () => setState(() {
                    if (!_goals.remove(o.label)) _goals.add(o.label);
                  }),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ]);
      default:
        return WorkbookCatalog(
          grades: _grades,
          shrinkWrap: true,
          isSelected: _workbooks.contains,
          onToggle: (w) => setState(() {
            if (_workbooks.contains(w.id)) {
              _workbooks.remove(w.id);
            } else {
              _workbooks.add(w.id);
            }
          }),
        );
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
