import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../app/learner.dart';
import '../app/theme.dart';
import '../widgets/common.dart';
import 'community_screen.dart' show RankingPanel;
import 'dashboard_screen.dart' show fmtStudy;

/// 학습관리: D-day · 순공 타이머 · 오늘 할 일 · 이번 주 · 모의고사 성적 · 주간 리포트.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  Timer? _tick;
  final _todo = TextEditingController();

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
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          const Text('학습관리', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
          const SizedBox(height: 4),
          const Text('시험까지 남은 날, 공부 시간, 할 일과 성적을 한곳에서 관리해요',
              style: TextStyle(fontSize: 15.5, color: AppColors.inkSoft)),
          const SizedBox(height: 22),
          pair(_ddayCard(app), _timerCard(app), fa: 2, fb: 3),
          const SizedBox(height: 18),
          pair(_todoCard(app), _weekCard(app), fa: 1, fb: 1),
          const SizedBox(height: 18),
          _scoresCard(app, wide),
          const SizedBox(height: 18),
          _reportCard(app),
          if (app.community != null) ...[
            const SizedBox(height: 18),
            const RankingPanel(compact: true),
          ],
        ],
      );
    });
  }

  // ---------------------------------------------------------------- D-day
  Widget _ddayCard(AppState app) {
    final l = app.learner;
    final d = app.dDay;
    final date = l.examDate == 0 ? null : DateTime.fromMillisecondsSinceEpoch(l.examDate);
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [Color(0xFF1B2A4A), Color(0xFF2B3F6B)]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(l.examName, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            key: const Key('dday-edit'),
            tooltip: '시험 바꾸기',
            onPressed: () => _editDday(app),
            icon: const Icon(Icons.edit_calendar_rounded, color: Colors.white),
          ),
        ]),
        Text(date == null ? '시험을 정해요' : (d > 0 ? 'D-$d' : (d == 0 ? 'D-DAY' : 'D+${-d}')),
            style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: -2)),
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
    );
  }

  Future<void> _editDday(AppState app) async {
    final name = TextEditingController(text: app.learner.examName);
    var date = app.learner.examDate == 0
        ? defaultSuneungDate(DateTime.now())
        : DateTime.fromMillisecondsSinceEpoch(app.learner.examDate);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('목표 시험'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '시험 이름 (예: 수능, 2학기 중간고사)')),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              for (final n in ['수능', '6월 모의평가', '9월 모의평가', '중간고사', '기말고사'])
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
                decoration: const InputDecoration(hintText: '예) 수학Ⅰ 지수함수 20문제, 영어 단어 50개', isDense: true),
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

  // ---------------------------------------------------------------- scores
  Widget _scoresCard(AppState app, bool wide) {
    final list = app.scoresByDate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('모의고사 성적', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            const Text('등급 추이를 기록해요', style: TextStyle(color: AppColors.inkMuted)),
            const Spacer(),
            FilledButton.icon(
              key: const Key('score-add'),
              onPressed: () => _editScore(app, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('성적 입력'),
            ),
          ]),
          const SizedBox(height: 14),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('모의고사를 보면 과목별 등급을 입력해 보세요. 추이 그래프로 보여 드려요.',
                  style: TextStyle(color: AppColors.inkMuted)),
            )
          else ...[
            SizedBox(height: 220, child: CustomPaint(size: Size.infinite, painter: _GradeChart(list))),
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 6, children: [
              for (final (i, s) in _subjectsIn(list).indexed) _Legend(color: _chartColors[i % _chartColors.length], label: s),
            ]),
            const SizedBox(height: 12),
            for (final s in list.reversed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  [for (final e in s.grades.entries) '${e.key} ${e.value}등급${s.raw[e.key] != null ? '(${s.raw[e.key]})' : ''}']
                      .join('  ·  '),
                ),
                leading: CircleAvatar(
                  backgroundColor: AppColors.paperDeep,
                  child: Text(s.average == null ? '-' : s.average!.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink)),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(fmtDate(s.date, withTime: false), style: const TextStyle(color: AppColors.inkMuted)),
                  IconButton(onPressed: () => _editScore(app, s), icon: const Icon(Icons.edit_rounded, size: 19)),
                  IconButton(onPressed: () => app.removeScore(s.id), icon: const Icon(Icons.delete_outline_rounded, size: 19)),
                ]),
              ),
          ],
        ]),
      ),
    );
  }

  Future<void> _editScore(AppState app, ExamScore? old) async {
    final name = TextEditingController(text: old?.name ?? '');
    final grades = <String, int>{...?old?.grades};
    final raw = {for (final s in kScoreSubjects) s: TextEditingController(text: old?.raw[s]?.toString() ?? '')};
    var date = old == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(old.date);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(old == null ? '모의고사 성적 입력' : '성적 고치기'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  key: const Key('score-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: '시험 이름 (예: 9월 모의평가)'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final p = await showDatePicker(
                        context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (p != null) set(() => date = p);
                  },
                  icon: const Icon(Icons.event_rounded),
                  label: Text('${date.year}.${date.month}.${date.day}'),
                ),
                const SizedBox(height: 6),
                for (final s in kScoreSubjects)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      SizedBox(width: 64, child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            for (var g = 1; g <= 9; g++)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: ChoiceChip(
                                  key: Key('score-$s-$g'),
                                  label: Text('$g'),
                                  selected: grades[s] == g,
                                  onSelected: (v) => set(() => v ? grades[s] = g : grades.remove(s)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ]),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: raw[s],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '점수', isDense: true),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(key: const Key('score-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
          ],
        ),
      ),
    );
    if (ok == true && grades.isNotEmpty) {
      app.saveScore(ExamScore(
        id: old?.id ?? app.newId(),
        name: name.text.trim().isEmpty ? '모의고사' : name.text.trim(),
        date: DateTime(date.year, date.month, date.day).millisecondsSinceEpoch,
        grades: grades,
        raw: {
          for (final e in raw.entries)
            if (int.tryParse(e.value.text.trim()) case final v?) e.key: v
        },
      ));
    }
  }

  // ---------------------------------------------------------------- report
  String _report(AppState app) {
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day).subtract(Duration(days: i))];
    var solved = 0, correct = 0, study = 0;
    for (final d in days) {
      final t = app.daily[dayKey(d)];
      solved += t?.solved ?? 0;
      correct += t?.correct ?? 0;
      study += app.studyMsOn(dayKey(d));
    }
    final weak = app.weakTopics.take(3).map((e) => e.$1).join(', ');
    final b = StringBuffer()
      ..writeln('[풀이노트 주간 리포트] ${app.profile.name} (${app.learner.grade})')
      ..writeln('· 기간: ${days.first.month}/${days.first.day} ~ ${days.last.month}/${days.last.day}')
      ..writeln('· 순공 시간: ${fmtDuration(study)}')
      ..writeln('· 푼 문제: $solved문제 (정답률 ${solved == 0 ? '-' : pct(correct / solved)})')
      ..writeln('· 연속 학습: ${app.streak}일')
      ..writeln('· 오답노트: ${app.wrongNote.length}문제 (해결 ${app.resolvedWrong.length})');
    if (weak.isNotEmpty) b.writeln('· 보완할 유형: $weak');
    if (app.learner.examDate > 0) b.writeln('· ${app.learner.examName} D-${app.dDay}');
    return b.toString().trim();
  }

  Widget _reportCard(AppState app) {
    final text = _report(app);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('주간 리포트', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            const Text('학부모님께 그대로 보내도 돼요', style: TextStyle(color: AppColors.inkMuted)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('리포트를 복사했어요. 메신저에 붙여 넣으세요.')));
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('복사하기'),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
            child: Text(text, style: const TextStyle(height: 1.7, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

const _chartColors = [
  Color(0xFFD9534F),
  Color(0xFFE0703B),
  Color(0xFF2F9E6E),
  Color(0xFF8C5BD6),
  Color(0xFF2F6BFF),
  Color(0xFF0EA5E9),
];

List<String> _subjectsIn(List<ExamScore> list) {
  final out = <String>[];
  for (final s in kScoreSubjects) {
    if (list.any((e) => e.grades.containsKey(s))) out.add(s);
  }
  return out;
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

/// 등급 line chart: 1등급 at the top.
class _GradeChart extends CustomPainter {
  _GradeChart(this.list);
  final List<ExamScore> list;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 26.0, top = 8.0;
    final w = size.width - left - 10, h = size.height - bottom - top;
    final grid = Paint()
      ..color = const Color(0xFFE6E0D5)
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    double y(num g) => top + h * (g - 1) / 8;
    for (var g = 1; g <= 9; g++) {
      canvas.drawLine(Offset(left, y(g)), Offset(left + w, y(g)), grid);
      tp.text = TextSpan(text: '$g', style: const TextStyle(fontFamily: AppTheme.font, fontSize: 11.5, color: AppColors.inkMuted, fontWeight: FontWeight.w700));
      tp.layout();
      tp.paint(canvas, Offset(left - 10 - tp.width, y(g) - tp.height / 2));
    }
    final n = list.length;
    double x(int i) => n == 1 ? left + w / 2 : left + w * i / (n - 1);
    for (var i = 0; i < n; i++) {
      tp.text = TextSpan(
          text: list[i].name.length > 8 ? list[i].name.substring(0, 8) : list[i].name,
          style: const TextStyle(fontFamily: AppTheme.font, fontSize: 11.5, color: AppColors.inkSoft, fontWeight: FontWeight.w700));
      tp.layout();
      tp.paint(canvas, Offset((x(i) - tp.width / 2).clamp(0, size.width - tp.width), size.height - bottom + 6));
    }
    final subjects = _subjectsIn(list);
    for (final (k, s) in subjects.indexed) {
      final c = _chartColors[k % _chartColors.length];
      final line = Paint()
        ..color = c
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final g = list[i].grades[s];
        if (g == null) continue;
        final p = Offset(x(i), y(g));
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawCircle(p, 5, Paint()..color = c);
      }
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_GradeChart old) => true;
}
