import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import 'dashboard_screen.dart' show fmtStudy;
import 'history_screen.dart';
import 'stats_screen.dart';

/// 학습관리 — 세 칸:
/// 플래너 (시험 D-day · 순공 타이머 · 오늘 할 일 · 이번 주) / 분석 (통계) / 풀이 기록.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key, this.initialView = 0});

  /// 0 플래너 · 1 분석 · 2 풀이 기록
  final int initialView;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

/// 학습관리 안에서 쓰는 글자 크기 (DESIGN.md 의 크기 단계).
const _sectionTitle = TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.ink);
const _meta = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted);

class _PlannerScreenState extends State<PlannerScreen> {
  Timer? _tick;
  final _todo = TextEditingController();
  late int _view = widget.initialView;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AppScope.read(context).studying) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _todo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
      child: Wrap(
        spacing: 20,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          const Text('학습관리', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1.0)),
          SegmentedButton<int>(
            key: const Key('planner-view'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('플래너'), icon: Icon(Icons.event_note_rounded, size: 18)),
              ButtonSegment(value: 1, label: Text('분석'), icon: Icon(Icons.insights_rounded, size: 18)),
              ButtonSegment(value: 2, label: Text('풀이 기록'), icon: Icon(Icons.history_rounded, size: 18)),
            ],
            selected: {_view},
            onSelectionChanged: (v) => setState(() => _view = v.first),
          ),
        ],
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Expanded(
        child: switch (_view) {
          1 => const StatsScreen(embedded: true),
          2 => const HistoryScreen(embedded: true),
          _ => _planner(context),
        },
      ),
    ]);
  }

  Widget _planner(BuildContext context) {
    final app = AppScope.of(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      final gutter = box.maxWidth < 620 ? 16.0 : 32.0;
      Widget pair(Widget a, Widget b, {int fa = 1, int fb = 1}) => wide
          ? IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: fa, child: a),
                const SizedBox(width: 16),
                Expanded(flex: fb, child: b),
              ]),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 16), b]);
      return ListView(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 40),
        children: [
          pair(_ddayCard(app), _timerCard(app), fa: 2, fb: 3),
          const SizedBox(height: 16),
          pair(_todoCard(app), _weekCard(app), fa: 1, fb: 1),
        ],
      );
    });
  }

  // ---------------------------------------------------------------- D-day
  /// 평평한 흑연 판 — 남은 날만 크게, 나머지는 조용하게.
  Widget _ddayCard(AppState app) {
    final l = app.learner;
    final d = app.dDay;
    final date = l.examDate == 0 ? null : DateTime.fromMillisecondsSinceEpoch(l.examDate);
    final faint = Colors.white.withValues(alpha: 0.62);
    return Material(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editDday(app),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 18, 14, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(date == null ? '다음 시험' : l.examName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                key: const Key('dday-edit'),
                tooltip: '시험 바꾸기',
                onPressed: () => _editDday(app),
                icon: Icon(Icons.edit_calendar_rounded, color: faint, size: 22),
              ),
            ]),
            const SizedBox(height: 4),
            if (date == null) ...[
              const Text('시험 날짜 정하기',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1.0)),
              const SizedBox(height: 8),
              Text('중간·기말고사, 인적성, 편입시험 날짜를 넣으면 남은 날을 세어 드려요',
                  style: TextStyle(color: faint, fontSize: 14, fontWeight: FontWeight.w600, height: 1.5)),
            ] else ...[
              Text(d > 0 ? 'D-$d' : (d == 0 ? 'D-DAY' : 'D+${-d}'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2,
                      height: 1.05,
                      fontFeatures: AppColors.tabular)),
              const SizedBox(height: 6),
              Text('${date.year}년 ${date.month}월 ${date.day}일',
                  style: TextStyle(
                      color: faint, fontSize: 14.5, fontWeight: FontWeight.w600, fontFeatures: AppColors.tabular)),
              if (d > 0 && app.wrongNote.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
                const SizedBox(height: 14),
                Text(
                  '오답 ${app.wrongNote.length}개, 하루 ${math.max(1, (app.wrongNote.length / math.max(1, d)).ceil())}개씩 정리하면 시험 전에 끝나요',
                  style: TextStyle(color: faint, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.5),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _editDday(AppState app) async {
    final name = TextEditingController(text: app.learner.examName);
    var date = app.learner.examDate == 0
        ? DateTime.now().add(const Duration(days: 28))
        : DateTime.fromMillisecondsSinceEpoch(app.learner.examDate);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('목표 시험'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '시험 이름 (예: 공업수학 중간고사)')),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in ['중간고사', '기말고사', '인적성', 'NCS', '편입시험', '퀴즈'])
                ActionChip(label: Text(n), onPressed: () => set(() => name.text = n)),
            ]),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: date,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 800)),
                );
                if (picked != null) set(() => date = picked);
              },
              icon: const Icon(Icons.event_rounded),
              label: Text('${date.year}년 ${date.month}월 ${date.day}일'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
          ],
        ),
      ),
    );
    if (ok == true) {
      app.updateLearner((l) {
        l.examName = name.text.trim().isEmpty ? '시험' : name.text.trim();
        l.examDate = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
      });
    }
  }

  // ---------------------------------------------------------------- timer
  /// 큰 고정폭 시계 하나와 버튼 하나. 공부 중일 때만 파랑으로 표시.
  Widget _timerCard(AppState app) {
    final on = app.studying;
    final today = app.todayStudyMs;
    final solve = app.solveMsOn(dayKey(DateTime.now()));
    final running = on ? DateTime.now().millisecondsSinceEpoch - (app.studyStartedAt ?? 0) : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('오늘 순공 시간', style: _sectionTitle),
            const SizedBox(width: 10),
            if (on)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('공부 중 ${fmtStudy(running)}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                          fontFeatures: AppColors.tabular)),
                ]),
              ),
          ]),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(fmtStudy(today),
                    style: TextStyle(
                        fontSize: 60,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -2,
                        height: 1.0,
                        color: on ? AppColors.accent : AppColors.ink,
                        fontFeatures: AppColors.tabular)),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              key: const Key('planner-study-toggle'),
              style: FilledButton.styleFrom(
                backgroundColor: on ? AppColors.wrong : AppColors.accent,
                minimumSize: const Size(132, 52),
              ),
              onPressed: on ? app.stopStudy : app.startStudy,
              icon: Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 22),
              label: Text(on ? '멈추기' : '공부 시작'),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 18, runSpacing: 4, children: [
            Text('타이머 ${fmtDuration(today)}', style: _meta.copyWith(fontFeatures: AppColors.tabular)),
            Text('앱에서 문제 푼 시간 ${fmtDuration(solve)}', style: _meta.copyWith(fontFeatures: AppColors.tabular)),
          ]),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- todos
  Widget _todoCard(AppState app) {
    final todos = app.todayTodos;
    final set = app.dailySet;
    final done = todos.where((t) => t.done).length;
    void add() {
      app.addTodo(_todo.text);
      _todo.clear();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('오늘 할 일', style: _sectionTitle),
            const Spacer(),
            if (todos.isNotEmpty) Text('$done / ${todos.length}', style: _meta.copyWith(fontFeatures: AppColors.tabular)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('todo-input'),
                controller: _todo,
                decoration: const InputDecoration(hintText: '예) 공업수학 2장 연습문제, 인적성 수리 20문제', isDense: true),
                onSubmitted: (_) => add(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('todo-add'),
              tooltip: '할 일 추가',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: add,
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
          const SizedBox(height: 12),
          // 오늘의 세트: 앱이 정해 주는 할 일 — 형광펜 띠로 표시
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: set.complete ? AppColors.correctSoft : AppColors.highlightSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(set.complete ? Icons.check_circle_rounded : Icons.auto_awesome_rounded,
                  size: 20, color: set.complete ? AppColors.correct : AppColors.ink),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('오늘의 오답 변형 세트', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Text('${set.doneCount} / ${set.problemIds.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, fontFeatures: AppColors.tabular)),
            ]),
          ),
          const SizedBox(height: 4),
          for (final (i, t) in todos.indexed) ...[
            if (i > 0) const Divider(indent: 48),
            Dismissible(
              key: ValueKey(t.id),
              onDismissed: (_) => app.removeTodo(t.id),
              background: Container(color: AppColors.wrongSoft),
              child: CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 2),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.ink,
                checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                value: t.done,
                onChanged: (_) => app.toggleTodo(t.id),
                title: Text(t.text,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: t.done ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.inkMuted,
                        color: t.done ? AppColors.inkMuted : AppColors.ink)),
                secondary: IconButton(
                  tooltip: '지우기',
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.inkMuted),
                  onPressed: () => app.removeTodo(t.id),
                ),
              ),
            ),
          ],
          if (todos.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 12, 2, 6),
              child: Text('끝내지 못한 할 일은 다음 날로 넘어가요', style: _meta),
            ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- week
  Widget _weekCard(AppState app) {
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day).subtract(Duration(days: i))];
    final study = [for (final d in days) app.studyMsOn(dayKey(d))];
    final solve = [for (final d in days) app.solveMsOn(dayKey(d))];
    final solved = [for (final d in days) app.daily[dayKey(d)]?.solved ?? 0];
    final totalStudy = study.fold<int>(0, (a, b) => a + b);
    final totalSolved = solved.fold<int>(0, (a, b) => a + b);
    const wd = ['월', '화', '수', '목', '금', '토', '일'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('이번 주', style: _sectionTitle),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _WeekFigure(value: fmtDuration(totalStudy), label: '순공 시간'),
            const SizedBox(width: 28),
            _WeekFigure(value: '$totalSolved', label: '푼 문제'),
          ]),
          const SizedBox(height: 18),
          SizedBox(
            height: 160,
            child: CustomPaint(
              size: Size.infinite,
              painter: _WeekBars(study: study, solve: solve, labels: [for (final d in days) wd[d.weekday - 1]]),
            ),
          ),
          const SizedBox(height: 10),
          const Row(children: [
            _Legend(color: AppColors.ink, label: '순공 타이머'),
            SizedBox(width: 16),
            _Legend(color: AppColors.accent, label: '문제 풀이'),
          ]),
        ]),
      ),
    );
  }
}

