import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/workbook_card.dart';
import 'exam_setup.dart';
import 'solve_screen.dart';
import 'workbook_store_screen.dart';

/// 홈: 오늘의 오답 변형 세트 · 순공 · 내 교재 · 할 일 · 약점 유형.
/// 계산지(모눈) 위의 흑연 글씨 — 강조는 오늘 세트의 형광펜 진도 막대 하나뿐.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '늦은 밤까지 수고 많아요';
    if (h < 12) return '좋은 아침이에요';
    if (h < 18) return '오늘도 한 문제씩';
    return '오늘 하루 마무리해요';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final books = app.myWorkbooks;
    final l = app.learner;
    final dday = app.dDay;

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      // 폰 세로: 인사말 아래로 배지를 내려 접는다 (한 줄에 다 넣으면 글자가 잘린다)
      final narrow = box.maxWidth < 620;
      final gutter = narrow ? 16.0 : 32.0;
      final hello = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_greeting()}, ${app.profile.name}님',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: narrow ? 23 : 28, fontWeight: FontWeight.w800, letterSpacing: -1.0, height: 1.2)),
        const SizedBox(height: 6),
        Text(
          books.isEmpty ? '${l.gradeLabel} · 아직 담은 교재가 없어요' : '${l.gradeLabel} · 내 교재 ${books.length}권',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: narrow ? 14 : 15, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
        ),
      ]);
      final badges = <Widget>[
        if (app.unreadAnswers > 0)
          InkWell(
            key: const Key('home-answers'),
            borderRadius: BorderRadius.circular(20),
            onTap: () => onNavigate(4),
            child: Pill('선생님 답변 ${app.unreadAnswers}개', icon: Icons.mark_chat_unread_rounded, color: AppColors.correct),
          ),
        if (app.streak > 0)
          Pill('${app.streak}일째 공부 중', icon: Icons.local_fire_department_rounded, color: AppColors.inkSoft,
              background: AppColors.surface),
        if (l.examDate > 0) _DdayBadge(name: l.examName, dday: dday, onTap: () => onNavigate(3)),
      ];
      return ListView(
        padding: EdgeInsets.fromLTRB(gutter, narrow ? 18 : 28, gutter, 48),
        children: [
          // ---------- header
          if (narrow) ...[
            hello,
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: badges),
            ],
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: hello),
              for (final b in badges) ...[const SizedBox(width: 10), b],
            ]),
          SizedBox(height: narrow ? 20 : 26),

          // ---------- hero: 오늘 세트 + 오늘 한 것
          _flex(
            wide,
            [
              (13, _DailySetCard(narrow: narrow)),
              (7, _TodayPanel(fill: wide, onOpenPlanner: () => onNavigate(3), onOpenWrong: () => onNavigate(2))),
            ],
          ),
          const SizedBox(height: 40),

          // ---------- workbooks (내 교재)
          SectionHeader('내 교재',
              subtitle: books.isEmpty ? '교재를 담으면 여기에서 바로 풀 수 있어요' : '순서대로 풀며 진도를 채워요',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton.icon(
                  key: const Key('home-add-books'),
                  onPressed: () => WorkbookStoreScreen.open(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('교재 담기'),
                ),
                if (books.isNotEmpty) TextButton(onPressed: () => onNavigate(1), child: const Text('전체 보기')),
              ])),
          SizedBox(
            height: 178,
            child: books.isEmpty
                ? Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => WorkbookStoreScreen.open(context),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.lineStrong),
                        ),
                        child: const Center(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.collections_bookmark_outlined, color: AppColors.inkSoft, size: 28),
                            SizedBox(width: 12),
                            Flexible(
                              child: Text('우리 학교 수업 교재를 골라 담아 보세요',
                                  style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w700, fontSize: 15.5)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: books.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, i) => SizedBox(width: 290, child: WorkbookCard(workbook: books[i])),
                  ),
          ),
          const SizedBox(height: 40),

          // ---------- endless (내 교재에서만) — kEndlessEnabled 가 false 면 시험처럼 풀기만 남는다
          if (books.isNotEmpty) ...[
            SectionHeader(kEndlessEnabled ? '무한 풀기' : '실전 연습',
                subtitle: kEndlessEnabled ? '내 교재 문제로 · 맞히면 더 어렵게, 틀리면 쉽게' : '내 교재 문제로 시간을 재며 시험처럼 풀어요'),
            Wrap(spacing: 12, runSpacing: 12, children: [
              if (kEndlessEnabled)
                _EndlessChip(
                  key: const Key('endless-all'),
                  label: '내 교재 전체',
                  icon: Icons.all_inclusive_rounded,
                  color: AppColors.ink,
                  onTap: () => SolveScreen.endless(context, title: '내 교재 전체'),
                ),
              if (kEndlessEnabled)
                for (final w in books.take(6))
                  _EndlessChip(
                    key: Key('endless-wb-${w.id}'),
                    label: w.title,
                    icon: app.bank.subject(w.course) == null ? Icons.menu_book_rounded : courseIcon(app.bank.subject(w.course)!),
                    color: Color(app.bank.subject(w.course)?.color ?? 0xFF515A64),
                    onTap: () => SolveScreen.endless(context, workbookId: w.id, title: w.title),
                  ),
              _EndlessChip(
                label: '시험처럼 풀기',
                icon: Icons.timer_outlined,
                color: AppColors.ink,
                outlined: true,
                onTap: () => showExamSetup(context),
              ),
            ]),
            const SizedBox(height: 40),
          ],

          // ---------- todo + weak topics
          _flex(wide, [
            (1, _TodoPreview(onOpen: () => onNavigate(3))),
            (1, const _WeakTopics()),
          ], cross: CrossAxisAlignment.start),
        ],
      );
    });
  }

  Widget _flex(bool wide, List<(int, Widget)> items, {CrossAxisAlignment cross = CrossAxisAlignment.stretch}) {
    if (!wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: 16), items[i].$2],
      ]);
    }
    final row = Row(crossAxisAlignment: cross, children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 18),
        Expanded(flex: items[i].$1, child: items[i].$2),
      ],
    ]);
    return cross == CrossAxisAlignment.stretch ? IntrinsicHeight(child: row) : row;
  }
}

