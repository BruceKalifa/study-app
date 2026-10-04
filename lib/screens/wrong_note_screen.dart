import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/records.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/ink_preview.dart';
import '../widgets/math_text.dart';
import 'questions_screen.dart' show AskTeacherScreen;
import 'solve_screen.dart';

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('오답노트', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
              SizedBox(height: 4),
              Text('틀린 문제는 자동으로 모이고, 1일 → 3일 → 7일 간격으로 다시 풀면 졸업해요.',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 15)),
            ]),
          ),
          if (due.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
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
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final (i, label) in [(0, '오늘 복습'), (1, '전체 오답'), (2, '졸업한 문제'), (3, '북마크')])
            ChoiceChip(label: Text(label), selected: _tab == i, onSelected: (_) => setState(() => _tab = i)),
          if (solvedCourses.isNotEmpty) ...[
            Container(width: 1, height: 24, color: AppColors.line, margin: const EdgeInsets.symmetric(horizontal: 6)),
            ChoiceChip(
                label: const Text('전체 과목'), selected: _subject == null, onSelected: (_) => setState(() => _subject = null)),
          ],
          for (final s in solvedCourses)
            ChoiceChip(
              key: Key('wn-subject-${s.id}'),
              label: Text(s.name),
              selected: _subject == s.id,
              selectedColor: Color(s.color),
              onSelected: (_) => setState(() => _subject = s.id),
            ),
        ]),
        const SizedBox(height: 20),
        if (list.isEmpty)
          EmptyState(
            icon: _tab == 3 ? Icons.bookmark_border_rounded : Icons.celebration_rounded,
            title: _tab == 0
                ? '지금 복습할 문제가 없어요'
                : _tab == 3
                    ? '북마크한 문제가 없어요'
                    : '여기는 비어 있어요',
            message: _tab == 0 ? '틀린 문제는 다음 날 이곳에 다시 나타나요.' : null,
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 5, color: color),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Pill(p.subjectName, color: color, dense: true),
              const SizedBox(width: 6),
              Flexible(
                child: Text(p.topic.isEmpty ? p.unit : p.topic,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              ),
              const Spacer(),
              if (state.inWrongNote) ...[
                _StageDots(stage: state.reviewStage),
                const SizedBox(width: 8),
                Pill(_when(state.nextReviewAt),
                    color: state.isDue(DateTime.now().millisecondsSinceEpoch) ? AppColors.accent : AppColors.inkSoft,
                    dense: true),
              ] else if (state.resolvedAt != null)
                const Pill('졸업', color: AppColors.correct, icon: Icons.school_rounded, dense: true),
            ]),
            const SizedBox(height: 12),
            MathText(p.stem, maxLines: 4, style: const TextStyle(fontSize: 15, color: AppColors.ink, height: 1.6)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (wrongAns != null)
                    _kv('내 답', p.isChoice ? circled(int.tryParse(wrongAns) ?? 0) : wrongAns, AppColors.wrong),
                  _kv('정답', p.isChoice ? circled(int.tryParse(p.answer) ?? 0) : '${p.answer} ${p.answerUnit ?? ''}',
                      AppColors.correct),
                  _kv('기록', '${state.attempts}번 풀이 · ${state.wrong}번 틀림', AppColors.inkSoft),
                ]),
              ),
              if (state.lastWrongAttemptId != null &&
                  app.attempts.any((a) => a.id == state.lastWrongAttemptId && a.hasInk))
                SizedBox(width: 170, child: InkThumbnail(attemptId: state.lastWrongAttemptId!, height: 96)),
            ]),
            if (state.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.reviewSoft, borderRadius: BorderRadius.circular(12)),
                child: Text('📝 ${state.note}', style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: color),
                onPressed: () => SolveScreen.open(context, title: '다시 풀기', mode: 'review', problems: [p]),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('다시 풀기'),
              ),
              if (p.hasTemplate)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => SolveScreen.open(context,
                      title: '변형으로 복습', mode: 'variant', problems: app.variantsFor(p, 3)),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('변형 3문제'),
                ),
              TextButton.icon(
                onPressed: () => _editNote(context, app, state),
                icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                label: const Text('메모'),
              ),
              TextButton.icon(
                onPressed: () => _showSolution(context, p),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('해설'),
              ),
              if (app.signedIn && !app.isTeacher)
                TextButton.icon(
                  key: Key('wn-ask-${p.id}'),
                  onPressed: () => AskTeacherScreen.open(context, problem: p),
                  icon: const Icon(Icons.contact_support_outlined, size: 18),
                  label: const Text('선생님께 질문'),
                ),
              if (state.inWrongNote)
                TextButton.icon(
                  onPressed: () => app.markResolved(state.baseId),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('이해했어요'),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _kv(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 40, child: Text(k, style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600))),
          Flexible(child: Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w800))),
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
            child: MathText(p.solution, style: const TextStyle(fontSize: 16, color: AppColors.ink, height: 1.7)),
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
            width: 16,
            height: 6,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i < stage ? AppColors.correct : AppColors.line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]),
    );
  }
}