class _WeekFigure extends StatelessWidget {
  const _WeekFigure({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, fontFeatures: AppColors.tabular)),
        const SizedBox(height: 2),
        Text(label, style: _meta),
      ]);
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
      ]);
}

/// 7일 막대: 흑연 = 순공 타이머, 파랑 = 문제 풀이. 오늘 요일은 형광펜 띠.
class _WeekBars extends CustomPainter {
  _WeekBars({required this.study, required this.solve, required this.labels});
  final List<int> study, solve;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 26.0;
    final h = size.height - labelH;
    final maxV = math.max(30 * 60000, [for (var i = 0; i < study.length; i++) study[i] + solve[i]].reduce(math.max));
    final slot = size.width / study.length;
    final bw = math.min(28.0, slot * 0.42);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    canvas.drawLine(Offset(0, h + 0.5), Offset(size.width, h + 0.5), Paint()..color = AppColors.line);
    for (var i = 0; i < study.length; i++) {
      final x = slot * i + (slot - bw) / 2;
      final hs = h * study[i] / maxV, hv = h * solve[i] / maxV;
      const r = Radius.circular(5);
      if (hs + hv == 0) {
        // 비어 있는 날: 바닥에 얇은 자리만
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, h - 3, bw, 3), r), Paint()..color = AppColors.paperDeep);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(x, h - hs - hv, bw, hv),
                topLeft: r,
                topRight: r,
                bottomLeft: hs == 0 ? r : Radius.zero,
                bottomRight: hs == 0 ? r : Radius.zero),
            Paint()..color = AppColors.accent);
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(x, h - hs, bw, hs),
                bottomLeft: r,
                bottomRight: r,
                topLeft: hv == 0 ? r : Radius.zero,
                topRight: hv == 0 ? r : Radius.zero),
            Paint()..color = AppColors.ink);
      }
      final today = i == study.length - 1;
      tp.text = TextSpan(
          text: labels[i],
          style: TextStyle(
              fontFamily: AppTheme.font,
              fontSize: 12.5,
              fontWeight: today ? FontWeight.w800 : FontWeight.w600,
              color: today ? AppColors.ink : AppColors.inkMuted));
      tp.layout();
      final lx = slot * i + (slot - tp.width) / 2, ly = h + 7;
      if (today) {
        // 형광펜으로 그은 것처럼: 글자 아래쪽에 노란 띠
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(lx - 6, ly + tp.height * 0.35, tp.width + 12, tp.height * 0.7),
                const Radius.circular(3)),
            Paint()..color = AppColors.highlight);
      }
      tp.paint(canvas, Offset(lx, ly));
    }
  }

  @override
  bool shouldRepaint(_WeekBars old) => true;
}
