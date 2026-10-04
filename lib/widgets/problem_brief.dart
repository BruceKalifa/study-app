import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/problem.dart';
import 'common.dart';
import 'math_text.dart';

/// Compact read-only view of a problem (선생님 화면 · 질문 · 오답 상세):
/// stem, <보기>, choices (정답 green, 학생 답 red), the student's answer and optionally the 해설.
class ProblemBrief extends StatelessWidget {
  const ProblemBrief({
    super.key,
    required this.problem,
    this.studentAnswer,
    this.showAnswer = true,
    this.showSolution = false,
    this.compact = false,
  });

  final Problem problem;

  /// What the student wrote (choice number as text or the short answer).
  final String? studentAnswer;
  final bool showAnswer;
  final bool showSolution;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = problem;
    final fs = compact ? 14.5 : 16.0;
    final given = int.tryParse(studentAnswer ?? '');
    final right = int.tryParse(p.answer);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Pill(p.subjectName, color: AppColors.ink, dense: true),
        if (p.unit.isNotEmpty) Pill(p.unit, color: AppColors.inkSoft, dense: true),
        if (p.topic.isNotEmpty) Pill(p.topic, color: AppColors.inkSoft, dense: true),
        if (p.isVariant || p.isTwin) const Pill('변형', color: AppColors.accent, dense: true, icon: Icons.auto_awesome_rounded),
        if (p.source != null) Pill(p.source!, color: AppColors.accent, dense: true),
        DifficultyDots(p.difficulty, size: 6),
      ]),
      const SizedBox(height: 12),
      MathText(p.stem, style: TextStyle(fontSize: fs, color: AppColors.ink, height: 1.7)),
      if (p.boxItems.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: AppColors.lineStrong), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('<보 기>', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
            const SizedBox(height: 4),
            for (final b in p.boxItems)
              MathText(b, style: TextStyle(fontSize: fs - 1, color: AppColors.inkSoft, height: 1.6)),
          ]),
        ),
      ],
      if (p.isChoice) ...[
        const SizedBox(height: 10),
        for (var i = 0; i < p.choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 10, top: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: showAnswer && right == i + 1
                          ? AppColors.correct
                          : (given == i + 1 ? AppColors.wrong : AppColors.inkMuted),
                      width: 1.4),
                ),
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: showAnswer && right == i + 1
                            ? AppColors.correct
                            : (given == i + 1 ? AppColors.wrong : AppColors.inkSoft))),
              ),
              Expanded(
                child: MathText(p.choices[i],
                    style: TextStyle(
                        fontSize: fs - 0.5,
                        fontWeight: (showAnswer && right == i + 1) || given == i + 1 ? FontWeight.w800 : FontWeight.w500,
                        color: showAnswer && right == i + 1
                            ? AppColors.correct
                            : (given == i + 1 ? AppColors.wrong : AppColors.inkSoft))),
              ),
              if (given == i + 1) const Pill('학생 답', color: AppColors.wrong, dense: true),
            ]),
          ),
      ],
      if (studentAnswer != null || showAnswer) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 4, children: [
          if (studentAnswer != null)
            Text('학생 답: ${p.isChoice ? circled(given ?? 0) : (studentAnswer!.isEmpty ? '-' : studentAnswer!)}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.wrong)),
          if (showAnswer)
            Text('정답: ${p.isChoice ? circled(right ?? 0) : p.answer}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.correct)),
        ]),
      ],
      if (showSolution && p.solution.trim().isNotEmpty) ...[
        const Divider(height: 28),
        const Text('해설', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        MathText(p.solution, style: TextStyle(fontSize: fs - 1, color: AppColors.ink, height: 1.7)),
      ],
    ]);
  }
}
