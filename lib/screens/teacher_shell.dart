import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../services/account_api.dart';
import '../widgets/common.dart';
import '../widgets/problem_brief.dart';
import 'library_screen.dart' show CourseBrowser;
import 'questions_screen.dart';

/// 선생님 화면: 학생 · 질문함 · 문제 보기 · 설정.
class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _tab = 0;

  static const _tabs = [
    (Icons.groups_outlined, Icons.groups_rounded, '학생'),
    (Icons.forum_outlined, Icons.forum_rounded, '질문함'),
    (Icons.menu_book_outlined, Icons.menu_book_rounded, '문제 보기'),
    (Icons.settings_outlined, Icons.settings_rounded, '설정'),
  ];

  Widget _page() => switch (_tab) {
        0 => const TeacherStudentsScreen(),
        1 => const QuestionsScreen(),
        2 => const CourseBrowser(),
        _ => const TeacherSettingsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final open = app.openQuestions;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(_tab), child: _page()),
    );
    if (!wide) {
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            for (final (icon, active, label) in _tabs)
              NavigationDestination(icon: Icon(icon), selectedIcon: Icon(active), label: label),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(children: [
        Container(
          width: 96,
          color: AppColors.rail,
          child: SafeArea(
            right: false,
            child: Column(children: [
              const SizedBox(height: 18),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.correct, borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.co_present_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 6),
              const Text(kAppName, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
              const Text('선생님', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700, fontSize: 11.5)),
              const SizedBox(height: 18),
              for (var i = 0; i < _tabs.length; i++)
                _RailButton(
                  key: Key('t-tab-$i'),
                  icon: _tab == i ? _tabs[i].$2 : _tabs[i].$1,
                  label: _tabs[i].$3,
                  selected: _tab == i,
                  badge: i == 1 && open > 0 ? '$open' : null,
                  onTap: () => setState(() => _tab = i),
                ),
              const Spacer(),
              Tooltip(
                message: app.profile.name,
                child: CircleAvatar(
                  radius: 21,
                  backgroundColor: AppColors.correct,
                  child: Text(app.profile.initial,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                ),
              ),
              const SizedBox(height: 18),
            ]),
          ),
        ),
        Expanded(child: SafeArea(left: false, child: body)),
      ]),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton(
      {super.key, required this.icon, required this.label, required this.selected, required this.onTap, this.badge});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 80,
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 56,
                height: 34,
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: selected ? Colors.white : Colors.white60, size: 23),
              ),
              if (badge != null)
                Positioned(
                  right: 4,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
                    child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

String _ago(int? ms) {
  if (ms == null || ms == 0) return '아직 기록 없음';
  final d = DateTime.now().millisecondsSinceEpoch - ms;
  if (d < 60000) return '방금';
  if (d < 3600000) return '${d ~/ 60000}분 전';
  if (d < 86400000) return '${d ~/ 3600000}시간 전';
  if (d < 7 * 86400000) return '${d ~/ 86400000}일 전';
  return fmtDate(ms, withTime: false);
}

// ───────────────────────────────────────────────────────────── students

class TeacherStudentsScreen extends StatefulWidget {
  const TeacherStudentsScreen({super.key});

  @override
  State<TeacherStudentsScreen> createState() => _TeacherStudentsScreenState();
}

class _TeacherStudentsScreenState extends State<TeacherStudentsScreen> {
  String _code = '';
  List<StudentSummary>? _list;
  String? _error;
  String _q = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final api = AppScope.read(context).api;
    if (api == null) return;
    try {
      final (code, list) = await api.students();
      if (!mounted) return;
      setState(() {
        _code = code;
        _list = list;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _newCode() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('초대 코드를 새로 만들까요?'),
        content: const Text('예전 코드로는 더 이상 연결할 수 없어요. 이미 연결된 학생은 그대로예요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('새로 만들기')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final code = await AppScope.read(context).api!.newInviteCode();
      if (mounted) setState(() => _code = code);
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = _list;
    final shown = list == null
        ? <StudentSummary>[]
        : [for (final s in list) if (_q.isEmpty || s.name.contains(_q)) s];
    final today = list?.fold<int>(0, (n, s) => n + s.today.solved) ?? 0;
    final active = list?.where((s) => s.today.solved > 0).length ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${app.profile.name} 선생님의 학생',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                const SizedBox(height: 4),
                Text(
                  list == null ? '불러오는 중…' : '학생 ${list.length}명 · 오늘 공부한 학생 $active명 · 오늘 푼 문제 $today개',
                  style: const TextStyle(fontSize: 15, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: '학생 이름'),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(key: const Key('t-refresh'), tooltip: '새로고침', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 20),
          _InviteCard(code: _code, onNew: _newCode),
          const SizedBox(height: 22),
          if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_rounded, color: AppColors.wrong),
                title: Text(_error!),
                trailing: TextButton(onPressed: _load, child: const Text('다시 시도')),
              ),
            )
          else if (list == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (list.isEmpty)
            const EmptyState(
              icon: Icons.group_add_rounded,
              title: '아직 연결된 학생이 없어요',
              message: '학생에게 위의 초대 코드를 알려 주세요.\n학생 앱의 "질문" 탭이나 설정에서 코드를 입력하면 연결돼요.',
            )
          else
            LayoutBuilder(builder: (context, box) {
              final cols = box.maxWidth >= 1200 ? 3 : (box.maxWidth >= 760 ? 2 : 1);
              final w = (box.maxWidth - (cols - 1) * 14) / cols;
              return Wrap(spacing: 14, runSpacing: 14, children: [
                for (final s in shown)
                  SizedBox(
                    width: w,
                    child: _StudentCard(
                      student: s,
                      onTap: () async {
                        await TeacherStudentScreen.open(context, s.id, s.name);
                        _load();
                      },
                    ),
                  ),
              ]);
            }),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.code, required this.onNew});
  final String code;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF14523F), Color(0xFF1F7A5C)]),
      ),
      child: Row(children: [
        const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 30),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('학생 초대 코드', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            SelectableText(code.isEmpty ? '······' : code,
                key: const Key('t-invite-code'),
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 6)),
            const SizedBox(height: 4),
            Text('학생이 앱에서 이 코드를 입력하면 연결되고, 그 학생의 풀이 기록과 질문이 여기에 와요.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
          ]),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: code.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('초대 코드를 복사했어요')));
                },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('복사'),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onNew,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: const Text('새 코드'),
        ),
      ]),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, required this.onTap});
  final StudentSummary student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = student;
    final todayAcc = s.today.solved == 0 ? null : s.today.accuracy;
    return Card(
      key: Key('t-student-${s.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.blue,
                child: Text(s.name.isEmpty ? '?' : String.fromCharCode(s.name.runes.first),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('${s.grade.isEmpty ? '' : '${s.grade} · '}마지막 풀이 ${_ago(s.lastActiveAt)}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                ]),
              ),
              if (s.wrongOpen > 0) Pill('오답 ${s.wrongOpen}', color: AppColors.wrong),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _mini('오늘', '${s.today.solved}문제', todayAcc == null ? '-' : '정답률 ${pct(todayAcc)}'),
              _mini('이번 주', '${s.week.solved}문제', fmtDuration(s.week.timeMs)),
              _mini('전체', '${s.solved}문제', s.solved == 0 ? '-' : '정답률 ${pct(s.accuracy)}'),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _mini(String label, String value, String sub) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w700)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ───────────────────────────────────────────────────────────── one student

class TeacherStudentScreen extends StatefulWidget {
  const TeacherStudentScreen({super.key, required this.studentId, required this.name});
  final String studentId;
  final String name;

  static Future<void> open(BuildContext context, String id, String name) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => TeacherStudentScreen(studentId: id, name: name)));

  @override
  State<TeacherStudentScreen> createState() => _TeacherStudentScreenState();
}

