import 'package:flutter/material.dart';

import '../app/app_state.dart';
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
  String _grade = '고2';
  String _goal = '수능';
  final List<String> _workbooks = [];

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final acc = app.account;
    _name = TextEditingController(text: acc != null ? acc.name : (app.profile.name == '학생' ? '' : app.profile.name));
    if (acc != null && acc.grade.isNotEmpty) _grade = acc.grade;
    if (widget.editing || app.learner.onboarded) {
      _grade = app.learner.grade;
      _goal = app.learner.goal;
      _workbooks.addAll(app.learner.workbooks);
    } else if (kGrades.contains(app.learner.grade) && acc != null && acc.grade.isEmpty) {
      _grade = app.learner.grade;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _finish(AppState app) {
    app.completeOnboarding(
      name: _name.text,
      grade: _grade,
      goal: _goal,
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
      '목표에 맞춰 D-day와 오늘의 세트를 짜 드려요.',
      '과목별로 개념서부터 유형·기출·N제·모의고사까지 있어요. 고른 문제집이 "내 교재"에 담기고, 내 교재의 문제로 오늘의 세트와 무한 풀기가 만들어져요. 나중에 언제든 더 담을 수 있어요.',
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
                    onPressed: last ? () => _finish(app) : () => setState(() => _step++),
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
          const _Label('학년'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final g in kGrades)
              _BigChoice(
                key: Key('grade-$g'),
                label: g,
                selected: _grade == g,
                onTap: () => setState(() => _grade = g),
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
      default:
        return WorkbookCatalog(
          grade: _grade,
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
