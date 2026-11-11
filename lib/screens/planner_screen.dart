import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../widgets/common.dart';
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
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 18),
      child: Wrap(
        spacing: 20,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          const Text('학습관리', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
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
      Widget pair(Widget a, Widget b, {int fa = 1, int fb = 1}) => wide
          ? IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: fa, child: a),
                const SizedBox(width: 18),
                Expanded(flex: fb, child: b),
              ]),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 16), b]);
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 4, 32, 40),
        children: [
          pair(_ddayCard(app), _timerCard(app), fa: 2, fb: 3),
          const SizedBox(height: 18),
          pair(_todoCard(app), _weekCard(app), fa: 1, fb: 1),
        ],
      );
    });
  }

  // ---------------------------------------------------------------- D-day
  Widget _ddayCard(AppState app) {
    final l = app.learner;
    final d = app.dDay;
    final date = l.examDate == 0 ? null : DateTime.fromMillisecondsSinceEpoch(l.examDate);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _editDday(app),
      child: Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF2B3F6B)]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(date == null ? '다음 시험' : l.examName,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            key: const Key('dday-edit'),
            tooltip: '시험 바꾸기',
            onPressed: () => _editDday(app),
            icon: const Icon(Icons.edit_calendar_rounded, color: Colors.white),
          ),
        ]),
        Text(date == null ? '시험 일정 정하기' : (d > 0 ? 'D-$d' : (d == 0 ? 'D-DAY' : 'D+${-d}')),
            style: TextStyle(
                color: Colors.white, fontSize: date == null ? 30 : 52, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
        if (date == null)
          Text('중간·기말고사, 인적성, 편입시험 날짜를 넣으면 남은 날을 세어 드려요',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
        if (date != null)
          Text('${date.year}년 ${date.month}월 ${date.day}일',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        if (date != null && d > 0)
          Text(
            '하루 ${math.max(1, (app.wrongNote.length / math.max(1, d)).ceil())}개씩 오답을 정리하면 시험 전에 끝나요',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
          ),
      ]),
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
            Wrap(spacing: 8, children: [
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
  Widget _timerCard(AppState app) {
    final on = app.studying;
    final today = app.todayStudyMs;
    final solve = app.solveMsOn(dayKey(DateTime.now()));
    final running = on ? DateTime.now().millisecondsSinceEpoch - (app.studyStartedAt ?? 0) : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                Icon(Icons.timer_rounded, color: on ? AppColors.accent : AppColors.inkSoft),
                const SizedBox(width: 8),
                Text(on ? '지금 공부 중 · ${fmtStudy(running)}' : '오늘 순공 시간',
                    style: TextStyle(fontWeight: FontWeight.w800, color: on ? AppColors.accent : AppColors.inkSoft)),
              ]),
              const SizedBox(height: 8),
              Text(fmtStudy(today), style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800, letterSpacing: -2)),
              Text('타이머 ${fmtDuration(today)} · 앱에서 문제 푼 시간 ${fmtDuration(solve)}',
                  style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            ]),
          ),
          SizedBox(
            width: 120,
            height: 120,
            child: FilledButton(
              key: const Key('planner-study-toggle'),
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: on ? AppColors.wrong : AppColors.accent,
              ),
              onPressed: on ? app.stopStudy : app.startStudy,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 40),
                Text(on ? '멈추기' : '시작', style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- todos
  Widget _todoCard(AppState app) {
    final todos = app.todayTodos;
    final set = app.dailySet;
    void add() {
      app.addTodo(_todo.text);
      _todo.clear();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('오늘 할 일', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
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
            IconButton.filled(key: const Key('todo-add'), onPressed: add, icon: const Icon(Icons.add_rounded)),
          ]),
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(set.complete ? Icons.check_circle_rounded : Icons.auto_awesome_rounded,
                color: set.complete ? AppColors.correct : AppColors.accent),
            title: const Text('오늘의 오답 변형 세트', style: TextStyle(fontWeight: FontWeight.w700)),
            trailing: Text('${set.doneCount}/${set.problemIds.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          for (final t in todos)
            Dismissible(
              key: ValueKey(t.id),
              onDismissed: (_) => app.removeTodo(t.id),
              background: Container(color: AppColors.wrongSoft),
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: t.done,
                onChanged: (_) => app.toggleTodo(t.id),
                title: Text(t.text,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: t.done ? TextDecoration.lineThrough : null,
                        color: t.done ? AppColors.inkMuted : AppColors.ink)),
                secondary: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.inkMuted),
                  onPressed: () => app.removeTodo(t.id),
                ),
              ),
            ),
          if (todos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('끝내지 못한 할 일은 다음 날로 넘어가요', style: TextStyle(color: AppColors.inkMuted)),
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('이번 주', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('순공 ${fmtDuration(totalStudy)} · $totalSolved문제',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            child: CustomPaint(
              size: Size.infinite,
              painter: _WeekBars(study: study, solve: solve, labels: [for (final d in days) wd[d.weekday - 1]]),
            ),
          ),
          const SizedBox(height: 8),
          const Row(children: [
            _Legend(color: AppColors.ink, label: '순공 타이머'),
            SizedBox(width: 14),
            _Legend(color: AppColors.accent, label: '문제 풀이'),
          ]),
        ]),
      ),
    );
  }
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

class _WeekBars extends CustomPainter {
  _WeekBars({required this.study, required this.solve, required this.labels});
  final List<int> study, solve;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 22.0;
    final h = size.height - labelH;
    final maxV = math.max(30 * 60000, [for (var i = 0; i < study.length; i++) study[i] + solve[i]].reduce(math.max));
    final slot = size.width / study.length;
    final bw = math.min(34.0, slot * 0.5);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < study.length; i++) {
      final x = slot * i + (slot - bw) / 2;
      final hs = h * study[i] / maxV, hv = h * solve[i] / maxV;
      final r = const Radius.circular(6);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, bw, h), r), Paint()..color = const Color(0xFFF1EDE6));
      if (hs + hv > 0) {
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(x, h - hs - hv, bw, hv), topLeft: r, topRight: r,
                bottomLeft: hs == 0 ? r : Radius.zero, bottomRight: hs == 0 ? r : Radius.zero),
            Paint()..color = AppColors.accent);
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(x, h - hs, bw, hs),
                bottomLeft: r, bottomRight: r, topLeft: hv == 0 ? r : Radius.zero, topRight: hv == 0 ? r : Radius.zero),
            Paint()..color = AppColors.ink);
      }
      tp.text = TextSpan(
          text: labels[i],
          style: TextStyle(
              fontFamily: AppTheme.font,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: i == study.length - 1 ? AppColors.ink : AppColors.inkMuted));
      tp.layout();
      tp.paint(canvas, Offset(slot * i + (slot - tp.width) / 2, h + 5));
    }
  }

  @override
  bool shouldRepaint(_WeekBars old) => true;
}