IconData courseIcon(Subject s) {
  switch (s.id) {
    case 'phy1':
      return Icons.bolt_rounded;
    case 'phy2':
      return Icons.blur_circular_rounded;
    case 'earth1':
      return Icons.public_rounded;
  }
  switch (s.group) {
    case 'kor':
      return Icons.auto_stories_rounded;
    case 'math':
      return Icons.functions_rounded;
    case 'eng':
      return Icons.translate_rounded;
    case 'soc':
      return Icons.account_balance_rounded;
    case 'sci':
      return Icons.science_rounded;
  }
  return Icons.edit_note_rounded;
}

/// Kept for screens that only know the course id.
IconData subjectIcon(String id) => switch (id) {
      'phy1' => Icons.bolt_rounded,
      'phy2' => Icons.blur_circular_rounded,
      'earth1' => Icons.public_rounded,
      'math1' || 'math2' || 'prob' => Icons.functions_rounded,
      'integ' || 'mid-sci' => Icons.science_rounded,
      'kor-read' => Icons.auto_stories_rounded,
      'eng' => Icons.translate_rounded,
      'soc-int' => Icons.account_balance_rounded,
      _ => Icons.edit_note_rounded,
    };

class _DdayBadge extends StatelessWidget {
  const _DdayBadge({required this.name, required this.dday, required this.onTap});
  final String name;
  final int dday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Text(dday > 0 ? 'D-$dday' : (dday == 0 ? 'D-DAY' : 'D+${-dday}'),
                style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.1,
                    fontFeatures: AppColors.tabular)),
          ]),
        ),
      ),
    );
  }
}

