import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/records.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/answer_panel.dart' show expectedDisplay;
import '../widgets/common.dart';
import '../widgets/ink_preview.dart';
import '../widgets/math_text.dart';
import 'questions_screen.dart' show AskTeacherScreen;
import 'solve_screen.dart';
import '../widgets/problem_stem.dart';

class WrongNoteScreen extends StatefulWidget {
  const WrongNoteScreen({super.key});

  @override
  State<WrongNoteScreen> createState() => _WrongNoteScreenState();
}

class _WrongNoteScreenState extends State<WrongNoteScreen> {
  int _tab = 0; // 0 due, 1 all, 2 resolved, 3 bookmarks
  String? _subject;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = DateTime.now().millisecondsSinceEpoch;
    List<ProblemState> list;
    switch (_tab) {
      case 0:
        list = app.wrongNote.where((s) => s.isDue(now)).toList();
        break;
      case 1:
        list = app.wrongNote;
        break;
      case 2:
        list = app.resolvedWrong;
        break;
      default:
        list = app.bookmarks;
    }
    list = list.where((s) {
      if (_subject == null) return true;
      return app.problem(s.baseId)?.subjectId == _subject;
    }).toList();
    final due = app.wrongNote.where((s) => s.isDue(now)).toList();
    // only the courses the student has actually solved problems in
    final solvedIds = {for (final a in app.attempts) a.subjectId};
    final solvedCourses = [
      for (final s in app.bank.subjects)
        if (solvedIds.contains(s.id)) s
    ];

    final counts = {
      0: due.length,
      1: app.wrongNote.length,
      2: app.resolvedWrong.length,
      3: app.bookmarks.length,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('오답노트', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1.0)),
              SizedBox(height: 4),
              Text('틀린 문제는 여기 모여요. 1일, 3일, 7일 뒤에 다시 맞히면 졸업해요.',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 15, fontWeight: FontWeight.w500)),
            ]),
          ),
          if (due.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size(0, 52)),
              onPressed: () => SolveScreen.open(
                context,
                title: '오답 복습',
                mode: 'review',
                problems: [
                  for (final s in due)
                    if (app.problem(s.baseId) case final Problem p) app.hasVariant(p) ? app.makeVariant(p) : p,
                ],
              ),
              icon: const Icon(Icons.replay_rounded),
              label: Text('복습 시작 (${due.length})'),
            ),
        ]),
        const SizedBox(height: 22),
        // 상태: 한 줄짜리 구분 버튼 (개수는 고정폭 숫자)
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
              key: const Key('wn-tabs'),
              showSelectedIcon: false,
              segments: [
                for (final (i, label) in [(0, '오늘 복습'), (1, '전체 오답'), (2, '졸업한 문제'), (3, '북마크')])
                  ButtonSegment(
                    value: i,
                    label: Text.rich(TextSpan(children: [
                      TextSpan(text: label),
                      if (counts[i]! > 0)
                        TextSpan(
                            text: '  ${counts[i]}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: AppColors.tabular)),
                    ])),
                  ),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
        ),
        // 과목: 조용한 칩 (선택하면 흑연 바탕)
        if (solvedCourses.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: const Text('모든 과목'),
              selected: _subject == null,
              selectedColor: AppColors.ink,
              labelStyle: TextStyle(
                  fontWeight: FontWeight.w700, color: _subject == null ? Colors.white : AppColors.inkSoft),
              onSelected: (_) => setState(() => _subject = null),
            ),
            for (final s in solvedCourses)
              ChoiceChip(
                key: Key('wn-subject-${s.id}'),
                avatar: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: Color(s.color), shape: BoxShape.circle),
                ),
                label: Text(s.name),
                selected: _subject == s.id,
                selectedColor: AppColors.ink,
                labelStyle: TextStyle(
                    fontWeight: FontWeight.w700, color: _subject == s.id ? Colors.white : AppColors.inkSoft),
                onSelected: (_) => setState(() => _subject = s.id),
              ),
          ]),
        ],
        const SizedBox(height: 24),
        if (list.isEmpty)
          EmptyState(
            icon: _tab == 3 ? Icons.bookmark_border_rounded : Icons.check_circle_outline_rounded,
            title: _tab == 0
                ? '지금 복습할 문제가 없어요'
                : _tab == 3
                    ? '북마크한 문제가 없어요'
                    : '여기는 비어 있어요',
            message: _tab == 0 ? '오늘 틀린 문제는 내일 이곳에 다시 나와요.' : null,
          )
        else
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 1100 ? 2 : 1;
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(spacing: 16, runSpacing: 16, children: [
              for (final s in list) SizedBox(width: w, child: _WrongCard(state: s)),
            ]);
          }),
      ],
    );
  }
}

class _WrongCard extends StatelessWidget {
  const _WrongCard({required this.state});
  final ProblemState state;

