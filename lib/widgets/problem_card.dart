import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/problem.dart';
import 'common.dart';
import 'math_text.dart';

/// The printed part of the worksheet: rendered at page scale (width 1000) under the ink.
class ProblemSheet extends StatelessWidget {
  const ProblemSheet({
    super.key,
    required this.problem,
    required this.number,
    required this.color,
    this.selectedChoice,
    this.revealAnswer = false,
  });

  final Problem problem;
  final int number;
  final Color color;
  final int? selectedChoice;
  final bool revealAnswer;

  @override
  Widget build(BuildContext context) {
    final p = problem;
    final correctChoice = int.tryParse(p.answer);
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: AppTheme.font, fontSize: 25, height: 1.65, color: AppColors.ink),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 48, 56, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                  child: Text('$number',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, height: 1.3)),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    [p.subjectName, p.unit, if (p.topic.isNotEmpty) p.topic].join('  ·  '),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color, height: 1.2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 14),
                DifficultyDots(p.difficulty, color: color, size: 9),
                if (p.isVariant) ...[
                  const SizedBox(width: 12),
                  const Pill('변형', color: AppColors.accent, icon: Icons.auto_awesome_rounded),
                ],
              ],
            ),
            const SizedBox(height: 22),
            MathText(p.stem, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w500)),
            if (p.boxItems.isNotEmpty) ...[
              const SizedBox(height: 22),
              _BoxItems(items: p.boxItems),
            ],
            if (p.isChoice && p.choices.isNotEmpty) ...[
              const SizedBox(height: 24),
              _Choices(
                choices: p.choices,
                selected: selectedChoice,
                correct: revealAnswer ? correctChoice : null,
                color: color,
              ),
            ],
            if (!p.isChoice && p.answerUnit != null && p.answerUnit!.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('답의 단위: ${p.answerUnit}',
                  style: const TextStyle(fontSize: 18, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 30),
            Row(children: [
              Expanded(child: Container(height: 1.5, color: AppColors.line)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('풀이', style: TextStyle(fontSize: 16, color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
              ),
              Expanded(child: Container(height: 1.5, color: AppColors.line)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _BoxItems extends StatelessWidget {
  const _BoxItems({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(26, 28, 26, 18),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lineStrong, width: 1.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MathText(it, style: const TextStyle(fontSize: 23)),
                ),
            ],
          ),
        ),
        Positioned(
          top: -14,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              color: const Color(0xFFFFFDF8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: const Text('〈보기〉', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({required this.choices, required this.selected, required this.correct, required this.color});
  final List<String> choices;
  final int? selected;
  final int? correct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final longest = choices.fold<int>(0, (m, c) => MathText.plain(c).length > m ? MathText.plain(c).length : m);
    final perRow = longest <= 8 ? 5 : (longest <= 22 ? 2 : 1);
    final rows = <List<int>>[];
    for (var i = 0; i < choices.length; i += perRow) {
      rows.add([for (var j = i; j < i + perRow && j < choices.length; j++) j]);
    }
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in row)
                  Expanded(
                    child: _ChoiceItem(
                      n: i + 1,
                      text: choices[i],
                      selected: selected == i + 1,
                      correct: correct == null ? null : correct == i + 1,
                      color: color,
                    ),
                  ),
                for (var k = row.length; k < perRow; k++) const Expanded(child: SizedBox()),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChoiceItem extends StatelessWidget {
  const _ChoiceItem({required this.n, required this.text, required this.selected, required this.correct, required this.color});
  final int n;
  final String text;
  final bool selected;
  final bool? correct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final mark = correct == true ? AppColors.correct : (selected ? color : null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(right: 8, top: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: mark?.withValues(alpha: 0.14),
            border: Border.all(color: mark ?? AppColors.lineStrong, width: mark == null ? 1.4 : 2.2),
          ),
          child: Text('$n',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: mark ?? AppColors.inkSoft, height: 1.0)),
        ),
        Expanded(child: MathText(text, style: const TextStyle(fontSize: 23))),
      ],
    );
  }
}