/// 계산지 모눈 (아주 옅게) — 오늘 세트 카드의 바탕.
class _GridPaper extends CustomPainter {
  const _GridPaper();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 22.0;
    final thin = Paint()
      ..color = AppColors.grid
      ..strokeWidth = 1;
    final bold = Paint()
      ..color = AppColors.grid
      ..strokeWidth = 1.6;
    var k = 0;
    for (var x = step; x < size.width; x += step, k++) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), k % 5 == 4 ? bold : thin);
    }
    k = 0;
    for (var y = step; y < size.height; y += step, k++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), k % 5 == 4 ? bold : thin);
    }
  }

  @override
  bool shouldRepaint(_GridPaper old) => false;
}

/// 형광펜으로 그은 진도 막대 — 끝이 살짝 비스듬한 굵은 획.
class _MarkerBar extends StatelessWidget {
  const _MarkerBar({required this.value, required this.complete});
  final double value;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: CustomPaint(
        size: Size.infinite,
        painter: _MarkerPainter(value.clamp(0.0, 1.0), complete ? AppColors.correct.withValues(alpha: 0.35) : AppColors.highlight),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.value, this.color);
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    // 빈 칸: 옅은 형광펜 자리 (0 이어도 어디까지 칠할지 보이게)
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, h), const Radius.circular(3)),
        Paint()..color = AppColors.highlightSoft);
    if (value <= 0) return;
    final w = math.max(h, size.width * value);
    const slant = 5.0;
    final path = Path()
      ..moveTo(slant, 0)
      ..lineTo(w, 0)
      ..lineTo(w - slant, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => old.value != value || old.color != color;
}

class _DailySetCard extends StatelessWidget {
  const _DailySetCard({required this.narrow});

  /// 폰 세로 — 진도 숫자를 위로 올리고 글을 아래로 (IntrinsicHeight 안이라 LayoutBuilder 를 못 쓴다).
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final set = app.dailySet;
    final total = set.problemIds.length;
    final done = set.doneCount;
    final variants = set.count('twin') + set.count('variant') + set.count('similar');
    final review = set.count('review');
    final weak = set.count('weak');
    final fresh = set.count('new');
    final remaining = [
      for (final p in app.dailyProblems)
        if (!set.done.contains(p.id)) p
    ];
    final hasWrong = variants + review > 0;
    final noBooks = app.myWorkbooks.isEmpty;
    final d = DateTime.now();