  String _when(int? at) {
    if (at == null) return '';
    final now = DateTime.now();
    final d = DateTime.fromMillisecondsSinceEpoch(at);
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days <= 0) return '오늘 복습';
    if (days == 1) return '내일 복습';
    return '$days일 후 복습';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.problem(state.baseId);
    if (p == null) return const SizedBox();
    final color = Color(app.bank.subject(p.subjectId)?.color ?? 0xFF2F6BFF);
    final wrongAns = state.lastWrongAnswer;
    final dueNow = state.isDue(DateTime.now().millisecondsSinceEpoch);
    final hasInk = state.lastWrongAttemptId != null &&
        app.attempts.any((a) => a.id == state.lastWrongAttemptId && a.hasInk);
    final right = p.isEssay
        ? expectedDisplay(p)
        : p.isChoice
            ? circled(int.tryParse(p.answer) ?? 0)
            : '${p.answer} ${p.answerUnit ?? ''}'.trim();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 머리: 과목 색 점 + 과목, 유형 · 오른쪽에 복습 단계
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(p.subjectName,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(p.topic.isEmpty ? p.unit : p.topic,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.3)),
            ),
            const SizedBox(width: 12),
            if (state.inWrongNote) ...[
              _StageDots(stage: state.reviewStage),
              const SizedBox(width: 10),
              Text(_when(state.nextReviewAt),
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: dueNow ? AppColors.accent : AppColors.inkMuted)),
            ] else if (state.resolvedAt != null)
              const Pill('졸업', color: AppColors.correct, icon: Icons.school_rounded, dense: true),
          ]),
          const SizedBox(height: 14),
          ProblemStem(p, maxLines: 4, style: const TextStyle(fontSize: 15, color: AppColors.ink, height: 1.6)),
          const SizedBox(height: 14),
          // 내 답 / 정답 — 종이색 한 칸에 나란히
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (wrongAns != null)
                    _kv('내 답', p.isChoice ? circled(int.tryParse(wrongAns) ?? 0) : wrongAns, AppColors.wrong),
                  _kv(p.isEssay ? '모범' : '정답', right, AppColors.correct),
                  const SizedBox(height: 2),
                  Text('${state.attempts}번 풀어서 ${state.wrong}번 틀렸어요',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600, fontFeatures: AppColors.tabular)),
                ]),
              ),
              if (hasInk) ...[
                const SizedBox(width: 12),
                SizedBox(width: 170, child: InkThumbnail(attemptId: state.lastWrongAttemptId!, height: 96)),
              ],
            ]),
          ),
          if (state.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(color: AppColors.highlightSoft, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.sticky_note_2_outlined, size: 17, color: AppColors.inkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(state.note, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          // 동작: 주 동작 하나(다시 풀기) + 글자 단추
          Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 18)),
              onPressed: () => SolveScreen.open(context, title: '다시 풀기', mode: 'review', problems: [p]),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('다시 풀기'),
            ),
            const SizedBox(width: 4),
            if (p.hasTemplate)
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => SolveScreen.open(context,
                    title: '변형으로 복습', mode: 'variant', problems: app.variantsFor(p, 3)),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('변형 3문제'),
              ),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _showSolution(context, p),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('해설'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _editNote(context, app, state),
              icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
              label: const Text('메모'),
            ),
            if (app.signedIn && !app.isTeacher)
              TextButton.icon(
                key: Key('wn-ask-${p.id}'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => AskTeacherScreen.open(context, problem: p),
                icon: const Icon(Icons.contact_support_outlined, size: 18),
                label: const Text('선생님께 질문'),
              ),
            if (state.inWrongNote)
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: AppColors.correct),
                onPressed: () => app.markResolved(state.baseId),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('이해했어요'),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          SizedBox(
              width: 44,
              child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600))),
          Flexible(
            child: Text(v,
                style: TextStyle(fontSize: 16, color: c, fontWeight: FontWeight.w800, fontFeatures: AppColors.tabular)),
          ),
        ]),
      );

  void _editNote(BuildContext context, AppState app, ProblemState s) {
    final ctl = TextEditingController(text: s.note);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오답 메모'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: ctl,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(hintText: '왜 틀렸는지, 다음엔 무엇을 조심할지 적어 두세요'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              app.setNote(s.baseId, ctl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _showSolution(BuildContext context, Problem p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('해설'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: ProblemSolution(p,
                style: TextStyle(
                    fontSize: 16, color: AppColors.ink, height: 1.7, fontFamily: p.texStyle ? AppTheme.texSerif : null)),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))],
      ),
    );
  }
}

class _StageDots extends StatelessWidget {
  const _StageDots({required this.stage});
  final int stage;

  @override
  Widget build(BuildContext context) {
    const total = 3;
    return Tooltip(
      message: '복습 단계 $stage / $total',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < total; i++)
          Container(
            width: 14,
            height: 4,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
            decoration: BoxDecoration(
              color: i < stage ? AppColors.correct : AppColors.lineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ]),
    );
  }
}