class _TeacherStudentScreenState extends State<TeacherStudentScreen> {
  StudentDetail? _d;
  String? _error;
  bool _openOnly = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final d = await AppScope.read(context).api!.student(widget.studentId);
      if (mounted) setState(() => _d = d);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${widget.name} 학생과 연결을 끊을까요?'),
        content: const Text('더 이상 이 학생의 풀이 기록을 볼 수 없어요. 주고받은 질문은 남아요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.wrong),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('연결 끊기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.read(context).api!.removeStudent(widget.studentId);
      if (mounted) Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _showWrong(WrongItem w) {
    final app = AppScope.read(context);
    final p = app.problem(w.problemId) ?? app.problem(w.baseId);
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(w.topic.isEmpty ? w.unit : w.topic,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded)),
              ]),
              Text(
                '${fmtDate(w.wrongAt)}에 틀림 · ${w.tries}번 풀어서 ${w.correct}번 맞힘'
                '${w.open ? ' · 오답노트에 있음' : ' · 복습으로 해결'}',
                style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600),
              ),
              const Divider(height: 26),
              Expanded(
                child: SingleChildScrollView(
                  child: p == null
                      ? Text('이 기기에 없는 문제예요 (${w.problemId}). 문항을 받은 뒤 다시 열어 보세요.\n학생 답: ${w.answer} · 정답: ${w.expected}')
                      : ProblemBrief(problem: p, studentAnswer: w.answer, showSolution: true),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(tooltip: '새로고침', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          PopupMenuButton<int>(
            onSelected: (_) => _remove(),
            itemBuilder: (_) => const [PopupMenuItem(value: 0, child: Text('연결 끊기'))],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: d == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : DefaultTabController(
              length: 4,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 4, 28, 8),
                  child: _summary(app, d),
                ),
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(key: Key('t-tab-wrong'), text: '틀린 문제'),
                    Tab(key: Key('t-tab-recent'), text: '최근 풀이'),
                    Tab(key: Key('t-tab-subjects'), text: '과목 · 교재'),
                    Tab(key: Key('t-tab-questions'), text: '질문'),
                  ],
                ),
                Expanded(
                  child: TabBarView(children: [
                    _wrongTab(app, d),
                    _recentTab(app, d),
                    _subjectsTab(app, d),
                    ListView(
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
                      children: [QuestionsScreen(studentId: widget.studentId, embedded: true)],
                    ),
                  ]),
                ),
              ]),
            ),
    );
  }

  Widget _summary(AppState app, StudentDetail d) {
    final s = d.student;
    final maxDay = d.byDay.fold<int>(1, (m, x) => x.t.solved > m ? x.t.solved : m);
    final dday = d.examDate == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(d.examDate).difference(DateTime.now()).inDays + 1;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
        flex: 5,
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          _tile('오늘', '${s.today.solved}문제', s.today.solved == 0 ? '아직 안 풀었어요' : '정답 ${s.today.correct} · ${fmtDuration(s.today.timeMs)}'),
          _tile('이번 주', '${s.week.solved}문제', '정답률 ${s.week.solved == 0 ? '-' : pct(s.week.accuracy)}'),
          _tile('전체', '${s.solved}문제', '정답률 ${s.solved == 0 ? '-' : pct(s.accuracy)}'),
          _tile('오답노트', '${s.wrongOpen}문제', '아직 해결 못 한 문제', color: AppColors.wrong),
          _tile(
            '목표',
            d.goal.isEmpty ? '-' : d.goal,
            [if (d.grade.isNotEmpty) d.grade, if (dday != null) '${d.examName.isEmpty ? '시험' : d.examName} D-$dday'].join(' · '),
          ),
        ]),
      ),
      const SizedBox(width: 20),
      // 최근 14일 막대
      SizedBox(
        width: 300,
        height: 96,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('최근 14일', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
          const SizedBox(height: 6),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final x in d.byDay)
                Expanded(
                  child: Tooltip(
                    message: '${x.day.substring(5)} · ${x.t.solved}문제 (정답 ${x.t.correct})',
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 4 + 66 * x.t.solved / maxDay,
                      decoration: BoxDecoration(
                        color: x.t.solved == 0 ? AppColors.line : AppColors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _tile(String label, String value, String sub, {Color color = AppColors.ink}) => Container(
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.6)),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _wrongTab(AppState app, StudentDetail d) {
    final list = [for (final w in d.wrong) if (!_openOnly || w.open) w];
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
      children: [
        Row(children: [
          Text(_openOnly ? '오답노트에 남은 문제 ${list.length}개' : '한 번이라도 틀린 문제 ${list.length}개',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          FilterChip(
            key: const Key('t-wrong-open-only'),
            label: const Text('해결 못 한 것만'),
            selected: _openOnly,
            onSelected: (v) => setState(() => _openOnly = v),
          ),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const EmptyState(icon: Icons.verified_rounded, title: '틀린 문제가 없어요')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _wrongRow(app, list[i]),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _wrongRow(AppState app, WrongItem w) {
    final p = app.problem(w.problemId) ?? app.problem(w.baseId);
    final course = app.bank.subject(w.subjectId);
    return InkWell(
      key: Key('t-wrong-${w.baseId}'),
      onTap: () => _showWrong(w),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(children: [
          ResultMark(correct: w.lastCorrect, size: 26),
          const SizedBox(width: 12),
          SizedBox(
            width: 210,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.topic.isEmpty ? w.unit : w.topic,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${course?.name ?? w.subjectId} · ${w.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(p == null ? w.problemId : p.stem.replaceAll('\n', ' ').replaceAll(r'$', ''),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkSoft)),
          ),
          const SizedBox(width: 12),
          Text('학생 ${p != null && p.isChoice ? circled(int.tryParse(w.answer) ?? 0) : w.answer}',
              style: const TextStyle(color: AppColors.wrong, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Text('정답 ${w.expected}', style: const TextStyle(color: AppColors.correct, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text('${w.wrongs}번 틀림\n${_ago(w.wrongAt)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _recentTab(AppState app, StudentDetail d) {
    if (d.recent.isEmpty) return const EmptyState(icon: Icons.history_rounded, title: '아직 푼 문제가 없어요');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
      itemCount: d.recent.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final a = d.recent[i];
        final p = app.problem(a.problemId);
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: ResultMark(correct: a.correct, size: 28),
            title: Text(a.topic.isEmpty ? a.unit : a.topic, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${app.bank.subject(a.subjectId)?.name ?? a.subjectId} · ${fmtDate(a.at)} · ${fmtDuration(a.timeMs)}'
                '${a.isVariant ? ' · 변형' : ''}'),
            trailing: Text(
              a.correct ? '정답' : '학생 ${p != null && p.isChoice ? circled(int.tryParse(a.answer) ?? 0) : a.answer}',
              style: TextStyle(fontWeight: FontWeight.w800, color: a.correct ? AppColors.correct : AppColors.wrong),
            ),
            onTap: p == null
                ? null
                : () => _showWrong(WrongItem(
                      baseId: a.baseId,
                      problemId: a.problemId,
                      subjectId: a.subjectId,
                      unit: a.unit,
                      topic: a.topic,
                      answer: a.answer,
                      expected: a.expected,
                      wrongAt: a.at,
                      lastAt: a.at,
                      tries: 1,
                      correct: a.correct ? 1 : 0,
                      wrongs: a.correct ? 0 : 1,
                      lastCorrect: a.correct,
                      open: !a.correct,
                    )),
          ),
        );
      },
    );
  }

  Widget _subjectsTab(AppState app, StudentDetail d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
      children: [
        const SectionHeader('과목별'),
        if (d.bySubject.isEmpty)
          const Text('아직 기록이 없어요', style: TextStyle(color: AppColors.inkMuted))
        else
          Card(
            child: Column(children: [
              for (final e in d.bySubject.entries)
                ListTile(
                  title: Text(app.bank.subject(e.key)?.name ?? e.key, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: AccuracyBar(value: e.value.accuracy, color: accuracyColor(e.value.accuracy)),
                  ),
                  trailing: Text('${e.value.solved}문제 · ${pct(e.value.accuracy)}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        const SizedBox(height: 24),
        const SectionHeader('학생의 내 교재'),
        if (d.workbooks.isEmpty)
          const Text('아직 담은 문제집이 없어요', style: TextStyle(color: AppColors.inkMuted))
        else
          Card(
            child: Column(children: [
              for (final id in d.workbooks)
                ListTile(
                  leading: const Icon(Icons.menu_book_rounded),
                  title: Text(app.bank.workbook(id)?.title ?? id, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    if (app.bank.workbook(id) case final w?) ...[w.stage, '${w.problemIds.length}문항'],
                  ].join(' · ')),
                ),
            ]),
          ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────── settings

class TeacherSettingsScreen extends StatelessWidget {
  const TeacherSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = app.account;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        const Text('설정', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
        const SizedBox(height: 20),
        const AccountCard(),
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('서버'),
              subtitle: Text(a?.server ?? '-'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('문항 받기'),
              subtitle: Text(app.syncMessage.isEmpty ? '서버에 올린 새 문항과 문제집을 받아요' : app.syncMessage),
              trailing: app.syncing ? const CircularProgressIndicator() : null,
              onTap: app.syncing
                  ? null
                  : () {
                      if (app.settings.serverUrl.trim().isEmpty && a != null) {
                        app.updateSettings((s) => s.serverUrl = a.server);
                      }
                      app.syncContent();
                    },
            ),
          ]),
        ),
      ],
    );
  }
}

/// 로그인 정보 · 비밀번호 바꾸기 · 로그아웃 (학생·선생님 설정 공통).
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  Future<void> _password(BuildContext context) async {
    final cur = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('비밀번호 바꾸기'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: '지금 비밀번호')),
            const SizedBox(height: 10),
            TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: '새 비밀번호 (6자 이상)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('바꾸기')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await AppScope.read(context).api!.changePassword(cur.text, next.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('비밀번호를 바꿨어요. 다른 기기는 다시 로그인해야 해요.')));
      }
    } on ApiError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('로그아웃할까요?'),
        content: const Text('이 기기의 기록은 서버에 저장한 뒤 로그아웃해요. 다시 로그인하면 이어서 쓸 수 있어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('로그아웃')),
        ],
      ),
    );
    if (ok == true && context.mounted) await AppScope.read(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = app.account;
    if (a == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.person_off_outlined),
          title: const Text('로그인하지 않고 쓰는 중', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('기록이 이 기기에만 저장돼요. 로그인하면 선생님과 연결하고 다른 기기에서도 이어서 풀 수 있어요.'),
          trailing: FilledButton(
            key: const Key('settings-login'),
            onPressed: app.showWelcome,
            child: const Text('로그인 · 회원가입'),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: a.isTeacher ? AppColors.correct : AppColors.blue,
              child: Icon(a.isTeacher ? Icons.co_present_rounded : Icons.school_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a.name} (${a.roleLabel})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('아이디 ${a.loginId}', style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
              ]),
            ),
            TextButton(onPressed: () => _password(context), child: const Text('비밀번호 바꾸기')),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              key: const Key('logout'),
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('로그아웃'),
            ),
          ]),
          if (!a.isTeacher) ...[
            const Divider(height: 28),
            Row(children: [
              const Icon(Icons.cloud_done_outlined, size: 18, color: AppColors.inkMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  app.unsyncedCount == 0
                      ? '풀이 기록이 서버에 저장돼 있어요${app.lastRecordsSync.isEmpty ? '' : ' (${app.lastRecordsSync})'}'
                      : '아직 서버에 안 올라간 풀이 ${app.unsyncedCount}개${app.lastRecordsSync.isEmpty ? '' : ' · ${app.lastRecordsSync}'}',
                  style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(onPressed: app.syncRecords, child: const Text('지금 저장')),
            ]),
            const SizedBox(height: 8),
            const Text('내 선생님', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
            const SizedBox(height: 6),
            if (app.myTeachers.isEmpty)
              const Text('아직 연결된 선생님이 없어요', style: TextStyle(color: AppColors.inkMuted))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in app.myTeachers)
                  InputChip(
                    avatar: const Icon(Icons.co_present_rounded, size: 18),
                    label: Text(t.name),
                    onDeleted: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text('${t.name}과(와) 연결을 끊을까요?'),
                          content: const Text('선생님이 더 이상 내 풀이 기록을 볼 수 없어요.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
                            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('끊기')),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        try {
                          await AppScope.read(context).leaveTeacher(t.id);
                        } on ApiError catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
                  ),
              ]),
            const SizedBox(height: 12),
            const LinkTeacherCard(),
          ],
        ]),
      ),
    );
  }
}