    Widget part(String label, int n, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 5),
          Text('$n',
              style: const TextStyle(
                  color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 14, fontFeatures: AppColors.tabular)),
        ]);

    final progress = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(set.complete ? '$total' : '$done',
            style: TextStyle(
                fontSize: narrow ? 40 : 52,
                fontWeight: FontWeight.w800,
                letterSpacing: -2,
                height: 1.0,
                color: AppColors.ink,
                fontFeatures: AppColors.tabular)),
        const SizedBox(width: 6),
        Text('/ $total 문제',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.inkSoft, fontFeatures: AppColors.tabular)),
        if (set.complete) ...[
          const SizedBox(width: 10),
          const Icon(Icons.check_circle_rounded, color: AppColors.correct, size: 24),
        ],
      ]),
      const SizedBox(height: 12),
      _MarkerBar(value: total == 0 ? 0 : done / total, complete: set.complete),
      const SizedBox(height: 8),
      Text(
          set.complete
              ? '오늘 세트를 다 풀었어요'
              : total == 0
                  ? '오늘 풀 문제가 아직 없어요'
                  : '${remaining.length}문제 남았어요',
          style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
    ]);

    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('${d.month}월 ${d.day}일',
          style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 4),
      Text('오늘의 오답 변형 세트',
          style: TextStyle(
              color: AppColors.ink, fontSize: narrow ? 21 : 25, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
      const SizedBox(height: 8),
      Text(
        total == 0 && noBooks
            ? '교재를 담으면, 교재 진도와 틀린 문제의 변형으로 매일 세트를 만들어 드려요.'
            : total == 0
                ? '내 교재를 다 풀었어요. 새 교재를 담아 이어 가세요.'
                : hasWrong
                    ? '틀린 문제를 쌍둥이 문항과 변형으로 다시 풀고, 교재 진도를 채웠어요.'
                    : '아직 오답이 없어서 교재의 다음 문제로 채웠어요. 틀리면 내일 세트에 변형이 나와요.',
        style: const TextStyle(color: AppColors.inkSoft, fontSize: 15, height: 1.55),
      ),
      if (variants + review + weak + fresh > 0) ...[
        const SizedBox(height: 14),
        Wrap(spacing: 18, runSpacing: 8, children: [
          if (variants > 0) part('오답 변형', variants, AppColors.accent),
          if (review > 0) part('복습', review, AppColors.review),
          if (weak > 0) part('약점 유형', weak, AppColors.wrong),
          if (fresh > 0) part('오늘의 진도', fresh, AppColors.inkMuted),
        ]),
      ],
      const SizedBox(height: 20),
      if (total == 0)
        FilledButton.icon(
          key: const Key('daily-pick-books'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size(0, 52)),
          onPressed: () => WorkbookStoreScreen.open(context),
          icon: const Icon(Icons.collections_bookmark_rounded),
          label: Text(noBooks ? '교재 고르러 가기' : '교재 더 담기'),
        )
      else
        FilledButton.icon(
          key: const Key('daily-start'),
          style: FilledButton.styleFrom(
            backgroundColor: set.complete ? AppColors.ink : AppColors.accent,
            minimumSize: const Size(0, 54),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          onPressed: () => SolveScreen.open(context,
              title: '오늘의 오답 변형 세트',
              problems: set.complete || remaining.isEmpty ? app.dailyProblems : remaining,
              mode: 'daily'),
          icon: Icon(set.complete ? Icons.replay_rounded : Icons.edit_rounded, size: 20),
          label: Text(set.complete
              ? '한 번 더 풀기'
              : done == 0
                  ? '오늘 세트 풀기'
                  : '이어서 풀기'),
        ),
    ]);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
        ),
        child: CustomPaint(
          painter: const _GridPaper(),
          child: Padding(
            padding: EdgeInsets.all(narrow ? 20 : 30),
            child: narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    progress,
                    const SizedBox(height: 22),
                    body,
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(flex: 3, child: body),
                    const SizedBox(width: 32),
                    Expanded(flex: 2, child: progress),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// 오늘 한 것 — 순공 타이머 · 오늘 푼 문제 · 오답 복습을 한 판에.
class _TodayPanel extends StatefulWidget {
  const _TodayPanel({required this.fill, required this.onOpenPlanner, required this.onOpenWrong});

  /// 넓은 화면: 옆 카드 높이에 맞춰 늘인다 (IntrinsicHeight 안). 좁으면 내용 높이만.
  final bool fill;
  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenWrong;

  @override
  State<_TodayPanel> createState() => _TodayPanelState();
}

class _TodayPanelState extends State<_TodayPanel> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AppScope.read(context).studying) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Widget _stat({required String label, required String value, required String sub, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.1, fontFeatures: AppColors.tabular)),
          const SizedBox(height: 2),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ms = app.todayStudyMs;
    final solve = app.solveMsOn(dayKey(DateTime.now()));
    final on = app.studying;
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        // 순공 타이머
        InkWell(
          onTap: widget.onOpenPlanner,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (on) ...[
                      Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AppColors.wrong, shape: BoxShape.circle)),
                      const SizedBox(width: 7),
                    ],
                    Text(on ? '공부 중' : '오늘 순공 시간',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? AppColors.ink : AppColors.inkSoft)),
                  ]),
                  const SizedBox(height: 6),
                  Text(fmtStudy(ms),
                      style: const TextStyle(
                          fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.1, fontFeatures: AppColors.tabular)),
                  const SizedBox(height: 2),
                  Text('+ 문제 푼 시간 ${fmtDuration(solve)}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('study-toggle'),
                onPressed: on ? app.stopStudy : app.startStudy,
                style: FilledButton.styleFrom(
                  backgroundColor: on ? AppColors.wrong : AppColors.ink,
                  minimumSize: const Size(0, 50),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                icon: Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(on ? '멈추기' : '시작'),
              ),
            ]),
          ),
        ),
        const Divider(height: 1),
        _fillOrFit(
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _stat(
                label: '오늘 푼 문제',
                value: '${app.todayCount}',
                sub: app.todayCount == 0 ? '첫 문제를 풀어 볼까요' : '정답 ${app.todayCorrect}개',
                onTap: widget.onOpenPlanner,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _stat(
                label: '오답노트',
                value: '${app.wrongNote.length}',
                sub: app.dueCount > 0 ? '지금 복습할 것 ${app.dueCount}개' : '복습할 문제 없음',
                onTap: widget.onOpenWrong,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _fillOrFit(Widget row) => widget.fill ? Expanded(child: row) : IntrinsicHeight(child: row);
}

/// 1:02:03 / 12:03
String fmtStudy(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

class _EndlessChip extends StatelessWidget {
  const _EndlessChip(
      {super.key, required this.label, required this.icon, required this.color, required this.onTap, this.outlined = false});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: outlined ? AppColors.paper : color, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 19, color: outlined ? AppColors.ink : Colors.white),
            ),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          ]),
        ),
      ),
    );
  }
}

