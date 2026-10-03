import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import 'solve_screen.dart';

/// 모의고사 모드: pick subject / count / time, answers stay hidden until the end.
Future<void> showExamSetup(BuildContext context, {String? subjectId}) async {
  final cfg = await showDialog<(String, List<Problem>, int)>(
      context: context, builder: (_) => _ExamSetup(initialSubject: subjectId));
  if (cfg == null || !context.mounted) return;
  final (title, problems, ms) = cfg;
  await SolveScreen.open(context, title: title, problems: problems, mode: 'exam', timeLimitMs: ms);
}

class _ExamSetup extends StatefulWidget {
  const _ExamSetup({this.initialSubject});
  final String? initialSubject;

  @override
  State<_ExamSetup> createState() => _ExamSetupState();
}

class _ExamSetupState extends State<_ExamSetup> {
  String? _subject;
  int _count = 10;
  int _minutes = 20;
  bool _variants = true;

  @override
  void initState() {
    super.initState();
    _subject = widget.initialSubject;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.timer_rounded, color: AppColors.accent),
        SizedBox(width: 8),
        Text('모의고사 모드'),
      ]),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('제한 시간 안에 풀고, 끝나면 한꺼번에 채점해요. 풀이 중에는 정답이 보이지 않아요.',
              style: TextStyle(color: AppColors.inkSoft)),
          const SizedBox(height: 18),
          const Text('과목', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('전 과목'), selected: _subject == null, onSelected: (_) => setState(() => _subject = null)),
            for (final s in app.bank.subjects)
              ChoiceChip(
                label: Text(s.name),
                selected: _subject == s.id,
                selectedColor: Color(s.color),
                onSelected: (_) => setState(() => _subject = s.id),
              ),
          ]),
          const SizedBox(height: 16),
          const Text('문항 수', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final n in const [5, 10, 15, 20])
              ChoiceChip(label: Text('$n문항'), selected: _count == n, onSelected: (_) => setState(() => _count = n)),
          ]),
          const SizedBox(height: 16),
          const Text('제한 시간', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final m in const [10, 20, 30, 50])
              ChoiceChip(label: Text('$m분'), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('변형문제로 출제', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('숫자가 바뀐 새 문제라 답을 외워서 풀 수 없어요'),
            value: _variants,
            onChanged: (v) => setState(() => _variants = v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: () {
            final rnd = math.Random();
            final pool = app.problemsWhere(subjectId: _subject)..shuffle(rnd);
            // spread difficulty: easy → hard like a real paper
            final picked = pool.take(_count).toList()..sort((a, b) => a.difficulty.compareTo(b.difficulty));
            final problems = <Problem>[
              for (final p in picked) _variants && p.hasTemplate ? app.makeVariant(p) : p,
            ];
            final name = _subject == null ? '전 과목' : (app.bank.subject(_subject!)?.name ?? '');
            Navigator.pop(context, ('모의고사 · $name ${problems.length}문항', problems, _minutes * 60000));
          },
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('시작'),
        ),
      ],
    );
  }
}