class _TodoPreview extends StatelessWidget {
  const _TodoPreview({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final todos = app.todayTodos;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('오늘 할 일', trailing: TextButton(onPressed: onOpen, child: const Text('학습관리'))),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            _autoRow(Icons.auto_awesome_rounded, '오늘의 오답 변형 세트', app.dailySet.complete,
                '${app.dailySet.doneCount}/${app.dailySet.problemIds.length}'),
            if (app.dueCount > 0) _autoRow(Icons.assignment_late_rounded, '오답 복습 ${app.dueCount}문제', false, null),
            for (final t in todos.take(4))
              CheckboxListTile(
                dense: true,
                value: t.done,
                onChanged: (_) => app.toggleTodo(t.id),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(t.text,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: t.done ? TextDecoration.lineThrough : null,
                        color: t.done ? AppColors.inkMuted : AppColors.ink)),
              ),
            if (todos.isEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.add_rounded, color: AppColors.inkMuted),
                title: const Text('할 일을 추가해 보세요', style: TextStyle(color: AppColors.inkMuted)),
                onTap: onOpen,
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _autoRow(IconData icon, String text, bool done, String? trailing) => ListTile(
        dense: true,
        leading: Icon(done ? Icons.check_circle_rounded : icon, color: done ? AppColors.correct : AppColors.accent),
        title: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: trailing == null ? null : Text(trailing, style: const TextStyle(fontWeight: FontWeight.w800)),
      );
}

class _WeakTopics extends StatelessWidget {
  const _WeakTopics();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final weak = app.weakTopics;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('보완이 필요한 유형'),
      if (weak.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Text('문제를 더 풀면 약한 유형을 찾아 드려요.', style: TextStyle(color: AppColors.inkMuted)),
          ),
        )
      else
        Card(
          child: Column(children: [
            for (final (topic, acc, _) in weak.take(4))
              ListTile(
                title: Text(topic, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AccuracyBar(value: acc, color: accuracyColor(acc)),
                ),
                trailing: kEndlessEnabled
                    ? TextButton.icon(
                        onPressed: () => SolveScreen.endless(context, topic: topic, title: topic),
                        icon: const Icon(Icons.all_inclusive_rounded, size: 18),
                        label: Text('${pct(acc)} · 집중 풀기'),
                      )
                    : Text(pct(acc), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
              ),
          ]),
        ),
    ]);
  }
}
